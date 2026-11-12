import AVFoundation
import Foundation
import WhisperKit

/// Tale til tekst med WhisperKit (Whisper kjørt med Core ML på telefonen).
///
/// Første gang lastes Whisper-modellen ned fra Hugging Face (argmaxinc/whisperkit-coreml).
/// Deretter fungerer den uten nett.
@MainActor
final class SpeechRecognizer {
    /// "openai_whisper-small" er et godt kompromiss for norsk og bengali (ca. 250 MB).
    /// Prøv "openai_whisper-large-v3-v20240930_turbo_632MB" for bedre kvalitet på nyere iPhoner,
    /// eller "openai_whisper-base" om du vil ha noe raskere og mindre.
    static let modelName = "openai_whisper-small"

    private var whisper: WhisperKit?
    private var recorder: AVAudioRecorder?
    private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("opptak.wav")

    var isRecording: Bool { recorder?.isRecording ?? false }

    func load() async throws {
        guard whisper == nil else { return }
        let config = WhisperKitConfig(model: Self.modelName, verbose: false, prewarm: true, load: true, download: true)
        whisper = try await WhisperKit(config)
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        // Whisper vil ha 16 kHz mono.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        recorder?.record()
    }

    /// Stopper opptaket og returnerer teksten som ble sagt.
    func stopAndTranscribe(language: Language) async throws -> String {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        try await load()
        guard let whisper else { return "" }

        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperCode,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisper.transcribe(audioPath: recordingURL.path, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
