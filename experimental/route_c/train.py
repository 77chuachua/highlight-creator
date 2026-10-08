# -*- coding: utf-8 -*-
"""plan_C train: build per-second samples, fit goal/save GBDT, pick thresholds.

Reads feats/*.csv (from features.py, one per segment) + gt/events.json.
Trains two binary HistGradientBoosting classifiers (goal, save) with
sample_weight for class imbalance.  Validation is time-ordered: the last
--val-count segments are held out; threshold is chosen on them with
predict.postproc + eval.event_metrics (event-level F1, recall-first).

usage:
  python experimental/route_c/train.py [--feats DIR] [--events GT.JSON]
      [--model-dir DIR] [--val-count N] [--val-segs a,b] [--pos-weight W]
      [--lr X] [--max-iter N] [--max-leaf-nodes N]
"""
import argparse
import glob
import json
import os
import pickle
import sys

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import features  # noqa: E402
import eval as evl  # noqa: E402
import predict  # noqa: E402

CLASSES = ('goal', 'save')


def load_segments(feats_dir):
    segs = {}
    for path in sorted(glob.glob(os.path.join(feats_dir, '*.csv'))):
        name = os.path.splitext(os.path.basename(path))[0]
        d = features.read_csv_series(path)
        colnames = [c for c in d if c != 't']
        segs[name] = {'ts': d['t'],
                      'X': np.column_stack([d[c] for c in colnames]),
                      'colnames': colnames}
    return segs, sorted(segs)


def mark_windows(ts, events, cls):
    """1 for seconds overlapping any GT window of cls, else 0."""
    y = np.zeros(len(ts), dtype=np.int64)
    for e in events:
        if e['class'] != cls:
            continue
        w0, w1 = e['window']
        y[(ts < w1) & (ts + 1 > w0)] = 1
    return y


def main(argv):
    ap = argparse.ArgumentParser(description='plan_C GBDT training')
    ap.add_argument('--feats', default=os.path.join('temp', 'models',
                                                    'plan_C', 'feats'))
    ap.add_argument('--events', default=os.path.join('temp', 'models',
                                                     'plan_C', 'gt',
                                                     'events.json'))
    ap.add_argument('--model-dir', default=os.path.join('temp', 'models',
                                                        'plan_C', 'models'))
    ap.add_argument('--val-count', type=int, default=3)
    ap.add_argument('--val-segs', default=None, help='comma list override')
    ap.add_argument('--exclude', default='',
                    help='comma list of segment stems to keep OUT of '
                         'training (e.g. held-out test pool)')
    ap.add_argument('--pos-weight', type=float, default=10.0)
    ap.add_argument('--lr', type=float, default=0.1)
    ap.add_argument('--max-iter', type=int, default=300)
    ap.add_argument('--max-leaf-nodes', type=int, default=31)
    args = ap.parse_args(argv)

    segs, order = load_segments(args.feats)
    excl = {s for s in args.exclude.split(',') if s}
    if excl:
        segs = {k: v for k, v in segs.items() if k not in excl}
        order = [s for s in order if s not in excl]
    if not segs:
        print('no feature CSVs under %s -- run features.py first'
              % args.feats, file=sys.stderr)
        return 1
    colnames = next(iter(segs.values()))['colnames']
    assert all(s['colnames'] == colnames for s in segs.values())

    gt = evl.load_flat(args.events)
    by_video = {}
    for e in gt:
        by_video.setdefault(os.path.splitext(e['video'])[0], []).append(e)

    n_val = min(args.val_count, len(order))
    if args.val_segs:
        val_set = [s.strip() for s in args.val_segs.split(',') if s.strip()]
    else:
        val_set = order[-n_val:]
    train_set = [s for s in order if s not in val_set]
    print('train segments: %s' % train_set)
    print('val segments:   %s' % val_set)

    stats = {'train': {}, 'val': {}}
    labels = {}
    for cls in CLASSES:
        labels[cls] = {}
        for name, seg in segs.items():
            labels[cls][name] = mark_windows(seg['ts'], by_video.get(name, []),
                                             cls)

    model_dir = args.model_dir
    os.makedirs(model_dir, exist_ok=True)
    thresholds = {}
    cv_metrics = {}

    for cls in CLASSES:
        X_tr = np.vstack([segs[s]['X'] for s in train_set])
        y_tr = np.concatenate([labels[cls][s] for s in train_set])
        w = np.where(y_tr == 1, args.pos_weight, 1.0)
        n_pos = int(y_tr.sum())
        n_neg = int((y_tr == 0).sum())
        stats['train'][cls] = {'pos': n_pos, 'neg': n_neg}
        print(f'[{cls}] train pos={n_pos} neg={n_neg}')
        if n_pos == 0 or n_neg == 0:
            print('  no positives/negatives in train; skip', file=sys.stderr)
            continue
        clf = HistGradientBoostingClassifier(
            learning_rate=args.lr, max_iter=args.max_iter,
            max_leaf_nodes=args.max_leaf_nodes, random_state=0)
        clf.fit(X_tr, y_tr, sample_weight=w)
        with open(os.path.join(model_dir, f'{cls}.pkl'), 'wb') as f:
            pickle.dump(clf, f)

        if not val_set:
            thresholds[cls] = 0.5
            cv_metrics[cls] = {'note': 'no val segments'}
            continue
        seg_probs = {s: clf.predict_proba(segs[s]['X'])[:, 1]
                     for s in val_set}
        allp = np.concatenate(list(seg_probs.values()))
        grid = sorted(set(
            np.percentile(allp, [50, 60, 70, 80, 85, 90, 95]).tolist()
            + [0.05, 0.1, 0.2, 0.3, 0.5, 0.7]))
        grid = [g for g in grid if g > 0.01]
        best = None
        for thr in grid:
            pred = []
            for s in val_set:
                evs = predict.to_events(segs[s]['ts'], seg_probs[s], thr, cls)
                pred.append({'video': s, 'events': evs})
            flat = [e for obj in pred for e in evl.flatten([obj])]
            gt_val = []
            for s in val_set:
                gt_val += by_video.get(s, [])
            m = evl.event_metrics(flat, gt_val)[cls]
            key = (m['f1'], m['recall'])
            if best is None or key > best[0]:
                best = (key, thr, m)
        _, thr, m = best
        thresholds[cls] = round(float(thr), 4)
        cv_metrics[cls] = m
        print(f'[{cls}] thr={thr:.3f} val F1={m["f1"]:.3f} '
              f'P={m["precision"]:.3f} R={m["recall"]:.3f} '
              f'miss={m["miss_rate"]:.2f} loc={m["loc_median_s"]}')

    with open(os.path.join(model_dir, 'thresholds.json'), 'w',
              encoding='utf-8') as f:
        json.dump(thresholds, f, indent=2)
    with open(os.path.join(model_dir, 'cv_metrics.json'), 'w',
              encoding='utf-8') as f:
        json.dump({'classes': cv_metrics, 'segments': {
            'train': train_set, 'val': val_set}}, f, ensure_ascii=False,
            indent=2)
    with open(os.path.join(model_dir, 'sample_stats.json'), 'w',
              encoding='utf-8') as f:
        json.dump(stats, f, indent=2)
    print('models + thresholds + metrics -> %s' % os.path.abspath(model_dir))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))