import Foundation

/// Simplifies Spotify titles/artists for fuzzy lyric searches.
public enum SearchTerms {
    /// "Song (feat. X) - Remastered 2011" → "Song"
    public static func cleanTitle(_ title: String) -> String {
        var t = title
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        t = t.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? title : t
    }

    /// "Artist A, Artist B" / "A & B" / "A feat. B" → "Artist A"
    public static func primaryArtist(_ artist: String) -> String {
        var a = artist
        for separator in [", ", " & ", " feat. ", " ft. ", " featuring "] {
            if let r = a.range(of: separator, options: .caseInsensitive) { a = String(a[..<r.lowerBound]) }
        }
        a = a.trimmingCharacters(in: .whitespaces)
        return a.isEmpty ? artist : a
    }
}
