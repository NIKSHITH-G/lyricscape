import Foundation
import NaturalLanguage

/// Splits a lyric line into the "words" that get animated and timed one by one.
/// Spaces separate words as usual; Chinese and Japanese runs (which have no spaces)
/// are segmented into short natural phrases so they animate word by word too.
public enum WordSplitter {
    public static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).flatMap { token -> [String] in
            let token = String(token)
            guard token.count > 2, token.unicodeScalars.contains(where: isCJK) else { return [token] }
            return segment(token)
        }
    }

    private static func segment(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var pieces: [String] = []
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // Keep anything between tokens (punctuation) attached to the previous piece.
            if cursor < range.lowerBound, !pieces.isEmpty {
                pieces[pieces.count - 1] += text[cursor..<range.lowerBound]
            }
            pieces.append(String(text[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex {
            if pieces.isEmpty { pieces.append("") }
            pieces[pieces.count - 1] += text[cursor...]
        }
        // Single-kana particles (に, の, を…) read better attached to the word before.
        var merged: [String] = []
        for piece in pieces {
            if let last = merged.last, piece.count == 1, piece.unicodeScalars.allSatisfy(isKana) {
                merged[merged.count - 1] = last + piece
            } else {
                merged.append(piece)
            }
        }
        return merged.isEmpty ? [text] : merged
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: true // Han
        case 0x3040...0x30FF: true // Hiragana, Katakana
        default: false
        }
    }

    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value)
    }
}
