import Foundation

/// Picks the "important" words of a lyric line (to draw bigger and bolder):
/// long, non-filler words, with a bonus for emphasis.
public enum KeywordPicker {
    public static func keywords(in words: [String]) -> Set<Int> {
        let maxCount = words.count <= 5 ? 1 : 2
        let scored: [(index: Int, score: Double)] = words.enumerated().compactMap { i, word in
            let letters = word.filter { $0.isLetter || $0.isNumber }
            let normalized = letters.lowercased()
            if stopwords.contains(normalized) { return nil }
            let isASCII = letters.allSatisfy(\.isASCII)
            // Non-Latin scripts (e.g. Hangul) pack more meaning into fewer characters.
            let length = Double(letters.count) * (isASCII ? 1 : 2)
            guard length >= 4 else { return nil }
            var score = length
            if i > 0, letters.first?.isUppercase == true { score += 2 } // emphasised / proper noun
            if word.contains("!") { score += 1 }
            return (i, score)
        }
        let best = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return Set(best.prefix(maxCount).map(\.index))
    }

    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "if", "of", "to", "in", "on", "at", "for", "with",
        "from", "by", "up", "down", "out", "off", "into", "onto", "over", "about", "just", "like",
        "i", "im", "ill", "ive", "id", "me", "my", "mine", "you", "youre", "youll", "youve", "your",
        "yours", "he", "him", "his", "she", "her", "hers", "it", "its", "we", "us", "our", "they",
        "them", "their", "this", "that", "these", "those", "there", "here", "what", "when", "where",
        "who", "why", "how", "is", "am", "are", "was", "were", "be", "been", "being", "do", "does",
        "did", "dont", "doesnt", "didnt", "cant", "wont", "aint", "have", "has", "had", "will",
        "would", "could", "should", "can", "not", "no", "yes", "yeah", "oh", "ooh", "ah", "uh",
        "hey", "la", "na", "da", "mm", "mmm", "woah", "whoa", "baby", "gonna", "wanna", "gotta",
        "cause", "cuz", "too", "all", "some", "any", "every", "then", "than", "now", "still",
        "ever", "never", "again", "very", "really", "only", "also", "back", "get", "got",
    ]
}
