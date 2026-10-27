"""Install the local voice-cloning engine (CosyVoice2).

Run this once. It clones the CosyVoice repository, creates a virtual
environment, installs the packages and downloads the model; afterwards the
cloning runs offline, on this machine only. Budget about 6 GB of disk.

Every step checks what is already there, so an interrupted run is simply
started again - nothing is downloaded twice.

    python setup.py           install
    python setup.py --check   report what is installed, download nothing
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path(os.environ.get("USERPROFILE") or Path.home())
DEST = HOME / "HighlightCreator" / "voice_clone"
REPO = DEST / "CosyVoice"
MODEL = DEST / "models" / "CosyVoice2-0.5B"
VENV_PY = DEST / "venv" / "Scripts" / "python.exe"
WORKER = Path(__file__).resolve().parent / "worker.py"
STUDIO = Path(__file__).resolve().parent / "studio"

REPO_URL = "https://github.com/FunAudioLLM/CosyVoice.git"
MODEL_ID = "iic/CosyVoice2-0.5B"
HF_MODEL_ID = "FunAudioLLM/CosyVoice2-0.5B"

# The big wheels stall on the default index; these mirrors are usually faster.
INDEXES = [
    "https://mirrors.cloud.tencent.com/pypi/simple",
    "https://pypi.tuna.tsinghua.edu.cn/simple",
    "https://pypi.org/simple",
]

# PyPI's Windows torch wheel is CPU-only; the CUDA build only exists here.
# Adding it as an extra index works because 2.3.1+cu121 outranks plain 2.3.1.
TORCH_INDEX = "https://download.pytorch.org/whl/cu121"


def say(message):
    print(message, flush=True)


# The console may be GBK or UTF-8; make sure the Chinese labels survive either.
for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def status():
    """What is already in place, so the user knows where a failed run stopped."""
    return {
        "仓库 CosyVoice": (REPO / "cosyvoice").exists(),
        "Matcha-TTS 子模块": (REPO / "third_party" / "Matcha-TTS" / "matcha").exists(),
        "虚拟环境": VENV_PY.exists(),
        "torch": (DEST / "venv" / "Lib" / "site-packages" / "torch").exists(),
        "coqui/依赖": (DEST / "venv" / "Lib" / "site-packages" / "modelscope").exists(),
        "模型 CosyVoice2-0.5B": (MODEL / "cosyvoice2.yaml").exists(),
        "语音工作室": (DEST / "studio" / "studio.py").exists(),
    }


def run(command, label, retries=1, **kwargs):
    """Run a command, retrying a few times: these downloads drop often."""
    for attempt in range(1, retries + 1):
        say("  -> %s (第 %d 次)" % (label, attempt))
        result = subprocess.run(command, **kwargs)
        if result.returncode == 0:
            return True
        say("  !! %s 失败 (exit %d)" % (label, result.returncode))
    return False


def git(*args):
    return ["git", *args]


def pip_install(packages, retries=2, extra_indexes=(), index=None,
                force=False, no_deps=False):
    """Install into the venv, walking the mirror list until one works."""
    for entry in ([index] if index else INDEXES):
        command = [str(VENV_PY), "-m", "pip", "install", *packages,
                   "--timeout", "60", "--retries", "20",
                   "--index-url", entry]
        for extra in extra_indexes:
            command += ["--extra-index-url", extra]
        if force:
            command.append("--force-reinstall")
        if no_deps:
            command.append("--no-deps")
        if run(command, "%s @ %s" % (" ".join(packages), entry.split("/")[2]),
               retries=retries):
            return True
        say("  .. 换下一个源")
    return False


def has_cuda_torch():
    probe = subprocess.run(
        [str(VENV_PY), "-c", "import torch,sys; sys.exit(0 if torch.version.cuda else 1)"],
        capture_output=True)
    return probe.returncode == 0


def ensure_torch():
    """PyPI's Windows wheel is CPU-only, so the CUDA build has to be forced in.

    A plain install is a no-op once 2.3.1+cpu is there: pip counts it as
    satisfying "==2.3.1" and never looks at the CUDA wheel.
    """
    if VENV_PY.exists() and has_cuda_torch():
        say("  torch 已是 CUDA 版，跳过")
        return True
    say("== 换装 CUDA 版 torch (约 2.5 GB) ==")
    return pip_install(["torch==2.3.1", "torchaudio==2.3.1"],
                       index=TORCH_INDEX, force=True, no_deps=True)


def ensure_repo():
    if not (REPO / "cosyvoice").exists():
        say("== 克隆 CosyVoice 仓库 ==")
        REPO.parent.mkdir(parents=True, exist_ok=True)
        if not run(git("clone", "--recursive", REPO_URL, str(REPO)), "git clone",
                   retries=3):
            return False

    # The submodule drops its connection often; keep retrying.
    for attempt in range(1, 6):
        if (REPO / "third_party" / "Matcha-TTS" / "matcha").exists():
            return True
        say("== 拉取 Matcha-TTS 子模块 (第 %d 次) ==" % attempt)
        subprocess.run(git("-C", str(REPO), "submodule", "update", "--init",
                           "--recursive"))
    return (REPO / "third_party" / "Matcha-TTS" / "matcha").exists()


def ensure_venv():
    if VENV_PY.exists():
        return True
    say("== 创建虚拟环境 ==")
    return run([sys.executable, "-m", "venv", str(DEST / "venv")], "venv")


def ensure_packages():
    os.environ.setdefault("PIP_CACHE_DIR", str(DEST / "pipcache"))
    run([str(VENV_PY), "-m", "pip", "install", "--upgrade", "pip"], "升级 pip")
    say("== 检查 torch ==")
    if not ensure_torch():
        return False
    say("== 安装 CosyVoice 依赖 (约 1 GB) ==")
    requirements = str(REPO / "requirements.txt")
    return pip_install(["-r", requirements])


def ensure_model():
    if (MODEL / "cosyvoice2.yaml").exists():
        return True
    say("== 下载模型 CosyVoice2-0.5B (约 4 GB) ==")
    script = (
        "from modelscope import snapshot_download;"
        "snapshot_download(%r, local_dir=%r)" % (MODEL_ID, str(MODEL))
    )
    for attempt in range(1, 4):
        if run([str(VENV_PY), "-c", script], "ModelScope 下载"):
            break
        say("  .. ModelScope 失败，改用 HuggingFace 镜像")
        env = dict(os.environ, HF_ENDPOINT="https://hf-mirror.com")
        hf = ("from huggingface_hub import snapshot_download;"
              "snapshot_download(%r, local_dir=%r)" % (HF_MODEL_ID, str(MODEL)))
        if run([str(VENV_PY), "-c", hf], "HF 镜像下载", env=env):
            break
    return (MODEL / "cosyvoice2.yaml").exists()


def ensure_worker():
    DEST.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(WORKER, DEST / "worker.py")
    return True


def ensure_studio():
    """Copy the studio next to the engine; plugin.json points at it."""
    target = DEST / "studio"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("studio.py", "studio.html", "studio.bat", "selftest.py"):
        source = STUDIO / name
        if not source.exists():
            continue
        data = source.read_bytes()
        if name.endswith(".bat"):
            # cmd reads an LF-only batch file as one long line: the second
            # line onward fails with "not recognized". Force CRLF whatever
            # the copy on disk uses.
            data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        (target / name).write_bytes(data)
    return (target / "studio.py").exists()


def write_manifest():
    """Describe the plugin so the app reads paths instead of guessing them.

    This file is the contract: an engine swap (a newer CosyVoice, a cloud
    backend) only has to ship a different manifest.
    """
    import json

    manifest = {
        "schema": 1,
        "kind": "tts-clone",
        "name": "CosyVoice2 本地克隆",
        "version": "1.0.0",
        "protocol": "hlc-voice-jsonl/1",
        "engine": "cosyvoice2",
        "python": "venv\\Scripts\\python.exe",
        "worker": "worker.py",
        "repo": "CosyVoice",
        "model": "models\\CosyVoice2-0.5B",
        "studio": "studio\\studio.bat",
        "limits": {"minReferenceSeconds": 3, "maxReferenceSeconds": 30},
    }
    (DEST / "plugin.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    say("  已写 plugin.json")
    return True


def check_loads():
    say("== 试加载模型（约 20~40 秒）==")
    env = dict(os.environ,
               HIGHLIGHT_COSYVOICE_ROOT=str(REPO),
               HIGHLIGHT_COSYVOICE_MODEL=str(MODEL))
    return run([str(VENV_PY), str(DEST / "worker.py"), "--prefetch"], "加载模型",
               env=env)


def main():
    parser = argparse.ArgumentParser(description="安装本地语音克隆引擎")
    parser.add_argument("--check", action="store_true",
                        help="只报告当前状态，不下载任何东西")
    args = parser.parse_args()

    if sys.version_info < (3, 10):
        say("需要 Python 3.10 或更新版本，当前是 %s" % sys.version.split()[0])
        return 1

    state = status()
    say("引擎目录: %s" % DEST)
    for name, done in state.items():
        say("  [%s] %s" % ("x" if done else " ", name))
    say("")

    if args.check:
        say("（--check 模式：未做任何改动）")
        return 0

    steps = [
        ("仓库", ensure_repo),
        ("虚拟环境", ensure_venv),
        ("依赖", ensure_packages),
        ("模型", ensure_model),
        ("worker", ensure_worker),
        ("工作室", ensure_studio),
        ("清单", write_manifest),
        ("自检", check_loads),
    ]
    for name, step in steps:
        if not step():
            say("")
            say("== 失败于「%s」==" % name)
            say("修好网络或环境后，重新运行本脚本即可接着装（不会重下已完成的）")
            return 1

    say("")
    say("== 安装完成 ==")
    say("启动 App，进 5佳球 - 下一步 - 创建自己语音，读提示词后选「我的声音」。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
