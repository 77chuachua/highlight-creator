"""方案3：背景建模 + 人形 blob + 多目标跟踪（逐人速度，最准）。

usage: python experimental/solution3_track.py <filelist.txt>
输出：temp/motion_quant/solution3/<name>.csv / .json / _summary.json
"""
import os
import time

import cv2
import numpy as np

from motion_common import (frame_reader, roi_mask, moving_avg, median,
                           detect_events, write_csv, write_json, run_cli,
                           new_mog2, WIDTH)

AREA_MIN, AREA_MAX = 60, 3000   # person blob px^2 at 480w
MAX_LINK_PX = 25.0
V_MOVE = 15.0                   # px/s "moving" gate
WARMUP_SECS = 1.0
SMOOTH_SECS = 1.5
MIN_STALL_SECS = 2.0
STILL_FRAC_THR = 0.65
MIN_TRACKS = 3


def process(video, od, name, sample_fps=None, width=None):
    from motion_common import SAMPLE_FPS
    t0 = time.perf_counter()
    fps = sample_fps or SAMPLE_FPS
    w = width or WIDTH
    roi = None
    mog2 = new_mog2()
    k_open = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    k_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))

    tracks = {}          # id -> [x, y, speed_ema, last_t, hits]
    next_id = 0
    ts, ntr, means, stills = [], [], [], []
    still_centroids = []  # per-frame list of (x, y) of slow tracks

    for t, gray in frame_reader(video, width=w, sample_fps=fps):
        if roi is None:
            roi = roi_mask(*gray.shape)
        fg = mog2.apply(gray, learningRate=0.01)
        fg = cv2.bitwise_and(fg, fg, mask=roi)
        fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, k_open)
        fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, k_close)
        n, _, stats, cents = cv2.connectedComponentsWithStats(fg, 8)

        cands = [(float(c[0]), float(c[1])) for i, c in enumerate(cents)
                 if i > 0 and AREA_MIN <= stats[i, cv2.CC_STAT_AREA] <= AREA_MAX]

        # greedy nearest-neighbor assignment
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
                dt = max(1e-3, t - tr[3])
                sp = bd / dt
                tr[2] = 0.7 * tr[2] + 0.3 * sp
                tr[0], tr[1], tr[3], tr[4] = cx, cy, t, tr[4] + 1
                used.add(best)
            else:
                tracks[next_id] = [cx, cy, 0.0, t, 1]
                next_id += 1
        tracks = {tid: tr for tid, tr in tracks.items() if t - tr[3] <= 1.0}

        if t < WARMUP_SECS:
            continue
        valid = [tr for tr in tracks.values() if tr[4] >= 3]
        slow = [(tr[0], tr[1]) for tr in valid if tr[2] < V_MOVE]
        ts.append(t)
        ntr.append(len(valid))
        means.append(float(np.mean([tr[2] for tr in valid])) if valid else 0.0)
        stills.append(len(slow) / len(valid) if valid else 0.0)
        still_centroids.append(slow)

    sm = moving_avg(means, max(1, int(SMOOTH_SECS * fps)))
    thr = max(1.0, 0.35 * median(means))
    events = detect_events(ts, sm, thr, MIN_STALL_SECS, 'below')

    still_masked = [s if n >= MIN_TRACKS else 0.0
                    for s, n in zip(stills, ntr)]
    ssm = moving_avg(still_masked, max(1, int(SMOOTH_SECS * fps)))
    still_events = detect_events(ts, ssm, STILL_FRAC_THR, MIN_STALL_SECS,
                                 'above')
    for ev in still_events:  # localize the stall cluster
        loc = [c for c, tt in zip(still_centroids, ts)
               if ev['start'] <= tt <= ev['end'] for c in c]
        if loc:
            p = np.mean(loc, axis=0)
            ev['cluster_xy'] = [round(float(p[0]), 1), round(float(p[1]), 1)]

    runtime = round(time.perf_counter() - t0, 2)
    write_csv(os.path.join(od, f'{name}.csv'),
              ['t', 'n_tracks', 'mean_speed_px_s', 'still_ratio'],
              [[round(t, 2), n, round(m, 2), round(s, 3)]
               for t, n, m, s in zip(ts, ntr, means, stills)],
              meta={'runtime_secs': runtime})
    write_json(os.path.join(od, f'{name}.json'), {
        'video': name, 'solution': 3, 'runtime_secs': runtime,
        'mean_speed': round(float(np.mean(means)), 2),
        'stall_threshold_px_s': round(thr, 2),
        'stall_events': events,
        'still_events': still_events,
    })
    print(f'  tracks mean_speed={np.mean(means):.1f}px/s '
          f'stalls={len(events)} still_events={len(still_events)} '
          f'runtime={runtime}s')
    return {'video': name, 'runtime_secs': runtime,
            'mean_speed': round(float(np.mean(means)), 2),
            'stall_events': events, 'still_events': still_events}


if __name__ == '__main__':
    run_cli('solution3', process)
