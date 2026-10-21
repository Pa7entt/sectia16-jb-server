#!/usr/bin/env python3
"""
SECTIA 16 - Generator efecte sonore (jb.sectia16.ro)
Genereaza toate fisierele .wav din cstrike/sound/sectia16/.
Ruleaza:  python3 tools/gen_sounds.py
Dependente: doar stdlib (math, random, struct, wave).

Toate fisierele: PCM 16-bit mono, 22050 Hz - compatibil GoldSrc (spk).
"""

import math
import os
import random
import struct
import wave

SR = 22050
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "cstrike", "sound", "sectia16"))

random.seed(1616)  # determinist: aceleasi sunete la fiecare rulare


# ----------------------------------------------------------------
#  Primitive
# ----------------------------------------------------------------

def write_wav(name, samples):
    """Scriere 16-bit mono cu clamp soft."""
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = min(1.0, 0.92 / peak)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32000))
        for s in samples
    )
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"  [ok] {name:16s} {len(samples) / SR:5.2f}s  ({os.path.getsize(path) // 1024} KB)")


def sec(x):
    return int(x * SR)


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def add(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def env_ad(samples, attack=0.004, release=0.08):
    """Atac liniar + release exponential."""
    n = len(samples)
    a = sec(attack)
    r = sec(release)
    out = list(samples)
    for i in range(n):
        g = 1.0
        if i < a:
            g = i / max(1, a)
        if i > n - r:
            g *= math.exp(-4.0 * (i - (n - r)) / max(1.0, r))
        out[i] *= g
    return out


def sine(freq, dur, vol=0.5, vib_hz=0.0, vib_amt=0.0):
    out = []
    ph = 0.0
    for i in range(sec(dur)):
        t = i / SR
        f = freq + vib_amt * math.sin(2 * math.pi * vib_hz * t)
        ph += 2 * math.pi * f / SR
        out.append(vol * math.sin(ph))
    return out


def square(freq, dur, vol=0.4, duty=0.5):
    out = []
    ph = 0.0
    for i in range(sec(dur)):
        ph = (ph + freq / SR) % 1.0
        out.append(vol if ph < duty else -vol)
    return out


def saw(freq, dur, vol=0.4, vib_hz=0.0, vib_amt=0.0):
    out = []
    ph = 0.0
    for i in range(sec(dur)):
        t = i / SR
        f = freq + vib_amt * math.sin(2 * math.pi * vib_hz * t)
        ph = (ph + f / SR) % 1.0
        out.append(vol * (2.0 * ph - 1.0))
    return out


def noise(dur, vol=0.4, lp=0.15):
    """Zgomot cu lowpass simplu (media mobila)."""
    out = []
    y = 0.0
    for _ in range(sec(dur)):
        x = random.uniform(-1, 1)
        y += lp * (x - y)
        out.append(vol * y)
    return out


def chirp(f0, f1, dur, vol=0.5, kind="sine"):
    out = []
    n = sec(dur)
    ph = 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        ph += 2 * math.pi * f / SR
        v = math.sin(ph)
        if kind == "square":
            v = 1.0 if v >= 0 else -1.0
        out.append(vol * v * (1.0 - 0.35 * t))
    return out


def bell(freq, dur, vol=0.5):
    """Clopot: partiali inarmonici cu decay diferit."""
    n = sec(dur)
    out = []
    for i in range(n):
        t = i / SR
        v = (math.sin(2 * math.pi * freq * t) * math.exp(-3.0 * t / dur) +
             0.55 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-5.0 * t / dur) +
             0.28 * math.sin(2 * math.pi * freq * 5.40 * t) * math.exp(-8.0 * t / dur))
        out.append(vol * v)
    return out


def place(track, samples, at_sec):
    """Adauga track peste samples la momentul at_sec (pad cu 0)."""
    start = sec(at_sec)
    need = start + len(track)
    if len(samples) < need:
        samples.extend([0.0] * (need - len(samples)))
    for i, v in enumerate(track):
        samples[start + i] += v


# ----------------------------------------------------------------
#  Instrumente manele
# ----------------------------------------------------------------

NOTE = {"E2": 82.41, "A2": 110.0, "B2": 123.47, "D3": 146.83, "E3": 164.81,
        "F#3": 185.0, "G3": 196.0, "A3": 220.0, "B3": 246.94, "C4": 261.63,
        "D4": 293.66, "D#4": 311.13, "E4": 329.63, "F#4": 369.99, "G4": 392.0,
        "A4": 440.0, "B4": 493.88, "C5": 523.25, "D5": 587.33, "D#5": 622.25,
        "E5": 659.26, "F#5": 739.99, "G5": 783.99, "A5": 880.0, "C6": 1046.50}


def clarinet(freq, dur, vol=0.4):
    """Sunet de clarinet manelist: saw + vibrato puternic."""
    return env_ad(saw(freq, dur, vol, vib_hz=6.2, vib_amt=freq * 0.012), 0.02, dur * 0.4)


def darbuka(dur_total, bpm, vol=0.9):
    """Ritm de darbuka: dum (grav) + tak (acut)."""
    beat = 60.0 / bpm
    out = [0.0] * sec(dur_total)
    pattern = [("dum", 0.0), ("tak", 0.5), ("tak", 0.75), ("dum", 1.0), ("tak", 1.5), ("tak", 1.75)]
    rep = int(dur_total / (beat * 2)) + 1
    for r in range(rep):
        for kind, pos in pattern:
            at = r * beat * 2 + pos * beat
            if at >= dur_total:
                continue
            if kind == "dum":
                place(env_ad(sine(72, 0.16, vol), 0.002, 0.12), out, at)
            else:
                place(env_ad(noise(0.05, vol * 0.5, lp=0.6), 0.001, 0.03), out, at)
    return out


def bass_line(notes, bpm, dur_total, vol=0.34):
    """Bas de manea: octave pe pulsurile de 8."""
    beat = 60.0 / bpm
    out = [0.0] * sec(dur_total)
    step = beat / 2.0
    n_notes = len(notes)
    i = 0
    t = 0.0
    while t < dur_total:
        f = notes[i % n_notes]
        place(env_ad(square(f, step * 0.9, vol, duty=0.42), 0.004, 0.05), out, t)
        t += step
        i += 1
    return out


def melody_line(notes, bpm, vol=0.42):
    """Melodie: lista de (nota, durime_in_biti)."""
    beat = 60.0 / bpm
    out = []
    for name, beats in notes:
        f = NOTE.get(name)
        if f is None:
            out.extend([0.0] * sec(beat * beats))
            continue
        out.extend(clarinet(f, beat * beats * 0.95, vol))
    return out


# ----------------------------------------------------------------
#  Sunetele SECTIA 16
# ----------------------------------------------------------------

def gen_fluierat():
    print("[*] Fluierat de arbitru...")
    blast = add(sine(2093, 0.8, 0.42, vib_hz=42, vib_amt=170),
                sine(2637, 0.8, 0.25))
    blast = env_ad(blast, 0.01, 0.10)
    # doua fluieraturi scurte + una lunga
    part1 = concat(blast[:sec(0.16)], [0.0] * sec(0.07),
                   blast[:sec(0.16)], [0.0] * sec(0.07),
                   blast[:sec(0.55)])
    write_wav("fluierat.wav", part1)


def gen_manea1():
    print("[*] Manea #1 (viata de detinut)...")
    bpm = 132
    dur = 9.0
    drums = darbuka(dur, bpm, 0.8)
    bass = bass_line([NOTE["E2"], NOTE["E2"], NOTE["A2"], NOTE["B2"]], bpm, dur)
    mel = melody_line([("E4", 1), ("F#4", 0.5), ("G4", 0.5), ("F#4", 0.5), ("D#4", 0.5),
                       ("E4", 1), ("B3", 1), ("D4", 0.5), ("E4", 0.5), ("F#4", 1),
                       ("G4", 0.5), ("A4", 0.5), ("B4", 1), ("A4", 0.5), ("G4", 0.5),
                       ("F#4", 0.5), ("D#4", 0.5), ("E4", 2)], bpm, 0.45)
    mel = [0.0] * sec(0.5) + mel
    mixdown = add(drums, bass, mel)
    write_wav("manea1.wav", mixdown)


def gen_manea2():
    print("[*] Manea #2 (boule de gardian)...")
    bpm = 148
    dur = 8.0
    drums = darbuka(dur, bpm, 0.85)
    bass = bass_line([NOTE["A2"], NOTE["A2"], NOTE["G3"], NOTE["A2"]], bpm, dur)
    mel = melody_line([("A4", 0.5), ("B4", 0.5), ("C5", 1), ("B4", 0.5), ("A4", 0.5),
                       ("G4", 1), ("A4", 1), ("E5", 0.5), ("D5", 0.5), ("C5", 1),
                       ("B4", 0.5), ("C5", 0.5), ("D5", 1), ("E5", 1), ("A4", 2)], bpm, 0.45)
    mel = [0.0] * sec(0.4) + mel
    write_wav("manea2.wav", add(drums, bass, mel))


def gen_manea_loud():
    print("[*] Manea Loudspeaker (versiunea asurzitoare)...")
    bpm = 150
    dur = 5.0
    drums = darbuka(dur, bpm, 1.0)
    bass = bass_line([NOTE["E2"], NOTE["E2"], NOTE["E2"], NOTE["D3"]], bpm, dur, 0.5)
    mel = melody_line([("E5", 0.5), ("D#5", 0.5), ("E5", 0.5), ("B4", 0.5),
                       ("E5", 0.5), ("F#5", 1), ("G5", 1)], bpm, 0.55)
    mel = mel + mel
    mixdown = add(drums, bass, mel[: sec(dur)])
    # distorsie tare + sclipire de sirena
    mixdown = [math.tanh(v * 4.2) for v in mixdown]
    place(env_ad(chirp(1200, 2600, 0.7, 0.35, kind="square"), 0.01, 0.2), mixdown, 1.8)
    place(env_ad(chirp(2600, 1200, 0.7, 0.35, kind="square"), 0.01, 0.2), mixdown, 3.2)
    write_wav("manea_loud.wav", mixdown)


def gen_palinca():
    print("[*] Palinca 70 de grade (glug-glug + wooo)...")
    glugs = []
    for i in range(5):
        g = env_ad(chirp(520 - i * 55, 160, 0.13, 0.55), 0.004, 0.05)
        glugs = concat(glugs, g, [0.0] * sec(0.09))
    wobble = []
    for i in range(sec(1.4)):
        t = i / SR
        f = 300 + 130 * math.sin(2 * math.pi * 4.5 * t)
        wobble.append(0.4 * math.sin(2 * math.pi * f * t) * min(1.0, t * 2))
    wobble = env_ad(wobble, 0.05, 0.5)
    write_wav("palinca.wav", concat(glugs, [0.0] * sec(0.2), wobble))


def gen_clopote():
    print("[*] Clopote de biserica (Protopopiat)...")
    total = [0.0] * sec(5.2)
    place(bell(NOTE["E5"], 2.4, 0.5), total, 0.0)
    place(bell(NOTE["G5"], 2.2, 0.45), total, 0.9)
    place(bell(NOTE["A5"], 2.4, 0.5), total, 1.8)
    place(bell(NOTE["E5"], 3.0, 0.55), total, 2.7)
    write_wav("clopote.wav", total)


def gen_zar():
    print("[*] Zaruri (zornait de barbut)...")
    out = []
    for i in range(9):
        b = env_ad(noise(0.045, 0.55, lp=0.7), 0.001, 0.02)
        # componenta tonala scurta, aleatoare
        f = random.uniform(900, 2200)
        b = add(b, env_ad(sine(f, 0.03, 0.2), 0.001, 0.01))
        out = concat(out, b, [0.0] * sec(random.uniform(0.03, 0.09)))
    write_wav("zar.wav", out)


def gen_gratar():
    print("[*] Gratar (scolzit de carne pe foc)...")
    dur = 4.0
    out = noise(dur, 0.32, lp=0.35)
    for i in range(sec(dur)):
        t = i / SR
        env = 0.6 + 0.4 * math.sin(2 * math.pi * 0.7 * t)
        out[i] *= env
    for _ in range(46):
        at = random.uniform(0.05, dur - 0.05)
        place(env_ad(noise(0.025, 0.85, lp=0.8), 0.0005, 0.015), out, at)
    write_wav("gratar.wav", out)


def gen_buzzer():
    print("[*] Buzzer celule...")
    b1 = env_ad(square(145, 0.5, 0.5, duty=0.5), 0.004, 0.05)
    b2 = env_ad(square(120, 0.28, 0.5, duty=0.5), 0.004, 0.05)
    write_wav("buzzer.wav", concat(b1, [0.0] * sec(0.06), b2))


def gen_win():
    print("[*] Fanfara victorie...")
    notes = ["C5", "E5", "G5", "C5", "E5", "G5", "C6"]
    out = []
    for i, n in enumerate(notes):
        dur = 0.11 if i < 4 else 0.3
        out.extend(env_ad(saw(NOTE[n], dur, 0.32, vib_hz=5.5, vib_amt=3.0), 0.004, dur * 0.5))
    out.extend(env_ad(add(saw(NOTE["C5"], 1.1, 0.24), saw(NOTE["E5"], 1.1, 0.2),
                          saw(NOTE["G5"], 1.1, 0.18)), 0.01, 0.6))
    write_wav("win.wav", out)


def gen_lose():
    print("[*] Dezastru (ecou de esec)...")
    seq = [("E4", 0.35), ("C4", 0.35), ("A3", 0.55)]
    out = []
    for n, d in seq:
        out.extend(env_ad(saw(NOTE[n], d, 0.3, vib_hz=5.0, vib_amt=2.5), 0.01, d * 0.6))
    out.extend(env_ad(sine(NOTE["E3"] / 2, 1.0, 0.4), 0.02, 0.9))
    write_wav("lose.wav", out)


def main():
    print(f"SECTIA 16 - generare efecte sonore -> {OUT_DIR}\n")
    gen_fluierat()
    gen_manea1()
    gen_manea2()
    gen_manea_loud()
    gen_palinca()
    gen_clopote()
    gen_zar()
    gen_gratar()
    gen_buzzer()
    gen_win()
    gen_lose()
    print("\nGata. Copiaz\u0103 dosarul cstrike/sound/sectia16 pe server \u0219i pe FastDL.")


if __name__ == "__main__":
    main()
