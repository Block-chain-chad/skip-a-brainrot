"""Code-synthesized cartoon SFX demo pack for Skip a Brainrot.

Pure-stdlib waveform synthesis (no numpy). 44.1 kHz, 16-bit mono WAVs.
Each function returns a list of float samples in [-1, 1].
"""
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).parent

random.seed(1337)  # deterministic — re-running produces identical files


def env_decay(i, n, curve=5.0):
    """Fast-attack exponential decay envelope."""
    t = i / n
    return math.exp(-curve * t)


def write_wav(name, samples, peak=0.8):
    m = max(abs(s) for s in samples) or 1.0
    scaled = [s / m * peak for s in samples]
    path = OUT / name
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in scaled))
    print(f"wrote {path.name}  ({len(samples)/SR*1000:.0f} ms)")


def ui_click_pop(ms=90):
    """Soft cartoon 'tup' — sine sweep 900->500 Hz, fast decay."""
    n = int(SR * ms / 1000)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = 900 * (500 / 900) ** t          # exponential sweep down
        phase += 2 * math.pi * f / SR
        s = math.sin(phase) * env_decay(i, n, 6.0)
        out.append(s)
    return out


def panel_open_bloop(ms=140):
    """Bubble bloop — rising 280->1150 Hz chirp with a breathy onset."""
    n = int(SR * ms / 1000)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = 280 * (1150 / 280) ** t         # exponential sweep up
        phase += 2 * math.pi * f / SR
        s = math.sin(phase)
        s += 0.35 * math.sin(2 * phase)     # 2nd harmonic = juicier
        if i < n * 0.04:                    # tiny noise tick at the lips
            s += random.uniform(-0.5, 0.5) * (1 - i / (n * 0.04))
        # bump envelope: swell then release (reads as a bubble bursting)
        env = math.sin(math.pi * min(t / 0.85, 1.0)) ** 0.7
        out.append(s * env)
    return out


def coin_collect(ms=170):
    """Arcade coin duotone (660 -> 990 Hz) — deliberately NOT bell-like:
    short notes, hard cutoff, square-ish timbre, zero long ring."""
    n = int(SR * ms / 1000)
    out = []
    split = int(n * 0.38)
    for i in range(n):
        if i < split:
            f, j, m_len = 660.0, i, split
        else:
            f, j, m_len = 990.0, i - split, n - split
        ph = 2 * math.pi * f * j / SR
        # square-ish: fundamental + odd harmonics, capped
        s = math.sin(ph) + 0.33 * math.sin(3 * ph) + 0.2 * math.sin(5 * ph)
        out.append(s * env_decay(j, m_len, 3.5))
    return out


def splash_cartoon(ms=300):
    """Stylized splash — 200 Hz 'plunk' + noise burst through a falling
    one-pole lowpass (bright spray -> dull water)."""
    n = int(SR * ms / 1000)
    out, lp = [], 0.0
    for i in range(n):
        t = i / n
        # one-pole lowpass whose cutoff falls over time
        alpha = 0.55 * (1 - t) + 0.06 * t
        lp += alpha * (random.uniform(-1, 1) - lp)
        s = lp * env_decay(i, n, 4.5)
        if t < 0.25:                        # the plunk under the spray
            s += 0.6 * math.sin(2 * math.pi * 200 * i / SR) * (1 - t / 0.25)
        out.append(s)
    return out


def fusion_sting(ms=650):
    """Rising 4-note power-up arpeggio (C5-E5-G5-C6), short notes,
    hard stops — celebratory without being a chime."""
    notes = [523.25, 659.25, 783.99, 1046.5]
    n = int(SR * ms / 1000)
    per = n // len(notes)
    out = []
    for k, f in enumerate(notes):
        for j in range(per):
            ph = 2 * math.pi * f * j / SR
            s = math.sin(ph) + 0.3 * math.sin(2 * ph)
            out.append(s * env_decay(j, per, 4.0))
    return out


if __name__ == "__main__":
    write_wav("demo_uiClick_pop.wav", ui_click_pop())
    write_wav("demo_panelOpen_bloop.wav", panel_open_bloop())
    write_wav("demo_cash_coin.wav", coin_collect())
    write_wav("demo_splash_cartoon.wav", splash_cartoon())
    write_wav("demo_fusion_sting.wav", fusion_sting())
