#!/usr/bin/env python3
"""Генератор абсурдных роликов для Reels и TikTok — полностью с нуля, без чужого контента.

Каждый ролик собирается из случайных сцен, нарезанных в такт музыке:
  * фон: фрактал Мандельброта, игра «Жизнь», клеточный автомат, плазма, шахматка,
    градиенты, треугольник Серпинского, телевизионные таблицы;
  * эффекты: вращение цвета, негатив, тряска, пульсация в бит, зеркало, пиксели,
    шлейфы, «пережаренные» цвета, сдвиг каналов и т. д.;
  * персонажи: квадратные и круглые рожицы, которые ржут, бегают глазами и прыгают;
  * подпись-мем сверху и выкрики посередине («BRUH», «HUH?»);
  * звук синтезируется тут же: бит, бас, писклявая мелодия, «бум» на каждой склейке,
    синтетический смех, «боинги» и «пи-и-и».

Нужны Python 3.9+ и ffmpeg в PATH.

    python make_absurd.py               # один ролик в output/
    python make_absurd.py --count 5     # пять роликов
    python make_absurd.py --seed 42     # повторить ролик с тем же зерном
"""

from __future__ import annotations

import argparse
import colorsys
import json
import math
import random
import subprocess
import sys
import tempfile
import textwrap
import time
import wave
from array import array
from dataclasses import dataclass
from pathlib import Path

import make_reels as mr

HERE = Path(__file__).resolve().parent

W, H = 1080, 1920          # итоговый кадр
RW, RH = 540, 960          # внутреннее разрешение картинки, потом растягивается «пикселями»
FPS = 30
SR = 22050                 # частота синтеза звука
SPRITE = 200               # размер заготовки персонажа
LOOP = 2.0                 # длина цикла анимации персонажа, с

IMPACT_CANDIDATES = [
    "C:/Windows/Fonts/impact.ttf",
    "/System/Library/Fonts/Supplemental/Impact.ttf",
    "/Library/Fonts/Impact.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Impact.ttf",
]

# ------------------------------------------------------------------ тексты

TEMPLATES = [
    "POV: the {noun} achieved {state}",
    "me when the {noun} {verb_s}",
    "nobody:\nthe {noun} at 3am:",
    "{noun}.exe has stopped working",
    "they don't know I {verb_ed} the {noun}",
    "the {noun} is watching. it knows.",
    "{adj} {noun} simulator",
    "when the {noun} hits different",
    "my last 2 brain cells during {event}",
    "this {noun} has {num} {nouns} and zero {nouns2}",
    "{noun} but it's {adj}",
    "average {noun} enjoyer",
    "the {noun} when {event} starts",
    "day {num} of being a {noun}",
    "I asked the {noun} for advice. bad idea.",
    "{noun} speedrun (any%)",
    "certified {adj} moment",
    "what the {noun} does when you leave the room",
    "breaking news: local {noun} {verb_s}",
    "the {noun} after {event}",
    "POV: you are the {noun}",
    "{noun} vs {noun2}: final battle",
    "how it feels to be a {noun} in {year}",
]
VOCAB = {
    "noun": ["fridge", "pigeon", "toaster", "cube", "wifi router", "sock", "cheese", "square", "microwave",
             "lamp", "potato", "cloud", "spoon", "printer", "goose", "shrimp", "traffic cone", "houseplant",
             "calculator", "washing machine", "tram", "bike", "frikandel", "stroopwafel", "duck", "brick",
             "cactus", "remote control", "rubber duck", "pixel", "windmill", "tulip", "herring", "keyboard"],
    "verb_s": ["starts vibrating", "learns to scream", "unlocks a new form", "files taxes",
               "enters the 4th dimension", "forgets how to exist", "starts a podcast", "sees the light",
               "discovers jazz", "logs off forever", "does a backflip", "becomes self-aware",
               "lags in real life", "speaks fluent Dutch", "gets promoted", "refuses to elaborate"],
    "verb_ed": ["befriended", "unplugged", "named", "taught karate to", "replaced", "duplicated",
                "upgraded", "hugged", "downloaded", "adopted", "outsmarted", "rebooted"],
    "state": ["enlightenment", "4K resolution", "ultra instinct", "its final form", "maximum vibe",
              "inner peace", "sentience", "the speed of sound", "pure chaos", "forbidden knowledge"],
    "adj": ["cursed", "forbidden", "ultra", "haunted", "sentient", "illegal", "premium", "budget",
            "quantum", "feral", "certified", "extremely normal", "low-poly", "deep-fried"],
    "event": ["the exam", "a group project", "Monday morning", "a job interview", "family dinner",
              "the dentist", "a power outage", "a math test", "a Zoom call", "the last train home"],
}
WORDS = ["HUH?", "BRUH", "NO WAY", "WHAT", "AAAAA", "?!?", "OK", "HELP", "LMAO", "WHY", "BRO", "WAIT",
         "NAH", "SHEESH", "ERROR", "LOADING...", "???", "OMG", "STOP", "404", "YES", "HMMM", "EXCUSE ME",
         "UNREAL", "GG", "MOOD", "LOL", "RUN"]


def make_caption(rng: random.Random, custom: list[str]) -> str:
    if custom and (rng.random() < 0.7):
        return rng.choice(custom).replace("\\n", "\n")
    tpl = rng.choice(TEMPLATES)
    n1, n2 = rng.sample(VOCAB["noun"], 2)
    return tpl.format(
        noun=n1, noun2=n2, nouns=rng.choice(VOCAB["noun"]) + "s", nouns2=rng.choice(VOCAB["noun"]) + "s",
        verb_s=rng.choice(VOCAB["verb_s"]), verb_ed=rng.choice(VOCAB["verb_ed"]),
        state=rng.choice(VOCAB["state"]), adj=rng.choice(VOCAB["adj"]), event=rng.choice(VOCAB["event"]),
        num=rng.randint(2, 999), year=rng.randint(2031, 3099),
    )


def read_lines(path: Path | None) -> list[str]:
    if not path or not path.is_file():
        return []
    return [ln.strip() for ln in path.read_text(encoding="utf-8-sig").splitlines()
            if ln.strip() and not ln.startswith("#")]


# ------------------------------------------------------------------- цвета


def vivid(rng: random.Random, s: float = 1.0, v: float = 1.0) -> tuple[int, int, int]:
    r, g, b = colorsys.hsv_to_rgb(rng.random(), s, v)
    return int(r * 255), int(g * 255), int(b * 255)


def hexc(c: tuple[int, int, int]) -> str:
    return "0x{:02X}{:02X}{:02X}".format(*c)


# -------------------------------------------------------------------- фоны
# Каждая функция возвращает цепочку фильтров-источник без меток.


def bg_tv(rng, d):
    src = rng.choice(["testsrc2", "smptehdbars", "smptebars", "pal75bars", "rgbtestsrc", "yuvtestsrc"])
    return f"{src}=s={RW}x{RH}:r={FPS}:d={d:.3f}"


def bg_mandelbrot(rng, d):
    x, y = rng.choice([(-0.743643887037158, -0.131825904205311), (-0.75, 0.1), (-1.25066, 0.02012),
                       (-0.7453, 0.1127), (-0.235125, 0.827215), (-1.7499, 0.0), (-0.1011, 0.9563)])
    return (f"mandelbrot=s=180x320:r={FPS}:maxiter=120:start_x={x}:start_y={y}"
            f":start_scale={rng.uniform(1.5, 3):.2f}:end_scale={rng.uniform(0.0005, 0.02):.5f}"
            f":end_pts={int(d * FPS * rng.uniform(1.0, 2.5))}"
            f":outer={rng.choice(['iteration_count', 'normalized_iteration_count', 'white'])}"
            f":inner={rng.choice(['black', 'period', 'convergence', 'mincol'])}")


def bg_life(rng, d):
    return (f"life=s=135x240:r={FPS}:ratio={rng.uniform(0.1, 0.5):.2f}:mold={rng.randint(0, 40)}"
            f":life_color={hexc(vivid(rng))}:death_color={hexc(vivid(rng, 0.8, 0.25))}"
            f":mold_color={hexc(vivid(rng))}:seed={rng.randrange(1 << 30)}")


def bg_cellauto(rng, d):
    c0, c1 = vivid(rng, 0.9, 0.3), vivid(rng)
    lut = ":".join(f"{ch}='if(gt(val,127),{c1[i]},{c0[i]})'" for i, ch in enumerate("rgb"))
    return (f"cellauto=s=270x480:r={FPS}:rule={rng.choice([18, 30, 45, 73, 90, 105, 110, 150, 182])}"
            f":ratio={rng.uniform(0.2, 0.6):.2f}:seed={rng.randrange(1 << 30)}:full=1"
            f",format=rgb24,lutrgb={lut}")


def bg_plasma(rng, d):
    a, b, c = (rng.uniform(4, 14) for _ in range(3))
    sa, sb, sc = (rng.uniform(1, 5) * rng.choice([-1, 1]) for _ in range(3))
    cx, cy = rng.uniform(0, 90), rng.uniform(0, 160)
    return (f"nullsrc=s=90x160:r={FPS}:d={d:.3f},format=gbrp,"
            f"geq=r='128+127*sin(X/{a:.2f}+T*{sa:.2f})':g='128+127*sin(Y/{b:.2f}+T*{sb:.2f})'"
            f":b='128+127*sin(hypot(X-{cx:.0f},Y-{cy:.0f})/{c:.2f}+T*{sc:.2f})'")


def bg_checker(rng, d):
    k, sp = rng.choice([6, 8, 10, 15]), rng.uniform(1, 6)
    c0, c1 = vivid(rng), vivid(rng)
    expr = lambda i: f"'if(mod(floor(X/{k})+floor(Y/{k})+floor(T*{sp:.2f}),2),{c1[i]},{c0[i]})'"  # noqa: E731
    return f"nullsrc=s=60x120:r={FPS}:d={d:.3f},format=gbrp,geq=r={expr(0)}:g={expr(1)}:b={expr(2)}"


def bg_gradients(rng, d):
    n = rng.randint(2, 8)
    cols = ":".join(f"c{i}={hexc(vivid(rng))}" for i in range(n))
    return (f"gradients=s={RW}x{RH}:r={FPS}:d={d:.3f}:n={n}:{cols}:speed={rng.uniform(0.02, 0.15):.3f}"
            f":type={rng.choice(['linear', 'radial', 'circular', 'spiral'])}:seed={rng.randrange(1 << 30)}")


def bg_sierpinski(rng, d):
    return (f"sierpinski=s={RW}x{RH}:r={FPS}:type={rng.choice(['carpet', 'triangle'])}"
            f":jump={rng.randint(1, 10)}:seed={rng.randrange(1 << 30)}")


def bg_color(rng, d):
    return f"color=c={hexc(vivid(rng))}:s={RW}x{RH}:r={FPS}:d={d:.3f},hue=H=2*PI*t*{rng.uniform(0.2, 1.2):.2f}"


BACKGROUNDS = [bg_tv, bg_mandelbrot, bg_life, bg_cellauto, bg_plasma, bg_checker, bg_gradients,
               bg_sierpinski, bg_color, bg_plasma, bg_mandelbrot, bg_life]


# ----------------------------------------------------------------- эффекты


def fx_hue(rng, beat):
    return f"hue=H=2*PI*t*{rng.uniform(0.3, 2.0):.2f}:s={rng.uniform(1, 2.5):.2f}"


def fx_rotate(rng, beat):
    return f"rotate=a={rng.choice([-1, 1]) * rng.uniform(0.3, 2.5):.2f}*t:c={hexc(vivid(rng))}"


def fx_shake(rng, beat):
    a, b = rng.uniform(20, 45), rng.uniform(20, 45)
    return (f"crop={int(RW * 0.86)}:{int(RH * 0.86)}:x='(iw-ow)/2+sin(t*{a:.1f})*iw*0.06'"
            f":y='(ih-oh)/2+cos(t*{b:.1f})*ih*0.06'")


def fx_pulse(rng, beat):
    amp = rng.uniform(0.15, 0.4)
    return (f"zoompan=z='1+{amp:.2f}*exp(-mod(it,{beat:.4f})*9)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2'"
            f":d=1:s={RW}x{RH}:fps={FPS}")


EFFECTS = [
    fx_hue, fx_rotate, fx_shake, fx_pulse, fx_pulse,
    lambda rng, beat: "negate",
    lambda rng, beat: "edgedetect=mode=colormix:high=0.15:low=0.05",
    lambda rng, beat: f"lagfun=decay={rng.uniform(0.9, 0.97):.3f}",
    lambda rng, beat: f"rgbashift=rh={rng.randint(-24, 24)}:bh={rng.randint(-24, 24)}:gv={rng.randint(-24, 24)}:edge=wrap",
    lambda rng, beat: f"noise=alls={rng.randint(25, 70)}:allf=t+u",
    lambda rng, beat: "eq=saturation=3:contrast=1.7,unsharp=7:7:2.5",
    lambda rng, beat: (lambda k: f"scale={RW // k}:{RH // k}:flags=neighbor,scale={RW}:{RH}:flags=neighbor")(
        rng.choice([6, 10, 15])),
    lambda rng, beat: "tmix=frames=8",
    lambda rng, beat: rng.choice(["hflip", "vflip"]),
    lambda rng, beat: "lutrgb=r='bitand(val,192)':g='bitand(val,192)':b='bitand(val,192)'",
    lambda rng, beat: f"chromashift=cbh={rng.randint(-16, 16)}:crh={rng.randint(-16, 16)}:edge=wrap",
    "mirror",
]


# --------------------------------------------------------------- персонажи


@dataclass
class Character:
    color: tuple[int, int, int]
    mouth_color: tuple[int, int, int]
    round: bool
    eye: float
    mouth_w: float
    laugh_hz: float
    pupil_k: int
    file: Path | None = None


def random_character(rng: random.Random) -> Character:
    return Character(
        color=vivid(rng, rng.uniform(0.6, 1.0)), mouth_color=rng.choice([(0, 0, 0), (120, 0, 20), (40, 0, 60)]),
        round=rng.random() < 0.45, eye=rng.uniform(0.09, 0.17), mouth_w=rng.uniform(0.3, 0.65),
        laugh_hz=rng.choice([2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0]), pupil_k=rng.randint(1, 6),
    )


def render_character(ch: Character, path: Path) -> None:
    """Рендерит зацикленную анимацию персонажа с прозрачным фоном."""
    s = SPRITE
    spin = math.pi * ch.pupil_k  # целое число оборотов за LOOP секунд — цикл без скачка
    px, py = f"{0.05 * s:.1f}*sin(T*{spin:.4f})", f"{0.04 * s:.1f}*cos(T*{spin:.4f})"
    er, pr = ch.eye * s, ch.eye * s * 0.45
    eye = (f"lt(hypot(X-{0.3 * s:.1f},Y-{0.38 * s:.1f}),{er:.1f})"
           f"+lt(hypot(X-{0.7 * s:.1f},Y-{0.38 * s:.1f}),{er:.1f})")
    pupil = (f"lt(hypot(X-{0.3 * s:.1f}-{px},Y-{0.38 * s:.1f}-{py}),{pr:.1f})"
             f"+lt(hypot(X-{0.7 * s:.1f}-{px},Y-{0.38 * s:.1f}-{py}),{pr:.1f})")
    mouth = (f"between(X,{(0.5 - ch.mouth_w / 2) * s:.1f},{(0.5 + ch.mouth_w / 2) * s:.1f})"
             f"*between(Y,{0.6 * s:.1f},{0.65 * s:.1f}+{0.22 * s:.1f}*abs(sin(PI*{ch.laugh_hz}*T)))")
    cls = f"st(0,if({mouth},3,if({pupil},2,if({eye},1,0))))"

    def chan(i: int) -> str:
        return (f"'{cls};if(eq(ld(0),0),{ch.color[i]},if(eq(ld(0),1),255,"
                f"if(eq(ld(0),2),0,{ch.mouth_color[i]})))'")

    alpha = f"'255*lt(hypot(X-{s / 2},Y-{s / 2}),{s / 2})'" if ch.round else "255"
    subprocess.run(
        [mr.FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
         f"nullsrc=s={s}x{s}:r={FPS}:d={LOOP},format=rgba,geq=r={chan(0)}:g={chan(1)}:b={chan(2)}:a={alpha}",
         "-c:v", "png", "-pix_fmt", "rgba", str(path)],
        check=True,
    )
    ch.file = path


# ----------------------------------------------------------------- звук


class Mixer:
    def __init__(self, seconds: float):
        self.n = int(seconds * SR) + 1
        self.buf = array("d", bytes(8 * self.n))

    def add(self, t0: float, samples, gain: float) -> None:
        i0 = int(t0 * SR)
        buf, n = self.buf, self.n
        for k, v in enumerate(samples):
            i = i0 + k
            if i >= n:
                break
            if i >= 0:
                buf[i] += v * gain

    def wav(self, path: Path) -> None:
        peak = max(1e-9, max(abs(v) for v in self.buf))
        drive = 1.4
        norm = math.tanh(drive)
        out = array("h", (int(32000 * math.tanh(drive * v / peak) / norm) for v in self.buf))
        if sys.byteorder == "big":
            out.byteswap()
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(out.tobytes())


def snd_kick():
    out, ph = [], 0.0
    for i in range(int(0.3 * SR)):
        t = i / SR
        ph += 2 * math.pi * (45 + 120 * math.exp(-t * 30)) / SR
        out.append(math.sin(ph) * math.exp(-t * 9))
    return out


def snd_snare(rng):
    return [(0.6 * (rng.random() * 2 - 1) + 0.5 * math.sin(2 * math.pi * 185 * i / SR)) * math.exp(-i / SR * 22)
            for i in range(int(0.22 * SR))]


def snd_hat(rng):
    return [(rng.random() * 2 - 1) * math.exp(-i / SR * 70) for i in range(int(0.06 * SR))]


def snd_boom():
    out, ph = [], 0.0
    for i in range(int(1.5 * SR)):
        t = i / SR
        ph += 2 * math.pi * (32 + 55 * math.exp(-t * 5)) / SR
        out.append(math.tanh(3 * math.sin(ph)) * math.exp(-t * 2.6))
    return out


def snd_laugh(rng):
    kind = rng.choice(["normal", "normal", "chipmunk", "demon"])
    f0 = {"normal": rng.uniform(170, 300), "chipmunk": rng.uniform(500, 800), "demon": rng.uniform(70, 110)}[kind]
    out, ph = [], 0.0
    for p in range(rng.randint(4, 9)):
        dur, gap = rng.uniform(0.1, 0.16), rng.uniform(0.04, 0.08)
        fp = f0 * (1 - 0.03 * p) * rng.uniform(0.95, 1.08)
        amps = [math.exp(-((k * fp - 750) / 350) ** 2) + 0.6 * math.exp(-((k * fp - 1200) / 450) ** 2) + 0.15 / k
                for k in range(1, 9)]
        for i in range(int(dur * SR)):
            t = i / SR
            ph += 2 * math.pi * fp * (1 + 0.08 * (1 - t / dur)) / SR
            env = min(1.0, t / 0.012) * math.exp(-t * 9)
            s = sum(a * math.sin(k * ph) for k, a in enumerate(amps, 1)) + 0.25 * (rng.random() * 2 - 1)
            out.append(s * env)
        out.extend([0.0] * int(gap * SR))
    peak = max(abs(v) for v in out) or 1
    return [v / peak for v in out]


def snd_boing(rng):
    out, ph, f0 = [], 0.0, rng.uniform(120, 260)
    for i in range(int(0.6 * SR)):
        t = i / SR
        ph += 2 * math.pi * f0 * (1 + 3 * t) * (1 + 0.15 * math.sin(2 * math.pi * 14 * t)) / SR
        out.append(math.sin(ph) * math.exp(-t * 4))
    return out


def snd_beep(rng):
    n = int(rng.uniform(0.3, 0.7) * SR)
    return [0.6 * math.sin(2 * math.pi * 1000 * i / SR) * min(1.0, i / 200, (n - i) / 200) for i in range(n)]


SCALES = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10], [0, 1, 3, 5, 7, 8, 10],
          [0, 2, 4, 6, 8, 10], [0, 2, 4, 7, 9], [0, 3, 5, 6, 7, 10]]
PATTERNS = {  # 8 восьмых в такте: бочка, малый, хэт
    "floor": ([1, 0, 1, 0, 1, 0, 1, 0], [0, 0, 1, 0, 0, 0, 1, 0], [0, 1, 0, 1, 0, 1, 0, 1]),
    "half": ([1, 0, 0, 0, 0, 0, 0, 1], [0, 0, 0, 0, 1, 0, 0, 0], [1, 1, 1, 1, 1, 1, 1, 1]),
    "bounce": ([1, 0, 0, 1, 0, 0, 1, 0], [0, 0, 1, 0, 0, 0, 1, 0], [1, 0, 1, 1, 1, 0, 1, 1]),
}


def synth_track(rng, total: float, bpm: float, cuts: list[float], laughs: list[float],
                sfx: list[float], path: Path) -> None:
    mix = Mixer(total)
    beat, eighth = 60 / bpm, 30 / bpm
    kick, snare, hat = snd_kick(), snd_snare(rng), snd_hat(rng)
    style = rng.choice(list(PATTERNS) + ["chaos"])
    for e in range(int(total / eighth) + 1):
        t = e * eighth
        if style == "chaos":
            k, s, h = rng.random() < 0.35, rng.random() < 0.2, rng.random() < 0.6
        else:
            pk, ps, ph = PATTERNS[style]
            k, s, h = pk[e % 8], ps[e % 8], ph[e % 8]
        if k:
            mix.add(t, kick, 0.7)
        if s:
            mix.add(t, snare, 0.35)
        if h:
            mix.add(t, hat, 0.12)

    # бас по долям и писклявая мелодия восьмыми
    scale, root = rng.choice(SCALES), rng.uniform(80, 140)
    buf, n = mix.buf, mix.n
    degree = 0
    for e in range(int(total / eighth) + 1):
        t0 = e * eighth
        if e % 2 == 0:  # бас
            note = rng.choice(scale)
            f = root * 2 ** (note / 12)
            for i in range(int(t0 * SR), min(n, int((t0 + beat * 0.9) * SR))):
                t = i / SR - t0
                v = math.sin(2 * math.pi * f * t)
                buf[i] += 0.16 * (0.6 * math.copysign(1, v) + 0.4 * v) * math.exp(-t * 3)
        if rng.random() < 0.7:  # мелодия
            degree = max(-3, min(len(scale) * 2, degree + rng.choice([-2, -1, 1, 1, 2, 3])))
            octave, idx = divmod(degree, len(scale))
            f = root * 4 * 2 ** ((scale[idx] + 12 * octave) / 12)
            ph = 0.0
            for i in range(int(t0 * SR), min(n, int((t0 + eighth * 0.85) * SR))):
                t = i / SR - t0
                ph += f * (1 + 0.01 * math.sin(2 * math.pi * 6 * t)) / SR
                buf[i] += 0.07 * (1 if (ph % 1) < 0.25 else -1) * min(1.0, t * 200) * math.exp(-t * 4)

    for t in cuts:
        mix.add(t, snd_boom(), 0.9)
    for t in laughs:
        mix.add(t, snd_laugh(rng), 0.75)
    for t in sfx:
        mix.add(t, rng.choice([snd_boing, snd_beep])(rng), 0.45)
    mix.wav(path)


# ---------------------------------------------------------------- сборка


@dataclass
class Scene:
    start: float
    dur: float


def build_video(rng: random.Random, seed: int, out: Path, args) -> dict:
    bpm = rng.uniform(95, 165)
    beat = 60 / bpm
    target = rng.uniform(args.min_dur, args.max_dur)
    scenes, t = [], 0.0
    while t < target - beat:
        d = beat * rng.choice([2, 4, 4, 4, 6, 8])
        scenes.append(Scene(t, d))
        t += d
    total = t
    cast = [random_character(rng) for _ in range(rng.randint(1, 3))]
    caption = make_caption(rng, args.custom_captions)
    words = args.custom_words or WORDS

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        for i, ch in enumerate(cast):
            render_character(ch, tmp / f"char{i}.mov")

        laughs = sorted(rng.uniform(0.5, max(0.6, total - 2)) for _ in range(rng.randint(1, 3)))
        sfx = sorted(rng.uniform(0.3, max(0.4, total - 1)) for _ in range(rng.randint(0, 3)))
        synth_track(rng, total, bpm, [s.start for s in scenes[1:]], laughs, sfx, tmp / "audio.wav")

        inputs = ["-i", "audio.wav"]
        n_inputs = 1
        graph: list[str] = []
        texts: list[str] = []
        for i, sc in enumerate(scenes):
            d = sc.dur
            norm = (f"trim=duration={d:.3f},setpts=PTS-STARTPTS,fps={FPS},"
                    f"scale={RW}:{RH}:flags=neighbor,setsar=1,format=yuv420p")
            label = f"b{i}"
            graph.append(f"{rng.choice(BACKGROUNDS)(rng, d)},{norm}[{label}]")
            for k in range(rng.choices([0, 1, 2, 3], [1, 4, 3, 1])[0]):
                eff, new = rng.choice(EFFECTS), f"b{i}e{k}"
                if eff == "mirror":
                    m = f"m{i}_{k}"
                    graph.append(f"[{label}]crop=iw/2:ih:0:0,split=2[{m}a][{m}b];[{m}b]hflip[{m}c];"
                                 f"[{m}a][{m}c]hstack,setsar=1[{new}]")
                else:
                    graph.append(f"[{label}]{eff(rng, beat)},scale={RW}:{RH},setsar=1,format=yuv420p[{new}]")
                label = new
            if rng.random() < 0.85:
                for j, ch in enumerate(rng.sample(cast, rng.randint(1, len(cast)))):
                    idx, n_inputs = n_inputs, n_inputs + 1  # номер входа ffmpeg
                    inputs += ["-stream_loop", "-1", "-t", f"{d:.3f}", "-i", ch.file.name]
                    size = rng.randint(90, 210)
                    cx, cy = rng.uniform(size / 2 + 20, RW - size / 2 - 20), rng.uniform(RH * 0.3, RH * 0.75)
                    room = max(0.0, min(cx, RW - cx) - size * 0.4)  # чтобы не уезжал за край
                    ax, fx = rng.uniform(0, min(140.0, room)), rng.uniform(0.2, 1.2)
                    ay, fy = rng.uniform(10, 90), bpm / 60 * rng.choice([0.5, 1, 1])
                    wob = rng.uniform(0, 0.5)
                    spr, new = f"c{i}_{j}", f"b{i}c{j}"
                    graph.append(f"[{idx}:v]scale={size}:{size},"
                                 f"rotate=a='{wob:.2f}*sin(t*{rng.uniform(3, 12):.1f})':c=none"
                                 f":ow='hypot(iw,ih)':oh=ow[{spr}]")
                    graph.append(f"[{label}][{spr}]overlay=x='{cx:.0f}-overlay_w/2+{ax:.0f}*sin(2*PI*{fx:.2f}*t)'"
                                 f":y='{cy:.0f}-overlay_h/2-{ay:.0f}*abs(sin(PI*{fy:.3f}*t))'"
                                 f":eof_action=pass[{new}]")
                    label = new
            flash = ",negate=enable='lt(t,0.07)'" if (i and not args.no_flash and rng.random() < 0.3) else ""
            graph.append(f"[{label}]format=yuv420p,setsar=1{flash}[s{i}]")

            if rng.random() < 0.55:  # выкрик посередине
                name = f"w{i}.txt"
                (tmp / name).write_text(rng.choice(words), encoding="utf-8")
                end = sc.start + min(d, rng.uniform(0.6, 1.6))
                texts.append(
                    f"drawtext=fontfile=font{args.font_ext}:textfile={name}:expansion=none"
                    f":fontsize={rng.randint(120, 175)}:fontcolor={hexc(vivid(rng, 0.7))}"
                    f":borderw=10:bordercolor=black:x='(w-text_w)/2+12*sin(t*31)'"
                    f":y={rng.randint(700, 1250)}:enable='between(t,{sc.start:.3f},{end:.3f})'")

        lines = [ln for part in caption.split("\n") for ln in (textwrap.wrap(part, 22) or [""])]
        shake = "+5*sin(t*23)" if rng.random() < 0.5 else ""
        for k, ln in enumerate(lines):
            name = f"cap{k}.txt"
            (tmp / name).write_text(ln, encoding="utf-8")
            texts.append(f"drawtext=fontfile=font{args.font_ext}:textfile={name}:expansion=none:fontsize=76"
                         f":fontcolor=white:borderw=7:bordercolor=black:x='(w-text_w)/2{shake}'"
                         f":y={220 + k * 92}")
        (tmp / f"font{args.font_ext}").write_bytes(Path(args.font_path).read_bytes())

        graph.append("".join(f"[s{i}]" for i in range(len(scenes))) + f"concat=n={len(scenes)}:v=1:a=0[cat]")
        graph.append(f"[cat]scale={W}:{H}:flags=neighbor," + ",".join(texts + ["format=yuv420p"]) + "[vout]")
        afx = rng.choice(["", "", "", ",acrusher=bits=8:samples=4:mix=0.5", ",vibrato=f=6:d=0.25",
                          ",aecho=0.8:0.6:70:0.35", ",flanger"])
        graph.append(f"[0:a]aresample=48000,aformat=channel_layouts=stereo{afx},alimiter=limit=0.9[aout]")
        (tmp / "graph.txt").write_text(";\n".join(graph), encoding="utf-8")

        part = out.with_name(out.stem + ".part.mp4")
        cmd = [mr.FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *inputs,
               *filter_script_args("graph.txt"), "-map", "[vout]", "-map", "[aout]",
               "-t", f"{total:.3f}", "-r", str(FPS), "-c:v", "libx264", "-preset", args.preset,
               "-crf", str(args.crf), "-maxrate", "10M", "-bufsize", "20M", "-profile:v", "high",
               "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
               "-movflags", "+faststart", str(part)]
        res = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
        if res.returncode != 0:
            part.unlink(missing_ok=True)
            if args.keep_failed:
                (out.parent / f"{out.stem}.graph.txt").write_text((tmp / "graph.txt").read_text(), encoding="utf-8")
            raise RuntimeError(res.stderr.strip()[:1500])
        part.replace(out)

    post = caption.replace("\n", " ").strip()
    if args.hashtags:
        post += "\n\n" + args.hashtags
    return {"video": out.name, "kind": "absurd", "seed": seed, "duration": round(total, 2),
            "bpm": round(bpm), "caption": caption, "post_text": post,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S")}


_FILTER_ARGS: list[str] | None = None


def filter_script_args(name: str) -> list[str]:
    """ffmpeg 7+ читает граф из файла через «-/filter_complex», старые — через -filter_complex_script."""
    global _FILTER_ARGS
    if _FILTER_ARGS is None:
        ver = subprocess.run([mr.FFMPEG, "-version"], capture_output=True, text=True).stdout.split()
        major = 99
        if len(ver) > 2 and ver[2][:1].isdigit() and "." in ver[2]:
            try:
                major = int(ver[2].split(".")[0].split("-")[0])
            except ValueError:
                pass
            if major > 1000:  # сборки вида 2025-01-01-git-…
                major = 99
        _FILTER_ARGS = ["-/filter_complex"] if major >= 7 else ["-filter_complex_script"]
    return [*_FILTER_ARGS, name]


def generate(count: int, args) -> list[Path]:
    args.output.mkdir(parents=True, exist_ok=True)
    made = []
    for n in range(count):
        seed = args.seed + n if args.seed is not None else random.randrange(10 ** 6)
        rng = random.Random(seed)
        out = args.output / f"absurd_{time.strftime('%Y%m%d_%H%M%S')}_{seed}.mp4"
        started = time.time()
        try:
            meta = build_video(rng, seed, out, args)
        except RuntimeError as err:
            mr.log(f"  ✗ зерно {seed}: ffmpeg завершился с ошибкой\n{err}")
            continue
        out.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
        mr.log(f"  ✓ {out.name}  ({meta['duration']:.1f} с, {meta['bpm']} BPM, "
               f"{time.time() - started:.0f} с на сборку) — {meta['caption']!r}")
        made.append(out)
    return made


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Генерирует абсурдные вертикальные ролики с нуля.",
                                formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    p.add_argument("--count", type=int, default=1, help="сколько роликов сделать")
    p.add_argument("--output", type=Path, default=HERE / "output")
    p.add_argument("--min-dur", type=float, default=8, help="минимальная длина, с")
    p.add_argument("--max-dur", type=float, default=16, help="максимальная длина, с")
    p.add_argument("--seed", type=int, default=None, help="зерно: одинаковое зерно — одинаковый ролик")
    p.add_argument("--captions", type=Path, default=HERE / "captions.txt",
                   help="свои подписи, по одной на строку (\\n — перенос)")
    p.add_argument("--words", type=Path, default=HERE / "words.txt", help="свои выкрики, по одному на строку")
    p.add_argument("--hashtags", default="#weirdcore #absurd #brainrot #funny #fyp")
    p.add_argument("--font", dest="font_path", default=None, help="путь к .ttf (по умолчанию Impact или Arial Bold)")
    p.add_argument("--no-flash", action="store_true", help="без вспышек-негативов на склейках")
    p.add_argument("--preset", default="medium")
    p.add_argument("--crf", type=int, default=21)
    p.add_argument("--keep-failed", action="store_true", help="сохранить граф фильтров, если сборка упала")
    return p.parse_args(argv)


def prepare(args) -> None:
    mr.FFMPEG, mr.FFPROBE = mr.need_tool("ffmpeg"), mr.need_tool("ffprobe")
    if not args.font_path:
        args.font_path = next((c for c in IMPACT_CANDIDATES if Path(c).is_file()), None)
    args.font_path = str(mr.find_font(args.font_path))
    args.font_ext = Path(args.font_path).suffix.lower()
    args.custom_captions = read_lines(args.captions)
    args.custom_words = read_lines(args.words)


def main(argv=None) -> None:
    args = parse_args(argv)
    prepare(args)
    made = generate(args.count, args)
    mr.log(f"Готово роликов: {len(made)} → {args.output}")


if __name__ == "__main__":
    main()
