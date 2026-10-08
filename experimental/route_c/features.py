# -*- coding: utf-8 -*-
"""plan_C features: per-second merged feature table for one segment.

Reuses existing motion/density solutions (they write per-second CSVs),
adds audio columns (rms_db / onset / hi_ratio), adds +/-5s context
(mean/max) and emits one CSV row per integer second under
  <root>/feats/<name>.csv        (fingerprinted -> resumable)
  <root>/raw/<sol>/<name>.csv    (solution outputs, isolated under root)
All intermediate artifacts stay under <root> (default temp/models/plan_C).

usage:
  python experimental/route_c/features.py <video1> <video2> ... [--out ROOT]
  python experimental/route_c/features.py --roi-check <video> --out ROOT
  python experimental/route_c/features.py --selftest
"""
import argparse
import os
import subprocess
import sys
import time

import numpy as np

_RC = os.path.dirname(os.path.abspath(__file__))
_EXP = os.path.dirname(_RC)
sys.path.insert(0, _EXP)

from motion_common import (frame_reader, roi_mask, zone_masks, moving_avg,
                           write_csv, WIDTH, SAMPLE_FPS)  # noqa: E402
import solution1_framediff as s1  # noqa: E402
import solution2_optflow as s2  # noqa: E402
import solution3_track as s3  # noqa: E402
import density_solution1_occupancy as d1  # noqa: E402
import density_solution3_trackcount as d3  # noqa: E402

SOLUTIONS = [('sol1', s1.process), ('sol2', s2.process),
             ('sol3', s3.process), ('den1', d1.process),
             ('den3', d3.process)]

BASE_COLS = ['activity', 'activity_smooth',
             'n_tracked', 'n_moving', 'frac_moving', 'p90_speed_px_s',
             'n_tracks', 'mean_speed_px_s', 'still_ratio',
             'occ_left', 'occ_right', 'tracks_left', 'tracks_right',
             'rms_db', 'onset', 'hi_ratio']
CTX_WIN = 11  # +/-5s at 1s grid
AUDIO_SR = 32000
VERSION = 1


def repo_root():
    return os.path.dirname(_EXP)


def default_root():
    return os.path.join(repo_root(), 'temp', 'models', 'plan_C')


def _ffmpeg():
    p = os.path.join(repo_root(), 'tools', 'ffmpeg', 'ffmpeg.exe')
    return p if os.path.exists(p) else None


def fingerprint(video):
    return f'{VERSION}:{os.path.getmtime(video)}:{WIDTH}:{SAMPLE_FPS}'


def read_csv_series(path):
    """Return {'t': np.array, col: np.array, ...}; skip '#' meta rows."""
    import csv
    cols = {}
    with open(path, 'r', encoding='utf-8', newline='') as f:
        r = csv.reader(f)
        header = None
        for row in r:
            if not row:
                continue
            if row[0].startswith('#'):
                continue
            if header is None:
                header = row
                for c in header:
                    cols[c] = []
                continue
            for c, val in zip(header, row):
                cols[c].append(float(val))
    return {c: np.array(v) for c, v in cols.items()}


def merge_per_second(series_list):
    """Merge several per-t series (dicts of arrays incl 't') onto a 1s grid."""
    ts_all = np.concatenate([s['t'] for s in series_list])
    kmin, kmax = int(np.floor(ts_all.min())), int(np.floor(ts_all.max()))
    nb = kmax - kmin + 1
    out = {'t': np.arange(kmin, kmax + 1, dtype=float)}
    for s in series_list:
        k = np.floor(s['t']).astype(np.int64) - kmin
        for name, vals in s.items():
            if name == 't':
                continue
            cnt = np.bincount(k, minlength=nb)
            sm = np.bincount(k, weights=vals, minlength=nb)
            out[name] = np.where(cnt > 0, sm / np.maximum(cnt, 1), 0.0)
    return out, kmin


def audio_seconds(video, sample_rate=AUDIO_SR):
    """Yield (block_index, float mono samples) aligned to integer seconds."""
    ff = _ffmpeg()
    if ff is None:
        raise RuntimeError('ffmpeg not found; audio features disabled')
    n = sample_rate
    args = [ff, '-hide_banner', '-loglevel', 'error', '-i', video,
            '-vn', '-ac', '1', '-ar', str(sample_rate), '-f', 's16le', '-']
    p = subprocess.Popen(args, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL,
                         bufsize=max(n * 4, 1 << 20))
    k = 0
    while True:
        buf = p.stdout.read(n * 2)
        if len(buf) < n * 2 // 4:  # tail shorter than 0.25s: drop
            p.stdout.close()
            p.wait()
            return
        a = np.frombuffer(buf[:n * 2], dtype=np.int16).astype(np.float32)
        a /= 32768.0
        yield k, a
        k += 1


def audio_feats(sig, prev_db=None, sample_rate=AUDIO_SR):
    """rms_db, onset, hi_ratio (>8kHz energy share) for one second block."""
    rms = float(np.sqrt(np.mean(sig * sig)))
    rms_db = max(20.0 * np.log10(rms + 1e-7), -120.0)
    onset = rms_db - prev_db if prev_db is not None else 0.0
    n = len(sig)
    win = np.hanning(n)
    sp = np.abs(np.fft.rfft(sig * win)) ** 2
    fr = np.fft.rfftfreq(n, 1.0 / sample_rate)
    hi = sp[fr > 8000.0].sum()
    tot = sp.sum()
    hi_ratio = float(hi / tot) if tot > 0 else 0.0
    return rms_db, onset, hi_ratio


def _fill_forward(a):
    last = 0.0
    for i in range(len(a)):
        if np.isnan(a[i]):
            a[i] = last
        else:
            last = a[i]
    return a


def audio_columns(video, nb, kmin):
    rms = np.full(nb, np.nan)
    ons = np.full(nb, np.nan)
    hir = np.full(nb, np.nan)
    prev = None
    try:
        for blk, sig in audio_seconds(video):
            k = blk + kmin
            if k >= nb:
                break
            db, on, hr = audio_feats(sig, prev)
            if prev is None:
                on = 0.0
            prev = db
            rms[k], ons[k], hir[k] = db, on, hr
    except (RuntimeError, OSError):
        pass
    return (_fill_forward(rms), _fill_forward(ons), _fill_forward(hir))


def build_table(video, root=None):
    """Compute (or load cached) feature table for one segment.

    returns (ts: np.array, X: np.ndarray [n x p], colnames: [str])
    """
    root = root or default_root()
    name = os.path.splitext(os.path.basename(video))[0]
    feats_dir = os.path.join(root, 'feats')
    os.makedirs(feats_dir, exist_ok=True)
    feats_path = os.path.join(feats_dir, f'{name}.csv')
    fp = fingerprint(video)
    if os.path.exists(feats_path) and _cached_fingerprint(feats_path) == fp:
        d = read_csv_series(feats_path)
        colnames = [c for c in d if c != 't']
        X = np.column_stack([d[c] for c in colnames])
        return d['t'], X, colnames

    t0 = time.perf_counter()
    raw_root = os.path.join(root, 'raw')
    series = []
    for tag, proc in SOLUTIONS:
        od = os.path.join(raw_root, tag)
        os.makedirs(od, exist_ok=True)
        p0 = time.perf_counter()
        proc(video, od, name)
        series.append(read_csv_series(os.path.join(od, f'{name}.csv')))
        print(f'    [{tag}] {time.perf_counter() - p0:.1f}s')
    merged, kmin = merge_per_second(series)

    base = {c: merged[c] for c in BASE_COLS if c in merged}
    for c in ('rms_db', 'onset', 'hi_ratio'):
        if c not in merged:
            base[c] = np.zeros(len(merged['t']))
    ar, ao, ah = audio_columns(video, len(merged['t']), kmin)
    base['rms_db'], base['onset'], base['hi_ratio'] = ar, ao, ah

    from scipy.ndimage import maximum_filter1d
    cols = {c: base[c] for c in BASE_COLS}
    for c in BASE_COLS:
        cols[c + '_mean5'] = moving_avg(cols[c], CTX_WIN)
        cols[c + '_max5'] = maximum_filter1d(cols[c], size=CTX_WIN,
                                             mode='nearest')
    order = ([c for c in BASE_COLS]
             + [c + '_mean5' for c in BASE_COLS]
             + [c + '_max5' for c in BASE_COLS])

    rows = []
    for i, t in enumerate(merged['t']):
        rows.append([round(float(t), 2)] + [round(float(cols[c][i]), 5)
                                            for c in order])
    write_csv(feats_path, ['t'] + order, rows, meta={'fingerprint': fp})
    X = np.column_stack([cols[c] for c in order])
    print(f'  [{name}] #rows={len(merged["t"])} '
          f'build={time.perf_counter() - t0:.1f}s -> {feats_path}')
    return merged['t'], X, order


def _cached_fingerprint(csv_path):
    try:
        with open(csv_path, 'r', encoding='utf-8', newline='') as f:
            for line in f:
                if line.startswith('#fingerprint,'):
                    return line.strip().split(',', 1)[1].strip()
    except Exception:
        pass
    return None


def roi_check(video, root=None):
    import cv2
    root = root or default_root()
    frame = next(frame_reader(video), None)
    if frame is None:
        print('cannot read frame', file=sys.stderr)
        return 1
    t, gray = frame
    h, w = gray.shape
    roi = roi_mask(h, w)
    oz = zone_masks(h, w)
    rgb = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    rgb[roi == 0] = (0, 0, 200)
    for zm in oz:
        rgb[zm == 1] = (0, 200, 0)
        rgb[zm == 1][::25] = (0, 0, 255)
    vis = os.path.join(root, 'vis')
    os.makedirs(vis, exist_ok=True)
    nm = os.path.splitext(os.path.basename(video))[0]
    out = os.path.join(vis, f'{nm}_roi.png')
    cv2.imwrite(out, rgb)
    print('roi overlay: %s' % os.path.abspath(out))
    return 0


def selftest():
    # merge_per_second
    s1d = {'t': np.array([0.0, 0.5, 1.0]), 'a': np.array([1.0, 3.0, 5.0])}
    s2d = {'t': np.array([0.33, 1.33]), 'b': np.array([2.0, 4.0])}
    m, kmin = merge_per_second([s1d, s2d])
    assert kmin == 0
    assert list(m['t']) == [0, 1], m['t']
    assert abs(m['a'][0] - 2.0) < 1e-9 and abs(m['a'][1] - 5.0) < 1e-9, m['a']
    assert abs(m['b'][0] - 2.0) < 1e-9 and abs(m['b'][1] - 4.0) < 1e-9, m['b']

    # audio_feats: silent vs 9kHz burst vs 1kHz tone
    import math
    n = AUDIO_SR
    sr = AUDIO_SR
    t = np.arange(n) / sr
    silent = np.zeros(n, np.float32)
    burst9 = (0.5 * np.sin(2 * math.pi * 9000 * t)).astype(np.float32)
    tone1k = (0.5 * np.sin(2 * math.pi * 1000 * t)).astype(np.float32)

    db_s, on_s, hi_s = audio_feats(silent)
    db_9, on_9, hi_9 = audio_feats(burst9, prev_db=db_s)
    db_1, on_1, hi_1 = audio_feats(tone1k, prev_db=db_s)
    assert db_s < -100.0, db_s
    assert db_9 > db_s + 40.0, (db_s, db_9)
    assert on_9 > 40.0, on_9
    assert hi_9 > 0.5 and hi_1 < 0.05, (hi_9, hi_1)
    print('features selftest OK')


def main(argv):
    ap = argparse.ArgumentParser(description='plan_C feature extraction')
    ap.add_argument('videos', nargs='*')
    ap.add_argument('--out', default=None, help='root dir (default '
                    'temp/models/plan_C)')
    ap.add_argument('--roi-check', metavar='VIDEO', default=None)
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args(argv)
    if args.selftest or '--selftest' in argv:
        selftest()
        return 0
    root = args.out or default_root()
    if args.roi_check:
        return roi_check(args.roi_check, root)
    if not args.videos:
        ap.error('no videos given')
    for v in args.videos:
        if not os.path.exists(v):
            print('missing video: %s' % v, file=sys.stderr)
            continue
        print('[features] %s' % os.path.basename(v))
        build_table(v, root)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))