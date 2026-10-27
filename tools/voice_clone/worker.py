"""Local voice cloning worker (CosyVoice2).

Reads one JSON request per line on stdin and writes one JSON reply per line
on stdout. The model is loaded once and kept warm, so the app pays the load
cost only for the very first line.

Request:
    {"text": "任意文字",
     "prompt_text": "参考录音里念的那段话",
     "reference": "C:/.../my_voice.wav",
     "output": "C:/.../out.wav"}
Reply:
    {"ok": true, "path": "C:/.../out.wav"}
    {"ok": false, "error": "..."}

The model never talks to the network once it is cached; setup.bat downloads it.
"""

import json
import os
import sys
import tempfile
import traceback

# The protocol is UTF-8 regardless of the console code page: a GBK/UTF-8
# mismatch here turns Chinese into lone surrogates, which makes CosyVoice take
# its English path and then fail inside the tokenizer.
for stream in (sys.stdin, sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

# Keep the protocol stream clean: CosyVoice and modelscope print progress with
# plain print(), and a stray line on stdout is a JSON parse error for the app.
# Replies go to the real stdout; everything else is diverted to stderr.
_PROTOCOL = sys.stdout
sys.stdout = sys.stderr

# Splits "how to say it" from "what to say" for the instruct path. The engine
# needs it at the end of the instruction (see example.py:
# '用四川话说这句话<|endofprompt|>'); without it the model reads the
# instruction aloud as if it were part of the sentence.
END_OF_PROMPT = "<|endofprompt|>"


def reply(payload):
    print(json.dumps(payload, ensure_ascii=False), file=_PROTOCOL, flush=True)

ROOT = os.environ.get("HIGHLIGHT_COSYVOICE_ROOT", "")
MODEL_DIR = os.environ.get("HIGHLIGHT_COSYVOICE_MODEL", "")

# The worker sits next to the checkout and the model, so it can find them
# itself; the app passes the env vars only to be explicit.
HERE = os.path.dirname(os.path.abspath(__file__))
if not ROOT:
    ROOT = os.path.join(HERE, "CosyVoice")
if not MODEL_DIR:
    MODEL_DIR = os.path.join(HERE, "models", "CosyVoice2-0.5B")

if os.path.isdir(ROOT):
    # CosyVoice's own entry scripts put the Matcha-TTS submodule on the path;
    # cosyvoice/flow/flow_matching.py imports matcha without adding it, so the
    # import only works when the entry point does this.
    for entry in (ROOT, os.path.join(ROOT, "third_party", "Matcha-TTS")):
        if entry not in sys.path:
            sys.path.insert(0, entry)


def log(message):
    """Progress goes to stderr; stdout carries the protocol only."""
    print(message, file=sys.stderr, flush=True)


def load_model():
    import torch
    from cosyvoice.cli.cosyvoice import CosyVoice2

    gpu = torch.cuda.is_available()
    log("[voice-clone] loading %s (gpu=%s)" % (MODEL_DIR, gpu))
    # fp16 halves the memory; a small card may not fit it.
    try:
        model = CosyVoice2(MODEL_DIR, load_jit=False, load_trt=False, fp16=True)
    except Exception as error:
        log("[voice-clone] fp16 failed (%s), retrying in fp32" % error)
        model = CosyVoice2(MODEL_DIR, load_jit=False, load_trt=False, fp16=False)
    log("[voice-clone] ready")
    return model


def limit_reference(path, max_seconds=30.0):
    """The speech tokenizer refuses prompts longer than 30s.

    Trim to the tail (the cleanest part of a reading) instead of failing with
    an assertion the user cannot act on.
    """
    # torchaudio is imported inside main; import it here too so this helper
    # also works when it is called first.
    import torchaudio

    speech, sample_rate = torchaudio.load(path, backend="soundfile")
    max_frames = int(max_seconds * sample_rate)
    if speech.shape[1] <= max_frames:
        return path
    trimmed = os.path.join(tempfile.gettempdir(), "hl_voice_ref.wav")
    torchaudio.save(trimmed, speech[:, -max_frames:], sample_rate)
    return trimmed


def main():
    if "--prefetch" in sys.argv:
        # The model is downloaded by setup.bat; here we only make sure it
        # loads, which also proves the environment works.
        load_model()
        reply({"ok": True, "path": ""})
        return

    import torch
    import torchaudio

    from cosyvoice.utils.common import set_all_random_seed

    # The LLM samples speech tokens with torch.multinomial (ras_sampling), so
    # without a seed the same sentence comes back with a different delivery -
    # and a different voice - every time. One seed per worker keeps runs
    # reproducible; change it for a different variation.
    seed = int(os.environ.get("HIGHLIGHT_TTS_SEED", "42"))

    model = load_model()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            # A path, not a pre-loaded tensor: this CosyVoice revision calls
            # load_wav inside the frontend and chokes when handed a tensor.
            reference = limit_reference(request["reference"])
            style = request.get("prosody_reference") or ""
            instruct = (request.get("instruct") or "").strip()
            prompt_text = request.get("prompt_text") or ""
            speed = float(request.get("speed") or 1.0)
            # token2wav rescales the mel, so applying it on both stages of the
            # two-stage path would square the effect. Only the last stage gets
            # it; the draft always runs at 1.0.
            set_all_random_seed(int(request.get("seed", seed)))
            chunks = []

            # Four paths, in order of how much they steer the delivery:
            #   instruct + style  -> instruct over the style's prosody, then VC
            #   instruct only     -> instruct on the user's own voice
            #   style only        -> the style's prosody, then VC
            #   neither           -> plain zero-shot clone
            if instruct:
                if END_OF_PROMPT not in instruct:
                    instruct = instruct.rstrip() + END_OF_PROMPT
                base = limit_reference(style) if style else reference
                chunks = [
                    out["tts_speech"]
                    for out in model.inference_instruct2(
                        request["text"],
                        instruct,
                        base,
                        stream=False,
                        speed=1.0 if style else speed,
                    )
                ]
                if style and chunks:
                    draft_path = os.path.join(
                        tempfile.gettempdir(), "hl_instruct_draft.wav"
                    )
                    torchaudio.save(
                        draft_path,
                        torch.cat(chunks, dim=1),
                        model.sample_rate,
                        encoding="PCM_S",
                        bits_per_sample=16,
                    )
                    chunks = [
                        out["tts_speech"]
                        for out in model.inference_vc(
                            draft_path, reference, stream=False, speed=speed
                        )
                    ]
                    try:
                        os.remove(draft_path)
                    except OSError:
                        pass
            elif style:
                # Two stages. The style file only has to set the delivery, so
                # the first pass needs no prompt text; the second pass keeps
                # that delivery and swaps the timbre for the user's voice.
                draft_chunks = [
                    out["tts_speech"]
                    for out in model.inference_cross_lingual(
                        request["text"], limit_reference(style), stream=False
                    )
                ]
                if not draft_chunks:
                    raise RuntimeError("语调参考没有生成音频")
                draft_path = os.path.join(
                    tempfile.gettempdir(), "hl_style_draft.wav"
                )
                torchaudio.save(
                    draft_path,
                    torch.cat(draft_chunks, dim=1),
                    model.sample_rate,
                    encoding="PCM_S",
                    bits_per_sample=16,
                )
                chunks = [
                    out["tts_speech"]
                    for out in model.inference_vc(
                        draft_path, reference, stream=False, speed=speed
                    )
                ]
                try:
                    os.remove(draft_path)
                except OSError:
                    pass
            else:
                chunks = [
                    out["tts_speech"]
                    for out in model.inference_zero_shot(
                        request["text"],
                        prompt_text,
                        reference,
                        stream=False,
                        speed=speed,
                    )
                ]
            if not chunks:
                raise RuntimeError("没有生成音频")
            speech = torch.cat(chunks, dim=1)
            # PCM16, not the float32 default: Python's wave module (and
            # other plain readers) refuse float WAVs.
            torchaudio.save(
                request["output"],
                speech,
                model.sample_rate,
                encoding="PCM_S",
                bits_per_sample=16,
            )
            reply({"ok": True, "path": request["output"]})
        except Exception as error:  # the app shows this message to the user
            log(traceback.format_exc())
            reply({"ok": False, "error": str(error)})


if __name__ == "__main__":
    main()
