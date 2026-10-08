"""方案1：帧差全局活动度指数（最便宜）。

usage: python experimental/solution1_framediff.py <filelist.txt>
输出：temp/motion_quant/solution1/<name>.csv / .json / _summary.json
"""
import os
import time

import cv2
import numpy as np

from motion_common import (frame_reader, roi_mask, moving_avg, median,
                           detect_events, write_csv, write_json, run_cli,
                           WIDTH)

DIFF_THR = 25
SMOOTH_SECS = 1.5
MIN_STALL_SECS = 2.0


def process(video, od, name, sample_fps=None, width=None):
    from motion_common import SAMPLE_FPS
    t0 = time.perf_counter()
    fps = sample_fps or SAMPLE_FPS
    w = width or WIDTH
    roi = None
    prev = None
    ts, acts = [], []
    for t, gray in frame_reader(video, width=w, sample_fps=fps):
        blur = cv2.GaussianBlur(gray, (5, 5), 0)
        if roi is None:
            roi = roi_mask(*blur.shape)
            roi_n = int(roi.sum())
        if prev is not None:
            diff = cv2.absdiff(blur, prev)
            act = float(((diff > DIFF_THR) & (roi == 1)).sum()) / roi_n
            ts.append(t)
            acts.append(act)
        prev = blur

    sm = moving_avg(acts, max(1, int(SMOOTH_SECS * fps)))
    thr = 0.35 * median(acts) or 0.0005
    events = detect_events(ts, sm, thr, MIN_STALL_SECS, 'below')

    runtime = round(time.perf_counter() - t0, 2)
    write_csv(os.path.join(od, f'{name}.csv'),
              ['t', 'activity', 'activity_smooth'],
              [[round(t, 2), round(a, 5), round(s, 5)]
               for t, a, s in zip(ts, acts, sm)],
              meta={'runtime_secs': runtime})
    write_json(os.path.join(od, f'{name}.json'), {
        'video': name, 'solution': 1, 'runtime_secs': runtime,
        'mean_activity': round(float(np.mean(acts)), 5),
        'stall_threshold': round(thr, 5),
        'stall_events': events,
    })
    print(f'  activity mean={np.mean(acts):.4f} stalls={len(events)} '
          f'runtime={runtime}s')
    return {'video': name, 'runtime_secs': runtime,
            'mean_activity': round(float(np.mean(acts)), 5),
            'stall_events': events}


if __name__ == '__main__':
    run_cli('solution1', process)
