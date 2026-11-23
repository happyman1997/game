#!/usr/bin/env python3
"""Заливает готовые ролики из output/ в Instagram Reels и TikTok через официальные API.

    python upload.py status              # очередь, токены, что ждёт публикации
    python upload.py check               # проверить доступы и подсказать ID аккаунтов
    python upload.py tiktok-login        # один раз: войти в TikTok через браузер
    python upload.py post                # выложить следующий ролик на все включённые площадки
    python upload.py post --platform tiktok --count 2

Настройки — в config.json (образец: config.example.json), токены и история — в папке state/.
Нужен только Python 3.9+, сторонних библиотек нет.
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATE_DIR = HERE / "state"
MAX_ATTEMPTS = 3


def log(msg: str) -> None:
    print(msg, flush=True)


class ApiError(Exception):
    """Площадка отклонила конкретный ролик — после нескольких попыток он пропускается."""


class SetupError(ApiError):
    """Проблема с доступом, настройками, лимитами или сетью — ролик не виноват, попытка не засчитывается."""


# ошибки Graph API, которые означают проблему с токеном, правами или лимитами
IG_SETUP_CODES = {4, 10, 17, 32, 190, 200, 613}
TT_SETUP_CODES = {"access_token_invalid", "scope_not_authorized", "rate_limit_exceeded", "spam_risk_too_many_posts",
                  "spam_risk_too_many_pending_share", "reached_active_user_cap", "spam_risk_user_banned_from_posting",
                  "unaudited_client_can_only_post_to_private_accounts"}


# ------------------------------------------------------------------ файлы


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def load_config(path: Path) -> dict:
    if not path.is_file():
        sys.exit(f"Нет {path.name}. Скопируйте config.example.json в config.json и заполните (см. README.md).")
    return json.loads(path.read_text(encoding="utf-8"))


# ------------------------------------------------------------------- HTTP


def request(method: str, url: str, *, params=None, form=None, json_body=None, body: bytes | None = None,
         headers=None, timeout: int = 300) -> tuple[int, dict]:
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    hdrs = dict(headers or {})
    data = None
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        hdrs.setdefault("Content-Type", "application/x-www-form-urlencoded")
    elif json_body is not None:
        data = json.dumps(json_body).encode()
        hdrs.setdefault("Content-Type", "application/json; charset=UTF-8")
    elif body is not None:
        data = body
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read()
    except urllib.error.URLError as err:
        raise SetupError(f"нет соединения с {urllib.parse.urlparse(url).netloc}: {err.reason}") from None
    try:
        payload = json.loads(raw.decode("utf-8") or "{}")
    except ValueError:
        payload = {"raw": raw.decode("utf-8", "replace")[:500]}
    return status, payload if isinstance(payload, dict) else {"data": payload}


# -------------------------------------------------------------- Instagram


class Instagram:
    """Instagram Graph API.

    mode "local": файл грузится прямо с диска (resumable upload). Нужен токен Facebook Login
                  (graph.facebook.com) и Instagram-аккаунт, привязанный к странице Facebook.
    mode "url":   Instagram сам скачивает ролик по публичной ссылке public_base_url/<файл>.
                  Подходит токен Instagram Login (graph.instagram.com), страница Facebook не нужна.
    """

    name = "instagram"

    def __init__(self, cfg: dict, tokens: dict):
        self.cfg, self.tokens = cfg, tokens
        self.mode = cfg.get("mode", "local")
        default_host = "https://graph.facebook.com" if self.mode == "local" else "https://graph.instagram.com"
        self.host = cfg.get("graph_host", default_host).rstrip("/")
        self.ver = cfg.get("api_version", "v27.0")
        self.ig_id = str(cfg.get("ig_user_id", "")).strip()

    # токен: сначала обновлённый из state/, иначе из config.json
    @property
    def token(self) -> str:
        saved = self.tokens.get("instagram", {})
        tok = saved.get("access_token") or self.cfg.get("access_token", "")
        if not tok:
            raise SetupError("в config.json не заполнен instagram.access_token")
        return tok

    def api(self, method: str, path: str, **params) -> dict:
        params["access_token"] = self.token
        kwargs = {"params": params} if method == "GET" else {"form": params}
        status, data = request(method, f"{self.host}/{self.ver}/{path.lstrip('/')}", **kwargs)
        if status >= 400 or "error" in data:
            err = data.get("error", {})
            msg = err.get("error_user_msg") or err.get("message") or data
            kind = SetupError if (err.get("code") in IG_SETUP_CODES or status >= 500) else ApiError
            raise kind(f"Instagram {status}: {msg} (code {err.get('code')}/{err.get('error_subcode')})")
        return data

    def maybe_refresh(self) -> None:
        """Токены Instagram Login живут 60 дней; продлеваем раз в неделю."""
        if self.mode != "url" or not self.cfg.get("auto_refresh", True):
            return
        saved = self.tokens.setdefault("instagram", {})
        now = time.time()
        if now - saved.get("refreshed_at", 0) < 7 * 86400 or now - saved.get("refresh_tried_at", 0) < 86400:
            return
        saved["refresh_tried_at"] = now  # токен младше суток продлить нельзя — тогда повторим завтра
        status, data = request("GET", f"{self.host}/refresh_access_token",
                               params={"grant_type": "ig_refresh_token", "access_token": self.token})
        if status == 200 and data.get("access_token"):
            saved.update(access_token=data["access_token"], refreshed_at=now,
                         expires_at=now + int(data.get("expires_in", 0)))
            log("  · Instagram: токен продлён на 60 дней")

    def check(self) -> None:
        if self.mode == "url":
            me = self.api("GET", "me", fields="user_id,username")
            log(f"  Instagram: @{me.get('username')}, user_id {me.get('user_id')}")
            if not self.ig_id:
                log(f"  → впишите \"ig_user_id\": \"{me.get('user_id')}\" в config.json")
        else:
            if self.ig_id:
                me = self.api("GET", self.ig_id, fields="username")
                log(f"  Instagram: @{me.get('username')}, ig_user_id {self.ig_id}")
            else:
                pages = self.api("GET", "me/accounts", fields="name,instagram_business_account{id,username}")
                for page in pages.get("data", []):
                    acc = page.get("instagram_business_account")
                    if acc:
                        log(f"  Страница «{page.get('name')}» → @{acc.get('username')}: "
                            f"впишите \"ig_user_id\": \"{acc.get('id')}\" в config.json")
                if not pages.get("data"):
                    log("  ! Токен не видит ни одной страницы Facebook с привязанным Instagram")
            try:
                dbg = self.api("GET", "debug_token", input_token=self.token).get("data", {})
                exp = dbg.get("expires_at", 0)
                left = "бессрочный" if not exp else f"истекает через {(exp - time.time()) / 86400:.0f} дн."
                log(f"  Токен: {left}")
            except ApiError:
                pass
        if self.ig_id:
            lim = self.api("GET", f"{self.ig_id}/content_publishing_limit", fields="config,quota_usage")
            row = (lim.get("data") or [{}])[0]
            log(f"  Публикаций через API за сутки: {row.get('quota_usage', '?')} из "
                f"{row.get('config', {}).get('quota_total', 100)}")

    def post(self, video: Path, caption: str) -> dict:
        if not self.ig_id:
            raise SetupError("в config.json не заполнен instagram.ig_user_id (подскажет: python upload.py check)")
        self.maybe_refresh()
        if self.mode == "local":
            size = video.stat().st_size
            cont = self.api("POST", f"{self.ig_id}/media", media_type="REELS", upload_type="resumable",
                            caption=caption)
            cid = cont["id"]
            uri = cont.get("uri") or f"https://rupload.facebook.com/ig-api-upload/{self.ver}/{cid}"
            log(f"  · Instagram: загружаю {size / 1e6:.1f} МБ")
            status, data = request("POST", uri, body=video.read_bytes(), timeout=900, headers={
                "Authorization": f"OAuth {self.token}", "offset": "0", "file_size": str(size),
                "Content-Type": "application/octet-stream"})
            if status >= 400 or not data.get("success"):
                raise ApiError(f"Instagram: загрузка файла не удалась ({status}): {data}")
        else:
            base = self.cfg.get("public_base_url", "").rstrip("/")
            if not base:
                raise SetupError("для mode \"url\" заполните instagram.public_base_url")
            url = f"{base}/{urllib.parse.quote(video.name)}"
            cid = self.api("POST", f"{self.ig_id}/media", media_type="REELS", video_url=url, caption=caption)["id"]

        log("  · Instagram: жду обработки видео")
        deadline = time.time() + 15 * 60
        while True:
            st = self.api("GET", cid, fields="status_code,status")
            code = st.get("status_code")
            if code == "FINISHED":
                break
            if code in ("ERROR", "EXPIRED"):
                raise ApiError(f"Instagram не принял видео: {st.get('status') or code}")
            if time.time() > deadline:
                raise ApiError("Instagram обрабатывает видео дольше 15 минут")
            time.sleep(float(self.cfg.get("poll_seconds", 15)))
        media = self.api("POST", f"{self.ig_id}/media_publish", creation_id=cid)
        return {"id": media.get("id"), "container": cid}


# ------------------------------------------------------------------ TikTok


class TikTok:
    """TikTok Content Posting API.

    mode "inbox":  ролик приходит в TikTok как черновик-уведомление, вы публикуете его одним нажатием
                   (scope video.upload; не больше 5 неопубликованных за сутки).
    mode "direct": публикуется сразу (scope video.publish). Пока приложение не прошло аудит TikTok,
                   такие ролики видны только вам.
    """

    name = "tiktok"
    AUTH_URL = "https://www.tiktok.com/v2/auth/authorize/"

    def __init__(self, cfg: dict, tokens: dict):
        self.cfg, self.tokens = cfg, tokens
        self.mode = cfg.get("mode", "inbox")
        self.api_base = cfg.get("api_base", "https://open.tiktokapis.com").rstrip("/")
        self.port = int(cfg.get("redirect_port", 3455))

    @property
    def redirect_uri(self) -> str:
        return f"http://localhost:{self.port}/callback/"

    def _need(self, key: str) -> str:
        val = self.cfg.get(key, "")
        if not val:
            raise SetupError(f"в config.json не заполнен tiktok.{key}")
        return val

    def _save_token(self, data: dict) -> None:
        now = time.time()
        self.tokens["tiktok"] = {
            "access_token": data["access_token"], "expires_at": now + int(data.get("expires_in", 7200)),
            "refresh_token": data["refresh_token"],
            "refresh_expires_at": now + int(data.get("refresh_expires_in", 180 * 86400)),
            "open_id": data.get("open_id"), "scope": data.get("scope"),
        }

    def _token_request(self, form: dict) -> dict:
        form = {"client_key": self._need("client_key"), "client_secret": self._need("client_secret"), **form}
        status, data = request("POST", f"{self.api_base}/v2/oauth/token/", form=form)
        if status >= 400 or not data.get("access_token"):
            raise SetupError(f"TikTok: не удалось получить токен ({status}): "
                           f"{data.get('error_description') or data.get('error') or data}")
        return data

    def login(self, open_browser: bool = True) -> None:
        scopes = ["user.info.basic", "video.upload"] + (["video.publish"] if self.mode == "direct" else [])
        verifier = secrets.token_urlsafe(72)[:96]
        # Особенность TikTok для десктопа: challenge — SHA256 в шестнадцатеричном виде, а не base64url.
        challenge = hashlib.sha256(verifier.encode()).hexdigest()
        state = secrets.token_urlsafe(16)
        url = self.AUTH_URL + "?" + urllib.parse.urlencode({
            "client_key": self._need("client_key"), "scope": ",".join(scopes), "response_type": "code",
            "redirect_uri": self.redirect_uri, "state": state,
            "code_challenge": challenge, "code_challenge_method": "S256"})

        result: dict = {}

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
                if "code" not in q and "error" not in q:
                    self.send_response(404)
                    self.end_headers()
                    return
                result.update(q)
                ok = q.get("state") == state and "code" in q
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                text = "Готово! Вкладку можно закрыть." if ok else "Вход не удался, смотрите терминал."
                self.wfile.write(f"<h2 style='font-family:sans-serif'>{text}</h2>".encode())

            def log_message(self, *a):
                pass

        server = http.server.HTTPServer(("127.0.0.1", self.port), Handler)
        server.timeout = 1
        log("Откройте ссылку и разрешите доступ (браузер должен открыться сам):\n" + url)
        if open_browser:
            webbrowser.open(url)
        deadline = time.time() + 600
        while not result and time.time() < deadline:
            server.handle_request()
        server.server_close()
        if not result:
            raise ApiError("TikTok: не дождался входа за 10 минут")
        if result.get("state") != state:
            raise ApiError("TikTok: state не совпал — попробуйте войти ещё раз")
        if "error" in result:
            raise ApiError(f"TikTok: {result.get('error')}: {result.get('error_description', '')}")
        data = self._token_request({"code": result["code"], "grant_type": "authorization_code",
                                    "redirect_uri": self.redirect_uri, "code_verifier": verifier})
        self._save_token(data)
        log(f"TikTok: вход выполнен, права: {data.get('scope')}")

    def token(self) -> str:
        saved = self.tokens.get("tiktok")
        if not saved:
            raise SetupError("TikTok: сначала войдите: python upload.py tiktok-login")
        if time.time() > saved["expires_at"] - 300:
            if time.time() > saved.get("refresh_expires_at", 0):
                raise SetupError("TikTok: вход истёк, войдите заново: python upload.py tiktok-login")
            # refresh_token одноразовый: TikTok выдаёт новый, старый сразу перестаёт работать
            self._save_token(self._token_request({"grant_type": "refresh_token",
                                                  "refresh_token": saved["refresh_token"]}))
            self.on_token_change()
        return self.tokens["tiktok"]["access_token"]

    def on_token_change(self) -> None:  # подменяется снаружи, чтобы сразу сохранить новый токен
        pass

    def api(self, path: str, body: dict | None = None) -> dict:
        status, data = request("POST", f"{self.api_base}{path}", json_body=body or {},
                            headers={"Authorization": f"Bearer {self.token()}"})
        err = data.get("error", {})
        if status >= 400 or (err and err.get("code") not in (None, "ok")):
            kind = SetupError if (err.get("code") in TT_SETUP_CODES or status == 401 or status >= 500) else ApiError
            raise kind(f"TikTok {status}: {err.get('code')}: {err.get('message')}")
        return data.get("data", {})

    def check(self) -> None:
        saved = self.tokens.get("tiktok")
        if not saved:
            log("  TikTok: вход не выполнен → python upload.py tiktok-login")
            return
        self.token()
        days = (saved["refresh_expires_at"] - time.time()) / 86400
        log(f"  TikTok: вход выполнен, права: {saved.get('scope')}; повторный вход через {days:.0f} дн.")
        if self.mode == "direct":
            info = self.api("/v2/post/publish/creator_info/query/")
            log(f"  Аккаунт @{info.get('creator_username')}; приватность: {info.get('privacy_level_options')}; "
                f"макс. длина {info.get('max_video_post_duration_sec')} с")

    def post(self, video: Path, caption: str) -> dict:
        size = video.stat().st_size
        if size <= 64_000_000:  # до 64 МБ — одним куском
            chunk, count = size, 1
        else:
            chunk = 10_000_000
            count = size // chunk  # последний кусок забирает остаток
        source = {"source": "FILE_UPLOAD", "video_size": size, "chunk_size": chunk, "total_chunk_count": count}

        if self.mode == "direct":
            info = self.api("/v2/post/publish/creator_info/query/")
            options = info.get("privacy_level_options") or []
            privacy = self.cfg.get("privacy_level", "PUBLIC_TO_EVERYONE")
            if privacy not in options:
                fallback = "SELF_ONLY" if "SELF_ONLY" in options else (options or ["SELF_ONLY"])[0]
                log(f"  ! TikTok не разрешает {privacy}, публикую как {fallback}")
                privacy = fallback
            body = {"post_info": {"title": caption[:2200], "privacy_level": privacy,
                                  "disable_duet": False, "disable_comment": False, "disable_stitch": False,
                                  "video_cover_timestamp_ms": 1000},
                    "source_info": source}
            init = self.api("/v2/post/publish/video/init/", body)
        else:
            init = self.api("/v2/post/publish/inbox/video/init/", {"source_info": source})

        publish_id, upload_url = init["publish_id"], init["upload_url"]
        log(f"  · TikTok: загружаю {size / 1e6:.1f} МБ")
        with video.open("rb") as fh:
            for i in range(count):
                start = i * chunk
                end = size - 1 if i == count - 1 else start + chunk - 1
                fh.seek(start)
                part = fh.read(end - start + 1)
                status, data = request("PUT", upload_url, body=part, timeout=900, headers={
                    "Content-Type": "video/mp4", "Content-Range": f"bytes {start}-{end}/{size}"})
                if status not in (200, 201, 206):
                    raise ApiError(f"TikTok: кусок {i + 1}/{count} не принят ({status}): {data}")

        log("  · TikTok: жду обработки видео")
        deadline = time.time() + 15 * 60
        while True:
            st = self.api("/v2/post/publish/status/fetch/", {"publish_id": publish_id})
            status = st.get("status")
            if status in ("PUBLISH_COMPLETE", "SEND_TO_USER_INBOX"):
                return {"id": publish_id, "state": status,
                        "post_ids": st.get("publicaly_available_post_id") or []}
            if status == "FAILED":
                raise ApiError(f"TikTok отклонил видео: {st.get('fail_reason')}")
            if time.time() > deadline:
                raise ApiError("TikTok обрабатывает видео дольше 15 минут")
            time.sleep(float(self.cfg.get("poll_seconds", 5)))


# ----------------------------------------------------------------- очередь


class Uploader:
    def __init__(self, config_path: Path, output: Path | None = None):
        self.config = load_config(config_path)
        self.output = Path(output or self.config.get("output_dir") or HERE / "output")
        if not self.output.is_absolute():
            self.output = HERE / self.output
        self.tokens_path, self.history_path = STATE_DIR / "tokens.json", STATE_DIR / "uploads.json"
        self.tokens = load_json(self.tokens_path, {})
        self.history = load_json(self.history_path, {})
        self.platforms: dict[str, Instagram | TikTok] = {}
        for cls in (Instagram, TikTok):
            cfg = self.config.get(cls.name, {})
            if cfg.get("enabled"):
                self.platforms[cls.name] = cls(cfg, self.tokens)
        if "tiktok" in self.platforms:
            self.platforms["tiktok"].on_token_change = self.save  # type: ignore[method-assign]

    def save(self) -> None:
        save_json(self.tokens_path, self.tokens)
        save_json(self.history_path, self.history)

    def videos(self) -> list[tuple[Path, dict]]:
        items = []
        for meta_path in self.output.glob("*.json"):
            meta = load_json(meta_path, {})
            video = self.output / meta.get("video", meta_path.stem + ".mp4")
            if video.is_file() and not video.name.endswith(".part.mp4"):
                items.append((video, meta))
        return sorted(items, key=lambda it: (it[1].get("created", ""), it[0].name))

    def pending(self, platform: str) -> list[tuple[Path, dict]]:
        out = []
        for video, meta in self.videos():
            rec = self.history.get(video.name, {}).get(platform, {})
            if rec.get("status") == "done" or rec.get("attempts", 0) >= MAX_ATTEMPTS:
                continue
            out.append((video, meta))
        return out

    def post_next(self, platform: str, dry_run: bool = False) -> bool:
        queue = self.pending(platform)
        if not queue:
            log(f"{platform}: очередь пуста")
            return False
        video, meta = queue[0]
        caption = meta.get("post_text", "")
        log(f"{platform}: {video.name}")
        if dry_run:
            log(f"  (проверка) подпись: {caption!r}")
            return True
        rec = self.history.setdefault(video.name, {}).setdefault(platform, {})
        try:
            result = self.platforms[platform].post(video, caption)
        except SetupError as err:
            rec["last_error"] = f"{time.strftime('%Y-%m-%d %H:%M')}: {err}"
            self.save()
            log(f"  ✗ {err}\n    (ролик останется в очереди — сначала исправьте доступ)")
            return False
        except ApiError as err:
            rec.update(status="failed", error=str(err), attempts=rec.get("attempts", 0) + 1,
                       at=time.strftime("%Y-%m-%d %H:%M"))
            self.save()
            log(f"  ✗ {err}")
            return False
        rec.clear()
        rec.update(status="done", at=time.strftime("%Y-%m-%d %H:%M"), **result)
        if result.get("state") == "SEND_TO_USER_INBOX":
            rec["caption"] = caption
            log("  ✓ отправлено в TikTok. Откройте уведомление в приложении и опубликуйте. Подпись:\n"
                f"    {caption}")
        else:
            log(f"  ✓ опубликовано (id {result.get('id')})")
        self.save()
        return True

    def status(self) -> None:
        log(f"Папка с роликами: {self.output}")
        if not self.platforms:
            log("Ни одна площадка не включена: \"enabled\": true в config.json")
        for name in self.platforms:
            queue = self.pending(name)
            log(f"{name}: в очереди {len(queue)}" + (f", следующий — {queue[0][0].name}" if queue else ""))
            failed = [(v, r[name]) for v, r in self.history.items()
                      if r.get(name, {}).get("status") == "failed"]
            for v, r in failed[-5:]:
                log(f"  ! {v}: попыток {r['attempts']}/{MAX_ATTEMPTS}, ошибка: {r['error']}")
            setup = sorted(r[name]["last_error"] for r in self.history.values() if r.get(name, {}).get("last_error"))
            if setup and queue and self.history.get(queue[0][0].name, {}).get(name, {}).get("last_error"):
                log(f"  ! последняя ошибка доступа: {setup[-1]}")
        inbox = [(v, r["tiktok"]) for v, r in self.history.items()
                 if r.get("tiktok", {}).get("state") == "SEND_TO_USER_INBOX"]
        if inbox:
            log("Ждут публикации в приложении TikTok (последние 5):")
            for v, r in inbox[-5:]:
                log(f"  · {v} ({r['at']}): {r.get('caption', '')!r}")


def main(argv=None) -> None:
    p = argparse.ArgumentParser(description="Заливка роликов в Instagram и TikTok через официальные API.")
    p.add_argument("command", choices=["status", "check", "post", "tiktok-login"])
    p.add_argument("--platform", nargs="+", choices=["instagram", "tiktok"], help="только эти площадки")
    p.add_argument("--count", type=int, default=1, help="сколько роликов выложить на каждую площадку")
    p.add_argument("--config", type=Path, default=HERE / "config.json")
    p.add_argument("--output", type=Path, default=None, help="папка с роликами (по умолчанию output/)")
    p.add_argument("--dry-run", action="store_true", help="только показать, что будет выложено")
    p.add_argument("--no-browser", action="store_true", help="не открывать браузер при входе")
    args = p.parse_args(argv)

    up = Uploader(args.config, args.output)
    names = [n for n in (args.platform or up.platforms) if n in up.platforms]
    if args.platform and len(names) < len(args.platform):
        log("! Некоторые площадки выключены в config.json")

    if args.command == "tiktok-login":
        tiktok = up.platforms.get("tiktok") or TikTok(up.config.get("tiktok", {}), up.tokens)
        try:
            tiktok.login(open_browser=not args.no_browser)
        except ApiError as err:
            sys.exit(str(err))
        up.save()
    elif args.command == "status":
        up.status()
    elif args.command == "check":
        for name in names:
            try:
                up.platforms[name].check()
            except ApiError as err:
                log(f"  ✗ {name}: {err}")
        up.save()
    elif args.command == "post":
        for name in names:
            for _ in range(args.count):
                if not up.post_next(name, dry_run=args.dry_run):
                    break


if __name__ == "__main__":
    main()
