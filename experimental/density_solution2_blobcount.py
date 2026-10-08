"""密度方案2：端区人形 blob 计数（背景减 + 连通域 + 面积估人数，折中）。

usage: python experimental/density_solution2_blobcount.py <filelist.txt>
输出：temp/density_quant/solution2/<name>.csv / .json / _summary.json
"""
import os
import time

import cv2
import numpy as np

from motion_common import (frame_reader, roi_mask, zone_masks, foreground,
                           new_mog2, moving_avg, median, detect_events,
                           write_csv, write_json, run_cli, PERSON_AREA,
                           SAMPLE_FPS)

SMOOTH_SECS = 1.5
MIN_EV_SECS = 2.0


def process(video, od, name):
    t0 = time.perf_counter()
    roi = None
    mog2 = new_mog2()
    ts, cnt_l, cnt_r = [], [], []
    for t, gray in frame_reader(video):
        if roi is None:
            roi = roi_mask(*gray.shape)
            zl, zr = zone_masks(*gray.shape)
        fg = foreground(mog2, gray, roi)
        n, _, stats, cents = cv2.connectedComponentsWithStats(fg, 8)
        counts = [0, 0]
        for i in range(1, n):
            a = stats[i, cv2.CC_STAT_AREA]
            cx, cy = int(cents[i][0]), int(cents[i][1])
            for z, (zm, pa) in enumerate(zip((zl, zr), PERSON_AREA)):
                if zm[cy, cx] == 1 and pa[0] <= a <= pa[1]:
                    counts[z] += max(1, round(a / pa[2]))
                    break
        ts.append(t)
        cnt_l.append(counts[0])
        cnt_r.append(counts[1])

    win = max(1, int(SMOOTH_SECS * SAMPLE_FPS))
    sl, sr = moving_avg(cnt_l, win), moving_avg(cnt_r, win)
    events = {}
    for zone, vals in (('left', sl), ('right', sr)):
        events[zone] = detect_events(ts, vals, max(1.0, 1.5 * median(vals)),
                                     MIN_EV_SECS, 'above')

    runtime = round(time.perf_counter() - t0, 2)
    write_csv(os.path.join(od, f'{name}.csv'),
              ['t', 'count_left', 'count_right'],
              [[round(t, 2), a, b] for t, a, b in zip(ts, cnt_l, cnt_r)],
              meta={'runtime_secs': runtime})
    write_json(os.path.join(od, f'{name}.json'), {
        'video': name, 'solution': 'density2', 'runtime_secs': runtime,
        'mean_count_left': round(float(np.mean(cnt_l)), 2),
        'mean_count_right': round(float(np.mean(cnt_r)), 2),
        'gather_events': events,
    })
    print(f'  count L={np.mean(cnt_l):.2f} R={np.mean(cnt_r):.2f} '
          f'runtime={runtime}s')
    return {'video': name, 'runtime_secs': runtime,
            'mean_count_left': round(float(np.mean(cnt_l)), 2),
            'mean_count_right': round(float(np.mean(cnt_r)), 2),
            'gather_events': events}


if __name__ == '__main__':
    run_cli('solution2', process, group='density_quant')
