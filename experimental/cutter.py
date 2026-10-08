"""cutter：运动停滞自动剪辑工具（tkinter UI + 命令行，纯本地）。

选 solution(1/2/3) → 配置各变量阈值与激活状态 → 选视频 → 执行：
对视频跑对应 solution 分析，按激活变量找出越过阈值的时间点，
截取 [时间点-10s, 时间点] 的 720P 片段（不足 10s 则从视频头截到时间点），
输出到 temp/cutter/，并在界面列表显示 视频名/开始时间/时长/结果路径。

dry run：只做分析、不做剪辑，把待剪片段写成 hlcproj 文件
（格式同 app 的保存功能，缺失字段用类型默认值填充）。

命令行模式（无 UI）：
  --config <file.json>   按 JSON 配置执行（覆盖 solution/视频/变量阈值/mode）
                         min_elapse / max_elapse = 静止段时长过滤范围（秒），
                         只保留时长在此范围内的停滞段（缺省 5 / 15 秒）。
  --gen-example          在脚本同目录生成示例配置 cutter.example.json

usage: python experimental/cutter.py                # 打开 UI
       python experimental/cutter.py --selftest     # 逻辑自检
       python experimental/cutter.py --smoke        # UI 冒烟
       python experimental/cutter.py --gen-example  # 生成示例配置
       python experimental/cutter.py --config <file.json>  # 按配置执行
"""
import csv
import json
import os
import subprocess
import sys
import threading
import tkinter as tk
import uuid
from tkinter import ttk, filedialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import motion_common as mc
import solution1_framediff as s1
import solution2_optflow as s2
import solution3_track as s3

SOLUTIONS = {1: s1, 2: s2, 3: s3}

# (变量名, 越界方向, 默认阈值)；≤ 表示低于阈值视为停滞，≥ 表示高于阈值视为停滞
VARS = {
    1: [('activity', '<=', 0.001), ('activity_smooth', '<=', 0.001)],
    2: [('n_moving', '<=', 2.0), ('frac_moving', '<=', 0.2),
        ('p90_speed_px_s', '<=', 15.0)],
    3: [('mean_speed_px_s', '<=', 10.0), ('still_ratio', '>=', 0.65),
        ('n_tracks', '<=', 3.0)],
}

# 静止画面时长过滤（秒）：只保留时长为 [MIN_ELAPSE, MAX_ELAPSE] 的停滞段。
# 短于 MIN_ELAPSE 的静止被过滤（原 threshold 的角色），长于 MAX_ELAPSE 的
# 也被过滤（长时间停机/画面中断不算单次停滞）。可经配置 min_elapse/max_elapse
# 或 UI 里的 elapse 范围覆盖。
MIN_ELAPSE_SECS = 5.0
MAX_ELAPSE_SECS = 15.0
MERGE_SECS = 2.0    # 多变量时间点间隔 <=2s 视为同一次停滞
CLIP_SECS = 10.0
DRY_SAMPLE_FPS = 3.0
DRY_WIDTH = 240


def read_series(csv_path):
    series = []
    with open(csv_path, newline='', encoding='utf-8') as f:
        r = csv.DictReader(f)
        for row in r:
            if row['t'].startswith('#'):
                continue
            t = float(row['t'])
            series.append((t, {k: float(v) for k, v in row.items()
                               if k != 't'}))
    return series


def _runs(tv, thr, direction, min_dwell=MIN_ELAPSE_SECS,
          max_dwell=MAX_ELAPSE_SECS):
    """返回越界段（停滞）的起始时间点；只保留时长在 [min_dwell, max_dwell] 内的段。"""
    starts, st, last = [], None, None
    for t, v in tv:
        hit = (v <= thr) if direction == '<=' else (v >= thr)
        if hit:
            if st is None:
                st = t
            last = t
        else:
            if st is not None and min_dwell <= last - st <= max_dwell:
                starts.append(st)
            st = None
    if st is not None and min_dwell <= last - st <= max_dwell:
        starts.append(st)
    return starts


def find_timepoints(series, active, min_dwell=MIN_ELAPSE_SECS,
                    max_dwell=MAX_ELAPSE_SECS):
    tps = []
    for col, direction, thr in active:
        tps += _runs([(t, vals[col]) for t, vals in series
                      if col in vals], thr, direction, min_dwell, max_dwell)
    tps.sort()
    out = []
    for t in tps:
        if not out or t - out[-1] > MERGE_SECS:
            out.append(t)
    return out


def clip_windows(tps):
    merged = []
    for tp in tps:
        win = [max(0.0, tp - CLIP_SECS), tp]
        if merged and win[0] <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], win[1])
        else:
            merged.append(win)
    return [(st, en - st) for st, en in merged if en - st > 0.5]


FFMPEG = os.path.join(mc.repo_root(), 'tools', 'ffmpeg', 'ffmpeg.exe')


def cut_clip(ffmpeg, video, start, dur, out):
    vf = ('scale=1280:720:force_original_aspect_ratio=decrease,'
          'pad=1280:720:(ow-iw)/2:(oh-ih)/2')
    subprocess.run([ffmpeg, '-y', '-v', 'error', '-ss', f'{start:.3f}',
                    '-i', video, '-t', f'{dur:.3f}', '-vf', vf,
                    '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23',
                    '-c:a', 'aac', '-ar', '44100', '-b:a', '128k',
                    '-pix_fmt', 'yuv420p', out],
                   check=True, capture_output=True)


def build_hlcproj(name, videos, jobs):
    """把待剪片段 jobs 拼成 app 保存格式的 hlcproj 项目 dict。

    jobs: [{'src': 视频路径, 'start': 秒, 'dur': 秒}, ...]
    cutter 没有的字段用类型默认值填充：字符串 ''、数值 0、bool False、
    可空 None（保证 app 的 loadProjectFromJson 能直接解析）。
    """
    sources, timeslots = [], []
    for v in videos:
        sid = str(uuid.uuid4())
        sources.append({
            'id': sid,
            'filePath': v,
            'durationMs': 0,
            'width': 0,
            'height': 0,
            'codecName': '',
            'fps': 0.0,
        })
        for j in jobs:
            if j['src'] != v:
                continue
            in_ms = int(round(j['start'] * 1000))
            out_ms = int(round((j['start'] + j['dur']) * 1000))
            timeslots.append({
                'id': str(uuid.uuid4()),
                'videoSourceId': sid,
                'inPointMs': in_ms,
                'outPointMs': out_ms,
                'label': '',
                'colorIndex': 0,
                'rating': 0,
                'filename': os.path.basename(v),
                'description': '',
                'elapse': out_ms - in_ms,
                'remote': False,
                'centerX': None,
                'centerY': None,
            })
    return {
        'name': name,
        'sources': sources,
        'templateSelections': {},
        'timeslots': timeslots,
    }


def write_dryrun_hlcproj(sol, videos, jobs):
    """dry run 入口：把分析出的待剪片段写成 temp/cutter/dryrun_sol{N}.hlcproj。"""
    project = build_hlcproj(f'dryrun_sol{sol}', videos, jobs)
    path = os.path.join(mc.repo_root(), 'temp', 'cutter',
                        f'dryrun_sol{sol}.hlcproj')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mc.write_json(path, project)
    return path


def _source_fingerprint(video, sol, sample_fps, width):
    """生成 CSV 缓存 key：源文件 mtime + 分析参数。"""
    return (os.path.getmtime(video), sol, sample_fps, width)


def analyze(sol, videos, active, log=print, dry=False,
            min_elapse=MIN_ELAPSE_SECS, max_elapse=MAX_ELAPSE_SECS):
    """对每个视频跑 solution 分析，按激活变量找停滞时间点并生成待剪片段 jobs。

    dry=True 时用低采样率+小分辨率加速；若已有匹配 fingerprint 的缓存 CSV 则跳过分析。
    只保留时长为 [min_elapse, max_elapse] 的停滞段。
    jobs: [{'src', 'video', 'start', 'dur', 'path'}, ...]
    """
    out_dir = os.path.join(mc.repo_root(), 'temp', 'cutter')
    os.makedirs(out_dir, exist_ok=True)
    fps = DRY_SAMPLE_FPS if dry else None
    w = DRY_WIDTH if dry else None
    jobs = []
    for video in videos:
        name = os.path.splitext(os.path.basename(video))[0]
        od = mc.out_dir('motion_quant', f'solution{sol}')
        csv_path = os.path.join(od, f'{name}.csv')

        fp = _source_fingerprint(video, sol, fps or mc.SAMPLE_FPS,
                                 w or mc.WIDTH)
        csv_fp = None
        if os.path.exists(csv_path):
            try:
                with open(csv_path, 'r', encoding='utf-8') as f:
                    for line in f:
                        if line.startswith('#fingerprint,'):
                            csv_fp = line.strip().split(',', 1)[1]
                            break
            except Exception:
                pass
        fp_str = f'{fp[0]}_{fp[1]}_{fp[2]}_{fp[3]}'

        if dry and csv_fp == fp_str:
            log(f'分析 {name} (solution {sol}) ... 缓存命中')
        else:
            log(f'分析 {name} (solution {sol}) ...')
            SOLUTIONS[sol].process(video, od, name,
                                   sample_fps=fps, width=w)
            with open(csv_path, 'a', encoding='utf-8') as f:
                f.write(f'#fingerprint,{fp_str}\n')

        series = read_series(csv_path)
        tps = find_timepoints(series, active, min_dwell=min_elapse,
                              max_dwell=max_elapse)
        log(f'{name}: {len(tps)} 个停滞时间点')
        for start, dur in clip_windows(tps):
            jobs.append({
                'src': video, 'video': name, 'start': start,
                'dur': dur,
                'path': os.path.join(out_dir, f'{name}_sol{sol}'
                                     f'_{start:.1f}s_{dur:.1f}s.mp4'),
            })
    return jobs


def active_vars_from_config(sol, vars_cfg):
    """从配置 vars 生成 (名称, 方向, 阈值) 激活列表；缺失项用默认值。"""
    active = []
    for name, direction, dflt in VARS[sol]:
        vc = vars_cfg.get(name, {})
        if not vc.get('enabled', True):
            continue
        try:
            thr = float(vc.get('threshold', dflt))
        except (TypeError, ValueError):
            thr = float(dflt)
        active.append((name, direction, thr))
    return active


def run_from_config(config, base=None):
    """按 JSON 配置执行（无 UI）。配置相对路径以配置所在目录为基准。"""
    sol = int(config.get('solution', 1))
    if sol not in VARS:
        print(f'未知 solution: {sol}', file=sys.stderr)
        return 1
    mode = config.get('mode', 'dry_run')
    videos = []
    for v in config.get('videos', []):
        videos.append(v if os.path.isabs(v) or not base
                      else os.path.join(base, v))
    if not videos:
        print('配置里没有 videos', file=sys.stderr)
        return 1
    missing = [v for v in videos if not os.path.exists(v)]
    if missing:
        print(f'视频不存在: {missing[0]}', file=sys.stderr)
        return 1
    active = active_vars_from_config(sol, config.get('vars', {}))
    if not active:
        print('没有激活的变量', file=sys.stderr)
        return 1
    # min_elapse / max_elapse：静止段时长过滤范围（秒），短于此或长于此的
    # 停滞片段都被过滤。缺省 5 / 15。
    def _flt(v, dflt):
        try:
            return float(v)
        except (TypeError, ValueError):
            return float(dflt)
    min_elapse = _flt(config.get('min_elapse'), MIN_ELAPSE_SECS)
    max_elapse = _flt(config.get('max_elapse'), MAX_ELAPSE_SECS)
    if min_elapse < 0 or max_elapse < min_elapse:
        min_elapse, max_elapse = MIN_ELAPSE_SECS, MAX_ELAPSE_SECS
    jobs = analyze(sol, videos, active, dry=(mode == 'dry_run'),
                   min_elapse=min_elapse, max_elapse=max_elapse)
    if not jobs:
        print('未找到符合条件的片段')
        return 0
    if mode == 'dry_run':
        path = write_dryrun_hlcproj(sol, videos, jobs)
        print(f'dry run 完成: {path} ({len(jobs)} 个片段)')
    elif mode == 'cut':
        if not os.path.exists(FFMPEG):
            print(f'ffmpeg 不存在: {FFMPEG}', file=sys.stderr)
            return 1
        for j in jobs:
            print(f'剪辑 {j["video"]} {j["start"]:.2f}s-'
                  f'{j["start"] + j["dur"]:.2f}s ...')
            cut_clip(FFMPEG, j['src'], j['start'], j['dur'], j['path'])
            print(f'  完成: {j["path"]}')
    else:
        print(f'未知 mode: {mode}（可选 cut / dry_run）', file=sys.stderr)
        return 1
    return 0


def gen_example_config():
    """在脚本同目录生成示例配置 cutter.example.json。"""
    sol = 1
    example = {
        'solution': sol,
        'mode': 'dry_run',
        'min_elapse': MIN_ELAPSE_SECS,
        'max_elapse': MAX_ELAPSE_SECS,
        'videos': [os.path.join(mc.repo_root(), 'test', 'e2e',
                                'videoSource', 'test1.mp4')],
        'vars': {name: {'enabled': True, 'threshold': dflt}
                 for name, _, dflt in VARS[sol]},
    }
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'cutter.example.json')
    mc.write_json(path, example)
    print(f'示例配置已生成: {path}')
    return path


class CutterApp:
    def __init__(self, root):
        self.root = root
        root.title('cutter - 运动停滞自动剪辑')
        self.videos = []
        self.var_rows = []

        top = ttk.Frame(root, padding=8)
        top.pack(fill='x')
        ttk.Label(top, text='Solution:').pack(side='left')
        self.sol_var = tk.IntVar(value=1)
        for i in (1, 2, 3):
            ttk.Radiobutton(top, text=f'方案 {i}', variable=self.sol_var,
                            value=i, command=self._rebuild_vars).pack(
                side='left', padx=6)
        self.status = ttk.Label(top, text='就绪')
        self.status.pack(side='right')

        self.vars_frame = ttk.LabelFrame(root, text='变量阈值（勾选=激活）',
                                         padding=8)
        self.vars_frame.pack(fill='x', padx=8)
        self._rebuild_vars()

        elapse = ttk.LabelFrame(root, text='elapse 范围（秒）', padding=8)
        elapse.pack(fill='x', padx=8)
        ttk.Label(elapse, text='min:').pack(side='left')
        self.min_elapse_var = tk.StringVar(value=str(MIN_ELAPSE_SECS))
        ttk.Entry(elapse, textvariable=self.min_elapse_var,
                  width=6).pack(side='left', padx=4)
        ttk.Label(elapse, text='max:').pack(side='left')
        self.max_elapse_var = tk.StringVar(value=str(MAX_ELAPSE_SECS))
        ttk.Entry(elapse, textvariable=self.max_elapse_var,
                  width=6).pack(side='left', padx=4)
        ttk.Label(elapse, text='只保留时长在此范围内的静止段').pack(
            side='left', padx=8)

        mid = ttk.Frame(root, padding=8)
        mid.pack(fill='x')
        ttk.Button(mid, text='选择视频文件...',
                   command=self._pick_videos).pack(side='left')
        self.vlist = tk.Listbox(mid, height=4)
        self.vlist.pack(side='left', fill='x', expand=True, padx=8)
        self.run_btn = ttk.Button(mid, text='执行', command=self._run)
        self.run_btn.pack(side='left')
        self.dry_btn = ttk.Button(mid, text='dry run', command=self._dry_run)
        self.dry_btn.pack(side='left', padx=6)

        cols = ('video', 'start', 'dur', 'path')
        self.tree = ttk.Treeview(root, columns=cols, show='headings',
                                 height=10)
        for c, w, t in (('video', 120, '视频名称'), ('start', 80, '开始时间'),
                        ('dur', 80, '时长'), ('path', 420, '截取结果路径')):
            self.tree.heading(c, text=t)
            self.tree.column(c, width=w)
        self.tree.pack(fill='both', expand=True, padx=8, pady=8)

    def _rebuild_vars(self):
        for w in self.vars_frame.winfo_children():
            w.destroy()
        self.var_rows = []
        for i, (name, direction, dflt) in enumerate(VARS[self.sol_var.get()]):
            act = tk.BooleanVar(value=True)
            ttk.Checkbutton(self.vars_frame, variable=act).grid(
                row=i, column=0, sticky='w')
            ttk.Label(self.vars_frame,
                      text=f'{name}  {direction} 阈值').grid(
                row=i, column=1, sticky='w', padx=4)
            ent = tk.Entry(self.vars_frame, width=10)
            ent.insert(0, str(dflt))
            ent.grid(row=i, column=2, sticky='w')
            self.var_rows.append((name, direction, act, ent))

    def _pick_videos(self):
        ps = filedialog.askopenfilenames(
            filetypes=[('video', '*.mp4 *.mov *.mkv *.avi'), ('all', '*.*')])
        for p in ps:
            if p not in self.videos:
                self.videos.append(p)
                self.vlist.insert('end', os.path.basename(p))

    def _active_vars(self):
        act = []
        for name, direction, on, ent in self.var_rows:
            if not on.get():
                continue
            try:
                act.append((name, direction, float(ent.get())))
            except ValueError:
                self._log(f'忽略无效阈值: {name}')
        return act

    def _log(self, msg):
        self.root.after(0, self.status.configure, {'text': msg})

    def _run(self):
        if not self.videos:
            self._log('请先选择视频文件')
            return
        active = self._active_vars()
        if not active:
            self._log('请至少激活一个变量')
            return
        if not os.path.exists(FFMPEG):
            self._log(f'ffmpeg 不存在: {FFMPEG}')
            return
        sol = self.sol_var.get()
        lo, hi = self._elapse_range()
        self._set_buttons('disabled')
        self.tree.delete(*self.tree.get_children())
        threading.Thread(target=self._worker, args=(sol, active, lo, hi),
                         daemon=True).start()

    def _dry_run(self):
        if not self.videos:
            self._log('请先选择视频文件')
            return
        active = self._active_vars()
        if not active:
            self._log('请至少激活一个变量')
            return
        sol = self.sol_var.get()
        lo, hi = self._elapse_range()
        self._set_buttons('disabled')
        threading.Thread(target=self._dry_worker, args=(sol, active, lo, hi),
                         daemon=True).start()

    def _set_buttons(self, state):
        self.run_btn.configure(state=state)
        self.dry_btn.configure(state=state)

    def _elapse_range(self):
        """读取 UI 的 elapse 范围；非法/倒置时回退默认 [5, 15]。"""
        def _f(var, dflt):
            try:
                return float(var.get())
            except (TypeError, ValueError):
                return float(dflt)
        lo = _f(self.min_elapse_var, MIN_ELAPSE_SECS)
        hi = _f(self.max_elapse_var, MAX_ELAPSE_SECS)
        if lo < 0 or hi < lo:
            return MIN_ELAPSE_SECS, MAX_ELAPSE_SECS
        return lo, hi

    def _collect_jobs(self, sol, active, lo, hi, dry=False):
        """分析阶段：对每个视频跑 solution，按激活变量找停滞时间点并生成片段。"""
        return analyze(sol, self.videos, active, log=self._log, dry=dry,
                       min_elapse=lo, max_elapse=hi)

    def _worker(self, sol, active, lo, hi):
        jobs = self._collect_jobs(sol, active, lo, hi)
        self.root.after(0, self._begin_cut, jobs)

    def _dry_worker(self, sol, active, lo, hi):
        try:
            jobs = self._collect_jobs(sol, active, lo, hi, dry=True)
            path = write_dryrun_hlcproj(sol, self.videos, jobs)
            self.root.after(0, self._log,
                            f'dry run 完成: {path} ({len(jobs)} 个片段)')
        except Exception as e:
            self.root.after(0, self._log, f'dry run 失败: {e}')
        self.root.after(0, self._set_buttons, 'normal')

    def _begin_cut(self, jobs):
        if not jobs:
            self._log('未找到符合条件的片段')
            self._set_buttons('normal')
            return
        for j in jobs:
            j['item'] = self.tree.insert(
                '', 'end', values=(j['video'], f"{j['start']:.2f}s",
                                   f"{j['dur']:.2f}s", '待剪辑'))
        dlg = tk.Toplevel(self.root)
        dlg.title('剪辑进度')
        dlg.transient(self.root)
        dlg.resizable(False, False)
        dlg.protocol('WM_DELETE_WINDOW', lambda: None)
        tk.Label(dlg, text=f'共 {len(jobs)} 个片段').pack(
            padx=20, pady=(14, 4))
        self._pb = ttk.Progressbar(dlg, length=360, maximum=len(jobs))
        self._pb.pack(padx=20)
        self._pb_label = tk.Label(dlg, text=f'0 / {len(jobs)}')
        self._pb_label.pack(pady=(4, 14))
        dlg.grab_set()
        self._dlg = dlg
        threading.Thread(target=self._cut_worker, args=(jobs,),
                         daemon=True).start()

    def _cut_worker(self, jobs):
        done = 0
        for j in jobs:
            ok = True
            try:
                cut_clip(FFMPEG, j['src'], j['start'], j['dur'], j['path'])
            except subprocess.CalledProcessError:
                ok = False
            done += 1
            self.root.after(0, self._cut_progress, j, done, len(jobs), ok)
        self.root.after(0, self._cut_done)

    def _cut_progress(self, j, done, total, ok):
        self._pb['value'] = done
        self._pb_label.configure(text=f'{done} / {total}')
        self.tree.item(j['item'],
                       values=(j['video'], f"{j['start']:.2f}s",
                               f"{j['dur']:.2f}s",
                               j['path'] if ok else '剪辑失败'))

    def _cut_done(self):
        self._dlg.destroy()
        self._set_buttons('normal')
        self._log('完成')


def selftest():
    series = [(float(i), {'a': v})
              for i, v in enumerate([1, 1, 0, 0, 0, 1, 1, 0, 1, 1])]
    # 默认范围 [5, 15]：最长静止段 0,0,0 仅 2s，全部被过滤
    assert find_timepoints(series, [('a', '<=', 0.5)]) == []
    # 显式放宽 min 保留原有逻辑
    assert find_timepoints(series, [('a', '<=', 0.5)],
                           min_dwell=1.0) == [2.0], \
        find_timepoints(series, [('a', '<=', 0.5)], min_dwell=1.0)
    assert find_timepoints(series, [('a', '>=', 0.5)],
                           min_dwell=1.0) == [0.0, 5.0, 8.0]
    # 5s 阈值：连续 5 个 0（时长 4s）在 [5, 15] 内视为一次停滞
    long = [(float(i), {'a': 0.0}) for i in range(10)]
    assert find_timepoints(long, [('a', '<=', 0.5)]) == [0.0], \
        find_timepoints(long, [('a', '<=', 0.5)])
    # max_elapse=15 过滤超长静止段：连续 20 个 0（时长 19s）被过滤
    long20 = [(float(i), {'a': 0.0}) for i in range(20)]
    assert find_timepoints(long20, [('a', '<=', 0.5)]) == [], \
        find_timepoints(long20, [('a', '<=', 0.5)])
    # 放宽 max 后可见
    assert find_timepoints(long20, [('a', '<=', 0.5)],
                           min_dwell=5.0, max_dwell=20.0) == [0.0], \
        find_timepoints(long20, [('a', '<=', 0.5)],
                        min_dwell=5.0, max_dwell=20.0)
    wins = clip_windows([2.0, 15.0, 16.0])
    assert wins[0] == (0.0, 2.0), wins
    assert wins[1][0] == 5.0 and abs(wins[1][1] - 11.0) < 1e-6, wins

    proj = build_hlcproj('t', ['a.mp4', 'b.mp4'],
                         [{'src': 'a.mp4', 'start': 1.5, 'dur': 10.0},
                          {'src': 'b.mp4', 'start': 0.0, 'dur': 8.0}])
    assert proj['name'] == 't' and proj['templateSelections'] == {}
    assert [s['filePath'] for s in proj['sources']] == ['a.mp4', 'b.mp4']
    assert [s['codecName'] for s in proj['sources']] == ['', '']
    ts = proj['timeslots']
    assert len(ts) == 2
    assert ts[0]['inPointMs'] == 1500 and ts[0]['outPointMs'] == 11500
    assert ts[0]['elapse'] == 10000 and ts[0]['filename'] == 'a.mp4'
    assert ts[1]['inPointMs'] == 0 and ts[1]['elapse'] == 8000
    assert ts[0]['videoSourceId'] == proj['sources'][0]['id']
    assert ts[1]['videoSourceId'] == proj['sources'][1]['id']
    assert set(ts[0]) == {'id', 'videoSourceId', 'inPointMs', 'outPointMs',
                          'label', 'colorIndex', 'rating', 'filename',
                          'description', 'elapse', 'remote', 'centerX',
                          'centerY'}
    assert ts[0]['label'] == '' and ts[0]['description'] == ''
    assert ts[0]['colorIndex'] == 0 and ts[0]['rating'] == 0
    assert ts[0]['remote'] is False and ts[0]['centerX'] is None

    assert active_vars_from_config(1, {}) == [('activity', '<=', 0.001),
                                              ('activity_smooth', '<=', 0.001)]
    assert active_vars_from_config(
        1, {'activity': {'enabled': False},
            'activity_smooth': {'threshold': 0.01}}
    ) == [('activity_smooth', '<=', 0.01)]
    assert active_vars_from_config(2, {'n_moving': {'enabled': False}}) \
        == [('frac_moving', '<=', 0.2), ('p90_speed_px_s', '<=', 15.0)]
    print('cutter selftest OK')


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        selftest()
    elif '--smoke' in sys.argv:
        r = tk.Tk()
        app = CutterApp(r)
        r.after(500, r.destroy)
        r.mainloop()
        print('cutter smoke OK')
    elif '--gen-example' in sys.argv:
        gen_example_config()
    elif '--config' in sys.argv:
        i = sys.argv.index('--config')
        if i + 1 >= len(sys.argv):
            print('usage: python experimental/cutter.py --config <file.json>',
                  file=sys.stderr)
            sys.exit(1)
        cfg_path = sys.argv[i + 1]
        # utf-8-sig: 兼容记事本等编辑器的 BOM
        with open(cfg_path, 'r', encoding='utf-8-sig') as f:
            config = json.load(f)
        base = os.path.dirname(os.path.abspath(cfg_path))
        sys.exit(run_from_config(config, base=base))
    else:
        CutterApp(tk.Tk()).root.mainloop()
