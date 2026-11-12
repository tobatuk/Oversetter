import Foundation
import Observation

/// Felles oversetter, brukt både av appen og av Siri/Snarveier.
enum Shared {
    static let translator = NLLBTranslator()
}

@MainActor
@Observable
final class TranslationViewModel {
    enum Status: Equatable {
        case idle
        case loading(String)
        case recording
        case working(String)
        case error(String)
    }

    var source: Language = .norwegian
    var target: Language = .bengali
    var inputText = ""
    var outputText = ""
    var status: Status = .idle
    var speakAutomatically = true
    var lastDuration: TimeInterval?

    private let speech = SpeechRecognizer()
    private let speaker = Speaker()
    private var task: Task<Void, Never>?

    var isRecording: Bool { status == .recording }
    var isBusy: Bool {
        switch status {
        case .loading, .working: return true
        default: return false
        }
    }

    func swapLanguages() {
        (source, target) = (target, source)
        if !outputText.isEmpty {
            (inputText, outputText) = (outputText, inputText)
        }
    }

    /// Laster NLLB i bakgrunnen når appen starter, så første oversettelse går raskere.
    func preload() {
        Task {
            status = .loading("Laster oversettelsesmodellen …")
            do {
                try await Shared.translator.load()
                status = .idle
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    func translate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        task = Task {
            status = .working("Oversetter …")
            let start = Date()
            do {
                let result = try await Shared.translator.translate(text, from: source, to: target)
                outputText = result
                lastDuration = Date().timeIntervalSince(start)
                status = .idle
                if speakAutomatically { speak() }
            } catch is CancellationError {
                status = .idle
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    /// Siri ba om å begynne å lytte.
    func handleListenRequest() {
        guard let request = PendingListenRequest.shared.take() else { return }
        source = request.source
        target = request.target
        if !isRecording { startRecording() }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        speaker.stop()
        Task {
            guard await speech.requestPermission() else {
                status = .error("Appen har ikke tilgang til mikrofonen. Slå det på i Innstillinger.")
                return
            }
            do {
                try speech.startRecording()
                status = .recording
            } catch {
                status = .error("Kunne ikke starte opptak: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecording() {
        Task {
            status = .working("Gjenkjenner tale … (første gang lastes Whisper ned)")
            do {
                let text = try await speech.stopAndTranscribe(language: source)
                inputText = text
                if text.isEmpty {
                    status = .error("Hørte ingen tale. Prøv igjen.")
                } else {
                    translate()
                }
            } catch {
                status = .error("Talegjenkjenning feilet: \(error.localizedDescription)")
            }
        }
    }

    func speak() {
        guard !outputText.isEmpty else { return }
        if speaker.hasVoice(for: target) {
            speaker.speak(outputText, language: target)
        } else {
            status = .error("Ingen stemme for \(target.displayName). Last ned under Innstillinger → Tilgjengelighet → Opplest innhold → Stemmer.")
        }
    }
}
