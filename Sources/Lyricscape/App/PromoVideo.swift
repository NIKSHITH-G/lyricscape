import AppKit
import LyricscapeCore
import Metal
import QuartzCore

/// Developer tool: `Lyricscape --video <out.mp4> [--size 1920x1080]` renders a short
/// promo video — title card, the overlay on a desktop, every style, outro — offscreen
/// with the real styles playing the demo song, and encodes it with ffmpeg. Then quits.
@MainActor
enum PromoVideo {
    static let fps = 30.0

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--video"), i + 1 < args.count else { return false }
        var size = CGSize(width: 1920, height: 1080)
        if let s = args.firstIndex(of: "--size"), s + 1 < args.count {
            let parts = args[s + 1].split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { size = CGSize(width: parts[0], height: parts[1]) }
        }
        render(to: args[i + 1], size: size)
        return true
    }

    private enum Scene {
        case title
        case desktop
        case style(id: String, index: Int)
        case outro

        var duration: Double {
            switch self {
            case .title: 3.2
            case .desktop: 4.8
            case .style: 3.3
            case .outro: 3.8
            }
        }
    }

    private static func render(to path: String, size: CGSize) {
        guard let renderer = FrameRenderer(size: size) else { return }
        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ffmpeg.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra",
                            "-s", "\(Int(size.width))x\(Int(size.height))", "-r", "\(Int(fps))", "-i", "-",
                            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "21", "-preset", "slow",
                            "-movflags", "+faststart", path]
        let pipe = Pipe()
        ffmpeg.standardInput = pipe
        do { try ffmpeg.run() } catch {
            print("Couldn't start ffmpeg: \(error)")
            return
        }

        var scenes: [Scene] = [.title, .desktop]
        scenes += StyleRegistry.ids.enumerated().map { Scene.style(id: $1, index: $0) }
        scenes.append(.outro)

        var frames = 0
        for scene in scenes {
            let stage = SceneStage(scene: scene, size: size)
            let count = Int(scene.duration * fps)
            for n in 0..<count {
                let local = Double(n) / fps
                stage.update(local: local, duration: scene.duration)
                guard let pixels = renderer.render(stage.root) else { continue }
                pipe.fileHandleForWriting.write(pixels)
                frames += 1
            }
            print("rendered \(stage.name) (\(count) frames)")
        }
        try? pipe.fileHandleForWriting.close()
        ffmpeg.waitUntilExit()
        print("wrote \(path): \(frames) frames, \(String(format: "%.1f", Double(frames) / fps)) s")
    }

    /// One scene's layer tree: background, the style (if any), captions and a fade.
    @MainActor
    private final class SceneStage {
        let root = CALayer()
        let name: String
        private let scene: Scene
        private let size: CGSize
        private let styleRoot = CALayer()
        private var style: (any LyricStyle)?
        private let caption = CALayer()
        private let fade = CALayer()
        private let demo = DemoLyricSource()
        private let engine: SyncEngine
        private var settings = StyleSettings()
        private var songStart = 0.0
        private var opaque = true

        init(scene: Scene, size: CGSize) {
            self.scene = scene
            self.size = size
            engine = SyncEngine(document: demo.document!)
            root.frame = CGRect(origin: .zero, size: size)
            root.isGeometryFlipped = true
            root.backgroundColor = CGColor.black
            styleRoot.frame = root.bounds
            caption.frame = root.bounds
            fade.frame = root.bounds
            fade.backgroundColor = CGColor.black

            switch scene {
            case .title:
                name = "title"
                addStarfield()
                buildTitle()
            case .desktop:
                name = "desktop"
                buildDesktop()
                root.addSublayer(styleRoot)
                settings.theme = .neon(hue: 0.92, lineHue: 0.98)
                settings.showFrame = false
                opaque = false
                songStart = 5.1
                style = ConstellationStyle(root: styleRoot)
                addCaption(kicker: "FLOATS OVER EVERYTHING", title: "Lyrics across your whole screen",
                           detail: "In time with Spotify. Clicks pass straight through.")
            case .style(let id, let index):
                let type = StyleRegistry.style(withID: id)
                name = id
                root.addSublayer(styleRoot)
                settings.theme = Snapshot.showcaseTheme(for: id)
                // Keep corner styles clear of the caption in the bottom left.
                if id == MinimalStyle.id { settings.anchor = .topRight }
                songStart = max(0, (Snapshot.showcaseTime[id] ?? 12) - 2.6)
                style = type.init(root: styleRoot)
                addCaption(kicker: "STYLE \(index + 1) OF \(StyleRegistry.ids.count)", title: type.displayName,
                           detail: type.summary)
            case .outro:
                name = "outro"
                addStarfield()
                buildOutro()
            }
            root.addSublayer(caption)
            root.addSublayer(fade)
            warmUp()
        }

        /// Run the style through the seconds before the scene starts, so it's mid-song.
        private func warmUp() {
            guard style != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for t in stride(from: max(0, songStart - 3), to: songStart, by: 1.0 / 30) { step(t) }
            CATransaction.commit()
        }

        private func step(_ t: Double) {
            let period = 60.0 / 112
            let beat = exp(-t.truncatingRemainder(dividingBy: period) / period * 7)
            style?.update(LyricFrame(time: t, document: demo.document!, position: engine.position(at: t), isPlaying: true,
                                     track: demo.track!, playID: 0, size: size, topInset: opaque ? 0 : size.height * 0.03,
                                     scale: 1, settings: settings, opaqueBackground: opaque,
                                     audio: AudioLevels(level: 0.6, bass: beat, beat: beat, isActive: true)))
        }

        func update(local: Double, duration: Double) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            step(songStart + local)
            // Fade in from and out to black at the scene edges.
            let edge = 0.3
            fade.opacity = Float(max(0, 1 - local / edge, 1 - (duration - local) / edge))
            // Captions slide up and in after a beat.
            let c = Ease.outCubic((local - 0.35) / 0.5)
            caption.opacity = Float(c)
            caption.transform = CATransform3DMakeTranslation(0, CGFloat(1 - c) * 24, 0)
            // Title and outro breathe slowly.
            if case .title = scene { pulseTitle(local) }
            if case .outro = scene { pulseTitle(local) }
            CATransaction.commit()
        }

        // MARK: Building blocks

        private var unit: CGFloat { min(size.width, size.height) }

        private func text(_ string: String, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor,
                          alignment: CATextLayerAlignmentMode = .left) -> CATextLayer {
            // Shrink to fit the frame (matters for the vertical video).
            let maxWidth = self.size.width * 0.88
            var font = StyleSettings().font(size: fontSize, weight: weight)
            var attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            if attributed.size().width + 8 > maxWidth {
                font = StyleSettings().font(size: fontSize * maxWidth / (attributed.size().width + 8), weight: weight)
                attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            }
            let layer = CATextLayer()
            layer.string = attributed
            layer.contentsScale = 1
            layer.alignmentMode = alignment
            layer.bounds = CGRect(x: 0, y: 0, width: ceil(attributed.size().width) + 8, height: ceil(attributed.size().height))
            return layer
        }

        private func gradientText(_ string: String, size fontSize: CGFloat) -> CALayer {
            let mask = text(string, size: fontSize, weight: .heavy, color: .white, alignment: .center)
            let gradient = CAGradientLayer()
            gradient.colors = [CGColor(srgbRed: 1, green: 0.165, blue: 0.427, alpha: 1),
                               CGColor(srgbRed: 0.545, green: 0.36, blue: 0.965, alpha: 1)]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            gradient.bounds = mask.bounds
            mask.position = CGPoint(x: mask.bounds.midX, y: mask.bounds.midY)
            gradient.mask = mask
            return gradient
        }

        private func addCaption(kicker: String, title: String, detail: String) {
            let margin = unit * 0.06
            let kickerLayer = text(kicker, size: unit * 0.022, weight: .bold, color: NSColor(srgbRed: 1, green: 0.35, blue: 0.55, alpha: 1))
            let titleLayer = text(title, size: unit * 0.06, weight: .heavy, color: .white)
            let detailLayer = text(detail, size: unit * 0.028, weight: .medium, color: NSColor(white: 1, alpha: 0.72))
            var y = size.height - margin
            for layer in [detailLayer, titleLayer, kickerLayer] {
                y -= layer.bounds.height
                layer.anchorPoint = .zero
                layer.position = CGPoint(x: margin, y: y)
                layer.shadowColor = CGColor.black
                layer.shadowOpacity = 0.9
                layer.shadowRadius = 12
                layer.shadowOffset = .zero
                caption.addSublayer(layer)
                y -= unit * 0.008
            }
            // A soft dark band so captions read on any background.
            let band = CAGradientLayer()
            band.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.65)]
            band.frame = CGRect(x: 0, y: y - unit * 0.06, width: size.width, height: size.height - y + unit * 0.06)
            caption.insertSublayer(band, at: 0)
        }

        private func addStarfield() {
            var rng = SeededRandom(seed: 11)
            for _ in 0..<Int(size.width * size.height / 9000) {
                let star = CALayer()
                let d = CGFloat.random(in: 0.8...2.6, using: &rng)
                star.frame = CGRect(x: CGFloat.random(in: 0...size.width, using: &rng),
                                    y: CGFloat.random(in: 0...size.height, using: &rng), width: d, height: d)
                star.cornerRadius = d / 2
                star.backgroundColor = CGColor(gray: 1, alpha: 1)
                star.opacity = Float.random(in: 0.1...0.55, using: &rng)
                root.addSublayer(star)
            }
            let glow = CAGradientLayer()
            glow.type = .radial
            glow.colors = [CGColor(srgbRed: 0.6, green: 0.15, blue: 0.5, alpha: 0.45), CGColor(gray: 0, alpha: 0)]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            glow.frame = CGRect(x: size.width * 0.1, y: size.height * 0.05, width: size.width * 0.8, height: size.height * 0.8)
            root.addSublayer(glow)
        }

        private var titleGroup = CALayer()

        private func buildTitle() {
            titleGroup.frame = root.bounds
            let icon = CALayer()
            icon.contents = NSApp.applicationIconImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let iconSize = unit * 0.2
            icon.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            icon.position = CGPoint(x: size.width / 2, y: size.height * 0.36)
            icon.shadowColor = CGColor(srgbRed: 1, green: 0.17, blue: 0.43, alpha: 1)
            icon.shadowOpacity = 0.8
            icon.shadowRadius = 40
            icon.shadowOffset = .zero
            titleGroup.addSublayer(icon)

            let name = text("Lyricscape", size: unit * 0.11, weight: .heavy, color: .white, alignment: .center)
            name.position = CGPoint(x: size.width / 2, y: size.height * 0.36 + iconSize * 0.5 + name.bounds.height * 0.62)
            titleGroup.addSublayer(name)
            let tagline = gradientText("Your lyrics, written across the sky.", size: unit * 0.05)
            tagline.position = CGPoint(x: size.width / 2, y: name.position.y + name.bounds.height * 0.5 + tagline.bounds.height * 0.7)
            titleGroup.addSublayer(tagline)
            let sub = text("Animated lyrics for Spotify on your Mac", size: unit * 0.03, weight: .medium,
                           color: NSColor(white: 1, alpha: 0.6), alignment: .center)
            sub.position = CGPoint(x: size.width / 2, y: tagline.position.y + tagline.bounds.height * 0.5 + sub.bounds.height)
            titleGroup.addSublayer(sub)
            root.addSublayer(titleGroup)
        }

        private func buildOutro() {
            titleGroup.frame = root.bounds
            let icon = CALayer()
            icon.contents = NSApp.applicationIconImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let iconSize = unit * 0.16
            icon.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            icon.position = CGPoint(x: size.width / 2, y: size.height * 0.34)
            icon.shadowColor = CGColor(srgbRed: 0.55, green: 0.36, blue: 0.97, alpha: 1)
            icon.shadowOpacity = 0.8
            icon.shadowRadius = 36
            icon.shadowOffset = .zero
            titleGroup.addSublayer(icon)
            let headline = text("Press play. Watch the sky.", size: unit * 0.075, weight: .heavy, color: .white, alignment: .center)
            headline.position = CGPoint(x: size.width / 2, y: size.height * 0.34 + iconSize * 0.5 + headline.bounds.height * 0.7)
            titleGroup.addSublayer(headline)
            let link = gradientText("getlyricscape.vercel.app", size: unit * 0.055)
            link.position = CGPoint(x: size.width / 2, y: headline.position.y + headline.bounds.height * 0.5 + link.bounds.height * 0.75)
            titleGroup.addSublayer(link)
            let sub = text("Free & open source · macOS 14+ · Apple silicon", size: unit * 0.028, weight: .medium,
                           color: NSColor(white: 1, alpha: 0.6), alignment: .center)
            sub.position = CGPoint(x: size.width / 2, y: link.position.y + link.bounds.height * 0.5 + sub.bounds.height)
            titleGroup.addSublayer(sub)
            root.addSublayer(titleGroup)
        }

        private func pulseTitle(_ local: Double) {
            let s = 0.96 + 0.04 * Ease.outCubic(local / 2.5)
            titleGroup.transform = CATransform3DMakeScale(s, s, 1)
            titleGroup.opacity = Float(Ease.outCubic(local / 0.6))
        }

        /// A stylised Mac desktop: wallpaper, menu bar and two app windows.
        private func buildDesktop() {
            let wallpaper = CAGradientLayer()
            wallpaper.frame = root.bounds
            wallpaper.colors = [CGColor(srgbRed: 0.16, green: 0.12, blue: 0.38, alpha: 1),
                                CGColor(srgbRed: 0.55, green: 0.22, blue: 0.48, alpha: 1),
                                CGColor(srgbRed: 0.93, green: 0.55, blue: 0.4, alpha: 1)]
            wallpaper.startPoint = CGPoint(x: 0, y: 0)
            wallpaper.endPoint = CGPoint(x: 1, y: 1)
            root.addSublayer(wallpaper)

            let menuBar = CALayer()
            menuBar.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.03)
            menuBar.backgroundColor = CGColor(gray: 0, alpha: 0.35)
            root.addSublayer(menuBar)
            let menuText = text("   Spotify    File    Edit    View    Playback", size: size.height * 0.016, weight: .semibold, color: .white)
            menuText.anchorPoint = .zero
            menuText.position = CGPoint(x: unit * 0.01, y: (menuBar.bounds.height - menuText.bounds.height) / 2)
            menuBar.addSublayer(menuText)

            func window(_ frame: CGRect, dark: Bool, lines: Int) {
                let w = CALayer()
                w.frame = frame
                w.cornerRadius = unit * 0.012
                w.backgroundColor = dark ? CGColor(srgbRed: 0.11, green: 0.1, blue: 0.13, alpha: 0.96)
                    : CGColor(srgbRed: 0.97, green: 0.96, blue: 0.95, alpha: 0.96)
                w.shadowColor = CGColor.black
                w.shadowOpacity = 0.45
                w.shadowRadius = 30
                w.shadowOffset = CGSize(width: 0, height: 12)
                let colors: [CGColor] = [CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                                         CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                                         CGColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
                let dot = unit * 0.011
                for (k, color) in colors.enumerated() {
                    let d = CALayer()
                    d.frame = CGRect(x: dot * 1.2 + CGFloat(k) * dot * 1.7, y: dot * 1.2, width: dot, height: dot)
                    d.cornerRadius = dot / 2
                    d.backgroundColor = color
                    w.addSublayer(d)
                }
                var rng = SeededRandom(seed: UInt64(frame.minX))
                for k in 0..<lines {
                    let bar = CALayer()
                    let width = frame.width * CGFloat.random(in: 0.35...0.85, using: &rng)
                    bar.frame = CGRect(x: frame.width * 0.07, y: dot * 4.5 + CGFloat(k) * dot * 2.6, width: width, height: dot * 0.9)
                    bar.cornerRadius = dot * 0.45
                    bar.backgroundColor = dark ? CGColor(gray: 1, alpha: 0.12) : CGColor(gray: 0, alpha: 0.1)
                    w.addSublayer(bar)
                }
                root.addSublayer(w)
            }
            window(CGRect(x: size.width * 0.06, y: size.height * 0.12, width: size.width * 0.42, height: size.height * 0.55), dark: false, lines: 9)
            window(CGRect(x: size.width * 0.52, y: size.height * 0.2, width: size.width * 0.42, height: size.height * 0.5), dark: true, lines: 7)
        }
    }
}

/// Renders a layer tree offscreen into raw BGRA pixels, reusing one texture.
@MainActor
private final class FrameRenderer {
    private let size: CGSize
    private let queue: MTLCommandQueue
    private let texture: MTLTexture
    private let renderer: CARenderer

    init?(size: CGSize) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width),
                                                                  height: Int(size.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.size = size
        self.queue = queue
        self.texture = texture
        renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
        renderer.bounds = CGRect(origin: .zero, size: size)
    }

    func render(_ layer: CALayer) -> Data? {
        renderer.layer = layer
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

        let width = Int(size.width), height = Int(size.height), rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        // Texture rows run bottom-up; flip for the video.
        var flipped = Data(count: bytes.count)
        flipped.withUnsafeMutableBytes { out in
            bytes.withUnsafeBytes { input in
                for row in 0..<height {
                    let src = input.baseAddress! + (height - 1 - row) * rowBytes
                    (out.baseAddress! + row * rowBytes).copyMemory(from: src, byteCount: rowBytes)
                }
            }
        }
        return flipped
    }
}
