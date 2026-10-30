import Image from "next/image";
import {
  ArrowRight, AudioLines, Check, Download, Film, Smartphone, Keyboard, Languages, Layers, MonitorSmartphone,
  MousePointerClick, Palette, ShieldCheck, Timer, Zap,
} from "lucide-react";
import ConstellationDemo from "./components/ConstellationDemo";
import CopyButton from "./components/CopyButton";
import { DMG_SIZE, DOWNLOAD_URL, GITHUB_URL, KAERU_URL, RELEASES_URL, SHORTCUTS, STYLES, VERSION } from "./site";

function GitHubMark({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M12 .5C5.73.5.75 5.48.75 11.75c0 4.97 3.22 9.18 7.69 10.67.56.1.77-.24.77-.54v-1.9c-3.13.68-3.79-1.51-3.79-1.51-.51-1.3-1.25-1.65-1.25-1.65-1.02-.7.08-.69.08-.69 1.13.08 1.72 1.16 1.72 1.16 1 1.72 2.63 1.22 3.27.93.1-.73.39-1.22.71-1.5-2.5-.28-5.13-1.25-5.13-5.57 0-1.23.44-2.24 1.16-3.03-.12-.28-.5-1.43.11-2.98 0 0 .95-.3 3.1 1.16a10.8 10.8 0 0 1 5.64 0c2.15-1.46 3.1-1.16 3.1-1.16.61 1.55.23 2.7.11 2.98.72.79 1.16 1.8 1.16 3.03 0 4.33-2.64 5.28-5.15 5.56.4.35.76 1.03.76 2.08v3.09c0 .3.2.65.78.54 4.46-1.49 7.68-5.7 7.68-10.67C23.25 5.48 18.27.5 12 .5Z" />
    </svg>
  );
}

function DownloadButton({ large = false }: { large?: boolean }) {
  return (
    <a className={`btn btn-primary ${large ? "btn-large" : ""}`} href={DOWNLOAD_URL}>
      <Download size={large ? 20 : 16} />
      <span className="btn-stack">
        <span>Download for macOS</span>
        {large && <small>v{VERSION} · {DMG_SIZE} · Apple silicon</small>}
      </span>
    </a>
  );
}

const FEATURES = [
  { icon: Timer, title: "In time, to the millisecond",
    text: "Reads Spotify's position directly and interpolates between readings — drift stays within a couple of milliseconds, and seeks re-sync instantly." },
  { icon: Palette, title: "A new colour every play",
    text: "Every song — and every replay — gets its own neon palette. Or pull colours from the album art, or lock in a favourite." },
  { icon: AudioLines, title: "Feels the beat",
    text: "Turn on audio reactivity and glows, stars and particles pulse with the kick and bass. It only ever listens to Spotify." },
  { icon: Languages, title: "Romanization & translation",
    text: "Sing along to K-pop, J-pop and C-pop: a romanized line (or an on-device translation) appears under the lyrics." },
  { icon: Layers, title: "Stage mode",
    text: "A black stage behind your windows, like a live wallpaper visualizer — your apps stay on top." },
  { icon: MousePointerClick, title: "Never in the way",
    text: "The overlay floats over everything, even full-screen apps, but every click goes straight through to what's underneath." },
  { icon: MonitorSmartphone, title: "Any screen",
    text: "Laptop or external monitor — pick one in Settings, or flip between them with ⌘⇧D." },
  { icon: Zap, title: "Featherweight",
    text: "Built on Core Animation, so the GPU does the drawing: a few percent of CPU while playing, next to nothing when paused." },
];

const FAQ = [
  { q: "Do I need Spotify Premium or an API key?",
    a: "No. Lyricscape reads the Spotify desktop app directly on your Mac — no login, no API key, and it works with free accounts too." },
  { q: "Where do the lyrics come from?",
    a: "From LRCLIB, a free community library of time-synced lyrics. They're cached on your Mac, so songs you've played before work offline." },
  { q: "Why does macOS say it can't check the app?",
    a: "Lyricscape isn't signed with a paid Apple developer certificate yet, so macOS asks you to approve it once. Follow step 3 above — it takes ten seconds." },
  { q: "Does it record my screen?",
    a: "No. The optional beat reactivity uses macOS's screen-capture framework only to hear Spotify's audio — nothing on your screen is captured, and it's off until you turn it on." },
  { q: "The lyrics are slightly early or late.",
    a: "Community lyric files vary. Nudge them in 0.1 s steps from the menu bar or Settings → Lyrics & Sound." },
  { q: "Does it work on Intel Macs?",
    a: "The download is built for Apple silicon. Intel users can build it from source with the Command Line Tools — see the README on GitHub." },
];

export default function Home() {
  return (
    <>
      <div className="aurora" aria-hidden />
      <header className="nav">
        <a className="brand" href="#top">
          <Image src="/icon.png" alt="" width={30} height={30} priority />
          <span>Lyricscape</span>
        </a>
        <nav>
          <a href="#video">Video</a>
          <a href="#styles">Styles</a>
          <a href="#features">Features</a>
          <a href="#install">Install</a>
          <a href="#faq">FAQ</a>
          <a href={GITHUB_URL} aria-label="GitHub" className="icon-link"><GitHubMark /></a>
          <a className="btn btn-primary btn-small" href={DOWNLOAD_URL}>Download</a>
        </nav>
      </header>

      <main id="top">
        <section className="hero">
          <a className="pill" href={RELEASES_URL}>
            <span className="pill-tag">New</span> v{VERSION} · Nine styles, one sky <ArrowRight size={14} />
          </a>
          <h1>
            Your lyrics,<br />
            <span className="gradient-text">written across the sky.</span>
          </h1>
          <p className="lead">
            Lyricscape turns whatever&apos;s playing in Spotify into animated lyrics across your whole screen —
            perfectly in time with the music, right on your Mac.
          </p>
          <div className="cta">
            <DownloadButton large />
            <a className="btn btn-ghost" href={GITHUB_URL}><GitHubMark /> View on GitHub</a>
          </div>
          <ul className="checks">
            <li><Check size={14} /> Free &amp; open source</li>
            <li><Check size={14} /> No account or API key</li>
            <li><Check size={14} /> Works with Spotify Free</li>
            <li><Check size={14} /> macOS 14+</li>
          </ul>

          <div className="mac">
            <div className="mac-bar">
              <span className="dots"><i /><i /><i /></span>
              <span className="mac-menu"><b></b> Spotify <span>File</span> <span>Edit</span> <span>View</span></span>
              <span className="mac-now">♪ Neon Satellites — Lyricscape Demo</span>
            </div>
            <div className="mac-screen">
              <ConstellationDemo />
            </div>
          </div>
          <p className="caption">A live, in-browser replay of the Constellation style. On your Mac it follows whatever Spotify is playing.</p>
        </section>

        <section className="stats">
          <div><strong>9</strong><span>styles</span></div>
          <div><strong>60</strong><span>fps</span></div>
          <div><strong>±2ms</strong><span>sync</span></div>
          <div><strong>0</strong><span>accounts</span></div>
        </section>

        <section id="video" className="section">
          <h2>See it in 40 seconds.</h2>
          <p className="section-lead">Every style, playing the built-in demo song — rendered by the app itself.</p>
          <div className="video-frame">
            <video src="/video/lyricscape-demo.mp4" poster="/video/poster.jpg" controls autoPlay muted loop playsInline
                   preload="metadata" aria-label="Lyricscape demo video" />
          </div>
          <div className="video-links">
            <a className="btn btn-ghost btn-small" href="/video/lyricscape-demo.mp4" download><Film size={14} /> Download video (16:9)</a>
            <a className="btn btn-ghost btn-small" href="/video/lyricscape-demo-vertical.mp4" download><Smartphone size={14} /> Vertical for Reels &amp; TikTok (9:16)</a>
          </div>
        </section>

        <section id="styles" className="section">
          <h2>Nine ways to see a song.</h2>
          <p className="section-lead">Flip between them with ⌃⌥⌘N, or pick one in Settings with a live preview.</p>
          <div className="gallery">
            {STYLES.map((style, i) => (
              <figure key={style.id} className={i === 0 ? "feature-card wide" : "feature-card"}>
                <div className="shot">
                  <Image src={`/styles/${style.id}.webp`} alt={`${style.name} style`} width={1600} height={1000}
                         sizes={i === 0 ? "(max-width: 900px) 100vw, 66vw" : "(max-width: 900px) 100vw, 33vw"} />
                </div>
                <figcaption>
                  <h3>{style.name}</h3>
                  <p>{i === 0 ? style.detail : style.summary}</p>
                </figcaption>
              </figure>
            ))}
          </div>
        </section>

        <section id="features" className="section">
          <h2>Thought through, down to the details.</h2>
          <div className="features">
            {FEATURES.map(({ icon: Icon, title, text }) => (
              <div key={title} className="feature">
                <span className="feature-icon"><Icon size={18} /></span>
                <h3>{title}</h3>
                <p>{text}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="section shortcuts-section">
          <div className="shortcuts-copy">
            <span className="feature-icon"><Keyboard size={18} /></span>
            <h2>Summon it from anywhere.</h2>
            <p className="section-lead left">Global shortcuts work in every app. Change them to anything you like in Settings.</p>
          </div>
          <ul className="shortcuts">
            {SHORTCUTS.map((s) => (
              <li key={s.label}>
                <span>{s.label}</span>
                <span className="keys">{s.keys.map((k) => <kbd key={k}>{k}</kbd>)}</span>
              </li>
            ))}
          </ul>
        </section>

        <section id="install" className="section">
          <h2>Installed in under a minute.</h2>
          <p className="section-lead">
            No App Store, no account. Lyricscape isn&apos;t signed with a paid Apple certificate yet, so macOS asks you to approve it once.
          </p>
          <div className="steps">
            <div className="step">
              <span className="step-num">1</span>
              <h3>Download</h3>
              <p>Get <b>Lyricscape.dmg</b> ({DMG_SIZE}). Everything it needs is inside.</p>
              <a className="btn btn-primary btn-small" href={DOWNLOAD_URL}><Download size={14} /> Download</a>
            </div>
            <div className="step">
              <span className="step-num">2</span>
              <h3>Drag to Applications</h3>
              <p>Open the DMG and drag Lyricscape onto the Applications folder.</p>
            </div>
            <div className="step">
              <span className="step-num">3</span>
              <h3>Approve once</h3>
              <p>Open Lyricscape and click <b>Done</b>. Then go to <b>System Settings → Privacy &amp; Security</b>, scroll down and click <b>Open Anyway</b>.</p>
            </div>
          </div>
          <div className="terminal-hint">
            <span>Prefer Terminal? This does the same as Open Anyway:</span>
            <code>xattr -dr com.apple.quarantine /Applications/Lyricscape.app</code>
            <CopyButton text="xattr -dr com.apple.quarantine /Applications/Lyricscape.app" />
          </div>
          <div className="permission-note">
            <ShieldCheck size={18} />
            <p>
              On first launch, click <b>OK</b> when macOS asks to let Lyricscape read Spotify. Then press play — and <b>⌃⌥⌘L</b> to bring up the lyrics.
            </p>
          </div>
        </section>

        <section id="faq" className="section">
          <h2>Questions</h2>
          <div className="faq">
            {FAQ.map((item) => (
              <details key={item.q}>
                <summary>{item.q}</summary>
                <p>{item.a}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="final">
          <Image src="/icon.png" alt="" width={96} height={96} />
          <h2>Press play. Watch the sky.</h2>
          <DownloadButton large />
        </section>
      </main>

      <footer className="footer">
        <div>
          <b>Lyricscape</b> · Made by NIKSHITH G · MIT licence · Lyrics from <a href="https://lrclib.net">LRCLIB</a>
        </div>
        <div className="footer-links">
          <a href={GITHUB_URL}>GitHub</a>
          <a href={RELEASES_URL}>Releases</a>
          <a href={KAERU_URL}>Also by me: Kaeru 🐸</a>
        </div>
      </footer>
    </>
  );
}
