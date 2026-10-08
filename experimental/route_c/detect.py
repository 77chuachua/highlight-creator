# -*- coding: utf-8 -*-
"""plan_C detect: one-command highlight detection -> events.json (and .hlcproj).

Runs predict_video on each input segment and optionally writes a
highlight-creator project (.hlcproj, same format as 090226.hlcproj)
so results drop straight into the app/cutter.

usage:
  python experimental/route_c/detect.py <video1> [video2 ...] [--out events.json] [--hlcproj OUT]
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import features  # noqa: E402
import predict  # noqa: E402
from cutter import build_hlcproj  # noqa: E402

DEFAULT_OUT = os.path.join('temp', 'models', 'plan_C', 'events',
                           'events.json')
DEFAULT_HLC = os.path.join('temp', 'models', 'plan_C', 'out',
                           'highlights.hlcproj')


def main(argv):
    ap = argparse.ArgumentParser(description='plan_C highlight detection')
    ap.add_argument('videos', nargs='*')
    ap.add_argument('--model-dir', default=predict.DEFAULT_MODEL_DIR)
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--hlcproj', default=DEFAULT_HLC, help='write .hlcproj '
                    'sidecar (same format as 090226.hlcproj)')
    ap.add_argument('--root', default=None)
    args = ap.parse_args(argv)

    if not args.videos:
        ap.error('no videos given')
    root = args.root or features.default_root()
    agg = []
    jobs = []
    for v in args.videos:
        if not os.path.exists(v):
            print('missing video: %s' % v, file=sys.stderr)
            continue
        print('[detect] %s' % os.path.basename(v))
        obj = predict.predict_video(v, args.model_dir, root)
        agg.append(obj)
        for e in obj['events']:
            w = e['window']
            jobs.append({'src': v, 'start': w[0],
                         'dur': max(0.0, w[1] - w[0])})

    out = args.out
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(agg, f, ensure_ascii=False, indent=2)
    print('events: %d -> %s' % (sum(len(o['events']) for o in agg),
                                os.path.abspath(out)))

    if jobs:
        proj = build_hlcproj('auto_highlights', args.videos, jobs)
        os.makedirs(os.path.dirname(os.path.abspath(args.hlcproj)),
                    exist_ok=True)
        with open(args.hlcproj, 'w', encoding='utf-8') as f:
            json.dump(proj, f, ensure_ascii=False, indent=2)
        print('hlcproj: %d clips -> %s' % (len(jobs),
                                           os.path.abspath(args.hlcproj)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))