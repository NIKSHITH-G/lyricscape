"""Synthesises the promo video's soundtrack: an original synthwave cue, 112 BPM,
built from scratch (no samples), timed to the video's scenes.

Usage: python3 scripts/assets/make-soundtrack.py <out.wav>

Timeline (must match PromoVideo.swift):
  0.0  title card   — pad swell, bell sparkle, riser
  3.2  desktop      — drop: drums, bass, pad
  8.0  styles       — arpeggio joins; a soft whoosh on every style change (every 3.3 s)
  37.7 outro        — drums stop, final chord rings out
  41.5 end
"""
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 48_000
LENGTH = 41.5
BPM = 112
BEAT = 60 / BPM
DROP, ARP_IN, OUTRO = 3.2, 8.0, 37.7
SCENES = [8.0 + 3.3 * k for k in range(10)]  # style changes, up to the outro

rng = np.random.default_rng(7)
N = int(LENGTH * SR)
t_all = np.arange(N) / SR


def bus():
    return np.zeros((N, 2))


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def lowpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, "low", fs=SR, output="sos"), x, axis=0)


def highpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, "high", fs=SR, output="sos"), x, axis=0)


def bandpass(x, low, high, order=2):
    return sosfilt(butter(order, [low, high], "band", fs=SR, output="sos"), x, axis=0)


def place(target, sound, start, pan=0.0, gain=1.0):
    """Mix a mono sound into a stereo bus at `start` seconds, equal-power panned."""
    i = int(start * SR)
    if i >= N:
        return
    sound = sound[: N - i] * gain
    angle = (pan + 1) * np.pi / 4
    target[i : i + len(sound), 0] += sound * np.cos(angle)
    target[i : i + len(sound), 1] += sound * np.sin(angle)


def envelope(n, attack, release, sustain_time=None):
    t = np.arange(n) / SR
    env = np.minimum(1, t / max(attack, 1e-4))
    if sustain_time is not None:
        env *= np.where(t > sustain_time, np.exp(-(t - sustain_time) / max(release, 1e-4)), 1)
    else:
        env *= np.exp(-t / max(release, 1e-4))
    return env


def saw(freq, n, detune_cents=0.0):
    t = np.arange(n) / SR
    f = freq * 2 ** (detune_cents / 1200)
    phase = rng.random()
    return 2 * ((t * f + phase) % 1) - 1


# Chords per bar from the drop: Am – F – C – G (vi–IV–I–V in C major).
CHORDS = [
    {"bass": 33, "notes": [57, 60, 64, 69]},  # Am
    {"bass": 29, "notes": [53, 57, 60, 65]},  # F
    {"bass": 36, "notes": [60, 64, 67, 72]},  # C
    {"bass": 31, "notes": [55, 59, 62, 67]},  # G
]
BAR = 4 * BEAT


def chord_at(time):
    if time < DROP:
        return CHORDS[0] if time < 1.6 else CHORDS[1]
    return CHORDS[int((time - DROP) // BAR) % 4]


# ---------------------------------------------------------------- drums

drums = bus()
kick_times = []
beat = DROP
while beat < OUTRO - 1e-6:
    kick_times.append(beat)
    beat += BEAT


def kick():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    freq = 46 + 110 * np.exp(-t * 28)
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 7)
    click = lowpass(rng.standard_normal(n) * np.exp(-t * 300), 4000)
    return np.tanh(1.6 * (body + 0.25 * click))


def clap():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 900, 6500)
    # Three quick bursts then a tail, like hands clapping slightly apart.
    bursts = sum(np.where(t >= d, np.exp(-(t - d) * 90), 0) for d in (0, 0.009, 0.019))
    return noise * (0.6 * bursts + 0.5 * np.exp(-t * 16)) + 0.25 * np.sin(2 * np.pi * 185 * t) * np.exp(-t * 30)


def hat(open_hat=False):
    n = int((0.32 if open_hat else 0.06) * SR)
    t = np.arange(n) / SR
    return highpass(rng.standard_normal(n), 7500) * np.exp(-t * (9 if open_hat else 70))


K, C, H, OH = kick(), clap(), hat(), hat(True)
for k, time in enumerate(kick_times):
    place(drums, K, time, gain=0.62)
    if k % 4 in (1, 3):
        place(drums, C, time, pan=0.0, gain=0.6)
    place(drums, H, time + BEAT / 2, pan=0.25, gain=0.36)
    place(drums, H, time, pan=-0.2, gain=0.14)
    if k % 8 == 7:
        place(drums, OH, time + BEAT / 2, pan=0.3, gain=0.18)

# Sidechain: everything melodic ducks under each kick, the classic synthwave pump.
duck = np.ones(N)
for time in kick_times:
    i = int(time * SR)
    seg = np.arange(min(int(0.4 * SR), N - i)) / SR
    duck[i : i + len(seg)] = np.minimum(duck[i : i + len(seg)], 1 - 0.6 * np.exp(-seg / 0.11))
duck2 = duck[:, None]

# ---------------------------------------------------------------- bass

bass = bus()
step = DROP
while step < OUTRO - 1e-6:
    root = chord_at(step)["bass"]
    n = int(BEAT / 2 * SR * 0.95)
    tone = 0.6 * saw(hz(root + 12), n) + 0.5 * np.sin(2 * np.pi * hz(root + 12) * np.arange(n) / SR)
    # Let some harmonics through so the bass still reads on phone speakers.
    tone = lowpass(tone, 900) * envelope(n, 0.004, 0.18)
    place(bass, tone, step, gain=0.34)
    step += BEAT / 2

# ---------------------------------------------------------------- pad

pad = bus()
segments = [(0.0, 1.6), (1.6, DROP)]
b = DROP
while b < OUTRO - 1e-6:
    segments.append((b, min(b + BAR, OUTRO)))
    b += BAR
for start, end in segments:
    notes = chord_at(start + 0.01)["notes"]
    n = int((end - start + 0.6) * SR)
    for k, note in enumerate(notes):
        for detune, pan in ((-9, -0.7), (0, 0), (9, 0.7)):
            tone = saw(hz(note), n, detune)
            tone = lowpass(tone, 2800 if start >= DROP else 1400) * envelope(n, 0.35 if start >= DROP else 1.2, 0.5, end - start)
            place(pad, tone, start, pan=pan, gain=0.06)

# ---------------------------------------------------------------- arpeggio

arp = bus()
pattern = [0, 1, 2, 3, 2, 1, 2, 3]
s = ARP_IN
k = 0
while s < OUTRO - 1e-6:
    notes = chord_at(s)["notes"]
    note = notes[pattern[k % len(pattern)]] + 12
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    tone = np.sign(np.sin(2 * np.pi * hz(note) * t)) * 0.5 + np.sin(2 * np.pi * hz(note) * t)
    tone = lowpass(tone, 5200) * np.exp(-t * 14)
    place(arp, tone, s, pan=0.35 * np.sin(k * 0.7), gain=0.15)
    s += BEAT / 4
    k += 1
# Ping-pong delay on the arp (dotted eighth).
delay = int(BEAT * 0.75 * SR)
echo = np.zeros_like(arp)
echo[delay:, 0] = arp[:-delay, 1] * 0.45
echo[2 * delay :, 1] = arp[: -2 * delay, 0] * 0.3
arp += echo

# ---------------------------------------------------------------- effects

fx = bus()


def bell(midi, length=2.8):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    partials = [(1, 1.0, 2.2), (2.76, 0.5, 3.5), (5.4, 0.25, 6), (8.93, 0.12, 9)]
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for r, a, d in partials) * np.minimum(1, t / 0.003)


def swell(length, low, high, gain=1.0):
    """Filtered-noise whoosh that rises then cuts."""
    n = int(length * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    chunks = 24
    for c in range(chunks):  # sweep the band upward in small steps
        a, b2 = c * n // chunks, (c + 1) * n // chunks
        centre = low * (high / low) ** (c / chunks)
        out[a:b2] = bandpass(noise[a:b2], centre * 0.7, min(centre * 1.4, SR / 2 - 100))
    return out * (t / length) ** 2 * gain


# Title: sparkle as the logo appears, a riser into the drop, a crash on it.
for when, note, pan in ((0.35, 88, -0.3), (0.62, 93, 0.3), (0.95, 100, 0.0)):
    place(fx, bell(note), when, pan=pan, gain=0.06)
place(fx, swell(1.9, 300, 9000), DROP - 1.9, gain=0.22)
crash_n = int(2.6 * SR)
crash = highpass(rng.standard_normal(crash_n), 4000) * np.exp(-np.arange(crash_n) / SR * 2.2)
place(fx, crash, DROP, pan=-0.2, gain=0.16)
place(fx, crash, DROP + 0.004, pan=0.2, gain=0.16)

# A soft whoosh and a tiny chime into every style change.
for k, when in enumerate(SCENES):
    place(fx, swell(0.45, 800, 7000), when - 0.45, pan=(-0.4 if k % 2 else 0.4), gain=0.1)
    place(fx, bell(84 + [0, 3, 7, 10][k % 4], 1.2), when, pan=(0.4 if k % 2 else -0.4), gain=0.025)

# Outro: a big C(add9) chord and bells, ringing out.
for note, pan in ((36, 0), (43, -0.3), (48, 0.3), (52, -0.5), (55, 0.5), (62, 0)):
    n = int((LENGTH - OUTRO) * SR)
    for detune in (-8, 8):
        tone = lowpass(saw(hz(note), n, detune), 1800) * envelope(n, 0.02, 1.4, 0.4)
        place(fx, tone, OUTRO, pan=pan, gain=0.05)
for when, note in ((OUTRO, 84), (OUTRO + 0.25, 91), (OUTRO + 0.5, 96)):
    place(fx, bell(note, 3.5), when, gain=0.06)
place(fx, crash, OUTRO, gain=0.14)

# ---------------------------------------------------------------- mix

def reverb(x, seconds=2.2, mix=0.32):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    impulse = rng.standard_normal((n, 2)) * np.exp(-t * 6.5 / seconds)[:, None]
    impulse = lowpass(impulse, 5000)
    wet = np.stack([fftconvolve(x[:, ch], impulse[:, ch])[: len(x)] for ch in range(2)], axis=1)
    wet /= np.max(np.abs(wet)) + 1e-9
    return x + mix * wet * np.max(np.abs(x))


melodic = (pad + bass * 1.0 + arp) * duck2
mix = drums + melodic + fx
mix = reverb(mix * 1.0, mix=0.18) + reverb(pad * duck2 + arp + fx, mix=0.25) * 0.35
mix = highpass(mix, 28)

# Gentle master: fade in/out, soft clip, normalise to -1 dBFS.
fade_in = np.minimum(1, t_all / 0.4)
fade_out = np.clip((LENGTH - t_all) / 1.4, 0, 1)
mix *= (fade_in * fade_out)[:, None]
mix = np.tanh(mix * 1.4 / (np.max(np.abs(mix)) + 1e-9))
mix *= 0.89 / np.max(np.abs(mix))

wavfile.write(sys.argv[1], SR, (mix * 32767).astype(np.int16))
rms = 20 * np.log10(np.sqrt(np.mean(mix ** 2)) + 1e-12)
print(f"wrote {sys.argv[1]}: {LENGTH:.1f} s, RMS {rms:.1f} dBFS")
