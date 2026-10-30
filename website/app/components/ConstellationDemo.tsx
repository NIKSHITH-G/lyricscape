"use client";

import { useEffect, useRef } from "react";
import { DEMO_LENGTH, DEMO_SONG } from "../site";

/** Neon hues for successive loops: like the app, every "play" gets a new colour. */
const HUES = [334, 192, 268, 24, 152, 48, 300];

type Word = { text: string; start: number; end: number; key: boolean; x: number; y: number; below: boolean; size: number };
type Line = { words: Word[]; start: number; end: number };

const STOP = new Set(["the", "are", "its", "in", "we", "let", "than", "way", "don't"]);

function seeded(seed: number) {
  // Scramble the seed first: neighbouring seeds would otherwise start out nearly equal.
  let s = Math.imul(seed ^ 0x9e3779b9, 0x85ebca6b) >>> 0;
  s = Math.imul(s ^ (s >>> 13), 0xc2b2ae35) >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
}

/** Lays one line out left to right in a zig-zag, keywords on the centre line. */
function layout(ctx: CanvasRenderingContext2D, index: number, w: number, h: number, loop: number): Line {
  const line = DEMO_SONG[index];
  const next = DEMO_SONG[index + 1]?.start ?? DEMO_LENGTH;
  const rand = seeded(index * 97 + loop * 13 + 7);
  const base = Math.min(w, h) * 0.05;
  const longest = Math.max(...line.words.filter((x) => !STOP.has(x.toLowerCase())).map((x) => x.length));
  const sung = (next - line.start) * 0.8;
  const total = line.words.reduce((sum, x) => sum + x.length + 2, 0);

  let t = line.start;
  let x = 0;
  let side = rand() < 0.5 ? 1 : -1;
  const words: Word[] = line.words.map((text) => {
    const key = text.length === longest && text.length >= 5;
    const size = key ? base * 1.7 : base;
    ctx.font = `${key ? 800 : 600} ${size}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
    const width = ctx.measureText(text).width;
    const duration = (sung * (text.length + 2)) / total;
    if (!key && rand() < 0.75) side = -side;
    const y = key ? 0 : side * base * (0.9 + rand() * 1.1);
    const word: Word = { text, start: t, end: t + duration, key, x: x + width / 2, y, below: y < 0, size };
    t += duration;
    x += width + base * (1.1 + rand() * 0.8);
    return word;
  });
  // Centre the shape, nudging alternate lines up and down.
  const span = x - base;
  const scale = Math.min(1, (w * 0.86) / span);
  const offsetY = h * (0.5 + (index % 2 === 0 ? -0.1 : 0.1));
  for (const word of words) {
    word.x = w / 2 + (word.x - span / 2) * scale;
    word.y = offsetY + word.y;
    word.size *= scale;
  }
  return { words, start: line.start, end: next };
}

export default function ConstellationDemo() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    let w = 0, h = 0, dpr = 1;
    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = canvas.clientWidth;
      h = canvas.clientHeight;
      canvas.width = w * dpr;
      canvas.height = h * dpr;
      cache.clear();
    };
    const cache = new Map<string, Line>();
    const stars = Array.from({ length: 140 }, (_, i) => {
      const r = seeded(i + 1);
      return { x: r(), y: r(), size: 0.4 + r() * 1.3, phase: r() * 6.28, speed: 0.4 + r() * 1.4 };
    });
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);

    const origin = performance.now() / 1000;
    let frame = 0;

    const draw = () => {
      const now = reduced ? origin + 9.2 : performance.now() / 1000;
      const elapsed = now - origin;
      const loop = Math.floor(elapsed / DEMO_LENGTH);
      const t = elapsed % DEMO_LENGTH;
      const hue = HUES[loop % HUES.length];
      const glow = `hsl(${hue} 100% 58%)`;
      const core = `hsl(${hue} 100% 95%)`;
      const lineColor = `hsl(${(hue + 30) % 360} 95% 64%)`;

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);

      // Twinkling background stars.
      for (const s of stars) {
        ctx.globalAlpha = 0.15 + 0.35 * (0.5 + 0.5 * Math.sin(now * s.speed + s.phase));
        ctx.fillStyle = "#fff";
        ctx.fillRect(s.x * w, s.y * h, s.size, s.size);
      }
      ctx.globalAlpha = 1;

      for (let i = 0; i < DEMO_SONG.length; i++) {
        const key = `${i}:${loop}`;
        if (!cache.has(key)) cache.set(key, layout(ctx, i, w, h, loop));
        const line = cache.get(key)!;
        if (t < line.start - 0.4 || t > line.end + 0.9) continue;
        const out = Math.max(0, Math.min(1, (t - line.end) / 0.9));
        const textOut = Math.min(1, out * 2.5);

        line.words.forEach((word, k) => {
          const age = t - word.start;
          const star = { x: word.x, y: word.below ? word.y + word.size * 0.55 : word.y - word.size * 0.55 };
          // Link from the previous star, drawn by a comet just before the word lands.
          if (k > 0) {
            const prev = line.words[k - 1];
            const from = { x: prev.x, y: prev.below ? prev.y + prev.size * 0.55 : prev.y - prev.size * 0.55 };
            const draw = Math.max(0, Math.min(1, (age + 0.15) / 0.35));
            const ease = 1 - Math.pow(1 - draw, 3);
            if (draw > 0) {
              const start = Math.min(ease, out * 1.5);
              ctx.strokeStyle = lineColor;
              ctx.globalAlpha = 0.85 * (1 - out);
              ctx.lineWidth = 1.4;
              ctx.shadowColor = glow;
              ctx.shadowBlur = 6;
              ctx.beginPath();
              ctx.moveTo(from.x + (star.x - from.x) * start, from.y + (star.y - from.y) * start);
              ctx.lineTo(from.x + (star.x - from.x) * ease, from.y + (star.y - from.y) * ease);
              ctx.stroke();
              if (draw < 1) {
                ctx.globalAlpha = Math.sin(draw * Math.PI);
                ctx.fillStyle = core;
                ctx.shadowBlur = 14;
                ctx.beginPath();
                ctx.arc(from.x + (star.x - from.x) * ease, from.y + (star.y - from.y) * ease, 2.6, 0, 6.28);
                ctx.fill();
              }
            }
          }
          ctx.globalAlpha = 1 - out;
          if (age < 0) {
            // Ghost star for a word still to come.
            ctx.fillStyle = core;
            ctx.globalAlpha = 0.2 * (1 - out);
            ctx.shadowBlur = 0;
            ctx.beginPath();
            ctx.arc(star.x, star.y, 1.8, 0, 6.28);
            ctx.fill();
            return;
          }
          const flash = Math.exp(-age * 3.5);
          const pop = Math.min(1, age / 0.25);
          const current = age >= 0 && t < word.end + 0.05;

          // Star, glint and (for keywords) a shockwave ring.
          ctx.shadowColor = glow;
          ctx.shadowBlur = 10 + 22 * flash;
          ctx.fillStyle = core;
          ctx.beginPath();
          ctx.arc(star.x, star.y, (word.key ? 3.8 : 2.8) * (pop + 0.8 * flash), 0, 6.28);
          ctx.fill();
          if (current || flash > 0.1) {
            const r = (word.key ? 22 : 15) * (0.5 + 0.7 * flash + (current ? 0.3 : 0));
            ctx.save();
            ctx.translate(star.x, star.y);
            ctx.rotate(now * 0.6 + k);
            ctx.globalAlpha = (current ? 0.6 + 0.4 * flash : 0.9 * flash) * (1 - out);
            ctx.beginPath();
            for (let p = 0; p < 8; p++) {
              const a = (p * Math.PI) / 4;
              const rr = p % 2 === 0 ? r : r * 0.09;
              ctx[p === 0 ? "moveTo" : "lineTo"](Math.cos(a) * rr, Math.sin(a) * rr);
            }
            ctx.closePath();
            ctx.fill();
            ctx.restore();
          }
          if (word.key && age < 1.1) {
            const p = age / 1.1;
            ctx.globalAlpha = 0.9 * (1 - p) * (1 - p);
            ctx.strokeStyle = glow;
            ctx.lineWidth = 2 * (1 - p);
            ctx.beginPath();
            ctx.arc(star.x, star.y, 4 + 70 * (1 - Math.pow(1 - p, 3)), 0, 6.28);
            ctx.stroke();
          }

          // Label: a saturated halo behind a white-hot core, like a neon tube.
          const alpha = Math.min(1, age / 0.12) * (current ? 1 : 0.88) * (1 - textOut);
          const rise = (1 - pop) * word.size * 0.25;
          ctx.font = `${word.key ? 800 : 600} ${word.size}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
          ctx.textAlign = "center";
          ctx.textBaseline = word.below ? "bottom" : "top";
          const ty = word.below ? word.y - word.size * 0.05 + rise : word.y + word.size * 0.05 + rise;
          ctx.globalAlpha = alpha * Math.min(1, (current ? 0.7 : 0.4) + 0.6 * flash);
          ctx.shadowBlur = word.size * 0.6;
          ctx.fillStyle = glow;
          ctx.fillText(word.text, word.x, ty);
          ctx.globalAlpha = alpha;
          ctx.shadowBlur = word.size * 0.15;
          ctx.fillStyle = word.key ? core : `hsl(${hue} 100% 90%)`;
          ctx.fillText(word.text, word.x, ty);
        });
      }
      ctx.globalAlpha = 1;
      ctx.shadowBlur = 0;
      if (!reduced) frame = requestAnimationFrame(draw);
    };
    frame = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, []);

  return <canvas ref={canvasRef} className="demo-canvas" aria-label="Animated demo of the Constellation style" />;
}
