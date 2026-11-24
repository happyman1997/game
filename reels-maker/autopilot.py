#!/usr/bin/env python3
"""Автопилот: держит запас готовых роликов и выкладывает их по расписанию.

    python autopilot.py          # работать постоянно (окно должно оставаться открытым)
    python autopilot.py --once   # сделать ролик, если очередь пуста, и выложить сейчас —
                                 # для Планировщика заданий Windows или cron

Расписание и источник роликов — в разделе "autopilot" файла config.json.
"""

from __future__ import annotations

import argparse
import datetime as dt
import random
import time
import traceback
from pathlib import Path

import make_absurd as ma
import make_fakegame as fg
import make_reels as mr
import upload as up

HERE = Path(__file__).resolve().parent
STATE_FILE = up.STATE_DIR / "autopilot.json"


def log(msg: str) -> None:
    up.log(f"[{dt.datetime.now():%H:%M}] {msg}")


def queue_size(uploader: up.Uploader) -> int:
    if not uploader.platforms:
        return len(uploader.videos())
    return min(len(uploader.pending(p)) for p in uploader.platforms)


def make_one(uploader: up.Uploader, cfg: dict) -> bool:
    """Собирает один ролик.

    source: fakegame — несуществующие игры, absurd — абсурд, mix — 70/30 игры и абсурд,
            reels — клипы из input/, both — сначала клипы, потом абсурд.
    """
    source = cfg.get("source", "fakegame")
    if source == "mix":
        source = random.choices(["fakegame", "absurd"], [0.7, 0.3])[0]
    if source == "fakegame":
        fargs = fg.parse_args(["--output", str(uploader.output), *cfg.get("fakegame_args", [])])
        fg.prepare(fargs)
        return bool(fg.generate(1, fargs))
    if source in ("reels", "both"):
        try:
            rargs = mr.parse_args(["--output", str(uploader.output), "--limit", "1", *cfg.get("reels_args", [])])
            mr.FFMPEG, mr.FFPROBE = mr.need_tool("ffmpeg"), mr.need_tool("ffprobe")
            rargs.font_path = str(mr.find_font(rargs.font_path))
            if mr.run_once(rargs):
                return True
        except SystemExit as err:  # нет реакций, смеха и т. п.
            log(f"reels: {err}")
    if source in ("absurd", "both"):
        aargs = ma.parse_args(["--output", str(uploader.output), *cfg.get("absurd_args", [])])
        ma.prepare(aargs)
        return bool(ma.generate(1, aargs))
    return False


def refill(uploader: up.Uploader, cfg: dict, need: int) -> None:
    have = queue_size(uploader)
    while have < need:
        log(f"в очереди {have}, нужно {need} — делаю ролик")
        if not make_one(uploader, cfg):
            log("не получилось сделать ролик")
            return
        have += 1


def post_all(uploader: up.Uploader) -> None:
    for name in uploader.platforms:
        uploader.post_next(name)


def slots(cfg: dict, day: dt.date) -> list[tuple[str, dt.datetime]]:
    jitter = float(cfg.get("jitter_minutes", 15))
    result = []
    for hhmm in cfg.get("post_times", ["11:40", "16:20", "20:50"]):
        h, m = (int(x) for x in hhmm.split(":"))
        base = dt.datetime.combine(day, dt.time(h, m))
        shift = random.Random(f"{day}{hhmm}").uniform(-jitter, jitter)  # каждый день чуть разное время
        result.append((f"{day} {hhmm}", base + dt.timedelta(minutes=shift)))
    return result


def run_forever(config_path: Path) -> None:
    state = up.load_json(STATE_FILE, {"done": []})
    log("автопилот запущен. Остановить — Ctrl+C")
    announced = None
    while True:
        try:
            uploader = up.Uploader(config_path)
            cfg = uploader.config.get("autopilot", {})
            now = dt.datetime.now()
            today = slots(cfg, now.date())
            for key, at in today:
                if key in state["done"]:
                    continue
                if at <= now <= at + dt.timedelta(hours=2):
                    log(f"время публикации ({at:%H:%M})")
                    refill(uploader, cfg, 1)
                    post_all(uploader)
                    state["done"].append(key)
                elif now > at + dt.timedelta(hours=2):
                    state["done"].append(key)  # пропущено (компьютер был выключен) — не догоняем
            state["done"] = state["done"][-200:]
            up.save_json(STATE_FILE, state)

            refill(uploader, cfg, int(cfg.get("min_queue", 3)))
            upcoming = [at for key, at in today + slots(cfg, now.date() + dt.timedelta(days=1))
                        if key not in state["done"] and at > now]
            if upcoming and upcoming[0] != announced:
                announced = upcoming[0]
                log(f"следующая публикация в {announced:%d.%m %H:%M}, в очереди {queue_size(uploader)}")
        except KeyboardInterrupt:
            raise
        except Exception:  # автопилот не должен падать из-за одной ошибки
            log("ошибка:\n" + traceback.format_exc())
        time.sleep(60)


def main(argv=None) -> None:
    p = argparse.ArgumentParser(description="Генерирует и выкладывает ролики по расписанию.")
    p.add_argument("--config", type=Path, default=HERE / "config.json")
    p.add_argument("--once", action="store_true", help="выложить один ролик сейчас и выйти")
    args = p.parse_args(argv)
    if args.once:
        uploader = up.Uploader(args.config)
        refill(uploader, uploader.config.get("autopilot", {}), 1)
        post_all(uploader)
        return
    try:
        run_forever(args.config)
    except KeyboardInterrupt:
        log("остановлено")


if __name__ == "__main__":
    main()
