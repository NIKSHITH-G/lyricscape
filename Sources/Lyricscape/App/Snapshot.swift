import AppKit
import LyricscapeCore
import Metal
import OSLog
import QuartzCore

/// Developer tool: `Lyricscape --snapshot <folder>` renders every style at a few
/// moments of the demo song to PNGs, offscreen (works with the screen locked), and
/// times each style's per-frame work. Then quits.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let only = args.firstIndex(of: "--style").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let times = args.firstIndex(of: "--times").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }?
            .split(separator: ",").compactMap { Double($0) } ?? [3, 7.0, 10.6, 15.0, 25.4, 41.0]
        let mode = args.firstIndex(of: "--theme").flatMap { $0 + 1 < args.count ? ThemeMode(rawValue: args[$0 + 1]) : nil }
        if args.contains("--gallery") {
            gallery(to: folder, size: parseSize(args) ?? CGSize(width: 1600, height: 1000))
        } else {
            render(to: folder, styleIDs: only.map { [$0] } ?? StyleRegistry.ids, times: times, themeMode: mode)
        }
        return true
    }

    private static func parseSize(_ args: [String]) -> CGSize? {
        guard let i = args.firstIndex(of: "--size"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }

    /// The moment of the demo song that shows each style off best.
    static let showcaseTime: [String: Double] = [
        "constellation": 15.6, "kinetic": 11.3, "karaoke": 10.7, "rain": 12.3, "orbit": 15.4,
        "typewriter": 15.6, "glitch": 10.4, "particles": 9.35, "minimal": 15.0,
    ]

    /// A hue per style, so a gallery of them isn't all one colour.
    static func showcaseTheme(for id: String) -> LyricTheme {
        let index = Double(StyleRegistry.ids.firstIndex(of: id) ?? 0)
        let hue = (0.92 + index * 0.11).truncatingRemainder(dividingBy: 1)
        return id == "typewriter" ? .terminal : .neon(hue: hue, lineHue: (hue + 0.08).truncatingRemainder(dividingBy: 1))
    }

    /// `--gallery`: one showcase PNG per style (for the website).
    private static func gallery(to folder: URL, size: CGSize) {
        for id in StyleRegistry.ids {
            var settings = StyleSettings()
            settings.theme = showcaseTheme(for: id)
            guard let image = still(styleID: id, size: size, time: showcaseTime[id] ?? 12, settings: settings) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(id).png"))
            print("rendered \(id)")
        }
    }

    /// One frame of a style playing the demo song at `time`, rendered offscreen.
    /// Used for the Settings thumbnails and the website gallery.
    static func still(styleID: String, size: CGSize, time: Double, settings: StyleSettings, scale: CGFloat = 1) -> CGImage? {
        let demo = DemoLyricSource()
        guard let document = demo.document, let track = demo.track,
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let engine = SyncEngine(document: document)
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.isGeometryFlipped = true
        root.backgroundColor = CGColor.black
        let styleRoot = CALayer()
        styleRoot.frame = root.bounds
        root.addSublayer(styleRoot)
        let style = StyleRegistry.style(withID: styleID).init(root: styleRoot)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in stride(from: max(0, time - 3), through: time, by: 1.0 / 30) {
            style.update(LyricFrame(time: t, document: document, position: engine.position(at: t), isPlaying: true,
                                    track: track, playID: 0, size: size, topInset: 0, scale: scale, settings: settings,
                                    opaqueBackground: true, audio: demoAudio(t)))
        }
        CATransaction.commit()
        // Render at `scale`× by drawing the point-sized tree into a larger canvas.
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let canvas = CALayer()
        canvas.frame = CGRect(origin: .zero, size: pixelSize)
        root.anchorPoint = .zero
        root.position = .zero
        root.transform = CATransform3DMakeScale(scale, scale, 1)
        canvas.addSublayer(root)
        defer { style.reset() }
        return renderImage(canvas, size: pixelSize, device: device, queue: queue)
    }

    private static func render(to folder: URL, styleIDs: [String], times: [Double], themeMode: ThemeMode?) {
        let size = CGSize(width: 1440, height: 900)
        let demo = DemoLyricSource()
        guard let document = demo.document, let track = demo.track,
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return }
        let engine = SyncEngine(document: document)
        var settings = StyleSettings()
        if let themeMode { settings.themeMode = themeMode }
        settings.theme = .neon(hue: 0.92, lineHue: 0.98)

        for id in styleIDs {
            let root = CALayer()
            root.frame = CGRect(origin: .zero, size: size)
            root.isGeometryFlipped = true
            root.backgroundColor = CGColor.black
            let styleRoot = CALayer()
            styleRoot.frame = root.bounds
            root.addSublayer(styleRoot)
            let style = StyleRegistry.style(withID: id).init(root: styleRoot)

            func frame(at t: Double) -> LyricFrame {
                let position = engine.position(at: t)
                return LyricFrame(time: t, document: document, position: position, isPlaying: true, track: track,
                                  playID: 0, size: size, topInset: 0, scale: 1, settings: settings,
                                  opaqueBackground: true, audio: demoAudio(t))
            }

            // Timing: 10 s of the song at 60 fps, as the display link would drive it.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let clock = ContinuousClock()
            let elapsed = clock.measure {
                for n in 0..<600 { style.update(frame(at: 8 + Double(n) / 60)) }
            }
            CATransaction.commit()
            let ms = Double(elapsed.components.attoseconds) / 1e15 / 600 + Double(elapsed.components.seconds) * 1000 / 600
            Logger.app.notice("📸 \(id, privacy: .public): \(String(format: "%.2f", ms), privacy: .public) ms per frame")
            print("\(id): \(String(format: "%.2f", ms)) ms/frame")

            for t in times {
                // Run up to the moment so time-accumulating effects (dust…) build up.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                style.reset()
                for n in stride(from: max(0, t - 3), through: t, by: 1.0 / 30) { style.update(frame(at: n)) }
                CATransaction.commit()
                if let image = renderImage(root, size: size, device: device, queue: queue) {
                    let url = folder.appending(path: "\(id)-\(String(format: "%04.1f", t)).png")
                    let rep = NSBitmapImageRep(cgImage: image)
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            style.reset()
        }
    }

    private static func demoAudio(_ t: Double) -> AudioLevels {
        let period = 60.0 / 112
        let beat = exp(-t.truncatingRemainder(dividingBy: period) / period * 7)
        return AudioLevels(level: 0.6, bass: beat, beat: beat, isActive: true)
    }

    /// Renders a layer tree with Core Animation's own renderer into a Metal texture.
    private static func renderImage(_ layer: CALayer, size: CGSize, device: MTLDevice, queue: MTLCommandQueue) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
        renderer.layer = layer
        renderer.bounds = CGRect(origin: .zero, size: size)
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()

        guard let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        // Texture rows run bottom-up; flip them so the PNG is the right way round.
        let rowBytes = width * 4
        var flipped = [UInt8](repeating: 0, count: bytes.count)
        for row in 0..<height {
            flipped.replaceSubrange(row * rowBytes..<(row + 1) * rowBytes,
                                    with: bytes[(height - 1 - row) * rowBytes..<(height - row) * rowBytes])
        }
        guard let provider = CGDataProvider(data: Data(flipped) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
