"""Shared helpers for the three motion-quantization CLIs.

All processing is local (OpenCV classic CV), no models, no cloud.
See temp/motion_quantization_solutions.md for the design.
"""
import csv
import json
import os
import sys

import cv2
import numpy as np

WIDTH = 480
SAMPLE_FPS = 3.0


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def out_dir(*parts):
    d = os.path.join(repo_root(), 'temp', *parts)
    os.makedirs(d, exist_ok=True)
    return d


def read_filelist(path):
    base = os.path.dirname(os.path.abspath(path))
    videos = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            p = line if os.path.isabs(line) else os.path.join(base, line)
            if not os.path.exists(p):
                print(f'[warn] missing video: {p}', file=sys.stderr)
                continue
            videos.append(p)
    return videos


def roi_mask(h, w):
    """Field band ROI: drop sky/stands, bottom-right watermark, right leaves."""
    m = np.zeros((h, w), np.uint8)
    y0, y1 = int(h * 0.30), int(h * 0.95)
    x0, x1 = int(w * 0.02), int(w * 0.98)
    m[y0:y1, x0:x1] = 1
    m[int(h * 0.90):, int(w * 0.70):] = 0  # timestamp watermark
    m[:, int(w * 0.88):] = 0               # foreground leaves
    return m


# normalized (x0, y0, x1, y1) end zones, left=far end, right=near end
# (per-camera calibration; see temp/end_density_solutions.md §0)
ZONES = ((0.10, 0.45, 0.30, 0.62), (0.62, 0.45, 0.88, 0.80))
# per zone (area_min, area_max, typical single-person area) px^2 at 480w
PERSON_AREA = ((40, 400, 100), (150, 1200, 400))


def zone_masks(h, w):
    masks = []
    for x0, y0, x1, y1 in ZONES:
        m = np.zeros((h, w), np.uint8)
        m[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)] = 1
        masks.append(m)
    return masks


_K = None


def new_mog2():
    return cv2.createBackgroundSubtractorMOG2(
        history=300, varThreshold=25, detectShadows=False)


def foreground(mog2, gray, roi):
    """Foreground mask: MOG2 + ROI + open/close denoise."""
    global _K
    if _K is None:
        _K = (cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)),
              cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    fg = mog2.apply(gray, learningRate=0.01)
    fg = cv2.bitwise_and(fg, fg, mask=roi)
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, _K[0])
    return cv2.morphologyEx(fg, cv2.MORPH_CLOSE, _K[1])


def _ffmpeg_pipe_reader(video, width, sample_fps):
    """Decode ~sample_fps gray frames at `width` via ffmpeg rawvideo pipe.

    cv2.VideoCapture decodes every full-res frame (4K football clips take
    minutes); ffmpeg does the subsample+scale in one pass → 5-10x faster.
    Yields (t_sec, gray) exactly like the OpenCV path.  Falls back to the
    caller's OpenCV path when ffmpeg isn't available.
    """
    import subprocess
    ffprobe = os.path.join(repo_root(), 'tools', 'ffmpeg', 'ffprobe.exe')
    ffmpeg = os.path.join(repo_root(), 'tools', 'ffmpeg', 'ffmpeg.exe')
    if not (os.path.exists(ffmpeg) and os.path.exists(ffprobe)):
        return None
    try:
        out = subprocess.run(
            [ffprobe, '-v', 'error', '-select_streams', 'v:0',
             '-show_entries', 'stream=width,height', '-of', 'csv=p=0',
             video], capture_output=True, text=True, timeout=30).stdout.strip()
        w0, h0 = map(int, out.split(','))
    except Exception:
        return None
    out_h = int(round(h0 * width / w0 / 2) * 2)
    frame_bytes = width * out_h
    args = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-i', video,
            '-vf', f'fps={sample_fps},scale={width}:{out_h},format=gray',
            '-f', 'rawvideo', '-pix_fmt', 'gray', '-']
    p = subprocess.Popen(args, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL,
                         bufsize=max(frame_bytes * 4, 1 << 20))
    t = 0.0
    dt = 1.0 / sample_fps
    while True:
        buf = p.stdout.read(frame_bytes)
        if not buf or len(buf) < frame_bytes:
            p.stdout.close()
            p.wait()
            return
        yield t, np.frombuffer(buf, dtype=np.uint8).reshape(out_h, width)
        t += dt


def frame_reader(video, width=WIDTH, sample_fps=SAMPLE_FPS):
    """Yield (t_sec, gray) at ~sample_fps, downscaled to `width`."""
    it = _ffmpeg_pipe_reader(video, width, sample_fps)
    first = next(it, None)  # peek: ffmpeg path emits nothing when unavailable
    if first is not None:
        yield first
        yield from it
        return
    # OpenCV fallback path.
    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        raise IOError(f'cannot open {video}')
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, round(fps / sample_fps))
    out_h = None
    idx = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if idx % step == 0:
            h, w = frame.shape[:2]
            if out_h is None:
                out_h = int(round(h * width / w / 2) * 2)
            small = cv2.resize(frame, (width, out_h))
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
            yield idx / fps, gray
        idx += 1
    cap.release()


def moving_avg(xs, win):
    if win <= 1:
        return list(xs)
    k = np.ones(win) / win
    return list(np.convolve(xs, k, mode='same'))


def median(xs):
    return float(np.median(xs)) if len(xs) else 0.0


def detect_events(ts, vs, thr, min_dur=2.0, direction='below'):
    """Contiguous runs where v crosses thr for >= min_dur seconds."""
    events = []
    start = None
    vals = []
    for i, (t, v) in enumerate(zip(ts, vs)):
        hit = v <= thr if direction == 'below' else v >= thr
        if hit and start is None:
            start, vals = t, []
        if start is not None:
            vals.append(v)
        if start is not None and (not hit or i == len(vs) - 1):
            end = t if hit else ts[i - 1]
            if end - start >= min_dur:
                events.append({
                    'start': round(start, 2),
                    'end': round(end, 2),
                    'duration': round(end - start, 2),
                    'mean_value': round(float(np.mean(vals)), 4),
                })
            start = None
    return events


def write_csv(path, header, rows, meta=None):
    """meta is written as '#key,value' lines right after the header."""
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(header)
        for k, v in (meta or {}).items():
            w.writerow([f'#{k}', v])
        w.writerows(rows)


def write_json(path, obj):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def run_cli(solution, process, group='motion_quant'):
    """CLI entry: argv[1] = filelist.txt; process(video, out_dir) -> dict."""
    if len(sys.argv) < 2:
        print(f'usage: python {sys.argv[0]} <filelist.txt>', file=sys.stderr)
        sys.exit(1)
    videos = read_filelist(sys.argv[1])
    if not videos:
        print('no videos in filelist', file=sys.stderr)
        sys.exit(1)
    od = out_dir(group, solution)
    summary = {'solution': solution, 'videos': []}
    for v in videos:
        name = os.path.splitext(os.path.basename(v))[0]
        print(f'[{solution}] {os.path.basename(v)} ...')
        result = process(v, od, name)
        summary['videos'].append(result)
    sp = os.path.join(od, '_summary.json')
    write_json(sp, summary)
    print(f'[{solution}] summary: {sp}')


if __name__ == '__main__':
    ts = [0.0, 1, 2, 3, 4, 5, 6, 7]
    vs = [1.0, 0.1, 0.1, 0.1, 1.0, 1.0, 0.2, 0.2]
    ev = detect_events(ts, vs, 0.3, min_dur=2.0, direction='below')
    assert len(ev) == 1 and ev[0]['start'] == 1.0 and ev[0]['end'] == 3.0, ev
    ev2 = detect_events(ts, [0.9, 0.9, 0.1], 0.5, min_dur=1.0, direction='above')
    assert len(ev2) == 1 and ev2[0]['end'] == 1.0, ev2
    print('motion_common selftest OK')
