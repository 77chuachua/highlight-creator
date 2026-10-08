"""密度方案3：逐人跟踪 + 端区分配（MOT，最准）。

轨迹穿越暂态遮挡/合并，端区人数在聚集时最稳；附赠进出次数与驻留时长。

usage: python experimental/density_solution3_trackcount.py <filelist.txt>
输出：temp/density_quant/solution3/<name>.csv / .json / _summary.json
"""
import os
import time

import cv2
import numpy as np

from motion_common import (frame_reader, roi_mask, zone_masks, foreground,
                           new_mog2, moving_avg, median, detect_events,
                           write_csv, write_json, run_cli, PERSON_AREA,
                           SAMPLE_FPS)

AREA_MIN = min(p[0] for p in PERSON_AREA)
AREA_MAX = max(p[1] for p in PERSON_AREA)
MAX_LINK_PX = 25.0
WARMUP_SECS = 1.0
SMOOTH_SECS = 1.5
MIN_EV_SECS = 2.0


def process(video, od, name):
    t0 = time.perf_counter()
    roi = None
    mog2 = new_mog2()
    tracks = {}
    next_id = 0
    entries = [0, 0]
    dwells = [[], []]
    ts, tr_l, tr_r = [], [], []

    for t, gray in frame_reader(video):
        if roi is None:
            roi = roi_mask(*gray.shape)
            zl, zr = zone_masks(*gray.shape)
        fg = foreground(mog2, gray, roi)
        n, _, stats, cents = cv2.connectedComponentsWithStats(fg, 8)
        cands = [(float(c[0]), float(c[1])) for i, c in enumerate(cents)
                 if i > 0 and AREA_MIN <= stats[i, cv2.CC_STAT_AREA] <= AREA_MAX]

        used = set()
        for cx, cy in cands:
            best, bd = None, MAX_LINK_PX
            for tid, tr in tracks.items():
                if tid in used or t - tr[3] > 1.0:
                    continue
                d = np.hypot(cx - tr[0], cy - tr[1])
                if d < bd:
                    best, bd = tid, d
            if best is not None:
                tr = tracks[best]
                tr[0], tr[1], tr[3], tr[4] = cx, cy, t, tr[4] + 1
                used.add(best)
            else:
                tracks[next_id] = [cx, cy, 0.0, t, 1, None, t]
                next_id += 1
        tracks = {tid: tr for tid, tr in tracks.items() if t - tr[3] <= 1.0}

        if t < WARMUP_SECS:
            continue
        cl = cr = 0
        for tr in (tr for tr in tracks.values() if tr[4] >= 3):
            x, y = int(tr[0]), int(tr[1])
            z = 0 if zl[y, x] == 1 else (1 if zr[y, x] == 1 else None)
            if z != tr[5]:
                if z is not None:
                    entries[z] += 1
                    tr[6] = t
                if tr[5] is not None:
                    dwells[tr[5]].append(t - tr[6])
                tr[5] = z
            if z == 0:
                cl += 1
            elif z == 1:
                cr += 1
        ts.append(t)
        tr_l.append(cl)
        tr_r.append(cr)

    win = max(1, int(SMOOTH_SECS * SAMPLE_FPS))
    sl, sr = moving_avg(tr_l, win), moving_avg(tr_r, win)
    events = {}
    for zone, vals in (('left', sl), ('right', sr)):
        events[zone] = detect_events(ts, vals, max(1.0, 1.5 * median(vals)),
                                     MIN_EV_SECS, 'above')
    mean_dwell = [round(float(np.mean(d)), 2) if d else 0.0 for d in dwells]

    runtime = round(time.perf_counter() - t0, 2)
    write_csv(os.path.join(od, f'{name}.csv'),
              ['t', 'tracks_left', 'tracks_right'],
              [[round(t, 2), a, b] for t, a, b in zip(ts, tr_l, tr_r)],
              meta={'runtime_secs': runtime})
    write_json(os.path.join(od, f'{name}.json'), {
        'video': name, 'solution': 'density3', 'runtime_secs': runtime,
        'entries_left': entries[0], 'entries_right': entries[1],
        'mean_dwell_left': mean_dwell[0], 'mean_dwell_right': mean_dwell[1],
        'gather_events': events,
    })
    print(f'  tracks L={np.mean(tr_l):.2f} R={np.mean(tr_r):.2f} '
          f'entries={entries} runtime={runtime}s')
    return {'video': name, 'runtime_secs': runtime,
            'entries_left': entries[0], 'entries_right': entries[1],
            'gather_events': events}


if __name__ == '__main__':
    run_cli('solution3', process, group='density_quant')
