import AVFoundation

/// Leser opp tekst med Apples innebygde talesyntese.
///
/// Stemmer lastes ned under Innstillinger → Tilgjengelighet → Opplest innhold → Stemmer.
/// Finnes det ingen stemme for språket, sier `hasVoice(for:)` fra.
@MainActor
final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()

    func hasVoice(for language: Language) -> Bool {
        voice(for: language) != nil
    }

    func speak(_ text: String, language: Language) {
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func voice(for language: Language) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: language.speechCode) {
            return exact
        }
        // Prøv en annen region for samme språk (f.eks. bn-BD i stedet for bn-IN).
        let prefix = String(language.speechCode.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(prefix) }
    }
}
