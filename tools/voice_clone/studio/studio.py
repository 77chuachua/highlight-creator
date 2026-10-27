"""Voice Studio - record a reference, hear the clone, save a voice pack.

Runs as a local web app: this file serves one page and a tiny JSON API on
127.0.0.1 and opens it in the default browser, so the studio needs nothing but
the plugin's own Python environment (no extra packages).

    python studio.py [--ffmpeg PATH] [--port N] [--no-browser]

The page talks to the same worker.py the app does, so a voice that sounds good
here sounds the same inside a reel.
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Identity + defaults. A fixed port means a second launch can find the first
# instead of starting another server, and the page always talks to the same URL.
APP_ID = "hlc-studio"
DEFAULT_PORT = 17321
IDLE_MINUTES = 15

_started_at = datetime.datetime.now()
_last_seen = time.time()
_port = DEFAULT_PORT
_args = None

HERE = Path(__file__).resolve().parent
# Where the engine lives (venv, worker, models). Normally the studio sits
# inside the plugin, so it is the parent folder. Running straight from the
# source tree has no engine next to it, so studio-debug.bat points this at the
# installed plugin and only the code comes from the checkout.
PLUGIN = Path(os.environ.get("HIGHLIGHT_STUDIO_PLUGIN") or HERE.parent)
HOME = Path(os.environ.get("USERPROFILE") or Path.home())
USER_DIR = HOME / "HighlightCreator"
VOICES = USER_DIR / "voices"
TEMP = USER_DIR / "temp" / "studio"

# What the user reads aloud, per language. The app hands the same string to the
# engine as the prompt text, so it has to match the recording word for word -
# an English speaker must read the English line.
GUIDE_TEXT = {
    "zh": "欢迎来到本周最佳进球时刻，让我们一起回顾赛场上的每一个精彩瞬间。",
    "en": "Welcome back to this week's best goals. Let's look back at every "
          "brilliant moment on the pitch together.",
}
# What the preview speaks by default.
SAMPLE_TEXT = {
    "zh": "这脚球太漂亮了，门将毫无办法。",
    "en": "What a strike - the keeper had no chance at all.",
}

# Our own messages travel as codes; the page owns the wording. Raw engine
# errors (libsndfile, torch) stay verbatim: they are diagnostics, not UI.
MESSAGES = {
    "busy_recording": ("已经在录音了", "Already recording"),
    "record_failed": ("打开麦克风失败:{detail}", "Could not open the microphone: {detail}"),
    "not_recording": ("没有在录音", "Not recording"),
    "no_audio_captured": ("没有录到内容", "Nothing was captured"),
    "need_take": ("先录一段声音，或者载入一个语音包",
                  "Record something first, or load a voice pack"),
    "take_gone": ("录音文件已不存在（临时目录可能被清理），请重新录音或载入语音包",
                  "The recording is gone (temp cleanup?), record again or load a pack"),
    "style_gone": ("语调参考文件已不存在（可能被删除），这次按你自己的语调处理。",
                   "The intonation reference is gone (deleted?), so your own "
                   "delivery was used."),
    "engine_incomplete": ("克隆引擎没有安装完整（缺少 venv 或 worker.py）",
                          "The cloning engine is incomplete (no venv or worker.py)"),
    "engine_start_failed": ("克隆引擎无法启动", "The cloning engine could not start"),
    "engine_interrupted": ("克隆引擎中断:{detail}",
                           "The cloning engine dropped out: {detail}"),
    "engine_no_reply": ("克隆引擎没有返回结果，已重置（详见 logs/）",
                        "The engine returned nothing; it was reset (see logs/)"),
    "engine_bad_reply": ("返回内容无法解析:{detail}",
                         "Could not parse the engine reply: {detail}"),
    "clone_failed": ("克隆失败", "Cloning failed"),
    "pack_not_found": ("找不到这个语音包", "That voice pack does not exist"),
    "pack_no_reference": ("这个语音包里没有 reference.wav",
                          "That pack has no reference.wav"),
    "no_audio_yet": ("还没有音频", "No audio yet"),
}

_lang = "zh"


def msg(code: str, **values) -> str:
    """Text for [code] in the current language, with {placeholders} filled."""
    zh, en = MESSAGES.get(code, ("", ""))
    text = en if _lang == "en" else zh
    if not text:
        text = zh or code
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


VOICE_CLONE = PLUGIN / "CosyVoice"
MODEL = PLUGIN / "models" / "CosyVoice2-0.5B"
WORKER = PLUGIN / "worker.py"
VENV_PY = PLUGIN / "venv" / "Scripts" / "python.exe"

if os.path.isdir(VOICE_CLONE):
    for entry in (str(VOICE_CLONE), str(VOICE_CLONE / "third_party" / "Matcha-TTS")):
        if entry not in sys.path:
            sys.path.insert(0, entry)

FFMPEG = "ffmpeg"

_state = {
    "device": "",
    "recording": False,
    "process": None,
    "take": None,      # path of the current recording
    "style": None,     # path of the chosen intonation reference
    "error": None,
}
_lock = threading.Lock()

LOGS = USER_DIR / "logs"


def log_error(label: str, detail: str):
    """Keep failures somewhere a user can find them: the app writes here too."""
    try:
        LOGS.mkdir(parents=True, exist_ok=True)
        stamp = datetime.datetime.now().isoformat()
        path = LOGS / f"studio-{datetime.date.today().isoformat()}.log"
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"[{stamp}] [{label}] {detail}\n")
    except Exception:  # noqa: BLE001 - logging must never mask the real error
        pass


_worker = {"process": None, "ready": False, "error": None}
_worker_lock = threading.Lock()


# --------------------------------------------------------------------- ffmpeg
def find_ffmpeg() -> str:
    if FFMPEG and Path(FFMPEG).exists():
        return FFMPEG
    found = shutil.which("ffmpeg")
    if found:
        return found
    # The app installs ffmpeg next to itself; nothing else to guess.
    raise RuntimeError(
        "找不到 ffmpeg。请从应用目录启动本工作室（应用会把路径传进来），"
        "或把 ffmpeg 放进 PATH。"
    )


def list_devices():
    try:
        result = subprocess.run(
            [find_ffmpeg(), "-hide_banner", "-list_devices", "true",
             "-f", "dshow", "-i", "dummy"],
            capture_output=True, timeout=30,
        )
    except Exception as error:  # noqa: BLE001 - reported to the page
        return [], f"{error}"
    text = (result.stdout + result.stderr).decode("utf-8", "replace")
    devices = []
    for line in text.splitlines():
        if "(audio)" not in line or '"' not in line:
            continue
        name = line.split('"')[1].strip()
        if name and name not in devices:
            devices.append(name)
    return devices, None


# ------------------------------------------------------------------- recording
def record_start(device: str):
    with _lock:
        if _state["recording"]:
            return {"ok": False, "code": "busy_recording",
                    "error": msg("busy_recording")}
        TEMP.mkdir(parents=True, exist_ok=True)
        # A fresh name per take: an ffmpeg that never got stopped (the studio
        # was killed mid-recording) still holds its file open, and Windows
        # refuses to overwrite it.
        target = TEMP / f"take-{int(time.time())}.wav"
        try:
            process = subprocess.Popen(
                [find_ffmpeg(), "-hide_banner", "-loglevel", "error",
                 "-f", "dshow", "-i", f"audio={device}",
                 "-ac", "1", "-ar", "44100", "-y", str(target)],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
        except Exception as error:  # noqa: BLE001
            return {"ok": False, "code": "record_failed",
                    "error": msg("record_failed", detail=error)}
        _state.update(recording=True, process=process, device=device,
                      pending=str(target), take=None, error=None)
    return {"ok": True}


def record_stop():
    with _lock:
        process = _state["process"]
        if process is None:
            return {"ok": False, "code": "not_recording",
                    "error": msg("not_recording")}
        _state.update(recording=False, process=None)
    try:
        process.stdin.write(b"q")
        process.stdin.flush()
        process.stdin.close()
    except Exception:  # noqa: BLE001 - the process may be gone already
        pass
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        process.kill()
    stderr = ""
    try:
        stderr = process.stderr.read().decode("utf-8", "replace").strip()
    except Exception:  # noqa: BLE001
        pass
    target = Path(_state.get("pending") or (TEMP / "take.wav"))
    if not target.exists() or target.stat().st_size < 2048:
        message = stderr.splitlines()[-1] if stderr else msg("no_audio_captured")
        with _lock:
            _state["error"] = message
        return {"ok": False, "code": "no_audio_captured", "error": message}
    with _lock:
        _state["take"] = str(target)
    return {"ok": True, "take": describe(str(target))}


def _samples(path: str):
    """Mono samples in -1..1 plus the sample rate, for any WAV we get.

    `wave` only understands PCM, but the engine saves float32 WAVs, so fall
    back to soundfile (already part of the engine's environment).
    """
    try:
        with wave.open(path, "rb") as handle:
            frames = handle.getnframes()
            rate = handle.getframerate()
            channels = handle.getnchannels()
            width = handle.getsampwidth()
            raw = handle.readframes(frames)
        if width == 2:
            total = len(raw) // 2
            values = [
                int.from_bytes(raw[i * 2:i * 2 + 2], "little", signed=True) / 32768.0
                for i in range(total)
            ]
        else:
            values = []
        return values, rate, channels
    except Exception:  # noqa: BLE001 - float WAVs land here
        pass
    import soundfile  # part of the engine environment

    data, rate = soundfile.read(path, always_2d=True)
    mono = [float(sum(frame) / max(1, len(frame))) for frame in data]
    return mono, rate, 1


def describe(path: str):
    """Duration, peak and a 120-bucket envelope for the waveform."""
    values, rate, channels = _samples(path)
    if channels > 1:
        values = values[::channels]
    seconds = len(values) / float(rate) if rate else 0.0
    peak = 0.0
    buckets = 120
    envelope = [0.0] * buckets
    total = len(values)
    for index, value in enumerate(values):
        magnitude = abs(value)
        if magnitude > peak:
            peak = magnitude
        slot = min(buckets - 1, index * buckets // max(1, total))
        if magnitude > envelope[slot]:
            envelope[slot] = magnitude
    return {
        "path": path,
        "seconds": round(seconds, 2),
        "peak": round(peak, 3),
        "envelope": [round(value, 3) for value in envelope],
    }


def _take_or_none():
    """The current recording, or a clear reason why there is none.

    The temp file can be cleaned up behind our back; a dead path would reach
    the engine and come back as "Error opening ...: System error".
    """
    take = _state.get("take")
    if not take:
        return None, msg("need_take")
    if not Path(take).exists():
        with _lock:
            _state.update(take=None, pending=None)
        return None, msg("take_gone")
    return take, None


def _style_or_none():
    """The intonation file, dropped once it no longer exists.

    Deleting the file (or the pack it came from) after selecting it used to
    make every later 试听 fail with an engine-level file error.
    """
    style = _state.get("style")
    if not style:
        return None, None
    if Path(style).exists():
        return style, None
    with _lock:
        _state["style"] = None
    return None, msg("style_gone")


# --------------------------------------------------------------------- worker
def _worker_start():
    """Start the clone worker once and keep the model warm."""
    with _worker_lock:
        if _worker["process"] is not None:
            return _worker["process"]
        if not VENV_PY.exists() or not WORKER.exists():
            _worker["error"] = msg("engine_incomplete")
            return None
        env = dict(
            os.environ,
            HIGHLIGHT_COSYVOICE_ROOT=str(VOICE_CLONE),
            HIGHLIGHT_COSYVOICE_MODEL=str(MODEL),
            PYTHONIOENCODING="utf-8",
        )
        process = subprocess.Popen(
            [str(VENV_PY), str(WORKER)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,  # inherits the studio's stderr, which goes to the log
            env=env,
        )
        _worker["process"] = process
        return process


def _reset_worker():
    """A dead or wedged worker must not poison every later preview."""
    with _worker_lock:
        process = _worker.get("process")
        _worker["process"] = None
    if process is not None:
        try:
            process.kill()
        except Exception:  # noqa: BLE001 - already gone
            pass


def synthesize(text: str, reference: str, style: str | None = None,
               speed: float = 1.0, instruct: str = "",
               prompt_text: str = "") -> dict:
    process = _worker_start()
    if process is None:
        return {"ok": False,
                "error": _worker.get("error") or msg("engine_start_failed")}
    TEMP.mkdir(parents=True, exist_ok=True)
    output = TEMP / "preview.wav"
    request = {
        "text": text,
        # The transcript of the reference recording: the engine aligns the
        # prompt against it, so it must be what was actually said.
        "prompt_text": prompt_text.strip() or GUIDE_TEXT,
        "reference": reference,
        "output": str(output),
        "speed": max(0.5, min(2.0, float(speed or 1.0))),
    }
    if style:
        request["prosody_reference"] = style
    if instruct.strip():
        request["instruct"] = instruct.strip()
    try:
        with _worker_lock:
            process.stdin.write(
                (json.dumps(request, ensure_ascii=False) + "\n").encode("utf-8"))
            process.stdin.flush()
            line = process.stdout.readline().decode("utf-8", "replace").strip()
    except Exception as error:  # noqa: BLE001
        _reset_worker()
        return {
            "ok": False,
            "error": msg("engine_interrupted", detail=error),
        }
    if not line.startswith("{"):
        _reset_worker()
        return {"ok": False, "error": msg("engine_no_reply")}
    try:
        reply = json.loads(line)
    except Exception as error:  # noqa: BLE001
        return {"ok": False, "error": msg("engine_bad_reply", detail=error)}
    if not reply.get("ok"):
        return {"ok": False, "error": reply.get("error") or msg("clone_failed")}
    return {"ok": True, "preview": describe(str(output))}


# ----------------------------------------------------------------------- packs
def list_packs():
    """Every imported voice pack, so one can be reused without re-recording."""
    if not VOICES.exists():
        return []
    packs = []
    for folder in VOICES.glob("*.voicepack"):
        manifest = {}
        try:
            manifest = json.loads(
                (folder / "manifest.json").read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001 - a broken manifest is not fatal
            pass
        name = manifest.get("name") or folder.name.replace(".voicepack", "")
        packs.append({
            "id": folder.name.replace(".voicepack", ""),
            "name": name,
            "seconds": manifest.get("referenceSeconds") or 0,
            "hasReference": (folder / "reference.wav").exists(),
            "hasStyle": (folder / "style.wav").exists(),
        })
    packs.sort(key=lambda item: item["name"])
    return packs


def manifest_of(folder: Path) -> dict:
    """The pack's manifest, or an empty dict when it is missing or broken."""
    try:
        data = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001 - a broken manifest is not fatal
        return {}


def name_of(folder: Path) -> str:
    """Display name of a pack folder: the manifest's, else the folder's."""
    value = (manifest_of(folder).get("name") or "").strip()
    return value or folder.name.replace(".voicepack", "")


def load_pack(pack_id: str):
    """Use a pack's recording as the take, and its style as the intonation."""
    folder = VOICES / f"{pack_id}.voicepack"
    if not folder.is_dir():
        return {"ok": False, "error": msg("pack_not_found")}
    reference = folder / "reference.wav"
    if not reference.exists():
        return {"ok": False, "error": msg("pack_no_reference")}
    TEMP.mkdir(parents=True, exist_ok=True)
    target = TEMP / f"take-{int(time.time())}.wav"
    shutil.copyfile(reference, target)
    style = folder / "style.wav"
    with _lock:
        _state.update(recording=False, process=None, take=str(target),
                      pending=str(target),
                      style=str(style) if style.exists() else None)
    info = describe(str(target))
    manifest = manifest_of(folder)
    # Bring the pack's delivery settings along, so "load, tweak, save" starts
    # from what that pack actually sounds like.
    info.update(
        ok=True,
        id=pack_id,
        name=name_of(folder),
        style=_state["style"],
        text=SAMPLE_TEXT,
        speed=manifest.get("speed") or 1.0,
        instruct=manifest.get("instruct") or "",
        promptText=manifest.get("promptText") or GUIDE_TEXT,
    )
    return info


def save_pack(name: str, reference: str, style: str | None, engine: str = "",
              speed: float = 1.0, instruct: str = "",
              prompt_text: str = "") -> dict:
    clean = "".join(ch for ch in name if ch not in '\\/:*?"<>|').strip() or "我的声音"
    VOICES.mkdir(parents=True, exist_ok=True)
    target = VOICES / f"{clean}.voicepack"
    counter = 2
    while target.exists():
        target = VOICES / f"{clean} ({counter}).voicepack"
        counter += 1
    target.mkdir(parents=True)
    shutil.copyfile(reference, target / "reference.wav")
    if style and Path(style).exists():
        shutil.copyfile(style, target / "style.wav")
    seconds = 0.0
    try:
        with wave.open(str(target / "reference.wav"), "rb") as handle:
            seconds = handle.getnframes() / float(handle.getframerate())
    except Exception:  # noqa: BLE001
        pass
    manifest = {
        "schema": 1,
        "name": clean,
        "createdAt": datetime.datetime.now().isoformat(),
        "engine": engine,
        "referenceSeconds": round(seconds, 3),
        "sampleRate": 44100,
        # Delivery, so the app reproduces what was heard here.
        "speed": round(max(0.5, min(2.0, float(speed or 1.0))), 3),
        "instruct": instruct.strip(),
        "promptText": prompt_text.strip() or GUIDE_TEXT,
    }
    (target / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")
    return {"ok": True, "dir": str(target), "name": clean, "seconds": round(seconds, 2)}


# ---------------------------------------------------------------------- server
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def _send(self, code, body: bytes, content_type="application/json"):
        self.send_response(code)
        if content_type.startswith(("text/", "application/json")):
            content_type += "; charset=utf-8"
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, payload, code=200):
        self._send(code, json.dumps(payload, ensure_ascii=False).encode("utf-8"))

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _touch(self):
        global _last_seen
        _last_seen = time.time()

    def do_GET(self):  # noqa: N802 - http.server API
        self._touch()
        if self.path.startswith("/api/ping"):
            self._json({
                "app": APP_ID,
                "pid": os.getpid(),
                "port": _port,
                "started": _started_at.isoformat(timespec="seconds"),
            })
            return
        if self.path in ("/", "/index.html"):
            page = (HERE / "studio.html").read_bytes()
            self._send(200, page, "text/html")
            return
        if self.path.startswith("/api/audio/"):
            # Audio goes over its own endpoint: base64 inside JSON made the
            # response large enough that the socket died mid-write.
            kind = self.path.rsplit("/", 1)[-1].split("?")[0]
            source = (TEMP / "preview.wav") if kind == "preview" else (
                Path(_state["take"]) if _state["take"] else None)
            if source is None or not source.exists():
                self._json({"ok": False, "error": msg("no_audio_yet")}, 404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(source.stat().st_size))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(source.read_bytes())
            return
        if self.path.startswith("/api/state"):
            if "?" in self.path:
                for part in self.path.split("?", 1)[1].split("&"):
                    if part.startswith("lang="):
                        set_language(part.split("=", 1)[1])
            devices, error = list_devices()
            self._json({
                "lang": _lang,
                "packs": list_packs(),
                "guide": GUIDE_TEXT[_lang],
                "sample": SAMPLE_TEXT[_lang],
                "devices": devices,
                "deviceError": error,
                "take": describe(_state["take"]) if _state["take"] else None,
                "style": _state["style"],
                "engine": {
                    "installed": VENV_PY.exists() and WORKER.exists() and MODEL.exists(),
                    "python": str(VENV_PY),
                },
            })
            return
        self._json({"ok": False, "error": "not found"}, 404)

    def do_POST(self):  # noqa: N802 - http.server API
        self._touch()
        try:
            self._post()
        except Exception as error:  # noqa: BLE001 - never drop the socket
            log_error("studio", traceback.format_exc())
            try:
                self._json({"ok": False, "error": f"{type(error).__name__}: {error}"})
            except Exception:  # noqa: BLE001 - the socket may already be gone
                pass

    def _post(self):
        route = self.path
        if route == "/api/packs/load":
            payload = json.loads(self._body() or b"{}")
            self._json(load_pack(payload.get("id") or ""))
            return
        if route == "/api/record/start":
            payload = json.loads(self._body() or b"{}")
            self._json(record_start(payload.get("device") or _state["device"]))
            return
        if route == "/api/record/stop":
            self._json(record_stop())
            return
        if route == "/api/style":
            # Raw WAV bytes uploaded by the page.
            name = self.headers.get("X-Filename") or "style.wav"
            TEMP.mkdir(parents=True, exist_ok=True)
            target = TEMP / "style-source"
            target.write_bytes(self._body())
            converted = TEMP / "style.wav"
            try:
                result = subprocess.run(
                    [find_ffmpeg(), "-y", "-i", str(target), "-vn",
                     "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le",
                     str(converted)],
                    capture_output=True, timeout=180)
            except Exception as error:  # noqa: BLE001
                self._json({"ok": False, "error": f"{error}"})
                return
            if result.returncode != 0 or not converted.exists():
                detail = result.stderr.decode("utf-8", "replace").strip()
                detail = detail.splitlines()[-1] if detail else "转换失败"
                self._json({"ok": False, "error": detail})
                return
            _state["style"] = str(converted)
            info = describe(str(converted))
            info.update(ok=True, original=name)
            self._json(info)
            return
        if route == "/api/style/clear":
            _state["style"] = None
            self._json({"ok": True})
            return
        if route == "/api/preview":
            # The caller sends the sentence to speak; the sample is only a
            # default for the very first try.
            payload = json.loads(self._body() or b"{}")
            take, problem = _take_or_none()
            if take is None:
                self._json({"ok": False, "error": problem})
                return
            style, notice = _style_or_none()
            text = (payload.get("text") or "").strip() or SAMPLE_TEXT
            reply = synthesize(
                text, take, style,
                speed=payload.get("speed", 1.0),
                instruct=payload.get("instruct", ""),
                prompt_text=payload.get("promptText", ""),
            )
            if notice:
                reply["notice"] = notice
            self._json(reply)
            return
        if route == "/api/save":
            payload = json.loads(self._body() or b"{}")
            take, problem = _take_or_none()
            if take is None:
                self._json({"ok": False, "error": problem})
                return
            style, notice = _style_or_none()
            reply = save_pack(
                payload.get("name") or "我的声音", take, style,
                payload.get("engine") or "",
                speed=payload.get("speed", 1.0),
                instruct=payload.get("instruct", ""),
                prompt_text=payload.get("promptText", ""),
            )
            if notice:
                reply["notice"] = notice
            self._json(reply)
            return
        if route == "/api/quit":
            self._json({"ok": True})
            threading.Timer(0.3, lambda: shutdown("requested")).start()
            return
        if route == "/api/restart":
            self._json({"ok": True, "pid": os.getpid()})

            def cycle():
                try:
                    spawn_replacement()
                finally:
                    shutdown("restart")

            threading.Timer(0.3, cycle).start()
            return
        self._json({"ok": False, "error": "not found"}, 404)


def _kill_children():
    """Stop the recorder and the engine before we exit.

    os._exit skips every `finally`, so leaving this to the interpreter is how
    a 4 GB engine process used to survive its studio.
    """
    for holder, key in ((_state, "process"), (_worker, "process")):
        child = holder.get(key)
        if child is None:
            continue
        try:
            child.kill()
        except Exception:  # noqa: BLE001 - already gone
            pass


def shutdown(reason: str = ""):
    """Stop everything and exit. Nothing in here may fail.

    The venv's python.exe is a launcher that re-execs the base interpreter, and
    under it sys.stderr can already be closed: an unguarded log() raised
    ValueError and took os._exit down with it, so /api/quit and /api/restart
    both answered 200 and then did nothing.
    """
    try:
        log(f"[studio] shutting down ({reason})")
    except Exception:  # noqa: BLE001 - a broken stderr must not block exit
        pass
    try:
        _kill_children()
    except Exception:  # noqa: BLE001 - same
        pass
    os._exit(0)


def spawn_replacement():
    """Start a fresh studio with the same arguments, detached."""
    command = [sys.executable, "-X", "utf8", str(HERE / "studio.py"),
               "--port", str(_port), "--ffmpeg", FFMPEG,
               "--idle-minutes", str(_args.idle_minutes if _args else IDLE_MINUTES),
               "--no-browser"]
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | \
        getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    subprocess.Popen(command, cwd=str(HERE), close_fds=True,
                     creationflags=flags,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def watch_idle(minutes: int):
    """Exit when nobody has talked to us for a while.

    Closing the browser tab used to leave the server (and its engine) running
    forever; the page sends a heartbeat so an open tab keeps it alive.
    """
    if minutes <= 0:
        return
    limit = minutes * 60
    while True:
        time.sleep(20)
        if time.time() - _last_seen > limit:
            shutdown(f"idle for {minutes} min")


def who_is_on(port: int):
    """The studio already listening on [port], or None."""
    try:
        with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/api/ping", timeout=2) as response:
            data = json.loads(response.read().decode("utf-8"))
        return data if data.get("app") == APP_ID else None
    except Exception:  # noqa: BLE001 - nothing there
        return None


def set_language(value: str) -> str:
    """Remember the page's language; unknown values fall back to Chinese."""
    global _lang
    _lang = "en" if str(value).lower().startswith("en") else "zh"
    return _lang


def main():
    global FFMPEG, _port, _args
    parser = argparse.ArgumentParser(description="语音工作室")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help="固定端口；0 表示随机端口")
    parser.add_argument("--idle-minutes", type=int, default=IDLE_MINUTES,
                        help="无请求多久后自动退出（0 表示不退出）")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    FFMPEG = args.ffmpeg

    if not (HERE / "studio.html").exists():
        print("缺少 studio.html", file=sys.stderr)
        return 1

    _args = args
    global _port
    _port = args.port or DEFAULT_PORT

    if _port:
        existing = who_is_on(_port)
        if existing:
            # One studio per machine: hand the URL back instead of starting a
            # second server that would linger on another port.
            running = f"http://127.0.0.1:{_port}/"
            print(f"语音工作室已经在运行: {running} "
                  f"(pid {existing.get('pid')})", flush=True)
            if not args.no_browser:
                __import__("webbrowser").open(running)
            return 0

    server = None
    for attempt in range(40):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", _port), Handler)
            break
        except OSError:
            if attempt == 39:
                raise
            time.sleep(0.25)
    _port = server.server_address[1]
    url = f"http://127.0.0.1:{_port}/"
    print(f"语音工作室: {url}", flush=True)
    threading.Thread(target=watch_idle, args=(args.idle_minutes,),
                     daemon=True).start()
    if not args.no_browser:
        threading.Timer(0.3, lambda: __import__("webbrowser").open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        recorder = _state.get("process")
        if recorder is not None:
            try:
                recorder.kill()
            except Exception:  # noqa: BLE001 - already gone
                pass
        process = _worker.get("process")
        if process is not None:
            try:
                process.kill()
            except Exception:  # noqa: BLE001
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
