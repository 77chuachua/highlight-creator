# -*- coding: utf-8 -*-
"""plan_C eval: event-level precision/recall/F1 vs GT events.json.

Hit rule: predicted window IoU >= 0.5 with a GT window (per class, per
video).  Also reports localization error (predicted t - GT t_sec) on hits
and the miss rate.

usage:
  python experimental/route_c/eval.py <pred.json> <gt.json>
  python experimental/route_c/eval.py --smoke
"""
import argparse
import json
import os
import sys


def flatten(data):
    """Normalize list-of-{video, events:[{class,t_sec,window}]} to flat list.

    Video keys are stripped of extension so pred and GT filenames match
    even when one side keeps '.MP4' and the other uses the bare stem.
    """
    flat = []
    for obj in data:
        vid = os.path.splitext(obj['video'])[0]
        for e in obj.get('events', []):
            flat.append({'video': vid, 'class': e['class'],
                         't_sec': e['t_sec'],
                         'window': list(e.get('window', [e['t_sec'] - 3,
                                                         e['t_sec'] + 3]))})
    return flat


def load_flat(path):
    """Load events.json (list of {video, events:...}) to a flat event list."""
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return flatten(data)


def iou(w1, w2):
    s = max(w1[0], w2[0])
    e = min(w1[1], w2[1])
    inter = max(0.0, e - s)
    union = (w1[1] - w1[0]) + (w2[1] - w2[0]) - inter
    return inter / union if union > 0 else 0.0


def event_metrics(pred_flat, gt_flat):
    """Per class: precision/recall/F1 + miss rate + loc error on hits."""
    classes = sorted(set([e['class'] for e in gt_flat]
                         + [e['class'] for e in pred_flat]))
    out = {}
    for cls in classes:
        gt = [e for e in gt_flat if e['class'] == cls]
        pr = [e for e in pred_flat if e['class'] == cls]
        used = [False] * len(pr)
        loc = []
        hits = 0
        for g in gt:
            best = None
            bid = -1
            for i, p in enumerate(pr):
                if used[i]:
                    continue
                if p['video'] != g['video']:
                    continue
                o = iou(p['window'], g['window'])
                if o >= 0.5 and (best is None or o > best):
                    best, bid = o, i
            if bid >= 0:
                used[bid] = True
                hits += 1
                loc.append(abs(pr[bid]['t_sec'] - g['t_sec']))
        tp = hits
        n_pred = len(pr)
        n_gt = len(gt)
        p = tp / n_pred if n_pred else 0.0
        r = tp / n_gt if n_gt else 0.0
        f1 = 2 * p * r / (p + r) if (p + r) > 0 else 0.0
        out[cls] = {
            'n_gt': n_gt, 'n_pred': n_pred, 'tp': tp,
            'precision': round(p, 4), 'recall': round(r, 4),
            'f1': round(f1, 4),
            'miss_rate': round((n_gt - tp) / n_gt, 4) if n_gt else 0.0,
            'loc_median_s': round(float(np_median(loc)), 2) if loc else None,
        }
    return out


def np_median(xs):
    xs = sorted(xs)
    n = len(xs)
    if n == 0:
        return float('nan')
    if n % 2 == 1:
        return xs[n // 2]
    return (xs[n // 2 - 1] + xs[n // 2]) / 2.0


def print_metrics(metrics):
    for cls, m in metrics.items():
        print(f'{cls}  GT={m["n_gt"]:3d} pred={m["n_pred"]:3d} '
              f'P={m["precision"]:.3f} R={m["recall"]:.3f} '
              f'F1={m["f1"]:.3f} miss={m["miss_rate"]:.2f} '
              f'loc(md)={m["loc_median_s"]}')


def smoke():
    gt = [{'video': 'a.mp4',
           'events': [{'class': 'goal', 't_sec': 10, 'window': [7, 13]},
                      {'class': 'goal', 't_sec': 40, 'window': [37, 43]},
                      {'class': 'save', 't_sec': 60, 'window': [57, 63]}]}]
    pred = [{'video': 'a.mp4',
             'events': [{'class': 'goal', 't_sec': 9, 'window': [6, 12]},
                        {'class': 'goal', 't_sec': 42, 'window': [10, 16]},
                        {'class': 'save', 't_sec': 90, 'window': [87, 93]}]}]
    m = event_metrics(flatten(pred), flatten(gt))
    # goal: pred#1 hits GT#1; pred#2 (12-16) vs GT#2 (37-43) IoU=0 -> 1 TP, 1 FP
    gm = m['goal']
    assert gm['n_gt'] == 2 and gm['n_pred'] == 2, gm
    assert gm['tp'] == 1 and gm['precision'] == 0.5, gm
    assert gm['recall'] == 0.5 and abs(gm['f1'] - 0.5) < 1e-9, gm
    assert gm['miss_rate'] == 0.5, gm
    assert gm['loc_median_s'] == 1.0, gm
    # save: pred window (87-93) vs GT (57-63) no overlap -> 0 TP, 1 FP, miss
    sm = m['save']
    assert sm['tp'] == 0, sm
    assert sm['recall'] == 0.0 and sm['miss_rate'] == 1.0, sm
    print('eval selftest OK')


def main(argv):
    ap = argparse.ArgumentParser(description='plan_C event metrics')
    ap.add_argument('pred', nargs='?', default=None)
    ap.add_argument('gt', nargs='?', default=None)
    ap.add_argument('--smoke', action='store_true')
    args = ap.parse_args(argv)
    if args.pred is None or args.smoke:
        smoke()
        return 0
    pred = load_flat(args.pred)
    gt = load_flat(args.gt)
    metrics = event_metrics(pred, gt)
    print_metrics(metrics)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))