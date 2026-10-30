#!/usr/bin/env python3
"""Writes assets/sfx/coin.wav and bank.wav: short square-wave blips (the turn and death sounds are the originals from JetLag 2017).
Usage: tools/gen_sfx.py   (stdlib only)"""
import math, os, struct, wave

RATE = 22050
here = os.path.dirname(os.path.abspath(__file__))

def tone(freq, ms, vol=0.25):
    n = int(RATE * ms / 1000)
    out = []
    for i in range(n):
        env = 1.0 - i / n
        out.append(int(32767 * vol * env * (1 if math.sin(2 * math.pi * freq * i / RATE) >= 0 else -1)))
    return out

def write(name, parts):
    data = [s for p in parts for s in p]
    with wave.open(os.path.join(here, "..", "assets", "sfx", name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", s) for s in data))

write("coin.wav", [tone(988, 50), tone(1319, 90)])
write("bank.wav", [tone(523, 70), tone(659, 70), tone(784, 70), tone(1047, 160)])
