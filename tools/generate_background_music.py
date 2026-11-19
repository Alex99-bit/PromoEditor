#!/usr/bin/env python3
"""Render a short, original, royalty-free instrumental backing track."""

import math
import random
import struct
import wave
from array import array
from pathlib import Path

SAMPLE_RATE = 44_100
BPM = 100
BEAT = 60 / BPM
BARS = 9
DURATION = BARS * 4 * BEAT
FRAME_COUNT = round(SAMPLE_RATE * DURATION)
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "original-upbeat.wav"

left = array("f", [0.0]) * FRAME_COUNT
right = array("f", [0.0]) * FRAME_COUNT
rng = random.Random(71824)

CHORDS = [
    # D, A, B minor, G: a bright, familiar major-key pop progression.
    ([146.83, 185.00, 220.00], 73.42),
    ([110.00, 138.59, 164.81], 55.00),
    ([123.47, 146.83, 185.00], 61.74),
    ([98.00, 123.47, 146.83], 49.00),
]


def add_signal(start: float, duration: float, generator, gain: float, pan: float = 0.0) -> None:
    first = max(0, int(start * SAMPLE_RATE))
    count = min(int(duration * SAMPLE_RATE), FRAME_COUNT - first)
    if count <= 0:
        return
    left_gain = math.sqrt((1 - pan) / 2)
    right_gain = math.sqrt((1 + pan) / 2)
    for i in range(count):
        value = generator(i / SAMPLE_RATE) * gain
        left[first + i] += value * left_gain
        right[first + i] += value * right_gain


def pluck(frequency: float, start: float, gain: float, pan: float = 0.0) -> None:
    duration = 0.32

    def sound(t: float) -> float:
        envelope = (1 - math.exp(-t * 900)) * math.exp(-t * 11)
        phase = 2 * math.pi * frequency * t
        return envelope * (
            math.sin(phase)
            + 0.42 * math.sin(phase * 2.01)
            + 0.18 * math.sin(phase * 3.98)
            + 0.08 * math.sin(phase * 6.02)
        )

    add_signal(start, duration, sound, gain, pan)
    add_signal(start + 0.105, duration * 0.8, sound, gain * 0.15, -pan)
    add_signal(start + 0.205, duration * 0.7, sound, gain * 0.08, pan)


def pad(frequency: float, start: float, duration: float) -> None:
    def sound(t: float) -> float:
        attack = min(1.0, t / 0.22)
        release = min(1.0, max(0.0, (duration - t) / 0.32))
        envelope = attack * release
        phase = 2 * math.pi * frequency * t
        return envelope * (
            0.72 * math.sin(phase)
            + 0.20 * math.sin(phase * 2.003)
            + 0.08 * math.sin(phase * 0.5)
        )

    add_signal(start, duration, sound, 0.026, 0.0)


def bass(frequency: float, start: float) -> None:
    duration = 0.43

    def sound(t: float) -> float:
        envelope = (1 - math.exp(-t * 100)) * math.exp(-t * 5.5)
        phase = 2 * math.pi * frequency * t
        return envelope * (math.sin(phase) + 0.22 * math.sin(phase * 2))

    add_signal(start, duration, sound, 0.16)


def kick(start: float) -> None:
    duration = 0.19

    def sound(t: float) -> float:
        envelope = math.exp(-t * 23)
        phase = 2 * math.pi * (48 * t + 58 * (1 - math.exp(-t * 22)) / 22)
        return envelope * math.sin(phase)

    add_signal(start, duration, sound, 0.24)


def snare(start: float) -> None:
    duration = 0.16
    noise = [rng.uniform(-1, 1) for _ in range(round(duration * SAMPLE_RATE))]

    def sound(t: float) -> float:
        index = min(len(noise) - 1, int(t * SAMPLE_RATE))
        envelope = math.exp(-t * 24)
        body = math.sin(2 * math.pi * 185 * t) * math.exp(-t * 18)
        return envelope * (0.72 * noise[index] + 0.28 * body)

    add_signal(start, duration, sound, 0.065)


def hat(start: float, gain: float = 0.016) -> None:
    duration = 0.045
    noise = [rng.uniform(-1, 1) for _ in range(round(duration * SAMPLE_RATE))]

    def sound(t: float) -> float:
        index = min(len(noise) - 1, int(t * SAMPLE_RATE))
        return noise[index] * math.exp(-t * 75)

    add_signal(start, duration, sound, gain, 0.08)


melody_patterns = [
    [293.66, 369.99, 440.00, 369.99, 440.00, 587.33, 440.00, 369.99],
    [329.63, 440.00, 493.88, 440.00, 493.88, 659.25, 493.88, 440.00],
    [293.66, 369.99, 440.00, 369.99, 440.00, 587.33, 493.88, 440.00],
    [293.66, 392.00, 493.88, 392.00, 493.88, 587.33, 493.88, 392.00],
]

for bar in range(BARS):
    bar_start = bar * 4 * BEAT
    chord, root = CHORDS[bar % len(CHORDS)]
    for note in chord:
        pad(note, bar_start, 4 * BEAT)

    pattern = melody_patterns[bar % len(melody_patterns)]
    for step, note in enumerate(pattern):
        pluck(note, bar_start + step * BEAT / 2, 0.047, -0.18 if step % 2 else 0.18)

    for beat in range(4):
        time = bar_start + beat * BEAT
        if beat in (0, 2):
            kick(time)
            bass(root, time)
        else:
            snare(time)
        hat(time + BEAT / 2, 0.012)
        hat(time + BEAT / 4, 0.008)

# Gentle fade-in/out, then leave enough headroom for social-platform encoding.
for i in range(FRAME_COUNT):
    time = i / SAMPLE_RATE
    fade_in = min(1.0, time / 0.45)
    fade_out = min(1.0, max(0.0, (DURATION - time) / 0.9))
    envelope = fade_in * fade_out
    left[i] *= envelope
    right[i] *= envelope

peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
scale = 0.86 / peak if peak > 0 else 1.0
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUTPUT), "wb") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(SAMPLE_RATE)
    frames = bytearray()
    for l_value, r_value in zip(left, right):
        l_sample = max(-32767, min(32767, round(math.tanh(l_value * scale) * 32767)))
        r_sample = max(-32767, min(32767, round(math.tanh(r_value * scale) * 32767)))
        frames.extend(struct.pack("<hh", l_sample, r_sample))
    wav.writeframes(frames)

print(f"Wrote original {DURATION:.1f}s backing track: {OUTPUT}")
