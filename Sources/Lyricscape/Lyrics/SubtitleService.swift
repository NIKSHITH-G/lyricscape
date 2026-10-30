import Foundation
import NaturalLanguage
import OSLog
import Translation

enum SubtitleMode: String, Codable, CaseIterable, Sendable {
    case off, romanization, translation, both

    var title: String {
        switch self {
        case .off: "Off"
        case .romanization: "Romanization"
        case .translation: "Translation"
        case .both: "Both"
        }
    }
}

/// Romanization (offline, built into macOS) and translation (Apple's on-device
/// Translation, using whatever languages are downloaded in System Settings) of
/// lyric lines. Results are cached; translations arrive asynchronously.
@MainActor
final class SubtitleService {
    private var romanized: [String: String] = [:]
    private var translated: [String: String] = [:]
    private var pending: Set<String> = []
    /// Last translation problem, shown in Settings.
    private(set) var lastProblem: String?

    var targetLanguage: Locale.Language { Locale.current.language }

    func subtitle(for text: String, mode: SubtitleMode) -> String? {
        switch mode {
        case .off: return nil
        case .romanization: return romanization(of: text)
        case .translation: return translation(of: text)
        case .both:
            let parts = [romanization(of: text), translation(of: text)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
    }

    /// Latin-letter reading of non-Latin text (Hangul, Kana, Han, Cyrillic…); nil for
    /// text that's already Latin.
    func romanization(of text: String) -> String? {
        if let cached = romanized[text] { return cached.isEmpty ? nil : cached }
        let needsIt = text.unicodeScalars.contains { $0.properties.isAlphabetic && !$0.isASCII && !Self.isLatin($0) }
        let result: String
        if !needsIt {
            result = ""
        } else if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            // Japanese: kanji need Japanese readings, not Chinese pinyin.
            result = Self.romaji(text)
        } else {
            result = text.applyingTransform(.toLatin, reverse: false) ?? ""
        }
        romanized[text] = result
        return result.isEmpty ? nil : result
    }

    /// Translation into the user's language, or nil if not available (yet).
    func translation(of text: String) -> String? {
        if let cached = translated[text] { return cached.isEmpty ? nil : cached }
        guard !pending.contains(text) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              language.rawValue != targetLanguage.languageCode?.identifier else {
            translated[text] = "" // already in the user's language
            return nil
        }
        pending.insert(text)
        Task {
            let result = await translate(text, from: Locale.Language(identifier: language.rawValue))
            translated[text] = result ?? ""
            pending.remove(text)
        }
        return nil
    }

    private func translate(_ text: String, from source: Locale.Language) async -> String? {
        guard #available(macOS 26.0, *) else {
            lastProblem = "Translation needs macOS 26 or later."
            return nil
        }
        do {
            let session = TranslationSession(installedSource: source, target: targetLanguage)
            return try await session.translate(text).targetText
        } catch {
            let name = Locale.current.localizedString(forLanguageCode: source.languageCode?.identifier ?? "") ?? "this language"
            lastProblem = "To translate \(name), download it in System Settings › General › Language & Region › Translation Languages."
            Logger.lyrics.notice("Translation unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Hepburn-style romaji using the system's Japanese word readings.
    private static func romaji(_ text: String) -> String {
        let string = text as CFString
        let tokenizer = CFStringTokenizerCreate(nil, string, CFRange(location: 0, length: CFStringGetLength(string)),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var parts: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                parts.append(latin)
            }
        }
        return parts.joined(separator: " ")
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        // Latin-1 Supplement through Latin Extended Additional.
        (0x00C0...0x024F).contains(scalar.value) || (0x1E00...0x1EFF).contains(scalar.value)
    }
}
