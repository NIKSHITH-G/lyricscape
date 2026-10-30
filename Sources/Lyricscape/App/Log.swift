import OSLog

extension Logger {
    static let subsystem = "app.lyricscape"
    static let spotify = Logger(subsystem: subsystem, category: "spotify")
    static let app = Logger(subsystem: subsystem, category: "app")
}
