"""Original deterministic mono PCM effects; no external recordings or runtime synthesis."""
from pathlib import Path
import math, random, struct, wave
RATE = 32000
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
for name, duration in [("cannon", .42), ("flame", .30), ("shield", .32), ("collapse", .65), ("deposit", .22)]:
    rng = random.Random(name)
    samples, low = [], 0.0
    for i in range(int(RATE * duration)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += .08 * (noise - low)
        if name == "cannon":
            value = .8 * math.sin(2 * math.pi * (95 * t - 55 * t * t)) * math.exp(-t * 11) + noise * math.exp(-t * 75) * .48 + low * math.exp(-t * 8)
        elif name == "flame":
            value = (noise * .15 + low * 1.5) * min(1, t * 100) * math.exp(-t * 4) + noise * max(0, math.sin(t * 630)) ** 12 * .15
        elif name == "shield":
            value = sum(math.sin(2 * math.pi * hz * t) * amp for hz, amp in [(731,.25),(1121,.18),(1513,.12)]) * math.exp(-t * 14) + noise * math.exp(-t * 100) * .3
        elif name == "collapse":
            value = low * 1.7 * math.exp(-t * 5) + math.sin(2 * math.pi * 57 * t) * math.exp(-t * 8) * .4 + noise * math.exp(-t * 30) * .28
        else:
            value = 0
            for when, hz in [(0,480),(.075,650),(.13,820)]:
                age = t - when
                if age >= 0: value += (math.sin(2 * math.pi * hz * age) * .23 + noise * .11) * math.exp(-age * 70)
        value *= min(1, max(0, (duration - t) * 100))
        samples.append(int(math.tanh(value * 1.2) * 26000))
    with wave.open(str(OUT / (name + ".wav")), "wb") as sound:
        sound.setnchannels(1); sound.setsampwidth(2); sound.setframerate(RATE)
        sound.writeframes(struct.pack("<" + "h" * len(samples), *samples))
    print(name + ".wav")
