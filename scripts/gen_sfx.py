#!/usr/bin/env python3
"""Generate the game sound effects into assets/audio/ (44.1kHz 16-bit mono WAV).

Pure-stdlib synthesis so the assets are reproducible without extra deps.

- pop.wav    — balloon pop: noise crack + fast downward thump (~150ms)
- boom.wav   — bomb explosion: crack + sub-sine + rumbling brown noise (~850ms)
- tick.wav   — countdown tick (last 3 seconds)
- go.wav     — round-start "GO!" (two quick rising notes)
- fanfare.wav— round-over jingle (rising major arpeggio + sparkle)
- whoosh.wav — balloon escaping upward (soft rising airy sweep)

Run: python3 scripts/gen_sfx.py
"""
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"
OUT_DIR.mkdir(parents=True, exist_ok=True)
rng = random.Random(42)  # deterministic assets


def write_wav(name, samples, peak=0.92):
    m = max(abs(s) for s in samples) or 1.0
    scale = peak / m
    # short fade-out to avoid click at the end
    n_fade = min(len(samples), int(0.02 * SR))
    data = bytearray()
    for i, s in enumerate(samples):
        v = s * scale
        if i >= len(samples) - n_fade:
            v *= (len(samples) - i) / n_fade
        data += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
    path = OUT_DIR / name
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(data))
    print(f"wrote {path} ({len(samples)/SR:.2f}s)")


def env_exp(t, tau):
    return math.exp(-t / tau)


def pop():
    dur = 0.15
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        crack = (rng.random() * 2 - 1) * env_exp(t, 0.016)
        f = 330.0 * math.exp(-t / 0.03) + 60.0  # fast downward sweep
        phase += 2 * math.pi * f / SR
        thump = math.sin(phase) * env_exp(t, 0.045) * 0.7
        out.append(crack + thump)
    write_wav("pop.wav", out)


def boom():
    dur = 0.85
    n = int(SR * dur)
    out = []
    brown = 0.0
    phase = 0.0
    for i in range(n):
        t = i / SR
        crack = (rng.random() * 2 - 1) * env_exp(t, 0.012) * 0.9
        brown = 0.985 * brown + (rng.random() * 2 - 1) * 0.09
        rumble = brown * env_exp(t, 0.30) * 2.2
        f = 55.0 * math.exp(-t / 0.9) + 28.0
        phase += 2 * math.pi * f / SR
        sub = math.sin(phase) * env_exp(t, 0.32) * 0.8
        # soft clip for punch
        s = crack + rumble + sub
        out.append(math.tanh(1.6 * s))
    write_wav("boom.wav", out)


def tick():
    dur = 0.09
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * 1250 * t) * env_exp(t, 0.018)
        s += math.sin(2 * math.pi * 2500 * t) * env_exp(t, 0.010) * 0.4
        out.append(s)
    write_wav("tick.wav", out, peak=0.6)


def go():
    # A5 then E6 — short, bright, energetic
    notes = [(880.0, 0.0, 0.10), (1318.5, 0.10, 0.22)]
    dur = 0.35
    n = int(SR * dur)
    out = [0.0] * n
    for freq, start, length in notes:
        s0 = int(start * SR)
        for i in range(s0, min(n, s0 + int(length * SR) + int(0.1 * SR))):
            t = (i - s0) / SR
            v = (math.sin(2 * math.pi * freq * t)
                 + 0.3 * math.sin(2 * math.pi * freq * 2 * t))
            out[i] += v * env_exp(t, length) * 0.5
    write_wav("go.wav", out, peak=0.75)


def fanfare():
    # C major up: C5 E5 G5 C6, overlapping soft square-ish tones + sparkle
    notes = [(523.25, 0.00), (659.25, 0.11), (783.99, 0.22), (1046.5, 0.33)]
    dur = 1.1
    n = int(SR * dur)
    out = [0.0] * n
    for freq, start in notes:
        s0 = int(start * SR)
        for i in range(s0, n):
            t = (i - s0) / SR
            v = (math.sin(2 * math.pi * freq * t)
                 + 0.35 * math.sin(2 * math.pi * freq * 2 * t)
                 + 0.15 * math.sin(2 * math.pi * freq * 3 * t))
            out[i] += v * env_exp(t, 0.28) * 0.35
    # sparkle noise burst at the top note
    s0 = int(0.33 * SR)
    for i in range(s0, min(n, s0 + int(0.25 * SR))):
        t = (i - s0) / SR
        out[i] += (rng.random() * 2 - 1) * env_exp(t, 0.06) * 0.12
    write_wav("fanfare.wav", out, peak=0.8)


def sizzle():
    # A rival popped your balloon: short fiery crackle (burning-up feel) —
    # bright noise bursts through a rising band, quick decay.
    dur = 0.4
    n = int(SR * dur)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        # crackle: sparse impulse bursts
        burst = (rng.random() * 2 - 1) if rng.random() < 0.22 else 0.0
        alpha = 0.35 + 0.3 * (t / dur)
        prev = prev + alpha * (burst - prev)
        hiss = (rng.random() * 2 - 1) * 0.25
        out.append((prev * 2.2 + hiss) * env_exp(t, 0.16))
    write_wav("sizzle.wav", out, peak=0.7)


def whoosh():
    dur = 0.5
    n = int(SR * dur)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        # low-passed noise with rising cutoff → airy rising whoosh
        alpha = 0.02 + 0.25 * (t / dur)
        prev = prev + alpha * ((rng.random() * 2 - 1) - prev)
        amp = math.sin(math.pi * t / dur)  # swell in and out
        out.append(prev * amp * 2.0)
    write_wav("whoosh.wav", out, peak=0.5)


pop()
boom()
tick()
go()
fanfare()
sizzle()
whoosh()
