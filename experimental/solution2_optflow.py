"""方案2：稀疏光流（Shi-Tomasi 角点 + KLT 跟踪）速度统计（折中）。

角点从"时域变化掩膜"上取（而非全图），避免附着在围栏/白线等静态纹理上；
指标 = 速度超过走路门限的跟踪点数 n_moving（场上移动点计数）。

usage: python experimental/solution2_optflow.py <filelist.txt>
输出：temp/motion_quant/solution2/<name>.csv / .json / _summary.json
"""
import os
import time

import cv2
import numpy as np

from motion_common import (frame_reader, roi_mask, moving_avg, median,
                           detect_events, write_csv, write_json, run_cli,
                           WIDTH)

MAX_CORNERS = 500
REDETECT_SECS = 0.5
DIFF_THR = 25
V_MOVE = 15.0        # px/s, "moving" gate at 480w (~walking)
SMOOTH_SECS = 1.5
MIN_STALL_SECS = 2.0

LK_PARAMS = dict(winSize=(21, 21), maxLevel=3,
                 criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT,
                           10, 0.03))


def process(video, od, name, sample_fps=None, width=None):
    from motion_common import SAMPLE_FPS
    t0 = time.perf_counter()
    fps = sample_fps or SAMPLE_FPS
    w = width or WIDTH
    roi = prev = None
    pts = None
    last_detect = -1e9
    k9 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    ts, ntrk, nmov, fracs, p90 = [], [], [], [], []

    for t, gray in frame_reader(video, width=w, sample_fps=fps):
        if roi is None:
            roi = roi_mask(*gray.shape)
        change = None
        if prev is not None:
            change = cv2.dilate((cv2.absdiff(gray, prev) > DIFF_THR)
                                .astype(np.uint8), k9)
            change = cv2.bitwise_and(change, change, mask=roi)
        if change is not None and (pts is None or len(pts) < 20
                                   or t - last_detect >= REDETECT_SECS):
            pts = cv2.goodFeaturesToTrack(gray, MAX_CORNERS, 0.01, 4,
                                          mask=change)
            last_detect = t
        elif change is not None and pts is not None and len(pts):
            nxt, st, _ = cv2.calcOpticalFlowPyrLK(prev, gray, pts, None,
                                                  **LK_PARAMS)
            ok = (st.ravel() == 1)
            if ok.any():
                d = (nxt[ok] - pts[ok]).reshape(-1, 2)
                v = np.hypot(d[:, 0], d[:, 1]) * fps
                v = v[v < 300]  # drop leaf/flicker outliers
                mv = int((v > V_MOVE).sum())
                ts.append(t)
                ntrk.append(int(len(v)))
                nmov.append(mv)
                fracs.append(mv / len(v))
                p90.append(float(np.percentile(v, 90)))
            pts = nxt[ok] if ok.any() else None
        prev = gray

    sm = moving_avg(nmov, max(1, int(SMOOTH_SECS * fps)))
    thr = max(1.0, 0.35 * median(nmov))
    events = detect_events(ts, sm, thr, MIN_STALL_SECS, 'below')

    runtime = round(time.perf_counter() - t0, 2)
    write_csv(os.path.join(od, f'{name}.csv'),
              ['t', 'n_tracked', 'n_moving', 'frac_moving', 'p90_speed_px_s'],
              [[round(t, 2), n, m, round(f, 3), round(p, 1)]
               for t, n, m, f, p in zip(ts, ntrk, nmov, fracs, p90)],
              meta={'runtime_secs': runtime})
    write_json(os.path.join(od, f'{name}.json'), {
        'video': name, 'solution': 2, 'runtime_secs': runtime,
        'mean_n_moving': round(float(np.mean(nmov)), 1),
        'stall_threshold': round(thr, 1),
        'stall_events': events,
    })
    print(f'  n_moving mean={np.mean(nmov):.1f} stalls={len(events)} '
          f'runtime={runtime}s')
    return {'video': name, 'runtime_secs': runtime,
            'mean_n_moving': round(float(np.mean(nmov)), 1),
            'stall_events': events}


if __name__ == '__main__':
    run_cli('solution2', process)
