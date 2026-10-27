"""Self-check for the Voice Studio.

    python selftest.py --start --ffmpeg "C:\\...\\ffmpeg.exe"

Starts the studio, then drives its API the way the page does: state, a short
recording, the clone preview, and an optional pack save. Everything is plain
HTTP + stdlib, so this works with no browser and exits non-zero on failure.

Flags:
    --start / --stop-pid N   launch the studio (and kill it afterwards)
    --url URL                talk to an already running studio instead
    --seconds N              recording length (default 3)
    --no-preview             skip the clone preview (it loads the model, ~40 s)
    --save NAME              also save a pack under this name
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent
VENV_PY = PLUGIN / "venv" / "Scripts" / "python.exe"

FAILED = []


def call(url, path, payload=None, timeout=60):
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        return {"ok": False, "error": f"HTTP {error.code}"}
    except Exception as error:  # noqa: BLE001
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def fetch_bytes(url, path, timeout=60):
    """GET a binary endpoint; returns (bytes, error)."""
    try:
        with urllib.request.urlopen(url + path, timeout=timeout) as response:
            return response.read(), ""
    except Exception as error:  # noqa: BLE001
        return b"", f"{type(error).__name__}: {error}"


def check(label, condition, detail=""):
    mark = "OK  " if condition else "FAIL"
    print(f"  [{mark}] {label}" + (f" - {detail}" if detail else ""))
    if not condition:
        FAILED.append(label)
    return condition


def main():
    parser = argparse.ArgumentParser(description="语音工作室自检")
    parser.add_argument("--start", action="store_true", help="启动工作室")
    parser.add_argument("--url", default="", help="已运行的工作室地址")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--port", type=int, default=18090)
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--speed", type=float, default=1.0,
                        help="语速 0.85~1.3")
    parser.add_argument("--no-preview", action="store_true")
    parser.add_argument("--text", default="", help="试听用的句子")
    parser.add_argument("--instruct", default="", help="语气指令，例如「用激动的语气说」")
    parser.add_argument("--save", default="", help="保存成这个名字的语音包")
    parser.add_argument("--log", default="", help="工作室输出重定向到这里")
    args = parser.parse_args()

    process = None
    url = args.url
    if not url:
        if not args.start:
            print("要么给 --start（我来启动），要么用 --url 指向已运行的工作室")
            return 2
        if not VENV_PY.exists():
            print(f"找不到插件自带的 Python: {VENV_PY}")
            print("先运行 ..\\setup.bat")
            return 2
        command = [str(VENV_PY), "-X", "utf8", str(HERE / "studio.py"),
                   "--no-browser", "--port", str(args.port),
                   "--ffmpeg", args.ffmpeg]
        print("启动:", " ".join(command))
        log = open(args.log, "ab") if args.log else subprocess.DEVNULL
        process = subprocess.Popen(
            command, stdout=log, stderr=log, cwd=str(HERE),
            env=dict(os.environ, PYTHONIOENCODING="utf-8"))
        url = f"http://127.0.0.1:{args.port}"
        # The server binds quickly; give it a moment and retry once.
        for _ in range(20):
            time.sleep(0.3)
            state = call(url, "/api/state", timeout=20)
            if "devices" in state:
                break
        else:
            print("工作室没有起来，看 --log 指定的输出")
            process.kill()
            return 2

    try:
        print("\n1) 状态")
        state = call(url, "/api/state", timeout=30)
        devices = state.get("devices") or []
        engine = state.get("engine") or {}
        check("服务应答", "guide" in state)
        check("找到麦克风", bool(devices), ", ".join(devices) or "没有设备")
        check("克隆引擎已安装", bool(engine.get("installed")),
              engine.get("python", ""))
        if not devices:
            print("\n没有麦克风可测，后面跳过。检查 Windows 设置 → 隐私 → 麦克风")
            return 1

        print("\n2) 录音 %.0f 秒" % args.seconds)
        started = call(url, "/api/record/start", {"device": devices[0]})
        if not check("开始录音", started.get("ok"), started.get("error", "")):
            return 1
        time.sleep(args.seconds)
        stopped = call(url, "/api/record/stop", {}, timeout=60)
        take = stopped.get("take") or {}
        ok = check("停止并拿到音频", stopped.get("ok"), stopped.get("error", ""))
        if ok:
            check("时长大于 0", (take.get("seconds") or 0) > 0,
                  f"{take.get('seconds')} 秒")
            check("有波形数据", len(take.get("envelope") or []) == 120)
            audio, error = fetch_bytes(url, "/api/audio/take")
            check("能取到回放音频", len(audio) > 2048,
                  error or f"{len(audio)} 字节")
            if (take.get("peak") or 0) < 0.02:
                print("       提示: 峰值很低，可能是静音或麦克风音量太小")

        print("\n3) 载入已有语音包")
        packs = state.get("packs") or []
        take_path = ""
        check("列出了语音包", bool(packs), f"{len(packs)} 个")
        if packs:
            loaded = call(url, "/api/packs/load", {"id": packs[0]["id"]}, timeout=60)
            ok = check("载入成功", loaded.get("ok"), loaded.get("error", ""))
            if ok:
                check("拿到录音", (loaded.get("seconds") or 0) > 0,
                      f"{loaded.get('seconds')} 秒")
                audio, error = fetch_bytes(url, "/api/audio/take")
                check("载入后可回放", len(audio) > 2048,
                      error or f"{len(audio)} 字节")
                take_path = loaded.get("path") or ""
                print(f"       已载入: {loaded.get('name')}"
                      f"（语调参考: {'有' if loaded.get('style') else '无'}）")

        if not args.no_preview:
            print("\n4) 试听克隆（自定义文本，第一次要加载模型，约 20~40 秒）")
            sentence = args.text or "自检这句话，用来确认输入文本能生效。"
            body = {"text": sentence, "speed": args.speed,
                    "instruct": args.instruct}
            preview = call(url, "/api/preview", body, timeout=420)
            ok = check("克隆成功", preview.get("ok"), preview.get("error", ""))
            if ok:
                clip = preview.get("preview") or {}
                audio, error = fetch_bytes(url, "/api/audio/preview")
                check("拿到克隆音频", len(audio) > 2048,
                      error or f"{clip.get('seconds')} 秒 / {len(audio)} 字节")

        if not args.no_preview:
            print("\n5) 语调参考被删掉后仍能试听")
            source = take_path
            if source and Path(source).exists():
                # Upload a style through the same endpoint the page uses, then
                # delete the converted file the way a user would.
                request = urllib.request.Request(
                    url + "/api/style", data=Path(source).read_bytes(),
                    headers={"Content-Type": "application/octet-stream",
                             "X-Filename": "probe.wav"})
                with urllib.request.urlopen(request, timeout=180) as response:
                    imported = json.loads(response.read().decode("utf-8"))
                ok = check("上传语调参考", imported.get("ok"), imported.get("error", ""))
                if ok:
                    converted = Path(imported.get("path") or "")
                    if converted.exists():
                        converted.unlink()
                    again = call(url, "/api/preview",
                                 {"text": "语调文件没了还能试听吗"}, timeout=420)
                    check("丢失语调后仍能试听", again.get("ok"),
                          again.get("error", ""))
                    check("并给出提示", bool(again.get("notice")),
                          again.get("notice") or "没有提示")
            else:
                print("       （没有可用的录音，跳过）")

        if args.save:
            print("\n6) 保存语音包")
            saved = call(url, "/api/save",
                         {"name": args.save, "speed": args.speed,
                          "instruct": args.instruct, "promptText": sentence},
                         timeout=120)
            ok = check("保存成功", saved.get("ok"), saved.get("error", ""))
            if ok:
                folder = Path(saved.get("dir") or "")
                check("文件夹存在", folder.exists(), str(folder))
                check("有 manifest.json", (folder / "manifest.json").exists())
                check("有 reference.wav", (folder / "reference.wav").exists())
                try:
                    written = json.loads(
                        (folder / "manifest.json").read_text(encoding="utf-8"))
                    check("清单记下了语速", abs(
                        float(written.get("speed") or 1) - args.speed) < 0.001,
                        str(written.get("speed")))
                    if args.instruct:
                        check("清单记下了语气指令",
                              (written.get("instruct") or "") == args.instruct,
                              written.get("instruct") or "空")
                    check("清单记下了参考文本",
                          bool(written.get("promptText")),
                          (written.get("promptText") or "")[:16])
                except Exception as error:  # noqa: BLE001
                    check("清单可解析", False, str(error))
                print(f"       包目录: {folder}")
                print("       （确认无误后可在应用里删除，或直接删掉这个文件夹）")
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
            print("\n工作室已停止")

    print()
    if FAILED:
        print(f"失败 {len(FAILED)} 项: " + ", ".join(FAILED))
        return 1
    print("全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
