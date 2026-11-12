"""Konverterer NLLB-200 (facebook/nllb-200-distilled-600M) til Core ML for Oversetter-appen.

Lager tre filer i Oversetter/Models/:
  NLLBEncoder.mlpackage   leser kildesetningen
  NLLBDecoder.mlpackage   gjetter neste token i oversettelsen
  tokenizer.json          NLLB sin SentencePiece-tokenizer

Begge modellene bruker fast lengde (128 tokens), som passer Neural Engine best,
og vektene komprimeres til 8 bit (ca. 1 GB totalt i stedet for 2,5 GB).

Samme oppdeling i encoder og decoder som Core ML-versjonene på Hugging Face
(f.eks. aoiandroid/nllb200-coreml-1024), men med kjente navn på inn- og utdata
som Swift-koden i appen bruker direkte.

Kjør med:  scripts/convert_nllb.sh   (setter opp Python-miljø først)
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import numpy as np
import torch
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

MODEL_ID = "facebook/nllb-200-distilled-600M"
MAX_TOKENS = 128  # må stemme med NLLBTranslator.maxTokens i Swift


class Encoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.get_encoder()

    def forward(self, input_ids, attention_mask):
        return self.encoder(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state


class Decoder(torch.nn.Module):
    """Kjører decoderen på hele den hittil genererte sekvensen og returnerer
    sannsynlighetene (logits) kun for posisjonen `position`."""

    def __init__(self, model):
        super().__init__()
        self.decoder = model.get_decoder()
        self.lm_head = model.lm_head

    def forward(self, decoder_input_ids, encoder_hidden_states, encoder_attention_mask, position):
        hidden = self.decoder(
            input_ids=decoder_input_ids,
            encoder_hidden_states=encoder_hidden_states,
            encoder_attention_mask=encoder_attention_mask,
            use_cache=False,
        ).last_hidden_state
        last = torch.index_select(hidden, 1, position)  # [1, 1, d_model]
        return self.lm_head(last)  # [1, 1, vocab]


def quantize(mlmodel, bits: int):
    import coremltools.optimize as cto

    if bits >= 16:
        return mlmodel
    config = cto.coreml.OptimizationConfig(
        global_config=cto.coreml.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")
    )
    return cto.coreml.linear_quantize_weights(mlmodel, config)


def pad(ids: list[int], value: int) -> list[int]:
    return ids + [value] * (MAX_TOKENS - len(ids))


def main():
    import coremltools as ct

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "Oversetter" / "Models"))
    parser.add_argument("--bits", type=int, default=8, choices=[8, 16], help="8 = komprimert (anbefalt), 16 = full float16")
    parser.add_argument("--skip-test", action="store_true")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"Laster {MODEL_ID} fra Hugging Face …")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_ID, attn_implementation="eager", torch_dtype=torch.float32)
    model.eval()
    pad_id = tokenizer.pad_token_id
    eos_id = tokenizer.eos_token_id
    d_model = model.config.d_model

    # Eksempeldata for sporing (tracing)
    tokenizer.src_lang = "nob_Latn"
    sample = tokenizer("Hei, hvordan har du det?")["input_ids"]
    input_ids = torch.tensor([pad(sample, pad_id)], dtype=torch.long)
    attention_mask = torch.tensor([pad([1] * len(sample), 0)], dtype=torch.long)
    decoder_ids = torch.tensor([pad([eos_id, tokenizer.convert_tokens_to_ids("ben_Beng")], pad_id)], dtype=torch.long)
    position = torch.tensor([1], dtype=torch.long)

    with torch.no_grad():
        encoder = Encoder(model).eval()
        decoder = Decoder(model).eval()
        hidden = encoder(input_ids, attention_mask)
        print("Sporer encoder …")
        traced_encoder = torch.jit.trace(encoder, (input_ids, attention_mask))
        print("Sporer decoder …")
        traced_decoder = torch.jit.trace(decoder, (decoder_ids, hidden, attention_mask, position))

    precision = ct.precision.FLOAT16
    target = ct.target.iOS17

    print("Konverterer encoder til Core ML …")
    ml_encoder = ct.convert(
        traced_encoder,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_TOKENS), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_TOKENS), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="encoder_hidden_states", dtype=np.float32)],
        compute_precision=precision,
        minimum_deployment_target=target,
        convert_to="mlprogram",
    )

    print("Konverterer decoder til Core ML …")
    ml_decoder = ct.convert(
        traced_decoder,
        inputs=[
            ct.TensorType(name="decoder_input_ids", shape=(1, MAX_TOKENS), dtype=np.int32),
            ct.TensorType(name="encoder_hidden_states", shape=(1, MAX_TOKENS, d_model), dtype=np.float32),
            ct.TensorType(name="encoder_attention_mask", shape=(1, MAX_TOKENS), dtype=np.int32),
            ct.TensorType(name="position", shape=(1,), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="logits", dtype=np.float32)],
        compute_precision=precision,
        minimum_deployment_target=target,
        convert_to="mlprogram",
    )

    print(f"Komprimerer vekter til {args.bits} bit …")
    ml_encoder = quantize(ml_encoder, args.bits)
    ml_decoder = quantize(ml_decoder, args.bits)

    for name, ml in [("NLLBEncoder", ml_encoder), ("NLLBDecoder", ml_decoder)]:
        ml.short_description = f"{name} for {MODEL_ID} (CC-BY-NC-4.0, kun ikke-kommersiell bruk)"
        path = out / f"{name}.mlpackage"
        if path.exists():
            shutil.rmtree(path)
        ml.save(str(path))
        print(f"Lagret {path}")

    tokenizer_dir = out / "_tokenizer_tmp"
    tokenizer.save_pretrained(tokenizer_dir)
    shutil.copy(tokenizer_dir / "tokenizer.json", out / "tokenizer.json")
    shutil.rmtree(tokenizer_dir)
    print(f"Lagret {out / 'tokenizer.json'}")

    if not args.skip_test:
        test(ml_encoder, ml_decoder, tokenizer)

    print("\nFerdig! Åpne Oversetter.xcodeproj i Xcode og trykk Kjør.")


def test(ml_encoder, ml_decoder, tokenizer):
    """Kjører en testoversettelse med Core ML-modellene på Macen (samme algoritme som Swift-appen)."""
    import platform

    if platform.system() != "Darwin":
        print("Hopper over test (Core ML kan bare kjøres på macOS).")
        return

    def translate(text, src, tgt):
        tokenizer.src_lang = src
        ids = tokenizer(text)["input_ids"][: MAX_TOKENS]
        input_ids = np.array([pad(ids, tokenizer.pad_token_id)], dtype=np.int32)
        mask = np.array([pad([1] * len(ids), 0)], dtype=np.int32)
        hidden = ml_encoder.predict({"input_ids": input_ids, "attention_mask": mask})["encoder_hidden_states"]
        out = [tokenizer.eos_token_id, tokenizer.convert_tokens_to_ids(tgt)]
        while len(out) < min(MAX_TOKENS, len(ids) * 2 + 16):
            logits = ml_decoder.predict({
                "decoder_input_ids": np.array([pad(out, tokenizer.pad_token_id)], dtype=np.int32),
                "encoder_hidden_states": hidden,
                "encoder_attention_mask": mask,
                "position": np.array([len(out) - 1], dtype=np.int32),
            })["logits"].reshape(-1)
            logits[[tokenizer.pad_token_id, tokenizer.bos_token_id, tokenizer.unk_token_id]] = -np.inf
            nxt = int(np.argmax(logits))
            if nxt == tokenizer.eos_token_id:
                break
            out.append(nxt)
        return tokenizer.decode(out[2:], skip_special_tokens=True)

    print("\nTest med Core ML:")
    for text, src, tgt in [
        ("Hei, hvordan har du det?", "nob_Latn", "ben_Beng"),
        ("Jeg liker å lese bøker om kvelden.", "nob_Latn", "ben_Beng"),
        ("আমি তোমাকে ভালোবাসি।", "ben_Beng", "nob_Latn"),
        ("Hvor ligger togstasjonen?", "nob_Latn", "hin_Deva"),
    ]:
        print(f"  {src} → {tgt}: {text}  =>  {translate(text, src, tgt)}")


if __name__ == "__main__":
    main()
