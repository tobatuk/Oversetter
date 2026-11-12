import Foundation

/// Språkene appen støtter. Alle finnes i NLLB-200 og Whisper.
/// For å legge til et språk: legg til en case og fyll inn de tre kodene.
enum Language: String, CaseIterable, Identifiable, Codable {
    case norwegian
    case bengali
    case hindi
    case urdu
    case persian
    case danish
    case swedish
    case german
    case english

    var id: String { rawValue }

    /// Navn som vises i appen.
    var displayName: String {
        switch self {
        case .norwegian: return "Norsk"
        case .bengali: return "Bengali (বাংলা)"
        case .hindi: return "Hindi (हिन्दी)"
        case .urdu: return "Urdu (اردو)"
        case .persian: return "Farsi (فارسی)"
        case .danish: return "Dansk"
        case .swedish: return "Svensk"
        case .german: return "Tysk"
        case .english: return "Engelsk"
        }
    }

    /// Språkkode i NLLB-200 (FLORES-200-format).
    var nllbCode: String {
        switch self {
        case .norwegian: return "nob_Latn"
        case .bengali: return "ben_Beng"
        case .hindi: return "hin_Deva"
        case .urdu: return "urd_Arab"
        case .persian: return "pes_Arab"
        case .danish: return "dan_Latn"
        case .swedish: return "swe_Latn"
        case .german: return "deu_Latn"
        case .english: return "eng_Latn"
        }
    }

    /// Språkkode for Whisper (talegjenkjenning).
    var whisperCode: String {
        switch self {
        case .norwegian: return "no"
        case .bengali: return "bn"
        case .hindi: return "hi"
        case .urdu: return "ur"
        case .persian: return "fa"
        case .danish: return "da"
        case .swedish: return "sv"
        case .german: return "de"
        case .english: return "en"
        }
    }

    /// Språkkode for Apples talesyntese (opplesning).
    var speechCode: String {
        switch self {
        case .norwegian: return "nb-NO"
        case .bengali: return "bn-IN"
        case .hindi: return "hi-IN"
        case .urdu: return "ur-PK"
        case .persian: return "fa-IR"
        case .danish: return "da-DK"
        case .swedish: return "sv-SE"
        case .german: return "de-DE"
        case .english: return "en-US"
        }
    }

    /// Skrives fra høyre mot venstre.
    var isRightToLeft: Bool {
        self == .urdu || self == .persian
    }
}
