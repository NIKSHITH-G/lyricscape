export const VERSION = "0.1.0";
export const DMG_SIZE = "1.6 MB";
export const REPO = "NIKSHITH-G/lyricscape";
export const GITHUB_URL = `https://github.com/${REPO}`;
export const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Lyricscape.dmg`;
export const RELEASES_URL = `${GITHUB_URL}/releases`;
export const SITE_URL = "https://getlyricscape.vercel.app";
export const KAERU_URL = "https://getkaeru.vercel.app";

/** Brand colours, matching the app's Settings window. */
export const COLORS = {
  pink: "#FF2A6D",
  violet: "#8B5CF6",
} as const;

export const STYLES: { id: string; name: string; summary: string; detail: string }[] = [
  { id: "constellation", name: "Constellation", summary: "Words become linked neon stars",
    detail: "Every sung word lands as a star, joined to the last by a line of light. Big words flare with a shockwave, and the sky fills with stardust as the song goes on." },
  { id: "kinetic", name: "Kinetic", summary: "Words slam in, music-video style",
    detail: "One huge word at a time, spinning in with motion blur and a screen shake." },
  { id: "karaoke", name: "Karaoke", summary: "Colour sweeps across each word",
    detail: "The classic, done properly: a glowing fill sweeps through each word as it's sung." },
  { id: "rain", name: "Rain", summary: "Words fall and pile up",
    detail: "Words drop from the top as they're sung, land with a squash and stack up." },
  { id: "orbit", name: "Orbit", summary: "Rings of words circle the centre",
    detail: "Each line is a slowly turning ring around a glowing core, drifting outward as it ages." },
  { id: "typewriter", name: "Typewriter", summary: "Monospace terminal, typed live",
    detail: "A terminal typing the lyrics character by character, with a blinking block cursor." },
  { id: "glitch", name: "Glitch", summary: "RGB split, jitter and scanlines",
    detail: "Every word hits with chromatic aberration, a displaced slice and a scanline flash." },
  { id: "particles", name: "Particles", summary: "Words form from, and burst into, particles",
    detail: "Words assemble from a swarm of particles, then burst apart when the line ends." },
  { id: "minimal", name: "Minimal", summary: "One soft line in a corner",
    detail: "A single quiet line tucked in a corner, for when you're working." },
];

export const SHORTCUTS: { keys: string[]; label: string }[] = [
  { keys: ["⌃", "⌥", "⌘", "L"], label: "Show or hide the lyrics" },
  { keys: ["⌃", "⌥", "⌘", "S"], label: "Stage mode" },
  { keys: ["⌃", "⌥", "⌘", "N"], label: "Next style" },
  { keys: ["⌘", "⇧", "D"], label: "Move to the next screen" },
];

/** Original lyrics written for the in-browser demo (the same demo song the app ships). */
export const DEMO_SONG: { start: number; words: string[] }[] = [
  { start: 0.6, words: ["City", "lights", "are", "humming", "in", "the", "dark"] },
  { start: 4.2, words: ["Every", "signal", "finds", "its", "way", "home"] },
  { start: 7.8, words: ["We", "are", "satellites", "in", "orbit"] },
  { start: 11.2, words: ["Burning", "brighter", "than", "the", "summer", "sky"] },
  { start: 14.8, words: ["Spinning", "slowly", "through", "the", "electric", "night"] },
  { start: 18.6, words: ["Don't", "let", "the", "morning", "take", "the", "stars", "away"] },
];
export const DEMO_LENGTH = 22.6;
