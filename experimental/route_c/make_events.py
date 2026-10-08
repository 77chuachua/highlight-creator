# -*- coding: utf-8 -*-
"""plan_C make_events: hlcproj -> events.json GT.

Reads a highlight-creator .hlcproj project, turns its manually-cut
timeslots into labeled event windows.  class mapping (user decision):
  goal  <- description contains `进球` | `进门` | `助攻`
  save  <- description contains `扑出` | `没收`

usage:
  python experimental/route_c/make_events.py <project.hlcproj> [--out events.json] [--t-align center|end|SECONDS]
  python experimental/route_c/make_events.py --smoke
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

GOAL_KW = ('进球', '进门', '助攻')
SAVE_KW = ('扑出', '没收')


def classify(desc):
    if any(k in desc for k in SAVE_KW):
        return 'save'
    if any(k in desc for k in GOAL_KW):
        return 'goal'
    return None


def parse_hlcproj(path, t_align='center'):
    d = json.load(open(path, encoding='utf-8'))
    src = {s['id']: os.path.basename(s['filePath']) for s in d['sources']}
    videos = {}
    for ts in d['timeslots']:
        cls = classify(ts.get('description', ''))
        if not cls:
            continue
        w0 = ts['inPointMs'] / 1000.0
        w1 = ts['outPointMs'] / 1000.0
        w0, w1 = min(w0, w1), max(w0, w1)
        if t_align == 'center':
            tsec = (w0 + w1) / 2
        elif t_align == 'end':
            tsec = w1
        else:
            tsec = float(t_align)
        videos.setdefault(src[ts['videoSourceId']], []).append({
            'class': cls, 't_sec': round(tsec, 2),
            'window': [round(w0, 2), round(w1, 2)],
        })
    out = []
    for vid, evs in sorted(videos.items()):
        evs.sort(key=lambda e: e['window'][0])
        out.append({'video': vid, 'events': evs})
    return out


def write_events(events, out):
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(events, f, ensure_ascii=False, indent=2)


def count_classes(events):
    from collections import Counter
    c = Counter()
    for v in events:
        for e in v['events']:
            c[e['class']] += 1
    return dict(c)


def smoke():
    fake = {
        'name': 'smoke',
        'sources': [
            {'id': 'S1', 'filePath': 'C:\\x\\a.mp4', 'durationMs': 10000,
             'width': 100, 'height': 100, 'codecName': 'h264', 'fps': 30.0},
        ],
        'templateSelections': {},
        'timeslots': [
            {'id': 't1', 'videoSourceId': 'S1', 'inPointMs': 5000,
             'outPointMs': 15000, 'description': '阿瑞进球', 'label': '',
             'colorIndex': 0, 'rating': 0, 'filename': 'a.mp4',
             'elapse': 10000, 'remote': False},
            {'id': 't2', 'videoSourceId': 'S1', 'inPointMs': 30000,
             'outPointMs': 40000, 'description': '阿可扑出皮球', 'label': '',
             'colorIndex': 0, 'rating': 0, 'filename': 'a.mp4',
             'elapse': 10000, 'remote': False},
            {'id': 't3', 'videoSourceId': 'S1', 'inPointMs': 60000,
             'outPointMs': 70000, 'description': '顺子助攻Winter',
             'label': '', 'colorIndex': 0, 'rating': 0, 'filename': 'a.mp4',
             'elapse': 10000, 'remote': False},
            {'id': 't4', 'videoSourceId': 'S1', 'inPointMs': 80000,
             'outPointMs': 90000, 'description': '普通镜头', 'label': '',
             'colorIndex': 0, 'rating': 0, 'filename': 'a.mp4',
             'elapse': 10000, 'remote': False},
        ],
    }
    path = os.path.join(os.environ.get('TEMP', '.'), 'smoke.hlcproj')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(fake, f)
    evs = parse_hlcproj(path)
    cnt = count_classes(evs)
    assert cnt == {'goal': 2, 'save': 1}, cnt  # 进球 + 助攻 both -> goal
    assert len(evs) == 1 and evs[0]['video'] == 'a.mp4'
    e0 = evs[0]['events']
    assert e0[0]['class'] == 'goal' and e0[0]['t_sec'] == 10.0, e0[0]
    assert e0[0]['window'] == [5.0, 15.0], e0[0]
    assert e0[1]['class'] == 'save' and e0[1]['t_sec'] == 35.0, e0[1]
    assert e0[2]['class'] == 'goal' and e0[2]['t_sec'] == 65.0, e0[2]
    assert len(e0) == 3, len(e0)  # 普通镜头 skipped
    print('make_events selftest OK (%s)' % cnt)


def main(argv):
    ap = argparse.ArgumentParser(description='hlcproj -> events.json')
    ap.add_argument('project', nargs='?', default=None)
    ap.add_argument('--out', default=None)
    ap.add_argument('--t-align', default='center',
                    help='event point: center|end|SECONDS')
    ap.add_argument('--smoke', action='store_true')
    args = ap.parse_args(argv)
    if args.project is None or args.smoke:
        smoke()
        return 0
    evs = parse_hlcproj(args.project, args.t_align)
    out = args.out
    if not out:
        out = os.path.join('temp', 'models', 'plan_C', 'gt', 'events.json')
    write_events(evs, out)
    print('classes: %s' % count_classes(evs))
    print('events written: %s' % os.path.abspath(out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))