#!/usr/bin/env python3
"""Генерирует искусственные тестовые файлы, чтобы проверить сборку без настоящих роликов.

    python make_demo_assets.py demo
    python make_reels.py --input demo/input --reactions demo/reactions \
        --laughs-dir demo/laughs --sources demo/sources.csv --output demo/output
"""

import subprocess
import sys
from pathlib import Path


def ff(*args: str) -> None:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "demo")
    for sub in ("input", "reactions", "laughs"):
        (root / sub).mkdir(parents=True, exist_ok=True)

    # клипы: тихий тон и резкий «бах» — его скрипт должен принять за кульминацию
    for name, size, dur, boom in (("landscape", "1280x720", 12, 7), ("vertical", "720x1280", 9, 5)):
        ff("-f", "lavfi", "-i", f"testsrc2=s={size}:r=30:d={dur}",
           "-f", "lavfi", "-i",
           f"aevalsrc='0.05*sin(2*PI*220*t)+0.8*between(t,{boom},{boom}+0.5)*(random(0)-0.5)':s=44100:d={dur}",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
           str(root / "input" / f"{name}.mp4"))

    # «человек» на зелёном фоне: жёлтое лицо, которое трясётся от смеха
    ff("-f", "lavfi", "-i", "color=c=0x00B140:s=640x640:r=30:d=6",
       "-vf", "drawbox=x=170:y='170+25*abs(sin(2*PI*2.5*t))':w=300:h=300:color=yellow:t=fill,"
              "drawbox=x=230:y='370+25*abs(sin(2*PI*2.5*t))':w=180:h=60:color=black:t=fill",
       "-c:v", "libx264", "-pix_fmt", "yuv420p", str(root / "reactions" / "laugher.mp4"))

    # «смех»: тон с вибрато и пульсацией «ха-ха-ха»
    ff("-f", "lavfi", "-i",
       "aevalsrc='0.4*sin(2*PI*(320+60*sin(2*PI*5*t))*t)*(0.5+0.5*sin(2*PI*6*t))':s=44100:d=6",
       str(root / "laughs" / "laugh.wav"))

    (root / "sources.csv").write_text(
        "file;url;author;license;caption;laugh_at\n"
        "landscape.mp4;https://www.youtube.com/watch?v=EXAMPLE;Demo Author;CC BY 4.0;"
        "When you try to look cool and the floor disagrees;\n"
        "vertical.mp4;;Другой Автор;с разрешения автора;Проверка: подпись на русском с переносом строк;\n",
        encoding="utf-8",
    )
    print(f"Тестовые файлы созданы в {root}")


if __name__ == "__main__":
    main()
