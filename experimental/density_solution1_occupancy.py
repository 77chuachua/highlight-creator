"""密度方案1：两端前景占用率（背景差 + 时间占用，最便宜）。

usage: python experimental/density_solution1_occupancy.py <filelist.txt>
输出：temp/density_quant/solution1/<name>.csv / .json / _summary.json
"""
import os
import time

import cv2
import numpy as np

from motion_common import (frame_reader, roi_mask, zone_masks, moving_avg,
                           median, detect_events, write_csv, write_json,
                           run_cli, SAMPLE_FPS)

DIFF_THR = 30
HOLD_SECS = 2.5
SMOOTH_SECS = 1.5
MIN_EV_SECS = 2.0


def process(video, od, name):
    t0 = time.perf_counter()
    bg = None
    ts, occ_l, occ_r = [], [], []
    for t, gray in frame_reader(video):
        if bg is None:
            bg = gray.astype(np.float32)
            roi = roi_mask(*gray.shape)
            zl, zr = zone_masks(*gray.shape)
            nl, nr = int(zl.sum()), int(zr.sum())
            hold = min(255, int(HOLD_SECS * SAMPLE_FPS))
            cnt = np.zeros(gray.shape, np.uint8)
            continue
        d = cv2.absdiff(gray, bg.astype(np.uint8))
        fg = (d > DIFF_THR) & (roi == 1)
        bg += 0.02 * (gray - bg)
        cnt = np.where(fg, hold,
                       np.maximum(cnt.astype(np.int16) - 1, 0)).astype(np.uint8)
        occ = cnt > 0
        ts.append(t)
        occ_l.append(float((occ & (zl == 1)).sum()) / nl)
        occ_r.append(float((occ & (zr == 1)).sum()) / nr)

    win = max(1, int(SMOOTH_SECS * SAMPLE_FPS))
    sl, sr = moving_avg(occ_l, win), moving_avg(occ_r, win)
    events = {}
    for zone, vals in (('left', sl), ('right', sr)):
        events[zone] = detect_events(ts, vals, max(0.02, 1.5 * median(vals)),
                                     MIN_EV_SECS, 'above')

    runtime = round(time.perf_counter() - t0, 2)
    write_csv(os.path.join(od, f'{name}.csv'),
              ['t', 'occ_left', 'occ_right'],
              [[round(t, 2), round(a, 4), round(b, 4)]
               for t, a, b in zip(ts, occ_l, occ_r)],
              meta={'runtime_secs': runtime})
    write_json(os.path.join(od, f'{name}.json'), {
        'video': name, 'solution': 'density1', 'runtime_secs': runtime,
        'mean_occ_left': round(float(np.mean(occ_l)), 4),
        'mean_occ_right': round(float(np.mean(occ_r)), 4),
        'gather_events': events,
    })
    print(f'  occ L={np.mean(occ_l):.3f} R={np.mean(occ_r):.3f} '
          f'runtime={runtime}s')
    return {'video': name, 'runtime_secs': runtime,
            'mean_occ_left': round(float(np.mean(occ_l)), 4),
            'mean_occ_right': round(float(np.mean(occ_r)), 4),
            'gather_events': events}


if __name__ == '__main__':
    run_cli('solution1', process, group='density_quant')
