#!/usr/bin/env python3
"""Собирает вертикальные ролики-реакции для Reels и TikTok из готовых клипов.

Для каждого клипа из папки input:
  * вписывает клип в кадр 1080x1920 поверх размытой копии самого клипа;
  * накладывает видео смеющегося человека (зелёный или синий фон вырезается сам);
  * подмешивает закадровый смех в момент «кульминации» — самый резкий всплеск
    громкости в клипе (или в моменты, заданные вручную в sources.csv);
  * пишет подпись сверху и строку с автором и лицензией;
  * кладёт рядом с роликом .json с готовым текстом поста для автозаливки.

Нужны Python 3.9+ и ffmpeg/ffprobe в PATH. Сторонних библиотек нет.

Быстрый старт:
    python make_reels.py                 # обработать всё новое в input/
    python make_reels.py --watch 300     # проверять input/ каждые 5 минут
    python make_reels.py --help          # все настройки
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
from array import array
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent

W, H = 1080, 1920
FPS = 30
VIDEO_EXT = {".mp4", ".mov", ".mkv", ".webm", ".m4v", ".avi"}
AUDIO_EXT = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac", ".opus"}

# Безопасная зона кадра: сверху вкладки приложения, снизу ник и описание,
# справа кнопки лайков и комментариев. Важное держим внутри.
SAFE_TOP = 220
SAFE_BOTTOM = 1520
SAFE_LEFT = 40
SAFE_RIGHT = 920

FONT_CANDIDATES = [
    "C:/Windows/Fonts/arialbd.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


# ---------------------------------------------------------------- утилиты


def log(msg: str) -> None:
    print(msg, flush=True)


def need_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        sys.exit(f"Не найден {name}. Установите ffmpeg и добавьте его в PATH (см. README.md).")
    return path


FFMPEG = ""
FFPROBE = ""


@dataclass
class Media:
    path: Path
    duration: float
    width: int = 0
    height: int = 0
    has_audio: bool = False


def probe(path: Path) -> Media:
    out = subprocess.run(
        [FFPROBE, "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    info = json.loads(out)
    streams = info.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    has_audio = any(s.get("codec_type") == "audio" for s in streams)
    duration = float(info.get("format", {}).get("duration") or (video or {}).get("duration") or 0)
    width = height = 0
    if video:
        width, height = int(video["width"]), int(video["height"])
        rotation = 0
        for side in video.get("side_data_list", []):
            if "rotation" in side:
                rotation = int(side["rotation"])
        rotation = rotation or int(video.get("tags", {}).get("rotate", 0))
        if abs(rotation) % 180 == 90:  # телефонное видео, ffmpeg сам его повернёт
            width, height = height, width
    return Media(path, duration, width, height, has_audio)


def list_files(folder: Path, exts: set[str]) -> list[Path]:
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.iterdir() if p.suffix.lower() in exts and not p.name.startswith("."))


def find_font(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit)
        if not p.is_file():
            sys.exit(f"Шрифт не найден: {p}")
        return p
    local = list_files(HERE / "fonts", {".ttf", ".otf"})
    if local:
        return local[0]
    for cand in FONT_CANDIDATES:
        if Path(cand).is_file():
            return Path(cand)
    sys.exit("Не нашёл жирный шрифт. Положите .ttf в папку fonts/ или укажите --font.")


# ---------------------------------------------------------- описания клипов


@dataclass
class SourceInfo:
    url: str = ""
    author: str = ""
    license: str = ""
    caption: str = ""
    laugh_at: list[float] = field(default_factory=list)


def read_sources(path: Path) -> dict[str, SourceInfo]:
    """Читает sources.csv (разделитель «,» или «;», как сохранит Excel)."""
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8-sig")
    try:
        dialect = csv.Sniffer().sniff(text.splitlines()[0], delimiters=",;\t")
    except (csv.Error, IndexError):
        dialect = csv.excel
    result: dict[str, SourceInfo] = {}
    for row in csv.DictReader(text.splitlines(), dialect=dialect):
        row = {(k or "").strip().lower(): (v or "").strip() for k, v in row.items()}
        name = row.get("file", "")
        if not name:
            continue
        times = []
        for part in row.get("laugh_at", "").replace(",", " ").replace(";", " ").split():
            try:
                times.append(float(part))
            except ValueError:
                log(f"  ! sources.csv: не понял время смеха «{part}» у {name}")
        result[name.lower()] = SourceInfo(
            url=row.get("url", ""), author=row.get("author", ""), license=row.get("license", ""),
            caption=row.get("caption", ""), laugh_at=times,
        )
    return result


def credit_text(src: SourceInfo, label: str) -> str:
    if not src.author:
        return ""
    lic = f" ({src.license})" if src.license else ""
    return f"{label} {src.author}{lic}"


# ------------------------------------------------------------ анализ звука


def detect_punchlines(clip: Media, count: int) -> list[float]:
    """Ищет моменты резкого всплеска громкости — обычно это и есть «кульминация»."""
    if not clip.has_audio or count <= 0:
        return []
    raw = subprocess.run(
        [FFMPEG, "-v", "error", "-t", f"{clip.duration:.3f}", "-i", str(clip.path),
         "-vn", "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
        capture_output=True,
    ).stdout
    samples = array("h")
    samples.frombytes(raw[: len(raw) // 2 * 2])
    if sys.byteorder == "big":
        samples.byteswap()
    win, step = 2000, 0.25  # окна по 0,25 с
    rms = [
        math.sqrt(sum(x * x for x in samples[i:i + win]) / win)
        for i in range(0, len(samples) - win + 1, win)
    ]
    if not rms or max(rms) < 300:  # почти тишина
        return []
    lo, hi = max(1.0, clip.duration * 0.15), clip.duration - 1.0
    scored = []
    for i in range(4, len(rms)):
        t = i * step
        if lo <= t <= hi:
            before = sum(rms[i - 4:i]) / 4  # средняя громкость за секунду до
            scored.append((rms[i] - before, t))
    scored.sort(reverse=True)
    picked: list[float] = []
    for score, t in scored:
        if score <= 0 or len(picked) == count:
            break
        if all(abs(t - p) >= 5 for p in picked):
            picked.append(t)
    return sorted(picked)


def plan_laughs(clip: Media, src: SourceInfo, args, total: float) -> list[float]:
    if src.laugh_at:
        return [t for t in src.laugh_at if 0 <= t < total]
    count = args.laughs if args.laughs > 0 else (1 if clip.duration < 20 else 2)
    peaks = detect_punchlines(clip, count)
    if peaks:
        times = [t + args.reaction_delay for t in peaks]
    else:  # звука нет или он ровный — ставим смех ближе к концу
        times = [clip.duration * (0.55 if count == 1 else 0.35 + 0.35 * i) for i in range(count)]
    # смеху нужно хотя бы 1,5 с, иначе обрубится концом ролика
    return [max(0.0, min(t, total - 1.5)) for t in times]


def chroma_color(reaction: Path) -> str | None:
    """Определяет цвет фона (зелёный/синий экран) по краям кадра. None — фона нет."""
    raw = subprocess.run(
        [FFMPEG, "-v", "error", "-ss", "0.5", "-i", str(reaction), "-frames:v", "1",
         "-vf", "scale=32:32", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
    ).stdout
    if len(raw) < 32 * 32 * 3:
        return None
    px = lambda x, y: raw[(y * 32 + x) * 3:(y * 32 + x) * 3 + 3]  # noqa: E731
    border = [px(x, 0) for x in range(32)] + [px(0, y) for y in range(32)] + [px(31, y) for y in range(32)]
    r = sum(p[0] for p in border) / len(border)
    g = sum(p[1] for p in border) / len(border)
    b = sum(p[2] for p in border) / len(border)
    if (g > 80 and g > 1.3 * r and g > 1.3 * b) or (b > 80 and b > 1.3 * r and b > 1.3 * g):
        return f"0x{int(r):02X}{int(g):02X}{int(b):02X}"
    return None


# --------------------------------------------------------------- раскладка


@dataclass
class Layout:
    fg_w: int
    fg_h: int
    fg_x: int
    fg_y: int
    rx_w: int  # рамка, в которую вписывается реакция
    rx_h: int
    rx_x: str  # выражения для overlay
    rx_y: str
    caption_top: int | None  # None — подпись прижимается к низу cap_bottom
    caption_bottom: int
    credit_x: int
    credit_y: int


def make_layout(clip: Media, args, caption_lines: int, line_h: int) -> Layout:
    fg_w, fg_h = W, round(W * clip.height / clip.width / 2) * 2
    if fg_h > H:
        fg_w, fg_h = round(H * clip.width / clip.height / 2) * 2, H
    pos = args.reaction_pos
    if pos == "auto":
        pos = "below" if fg_h <= H * 0.55 else "bl"

    if pos == "below":
        # Горизонтальный клип: подпись над ним, реакция под ним.
        gap, min_box = 70, 360
        fg_y = SAFE_BOTTOM - min_box - gap - fg_h
        fg_y = max(SAFE_TOP + 180, min(fg_y, 430))
        top = fg_y + fg_h + gap
        box_h = max(200, SAFE_BOTTOM - top)
        return Layout(
            fg_w, fg_h, (W - fg_w) // 2, fg_y,
            rx_w=int(W * 0.72), rx_h=box_h, rx_x="(main_w-overlay_w)/2", rx_y=str(top),
            caption_top=None, caption_bottom=fg_y - 24,
            credit_x=SAFE_LEFT, credit_y=fg_y + fg_h + 14,
        )

    # Вертикальный или квадратный клип: реакция в углу поверх клипа.
    size = int(W * args.reaction_size)
    xs = {"l": str(SAFE_LEFT), "r": f"{SAFE_RIGHT}-overlay_w"}
    cap_end = SAFE_TOP + caption_lines * line_h
    ys = {"t": str(cap_end + 70), "b": f"{SAFE_BOTTOM}-overlay_h"}
    return Layout(
        fg_w, fg_h, (W - fg_w) // 2, (H - fg_h) // 2,
        rx_w=size, rx_h=size, rx_x=xs[pos[1]], rx_y=ys[pos[0]],
        caption_top=SAFE_TOP, caption_bottom=cap_end,
        credit_x=SAFE_LEFT, credit_y=cap_end + 16,
    )


# ------------------------------------------------------------ сборка ролика


def build_command(clip: Media, src: SourceInfo, reaction: Media, laughs: list[tuple[float, Media]],
                  out: Path, workdir: Path, args) -> list[str]:
    total = clip.duration + args.tail
    caption = textwrap.wrap(src.caption, args.wrap) if src.caption else []
    font_px, line_h = args.font_size, int(args.font_size * 1.25)
    lay = make_layout(clip, args, len(caption), line_h)

    cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y"]
    cmd += ["-t", f"{clip.duration:.3f}", "-i", str(clip.path)]
    rx_offset = random.uniform(0, max(0.0, reaction.duration - 1))
    cmd += ["-stream_loop", "-1", "-ss", f"{rx_offset:.2f}", "-i", str(reaction.path)]
    for _, laugh in laughs:
        offset = random.uniform(0, max(0.0, laugh.duration - args.laugh_len))
        cmd += ["-stream_loop", "-1", "-ss", f"{offset:.2f}", "-i", str(laugh.path)]

    g: list[str] = []
    # фон: тот же клип, растянутый на весь кадр, размытый и затемнённый
    g.append(f"[0:v]fps={FPS},tpad=stop_mode=clone:stop_duration={args.tail},split=2[bg0][fg0]")
    g.append("[bg0]scale=270:480:force_original_aspect_ratio=increase,crop=270:480,"
             "boxblur=8:2,scale=1080:1920,eq=brightness=-0.12,setsar=1[bg]")
    g.append(f"[fg0]scale={lay.fg_w}:{lay.fg_h},setsar=1[fg]")
    g.append(f"[bg][fg]overlay={lay.fg_x}:{lay.fg_y}[base]")

    key = None if args.chroma == "off" else chroma_color(reaction.path)
    if args.chroma == "on" and not key:
        key = "0x00B140"
    rx = (f"[1:v]fps={FPS},scale=w={lay.rx_w}:h={lay.rx_h}:"
          f"force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1")
    if key:
        rx += (f",chromakey=color={key}:similarity={args.similarity}:blend={args.blend},"
               f"despill=type={'green' if int(key[4:6], 16) >= int(key[6:8], 16) else 'blue'}")
    else:
        rx += ",pad=iw+12:ih+12:6:6:white"  # без зелёного фона — белая рамка
    g.append(rx + ",format=yuva420p[rx]")
    enable = ""
    if args.reaction_show == "laugh" and laughs:
        enable = f":enable='gte(t,{max(0.0, laughs[0][0] - 0.3):.2f})'"
    g.append(f"[base][rx]overlay=x={lay.rx_x}:y={lay.rx_y}{enable}[v1]")

    font = workdir / ("font" + Path(args.font_path).suffix)
    shutil.copyfile(args.font_path, font)
    texts = []
    if caption:
        top = lay.caption_top
        if top is None:  # прижимаем блок подписи к клипу снизу
            top = max(140, lay.caption_bottom - len(caption) * line_h)
        for i, line in enumerate(caption):
            name = f"cap{i}.txt"
            (workdir / name).write_text(line, encoding="utf-8")
            texts.append(f"drawtext=fontfile={font.name}:textfile={name}:expansion=none:"
                         f"fontsize={font_px}:fontcolor=white:borderw=6:bordercolor=black:"
                         f"x=(w-text_w)/2:y={top + i * line_h}")
    credit = credit_text(src, args.credit_label)
    if credit:
        (workdir / "credit.txt").write_text(credit, encoding="utf-8")
        texts.append(f"drawtext=fontfile={font.name}:textfile=credit.txt:expansion=none:"
                     f"fontsize=30:fontcolor=white@0.9:borderw=2:bordercolor=black@0.8:"
                     f"x={lay.credit_x}:y={lay.credit_y}")
    g.append("[v1]" + ",".join(texts + ["format=yuv420p"]) + "[vout]")

    # звук: оригинал + смех, наложенный в нужные моменты
    norm = "aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo"
    if clip.has_audio:
        g.append(f"[0:a]{norm},apad,atrim=0:{total:.3f},volume={args.clip_volume}[a0]")
    else:
        g.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{total:.3f}[a0]")
    mix = ["[a0]"]
    for i, (t, _) in enumerate(laughs):
        length = max(1.0, min(args.laugh_len, total - t))
        fade_out = min(1.0, length / 2)
        g.append(f"[{2 + i}:a]{norm},atrim=0:{length:.3f},asetpts=PTS-STARTPTS,"
                 f"afade=t=in:d=0.15,afade=t=out:st={length - fade_out:.3f}:d={fade_out:.3f},"
                 f"volume={args.laugh_volume},adelay=delays={int(t * 1000)}:all=1[l{i}]")
        mix.append(f"[l{i}]")
    g.append(f"{''.join(mix)}amix=inputs={len(mix)}:duration=first:normalize=0,"
             f"alimiter=limit=0.95[aout]")

    cmd += ["-filter_complex", ";".join(g), "-map", "[vout]", "-map", "[aout]",
            "-t", f"{total:.3f}", "-r", str(FPS),
            "-c:v", "libx264", "-preset", args.preset, "-crf", str(args.crf),
            "-profile:v", "high", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
            "-movflags", "+faststart", str(out)]
    return cmd


def post_text(src: SourceInfo, args) -> str:
    parts = []
    if src.caption:
        parts.append(src.caption)
    credit = credit_text(src, args.credit_label)
    if credit:
        parts.append(credit + (f"\n{src.url}" if src.url else ""))
    if args.hashtags:
        parts.append(args.hashtags)
    return "\n\n".join(parts)


def process_clip(path: Path, sources: dict[str, SourceInfo], reactions: list[Media],
                 laugh_files: list[Media], args) -> bool:
    out = args.output / f"{path.stem}.mp4"
    if out.exists() and not args.overwrite:
        return False
    clip = probe(path)
    if not clip.width or clip.duration <= 0:
        log(f"  ! {path.name}: не похоже на видео, пропускаю")
        return False
    src = sources.get(path.name.lower(), SourceInfo())
    if not src.author:
        if args.require_credit:
            log(f"  ! {path.name}: в sources.csv нет автора — пропускаю (--require-credit)")
            return False
        log(f"  ! {path.name}: в sources.csv нет автора — подписи об источнике не будет")
    if clip.duration > args.max_duration:
        log(f"  · {path.name}: {clip.duration:.0f} с, обрезаю до {args.max_duration:.0f} с")
        clip.duration = args.max_duration

    total = clip.duration + args.tail
    laugh_times = plan_laughs(clip, src, args, total)
    laughs = [(t, random.choice(laugh_files)) for t in laugh_times]
    reaction = random.choice(reactions)

    part = out.with_name(out.stem + ".part.mp4")
    with tempfile.TemporaryDirectory() as tmp:
        cmd = build_command(clip, src, reaction, laughs, part, Path(tmp), args)
        if args.dry_run:
            log(" ".join(f'"{c}"' if " " in c or ";" in c else c for c in cmd))
            return False
        started = time.time()
        res = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
    if res.returncode != 0:
        part.unlink(missing_ok=True)
        log(f"  ✗ {path.name}: ffmpeg завершился с ошибкой\n{res.stderr.strip()[-2000:]}")
        return False
    part.replace(out)
    meta = {
        "video": out.name,
        "source_file": path.name,
        "source_url": src.url,
        "author": src.author,
        "license": src.license,
        "duration": round(total, 2),
        "laugh_at": [round(t, 2) for t in laugh_times],
        "reaction": reaction.path.name,
        "post_text": post_text(src, args),
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    out.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    laugh_info = ", ".join(f"{t:.1f} с" for t in laugh_times) or "нет"
    log(f"  ✓ {out.name}  ({total:.1f} с, смех: {laugh_info}, {time.time() - started:.0f} с на сборку)")
    return True


def run_once(args) -> int:
    clips = list_files(args.input, VIDEO_EXT)
    reactions = [probe(p) for p in list_files(args.reactions, VIDEO_EXT)]
    laugh_files = [probe(p) for p in list_files(args.laughs_dir, AUDIO_EXT | VIDEO_EXT)]
    if not reactions:
        sys.exit(f"Нет видео реакций в {args.reactions}")
    laugh_files = [m for m in laugh_files if m.has_audio or m.path.suffix.lower() in AUDIO_EXT]
    if not laugh_files:
        sys.exit(f"Нет звуков смеха в {args.laughs_dir}")
    sources = read_sources(args.sources)
    args.output.mkdir(parents=True, exist_ok=True)
    done = 0
    for path in clips:
        if args.limit and done >= args.limit:
            break
        if process_clip(path, sources, reactions, laugh_files, args):
            done += 1
    return done


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Собирает вертикальные ролики-реакции (1080x1920) для Reels и TikTok.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--input", type=Path, default=HERE / "input", help="папка с исходными клипами")
    p.add_argument("--reactions", type=Path, default=HERE / "assets" / "reactions",
                   help="папка с видео смеющегося человека")
    p.add_argument("--laughs-dir", type=Path, default=HERE / "assets" / "laughs",
                   help="папка со звуками смеха")
    p.add_argument("--sources", type=Path, default=HERE / "sources.csv",
                   help="таблица: автор, лицензия, ссылка, подпись, моменты смеха")
    p.add_argument("--output", type=Path, default=HERE / "output", help="куда класть готовые ролики")

    p.add_argument("--reaction-pos", choices=["auto", "below", "bl", "br", "tl", "tr"], default="auto",
                   help="где реакция: под клипом или в углу (b/t — низ/верх, l/r — лево/право)")
    p.add_argument("--reaction-size", type=float, default=0.4, help="размер реакции в углу, доля ширины")
    p.add_argument("--reaction-show", choices=["always", "laugh"], default="always",
                   help="показывать реакцию весь ролик или только с первого смеха")
    p.add_argument("--reaction-delay", type=float, default=0.35,
                   help="через сколько секунд после кульминации начинается смех")
    p.add_argument("--chroma", choices=["auto", "on", "off"], default="auto",
                   help="вырезать зелёный/синий фон у реакции")
    p.add_argument("--similarity", type=float, default=0.16, help="chromakey: насколько широко брать цвет фона")
    p.add_argument("--blend", type=float, default=0.08, help="chromakey: мягкость края")

    p.add_argument("--laughs", type=int, default=0, help="сколько раз смеяться за ролик (0 — авто)")
    p.add_argument("--laugh-len", type=float, default=4.0, help="длина одного смеха, с")
    p.add_argument("--laugh-volume", type=float, default=0.7, help="громкость смеха")
    p.add_argument("--clip-volume", type=float, default=1.0, help="громкость оригинального звука")
    p.add_argument("--tail", type=float, default=1.5, help="сколько секунд держать последний кадр под смех")
    p.add_argument("--max-duration", type=float, default=170, help="обрезать клипы длиннее, с")

    p.add_argument("--font", dest="font_path", default=None, help="путь к .ttf для подписей")
    p.add_argument("--font-size", type=int, default=62)
    p.add_argument("--wrap", type=int, default=24, help="сколько символов в строке подписи")
    p.add_argument("--credit-label", default="Video:", help="слово перед именем автора")
    p.add_argument("--hashtags", default="", help="хэштеги в текст поста, например \"#funny #fail\"")
    p.add_argument("--require-credit", action="store_true",
                   help="пропускать клипы без автора в sources.csv")

    p.add_argument("--preset", default="medium", help="скорость x264: veryfast … slow")
    p.add_argument("--crf", type=int, default=20, help="качество x264: меньше — лучше и тяжелее")
    p.add_argument("--limit", type=int, default=0, help="собрать не больше N роликов за проход")
    p.add_argument("--overwrite", action="store_true", help="пересобирать уже готовые")
    p.add_argument("--seed", type=int, default=None, help="зерно случайности для повторяемости")
    p.add_argument("--dry-run", action="store_true", help="только показать команды ffmpeg")
    p.add_argument("--watch", type=int, default=0, metavar="СЕК",
                   help="не завершаться, а проверять input/ каждые СЕК секунд")
    return p.parse_args(argv)


def main(argv=None) -> None:
    global FFMPEG, FFPROBE
    args = parse_args(argv)
    FFMPEG, FFPROBE = need_tool("ffmpeg"), need_tool("ffprobe")
    args.font_path = str(find_font(args.font_path))
    if args.seed is not None:
        random.seed(args.seed)
    while True:
        log(f"Ищу новые клипы в {args.input} …")
        made = run_once(args)
        log(f"Готово роликов: {made}" + ("" if args.dry_run else f" → {args.output}"))
        if not args.watch:
            break
        time.sleep(args.watch)


if __name__ == "__main__":
    main()
