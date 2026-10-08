# 路线 C：手工特征 + 浅分类器（GBDT）— 详细实施计划

> 依据 `models/training_plan.md` §2 路线 C 与 §4 Step 1。路线 C 是第 1 步必做，唯一目的是**量化基线**：先回答"用现有规则特征 + 一个便宜的浅模型到底能到多少"，再决定要不要上深度模型。
>
> **数据集已定**：`temp/test_data/090226/` 一场完整比赛录像（12 个连续分段、无解说），`090226.hlcproj` 里已有手工剪好的 46 个精彩集锦镜头。GT 标签白拿，无需人工标注——本计划的头号瓶颈已消失，剩下的主要是特征提取与调参。
>
> **目标类型（用户已拍板）**：`assist`（助攻）与 `goal` 合并为同一类 `goal`（都是"进攻得手"时刻）；`save` 单独一类。素材为**单固定机位、无回放/机位切换**，因此回放/切镜特征整组砍掉。

## 0. 判定标准（先讲清"何时算赢"）

| 指标 | 定义 | 路线 C 目标 |
|---|---|---|
| 事件级 F1 | 预测事件与 GT 窗口 `IoU ≥ 0.5` 算命中（training_plan §5） | goal F1 ≥ 0.35（明显超 ~10% 静态基线） |
| 定位偏差 | 预测时刻 − GT 中心时刻（秒） | goal 偏差 < 2s |
| 漏检率 | GT 中有、未检出的比例 | 单独报告，尽量压低 |
| 对比值 | 与静态基线比 | 必须显著超越才是"值得做下去"，否则进路线 A |

**go / no-go 决策门（写在计划里，避免做过头）**：
- goal F1 ≥ 0.35 → 留下来深挖路线 C（加数据 > 加特征 > 调参），深度模型整段跳过（YAGNI）。
- 0.15 ≤ F1 < 0.35 → C 给路线 A 当基线与对照。
- F1 < 0.15 → 特征与数据没绑住事件，直接转路线 A。

`save` 样本更少、信号更弱，允许比 goal 低一档，但必须单独报告，不许合并。
⚠️ 本数据集只有 **1 场**，上述数字只对这一场有效（乐观）；对"要不要上路线 A"的最终判断前，需先拿第 2 场验证（见 §9）。

---

## 1. 数据与现状盘点

### 1.1 素材事实（已核实的实测数据）

| 项 | 值 |
|---|---|
| 比赛 | `temp/test_data/090226/` 一场，12 个连续分段 4K 录像 |
| 分辨率/编码 | 3840×2160 h264 30fps，每段 ≈689s（末段 189s） |
| 总时长 | ≈7769.7s（2.16 小时），≈25.6GB（已在本机磁盘上，无需下载） |
| 音频 | **aac 单声道 32kHz 存在、无解说**（相机收音：喊声/哨声/环境声） |
| 机位 | **单固定广角镜头，无回放/机位切换**（用户已确认） |
| 时间跨度 | 05:07–07:14，清晨；**光照逐步变化**（训练/验证划分要留意） |

### 1.2 GT 已存在：`090226.hlcproj` 里的 46 个镜头

| class | 判定词（description 字段） | 数量 |
|---|---|---|
| goal | 含 `进球` 或 `进门` **或 `助攻`** | **26**（12 进球 + 14 助攻） |
| save | 含 `扑出` 或 `没收` | **20** |

每个镜头 = 一段 `[inPointMs, outPointMs)`，全部恰好 **10s**，且 12 个分段全部有镜头（GT 覆盖全场）。`inPointMs/1000` 即事件窗口秒级定位。

### 1.3 环境与可复用代码

- 环境已就绪，零安装：Python 3.11.1、numpy、opencv-python、scikit-learn 1.8、scipy。**路线 C 不需要 pytorch/torchvision**。
- 可复用（都已被 cutting 在用）：

| 文件 | 产出（per 0.33s 一行 CSV） | 字段 |
|---|---|---|
| `experimental/solution1_framediff.py` | `sol1` | `activity`, `activity_smooth` |
| `experimental/solution2_optflow.py` | `sol2` | `n_tracked`, `n_moving`, `frac_moving`, `p90_speed_px_s` |
| `experimental/solution3_track.py` | `sol3` | `n_tracks`, `mean_speed_px_s`, `still_ratio` |
| `experimental/density_solution1_occupancy.py` | `den1` | `occ_left`, `occ_right` |
| `experimental/density_solution3_trackcount.py` | `den3` | `tracks_left`, `tracks_right` |
| `experimental/motion_common.py` | 流式读帧 `frame_reader`、`roi_mask`、`zone_masks`、`write_csv/json`、`detect_events` | — |
| `experimental/cutter.py` | CSV 指纹缓存、`read_series`、`build_hlcproj`、`cut_clip`（集成时直接复用） | — |

**缺什么（本计划要做）**：hlcproj→events.json 解析、音频特征、训练/评估/预测脚本。

**临时文件规则（用户要求）**：本计划所有中间产物一律放 `temp/models/plan_C/` 下（features/models/events/gt/vis/raw），**不碰其它目录**；不改动、不删除 `temp/models/plan_C` 以外的任何文件。

---

## 2. 标注落地：`make_events.py`（GT 从 hlcproj 解析，不人工标）

新增 `experimental/route_c/make_events.py`：
1. 读 `090226.hlcproj` 的 `sources`（id→filePath）与 `timeslots`（videoSourceId + in/outPointMs + description）；
2. 按 §1.2 词表把 description 映射为 `goal / save`（助攻并入 goal）；
3. 输出 `temp/models/plan_C/gt/events.json`：
   ```json
   [{"video": "20260221051909_000004.MP4", "events": [
     {"class": "goal", "t_sec": 385.4, "window": [380.4, 390.4]},
     {"class": "save", "t_sec": 126.6, "window": [123.3, 133.3]}]}]
   ```
   `t_sec` = 窗口中心（10s 窗口内的精确事件瞬间未知，见下）。

### 窗口语义与定位约定（重要，诚实处理）
- GT 事件宽度直接用这 10s 窗口（IoU 按窗口算命中）；`t_sec` 按窗口中心计算。
- 手动剪辑时事件瞬间在窗口内哪个位置不确定；**先目测 3 个镜头**（如 `顺子进球` 524.8–534.8）确认习惯（通常在窗口后段，cutter 约定为 `[t-10s, t]`）。若一致靠后，`t_sec` 改用 `outPoint − 2s` 之类的偏移，避免定位偏差虚高。本实现先按中心，留 `--t-align` 可配。
- **ponytail:** 10s 宽的命中间距对 F1 偏宽，所以定位偏差 <2s 是更严格的验收项；两者一起看，别只看 F1。

### 验收
- `make_events.py --smoke`：虚构 hlcproj 断言计数/时间换算正确；真实文件上打印 `goal=26, save=20`。
- 目测 3 个镜头，确认窗内事件位置假设成立。

---

## 3. 特征工程

一个提取脚本 `experimental/route_c/features.py`，对每个分段产出
`temp/models/plan_C/feats/<name>.csv`，**每 1 秒一行**，列见 §3.3。全部复用 `frame_reader`/ffmpeg 管道（16GB 内存约束，禁止整段加载）。

### 3.1 复用现有特征（零成本）
直接调 `solution1/2/3` 与 `density1/3` 的 `process()`（各自已输出 per-second CSV），`features.py` 只做**按秒对齐合并**，不重算；命中 `#fingerprint` 缓存则跳过。
- 解出的各 solution 原始 CSV 也落 `temp/models/plan_C/raw/<sol>/<name>.csv`，不写进 `temp/motion_quant`，遵守临时文件规则。
- **先验证 ROI/分区校准**：这台机位（固定广角）与 `motion_common` 里 calibrate 的视角未必一致——`features.py --roi-check <video>` 叠 `roi_mask`/`zone_masks` 存图肉眼看，偏了再调 ZONES（否则占用率特征全错）。

### 3.2 音频特征（已确认有信号；仍是弱信号，别指望单独工作）
已实测：`阿淌进球` 段 mean −26.9dB / max −2.2dB，vs 无事件背景 ~ −46/−21dB → 欢呼爆发明显；但多个 save 段只有 ~ −47/−21dB（安静）→ **音频是弱预测器，必须与 motion 特征叠加，不能单独设阈值**。
- 提取：ffmpeg 管道读单声道 32kHz s16le（照着 `_ffmpeg_pipe_reader` 抄 `_audio_pipe_reader`），每 1s 算：
  - `rms_db`：能量包络；
  - `onset`：能量一阶差分（爆发起始）；
  - `hi_ratio`：>8kHz 能量占比（32kHz 采样、Nyquist 16k，哨声在 8–12k 附近）。
- **ponytail:** 先只做三列，够用；多频段/频谱留给路线 A。

### 3.3 特征列总表（每行 = 1 秒）

| 组 | 列 |
|---|---|
| motion（复用） | `activity`, `activity_smooth`, `n_tracked`, `n_moving`, `frac_moving`, `p90_speed_px_s`, `n_tracks`, `mean_speed_px_s`, `still_ratio` |
| density（复用） | `occ_left`, `occ_right`, `tracks_left`, `tracks_right` |
| audio（新） | `rms_db`, `onset`, `hi_ratio` |
| 上下文（训练时加） | 上述所有列的 ±5s 滚动均值/最大值（复用 `moving_avg`/`maximum_filter1d`） |

> ✂️ ~~回放/机位切换特征~~：素材无回放、单机位，`shot_cut`/`cut_streak` 整组删除。

### 3.4 验收
- ROI 图人工确认校准正确（3.1）；
- 抽 10s 片段可视化（帧 + 特征曲线叠印），时间戳与画面无偏移；
- `features.py --selftest` 通过（§11）。

---

## 4. 样本构建 + 类别均衡（单场，1 秒格点）

- 采样格点 1s/行。**正样本** = 落在任一 goal/save GT 窗口内的秒（goal、save 分别建二分类标签）。
- 硬事实：全场 ≈8260 行，goal 正例 ≈26×10=260 行、save ≈200 行、负样本 ≈7800 行 → **类别失衡 ~30:1**。先用 `sample_weight`（正样本 ×10）起步。
- 划分：**按分段（时间序）划分**，如前 9 段 train、后 3 段 val。不能按秒随机切（同段相邻秒强相关，泄漏）。⚠️ 该机位全场，清晨光照漂移恰好让 val（后段）比 train 更亮——这是**便宜的泛化压力**，保留。
- `train.py` 输出 `sample_stats.json`（每类正负计数、每段计数），防止静默空类。

---

## 5. 训练（单场 46 事件，模型很小）

- 默认 `HistGradientBoostingClassifier`（已装、支持 sample_weight、调参少）。**先别写 MLP**。
- ⚠️ 正例只有 26+20 个，**不许使劲调参**：`learning_rate {0.05,0.1}`、`max_iter {200,300}`、`max_leaf_nodes {15,31}` 各扫 2×2 即停，防过拟合班车。
- 阈值：val 上用 `predict.py` 的 `postproc` + `eval.py` 的事件级指标扫阈值（percentile 网格），选 F1 高且**优先保召回**者。
- 产出：`temp/models/plan_C/models/{goal,save}.pkl` + `cv_metrics.json`。

---

## 6. 评估

新增 `experimental/eval.py`：
- 输入：预测 `events.json` + GT `events.json`（来自 `make_events.py`）；
- 输出：goal/save 分开报 **P/R/F1**（事件级，IoU≥0.5 命中），定位偏差（预测−GT 中心，均/中位数秒），**漏检率**；并列打印静态基线对比。
- `--smoke`：虚构 2 命中 + 1 漏检 + 1 误检断言指标计算正确。

---

## 7. 时序后处理 → 事件时间戳

`experimental/route_c/predict.py`：
1. 逐秒概率 → `moving_avg` 平滑（1.5s）；
2. 峰值检测（断层式：概率 > `thr` 且其连续段内取最高）；
3. 时序 NMS：间隔 < 3s 合并，取概率最高者时刻；
4. 输出 `temp/models/plan_C/events/<name>.json`。
- **ponytail:** 三步 ≤15 行；峰值粘连才上 `scipy.signal.find_peaks` + 足量 NMS。

---

## 8. 集成进 highlight-creator（最后做，离线路）

- 固化 CLI `experimental/route_c/detect.py`：`detect.py <segment.mp4> -o out/events.json`（支持传整个 090226 目录批处理）；
- 命中 goal/save 时间戳直接喂 `cutter.py` 的 `build_hlcproj` + `cut_clip` 产片段——正好复刻 `090226.hlcproj` 的产出格式，可一键对比质量。
- 先离线，不做 ONNX/TRT。

---

## 9. 决策门复查（回到 §0）

每轮迭代跑 `eval.py` 对照 §0 三档。重点：**当前只有 1 场，给第 2 场（任何同机位/同画质比赛）做一次 hold-out 评估**，这场的数字才算数：
- 第 2 场 F1 ≥ 0.35 → 留 C（加数据 > 加特征 > 调参 > MLP）；
- 否则 → 用此基线转路线 A（feature + GRU/Transformer 头）。

---

## 10. 分步时间表（有 GT 后比原计划快很多）

| 天 | 步骤 | 产出 |
|---|---|---|
| D1 | 2 `make_events.py` + 3.1 ROI 校准 + 3.x `features.py` 跑 2–3 段先打通 + 3.2 音频验证 | events.json + 首段特征 CSV + ROI/对齐图 |
| D2 | 全 12 段特征提取（一次 ~1–2h，指纹缓存）+ 4–5 首训 + 6 `eval.py` | 首个 F1/定位数字 |
| D3 | 7 后处理 + 阈值调优 | 稳定 F1 + events.json 输出 |
| D4 | 8 `detect.py` 批处理 + 端到端对比 `090226.hlcproj` | 可部署候选 + 决策报告 |

合计 **3–4 天**，计算本身几小时（抽帧/音频/拟合）。

### 每周渐进式训练：直接用 GUI（`models/trainer_gui.py`）

运行 `python models/trainer_gui.py`（tkinter，无额外依赖）把每周流程收进界面：
① 新增比赛（选目录，自动读 `.hlcproj` 出 GT）→ ② 抽特征（后台线程，~4min/段）→
③ 设训练池/测试池（测试池是固定 hold-out，GUI 会自动把它的特征从重训中排除）→
④ 周末重训 → ⑤ 复跑测试集。
训练后若 goal F1 跨过门槛（默认 0.35，界面可调）自动弹窗提醒"下周可以尝试测试池视频"；
测试池 goal F1 ≥ 0.5 弹窗提示可实际使用。状态与周报存在 `temp/models/plan_C/pool.json` / `history.json`。

---

## 11. 验收清单与自检

每个非平凡模块留一个可运行检查（AGENTS.md ponytail 规则），不做测试框架：
- `make_events.py --smoke`：确保 `goal=26 / save=20` 精确命中；
- `features.py --selftest`：合成"静→爆发→静"断言 audio 三列正确升高 + 合并逻辑；
- `eval.py --smoke`：虚构数据掷准 P/R/F1/IoU 数值；
- `predict.py --smoke`：恒定 0.9 概率段 → 只出一个事件且在段中心；
- 端到端：`detect.py temp/test_data/090226 -o out` 至少一个 GT 窗口被命中。

**最终一句话**：GT 已在 `090226.hlcproj` 里白拿，别再造标注流程；先跑通 `make_events → features → train → predict → eval` 一行龙，再用数字过 §0 的门。

---

## 12. 实现结果（090226 实测，可复现）

全部脚本在 `experimental/route_c/`，产物在 `temp/models/plan_C/`。2026-09-03 实测：

| 项 | 结果 |
|---|---|
| `make_events.py`（真实 hlcproj） | `goal=26 / save=20` ✓ |
| 特征（12 段全量，~44min 一次性，指纹缓存） | 每段 689–690 行 × 48 列（16 基 + 16 mean5 + 16 max5），音频爆发与 `阿淌进球`(252–262s) 对齐 ✓ |
| 训练（前 9 段 / 后 3 段验证） | goal **F1=0.27**（P 0.25 / R 0.29 / 定位 1.28s / 漏检 0.71）；save F1=0 |
| 场内 in-sample（有泄漏，仅证明信号可学） | goal F1=0.81 / save F1=0.70 |
| LOSO（留一段平均） | goal F1≈0.13（recall≈0.10）；save ≈0.00；z-score 归一化未改善 |

**结论（走 §0 决策门）**：
- 同一场内**段间转移**不成立：后段天亮（光照漂移）+ `000014` 高运动量 OOD 段，浅模型无法泛化；single-match 时间序 holdout 下 goal F1≈0.13–0.27，**未达 0.35 门**，save 尤其崩。
- 按 §9：**转路线 A**（SoccerNet/自提特征 + GRU/Transformer 头），本套脚本 + 数字即为路线 A 的对照基线与特征/GT 管线（`make_events`、`features`、`eval` 直接复用）。
- `detect.py` 已端到端产出 `events.json` + `out/highlights.hlcproj`（格式同 `090226.hlcproj`，可直接进 app）。
- ⚠️ 待人工确认：`temp/models/plan_C/vis/*_roi.png` 的 ROI/端区框是否对准本机位（颜色法无法自动判定）；若偏，重调 `motion_common.ZONES` 后重跑 features（增量缓存会作废重算）。