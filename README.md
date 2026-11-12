# Oversetter

En iPhone-app som oversetter mellom **norsk og bengali** (og hindi, urdu, farsi, dansk, svensk, tysk, engelsk) – **helt lokalt på telefonen**, uten internett etter første oppsett.

| Del | Hva | Kjører på |
|---|---|---|
| Tale → tekst | [Whisper](https://github.com/openai/whisper) via [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Neural Engine |
| Tekst → tekst | [NLLB-200 distilled 600M](https://huggingface.co/facebook/nllb-200-distilled-600M) konvertert til Core ML | Neural Engine |
| Tekst → tale | Apples innebygde talesyntese | – |
| Siri | App Intents («Hei Siri, oversett med Oversetter») | – |

Oppbyggingen følger [RTranslator](https://github.com/niedev/RTranslator) (Whisper + NLLB på Android), men er skrevet i Swift og bruker Core ML. Oppdelingen av NLLB i encoder og decoder er den samme som i Core ML-versjonene på Hugging Face, f.eks. [aoiandroid/nllb200-coreml-1024](https://huggingface.co/aoiandroid/nllb200-coreml-1024).

> **Lisens:** NLLB-200 er lisensiert CC-BY-NC-4.0 – kun til ikke-kommersiell bruk. Appen er ment for eget bruk og skal ikke selges eller legges ut i App Store.

---

## Det du trenger

- En Mac med Apple Silicon (M1 eller nyere) og **Xcode 16** eller nyere
- En iPhone med iOS 17 eller nyere (iPhone 13 Pro / 14 eller nyere anbefales, helst 15 Pro for tale)
- En gratis Apple-ID
- Ca. 10 GB ledig plass på Macen under konverteringen

## Steg 1: Hent prosjektet

Åpne **Terminal** på Macen og skriv:

```bash
cd ~/Documents
git clone https://github.com/tobatuk/oversetter.git
cd oversetter
```

## Steg 2: Lag oversettelsesmodellen (én gang)

NLLB-modellen er for stor for GitHub, så den lages på Macen din:

```bash
./scripts/convert_nllb.sh
```

Dette laster ned NLLB fra Hugging Face, konverterer den til Core ML og komprimerer den til 8 bit. Det tar 10–20 minutter. Når det er ferdig, skriver skriptet ut noen testoversettelser, og du har tre nye filer i `Oversetter/Models/`:

- `NLLBEncoder.mlpackage`
- `NLLBDecoder.mlpackage`
- `tokenizer.json`

Får du feil om Python, kjør `xcode-select --install` først.

## Steg 3: Kjør appen på iPhonen

1. Dobbeltklikk `Oversetter.xcodeproj` for å åpne i Xcode. Xcode henter WhisperKit automatisk første gang (vent til «Resolving packages» er ferdig).
2. Gå til **Xcode → Settings → Accounts** og legg til Apple-ID-en din.
3. Klikk på **Oversetter** øverst i fillisten → fanen **Signing & Capabilities** → velg deg selv under **Team**. Gir Xcode feil om bundle-ID, endre `no.tobatuk.Oversetter` til noe unikt, f.eks. `no.dittnavn.Oversetter`.
4. Koble iPhonen til Macen med kabel og velg den øverst i Xcode-vinduet.
5. På iPhonen: **Innstillinger → Personvern og sikkerhet → Utviklermodus** → slå på (telefonen starter på nytt).
6. Trykk **▶ (Kjør)** i Xcode.
7. Første gang: på iPhonen, gå til **Innstillinger → Generelt → VPN og enhetsadministrasjon** og stol på utviklersertifikatet ditt.

Velg **Release** for raskest app: **Product → Scheme → Edit Scheme → Run → Build Configuration → Release**.

> Med gratis Apple-ID slutter appen å virke etter 7 dager. Koble til Macen og trykk Kjør igjen for å fornye.

## Bruk

- **Skriv** tekst og trykk **Oversett**, eller
- trykk **Snakk**, si setningen, og trykk **Stopp**. Første gang lastes Whisper ned (ca. 250 MB), deretter fungerer det uten nett.
- Pila i midten bytter språkretning.
- Høyttalerknappen øverst slår automatisk opplesning av og på.

**Stemme for bengali:** Gå til **Innstillinger → Tilgjengelighet → Opplest innhold → Stemmer** og last ned en bengali-stemme. Uten den kan appen vise teksten, men ikke lese den opp.

### Siri og Snarveier

Appen registrerer to snarveier automatisk:

- **«Hei Siri, oversett med Oversetter»** – Siri spør hva du vil oversette og svarer med oversettelsen.
- **«Hei Siri, snakk bengali med Oversetter»** – åpner appen og begynner å lytte med en gang.

Begge finnes også i **Snarveier**-appen, der du kan endre språk eller bygge egne kjeder (f.eks. Dikter tekst → Oversett tekst → Les opp tekst).

## Slik fungerer det

```
 mikrofon ──► WhisperKit ──► tekst ──► NLLBTokenizer ──► NLLBEncoder ─┐
                                                                       ▼
 høyttaler ◄── AVSpeechSynthesizer ◄── tekst ◄── NLLBDecoder (ett token om gangen)
```

| Fil | Innhold |
|---|---|
| `Oversetter/NLLBTokenizer.swift` | Deler tekst i tokens (SentencePiece Unigram, skrevet i ren Swift) |
| `Oversetter/NLLBTranslator.swift` | Kjører encoder én gang og decoder i en løkke til setningen er ferdig |
| `Oversetter/SpeechRecognizer.swift` | Opptak + Whisper |
| `Oversetter/Speaker.swift` | Opplesning |
| `Oversetter/TranslateIntents.swift` | Siri og Snarveier |
| `Oversetter/Language.swift` | Språkliste med koder for NLLB, Whisper og talesyntese |
| `scripts/convert_nllb.py` | Konverterer NLLB fra PyTorch til Core ML |

### Legge til et språk

Legg til en ny `case` i `Language.swift` med kodene for NLLB ([full liste](https://github.com/facebookresearch/flores/blob/main/flores200/README.md#languages-in-flores-200)), Whisper og talesyntese, og legg den til i `caseDisplayRepresentations` i `TranslateIntents.swift`. Modellen trenger ikke konverteres på nytt – alle 200 språk er allerede med.

### Kjente begrensninger

- Hver setning kan være maks ca. 100 ord (128 tokens). Lengre tekst deles automatisk opp i setninger.
- Decoderen regner på hele setningen for hvert nye ord (ingen KV-cache). Det holder for setninger, men en KV-cache-versjon vil være raskere for lange tekster.
- Whisper «small» er middels god på bengali. Bytt til en større modell i `SpeechRecognizer.swift` (`modelName`) på iPhone 15 Pro eller nyere.
- Norsk ↔ bengali er et sjeldent språkpar, så sjekk viktige oversettelser med noen som kan språket.

## Feilsøking

| Problem | Løsning |
|---|---|
| «Fant ikke NLLBEncoder i appen» | Kjør `./scripts/convert_nllb.sh`, og bygg appen på nytt |
| Appen krasjer ved oppstart på eldre iPhone | For lite minne. Lukk andre apper, eller prøv en nyere telefon |
| «Untrusted developer» | Innstillinger → Generelt → VPN og enhetsadministrasjon → stol på sertifikatet |
| Appen åpner ikke etter en uke | Gratis Apple-ID: kjør fra Xcode igjen |
| Siri finner ikke snarveien | Åpne appen én gang etter installasjon, og vent litt |
