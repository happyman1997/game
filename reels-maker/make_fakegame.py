#!/usr/bin/env python3
"""Ролики про несуществующие игры — в том же абсурдном формате, полностью с нуля.

Форматы (выбраны по исследованию трендов, см. research/fake-games-trend-brief.md):
  lost     «Найденная VHS»: заставка выдуманной консоли, титульный экран, геймплей
           пиксельного платформера, «GAME OVER». Эффект старой кассеты.
  ad       Пародия на рекламу мобильной игры: «99% FAIL», вытащи не тот штифт,
           провал, вторая попытка с абсурдным финалом, карточка «PLAY NOW».
  trailer  Трейлер: студия, «от создателей…», нарезка геймплея под «бум»,
           обещания со звёздочкой, название, «COMING 2027».
  patch    Патч-ноты к уже «вышедшей» игре: читать приходится на паузе.

Все игры складываются во «вселенную» (state/fakegames.json): у них появляются
патчи, продолжения и студии с историей — как сериал.

    python make_fakegame.py                    # формат выбирается сам
    python make_fakegame.py --format ad --count 3
"""

from __future__ import annotations

import argparse
import colorsys
import json
import math
import random
import re
import subprocess
import tempfile
import textwrap
import time
from pathlib import Path

import make_absurd as ma
import make_reels as mr

HERE = Path(__file__).resolve().parent
UNIVERSE = HERE / "state" / "fakegames.json"
CW, CH = 270, 480          # холст; каждый его пиксель станет квадратом 4×4 в кадре 1080×1920
FPS = 30
FORMATS = {"lost": 0.32, "ad": 0.26, "trailer": 0.2, "patch": 0.22}

# ------------------------------------------------------------ пиксельный шрифт 3×5

_F = {
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
    ".": "000000000000010", ",": "000000000010100", "!": "010010010000010", "?": "110001010000010",
    ":": "000010000010000", "-": "000000111000000", "+": "000010111010000", "/": "001001010100100",
    "'": "010010000000000", "%": "101001010100101", "(": "001010010010001", ")": "100010010010100",
    "*": "000101010101000", "#": "101111101111101", "=": "000111000111000", ">": "100010001010100",
    "<": "001010100010001", "&": "010101010101011", "_": "000000000000111", "$": "011110010011110",
    " ": "000000000000000",
}
GLYPHS = {ch: [(i % 3, i // 3) for i, bit in enumerate(bits) if bit == "1"] for ch, bits in _F.items()}

# ------------------------------------------------------------------- спрайты

SPRITES = {
    "box": (["..DDDDDDDD..", ".DXXXXXXXXD.", "DXXXXXXXXXXD", "DXWWXXXXWWXD", "DXWKXXXXWKXD", "DXXXXXXXXXXD",
             "DXXKXXXXKXXD", "DXXXKKKKXXXD", ".DXXXXXXXXD.", "..DDDDDDDD..", "...DD..DD...", "...DD..DD..."],
            ["..DDDDDDDD..", ".DXXXXXXXXD.", "DXXXXXXXXXXD", "DXWWXXXXWWXD", "DXWKXXXXWKXD", "DXXXXXXXXXXD",
             "DXXKXXXXKXXD", "DXXXKKKKXXXD", ".DXXXXXXXXD.", "..DDDDDDDD..", "..DD....DD..", ".DD......DD."]),
    "blob": (["....DDDD....", "..DDXXXXDD..", ".DXXXXXXXXD.", ".DXWWXXWWXD.", "DXXWKXXWKXXD", "DXXXXXXXXXXD",
              "DXXXKKKKXXXD", "DXXXXKKXXXXD", ".DXXXXXXXXD.", "..DDXXXXDD..", "....DDDD....", "...DD..DD..."],
             ["............", "....DDDD....", "..DDXXXXDD..", ".DXWWXXWWXD.", "DXXWKXXWKXXD", "DXXXXXXXXXXD",
              "DXXXKKKKXXXD", "DXXXXKKXXXXD", ".DXXXXXXXXD.", "..DDXXXXDD..", "....DDDD....", "..DD....DD.."]),
    "bird": (["....DDDD....", "...DXXXXD...", "..DXXXWKD...", "..DXXXWWDYY.", ".DXXXXXXDYYY", "DXXXXXXXD...",
              "DXXDDDXXXD..", "DXDXXXDXXD..", ".DXXXXXXD...", "..DDDDDD....", "...Y..Y.....", "...Y..Y....."],
             ["....DDDD....", "...DXXXXD...", "..DXXXWKD...", "..DXXXWWDYY.", ".DXXXXXXDYYY", "DXDDDXXXD...",
              "DDXXXDXXXD..", "DXXXXXXXXD..", ".DXXXXXXD...", "..DDDDDD....", "..Y....Y....", ".Y......Y..."]),
}
ENEMY = (["..DDDD..", ".DXXXXD.", "DKXXXXKD", "DXWKKWXD", "DXXXXXXD", "DXKKKKXD", ".DXXXXD.", ".D.DD.D."],
         ["..DDDD..", ".DXXXXD.", "DKXXXXKD", "DXWKKWXD", "DXXXXXXD", "DXKKKKXD", ".DXXXXD.", "D..DD..D"])
COIN = (["..YY..", ".YWYY.", "YWYYYY", "YYYYYY", ".YYYY.", "..YY.."],
        ["..YY..", ".YWY..", ".YYY..", ".YYY..", ".YYY..", "..YY.."],
        ["..Y...", "..W...", "..Y...", "..Y...", "..Y...", "..Y..."])
HAND = ["..KK......", ".KWWK.....", ".KWWK.....", ".KWWKKKK..", ".KWWKWWKKK", "KKWWWWWWWK", "KWWWWWWWWK",
        "KWWWWWWWWK", ".KWWWWWWK.", "..KWWWWK..", "..KKKKKK.."]
STAR = ["...Y...", "..YYY..", "YYYYYYY", ".YYYYY.", ".YY.YY.", "YY...YY"]


def runs_of(rows: list[str]) -> list[tuple[int, int, int, str]]:
    out = []
    for y, row in enumerate(rows):
        x = 0
        while x < len(row):
            ch = row[x]
            n = 1
            while x + n < len(row) and row[x + n] == ch:
                n += 1
            if ch != ".":
                out.append((x, y, n, ch))
            x += n
    return out


_RUNS: dict[int, list] = {}


def runs_cached(rows) -> list:
    key = id(rows)
    if key not in _RUNS:
        _RUNS[key] = runs_of(rows)
    return _RUNS[key]


# -------------------------------------------------------------------- цвета


def hsv(h: float, s: float, v: float) -> tuple[int, int, int]:
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0, min(1, s)), max(0, min(1, v)))
    return int(r * 255), int(g * 255), int(b * 255)


def shade(c, f: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(x * f))) for x in c)  # type: ignore[return-value]


def mixc(a, b, t: float) -> tuple[int, int, int]:
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))  # type: ignore[return-value]


BLACK, WHITE, RED, YELLOW = (0, 0, 0), (255, 255, 255), (230, 40, 40), (255, 220, 40)


# -------------------------------------------------------------------- холст


class Canvas:
    def __init__(self, w: int, h: int, color=BLACK):
        self.w, self.h = w, h
        self.buf = bytearray(bytes(color) * (w * h))

    def fill(self, color) -> None:
        self.buf[:] = bytes(color) * (self.w * self.h)

    def rect(self, x, y, w, h, c) -> None:
        x0, y0 = max(0, int(x)), max(0, int(y))
        x1, y1 = min(self.w, int(x + w)), min(self.h, int(y + h))
        if x0 >= x1 or y0 >= y1:
            return
        row = bytes(c) * (x1 - x0)
        n, W, b = len(row), self.w, self.buf
        for yy in range(y0, y1):
            o = (yy * W + x0) * 3
            b[o:o + n] = row

    def frame_rect(self, x, y, w, h, c, t=1) -> None:
        self.rect(x, y, w, t, c)
        self.rect(x, y + h - t, w, t, c)
        self.rect(x, y, t, h, c)
        self.rect(x + w - t, y, t, h, c)

    def gradient(self, x, y, w, h, c0, c1, bands=12) -> None:
        for i in range(bands):
            y0, y1 = y + h * i // bands, y + h * (i + 1) // bands
            self.rect(x, y0, w, y1 - y0, mixc(c0, c1, i / max(1, bands - 1)))

    def sprite(self, rows, x, y, pal: dict, s: int = 1, flip: bool = False) -> None:
        width = max(len(r) for r in rows)
        for rx, ry, n, ch in runs_cached(rows):
            c = pal.get(ch)
            if c is None:
                continue
            px = (width - rx - n) if flip else rx
            self.rect(x + px * s, y + ry * s, n * s, s, c)

    def text(self, x, y, s: str, color, scale: int = 1, shadow=None, center: bool = False) -> int:
        s = s.upper()
        width = len(s) * 4 * scale - scale
        if center:
            x = (self.w - width) // 2 if x is None else x - width // 2
        if shadow is not None:
            self._text(x + scale, y + scale, s, shadow, scale)
        self._text(x, y, s, color, scale)
        return width

    def _text(self, x, y, s, color, scale) -> None:
        for i, ch in enumerate(s):
            for gx, gy in GLYPHS.get(ch, GLYPHS["?"]):
                self.rect(x + (i * 4 + gx) * scale, y + gy * scale, scale, scale, color)

    def blit(self, other: "Canvas", x: int, y: int) -> None:
        for yy in range(other.h):
            ty = y + yy
            if 0 <= ty < self.h:
                src = other.buf[yy * other.w * 3:(yy + 1) * other.w * 3]
                x0 = max(0, x)
                x1 = min(self.w, x + other.w)
                if x0 < x1:
                    self.buf[(ty * self.w + x0) * 3:(ty * self.w + x1) * 3] = src[(x0 - x) * 3:(x1 - x) * 3]

    def glitch(self, rng: random.Random, bands: int = 3) -> None:
        """Сдвиг горизонтальных полос, как на зажёванной плёнке."""
        for _ in range(bands):
            y0 = rng.randrange(self.h)
            k = rng.randint(4, 40) * 3
            for yy in range(y0, min(self.h, y0 + rng.randint(2, 16))):
                o, e = yy * self.w * 3, (yy + 1) * self.w * 3
                row = self.buf[o:e]
                self.buf[o:e] = row[k:] + row[:k]


def wrap_upper(text: str, chars: int) -> list[str]:
    return textwrap.wrap(text.upper(), chars) or [""]


# ------------------------------------------------------------------ вселенная

HEROES = {
    "pigeon": "bird", "goose": "bird", "duck": "bird", "seagull": "bird", "rubber duck": "bird",
    "fridge": "box", "toaster": "box", "microwave": "box", "printer": "box", "calculator": "box", "brick": "box",
    "lamp": "box", "windmill": "box", "sock": "box", "stroopwafel": "box",
    "potato": "blob", "cheese": "blob", "cloud": "blob", "cactus": "blob", "frikandel": "blob", "tulip": "blob",
    "herring": "blob", "shrimp": "blob", "spoon": "blob",
}
TITLE_PATTERNS = ["{Hero} Game {n}", "Super {Hero} {n}", "{Hero} Simulator {year}", "{Hero} Tycoon",
                  "{Hero} Quest {roman}", "{Adj} {Hero}", "{Hero} Party Deluxe", "Mega {Hero} Turbo",
                  "{Hero} Adventures", "Legend of the {Adj} {Hero}", "{Hero} Racing 64", "{Hero}: The Reckoning",
                  "{Hero} Wars", "Night of the {Hero}", "{Hero} Rescue Team", "{Hero} vs Taxes"]
ADJ = ["Forbidden", "Haunted", "Damp", "Ultra", "Lonely", "Feral", "Quantum", "Moist", "Tiny", "Eternal", "Budget"]
CONSOLES = ["GigaBrick 64", "Toaster System", "Fridge Advance", "Mega Loaf", "HyperCube 9", "Pocket Radiator",
            "Turbo Soup", "Ultra Pebble", "Brick Boy Color", "Nebula Box"]
STUDIOS = ["Pigeon Interactive", "Damp Sock Games", "Studio Nope", "Wet Bread Ent.", "Moist Pixel",
           "Polder Softworks", "Tulip Byte", "Grandma Labs", "404 Studios", "Herring Hut"]
COLLECTIBLES = ["receipts", "crumbs", "vibes", "tax forms", "socks", "bolts", "tears", "beans", "keys"]
ENEMIES = ["tax inspectors", "angry clouds", "landlords", "seagulls", "geese", "printers", "neighbours"]
ROMAN = ["II", "III", "IV", "VII", "XII"]


def sequel_title(title: str, rng: random.Random) -> str:
    m = re.search(r"(\d+)$", title)
    if m:
        return title[:m.start()] + str(int(m.group(1)) + 1)
    nxt = {"II": "III", "III": "IV", "IV": "V", "V": "VI", "VII": "VIII", "XII": "XIII"}
    m = re.search(r"\b(II|III|IV|V|VII|XII)$", title)
    if m:
        return title[:m.start()] + nxt[m.group(1)]
    return rng.choice([f"{title} 2", f"{title}: Reloaded", f"{title} 2: The Return"])


def new_game(rng: random.Random, universe: dict, parent: dict | None = None) -> dict:
    h = rng.random()
    if parent:
        hero, template, title = parent["hero"], parent["template"], parent["title"]
        title = sequel_title(title, rng)
        studio, console = parent["studio"], rng.choice(CONSOLES)
    else:
        hero = rng.choice(list(HEROES))
        template = HEROES[hero]
        n = rng.choice([2, 3, 3, 4, 7])
        title = rng.choice(TITLE_PATTERNS).format(
            Hero=hero.title(), n=n, year=rng.randint(1994, 2003), roman=rng.choice(ROMAN), Adj=rng.choice(ADJ))
        studio, console = rng.choice(STUDIOS), rng.choice(CONSOLES)
    pal = {
        "sky0": hsv(h, 0.55, 0.95), "sky1": hsv(h + 0.06, 0.2, 1.0), "hills": hsv(h + 0.35, 0.45, 0.72),
        "grass": hsv(h + 0.3, 0.75, 0.85), "dirt": hsv(h + 0.08, 0.6, 0.55),
        "hero": hsv(h + 0.5 + rng.uniform(-0.1, 0.1), 0.8, 1.0), "coin": hsv(h + 0.15, 0.85, 1.0),
        "enemy": hsv(h + 0.75, 0.7, 0.85), "bg": hsv(h + 0.55, 0.35, 0.96),
    }
    return {
        "title": title, "hero": hero, "template": template, "console": console, "studio": studio,
        "year": rng.randint(1993, 2004), "collectible": rng.choice(COLLECTIBLES), "enemy": rng.choice(ENEMIES),
        "palette": {k: list(v) for k, v in pal.items()}, "patch": 0, "sequel": (parent or {}).get("sequel", 1) + 1
        if parent else 1, "parent": parent["title"] if parent else None, "videos": [],
    }


def load_universe(path: Path = UNIVERSE) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"games": []}


def save_universe(u: dict, path: Path = UNIVERSE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(u, ensure_ascii=False, indent=2), encoding="utf-8")


def plan(rng: random.Random, universe: dict, fmt: str, weights: dict | None = None) -> tuple[str, dict, bool]:
    """Выбирает формат и игру. Возвращает (формат, игра, новая ли игра)."""
    games = universe["games"]
    if fmt == "auto":
        w = weights or FORMATS
        fmt = rng.choices(list(w), list(w.values()))[0]
    if fmt == "patch":
        if games:
            return fmt, rng.choice(games[-12:]), False
        fmt = "lost"
    if fmt == "trailer" and games and rng.random() < 0.4:  # продолжение уже известной игры
        return fmt, new_game(rng, universe, parent=rng.choice(games[-12:])), True
    return fmt, new_game(rng, universe), True


# ------------------------------------------------------------- сборка кадров


class Ctx:
    def __init__(self, rng: random.Random, game: dict, sink):
        self.rng, self.game, self.sink = rng, game, sink
        self.frames = 0
        self.events: list[tuple[float, str]] = []
        self.pal = {k: tuple(v) for k, v in game["palette"].items()}
        self.hero_rows = SPRITES[game["template"]]

    @property
    def t(self) -> float:
        return self.frames / FPS

    def ev(self, kind: str, dt: float = 0.0) -> None:
        self.events.append((self.t + dt, kind))

    def emit(self, cv: Canvas) -> None:
        self.sink.write(cv.buf)
        self.frames += 1

    def hero_pal(self, ash: bool = False) -> dict:
        body = (70, 70, 70) if ash else self.pal["hero"]
        return {"X": body, "D": shade(body, 0.55), "W": WHITE, "K": BLACK, "Y": (255, 160, 30)}


class Platformer:
    """Пиксельный платформер: герой сам бежит и прыгает, собирает предметы, топчет врагов."""

    T = 12

    def __init__(self, ctx: Ctx, vw: int, vh: int, dur: float, die: bool = False, dialog: bool = True):
        rng, self.ctx, self.vw, self.vh = ctx.rng, ctx, vw, vh
        self.speed, self.cam = 2.6, 0.0
        self.die, self.dead, self.dead_t = die, False, 0
        cols = int(dur * FPS * self.speed / self.T) + vw // self.T + 12
        g, h = [], 3
        while len(g) < cols:
            if len(g) > 8 and rng.random() < 0.18:
                g += [0] * rng.randint(2, 3)
            else:
                if rng.random() < 0.35:
                    h = max(2, min(6, h + rng.choice([-1, 1])))
                g += [h] * rng.randint(3, 7)
        self.ground = g[:cols]
        self.pits = [i for i in range(1, cols) if g[i] == 0 and g[i - 1] > 0]
        self.death_pit = None
        if die:
            late = [p for p in self.pits if p * self.T > dur * FPS * self.speed * 0.6]
            self.death_pit = late[0] if late else None
        self.coins, self.enemies = [], []
        for c in range(6, cols - 2):
            top = self.top(c)
            if top is not None and rng.random() < 0.22:
                self.coins.append([c * self.T + 3, top - rng.randint(28, 60), False])
            if self.ground[c] == 0 and self.ground[c - 1] > 0:
                self.coins.append([c * self.T + 6, (self.top(c - 1) or vh) - 70, False])
            if (top is not None and c > 14 and rng.random() < 0.07 and self.ground[c - 1] == self.ground[c]
                    == self.ground[c + 1]):
                self.enemies.append([c * self.T, top - 16, 1, 0])  # x, y, жив, таймер «раздавлен»
        self.px, self.py, self.vy, self.on_ground = 60.0, float(self.top(5) - 24), 0.0, True
        self.score, self.got, self.lives = 0, 0, 3
        self.dialog_at = rng.uniform(0.35, 0.6) * dur if dialog else None
        self.dialog: list[str] | None = None
        self.dialog_t = 0
        self.dialog_at_abs = 1e9
        g_ = ctx.game
        self.lines = [
            "I HAVE BEEN RUNNING FOR 30 YEARS", f"WHO KEEPS PUTTING {g_['collectible']} HERE",
            "MY LANDLORD IS THE FINAL BOSS", "I CAN HEAR THE PLAYER BREATHING",
            "IS THIS THE TUTORIAL OR MY LIFE", "PLEASE STOP PRESSING JUMP",
            f"THE {g_['enemy']} OWE ME MONEY", "I LEFT THE OVEN ON IN LEVEL 2",
            "THIS GAME HAS NO ENDING. I CHECKED", f"I WAS A {g_['hero']} BEFORE IT WAS COOL",
            "WHY IS THE SKY LOADING", "SAVE FILE CORRUPTED. LIKE ME",
        ]
        # фон: небо и холмы одной полосой, которая повторяется по горизонтали
        self.strip = Canvas(vw, vh)
        p = ctx.pal
        self.strip.gradient(0, 0, vw, vh, p["sky0"], p["sky1"], bands=10)
        a, b = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
        for x in range(vw):
            hh = vh * 0.32 + 14 * math.sin(2 * math.pi * 2 * x / vw + a) + 9 * math.sin(2 * math.pi * 3 * x / vw + b)
            self.strip.rect(x, vh - hh, 1, hh, p["hills"])
        self.clouds = [[rng.uniform(0, vw), rng.uniform(10, vh * 0.35), rng.randint(16, 34)] for _ in range(4)]
        self.vp = Canvas(vw, vh)

    def top(self, col: int):
        if 0 <= col < len(self.ground) and self.ground[col] > 0:
            return self.vh - self.ground[col] * self.T
        return None

    def step(self) -> None:
        ctx = self.ctx
        if self.dialog is not None:  # пока герой говорит, мир стоит
            self.dialog_t += 1
            shown = int(self.dialog_t * 25 / FPS)
            total = sum(len(s) for s in self.dialog)
            if shown <= total and self.dialog_t % 2 == 0:
                ctx.ev("blip")
            if self.dialog_t > (total / 25 + 1.3) * FPS:
                self.dialog = None
            return
        if self.dialog_at is not None and ctx.t >= self.dialog_at_abs:
            self.dialog_at = None
            self.dialog = wrap_upper(ctx.rng.choice(self.lines), 26)[:2]
            self.dialog_t = 0
            return
        if self.dead:
            self.dead_t += 1
            self.py += self.vy
            self.vy += 0.5
            return
        self.px += self.speed
        front = int((self.px + 28) // self.T)
        here = int((self.px + 12) // self.T)
        cur, ahead = self.top(here), self.top(front)
        enemy_ahead = any(e[2] and 0 < e[0] - self.px < 34 for e in self.enemies)
        wants_jump = ahead is None or (cur is not None and ahead < cur) or enemy_ahead
        if self.death_pit is not None and front >= self.death_pit - 1:
            wants_jump = False
        if self.on_ground and wants_jump:
            self.vy, self.on_ground = -8.0, False
            ctx.ev("jump")
        if not self.on_ground:
            prev_feet = self.py + 24
            self.py += self.vy
            self.vy += 0.5
            feet = self.py + 24
            if cur is not None and self.vy > 0 and prev_feet <= cur + 3 and feet >= cur:
                self.py, self.vy, self.on_ground = cur - 24.0, 0.0, True
        elif cur is None or cur > self.py + 24:
            self.on_ground = False
        if self.py > self.vh:
            self.dead, self.vy = True, -6.0
            ctx.ev("fall")
        for c in self.coins:
            if not c[2] and abs(c[0] + 6 - (self.px + 12)) < 14 and abs(c[1] + 6 - (self.py + 12)) < 16:
                c[2] = True
                self.score += 100
                self.got += 1
                ctx.ev("coin")
        for e in self.enemies:
            if not e[2]:
                e[3] += 1
                continue
            e[0] -= 0.6
            if abs(e[0] + 8 - (self.px + 12)) < 18 and abs(e[1] + 8 - (self.py + 12)) < 18:
                if self.vy > 0 and self.py + 24 < e[1] + 12:
                    e[2], self.vy = 0, -6.0
                    self.score += 500
                    ctx.ev("stomp")
                else:
                    e[2] = 0
                    self.lives = max(0, self.lives - 1)
                    ctx.ev("hurt")
        self.cam = self.px - 60

    def draw(self) -> Canvas:
        vp, ctx, p, T = self.vp, self.ctx, self.ctx.pal, self.T
        off = int(self.cam * 0.3) % self.vw * 3
        n = self.vw * 3
        for y in range(self.vh):  # небо и холмы с параллаксом
            row = self.strip.buf[y * n:(y + 1) * n]
            vp.buf[y * n:(y + 1) * n] = row[off:] + row[:off]
        for c in self.clouds:
            x = (c[0] - self.cam * 0.15) % (self.vw + 60) - 40
            vp.rect(x, c[1], c[2], 7, WHITE)
            vp.rect(x + 5, c[1] - 4, c[2] - 10, 4, WHITE)
        c0 = int(self.cam // T)
        dirt, dark, grass = p["dirt"], shade(p["dirt"], 0.7), p["grass"]
        for col in range(max(0, c0), min(len(self.ground), c0 + self.vw // T + 2)):
            h = self.ground[col]
            if h <= 0:
                continue
            x, top = col * T - self.cam, self.vh - h * T
            vp.rect(x, top, T, h * T, dirt)
            for k in range(1, h):
                vp.rect(x, top + k * T, T, 1, dark)
            vp.rect(x, top, 1, h * T, dark)
            vp.rect(x, top, T, 3, grass)
        f = ctx.frames
        for c in self.coins:
            if not c[2] and -12 < c[0] - self.cam < self.vw:
                vp.sprite(COIN[(f // 5) % 3], c[0] - self.cam, c[1] + 2 * math.sin(f / 6 + c[0]),
                          {"Y": p["coin"], "W": WHITE}, s=2)
        epal = {"X": p["enemy"], "D": shade(p["enemy"], 0.5), "W": WHITE, "K": BLACK}
        for e in self.enemies:
            if -20 < e[0] - self.cam < self.vw:
                if e[2]:
                    vp.sprite(ENEMY[(f // 8) % 2], e[0] - self.cam, e[1], epal, s=2)
                elif e[3] < 12:
                    vp.rect(e[0] - self.cam, e[1] + 12, 16, 4, p["enemy"])
        walk = 0 if not self.on_ground else (f // 5) % 2
        vp.sprite(self.ctx.hero_rows[walk], self.px - self.cam, self.py, ctx.hero_pal(), s=2)
        vp.text(6, 6, f"SCORE {self.score:06d}", WHITE, 2, shadow=BLACK)
        vp.text(self.vw - 6 - 8 * 7, 6, f"x{self.got:02d} L{self.lives}", WHITE, 2, shadow=BLACK)
        vp.text(6, 22, self.ctx.game["collectible"][:10], p["coin"], 1, shadow=BLACK)
        if self.dialog is not None:
            bx, by, bw, bh = 6, self.vh - 60, self.vw - 12, 54
            vp.rect(bx, by, bw, bh, (16, 16, 40))
            vp.frame_rect(bx, by, bw, bh, WHITE, 2)
            vp.text(bx + 8, by + 6, self.ctx.game["hero"] + ":", YELLOW, 2)
            left = int(self.dialog_t * 25 / FPS)
            for i, line in enumerate(self.dialog):
                vp.text(bx + 8, by + 20 + i * 14, line[:max(0, left)], WHITE, 2)
                left -= len(line)
        return vp

    def start(self, dur: float) -> None:
        self.dialog_at_abs = self.ctx.t + self.dialog_at if self.dialog_at is not None else 1e9


# ------------------------------------------------------------------- сцены


def scene_lost(ctx: Ctx, cv: Canvas) -> None:
    """Запись с кассеты: консоль → титул → геймплей → (возможно) GAME OVER."""
    g, rng = ctx.game, ctx.rng
    VX, VY, VW, VH = 7, 150, 256, 192
    months = "JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split()
    date = f"{rng.choice(months)} {rng.randint(1, 28):02d} {g['year']}"
    vp = Canvas(VW, VH)
    rec_start = rng.randint(30, 3000)

    def frame(inner: Canvas) -> None:
        cv.fill((14, 14, 20))
        cv.rect(VX - 6, VY - 6, VW + 12, VH + 12, (38, 38, 44))
        cv.blit(inner, VX, VY)
        sec = rec_start + ctx.frames // FPS
        if (ctx.frames // 20) % 4:
            cv.text(14, 116, "PLAY >", WHITE, 3, shadow=BLACK)
        cv.text(14, 356, date, WHITE, 2, shadow=BLACK)
        cv.text(14, 372, f"SP  {sec // 3600}:{sec // 60 % 60:02d}:{sec % 60:02d}", WHITE, 2, shadow=BLACK)
        if rng.random() < 0.06:
            cv.glitch(rng, rng.randint(1, 4))
        ctx.emit(cv)

    # заставка консоли
    ctx.ev("chime", 0.5)
    for f in range(int(2.2 * FPS)):
        vp.fill(BLACK)
        y = min(70, -20 + f * 4)
        vp.text(None, y, g["console"], WHITE, 3, center=True)
        if f > 25:
            vp.text(None, 104, g["studio"], (170, 170, 170), 2, center=True)
            vp.text(None, 130, "LICENSED BY NOBODY", (110, 110, 110), 1, center=True)
        frame(vp)
    # титульный экран
    pf = Platformer(ctx, VW, VH, 1, dialog=False)
    lines = wrap_upper(g["title"], 20)
    for f in range(int(2.8 * FPS)):
        vp.buf[:] = pf.strip.buf
        for i, line in enumerate(lines):
            vp.text(None, 24 + i * 22 + int(2 * math.sin(f / 5)), line, YELLOW, 3, shadow=BLACK, center=True)
        vp.sprite(ctx.hero_rows[(f // 6) % 2], VW // 2 - 18, 96, ctx.hero_pal(), s=3)
        if (f // 12) % 2:
            vp.text(None, 146, "PRESS START", WHITE, 2, shadow=BLACK, center=True)
        vp.text(None, 176, f"(C) {g['year']} {g['studio']}", WHITE, 1, center=True)
        frame(vp)
    ctx.ev("blip")
    vp.fill(WHITE)
    frame(vp)
    # геймплей
    dur = rng.uniform(8.5, 11)
    die = rng.random() < 0.5
    pf = Platformer(ctx, VW, VH, dur, die=die)
    pf.start(dur)
    end = ctx.t + dur
    while ctx.t < end and not (pf.dead and pf.dead_t > FPS):
        pf.step()
        frame(pf.draw())
    # GAME OVER
    if die:
        ctx.ev("gameover")
        for f in range(int(3 * FPS)):
            vp.fill(BLACK)
            vp.text(None, 60, "GAME OVER", RED, 4, center=True)
            n = max(0, 9 - f // 9)
            if f % 9 == 0 and n > 0:
                ctx.ev("blip")
            vp.text(None, 120, f"CONTINUE? {n}", WHITE, 2, center=True)
            if f > 2.6 * FPS:  # плёнка кончилась — помехи
                for _ in range(300):
                    vp.rect(rng.randrange(VW), rng.randrange(VH), 3, 2, (rng.randrange(256),) * 3)
            frame(vp)


def scene_ad(ctx: Ctx, cv: Canvas) -> None:
    """Пародия на рекламу мобильной игры: вытащи штифт."""
    g, rng, p = ctx.game, ctx.rng, ctx.pal
    level = rng.randint(3, 87)
    L, R, TOP, MID, FLOOR = 42, 228, 172, 250, 392
    walls = (120, 120, 130)
    twist = rng.choice(["rich", "floor", "giant"])

    def particles(x0, x1, kind):
        # x, y, vy, вид, лежит, vx, получил толчок, камера (левая ли)
        return [[x, y, 0.0, kind, False, 0.0, False, x0 < 135]
                for y in range(TOP + 4, MID - 4, 6) for x in range(x0 + 2, x1 - 4, 6)]

    def attempt(n: int) -> None:
        lava_left = rng.random() < 0.5
        parts = particles(L, 132, "lava" if lava_left else "gold") + particles(138, R, "gold" if lava_left else "lava")
        pull_left = lava_left if n == 1 else not lava_left
        hm = {c: FLOOR for c in range(L // 4, R // 4 + 1)}
        HS = 3  # масштаб героя
        hero_x, ash, released, pin_off = 135 - 6 * HS, False, False, 0.0
        floor_gap, giant_x, hero_gone = 0.0, 300.0, False
        knob = (24, MID - 3) if pull_left else (232, MID - 3)
        frames = int((6.0 if n == 1 else 6.5) * FPS)
        shout = None
        for f in range(frames):
            t = f / FPS
            cv.fill(p["bg"])
            if (f // 8) % 2:
                cv.text(None, 112, "99% FAIL!", RED if (f // 16) % 2 else YELLOW, 4, shadow=BLACK, center=True)
            cv.text(None, 140, f"LEVEL {level}" + (" - TRY AGAIN" if n == 2 else ""), BLACK, 2, center=True)
            # стенки
            cv.rect(L - 6, TOP - 4, 6, FLOOR - TOP + 10, walls)
            cv.rect(R, TOP - 4, 6, FLOOR - TOP + 10, walls)
            cv.rect(132, TOP - 4, 6, MID - TOP + 4, walls)
            fw = (R - L) / 2
            cv.rect(L - 6, FLOOR, fw + 6 - floor_gap, 6, walls)
            cv.rect(L + fw + floor_gap, FLOOR, fw + 6, 6, walls)
            # рука и штифт
            if 1.0 <= t < 2.4 and not released:
                k = min(1.0, (t - 1.0) / 0.9)
                hx, hy = 200 + (knob[0] - 200) * k, 440 + (knob[1] - 440) * k
            else:
                hx, hy = knob
            if 2.0 <= t and not released:
                pin_off = min(110.0, pin_off + 9)
                if f % 6 == 0 and pin_off < 30:
                    ctx.ev("pin")
                if pin_off >= 110:
                    released = True
            sign = -1 if pull_left else 1
            for left_pin in (True, False):
                o = pin_off * sign if left_pin == pull_left else 0
                x0 = (L if left_pin else 138) + o
                cv.rect(x0, MID, 92 if left_pin else 90, 5, (200, 200, 210))
                kx = (L - 18 if left_pin else R + 6) + o
                cv.rect(kx, MID - 4, 12, 12, (230, 190, 60))
                cv.rect(kx + 3, MID - 1, 6, 6, (255, 235, 140))
            # герой (под частицами, чтобы его могло засыпать)
            hy_ = FLOOR - 12 * HS
            if n == 2 and twist == "floor" and t > 4.2:
                if floor_gap == 0:
                    ctx.ev("fall")
                floor_gap = min(fw, floor_gap + 6)
                hy_ = FLOOR - 12 * HS + (t - 4.2) ** 2 * 300
            if not hero_gone:
                shake = rng.randint(-1, 1) if ash else 0
                cv.sprite(ctx.hero_rows[(f // 6) % 2], hero_x + shake, hy_, ctx.hero_pal(ash), s=HS)
            # частицы
            floor_open = n == 2 and twist == "floor" and t > 4.2
            for q in parts:
                free = released and (q[7] == pull_left) or q[1] > MID + 2
                if floor_open and q[1] > MID + 2 and q[4]:
                    q[4], q[6] = False, False  # пол ушёл — всё, что лежало, падает
                if free and not q[4]:
                    if not q[6]:  # у каждой частицы своя скорость — сыплются, а не падают блоком
                        q[6], q[2], q[5] = True, rng.uniform(-2.5, 0.8), rng.uniform(-1.3, 1.3)
                    q[2] += 0.45
                    q[1] += q[2]
                    q[0] += q[5]
                    q[5] *= 0.97
                    lo, hi = (L, R - 4) if q[1] > MID else ((L, 128) if q[7] else (138, R - 4))
                    if q[0] < lo or q[0] > hi:  # пока частица в своей камере, стенки её держат
                        q[0], q[5] = min(hi, max(lo, q[0])), -q[5]
                    col = int(q[0]) // 4
                    floor_y = 9999 if floor_open else hm.get(col, FLOOR)
                    if q[1] + 4 >= floor_y:
                        for _ in range(4):  # осыпается в более низкую соседнюю колонку, как песок
                            best = col
                            for nb in (col - 1, col + 1):
                                if nb in hm and hm[nb] > hm[best] + 4:
                                    best = nb
                            if best == col:
                                break
                            col = best
                        q[0], q[1], q[4] = col * 4, hm[col] - 4, True
                        hm[col] -= 4
                    if (q[3] == "lava" and hero_x - 2 < q[0] < hero_x + 12 * HS
                            and FLOOR - 12 * HS - 2 < q[1] < FLOOR):
                        if not ash:
                            ash = True
                            ctx.ev("sizzle")
                color = (rng.choice([(255, 90, 20), (255, 40, 0), (255, 160, 40)]) if q[3] == "lava"
                         else (WHITE if rng.random() < 0.05 else (255, 205, 30)))
                if q[1] < 520:
                    cv.rect(q[0], q[1], 4, 4, color)
            # финалы
            if n == 2 and twist == "giant" and t > 3.8:
                if giant_x == 300:
                    ctx.ev("boom")
                giant_x = max(hero_x - 30, giant_x - 9)
                if giant_x <= hero_x + 10:
                    hero_gone = True
            if n == 2 and twist == "giant" and t > 3.8:
                cv.sprite(ENEMY[(f // 6) % 2], giant_x, FLOOR - 96,
                          {"X": p["enemy"], "D": shade(p["enemy"], 0.5), "W": WHITE, "K": BLACK}, s=12)
            cv.sprite(HAND, hx - 4, hy + 6, {"K": BLACK, "W": WHITE}, s=2)
            # надписи
            if n == 1 and ash and t > 3.6:
                if shout is None:
                    shout = "FAIL"
                    ctx.ev("fail")
                    ctx.ev("laugh", 0.6)
            if n == 2 and t > 4.6 and shout is None:
                shout = {"rich": "TOO RICH", "floor": "???", "giant": "NOOO"}[twist]
                ctx.ev("boom")
                ctx.ev("laugh", 0.4)
            if shout:
                cv.text(None, 290 + rng.randint(-2, 2), shout, RED, 6 if len(shout) <= 4 else 4,
                        shadow=BLACK, center=True)
            ctx.emit(cv)

    attempt(1)
    attempt(2)
    # карточка «PLAY NOW»
    ctx.ev("coin")
    lines = wrap_upper(g["title"], 22)
    for f in range(int(3.2 * FPS)):
        cv.gradient(0, 0, CW, CH, p["bg"], shade(p["bg"], 0.7))
        cv.rect(88, 150, 94, 94, shade(p["hero"], 0.45))
        cv.frame_rect(88, 150, 94, 94, WHITE, 3)
        cv.sprite(ctx.hero_rows[(f // 8) % 2], 99, 162, ctx.hero_pal(), s=6)
        for i, line in enumerate(lines):
            cv.text(None, 254 + i * 14, line, BLACK, 2, center=True)
        sy = 254 + len(lines) * 14 + 6
        for i in range(5):
            cv.sprite(STAR, 82 + i * 22, sy, {"Y": (255, 190, 0)}, s=2)
        cv.text(None, sy + 18, f"4.9  ({rng.randint(2, 90)}M)", BLACK, 2, center=True)
        pulse = 4 if (f // 8) % 2 else 0
        by = sy + 40
        cv.rect(60 - pulse, by - pulse, 150 + 2 * pulse, 30 + 2 * pulse, (40, 190, 60))
        cv.frame_rect(60 - pulse, by - pulse, 150 + 2 * pulse, 30 + 2 * pulse, WHITE, 2)
        cv.text(None, by + 8, "PLAY NOW", WHITE, 3, shadow=BLACK, center=True)
        cv.text(None, by + 44, "NOT A REAL GAME", (70, 70, 70), 1, center=True)
        ctx.emit(cv)


def scene_trailer(ctx: Ctx, cv: Canvas) -> None:
    """Трейлер: карточки с текстом, нарезка геймплея под «бум», название."""
    g, rng, p = ctx.game, ctx.rng, ctx.pal
    VW, VH, VY = 270, 152, 164

    def card(lines: list[str], dur: float, color=WHITE, scale=3, sound="whoosh") -> None:
        ctx.ev(sound)
        for f in range(int(dur * FPS)):
            cv.fill(BLACK)
            k = min(1.0, f / 8)
            c = mixc(BLACK, color, k)
            y0 = 200 - len(lines) * (6 * scale + 4) // 2
            for i, line in enumerate(lines):
                cv.text(None, y0 + i * (6 * scale + 4), line, c, scale, center=True)
            ctx.emit(cv)

    def gameplay(dur: float, dialog: bool = False) -> None:
        ctx.ev("boom")
        pf = Platformer(ctx, VW, VH, dur + 2, dialog=dialog)
        pf.dialog_at = 0.3 if dialog else None
        pf.start(dur)
        for _ in range(int(dur * FPS)):
            pf.step()
            cv.fill(BLACK)
            cv.blit(pf.draw(), 0, VY)
            cv.text(None, VY + VH + 10, "ACTUAL IN-GAME FOOTAGE", (150, 150, 150), 2, center=True)
            ctx.emit(cv)

    previous = g.get("parent") or rng.choice(["NOTHING", "A SPREADSHEET", "YOUR NIGHTMARES", "A LOADING SCREEN"])
    promises = [("OPEN WORLD*", "*ONE ROOM"), ("200 HOURS OF STORY*", "*MOSTLY LOADING"),
                ("REALISTIC PHYSICS*", "*NOT REALISTIC"), (f"PLAY AS A {g['hero']}*", "*NO REFUNDS"),
                ("NO MICROTRANSACTIONS*", "*ONLY MACRO ONES"), ("FAMILY FRIENDLY*", f"*EXCEPT {g['enemy']}")]
    prom = rng.choice(promises)
    card(wrap_upper(g["studio"], 14), 1.8, YELLOW, 3, sound="chime")
    card(["FROM THE STUDIO", "THAT BROUGHT YOU"] + wrap_upper(previous, 16), 2.2, WHITE, 2)
    gameplay(2.4)
    card(wrap_upper(prom[0], 14), 1.4, WHITE, 3)
    gameplay(2.6, dialog=True)
    card(wrap_upper(prom[1], 14), 1.2, RED, 3, sound="boom")
    gameplay(1.4)
    # название
    ctx.ev("boom")
    ctx.ev("laugh", 1.2)
    lines = wrap_upper(g["title"], 14)
    for f in range(int(3.2 * FPS)):
        cv.fill(BLACK)
        sh = rng.randint(-2, 2) if f < 20 else 0
        y0 = 150 - len(lines) * 13
        for i, line in enumerate(lines):
            cv.text(None, y0 + i * 26 + sh, line, YELLOW, 5 if len(line) <= 10 else 4, shadow=RED, center=True)
        cv.sprite(ctx.hero_rows[(f // 6) % 2], CW // 2 - 30, 230, ctx.hero_pal(), s=5)
        ctx.emit(cv)
    card([f"COMING {g['year'] + 30}", "ONLY ON"] + wrap_upper(g["console"], 16), 2.2, WHITE, 2, sound="chime")


def patch_notes(game: dict, rng: random.Random, n: int) -> list[str]:
    h, c, e, con = game["hero"], game["collectible"], game["enemy"], game["console"]
    pool = [f"FIXED A BUG WHERE THE {h} COULD SEE YOU", f"{h} NO LONGER FILES TAXES DURING BOSS FIGHTS",
            f"NERFED {e} BY 40%", f"{c} NOW HAVE FEELINGS", "REMOVED THE MOON (TEMPORARILY)",
            f"JUMPING NOW COSTS 2 {c}", f"ADDED A SECOND {h}. NOBODY KNOWS WHY", f"FIXED {e} CALLING YOUR MOM",
            "THE FINAL BOSS IS NOW YOUR LANDLORD", f"IMPROVED PERFORMANCE ON {con} BY 0.3 FPS",
            "DELETED LEVEL 4. IT KNOWS WHAT IT DID", f"THE {h} CAN NOW CRY (PRESS X)",
            "KNOWN ISSUE: THE GAME IS STILL RUNNING", "GRAVITY IS NOW OPTIONAL ON TUESDAYS",
            f"REDUCED {e} FROM 9000 TO 8999", "THE TUTORIAL NOW LIES LESS", "RAIN IS NOW WET",
            f"{e} WILL NO LONGER ASK ABOUT YOUR FUTURE", "FIXED A TYPO IN THE WORD ''GAME''",
            f"{c} NO LONGER SCREAM AT NIGHT", "ADDED BIKES. EVERYWHERE. YOU ARE WELCOME",
            "THE SUN NOW SETS (FINALLY)", f"YOU CAN NOW PET THE {e}. THEY HATE IT"]
    notes = rng.sample(pool, n)
    notes.append(rng.choice([f"REMOVED THE {h}", "REMOVED THE GAME", f"ADDED {sequel_title(game['title'], rng)}. PLAY IT. NOW",
                             "THE DEVELOPERS HAVE BEEN FREED"]))
    return notes


def scene_patch(ctx: Ctx, cv: Canvas) -> None:
    g, rng, p = ctx.game, ctx.rng, ctx.pal
    g["patch"] = g.get("patch", 0) + 1
    version = f"PATCH V1.0.{g['patch']}"
    notes = patch_notes(g, rng, rng.randint(4, 5))
    panel, border = (18, 22, 52), (120, 140, 255)
    title = wrap_upper(g["title"], 18)
    per = 2.4
    start = ctx.t
    note_i, typed = -1, 0
    ctx.ev("chime")
    total = per * len(notes) + 1.5
    while ctx.t - start < total:
        f = ctx.frames
        t = ctx.t - start
        idx = min(len(notes) - 1, int((t - 0.8) // per)) if t > 0.8 else -1
        if idx != note_i:
            note_i, typed = idx, 0
            if idx == len(notes) - 1:
                ctx.ev("boom")
                ctx.ev("laugh", 0.5)
            else:
                ctx.ev("blip")
        typed += 2
        cv.gradient(0, 0, CW, CH, shade(p["sky0"], 0.5), shade(p["sky0"], 0.2))
        cv.rect(10, 112, CW - 20, 300, panel)
        cv.frame_rect(10, 112, CW - 20, 300, border, 3)
        for i, line in enumerate(title):
            cv.text(None, 122 + i * 14, line, YELLOW, 2, shadow=BLACK, center=True)
        y = 124 + len(title) * 14 + 4
        cv.text(None, y, version, border, 2, center=True)
        y += 20
        for i in range(note_i + 1):
            wrapped = wrap_upper(notes[i], 27)
            color = RED if i == len(notes) - 1 else WHITE
            left = typed if i == note_i else 999
            for j, line in enumerate(wrapped):
                txt = ("- " if j == 0 else "  ") + line
                cv.text(18, y, txt[:max(0, left)], color, 2)
                left -= len(txt)
                y += 12
            y += 6
        cv.sprite(ctx.hero_rows[(f // 8) % 2], CW - 58, 372, ctx.hero_pal(), s=3)
        ctx.emit(cv)


SCENES = {"lost": scene_lost, "ad": scene_ad, "trailer": scene_trailer, "patch": scene_patch}

# ---------------------------------------------------------------------- звук


def _tone(freq_fn, dur: float, wave: str = "square", decay: float = 6.0, amp: float = 1.0) -> list[float]:
    out, ph = [], 0.0
    for i in range(int(dur * ma.SR)):
        t = i / ma.SR
        ph += freq_fn(t) / ma.SR
        x = ph % 1.0
        v = (1.0 if x < 0.5 else -1.0) if wave == "square" else (4 * abs(x - 0.5) - 1 if wave == "tri"
                                                                else 2 * x - 1)
        out.append(amp * v * math.exp(-t * decay) * min(1.0, i / 60))
    return out


def _noise(rng, dur: float, decay: float = 20.0, amp: float = 1.0) -> list[float]:
    return [amp * (rng.random() * 2 - 1) * math.exp(-i / ma.SR * decay) for i in range(int(dur * ma.SR))]


def sfx(kind: str, rng: random.Random) -> tuple[list[float], float]:
    if kind == "jump":
        return _tone(lambda t: 260 + 3800 * t, 0.13, "square", 8), 0.22
    if kind == "coin":
        return _tone(lambda t: 1046 if t < 0.05 else 2093, 0.22, "tri", 9), 0.3
    if kind == "stomp":
        return [a + b for a, b in zip(_noise(rng, 0.1, 30), _tone(lambda t: 140 - 300 * t, 0.1, "square", 20))], 0.35
    if kind == "hurt":
        return _tone(lambda t: 600 - 2000 * t, 0.25, "saw", 6), 0.3
    if kind == "blip":
        return _tone(lambda t: 1500, 0.03, "square", 40), 0.12
    if kind == "chime":
        out = [0.0] * int(1.4 * ma.SR)
        for k, f in enumerate([523, 659, 784, 1046]):
            for i, v in enumerate(_tone(lambda t, f=f: f, 1.0, "tri", 3.5)):
                j = i + int(k * 0.09 * ma.SR)
                if j < len(out):
                    out[j] += v * 0.5
        return out, 0.45
    if kind == "fail":
        out = []
        for f0, d in ((392, 0.28), (370, 0.28), (349, 0.28), (330, 0.9)):
            out += _tone(lambda t, f0=f0, d=d: f0 * (1 + (0.03 * math.sin(2 * math.pi * 6 * t) if d > 0.5 else 0)),
                         d, "saw", 1.5)
        return out, 0.4
    if kind == "gameover":
        out = []
        for f0 in (784, 659, 523, 392, 330, 262):
            out += _tone(lambda t, f0=f0: f0, 0.14, "square", 4)
        return out, 0.3
    if kind == "pin":
        return [a + b for a, b in zip(_noise(rng, 0.03, 80), _tone(lambda t: 2600, 0.03, "square", 60))], 0.25
    if kind == "sizzle":
        return [v * (0.6 + 0.4 * math.sin(i / 90)) for i, v in enumerate(_noise(rng, 1.0, 2.5))], 0.3
    if kind == "whoosh":
        n = int(0.5 * ma.SR)
        return [(rng.random() * 2 - 1) * math.sin(math.pi * i / n) ** 2 for i in range(n)], 0.3
    if kind == "fall":
        return _tone(lambda t: max(80.0, 900 - 1300 * t), 0.6, "square", 1.5), 0.25
    if kind == "boom":
        return ma.snd_boom(), 0.85
    if kind == "laugh":
        return ma.snd_laugh(rng), 0.65
    return [], 0.0


def chiptune(mix: "ma.Mixer", total: float, rng: random.Random, mood: str) -> None:
    bpm = {"creepy": rng.uniform(80, 100), "epic": rng.uniform(90, 110)}.get(mood, rng.uniform(125, 160))
    scale = {"creepy": [0, 1, 3, 6, 7, 8], "epic": [0, 2, 3, 5, 7, 8, 10]}.get(mood, [0, 2, 4, 7, 9])
    root = 220 * 2 ** (rng.randint(-4, 3) / 12)
    eighth = 30 / bpm
    pattern = [rng.choice(range(len(scale) * 2)) if rng.random() < 0.75 else None for _ in range(16)]
    bass = [rng.choice([0, 0, 3, 4, 5]) % len(scale) for _ in range(4)]
    buf, n = mix.buf, mix.n
    lead_amp = 0.0 if mood == "epic" else 0.07
    for e in range(int(total / eighth) + 1):
        t0 = e * eighth
        if e % 64 == 32:  # вариация мелодии, чтобы не надоедала
            pattern = [x if rng.random() < 0.7 else rng.choice(range(len(scale) * 2)) for x in pattern]
        if e % 2 == 0:
            deg = bass[(e // 8) % 4]
            f = root / 2 * 2 ** (scale[deg] / 12)
            ph = 0.0
            for i in range(int(t0 * ma.SR), min(n, int((t0 + eighth * 1.8) * ma.SR))):
                ph += f / ma.SR
                buf[i] += 0.11 * (1 if ph % 1 < 0.5 else -1) * math.exp(-(i / ma.SR - t0) * 2.5)
        deg = pattern[e % 16]
        if deg is not None and lead_amp:
            octave, idx = divmod(deg, len(scale))
            f = root * 2 * 2 ** ((scale[idx] + 12 * octave) / 12)
            ph = 0.0
            for i in range(int(t0 * ma.SR), min(n, int((t0 + eighth * 0.8) * ma.SR))):
                t = i / ma.SR - t0
                ph += f * (1 + 0.006 * math.sin(2 * math.pi * 5 * t)) / ma.SR
                buf[i] += lead_amp * (1 if ph % 1 < 0.25 else -1) * math.exp(-t * 3)
        if mood != "creepy" and e % 2 == 1:
            for i in range(int(t0 * ma.SR), min(n, int((t0 + 0.04) * ma.SR))):
                buf[i] += 0.035 * (rng.random() * 2 - 1)
    if mood == "creepy":  # шипение плёнки
        for i in range(n):
            buf[i] += 0.012 * (rng.random() * 2 - 1)


# ---------------------------------------------------------------- подписи

HOOKS = {
    "lost": ["found a VHS of a {year} game nobody remembers", "my uncle swears this {console} game was real",
             "the rarest {console} game ever made", "footage of {title} ({year}). why does nobody talk about this",
             "this {year} game got pulled from stores. now I know why"],
    "ad": ["mobile game ads be like", "this ad keeps following me", "99% fail this level. the other 1% also fail",
           "the {hero} game ad is getting out of hand", "every mobile game ad ever"],
    "trailer": ["{title} trailer just dropped", "they finally announced {title}", "nobody asked for {title}",
                "{title} looks insane (it doesn't exist)"],
    "patch": ["{title} patch notes are getting out of hand", "devs nerfed the {enemy} again",
              "{title} {version} patch notes (pause to read)"],
}
MOODS = {"lost": "creepy", "ad": "happy", "trailer": "epic", "patch": "happy"}


def build_video(rng: random.Random, seed: int, fmt: str, game: dict, out: Path, args,
                recent: list[str] | None = None) -> dict:
    options = [h for h in HOOKS[fmt] if h not in (recent or [])] or HOOKS[fmt]  # не повторять свежие подписи
    template = rng.choice(options)
    hook = template.format(
        year=game["year"], console=game["console"], title=game["title"], hero=game["hero"], enemy=game["enemy"],
        version=f"v1.0.{game.get('patch', 0) + 1}")
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        inter = tmp / "pixels.mkv"
        enc = subprocess.Popen(
            [mr.FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
             "-s", f"{CW}x{CH}", "-r", str(FPS), "-i", "-", "-c:v", "libx264rgb", "-qp", "0",
             "-preset", "ultrafast", str(inter)],
            stdin=subprocess.PIPE)
        ctx = Ctx(rng, game, enc.stdin)
        SCENES[fmt](ctx, Canvas(CW, CH))
        enc.stdin.close()
        if enc.wait() != 0:
            raise RuntimeError("не удалось записать кадры")
        total = ctx.frames / FPS

        mix = ma.Mixer(total + 0.1)
        chiptune(mix, total, rng, MOODS[fmt])
        cache: dict[str, tuple] = {}
        for t, kind in ctx.events:
            if kind not in cache or kind in ("laugh", "sizzle"):
                cache[kind] = sfx(kind, rng)
            samples, gain = cache[kind]
            mix.add(t, samples, gain)
        mix.wav(tmp / "audio.wav")

        (tmp / f"font{args.font_ext}").write_bytes(Path(args.font_path).read_bytes())
        texts = []
        for k, line in enumerate(textwrap.wrap(hook, 24)[:3]):
            (tmp / f"cap{k}.txt").write_text(line, encoding="utf-8")
            texts.append(f"drawtext=fontfile=font{args.font_ext}:textfile=cap{k}.txt:expansion=none:fontsize=70"
                         f":fontcolor=white:borderw=7:bordercolor=black:x=(w-text_w)/2:y={210 + k * 84}")
        vfx = {"lost": ",chromashift=cbh=4:crh=-4,noise=alls=9:allf=t,eq=saturation=0.85:contrast=1.06,"
                       "drawgrid=w=iw:h=8:t=3:c=black@0.22",
               "trailer": ",vignette=angle=PI/5", "patch": ",drawgrid=w=iw:h=8:t=2:c=black@0.12"}.get(fmt, "")
        afx = ",vibrato=f=1.3:d=0.05,lowpass=f=5500" if fmt == "lost" else ""
        graph = (f"[0:v]scale=1080:1920:flags=neighbor{vfx}," + ",".join(texts + ["format=yuv420p"]) + "[v];"
                 f"[1:a]aresample=48000,aformat=channel_layouts=stereo{afx},alimiter=limit=0.9[a]")
        part = out.with_name(out.stem + ".part.mp4")
        res = subprocess.run(
            [mr.FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(inter), "-i", "audio.wav",
             "-filter_complex", graph, "-map", "[v]", "-map", "[a]", "-t", f"{total:.3f}", "-r", str(FPS),
             "-c:v", "libx264", "-preset", args.preset, "-crf", str(args.crf), "-maxrate", "10M",
             "-bufsize", "20M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
             "-movflags", "+faststart", str(part)],
            cwd=tmp, capture_output=True, text=True)
        if res.returncode != 0:
            part.unlink(missing_ok=True)
            raise RuntimeError(res.stderr.strip()[:1500])
        part.replace(out)

    post = f"{hook}\n\nThis game does not exist. Would you play it?"
    if args.hashtags:
        post += "\n\n" + args.hashtags
    return {"video": out.name, "kind": "fakegame", "format": fmt, "game": game["title"], "seed": seed,
            "hook_template": template,
            "duration": round(total, 2), "caption": hook, "post_text": post,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S")}


def generate(count: int, args) -> list[Path]:
    args.output.mkdir(parents=True, exist_ok=True)
    made = []
    for i in range(count):
        seed = args.seed + i if args.seed is not None else random.randrange(10 ** 6)
        rng = random.Random(seed)
        universe = load_universe(args.universe)
        fmt, game, is_new = plan(rng, universe, args.format, args.weights)
        out = args.output / f"fakegame_{time.strftime('%Y%m%d_%H%M%S')}_{fmt}_{seed}.mp4"
        started = time.time()
        try:
            meta = build_video(rng, seed, fmt, game, out, args, universe.get("recent_hooks", []))
        except RuntimeError as err:
            mr.log(f"  ✗ {fmt}, зерно {seed}: {err}")
            continue
        game.setdefault("videos", []).append(out.name)
        universe["recent_hooks"] = (universe.get("recent_hooks", []) + [meta["hook_template"]])[-6:]
        if is_new:
            universe["games"].append(game)
        save_universe(universe, args.universe)
        out.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
        mr.log(f"  ✓ {out.name}  ({meta['duration']:.1f} с, {time.time() - started:.0f} с на сборку) — "
               f"{game['title']!r}: {meta['caption']!r}")
        made.append(out)
    return made


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Ролики про несуществующие игры.",
                                formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    p.add_argument("--count", type=int, default=1)
    p.add_argument("--format", choices=["auto", *FORMATS], default="auto",
                   help="lost — найденная кассета, ad — реклама мобилки, trailer — трейлер, patch — патч-ноты")
    p.add_argument("--output", type=Path, default=HERE / "output")
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--hashtags", default="#fakegame #gaming #retrogaming #pixelart #indiegame #fyp")
    p.add_argument("--font", dest="font_path", default=None)
    p.add_argument("--preset", default="medium")
    p.add_argument("--crf", type=int, default=20)
    p.add_argument("--weights", default="",
                   help="доли форматов при auto, например lost=3,ad=2,patch=1 (по умолчанию из исследования)")
    p.add_argument("--universe", type=Path, default=UNIVERSE, help="файл со всеми выдуманными играми")
    return p.parse_args(argv)


def prepare(args) -> None:
    weights = {}
    for part in filter(None, (x.strip() for x in str(args.weights).split(","))):
        name, _, val = part.partition("=")
        if name not in FORMATS:
            raise SystemExit(f"неизвестный формат в --weights: {name}")
        weights[name] = float(val or 1)
    args.weights = weights or None
    mr.FFMPEG, mr.FFPROBE = mr.need_tool("ffmpeg"), mr.need_tool("ffprobe")
    if not args.font_path:
        args.font_path = next((c for c in ma.IMPACT_CANDIDATES if Path(c).is_file()), None)
    args.font_path = str(mr.find_font(args.font_path))
    args.font_ext = Path(args.font_path).suffix.lower()


def main(argv=None) -> None:
    args = parse_args(argv)
    prepare(args)
    made = generate(args.count, args)
    mr.log(f"Готово роликов: {len(made)} → {args.output}")


if __name__ == "__main__":
    main()
