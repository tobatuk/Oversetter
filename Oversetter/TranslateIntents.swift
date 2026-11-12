import AppIntents
import Foundation

// Siri og Snarveier.
//
// «Hei Siri, oversett med Oversetter»          → Siri spør om teksten og svarer med oversettelsen.
// «Hei Siri, snakk bengali med Oversetter»      → åpner appen og begynner å lytte med en gang.
//
// Begge vises også i Snarveier-appen, der de kan kombineres med f.eks. «Dikter tekst» og «Les opp tekst».

extension Language: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Språk" }

    static var caseDisplayRepresentations: [Language: DisplayRepresentation] {
        [
            .norwegian: "Norsk",
            .bengali: "Bengali",
            .hindi: "Hindi",
            .urdu: "Urdu",
            .persian: "Farsi",
            .danish: "Dansk",
            .swedish: "Svensk",
            .german: "Tysk",
            .english: "Engelsk",
        ]
    }
}

/// Oversetter en tekst uten å åpne appen.
struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Oversett tekst"
    static var description = IntentDescription("Oversetter tekst lokalt på telefonen med NLLB.")

    @Parameter(title: "Tekst", requestValueDialog: "Hva vil du oversette?")
    var text: String

    @Parameter(title: "Fra", default: .norwegian)
    var source: Language

    @Parameter(title: "Til", default: .bengali)
    var target: Language

    static var parameterSummary: some ParameterSummary {
        Summary("Oversett \(\.$text) fra \(\.$source) til \(\.$target)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await Shared.translator.translate(text, from: source, to: target)
        return .result(value: result, dialog: "\(result)")
    }
}

/// Åpner appen og starter opptak med valgt språkpar.
struct ListenIntent: AppIntent {
    static var title: LocalizedStringResource = "Snakk og oversett"
    static var description = IntentDescription("Åpner Oversetter og begynner å lytte.")
    static var openAppWhenRun = true

    @Parameter(title: "Fra", default: .norwegian)
    var source: Language

    @Parameter(title: "Til", default: .bengali)
    var target: Language

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingListenRequest.shared.request(source: source, target: target)
        return .result()
    }
}

/// Holder på en «begynn å lytte»-forespørsel fra Siri til appen er klar.
@MainActor
final class PendingListenRequest {
    static let shared = PendingListenRequest()
    private(set) var pending: (source: Language, target: Language)?

    func request(source: Language, target: Language) {
        pending = (source, target)
        NotificationCenter.default.post(name: .listenRequested, object: nil)
    }

    func take() -> (source: Language, target: Language)? {
        defer { pending = nil }
        return pending
    }
}

extension Notification.Name {
    static let listenRequested = Notification.Name("ListenRequested")
}

struct OversetterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateTextIntent(),
            phrases: [
                "Oversett med \(.applicationName)",
                "Oversett til \(\.$target) med \(.applicationName)",
            ],
            shortTitle: "Oversett tekst",
            systemImageName: "character.bubble"
        )
        AppShortcut(
            intent: ListenIntent(),
            phrases: [
                "Snakk \(\.$target) med \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Snakk og oversett",
            systemImageName: "mic.fill"
        )
    }
}
