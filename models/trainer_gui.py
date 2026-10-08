# -*- coding: utf-8 -*-
"""highlight-creator 训练台（渐进式数据训练 GUI）

后台复用 experimental/route_c 的管线，把整个"每周渐进训练"流程收进一个界面：
  新增比赛 → 抽特征 → 设训练池/测试池 → 周末重训 → 复跑测试集
训练结束后按门限（goal F1 ≥ 0.35，可改）自动提醒"下周可以尝试测试池视频"。

运行:  python models/trainer_gui.py
所有中间产物一律在 temp/models/plan_C/ 下（pool.json / history.json / feats / models / gt / events）。
"""
import json
import os
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinter.scrolledtext import ScrolledText

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(_HERE, '..'))
_EXP = os.path.normpath(os.path.join(_HERE, '..', 'experimental'))
_RC = os.path.join(_EXP, 'route_c')
for _p in (_EXP, _RC):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import make_events  # noqa: E402
import features  # noqa: E402
import train as train_mod  # noqa: E402
import predict as predict_mod  # noqa: E402
import eval as evl  # noqa: E402

ROOT = features.default_root()
FEATS_DIR = os.path.join(ROOT, 'feats')
GT_PATH = os.path.join(ROOT, 'gt', 'events.json')
MODEL_DIR = os.path.join(ROOT, 'models')
POOL_PATH = os.path.join(ROOT, 'pool.json')
HISTORY_PATH = os.path.join(ROOT, 'history.json')
TEST_EVENTS = os.path.join(ROOT, 'events', 'test_pool.json')
DEFAULT_GATE = 0.35
TEST_READY_F1 = 0.5  # 测试池 "可用线"

VIDEO_EXT = ('.mp4', '.mov', '.mkv', '.avi', '.ts')
ROLE_LABEL = {'train': '训练池', 'test': '测试池', 'none': '未分配'}


def stem(p):
    return os.path.splitext(os.path.basename(p))[0]


def scan_folder(folder):
    videos = []
    if os.path.isdir(folder):
        for f in sorted(os.listdir(folder)):
            if f.lower().endswith(VIDEO_EXT):
                p = os.path.join(folder, f)
                if os.path.getsize(p) > 0:
                    videos.append(p)
    hlcs = [os.path.join(folder, f) for f in os.listdir(folder)
            if f.lower().endswith('.hlcproj')] if os.path.isdir(folder) else []
    return {
        'folder': os.path.abspath(folder),
        'name': os.path.basename(os.path.abspath(folder)),
        'videos': videos,
        'hlcproj': hlcs[0] if hlcs else None,
        'gt_counts': {'goal': 0, 'save': 0},
    }


def load_json(path, default):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (IOError, ValueError):
        return default


def save_json(path, obj):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def read_cv(model_dir):
    p = os.path.join(model_dir, 'cv_metrics.json')
    if os.path.exists(p):
        return json.load(open(p, encoding='utf-8')).get('classes', {})
    return {}


class TrainerApp:
    def __init__(self, root):
        self.root = root
        self.cfg = {'matches': []}
        self.history = load_json(HISTORY_PATH,
                                 {'weeks': [], 'last_gate_f1': 0.0,
                                  'last_test_f1': 0.0})
        self._busy = False
        self._old_gt_counts = {}
        self._build_styles()
        self._build_ui()
        self.refresh()

    # ----------------------------------------------------------- UI
    def _build_styles(self):
        style = ttk.Style(self.root)
        try:
            style.theme_use('clam')
        except tk.TclError:
            pass
        self.bg = '#eef1f6'
        self.card = '#ffffff'
        self.ink = '#0f172a'
        self.mut = '#64748b'
        self.accent = '#2563eb'
        self.accent_d = '#1e40af'
        self.ok = '#16a34a'
        self.warn = '#b45309'
        style.configure('.', font=('Segoe UI', 10), background=self.bg,
                        foreground=self.ink)
        style.configure('Card.TLabelframe', background=self.card,
                        relief='flat', bordercolor='#d7dde8')
        style.configure('Card.TLabelframe.Label', background=self.card,
                        foreground='#334155',
                        font=('Segoe UI', 11, 'bold'))
        style.configure('TLabel', background=self.bg, foreground=self.ink)
        style.configure('Card.TLabel', background=self.card,
                        foreground=self.ink)
        style.configure('Hint.TLabel', background=self.card,
                        foreground=self.mut)
        style.configure('TButton', padding=(12, 6), relief='flat',
                        background='#ffffff', bordercolor='#cbd5e1')
        style.map('TButton',
                  background=[('active', '#e2e8f0')],
                  bordercolor=[('active', '#94a3b8')])
        style.configure('Accent.TButton', padding=(18, 9), relief='flat',
                        background=self.accent, foreground='#ffffff',
                        font=('Segoe UI', 11, 'bold'))
        style.map('Accent.TButton',
                  background=[('active', self.accent_d),
                              ('disabled', '#94a3b8')],
                  foreground=[('disabled', '#e2e8f0')])
        style.configure('Soft.TButton', padding=(10, 6), relief='flat',
                        background='#f1f5f9', bordercolor='#cbd5e1')
        style.map('Soft.TButton',
                  background=[('active', '#e2e8f0')])
        style.configure('Treeview', background='#ffffff',
                        fieldbackground='#ffffff', rowheight=27,
                        bordercolor='#e2e8f0', relief='flat')
        style.configure('Treeview.Heading', background='#f8fafc',
                        foreground='#334155', font=('Segoe UI', 9, 'bold'),
                        relief='flat', padding=6)
        style.map('Treeview', background=[('selected', '#dbeafe')],
                  foreground=[('selected', '#0f172a')])
        style.configure('Vertical.TScrollbar', background='#cbd5e1',
                        troughcolor=self.card, arrowcolor='#475569')

    def _build_ui(self):
        self.root.title('highlight-creator · 训练台')
        self.root.geometry('1180x780')
        self.root.minsize(1000, 660)

        # header
        head = tk.Frame(self.root, bg='#0f172a', padx=22, pady=14)
        head.pack(fill='x')
        tk.Label(head, text='highlight-creator 训练台',
                 bg='#0f172a', fg='#ffffff',
                 font=('Segoe UI', 16, 'bold')).pack(anchor='w')
        tk.Label(head,
                 text='流程：新增比赛 → 抽特征 → 设为训练池/测试池 → 周末重训 → 复跑测试集',
                 bg='#0f172a', fg='#94a3b8',
                 font=('Segoe UI', 10)).pack(anchor='w', pady=(2, 0))

        body = tk.Frame(self.root, bg=self.bg)
        body.pack(fill='both', expand=True, padx=14, pady=12)
        body.columnconfigure(0, weight=2)
        body.columnconfigure(1, weight=3)
        body.rowconfigure(0, weight=4)
        body.rowconfigure(1, weight=3)

        # -------- 左：比赛数据池
        left = ttk.LabelFrame(body, text='① 比赛数据池', style='Card.TLabelframe',
                              padding=10)
        left.grid(row=0, column=0, sticky='nsew', padx=(0, 6), pady=(0, 6))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(0, weight=1)

        self.tree = ttk.Treeview(
            left, columns=('name', 'role', 'goal', 'save', 'feats'),
            show='headings', selectmode='browse', height=12)
        for c, t, w in (('name', '比赛', 170), ('role', '角色', 64),
                        ('goal', '进球', 56), ('save', '扑救', 56),
                        ('feats', '特征', 60)):
            self.tree.heading(c, text=t)
            self.tree.column(c, width=w, anchor='w' if c == 'name' else 'center')
        sb = ttk.Scrollbar(left, orient='vertical', command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.grid(row=0, column=0, sticky='nsew')
        sb.grid(row=0, column=1, sticky='ns')

        btns = tk.Frame(left, bg=self.card)
        btns.grid(row=1, column=0, columnspan=2, sticky='ew', pady=(10, 0))
        self.add_btn = ttk.Button(btns, text='+ 新增比赛', style='Accent.TButton',
                                  command=self.on_add_match)
        self.add_btn.pack(side='left', padx=(0, 6))
        self.rm_btn = ttk.Button(btns, text='移除', style='Soft.TButton',
                                 command=self.on_remove)
        self.rm_btn.pack(side='left', padx=6)
        ttk.Button(btns, text='→ 设为训练池', style='Soft.TButton',
                   command=lambda: self.on_set_role('train')).pack(side='left', padx=6)
        ttk.Button(btns, text='→ 设为测试池', style='Soft.TButton',
                   command=lambda: self.on_set_role('test')).pack(side='left', padx=6)
        ttk.Button(btns, text='未分配', style='Soft.TButton',
                   command=lambda: self.on_set_role('none')).pack(side='left', padx=6)
        self.feat_btn = ttk.Button(btns, text='抽特征 (所选)',
                                   style='Soft.TButton',
                                   command=self.on_extract_feats)
        self.feat_btn.pack(side='right', padx=(6, 0))

        hint = ttk.Label(left, text='测试池 = 永久 hold-out，只用来最终验证，绝不被重训吃到。',
                         style='Hint.TLabel')
        hint.grid(row=2, column=0, columnspan=2, sticky='w', pady=(8, 0))

        # -------- 右：训练与评估
        right = ttk.LabelFrame(body, text='② 训练与评估', style='Card.TLabelframe',
                               padding=10)
        right.grid(row=0, column=1, sticky='nsew', padx=(6, 0), pady=(0, 6))
        right.columnconfigure(0, weight=1)

        top = tk.Frame(right, bg=self.card)
        top.pack(fill='x')
        self.retrain_btn = ttk.Button(
            top, text='周末重训', style='Accent.TButton',
            command=self.on_retrain)
        self.retrain_btn.pack(side='left')
        self.test_btn = ttk.Button(
            top, text='复跑测试集', style='Accent.TButton',
            command=self.on_test)
        self.test_btn.pack(side='left', padx=(10, 0))
        ttk.Button(top, text='打开结果目录', style='Soft.TButton',
                   command=lambda: os.startfile(ROOT)).pack(side='right')

        gate_row = tk.Frame(right, bg=self.card)
        gate_row.pack(fill='x', pady=(10, 6))
        ttk.Label(gate_row, text='测试池尝试门槛 (goal F1 ≥)',
                  style='Card.TLabel').pack(side='left')
        self.gate = tk.DoubleVar(value=DEFAULT_GATE)
        ttk.Spinbox(gate_row, from_=0.05, to=1.0, increment=0.05,
                    width=6, textvariable=self.gate).pack(side='left', padx=8)
        self.status_label = ttk.Label(gate_row, style='Card.TLabel')
        self.status_label.pack(side='right')

        ttk.Label(right, text='最近训练摘要',
                  style='Hint.TLabel').pack(anchor='w', pady=(4, 2))
        self.summary = tk.Text(right, height=3, bg='#f8fafc', fg='#334155',
                               relief='flat', font=('Consolas', 10),
                               borderwidth=1, highlightthickness=1,
                               highlightbackground='#e2e8f0')
        self.summary.pack(fill='x')
        self.summary.configure(state='disabled')
        self.hint_test = ttk.Label(right, text='', style='Hint.TLabel')
        self.hint_test.pack(anchor='w', pady=(2, 0))

        ttk.Label(right, text='周报（数据池 vs 双指标）',
                  style='Hint.TLabel').pack(anchor='w', pady=(10, 2))
        self.hist_tree = ttk.Treeview(
            right, columns=('date', 'pool', 'goal', 'save', 'loc', 'tgoal',
                            'tsave'), show='headings', height=5)
        for c, t, w in (('date', '日期', 118), ('pool', '训练/测试池', 88),
                        ('goal', 'goalF1', 62), ('save', 'saveF1', 62),
                        ('loc', '定位s', 60), ('tgoal', '测试·goal', 70),
                        ('tsave', '测试·save', 70)):
            self.hist_tree.heading(c, text=t)
            self.hist_tree.column(c, width=w, anchor='center')
        self.hist_tree.pack(fill='x', pady=(0, 4))

        # -------- 日志
        log_card = ttk.LabelFrame(body, text='运行日志', style='Card.TLabelframe',
                                  padding=8)
        log_card.grid(row=1, column=0, columnspan=2, sticky='nsew',
                      padx=(0, 0), pady=(6, 0))
        log_card.columnconfigure(0, weight=1)
        log_card.rowconfigure(0, weight=1)
        self.log = ScrolledText(log_card, height=9, bg='#0f172a', fg='#cbd5e1',
                                relief='flat', font=('Consolas', 9),
                                state='disabled')
        self.log.grid(row=0, column=0, sticky='nsew')

        # footer hint
        foot = tk.Label(self.root, text='所有产物保存在 temp/models/plan_C/（特征/模型/事件/周报）',
                        bg=self.bg, fg=self.mut, font=('Segoe UI', 9))
        foot.pack(fill='x', padx=14, pady=(0, 8))

    # ----------------------------------------------------------- helpers
    def _log(self, text):
        self.root.after(0, self._append_log, text)

    def _append_log(self, text):
        self.log.configure(state='normal')
        self.log.insert('end', '%s  %s\n' % (
            time.strftime('%H:%M:%S'), text))
        self.log.see('end')
        self.log.configure(state='disabled')

    def _set_busy(self, busy):
        self._busy = busy
        state = 'disabled' if busy else 'normal'
        for b in (self.add_btn, self.rm_btn, self.feat_btn,
                  self.retrain_btn, self.test_btn):
            b.configure(state=state)
        # ttk.Treeview has no '-state' configure option; use the ttk state API.
        self.tree.state(['disabled'] if busy else ['!disabled'])

    def _run_thread(self, job, on_done):
        self._set_busy(True)
        stdout_tap = _Tap(self._log)
        old_out, old_err = sys.stdout, sys.stderr

        def wrap():
            sys.stdout, sys.stderr = stdout_tap, stdout_tap
            try:
                result = job()
            except Exception as e:  # noqa: BLE001
                result = ('error', '%s: %s' % (type(e).__name__, e))
            finally:
                sys.stdout, sys.stderr = old_out, old_err
                self.root.after(0, lambda: self._set_busy(False))
                self.root.after(0, lambda: on_done(result))

        threading.Thread(target=wrap, daemon=True).start()

    def _save_cfg(self):
        save_json(POOL_PATH, self.cfg)

    def _save_history(self):
        save_json(HISTORY_PATH, self.history)

    def refresh(self):
        # merge scanned info into cfg matches
        for m in self.cfg['matches']:
            info = scan_folder(m['folder'])
            m['videos'] = info['videos']
            m['hlcproj'] = info['hlcproj']
            m['gt_counts'] = info['gt_counts']
        self._rebuild_gt()
        self._fill_tree()
        self._fill_history()
        self._fill_summary()

    def _feats_state(self, match):
        done = sum(1 for v in match['videos']
                   if os.path.exists(os.path.join(FEATS_DIR, stem(v) + '.csv')))
        total = len(match['videos'])
        return done, total

    def _rebuild_gt(self):
        agg = []
        for m in self.cfg['matches']:
            if not m.get('hlcproj'):
                continue
            try:
                evs = make_events.parse_hlcproj(m['hlcproj'])
                m['gt_counts'] = make_events.count_classes(evs)
                agg.extend(evs)
            except Exception as e:  # noqa: BLE001
                self._log('GT 解析失败 %s: %s' % (m['name'], e))
        make_events.write_events(agg, GT_PATH)
        n = sum(len(v['events']) for v in agg)
        self._log('GT 重建: %d 条事件 -> %s' % (n, GT_PATH))

    def _fill_tree(self):
        for iid in self.tree.get_children():
            self.tree.delete(iid)
        for i, m in enumerate(self.cfg['matches']):
            g = m['gt_counts'].get('goal', 0)
            s = m['gt_counts'].get('save', 0)
            done, total = self._feats_state(m)
            feats = '%d/%d' % (done, total) if total else '—'
            self.tree.insert('', 'end', iid=str(i),
                             values=(m['name'], ROLE_LABEL[m['role']], g, s,
                                     feats))

    def _fill_history(self):
        for iid in self.hist_tree.get_children():
            self.hist_tree.delete(iid)
        for row in reversed(self.history['weeks']):
            self.hist_tree.insert('', 0, values=(
                row.get('date', ''), row.get('pool', ''),
                _fmt(row.get('goal_f1')), _fmt(row.get('save_f1')),
                _fmt(row.get('loc'), 1), _fmt(row.get('test_goal_f1')),
                _fmt(row.get('test_save_f1'))))

    def _fill_summary(self):
        cv = read_cv(MODEL_DIR)
        goal, save = cv.get('goal', {}), cv.get('save', {})
        gf = goal.get('f1', 0.0)
        gate_f = float(self.gate.get())
        lines = []
        if cv:
            lines.append('训练池校验: goal F1=%.3f (P %.2f/R %.2f, 定位 %s) | save F1=%.3f'
                         % (goal.get('f1', 0), goal.get('precision', 0),
                            goal.get('recall', 0), goal.get('loc_median_s'),
                            save.get('f1', 0)))
        else:
            lines.append('还没有训练结果 —— 先「周末重训」。')
        if self.history['weeks']:
            last = self.history['weeks'][0]
            if last.get('test_goal_f1') is not None:
                lines.append('最新测试池: goal F1=%.3f | save F1=%.3f'
                             % (last['test_goal_f1'], last['test_save_f1']))
        else:
            lines.append('还没有测试池结果。')
        self._set_summary('\n'.join(lines))
        # readiness
        if self.history.get('last_gate_f1', 0) >= gate_f:
            ready = '可达门槛: goal F1=%.2f ≥ %.2f' % (
                self.history['last_gate_f1'], gate_f)
            self.status_label.configure(text='✔ %s' % ready,
                                        foreground=self.ok)
            self.hint_test.configure(
                text='模型已达门槛 —— 本周即可尝试「复跑测试集」，看是否值得在测试池上使用。',
                foreground=self.ok)
        else:
            self.status_label.configure(text='训练中/未达门槛', foreground=self.warn)
            self.hint_test.configure(text='')

    def _set_summary(self, text):
        self.summary.configure(state='normal')
        self.summary.delete('1.0', 'end')
        self.summary.insert('1.0', text)
        self.summary.configure(state='disabled')

    # ----------------------------------------------------------- actions
    def _selected(self):
        sel = self.tree.selection()
        if not sel:
            return None
        return self.cfg['matches'][int(sel[0])]

    def on_add_match(self):
        if self._busy:
            return
        folder = filedialog.askdirectory(
            title='选择比赛目录（须包含视频 + .hlcproj 集锦文件）',
            initialdir=REPO_ROOT)
        if not folder:
            return
        folder = os.path.abspath(folder)
        if any(m['folder'] == folder for m in self.cfg['matches']):
            messagebox.showinfo('提示', '该比赛已在数据池中')
            return
        info = scan_folder(folder)
        if not info['videos']:
            messagebox.showwarning('未找到视频', '该目录下没有视频文件')
            return
        if not info['hlcproj']:
            if not messagebox.askyesno(
                    '缺少标签文件',
                    '该目录下没有 .hlcproj。\n\n它只在「highlight-creator 里剪完高光后」才会生成，'
                    '没有它=这场比赛没有标签，训练台没法用。\n\n'
                    '仍要加入数据池吗（标签为空）？'):
                return
        self.cfg['matches'].append({'folder': folder, 'name': info['name'],
                                    'role': 'none'})
        self._save_cfg()
        self.refresh()
        name = info['name']
        do = messagebox.askyesno(
            '新增比赛',
            '已将「%s」加入数据池。\n\n现在就为它抽特征并设为「训练池」吗？（抽特征约每段 4 分钟）'
            % name)
        if do:
            for m in self.cfg['matches']:
                if m['folder'] == folder:
                    m['role'] = 'train'
            self._save_cfg()
            self.refresh()
            self._run_extract(folder)

    def on_remove(self):
        if self._busy:
            return
        m = self._selected()
        if not m:
            messagebox.showinfo('提示', '先在比赛列表选中一项')
            return
        if not messagebox.askyesno('移除',
                                   '将「%s」移出数据池（磁盘上的视频/特征文件不会删除）？'
                                   % m['name']):
            return
        self.cfg['matches'] = [x for x in self.cfg['matches']
                               if x['folder'] != m['folder']]
        self._save_cfg()
        self.refresh()

    def on_set_role(self, role):
        if self._busy:
            return
        m = self._selected()
        if not m:
            messagebox.showinfo('提示', '先在比赛列表选中一项')
            return
        m['role'] = role
        self._save_cfg()
        self.refresh()
        if role == 'test':
            self._log('「%s」设为测试池（此场任何训练都不会用到）' % m['name'])

    def on_extract_feats(self):
        if self._busy:
            return
        m = self._selected()
        if not m:
            messagebox.showinfo('提示', '先在比赛列表选中一项')
            return
        self._run_extract(m['folder'])

    def _run_extract(self, folder):
        def job():
            count = 0
            for v in scan_folder(folder)['videos']:
                t0 = time.perf_counter()
                self._log('抽特征: %s ...' % os.path.basename(v))
                features.build_table(v, ROOT)
                self._log('  ✓ %s (%.0fs)' % (os.path.basename(v),
                                              time.perf_counter() - t0))
                count += 1
            return ('feats_ok', count)
        self._run_thread(job, self._on_feats_done)

    def _on_feats_done(self, result):
        self.refresh()
        if isinstance(result, tuple) and result[0] == 'feats_ok':
            self._log('特征完成: %d 段' % result[1])
        else:
            self._log('特征任务失败: %s' % (result,))

    def _train_pool(self):
        return [m for m in self.cfg['matches'] if m['role'] == 'train']

    def _test_pool(self):
        return [m for m in self.cfg['matches'] if m['role'] == 'test']

    def on_retrain(self):
        if self._busy:
            return
        train_pool = self._train_pool()
        if not train_pool:
            messagebox.showwarning('无法重训',
                                   '训练池为空。先「新增比赛」并设为训练池，且每场至少抽过特征。')
            return
        missing = []
        for m in train_pool:
            done, total = self._feats_state(m)
            if total and done < total:
                missing.append('%s (%d/%d)' % (m['name'], done, total))
        if missing:
            messagebox.showwarning(
                '训练池特征未抽全',
                '以下比赛的特征还没抽完，重训会跳过它们：\n' + '\n'.join(missing)
                + '\n\n请先在比赛列表选中它们「抽特征」，再点「周末重训」。')
            return
        self.refresh()
        self._log('开始周末重训（训练池 %d 场）...' % len(train_pool))
        self._run_thread(self._job_retrain, self._on_retrain_done)

    def _job_retrain(self):
        test_vids = [v for m in self._test_pool() for v in m['videos']]
        excl = ','.join(sorted(stem(v) for v in test_vids))
        args = ['--feats', FEATS_DIR, '--events', GT_PATH,
                '--model-dir', MODEL_DIR, '--exclude', excl]
        rc = train_mod.main(args)
        metrics = read_cv(MODEL_DIR)
        return rc, metrics

    def _on_retrain_done(self, result):
        self.refresh()
        rc, metrics = result
        self._log('重训结束 (rc=%s)' % rc)
        goal = metrics.get('goal', {})
        save = metrics.get('save', {})
        gf = goal.get('f1', 0.0)
        self._log('训练池校验: goal F1=%.3f  save F1=%.3f'
                  % (gf, save.get('f1', 0)))
        self.history.setdefault('weeks', []).insert(0, {
            'date': time.strftime('%m-%d %H:%M'),
            'pool': '%d/%d' % (len(self._train_pool()), len(self._test_pool())),
            'goal_f1': gf,
            'save_f1': save.get('f1', 0),
            'loc': goal.get('loc_median_s'),
            'test_goal_f1': None,
            'test_save_f1': None,
        })
        gate_f = float(self.gate.get())
        if gf >= gate_f and gf > self.history.get('last_gate_f1', 0):
            self.history['last_gate_f1'] = gf
            self._save_history()
            self.refresh()
            self._append_log('★ 达标提醒触发')
            messagebox.showinfo(
                '模型已达标',
                '本周训练后: goal F1 = %.3f（门槛 %.2f）✓\n\n'
                '下周可以尝试「复跑测试集」，用测试池视频做最终验证；'
                '若测试池 goal F1 ≥ %.2f 即可考虑实际使用。'
                % (gf, gate_f, TEST_READY_F1))
            return
        self._save_history()
        self.refresh()
        self._log('未跨过 %.2f 门槛（当前 %s）' % (gate_f, '%.3f' % gf
                                                if gf > 0 else '0'))

    def on_test(self):
        if self._busy:
            return
        test_pool = self._test_pool()
        if not test_pool:
            messagebox.showwarning('无法复跑测试集', '测试池为空。先在比赛列表设置至少一场「测试池」。')
            return
        if not os.path.exists(os.path.join(MODEL_DIR, 'goal.pkl')):
            messagebox.showwarning('无模型', '还没有训练结果。先「周末重训」。')
            return
        self._log('开始复跑测试集（%d 场）...' % len(test_pool))
        self._run_thread(self._job_test, self._on_test_done)

    def _job_test(self):
        agg = []
        stems_ = set()
        for m in self._test_pool():
            for v in m['videos']:
                self._log('推理: %s' % os.path.basename(v))
                agg.append(predict_mod.predict_video(v, MODEL_DIR, ROOT))
                stems_.add(stem(v))
        save_json(TEST_EVENTS, agg)
        gt = evl.load_flat(GT_PATH)
        gt_f = [e for e in gt if os.path.splitext(e['video'])[0] in stems_]
        pred = [f for obj in agg for f in evl.flatten([obj])]
        metrics = evl.event_metrics(pred, gt_f)
        return metrics, len(agg)

    def _on_test_done(self, result):
        self.refresh()
        metrics, n = result
        goal = metrics.get('goal', {})
        save = metrics.get('save', {})
        self._log('测试池结果: goal F1=%.3f  save F1=%.3f (预测 %d 条)'
                  % (goal.get('f1', 0), save.get('f1', 0), n))
        if self.history['weeks']:
            row = self.history['weeks'][0]
            row['test_goal_f1'] = goal.get('f1', 0)
            row['test_save_f1'] = save.get('f1', 0)
        tf = goal.get('f1', 0)
        if tf >= TEST_READY_F1 and tf > self.history.get('last_test_f1', 0):
            self.history['last_test_f1'] = tf
            messagebox.showinfo(
                '测试池通过可用线',
                '测试池 goal F1 = %.3f ≥ %.2f ✓\n\n模型可考虑投入实际使用。'
                % (tf, TEST_READY_F1))
        self._save_history()
        self.refresh()


class _Tap:
    """Redirect sys.stdout/stderr lines into the GUI log."""

    def __init__(self, emit):
        self._emit = emit

    def write(self, s):
        s = s.rstrip('\n')
        if s:
            self._emit(s)

    def flush(self):
        pass


def _fmt(v, nd=3):
    if v is None:
        return '—'
    return ('%.*f' % (nd, v))


def main():
    app = TrainerApp(tk.Tk())
    if '--smoke' in sys.argv:
        app.root.after(500, app.root.destroy)
    try:
        app.root.mainloop()
    except KeyboardInterrupt:
        pass
    if '--smoke' in sys.argv:
        print('trainer_gui smoke OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())