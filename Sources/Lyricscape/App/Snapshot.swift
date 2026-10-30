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
        render(to: folder, styleIDs: only.map { [$0] } ?? StyleRegistry.ids, times: times, themeMode: mode)
        return true
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
