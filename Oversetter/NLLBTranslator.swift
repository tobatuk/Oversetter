import Accelerate
import CoreML
import Foundation
import NaturalLanguage

enum TranslatorError: LocalizedError {
    case missingModel(String)
    case tokenizer(String)
    case prediction(String)

    var errorDescription: String? {
        switch self {
        case .missingModel(let name):
            return "Fant ikke \(name) i appen. Kjør scripts/convert_nllb.sh på Macen og bygg appen på nytt (se README)."
        case .tokenizer(let message):
            return "Tokenizer-feil: \(message)"
        case .prediction(let message):
            return "Oversettelsesfeil: \(message)"
        }
    }
}

/// Kjører NLLB-200 lokalt med Core ML.
///
/// Modellen er delt i to filer, laget av scripts/convert_nllb.py:
/// - NLLBEncoder: leser hele kildesetningen én gang.
/// - NLLBDecoder: gjetter neste ord i oversettelsen, ett ord om gangen.
///
/// Begge bruker fast lengde (128 tokens), som passer best for Neural Engine.
/// Lengre tekst deles opp i setninger før oversettelse.
actor NLLBTranslator {
    static let maxTokens = 128

    private var encoder: MLModel?
    private var decoder: MLModel?
    private var tokenizer: NLLBTokenizer?

    var isLoaded: Bool { encoder != nil && decoder != nil && tokenizer != nil }

    func load() async throws {
        guard !isLoaded else { return }

        guard let tokenizerURL = Bundle.main.url(forResource: "tokenizer", withExtension: "json") else {
            throw TranslatorError.missingModel("tokenizer.json")
        }
        guard let encoderURL = Bundle.main.url(forResource: "NLLBEncoder", withExtension: "mlmodelc") else {
            throw TranslatorError.missingModel("NLLBEncoder")
        }
        guard let decoderURL = Bundle.main.url(forResource: "NLLBDecoder", withExtension: "mlmodelc") else {
            throw TranslatorError.missingModel("NLLBDecoder")
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all // Core ML velger selv Neural Engine, GPU eller CPU

        tokenizer = try NLLBTokenizer(tokenizerURL: tokenizerURL)
        encoder = try await MLModel.load(contentsOf: encoderURL, configuration: configuration)
        decoder = try await MLModel.load(contentsOf: decoderURL, configuration: configuration)
    }

    /// Oversetter tekst. Teksten deles i setninger som oversettes én og én.
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        try await load()
        let sentences = Self.splitIntoSentences(text, language: source)
        var results: [String] = []
        for sentence in sentences {
            try Task.checkCancellation()
            results.append(try translateSentence(sentence, from: source, to: target))
        }
        return results.joined(separator: " ")
    }

    // MARK: - Én setning

    private func translateSentence(_ sentence: String, from source: Language, to target: Language) throws -> String {
        guard let encoder, let decoder, let tokenizer else {
            throw TranslatorError.prediction("Modellen er ikke lastet")
        }
        let n = Self.maxTokens

        // 1. Tokenisering: [kildespråk] tekst </s>
        var tokens = tokenizer.encode(sentence)
        if tokens.count > n - 2 { tokens = Array(tokens.prefix(n - 2)) }
        let sourceIds = [try tokenizer.languageId(source.nllbCode)] + tokens + [NLLBTokenizer.eosId]

        let inputIds = try Self.int32Array(sourceIds, length: n, padding: NLLBTokenizer.padId)
        let attentionMask = try Self.int32Array(Array(repeating: 1, count: sourceIds.count), length: n, padding: 0)

        // 2. Encoder: kjøres én gang per setning.
        let encoderOutput = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ]))
        guard let hiddenStates = encoderOutput.featureValue(for: "encoder_hidden_states")?.multiArrayValue else {
            throw TranslatorError.prediction("Encoderen ga ikke noe resultat")
        }

        // 3. Decoder-løkke: starter med </s> [målspråk] og legger til ett token om gangen.
        var output = [NLLBTokenizer.eosId, try tokenizer.languageId(target.nllbCode)]
        let maxLength = min(n, sourceIds.count * 2 + 16)
        let position = try MLMultiArray(shape: [1], dataType: .int32)

        while output.count < maxLength {
            let decoderIds = try Self.int32Array(output, length: n, padding: NLLBTokenizer.padId)
            position[0] = NSNumber(value: Int32(output.count - 1))

            let decoderOutput = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": MLFeatureValue(multiArray: decoderIds),
                "encoder_hidden_states": MLFeatureValue(multiArray: hiddenStates),
                "encoder_attention_mask": MLFeatureValue(multiArray: attentionMask),
                "position": MLFeatureValue(multiArray: position),
            ]))
            guard let logits = decoderOutput.featureValue(for: "logits")?.multiArrayValue else {
                throw TranslatorError.prediction("Decoderen ga ikke noe resultat")
            }

            let next = Self.argmax(logits, excluding: [NLLBTokenizer.padId, NLLBTokenizer.bosId, NLLBTokenizer.unkId])
            if next == NLLBTokenizer.eosId { break }
            // Enkel vern mot at modellen gjentar seg selv i det uendelige.
            if output.suffix(4).allSatisfy({ $0 == next }) { break }
            output.append(next)
        }

        return tokenizer.decode(Array(output.dropFirst(2)))
    }

    // MARK: - Hjelpefunksjoner

    static func splitIntoSentences(_ text: String, language: Language) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private static func int32Array(_ values: [Int], length: Int, padding: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: length)
        for i in 0..<length {
            pointer[i] = Int32(i < values.count ? values[i] : padding)
        }
        return array
    }

    /// Finner token-id-en med høyest sannsynlighet.
    private static func argmax(_ logits: MLMultiArray, excluding excluded: [Int]) -> Int {
        let count = logits.count
        var values = [Float](repeating: 0, count: count)

        switch logits.dataType {
        case .float16:
            logits.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
                for i in 0..<count { values[i] = Float(buffer[i]) }
            }
        case .double:
            logits.withUnsafeBufferPointer(ofType: Double.self) { buffer in
                for i in 0..<count { values[i] = Float(buffer[i]) }
            }
        default:
            logits.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                _ = values.withUnsafeMutableBufferPointer { $0.initialize(from: buffer) }
            }
        }

        for id in excluded where id < count { values[id] = -.greatestFiniteMagnitude }

        var maxValue: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(values, 1, &maxValue, &maxIndex, vDSP_Length(count))
        return Int(maxIndex)
    }
}
