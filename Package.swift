// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lyricscape",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (no AppKit/SwiftUI): playback clock, LRC parsing, sync engine.
        // Kept separate so it can be unit tested quickly.
        .target(name: "LyricscapeCore"),

        // The menu bar app itself.
        .executableTarget(
            name: "Lyricscape",
            dependencies: ["LyricscapeCore"],
            linkerSettings: [.linkedFramework("ScriptingBridge")]
        ),

        .testTarget(name: "LyricscapeCoreTests", dependencies: ["LyricscapeCore"]),
    ]
)
