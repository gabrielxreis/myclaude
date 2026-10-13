"""Synthesizes Cloud's own sounds (originals, not Coucou's): cute chirps, pops and arpeggios.
python3 scripts/make-cloud-sounds.py NotchBuddy/Resources/cloud-sounds"""
import sys, os, wave, struct, math, random
import numpy as np

SR = 48000
out = sys.argv[1] if len(sys.argv) > 1 else "cloud-sounds"
os.makedirs(out, exist_ok=True)
random.seed(7); np.random.seed(7)

def env(n, a=0.005, r=0.08):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4))
    tail = np.clip((t[-1] - t) / max(r, 1e-4), 0, 1)
    return e * tail

def tone(f0, f1, dur, shape="sine", vib=0.0, vibf=7, harm=0.25, a=0.005, r=None):
    n = int(SR * dur); t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / dur)                       # exponential glide
    if vib: f = f * (1 + vib * np.sin(2 * np.pi * vibf * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    w = np.sin(ph) + harm * np.sin(2 * ph) + harm * 0.4 * np.sin(3 * ph)
    if shape == "soft": w = np.tanh(1.4 * w)
    return w * env(n, a, r if r is not None else dur * 0.6)

def noise(dur, lp=0.15, a=0.002, r=None):
    n = int(SR * dur); x = np.random.randn(n)
    y = np.zeros(n); acc = 0.0
    for i in range(n): acc += lp * (x[i] - acc); y[i] = acc
    return y / (np.abs(y).max() + 1e-9) * env(n, a, r if r is not None else dur * 0.8)

def seq(*parts, gap=0.0):
    g = np.zeros(int(SR * gap)); out = []
    for p in parts: out += [p, g]
    return np.concatenate(out)

def mix(*xs):
    n = max(len(x) for x in xs); y = np.zeros(n)
    for x in xs: y[:len(x)] += x
    return y

def note(m): return 440 * 2 ** ((m - 69) / 12)

def chirp(m, dur=0.07, up=1.06): return tone(note(m), note(m) * up, dur, harm=0.18, r=dur * 0.7)

def save(name, x, gain=0.55):
    x = x / (np.abs(x).max() + 1e-9) * gain
    pad = np.zeros(int(SR * 0.02)); x = np.concatenate([x, pad])
    st = np.stack([x, x], 1)
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype("<i2").tobytes())

S = {}
S["tick"]     = chirp(96, 0.035, 1.02)
S["blip"]     = chirp(91, 0.05, 1.08)
S["hover"]    = tone(note(88), note(93), 0.045, harm=0.1, r=0.035) * 0.6
S["pop"]      = tone(320, 980, 0.085, harm=0.3, r=0.06)
S["peek"]     = seq(tone(500, 900, 0.06, r=0.05), tone(700, 1200, 0.06, r=0.05), gap=0.02)
S["open"]     = tone(380, 1150, 0.13, harm=0.25, r=0.09)
S["close"]    = tone(1100, 360, 0.12, harm=0.25, r=0.08)
S["greet"]    = seq(chirp(79, .09), chirp(83, .09), chirp(86, .16, 1.1), gap=0.025)
S["greeting"] = seq(chirp(76, .1), chirp(79, .1), chirp(83, .1), chirp(88, .22, 1.12), gap=0.03)
S["finish"]   = mix(seq(chirp(84, .08), chirp(88, .08), chirp(91, .2, 1.05), gap=0.02), np.concatenate([np.zeros(int(SR*.2)), noise(.25, .5) * .08]))
S["proud"]    = seq(chirp(79, .1), chirp(84, .1), chirp(88, .1), chirp(91, .26, 1.03), gap=0.02)
S["approve"]  = seq(chirp(86, .07), chirp(91, .12, 1.04), gap=0.02)
S["love"]     = seq(tone(note(84), note(88), .14, vib=.012, harm=.15), tone(note(88), note(91), .2, vib=.015, harm=.15), gap=0.04)
S["wink"]     = seq(chirp(93, .045), chirp(98, .05), gap=0.03)
S["question"] = seq(chirp(79, .08, 1.0), tone(note(81), note(88), .16, harm=.2, r=.1), gap=0.03)
S["approval"] = seq(chirp(84, .07, 1.0), chirp(84, .07, 1.0), tone(note(86), note(91), .14, harm=.2), gap=0.05)
S["error"]    = seq(tone(330, 280, .12, shape="soft", harm=.35), tone(262, 196, .22, shape="soft", harm=.35), gap=0.03)
S["annoyed"]  = tone(240, 170, .26, shape="soft", vib=.04, vibf=11, harm=.4)
S["dizzy"]    = tone(900, 260, .6, vib=.06, vibf=9, harm=.2, r=.3)
S["yawn"]     = mix(tone(520, 240, .75, vib=.01, vibf=4, harm=.15, a=.08, r=.4), noise(.75, .04, a=.2, r=.5) * .12)
S["sleep"]    = seq(tone(330, 300, .35, harm=.1, a=.06, r=.25), tone(300, 262, .45, harm=.1, a=.06, r=.35), gap=0.12) * .7
S["gulp"]     = seq(tone(700, 220, .09, harm=.3, r=.06), tone(260, 180, .08, harm=.3, r=.06), gap=0.02)
S["attach"]   = seq(tone(260, 700, .07, r=.05), chirp(91, .08), gap=0.02)
S["slap"]     = mix(noise(.07, .6, r=.05), tone(200, 120, .08, shape="soft", harm=.4) * .6)
S["think"]    = seq(chirp(86, .04), chirp(88, .04), chirp(86, .04), gap=0.06) * .7
S["search"]   = seq(*[chirp(84 + (i % 2) * 3, .035) for i in range(5)], gap=0.04) * .6
S["work"]     = seq(chirp(81, .035, 1.0), chirp(81, .035, 1.0), gap=0.05) * .6
S["send"]     = mix(noise(.22, .25, a=.03, r=.12) * .5, tone(600, 1800, .22, harm=.1, r=.1) * .5)
S["rate"]     = seq(chirp(88, .06), chirp(91, .06), chirp(96, .1), gap=0.02)

for k, v in S.items(): save(k, v)
print(len(S), "sons em", out)
