#!/usr/bin/env python3
"""Procedurally synthesize Minecraft-style ambient music and soft SFX for Desert Oasis."""

from __future__ import annotations

import math
import os
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
OUT_DIR = Path(__file__).resolve().parents[1] / "DesertOasis" / "Resources" / "Audio"


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def write_wav(path: Path, samples: list[float], sample_rate: int = SAMPLE_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(clamp(s) * 32767))
        wf.writeframes(frames)
    print(f"wrote {path.name} ({len(samples) / sample_rate:.1f}s)")


def envelope(t: float, attack: float, release: float, duration: float) -> float:
    if t < 0 or t > duration:
        return 0.0
    if t < attack:
        return t / attack if attack > 0 else 1.0
    if t > duration - release:
        return max(0.0, (duration - t) / release) if release > 0 else 1.0
    return 1.0


def sine(freq: float, t: float) -> float:
    return math.sin(2.0 * math.pi * freq * t)


def soft_noise(t: float, seed: float = 0.0) -> float:
    # Cheap deterministic-ish soft noise from stacked sines.
    return (
        0.35 * sine(37.0 + seed, t)
        + 0.25 * sine(91.0 + seed * 0.7, t)
        + 0.2 * sine(173.0 + seed * 1.3, t)
        + 0.15 * sine(311.0 + seed * 0.4, t)
    )


def note_hz(midi: int) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def render_note(
    samples: list[float],
    start: float,
    duration: float,
    midi: int,
    amp: float,
    warmth: float = 0.15,
) -> None:
    freq = note_hz(midi)
    n0 = int(start * SAMPLE_RATE)
    n1 = min(len(samples), int((start + duration) * SAMPLE_RATE))
    for i in range(n0, n1):
        t = (i - n0) / SAMPLE_RATE
        env = envelope(t, 0.08, max(0.2, duration * 0.45), duration)
        # Soft piano-ish: fundamental + quiet harmonics, slight detune for width.
        tone = (
            sine(freq, t)
            + warmth * 0.35 * sine(freq * 2.002, t)
            + warmth * 0.12 * sine(freq * 3.01, t)
            + 0.08 * sine(freq * 0.5, t)
        )
        samples[i] += amp * env * tone * 0.35


def render_pad(
    samples: list[float],
    start: float,
    duration: float,
    midis: list[int],
    amp: float,
) -> None:
    n0 = int(start * SAMPLE_RATE)
    n1 = min(len(samples), int((start + duration) * SAMPLE_RATE))
    for i in range(n0, n1):
        t = (i - n0) / SAMPLE_RATE
        env = envelope(t, 1.2, 2.0, duration)
        chord = 0.0
        for m in midis:
            f = note_hz(m)
            chord += sine(f, t) + 0.2 * sine(f * 1.997, t)
        chord /= max(1, len(midis))
        samples[i] += amp * env * chord * 0.22


def normalize(samples: list[float], peak: float = 0.85) -> None:
    m = max(abs(s) for s in samples) or 1.0
    scale = peak / m
    for i in range(len(samples)):
        samples[i] *= scale


def make_music(
    name: str,
    duration: float,
    root_midi: int,
    scale: list[int],
    pad_amps: tuple[float, float],
    note_amp: float,
    seed: int,
) -> None:
    rng = random.Random(seed)
    samples = [0.0] * int(duration * SAMPLE_RATE)

    # Two long overlapping pads
    pad_a = [root_midi + i for i in (0, 7, 12)]
    pad_b = [root_midi + i for i in (scale[2], scale[4], 12 + scale[1])]
    render_pad(samples, 0.0, duration * 0.72, pad_a, pad_amps[0])
    render_pad(samples, duration * 0.28, duration * 0.7, pad_b, pad_amps[1])

    # Sparse melodic notes (Minecraft-ish)
    t = rng.uniform(2.0, 5.0)
    while t < duration - 4.0:
        midi = root_midi + rng.choice(scale) + 12 * rng.choice([0, 0, 1])
        note_dur = rng.uniform(1.8, 4.2)
        render_note(samples, t, note_dur, midi, note_amp * rng.uniform(0.7, 1.0))
        # Occasional soft dual note
        if rng.random() < 0.35:
            harmony = midi + rng.choice([3, 4, 7, -5])
            render_note(samples, t + 0.15, note_dur * 0.9, harmony, note_amp * 0.45)
        t += rng.uniform(2.5, 7.5)

    # Very quiet air / shimmer
    for i in range(len(samples)):
        tt = i / SAMPLE_RATE
        samples[i] += 0.012 * soft_noise(tt, seed=float(seed)) * envelope(tt, 2.0, 2.0, duration)

    normalize(samples, 0.72)
    write_wav(OUT_DIR / name, samples)


def make_sfx_ui_tap() -> None:
    dur = 0.08
    samples = [0.0] * int(dur * SAMPLE_RATE)
    for i in range(len(samples)):
        t = i / SAMPLE_RATE
        env = envelope(t, 0.002, 0.05, dur)
        samples[i] = env * (0.35 * sine(880, t) + 0.15 * sine(1760, t))
    normalize(samples, 0.55)
    write_wav(OUT_DIR / "sfx_ui_tap.wav", samples)


def make_sfx_collect() -> None:
    dur = 0.55
    samples = [0.0] * int(dur * SAMPLE_RATE)
    # Soft splash: descending blips + filtered noise burst
    for k, midi in enumerate([76, 72, 69, 64]):
        render_note(samples, 0.02 + k * 0.07, 0.25, midi, 0.55, warmth=0.4)
    for i in range(len(samples)):
        t = i / SAMPLE_RATE
        burst = envelope(t, 0.01, 0.25, 0.35) * soft_noise(t * 8.0, 3.0) * 0.18
        samples[i] += burst
    normalize(samples, 0.7)
    write_wav(OUT_DIR / "sfx_collect.wav", samples)


def make_sfx_deliver() -> None:
    dur = 0.7
    samples = [0.0] * int(dur * SAMPLE_RATE)
    # Pour: rising mid tones + soft rumble
    for k in range(8):
        midi = 55 + k
        render_note(samples, 0.04 + k * 0.06, 0.28, midi, 0.28, warmth=0.5)
    for i in range(len(samples)):
        t = i / SAMPLE_RATE
        rumble = envelope(t, 0.05, 0.25, dur) * soft_noise(t * 3.0, 9.0) * 0.12
        samples[i] += rumble
    normalize(samples, 0.68)
    write_wav(OUT_DIR / "sfx_deliver.wav", samples)


def make_sfx_dialogue() -> None:
    dur = 0.45
    samples = [0.0] * int(dur * SAMPLE_RATE)
    render_note(samples, 0.0, 0.4, 71, 0.55, warmth=0.25)
    render_note(samples, 0.08, 0.38, 78, 0.4, warmth=0.2)
    normalize(samples, 0.6)
    write_wav(OUT_DIR / "sfx_dialogue.wav", samples)


def make_sfx_toast() -> None:
    dur = 0.35
    samples = [0.0] * int(dur * SAMPLE_RATE)
    render_note(samples, 0.0, 0.28, 67, 0.45)
    render_note(samples, 0.1, 0.28, 74, 0.5)
    render_note(samples, 0.18, 0.3, 79, 0.35)
    normalize(samples, 0.58)
    write_wav(OUT_DIR / "sfx_toast.wav", samples)


def make_sfx_sand_step() -> None:
    """Short soft sand crunch for walking footsteps."""
    dur = 0.18
    samples = [0.0] * int(dur * SAMPLE_RATE)
    rng = random.Random(91)
    for i in range(len(samples)):
        t = i / SAMPLE_RATE
        env = envelope(t, 0.004, 0.12, dur)
        # Filtered noise burst (sand grains) + low thud
        n = soft_noise(t * 14.0 + rng.random(), seed=12.0)
        thud = sine(95 + 40 * t, t) * envelope(t, 0.002, 0.08, 0.1)
        samples[i] = env * (0.55 * n + 0.28 * thud)
    normalize(samples, 0.65)
    write_wav(OUT_DIR / "sfx_sand_step.wav", samples)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Warm desert dunes — G major-ish pentatonic
    make_music(
        "music_dunes.wav",
        duration=72.0,
        root_midi=55,  # G3
        scale=[0, 2, 4, 7, 9],
        pad_amps=(0.55, 0.4),
        note_amp=0.85,
        seed=11,
    )

    # Cooler oasis — D / A feel
    make_music(
        "music_oasis.wav",
        duration=80.0,
        root_midi=50,  # D3
        scale=[0, 2, 5, 7, 10],
        pad_amps=(0.5, 0.48),
        note_amp=0.8,
        seed=42,
    )

    # Campfire evening — warmer, lower
    make_music(
        "music_campfire.wav",
        duration=68.0,
        root_midi=53,  # F3
        scale=[0, 3, 5, 7, 10],
        pad_amps=(0.6, 0.35),
        note_amp=0.75,
        seed=77,
    )

    make_sfx_ui_tap()
    make_sfx_collect()
    make_sfx_deliver()
    make_sfx_dialogue()
    make_sfx_toast()
    make_sfx_sand_step()
    print(f"done → {OUT_DIR}")


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "--sfx-only":
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        make_sfx_ui_tap()
        make_sfx_collect()
        make_sfx_deliver()
        make_sfx_dialogue()
        make_sfx_toast()
        make_sfx_sand_step()
        print(f"done (sfx) → {OUT_DIR}")
    else:
        main()
