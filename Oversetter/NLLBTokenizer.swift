import Foundation

/// Tokenizer for NLLB-200, skrevet i ren Swift.
///
/// Leser `tokenizer.json` fra Hugging Face (facebook/nllb-200-distilled-600M), som
/// inneholder en SentencePiece Unigram-modell. Teksten deles i ord, og hvert ord
/// deles i biter (tokens) med Viterbi-algoritmen slik SentencePiece gjør.
final class NLLBTokenizer {
    static let bosId = 0   // <s>
    static let padId = 1   // <pad>
    static let eosId = 2   // </s>
    static let unkId = 3   // <unk>

    private static let space = "\u{2581}" // ▁ (SentencePiece sitt mellomrom)

    private var pieceToId: [String: Int] = [:]
    private var scores: [Float] = []
    private var idToPiece: [Int: String] = [:]
    private var specialIds: Set<Int> = []
    private var maxPieceLength = 1
    private var minScore: Float = 0

    init(tokenizerURL: URL) throws {
        let data = try Data(contentsOf: tokenizerURL)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = root["model"] as? [String: Any],
            let vocab = model["vocab"] as? [[Any]]
        else {
            throw TranslatorError.tokenizer("tokenizer.json har ukjent format")
        }

        scores.reserveCapacity(vocab.count)
        pieceToId.reserveCapacity(vocab.count + 256)
        for (id, entry) in vocab.enumerated() {
            guard entry.count >= 2, let piece = entry[0] as? String else { continue }
            let score = (entry[1] as? NSNumber)?.floatValue ?? 0
            scores.append(score)
            pieceToId[piece] = id
            idToPiece[id] = piece
            maxPieceLength = max(maxPieceLength, piece.unicodeScalars.count)
            minScore = min(minScore, score)
        }

        // Spesialtokens og språkkoder (f.eks. "nob_Latn") ligger i added_tokens.
        if let added = root["added_tokens"] as? [[String: Any]] {
            for token in added {
                guard let id = token["id"] as? Int, let content = token["content"] as? String else { continue }
                pieceToId[content] = id
                idToPiece[id] = content
                specialIds.insert(id)
            }
        }
        specialIds.formUnion([Self.bosId, Self.padId, Self.eosId, Self.unkId])
        // Ikke la vanlige biter få spesialtokens som match.
        maxPieceLength = min(maxPieceLength, 32)
    }

    /// Token-id for en språkkode, f.eks. "ben_Beng".
    func languageId(_ code: String) throws -> Int {
        guard let id = pieceToId[code] else {
            throw TranslatorError.tokenizer("Fant ikke språkkoden \(code) i tokenizeren")
        }
        return id
    }

    /// Gjør tekst om til token-id-er (uten språkkode og </s>).
    func encode(_ text: String) -> [Int] {
        // Normalisering omtrent som NLLB: NFKC og ett mellomrom mellom ord.
        let normalized = text.precomposedStringWithCompatibilityMapping
        let words = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var ids: [Int] = []
        for word in words {
            ids.append(contentsOf: viterbi(Self.space + word))
        }
        return ids
    }

    /// Gjør token-id-er om til tekst. Hopper over spesialtokens og språkkoder.
    func decode(_ ids: [Int]) -> String {
        var text = ""
        for id in ids where !specialIds.contains(id) {
            if let piece = idToPiece[id] { text += piece }
        }
        return text
            .replacingOccurrences(of: Self.space, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Finner den mest sannsynlige oppdelingen av ett ord (Unigram + Viterbi).
    private func viterbi(_ word: String) -> [Int] {
        let scalars = Array(word.unicodeScalars)
        let n = scalars.count
        guard n > 0 else { return [] }

        let unkPenalty = minScore - 10
        var best = [Float](repeating: -.infinity, count: n + 1)
        var backPointer = [(start: Int, id: Int)](repeating: (0, Self.unkId), count: n + 1)
        best[0] = 0

        for end in 1...n {
            let lowest = max(0, end - maxPieceLength)
            for start in lowest..<end where best[start] > -.infinity {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[start..<end])
                let piece = String(view)
                if let id = pieceToId[piece], id < scores.count, !specialIds.contains(id) {
                    let candidate = best[start] + scores[id]
                    if candidate > best[end] {
                        best[end] = candidate
                        backPointer[end] = (start, id)
                    }
                }
            }
            // Ukjent tegn: ta ett tegn som <unk> hvis ingenting annet passer.
            if best[end] == -.infinity, best[end - 1] > -.infinity {
                best[end] = best[end - 1] + unkPenalty
                backPointer[end] = (end - 1, Self.unkId)
            }
        }

        var ids: [Int] = []
        var position = n
        while position > 0 {
            let (start, id) = backPointer[position]
            // Slå sammen påfølgende <unk> til én, slik SentencePiece gjør.
            if !(id == Self.unkId && ids.last == Self.unkId) {
                ids.append(id)
            }
            position = start
        }
        return ids.reversed()
    }
}
