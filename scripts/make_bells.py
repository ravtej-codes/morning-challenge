"""Synthesise soft singing-bowl style bells as WAV files (stdlib only).

Usage: python scripts/make_bells.py App/Resources
"""
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 22050
# (frequency ratio, relative amplitude, decay seconds) — inharmonic partials of a bowl
PARTIALS = [(1.0, 1.0, 6.0), (2.76, 0.45, 3.5), (5.40, 0.20, 2.0), (8.93, 0.08, 1.2), (0.5, 0.15, 7.0)]


def strike(base_hz, seconds):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        attack = min(1.0, t / 0.01)
        s = sum(a * math.exp(-t / d) * math.sin(2 * math.pi * base_hz * r * t + r) for r, a, d in PARTIALS)
        # slight beating, like a real bowl
        s *= 1 + 0.06 * math.sin(2 * math.pi * 1.7 * t)
        out.append(s * attack)
    return out


def render(path, strikes, gap, tail, base_hz, volume):
    total = int(RATE * (gap * (strikes - 1) + tail))
    buf = [0.0] * total
    for k in range(strikes):
        start = int(RATE * gap * k)
        for i, v in enumerate(strike(base_hz, tail)):
            if start + i < total:
                buf[start + i] += v
    peak = max(abs(v) for v in buf) or 1
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * volume * v / peak)) for v in buf))


if __name__ == "__main__":
    out = Path(sys.argv[1])
    render(out / "soft_bells.wav", strikes=2, gap=4.0, tail=7.0, base_hz=432, volume=0.55)
    render(out / "deadline_bells.wav", strikes=5, gap=4.0, tail=7.0, base_hz=432, volume=0.8)
    render(out / "lost_bell.wav", strikes=1, gap=1.0, tail=6.0, base_hz=288, volume=0.7)
