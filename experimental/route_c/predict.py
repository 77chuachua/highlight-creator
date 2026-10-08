# -*- coding: utf-8 -*-
"""plan_C predict: score a segment, post-process, emit events.json.

Pipeline: build features (cache) -> model probabilities per second ->
smooth -> peak detection on contiguous over-threshold runs -> temporal NMS
(merge runs closer than merge_secs on the same class) -> events.json
(grouped by video, same format as make_events).

usage:
  python experimental/route_c/predict.py <video1> <video2> ... [--model-dir DIR] [--out FILE]
  python experimental/route_c/predict.py --smoke
"""
import argparse
import json
import os
import pickle
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from motion_common import moving_avg  # noqa: E402
import features  # noqa: E402

DEFAULT_MODEL_DIR = os.path.join('temp', 'models', 'plan_C', 'models')
DEFAULT_OUT = os.path.join('temp', 'models', 'plan_C', 'events', 'events.json')
SMOOTH_SECS = 1.5
MERGE_SECS = 3.0
WIN_HS = 3.0  # predicted event window half-width


def postproc(ts, probs, thr, smooth_secs=SMOOTH_SECS, merge_secs=MERGE_SECS):
    """Smooth -> contiguous over-threshold runs -> keep argmax of each run.

    Returns list of {'t': float, 'p': float} already NMS'd (runs are by
    construction >=1s apart on the 1s grid; runs separated by a single
    below-threshold second are merged if closer than merge_secs).
    """
    p = np.array(moving_avg(probs, int(round(smooth_secs))))
    runs = []
    i = 0
    n = len(p)
    while i < n:
        if p[i] >= thr:
            j = i
            while j + 1 < n and p[j + 1] >= thr:
                j += 1
            # event time = center of the raw-prob plateau inside the run
            vals = np.asarray(probs[i:j + 1])
            ws = np.where(vals == vals.max())[0]
            k0, k1 = i + int(ws[0]), i + int(ws[-1])
            t = float((float(ts[k0]) + float(ts[k1])) / 2.0)
            runs.append({'t': t, 'p': float(vals.max())})
            i = j + 1
        else:
            i += 1
    # NMS: merge runs closer than merge_secs, keep the stronger one
    out = []
    for r in runs:
        if out and abs(r['t'] - out[-1]['t']) < merge_secs:
            if r['p'] > out[-1]['p']:
                out[-1] = r
        else:
            out.append(r)
    return out


def to_events(ts, probs, thr, cls):
    evs = []
    for r in postproc(ts, probs, thr):
        t = r['t']
        evs.append({'class': cls, 't_sec': round(t, 2),
                    'window': [round(max(0.0, t - WIN_HS), 2),
                               round(t + WIN_HS, 2)]})
    return evs


def load_models(model_dir):
    models = {}
    for cls in ('goal', 'save'):
        path = os.path.join(model_dir, f'{cls}.pkl')
        if os.path.exists(path):
            with open(path, 'rb') as f:
                models[cls] = pickle.load(f)
    return models


def load_thresholds(model_dir):
    thr = {}
    path = os.path.join(model_dir, 'thresholds.json')
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            thr = json.load(f)
    return thr


def predict_video(video, model_dir, root, thr=None):
    """Return events list (same schema as make_events) for one segment."""
    ts, X, _ = features.build_table(video, root)
    models = load_models(model_dir)
    thrs = load_thresholds(model_dir)
    evs = []
    for cls, clf in models.items():
        proba = clf.predict_proba(X)
        hi = proba.shape[1] - 1
        probs = proba[:, hi]
        t = (thr or {}).get(cls) or thrs.get(cls)
        if t is None:
            t = 0.5
        evs += to_events(ts, probs, float(t), cls)
    evs.sort(key=lambda e: e['t_sec'])
    return {'video': os.path.basename(video), 'events': evs}


def smoke():
    ts = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
    probs = [0.0, 0.0, 0.9, 0.9, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0]
    evs = postproc(ts, probs, 0.5)
    assert len(evs) == 1, evs
    # smoothed run covers cells 3..4, raw plateau -> center 3.5
    assert abs(evs[0]['t'] - 3.5) < 1e-9, evs
    # NMS merge: two single-cell peaks at t=1 and t=3 (2s apart < merge),
    # smoothing disabled so the branch under test is the NMS, not the fusion
    probs2 = [0.0, 0.9, 0.0, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    evs2 = postproc(ts, probs2, 0.5, smooth_secs=0.0)
    assert len(evs2) == 1, evs2
    assert abs(evs2[0]['t'] - 1.0) < 1e-9, evs2  # equal p: first kept
    # constant plateau -> single event (center of the detected run)
    probs3 = [0.95] * 10
    evs3 = postproc(ts, probs3, 0.5)
    assert len(evs3) == 1 and abs(evs3[0]['t'] - 5.0) < 1e-9, evs3
    print('predict selftest OK')


def main(argv):
    ap = argparse.ArgumentParser(description='plan_C event prediction')
    ap.add_argument('videos', nargs='*')
    ap.add_argument('--model-dir', default=DEFAULT_MODEL_DIR)
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--root', default=None,
                    help='features root (default temp/models/plan_C)')
    ap.add_argument('--smoke', action='store_true')
    args = ap.parse_args(argv)
    if args.smoke or '--smoke' in argv:
        smoke()
        return 0
    if not args.videos:
        ap.error('no videos given')
    root = args.root or features.default_root()
    agg = []
    for v in args.videos:
        if not os.path.exists(v):
            print('missing video: %s' % v, file=sys.stderr)
            continue
        print('[predict] %s' % os.path.basename(v))
        agg.append(predict_video(v, args.model_dir, root))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(agg, f, ensure_ascii=False, indent=2)
    total = sum(len(o['events']) for o in agg)
    print('events: %d -> %s' % (total, os.path.abspath(args.out)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))