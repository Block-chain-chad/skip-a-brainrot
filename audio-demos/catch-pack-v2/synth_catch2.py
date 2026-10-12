"""Catch-stinger pack v2 for Skip a Brainrot.

v1 was thin: additive saws, white-noise convolution reverb, no dynamics, no EQ.
This pass uses the techniques that actually make a stinger sound produced:

  * FM synthesis for bells/mallets (inharmonic ratios) instead of stacked sines
  * three-part impacts - click transient / tonal body / sub drop - each with its
    own envelope, glued with saturation and a fast compressor
  * risers that DUCK to near-silence ~50 ms before the hit. That gap is the
    single biggest trick in reward audio; the hit lands twice as hard.
  * supersaw pads (7 detuned voices) through an envelope-swept resonant filter
    and a chorus, not raw saw stacks
  * a proper reverb (early reflections + multi-band decaying tail), not white noise
  * EQ: high-pass everything except the sub, notch the 350-500 Hz mud
  * bus compression + soft limiting so the quiet parts stay present

Stereo, 44.1 kHz. These are 2D UI sounds so stereo is correct; keep positional
world sounds (splashes) mono.
"""
import numpy as np
from scipy import signal
from pathlib import Path
import wave, struct

SR = 44100
OUT = Path("/home/claude/catch-pack-v2")
OUT.mkdir(exist_ok=True)
rng = np.random.default_rng(7)

C2, C3, Eb3, G3, Bb3 = 65.41, 130.81, 155.56, 196.00, 233.08
C4, Eb4, F4, G4, Bb4 = 261.63, 311.13, 349.23, 392.00, 466.16
C5, Eb5, F5, G5, Bb5 = 523.25, 622.25, 698.46, 783.99, 932.33
C6, Eb6, G6, C7 = 1046.50, 1244.51, 1567.98, 2093.00


# ================================================================= primitives

def t_of(ms):
    return np.arange(int(SR * ms / 1000)) / SR


def n_of(ms):
    return int(SR * ms / 1000)


def expdec(n, curve=5.0):
    return np.exp(-curve * np.linspace(0, 1, n))


def ar(n, attack_ms=2, curve=5.0):
    a = min(n_of(attack_ms), n)
    env = expdec(n, curve)
    env[:a] *= np.linspace(0, 1, a) ** 0.6
    return env


def noise(n):
    return rng.uniform(-1, 1, n)


def bw(x, lo, hi, order=2):
    ny = SR / 2
    lo = max(20.0, min(lo, ny * 0.98))
    hi = max(lo * 1.05, min(hi, ny * 0.98))
    b, a = signal.butter(order, [lo / ny, hi / ny], "band")
    return signal.lfilter(b, a, x)


def lop(x, f, order=2):
    b, a = signal.butter(order, min(f, SR / 2.05) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hip(x, f, order=2):
    b, a = signal.butter(order, max(20, min(f, SR / 2.05)) / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def notch(x, f, q=1.2):
    b, a = signal.iirnotch(f / (SR / 2), q)
    return signal.lfilter(b, a, x)


def sweep_phase(f_curve):
    return np.cumsum(2 * np.pi * f_curve / SR)


def fm_bell(f, ms, ratio=1.41, index=6.0, idx_decay=9.0, amp_decay=5.0):
    """2-operator FM. Inharmonic ratio -> bell/metal. Index envelope decays
    faster than amplitude, so it starts bright and settles into a pure tone."""
    n = n_of(ms)
    t = np.arange(n) / SR
    idx = index * expdec(n, idx_decay)
    mod = np.sin(2 * np.pi * f * ratio * t) * idx
    return np.sin(2 * np.pi * f * t + mod) * ar(n, 1.5, amp_decay)


def mallet(f, ms, bright=3.0):
    """Short wooden/plastic tick. FM with a low index and a noise chiff."""
    n = n_of(ms)
    tone = fm_bell(f, ms, ratio=2.7, index=bright, idx_decay=22.0, amp_decay=11.0)
    chiff = bw(noise(n), 2200, 6500) * expdec(n, 70.0) * 0.20
    return tone + chiff


def supersaw(f, ms, voices=7, detune_cents=14):
    """Detuned saw stack. Phase-randomised so it doesn't phase-cancel."""
    n = n_of(ms)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i in range(voices):
        c = (i - (voices - 1) / 2) / max(1, (voices - 1) / 2) * detune_cents
        ff = f * (2 ** (c / 1200))
        ph = rng.uniform(0, 1)
        out += signal.sawtooth(2 * np.pi * ff * t + ph * 2 * np.pi)
    return out / voices


def chorus(x, depth_ms=6.0, rate=0.7, mix=0.45):
    n = len(x)
    t = np.arange(n) / SR
    d = (depth_ms / 1000) * SR * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t))
    idx = np.arange(n) - d
    wet = np.interp(idx, np.arange(n), x, left=0, right=0)
    return x * (1 - mix) + wet * mix


def reverb(x, seconds=1.4, mix=0.28, pre_ms=18, damp=5200):
    """Early reflections + band-damped exponential tail. Much less metallic
    than convolving with flat white noise."""
    n = int(SR * seconds)
    tail = noise(n) * np.exp(-np.linspace(0, 6.5, n))
    tail = lop(tail, damp)
    # dampen highs progressively down the tail
    tail *= np.linspace(1.0, 0.25, n)
    ir = np.zeros(n)
    for d_ms, g in [(11, .5), (19, .38), (27, .3), (41, .22), (58, .16)]:
        i = int(SR * d_ms / 1000)
        if i < n:
            ir[i] += g
    ir += tail * 0.7
    ir[:n_of(pre_ms)] = 0
    ir /= np.max(np.abs(ir)) or 1
    wet = signal.fftconvolve(x, ir)[: len(x) + n]
    wet /= np.max(np.abs(wet)) or 1
    dry = np.pad(x, (0, len(wet) - len(x)))
    return dry * (1 - mix) + wet * mix


def compress(x, thresh=0.28, ratio=4.5, atk_ms=3, rel_ms=90):
    """Feed-forward peak compressor with a smoothed envelope."""
    env = np.abs(signal.lfilter([1], [1, -0.999], np.abs(x)) * 0.001)
    env = np.maximum(env, np.abs(x))
    a = np.exp(-1 / (SR * atk_ms / 1000))
    r = np.exp(-1 / (SR * rel_ms / 1000))
    sm = np.zeros_like(env)
    prev = 0.0
    for i, v in enumerate(env):
        co = a if v > prev else r
        prev = co * prev + (1 - co) * v
        sm[i] = prev
    gain = np.ones_like(sm)
    over = sm > thresh
    gain[over] = (thresh + (sm[over] - thresh) / ratio) / np.maximum(sm[over], 1e-9)
    return x * gain


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def limit(x, ceiling=0.94):
    p = np.max(np.abs(x)) or 1
    if p > ceiling:
        x = np.tanh(x / p * 1.9) / np.tanh(1.9) * ceiling
    return x


def shelf(x, f, gain_db, kind="low"):
    g = 10 ** (gain_db / 20)
    b, a = signal.butter(1, min(f, SR / 2.05) / (SR / 2), "low" if kind == "low" else "high")
    band = signal.lfilter(b, a, x)
    return x + band * (g - 1)


def glue(x):
    """The bus chain everything goes through."""
    x = hip(x, 26)
    x = notch(x, 420, q=1.1)            # pull the mud
    x = shelf(x, 110, 3.5, "low")       # put the weight back
    x = shelf(x, 9000, -7.0, "high")    # air rolloff - kills the digital hiss
    x = lop(x, 15000, order=2)
    x = compress(x, 0.26, 5.0, 2, 80)
    x = sat(x, 1.35)
    return limit(x)


def fit(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mixdown(*parts):
    n = max(len(p) for p in parts)
    return sum(fit(p, n) for p in parts)


def at(x, delay_ms):
    return np.pad(x, (n_of(delay_ms), 0))


def widen(x, ms=11, amount=0.75):
    """Haas-style width. Impacts stay centred because we only widen the
    layers we pass through here."""
    d = n_of(ms)
    l = x
    r = np.pad(x, (d, 0))[: len(x)] * (1 - 0.12) + x * 0.12
    return l, l * (1 - amount) + r * amount


def to_stereo(center, wide=None):
    if wide is None:
        return center, center.copy()
    n = max(len(center), len(wide))
    c, w = fit(center, n), fit(wide, n)
    wl, wr = widen(w)
    return c + fit(wl, n), c + fit(wr, n)


def write(name, left, right=None, peak_db=-0.8, max_ms=None):
    if right is None:
        right = left
    n = max(len(left), len(right))
    L, R = glue(fit(left, n)), glue(fit(right, n))
    if max_ms:
        n2 = n_of(max_ms)
        L, R = L[:n2], R[:n2]
    p = max(np.max(np.abs(L)), np.max(np.abs(R))) or 1
    g = (10 ** (peak_db / 20)) / p
    L, R = L * g, R * g
    f = n_of(6)
    if len(L) > f:
        ramp = np.linspace(1, 0, f)
        L[-f:] *= ramp
        R[-f:] *= ramp
    inter = np.empty(len(L) * 2)
    inter[0::2], inter[1::2] = L, R
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(np.clip(v, -1, 1) * 32767)) for v in inter))
    print(f"  {name:16s} {len(L)/SR*1000:6.0f} ms")


# ================================================================= components

def impact(size=1.0, ms=520):
    """Three-part hit. Click / body / sub, each independently enveloped."""
    n = n_of(ms)
    t = np.arange(n) / SR
    click = bw(noise(n), 1800, 7500) * expdec(n, 150.0) * 0.42
    bodyf = 380 * (95 / 380) ** np.linspace(0, 1, n)
    body = np.sin(sweep_phase(bodyf)) * ar(n, 1, 13.0) * 0.75
    body += bw(noise(n), 180, 1400) * expdec(n, 26.0) * 0.4
    subf = (130 * (34 / 130) ** np.linspace(0, 1, n)) * (0.85 + 0.35 * size)
    sub = np.sin(sweep_phase(subf)) * ar(n, 1, 4.2) * (0.95 + 1.35 * size)
    x = click + body * (0.6 + 0.5 * size) + sub
    return compress(sat(x, 1.7 + size), 0.2, 7.0, 1, 60)


def riser(ms=1100, f0=70, f1=900, duck_ms=55):
    """Sweeping bandpass noise + pitch sweep, ducking to near-silence just
    before the end so the impact that follows has room to land."""
    n = n_of(ms)
    ramp = np.linspace(0, 1, n) ** 1.7
    cf = f0 * (f1 / f0) ** ramp
    nz = noise(n)
    # time-varying bandpass via short overlapping blocks
    out = np.zeros(n)
    blk = 1024
    for i in range(0, n, blk):
        j = min(i + blk, n)
        c = cf[(i + j) // 2]
        out[i:j] = bw(nz[i:j], c * 0.6, min(c * 2.4, 8000))[: j - i]
    tone = np.sin(sweep_phase(cf * 0.5)) * 0.5
    x = (out * 0.8 + tone) * (ramp ** 1.3)
    d = n_of(duck_ms)
    if d < n:
        x[-d:] *= np.linspace(1, 0.04, d) ** 2
    return x


def pad(freqs, ms=1600, cutoff0=380, cutoff1=3400):
    """Supersaw chord through an envelope-swept lowpass, then chorus."""
    n = n_of(ms)
    x = sum(supersaw(f, ms) for f in freqs) / len(freqs)
    env = np.linspace(0, 1, n) ** 0.45
    cf = cutoff0 + (cutoff1 - cutoff0) * env
    out = np.zeros(n)
    blk = 2048
    for i in range(0, n, blk):
        j = min(i + blk, n)
        out[i:j] = lop(x[i:j], cf[(i + j) // 2])[: j - i]
    amp = np.minimum(np.linspace(0, 1, n) * 6, 1) * np.exp(-2.0 * np.linspace(0, 1, n))
    return chorus(out * amp, 7.0, 0.45, 0.4)


def shimmer(ms=900, density=18, lo=C6, spread=2.4):
    """High FM grains. No low end, so it layers over anything."""
    n = n_of(ms)
    out = np.zeros(n)
    for _ in range(density):
        s = int(rng.uniform(0, 0.55) * n)
        dur = rng.uniform(90, 260)
        f = lo * rng.uniform(1.0, spread)
        g = fm_bell(f, dur, ratio=3.5, index=2.2, idx_decay=14, amp_decay=8)
        seg = out[s : s + len(g)]
        out[s : s + len(seg)] += g[: len(seg)] * rng.uniform(0.25, 0.9)
    return lop(hip(out, 1900), 8500)


def arp(freqs, note_ms, ratio=1.41, index=5.0, decay=6.0, overlap=0.55):
    """Bell arpeggio with overlapping tails so it rings rather than stutters."""
    step = n_of(note_ms * (1 - overlap))
    total = step * (len(freqs) - 1) + n_of(note_ms * 2)
    out = np.zeros(total)
    for i, f in enumerate(freqs):
        g = fm_bell(f, note_ms * 2, ratio, index, 10.0, decay)
        out[i * step : i * step + len(g)] += g * (0.75 + 0.05 * i)
    return out


# ================================================================= the ladder

def t1_common():
    """~110 ms. A tick. Not a reward - you hear this hundreds of times."""
    return mallet(C5, 110, bright=2.4) * 0.9


def t2_uncommon():
    """~260 ms. Two mallets, a breath of room."""
    a = mallet(C5, 110, 2.6)
    b = mallet(G5, 150, 3.2)
    return reverb(mixdown(a, at(b, 95)), 0.35, 0.14, 10)


def t3_rare():
    """~520 ms. Three-note bell rise. First time it rings."""
    x = arp([C5, Eb5, G5], 150, ratio=1.41, index=4.0, decay=6.5)
    return reverb(x, 0.6, 0.22, 14)


def t4_epic():
    """~950 ms. Bell run + soft impact underneath + shimmer tail."""
    x = arp([C5, Eb5, G5, C6], 145, index=5.0, decay=5.5)
    body = mixdown(x, impact(0.35, 300) * 0.4)
    wide = at(shimmer(600, 12, C6, 1.9) * 0.5, 380)
    l, r = to_stereo(body, wide)
    return reverb(l, 0.9, 0.26, 16), reverb(r, 0.9, 0.26, 16)


def t5_legend():
    """~1.5 s. Short riser -> impact -> bell melody over a pad."""
    ris = riser(420, 90, 620, 45) * 0.5
    hit = at(impact(0.6, 460), 420)
    bells = at(arp([C5, Eb5, G5, Bb5], 155, index=5.5, decay=5.0), 470)
    pd = at(pad([C3, Eb3, G3], 1000, 340, 2600) * 0.4, 430)
    center = mixdown(ris, hit, bells * 0.85)
    wide = mixdown(pd, at(shimmer(700, 14, C6, 2.0) * 0.55, 620))
    l, r = to_stereo(center, wide)
    return reverb(l, 1.3, 0.3, 18), reverb(r, 1.3, 0.3, 18)


def t6_mythic():
    """~2.1 s. Longer riser, heavier hit, pad carries the tail."""
    ris = riser(700, 75, 800, 55) * 0.62
    hit = at(impact(0.85, 620), 700)
    bells = at(arp([C5, Eb5, G5, C6, Eb6], 150, index=6.0, decay=4.5), 760)
    pd = at(pad([C3, Eb3, G3, C4], 1500, 320, 3000) * 0.5, 710)
    center = mixdown(ris, hit, bells * 0.8)
    wide = mixdown(pd, at(shimmer(1000, 18, C6, 2.2) * 0.6, 900))
    l, r = to_stereo(center, wide)
    return reverb(l, 1.7, 0.33, 20), reverb(r, 1.7, 0.33, 20)


def t7_secret():
    """~2.9 s. The tier that announces your name to the server."""
    ris = riser(1150, 60, 1000, 65) * 0.72
    hit = at(impact(1.0, 780), 1150)
    bells = at(arp([C5, G5, C6, Eb6, G6], 160, index=6.5, decay=4.0), 1220)
    pd = at(pad([C3, Eb3, G3, Bb3, C4], 1700, 300, 3400) * 0.58, 1160)
    center = mixdown(ris, hit, bells * 0.78)
    wide = mixdown(pd,
                   at(shimmer(1300, 22, C6, 2.4) * 0.65, 1300),
                   at(shimmer(900, 12, C7, 1.6) * 0.4, 1900))
    l, r = to_stereo(center, wide)
    return reverb(l, 2.2, 0.36, 22), reverb(r, 2.2, 0.36, 22)


def t8_god():
    """~4.0 s. Five of these exist in the whole game. Let it be enormous."""
    ris = riser(1700, 50, 1200, 75) * 0.85
    hit = mixdown(at(impact(1.0, 900), 1700), at(impact(0.7, 700), 1760) * 0.5)
    bells = at(arp([C5, G5, C6, Eb6, G6, C7], 165, index=7.0, decay=3.6), 1780)
    pd = at(pad([C2, C3, Eb3, G3, C4, Eb4], 2200, 260, 3800) * 0.65, 1710)
    lift = at(np.sin(sweep_phase(np.linspace(C5, C6, n_of(1600)))) *
              np.minimum(np.linspace(0, 1, n_of(1600)) * 3, 1) *
              expdec(n_of(1600), 2.0) * 0.22, 1800)
    center = mixdown(ris, hit, bells * 0.75, lift)
    wide = mixdown(pd,
                   at(shimmer(1600, 26, C6, 2.6) * 0.7, 1850),
                   at(shimmer(1200, 16, C7, 1.8) * 0.45, 2500),
                   at(shimmer(900, 10, C7, 1.4) * 0.3, 3100))
    l, r = to_stereo(center, wide)
    return reverb(l, 2.8, 0.4, 24), reverb(r, 2.8, 0.4, 24)


# ================================================================= layers

def l_bighit():
    return reverb(impact(1.0, 700), 0.9, 0.2, 14)


def l_sparkle():
    x = shimmer(800, 20, C6, 2.4)
    l, r = to_stereo(np.zeros_like(x), x)
    return reverb(l, 1.0, 0.3, 12), reverb(r, 1.0, 0.3, 12)


def l_drama():
    return riser(1500, 45, 900, 70)


if __name__ == "__main__":
    print("ladder:")
    write("catchCommon", t1_common(), max_ms=130)
    write("catchUncommon", t2_uncommon(), max_ms=300)
    write("catchRare", t3_rare(), max_ms=620)
    write("catchEpic", *t4_epic(), max_ms=1100)
    write("catchLegend", *t5_legend(), max_ms=1700)
    write("catchMythic", *t6_mythic(), max_ms=2300)
    write("catchSecret", *t7_secret(), max_ms=3100)
    write("catchGod", *t8_god(), max_ms=4300)
    print("layers:")
    write("catchBigHit", l_bighit(), max_ms=700)
    write("catchSparkle", *l_sparkle(), max_ms=900)
    write("catchDrama", l_drama(), max_ms=1500)
