# AI 打点

控制面板「我要 → AI 打点」：选一个或多个比赛视频，本地逐个找出"值得看一眼"的
**8 秒候选**，逐段交给 DeepSeek 视觉模型判定，最后把通过的候选**写进同一个**
`.hlcproj`。多个文件**按文件名排序、一次只跑一个**（不并发）；一个文件失败只记为
「跳过」，整批继续。

模型只给建议——**不判定、不写项目**，直到用户点「保存为项目」。

> **入口目前是隐藏的（2026-10-30）**：`app/lib/presentation/shell/control_panel.dart`
> 里「我要 → AI 打点」的 `PopupMenuItem(value: 'ai')` 被注释掉了，原因是 VLM 判定还
> 不够可靠（实拍素材上判定正确率 8%）。`case 'ai'` 分支和 `ai_marking_dialog.dart`
> 都原样保留；要恢复入口，把那一段被注释的 `PopupMenuItem` 取消注释即可，其余不用改。
>
> 对话框本身是**模态**的（`showDialog(barrierDismissible: false)`）：点对话框外面不会
> 关闭，只有「关闭」（会顺带取消正在跑的分析）和运行中的「取消」能退出。

| 项 | 决定 |
|---|---|
| 入口 | 控制面板「我要」→「AI 打点」（「手机打点」下面，「打开成品文件夹」上面）——**当前该菜单项被注释隐藏**，见上文 |
| 输入 | **多个**视频：mp4 / mov / mkv（选择器允许多选，去重、按文件名自然序排队） |
| 顺序 | 一次一个文件，**不并发**（避免限流与 CPU 争抢） |
| 候选 | 纯本地：**画面运动（主）** + 声音 RMS/过零率（辅）取并集，**每个文件**最多 60 个，每个 8 秒 |
| 判定 | 每段 3 张图（三张各 8 帧、各覆盖完整 8 秒：全景 + 两张放大；未标定时为画面上/下半部，标定球门后为两个球门区）→ DeepSeek 视觉请求（最多重试 1 次），**串行** |
| 输出 | **一个** `.hlcproj` 装下所有文件：`sources[]` 每个文件一条，`timeslots[].videoSourceId` 指向各自文件；`%USERPROFILE%\HighlightCreator\results\ai_marking\<首个文件名>-<日期>-<时分秒>.hlcproj` |
| 标定 | 可选：在一帧上框出球门（最多 2 个），存 `%USERPROFILE%\HighlightCreator\calibration\<sha1>.json`；有标定时图2/图3 改裁球门区。**批量开始时**若某些选中文件没有标定、而另一个有，自动 `applyToSiblings` 把该标定写给整批（同一机位） |
| 依赖 | 现有 ffmpeg（`VideoProcessingService.findFfmpeg()`）+ `dart:io HttpClient`，不加包 |

## 流程

```
我要 → AI 打点
  API Key（默认读 settings.json 的 aiMarkingApiKey；勾「记住」才写回）
  模型（默认 deepseek-flash，可改成 deepseek-v4-flash-vision-exp）
  选择比赛视频（mp4 / mov / mkv，可多选）→ 已选 N 个文件（共 X 分钟）
  （可选）标定球门  抽 30% 处一帧 → 拖框 1–2 个 → 保存（可同步到同目录）
  开始分析
    批量开始    选中文件按文件名排序；有标定的文件把标定写给没有的（applyToSiblings）
    逐个文件（一次一个，不并发）
      A  抽音频     ffmpeg → temp\ai_marking\<hash>.wav（该文件用完即删）
      A2 算画面运动  ffmpeg 5 fps 帧差 → temp\ai_marking\<hash>.motion.txt → YAVG 序列（读完即删）
      B  找候选     画面运动 + 声音各出一组 → 重叠 >50% 合并（src=motion|audio|both）→ 8 秒候选（每个文件 ≤60）
      C  逐段判定   每段 ffmpeg 抽 3 张图（全景 8 帧 + 球门区/上下半部放大各 8 帧，
                     三张都覆盖完整 8 秒；见 §C）
                    → 同一条 user 消息 POST → {"highlight","kind","description"}
      文件失败     ffmpeg 打不开 / 解析失败 → 记为「跳过」，继续下一个文件
    D  完成       高光片段列表（按文件分组）+ 候选片段列表（按文件分组）
  保存为项目（只写通过 + 未判定，所有文件进同一个 .hlcproj）→ 提示路径
  全程写 [ai-marking] 日志 → logs\error-YYYYMMDD.log（见 §Logging）
```

实现：

- 界面 `app/lib/presentation/shell/ai_marking_dialog.dart`
- 批量的纯 Dart 部分（排序 / 按文件分组 / 批量汇总 / 多源 `.hlcproj` 组装）
  `app/lib/services/ai_marking_batch.dart`（纯 Dart，可用
  `dart --packages=temp/ai_probe_pkg/package_config.json temp/ai_batch_probe.dart` 单独验证）
- 球门标定界面 `app/lib/presentation/shell/goal_calibration_dialog.dart`
- 标定数据与裁切表达式 `app/lib/services/goal_calibration.dart`（纯 Dart，可用
  `dart temp/goal_calibration_probe.dart` 单独验证）
- ffmpeg 与 HTTP `app/lib/services/ai_marking_service.dart`
- 画面运动候选 `app/lib/services/motion_spike_detector.dart`（纯 Dart，可用
  `flutter test test/services/motion_spike_detector_test.dart` 单独验证）
- 声音候选 `app/lib/services/audio_spike_detector.dart`（纯 Dart，可用
  `flutter test test/services/audio_spike_detector_test.dart` 单独验证）

## 批量（多选、顺序、跳过、取消）

一次跑 11 个分片是这一功能最常用的姿势：一场比赛被相机切成十几个文件，逐个选太慢，
一次选完又不能让它们互相干扰。

### 选择

- 选择器 `allowMultiple: true`，仍只接受 **mp4 / mov / mkv**；不支持的扩展名被过滤，
  一个都不剩时提示「只支持 mp4 / mov / mkv。」；
- 选完按**文件名**排序并去重（同一文件被选两次只跑一次），文件行显示
  **「已选 N 个文件（共 X 分钟）」**，X = 各文件时长之和（1 位小数）；悬停可看完整文件名列表；
- 排序规则（`sortBatchFiles`）：basename、忽略大小写、**数字段按数值比较**
  （`part9` 在 `part10` 前，`GX0111` 在 `GX0112` 前），同名的两个路径再按完整路径定序；
- 时长在选完时用 ffprobe 逐个探一次并缓存，start 行与「共 X 分钟」都不会再探第二遍；
  ffprobe 不可用时显示「共 — 分钟」，不影响分析。

### 执行

- **串行**：`for` 循环里 `await` 完一个文件再进下一个；同一时刻只有一条 ffmpeg 和一个
  在途 HTTP，限流与 CPU 争抢都不会因为多选而出现；
- 每个文件都完整跑一遍 A → A2 → B → C，**不合并、不抽样**：候选数量与阈值和单文件完全一致
  （每个文件仍是最多 60 个 8 秒候选，判定标准不变）；
- 进度分两层：
  - **文件级**（进度条上方）`第 2/11 个文件 · 已完成候选 47 段`——「已完成候选」是整批
    到此刻已经产出的候选段数（前面文件 + 当前文件已检测到的），只增不减；
  - **阶段级**（进度条下方，沿用旧文案）`抽音频 / 算画面运动 / 找候选 / 逐段判定 i/n`；
  - 进度条 = (已完成文件数 + 当前文件内进度) / 文件总数；
- **单文件失败不中断整批**：抽音频失败、WAV/元数据解析失败、候选检测抛异常 → 该文件记为
  「跳过」（界面显示「N 个文件失败」，高光列表里该文件分组写「已跳过（分析失败）」），
  继续下一个文件；
- **401 / 模型不支持图片** 仍会中止整批：后面每个文件都会以同样原因失败，没有意义再跑；
  已跑完的文件结果保留、可保存；
- **取消** 中止整批：`AiMarkingService.cancel()` 杀掉正在跑的 ffmpeg，
  `DeepSeekVisionClient.cancel()` 关闭在途 HTTP，循环在下一个检查点退出，状态显示「已取消。」，
  已完成文件的结果保留；
- **中间状态用完即删**：WAV 在该文件跑完（含失败、取消）时删除，`motion.txt` 读成序列后立即删，
  每个候选的 3 张拼图判完立即删。批量不会让 `temp\ai_marking` 堆积——11 个文件跑完，
  那里最多只有**当前文件**的临时文件，正常结束时为空。

### 高光片段列表（新）

跑完后对话框**上半部分**多一个「高光片段」区域，候选列表仍在它下面：

- 标题带总数：**「高光片段 · 共 12 段」**；
- **按视频文件分组**，组标题是文件名 + 「N 段高光」（`GX01123.MP4 · 4 段高光`）；
- 每行：`mm:ss–mm:ss`、kind 的中文译名（goal→进球 / save→扑救 / shot→射门 / other→其他）、
  模型给的一句话描述；**点整行**用现有预览窗口播放该段
  （`Media(start, end)`，用的是**该行所属文件**的路径，不是第一个文件）；
- 只列 `verdict=highlight` 的段；某个文件 0 段高光时保留它的分组并显示「无检出高光」，
  跳过（分析失败）的文件同样保留分组并显示「已跳过（分析失败）」——跑过的文件不会静默消失；
- 候选列表（旧的）保留**全部**候选，也按文件分组的组标题显示（`文件名 · N 段候选`），
  每行仍是「mm:ss–mm:ss · 高光/普通/未判定 · 描述 · 查看」。


## A. 抽音频

```
ffmpeg -y -loglevel error -i <源> -vn -ac 1 -ar 16000 -f wav <temp>\ai_marking\<hash>.wav
```

`<hash>` = 源路径 + 文件大小 + mtime 的 SHA-1 前 16 位（`AiMarkingService.keyFor`），
换一个同名但重新导出过的文件不会命中旧 WAV。抽完立即删除，跑完 `temp\ai_marking` 里不留东西。

## B. 候选检测（不联网）

两条通道各跑各的，最后取并集：

| 通道 | 判据 | 代码 | 角色 |
|---|---|---|---|
| **画面运动** | 帧间差异骤增 | `motion_spike_detector.dart` | **主判据** |
| 声音 | RMS 能量 + 过零率 | `audio_spike_detector.dart` | 辅助 |

### 画面运动通道

**为什么主判据换成画面**：素材是业余球场、固定远景机位（实测画面见
`temp\test_data`：夜间灯光、5 人制、相机在场外高台上）——没有裁判所以没有哨声，进球/扑救后
观众可能欢呼也可能一声不吭，相机离得远、收音差。2026-10-29 那一轮 11.5 分钟素材只召回 4 条
真高光里的 3 条，漏掉的 **01:24** 是一记扑救，现场没人喊：声音通道从物理上就看不见它。
而球进门、门将倒地、射门这几件事一定让画面里的像素成片移动——**帧间差异是比响度可靠得多的
信号**，而且不受"有没有人喊"影响。

**命令**（`MotionSpikeDetector.ffmpegArgs`，临时文件在 `temp\ai_marking\<hash>.motion.txt`）：

```
ffmpeg -y -loglevel error -i <源> -an \
  -vf "fps=5,scale=320:-2,format=gray,tblend=all_mode=difference,signalstats,metadata=print:file='<临时 txt>'" \
  -f null -
```

- `fps=5`：5 fps 够用（8 秒窗口 40 个采样点），metadata 一分钟约 2900 行、几十 KB；
- `scale=320:-2`：4K 先缩到 320 宽再比，比较量小一个数量级；
- `format=gray` + `tblend=all_mode=difference`：转灰度，相邻帧相减取绝对差；
- `signalstats` 把每帧的 `lavfi.signalstats.YAVG`（这一帧差图平均亮度）写进 metadata，
  `metadata=print:file=` 落盘；
- 路径写成 `file='C\:/...'`：ffmpeg 滤镜用 `:` 分隔选项，Windows 盘符冒号必须转义、
  整段再加单引号（`MotionSpikeDetector._filterPath`）；
- `-an` 只是省掉音频解码，不改变画面帧数；`-loglevel error` 免得 12 分钟的进度刷屏。

**序列 → 候选**（`MotionSpikeDetector.detect`，纯 Dart，不联网不需要模型）：

1. 5 个采样点（1 秒）取均值 → `motion[i]`；
2. **局部基线** `base[i]` = `motion[i-60 .. i+60]`（±60 秒，边界裁剪）的**中位数**；
3. 命中条件：`motion[i] > 1.8 * base[i]`，**并且** `motion[i] > 0.15 * median(motion)`
   （底噪保护：死寂画面里的压缩噪声不算事件）；
4. 连续命中窗口合并成事件；相邻事件间隔 **< 5 s** 再合并；
5. 取事件内 `motion` 峰值那一秒 → 候选窗口固定为 **`峰值 − 6 s` 到 `峰值 + 2 s`**
   （仍 8 秒，只前移；见 §窗口为什么前移），超出文件头尾按边界裁剪；
6. 超过 60 个按峰值从高到低截断，再按时间排序。

阈值与声音通道同一套（1.8× / 0.15 / ±60 s / 5 s），写死在 `MotionSpikeDetector` 的常量里。
**没有**"结果太少就放宽"的第二次机会：画面运动的漏检比误检贵得多，放宽会立刻把换镜头、
灯光变化、镜头抖动全放进来。

### 声音通道（辅助）

读 WAV 的 PCM16（必须单声道 16 bit，否则抛 `FormatException`——命令行是我们自己给的，
格式不对就是 bug）：

1. 按 **1 秒窗口**算 RMS 与过零率 ZCR；
2. **局部基线**：对每个窗口 i，取 `[i-60, i+60]`（±60 秒，边界裁剪）内所有窗口 RMS 的
   **中位数** `base[i]`；
3. 两个通道，任一命中即为候选窗口：
   - 能量通道：`rms[i] > 1.8 * base[i]`；
   - 哨声通道：`zcr[i] > 1.3 * median(zcr)` 且 `rms[i] > 1.5 * base[i]`（哨声=响且高频）；
   - 底噪保护：还要 `rms[i] > 0.15 * median(rms)`，避免在极安静段把空调噪声当事件；
4. 连续命中窗口合并成事件；相邻事件间隔 **< 5 s** 再合并；
5. 每个事件取 RMS 峰值那一秒 → 候选窗口固定为 **`峰值 − 6 s` 到 `峰值 + 2 s`**
   （仍 8 秒，只前移；见 §窗口为什么前移），超出文件头尾按边界裁剪；
6. 事件 > 60：按峰值 RMS 从高到低取前 60，再按时间排序；
7. 事件 < 10：放宽到能量 **1.5×**、哨声 **1.3×**（ZCR 侧仍是 1.3×）重跑一次
   （更少则保留第一次的结果）。

阈值写死在 `AudioSpikeDetector` 的常量里，改之前先想清楚：这是"漏掉高光"与"发 60 个请求"的
唯一折中，不是可随手调的旋钮。**为什么用局部基线**：2026-10-29 的 11.5 分钟素材手动标了
4 条真高光，旧的全局 `RMS > median + 4×MAD`（放宽 `3×MAD`）只覆盖了其中 **2 条**，漏掉的
01:24、01:34 位于一段整体偏吵/偏静不均的区间——只要全场某处更响，全局阈值就被抬高，局部
高光随之被压掉。改成 ±60 秒局部中位数后，阈值只跟窗口周围一分钟的"常态"比，同一素材上的
这两条不再被远处的响段拖累；`test/services/audio_spike_detector_test.dart` 用"前 60 秒大
白噪声 + 84 s / 94 s 两个短脉冲"固定住了这个差异（旧规则 0 命中，新规则两处都命中）。

即便如此，声音通道的上限就在那里：**01:24 那记扑救只有画面、没有声音**，所以它现在只做辅助
——它的价值是补齐"画面看不出、但有哨声/欢呼"的时刻（进球后庆祝、裁判哨）。

### 窗口为什么前移（2026-10-29 实测）

候选窗口从「峰值 ±4 秒」改成 **`峰值 − 6 秒` 到 `峰值 + 2 秒`**（仍 8 秒）。原因有两层：

1. **欢呼滞后**：进球时人群的反应比球过线晚 **1–3 秒**。按声音峰值居中取 ±4 秒，
   球进门那一下落在窗口前半段甚至窗外；只按运动峰值居中，球在窗口正中，但进球后
   2 秒的庆祝/球在网里又看不到。前移 2 秒（6+2 而非 4+4）让声音峰值对应的进球落在
   窗口 3–5 秒处，运动峰值对应的进球落在 6 秒处，后面仍留 2 秒余波。
2. **上一轮实测**：候选召回 89%（56/63），但 VLM 只判对 **8%**；判对的 5 段**全部是
   扑救**——扑救是持续 1–2 秒的姿态，容易撞上旧拼图；进球是一瞬间，撞不上只覆盖窗口
   前 4 秒（全景）/ 前 2 秒（球门放大）的旧拼图。窗口前移与 §C 的 8 帧全覆盖是同一轮
   修复的两半，判定标准与 prompt 的判定条款一个字没动。

边界规则不变：窗口超出文件头尾时照旧裁剪到文件边界，因此文件开头/结尾附近的候选可能
短于 8 秒。`cand` 行的 `win=` 是实际的 `起点 − 峰值`（正常 `-6000`；起点被文件头裁到 0
时会变成 `-3500` 之类；只在文件尾裁短时仍是 `-6000`，但 `out − in` 会小于 8 秒）。

### 合并与排序

- 两条通道各自给出 8 秒候选，**取并集**：按时间排序后，两个区间重叠**超过较短者的一半
  （>50%）**就视为同一个时刻，合成一个候选、区间取**并集**（例如 01:22–01:30 与
  01:24–01:32 → 01:22–01:32）；
- 每个候选记下来源 `src=motion | audio | both`——这是这一轮实验唯一的证据：01:24 是
  `src=motion` 就说明画面通道补上了声音漏掉的那一条；
- 并集区间超过 8 秒时，以**运动峰值**那一秒为准裁回 `峰值 − 6 s .. 峰值 + 2 s`
  （只有声音的候选就用声音峰值）：三个拼图现在覆盖完整 8 秒，裁剪是为了让合并后的窗口
  与两个 detector 的窗口形状一致，峰值仍落在 6/8 处、后面留 2 秒余波；
- **上限仍是 60**：先留 `both`，再按 `motionPeak` 从高到低，最后按 `peakRms`（声音响度），
  截断后按时间排序；
- **降级**：ffmpeg 不可用、解析不出 `YAVG`（连 2 个 1 秒窗口都凑不齐）或命令非零退出，都
  只记一行 `motion unavailable`、界面顶部提示「画面运动不可用，仅用声音。」，分析继续走
  纯声音，**不让整次分析失败**。

## 球门标定（可选）

这一节只决定「图2/图3 裁哪里」；本轮**没有**改 `motion_spike_detector.dart`，
运动通道完全保持原样（下轮再把运动判据限制到球门区）。

素材是固定机位的业余球场远景（4K）：球门在画面里是绝对固定的物体，但球只有几个像素。
用户在一帧上画出球门矩形后：

1. **图2/图3 变成球门区的放大画面**，模型能看清球门附近发生了什么；
2. 标定结果落盘，下一个视频/下一次启动直接复用。

### 数据与存储

- `GoalCalibration { sourceKey, rects, frameTimeMs, updatedAt }`，`rects` 最多 **2** 个；
- `NormRect { x, y, w, h }` 全部是 **0..1 归一化**（相对画面宽高），换分辨率不用重标；
- 一个源一个文件：
  `%USERPROFILE%\HighlightCreator\calibration\<sha1(源文件绝对路径)>.json`
  （`sourceKey` 就是这段 sha1，也是文件名）；
- JSON 形如：

  ```json
  {
    "sourceKey": "…",
    "rects": [{"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.16}],
    "frameTimeMs": 123456,
    "updatedAt": "2026-10-29T17:00:00.000"
  }
  ```

- 读/写失败一律**静默降级**：`load()` 返回 null、`save()` 返回 false，分析照旧按
  「没有标定」跑，不会因为标定文件坏了而失败。尺寸小于 1% 的误点会被丢弃。
- 标定不在 `temp\` 下，清缓存不会删掉它；要作废只能删对应的
  `<sha1>.json`（或换机位后重新标定覆盖）。

### 界面

- 入口：AI 打点对话框里「选择比赛视频」旁边的「标定球门」（没选文件、或正在分析时不可点；
  多选时标的是**排序后的第一个文件**，批量开始时会自动把它的标定写给其它文件，见下节）；
- 打开时抽一帧：`ffmpeg -y -loglevel error -ss <0.3×时长> -i <源> -frames:v 1 -an
  temp\ai_marking\calib_frame.jpg`；已有标定时用它的 `frameTimeMs` 重抽同一帧，
  旧矩形才对得上；帧按源宽高比显示，画布坐标即归一化坐标；
- 在帧上**拖动**画矩形，最多 2 个（球门 1 / 球门 2）；再拖就替换第 2 个；
  矩形带边框与序号，下面用 3 位小数显示归一化坐标，便于排查；
- 按钮：「清除」重画、「保存」、「应用到同目录所有视频」（默认不勾；勾了会给同目录
  其它 mp4/mov/mkv 写同一组矩形——机位没变，标一次整场复用，写失败的其它文件跳过；
  这些文件的 `frameTimeMs` 写 0，下次打开各取自己 30% 处的帧，因为分片长度不同）；
- 保存后关闭并提示「已标定 N 个球门」；抽帧失败提示「无法取帧，标定不可用」，只能取消；
- 写 JSON 失败时界面提示「保存标定失败」，本次分析按无标定跑。

### 批量时的自动应用

一次选中 11 个分片时，用户通常只在第 1 个上标一次球门（机位没动）：

1. 批量开始时逐个文件按**各自的 sha1** 读标定；
2. 若「至少一个文件有标定」且「至少一个选中的文件没有」→ 对**第一个有标定的文件**调
   `GoalCalibration.applyToSiblings()`，把同一组矩形写给同目录所有视频；
3. 日志 `[ai-marking] calib applied from=<文件名> files=<写入个数> boxes=<矩形数>`，
   界面提示 **「已将球门标定应用到 N 个文件」**（N = 实际写入的文件数，含目录里没被选中的视频）；
4. 之后每个文件仍然**重新读自己的标定**，所以每个 `start` 行的 `calib=` 都是它自己的；
5. 全部文件都已有标定、或全都没有 → 什么都不做（不会互相覆盖）。

两个选中文件带着**不同**矩形时，后写的会覆盖前面的（`applyToSiblings` 是整目录写）。
同一机位是确认过的用法，换机位/换场次必须重新标定。

## C. 逐段判定

每个候选跑 3 条 ffmpeg 命令（都从窗口起点 `start` 开始，**不再提前 1 秒**），得到 3 张
各 **8 帧**的 JPEG。三张图都**覆盖完整 8 秒窗口**：`tile` 的格子数 ÷ `fps` 就是覆盖秒数。
旧版是 `fps=2`——全景 8 格只覆盖前 4 秒、球门 2×2 的 4 格只覆盖前 2 秒，进球这种一瞬间
的动作经常落在两格之间（上一轮 VLM 只有 8% 判对、5/5 判对的又全是扑救，原因就在这里）。
图1 永远是全景；图2/图3 取决于该源有没有标定（见 §球门标定）：

**没有标定**：

| 图 | `-vf` | 内容 | 典型尺寸（16:9 源） |
|---|---|---|---|
| 图1 全景 | `fps=1,scale=448:-2,tile=2x4` | 8 帧 = 8 秒，2 列 × 4 行 | 896×1008 |
| 图2 上半部 | `fps=1,crop=iw:ih/2:0:0,scale=896:-2,tile=4x2` | 画面上半部 8 帧 = 8 秒，4 列 × 2 行 | 3584×504 |
| 图3 下半部 | `fps=1,crop=iw:ih/2:0:ih/2,scale=896:-2,tile=4x2` | 画面下半部 8 帧 = 8 秒，4 列 × 2 行 | 3584×504 |

**有标定**（1–2 个球门）：

| 图 | `-vf` | 内容 | 典型尺寸 |
|---|---|---|---|
| 图1 全景 | 同上 | 8 帧 = 8 秒，2 列 × 4 行 | 896×1008 |
| 图2 球门 1 | `fps=1,crop=floor(iw*{w}/2)*2:floor(ih*{h}/2)*2:floor(iw*{x}):floor(ih*{y}),scale=896:-2,tile=4x2` | 球门 1 区 8 帧 = 8 秒，4 列 × 2 行 | 3584×(2×缩放后高)，约 400–900 |
| 图3 球门 2 | 同上，用第 2 个矩形 | 球门 2 区 8 帧 = 8 秒，4 列 × 2 行 | 同上 |
| 图3 单球门 | 没有第 2 个矩形时退回下半部滤镜 | 画面下半部 8 帧 = 8 秒，4 列 × 2 行 | 3584×504 |

- `{x}/{y}/{w}/{h}` 是 0..1 归一化值（写进表达式时保留 6 位小数），顺序固定为
  **先 `crop` 再 `scale`**，`fps=1` 在最前、`tile=4x2` 在最后；
- 为什么球门图用 `scale=896` 而不是 1120：3584 宽已经超过 DeepSeek 单图约 1300 px
  的等效上限（单图最多 1024 token），整张会一起被缩到同一档；把 scale 提到 1120
  只是先放大再缩回去，**每格分到的像素不变**，JPEG 与上传反而更大。所以选 896，
  尺寸就是上表的 3584×504；
- 宽高都写成 `floor(… / 2) * 2`：H.264/JPEG 的色度采样要求偶数尺寸，归一化宽度乘出来
  可能是奇数（3840×0.36 = 1382.4 → 1382，但 1921×0.3715 = 713.7 → 713 就是奇数，
  直接写 `iw*0.3715` 会落到 713）；x/y 只需 `floor` 取整；
- 表达式示例（球门 1 在 3840×2160 上取 x=0.32、y=0.60、w=0.36、h=0.24）：
  `crop=floor(iw*0.360000/2)*2:floor(ih*0.240000/2)*2:floor(iw*0.320000):floor(ih*0.600000)`
  → 1382×518 的裁切区，再 `scale=896:-2`；
- 只有 1 个球门时，图3 仍是下半部：模型还能看到球场另一半，不至于只剩一个球门。

完整命令与 A 相同，只换 `-ss` 起点、`-vf` 与输出名：
`ffmpeg -y -loglevel error -ss <窗口起点> -i <源> -vf "<上表的滤镜>" -frames:v 1 -an <jpg>`。
8 帧按 1 fps 采，正好是窗口的 0..7 秒；窗口本身是 `峰值 − 6 s .. 峰值 + 2 s`，所以
前 6 帧是上下文、后 2 帧是进球后的余波。

为什么这么裁：2026-10-29 复盘的 11.5 分钟素材里，漏判的 3 段全部发生在**画面远端**
（模型描述都是"远景，球员在中场跑动"）——单张 896 宽的全景里，远端球员只剩几十像素。
上下半部各裁一半再放大到 896 宽，等于把远端放大 2 倍；标定后直接把球门框出来放大，
远处的球门区不再是画面的一小块，球和门将的动作才看得清。

三张图放进**同一条 user 消息**的 `content` 数组（1 个 text + 3 个 image_url，顺序固定为
图1/图2/图3），POST 到 `https://api.deepseek.com/chat/completions`，OpenAI 兼容的 vision 格式：

```json
{
  "model": "deepseek-flash",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "<prompt>"},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,<图1>"}},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,<图2>"}},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,<图3>"}}
    ]
  }],
  "temperature": 0,
  "max_tokens": 512,
  "thinking": {"type": "disabled"},
  "response_format": {"type": "json_object"},
  "stream": false
}
```

prompt 明确告诉模型三张图各是什么，措辞随标定切换（`DeepSeekVisionClient.promptFor`）：

**没有标定**（只改了图片几何描述，判定条款逐字未动）：

- 图1 = 全场 8 帧（2×4，从左到右、从上到下按时间顺序）；
- 图2 = 画面上半部放大 8 帧（4×2），远端在画面上方时看这张；
- 图3 = 画面下半部放大 8 帧（4×2），远端在画面下方时看这张；
- 若动作发生在远处/画面深处，以图2或图3为准；三张图都看不清时判普通。

**有标定**（`promptFor(goals: n)`）：

- 图1 = 全场 8 帧；
- 图2 = 球门 1 区域的放大画面 8 帧（4×2）；
- 图3 = 球门 2 区域的放大画面 8 帧（4×2）；只有 1 个球门时仍是「画面下半部」；
- 两个球门时 prompt 明说「图2/图3 是两个球门区域的放大画面」，并说明这是用户在固定
  机位画面上标定的两处球门；进球/扑救以图2/图3 为准。

除图片说明外，判定标准、`json` 契约、`description` 要求与无标定时完全一致。

**判定标准（2026-10-29 收紧）**：只有下面三种情况之一才算高光（`highlight: true`）：

1. 球进入球门（含折射、补射）；
2. 门将做出扑救动作（倒地、扑出、没收）；
3. **无人防守**下面对球门起脚，且球明显朝门框范围内飞去。

prompt 里同时写死了**不算**的三种情况：仅仅在禁区外或人群中起脚、球被挡出或偏出、只是带球
推进——都不算高光。上一版判的是"有威胁的进攻"，模型于是把每一次禁区外起脚都记成高光，候选
里大半是"远射被挡"。收紧后判据只剩"球真的到了门框附近"这一类事件，宁可漏掉一次平淡的
射门，也不要把它写进项目。

`max_tokens: 512` + `response_format: json_object` 是 2026-10-29 那次实测之后加的：
11.5 分钟素材 22 段**全部 HTTP 200**，却 19 段失败——失败原因只有两种，
`choices[0].message.content` 为空（`finish_reason=length`，token 预算被思考吃掉）
和 JSON 被截断。当时的上限是 300、也没开 JSON 模式；3 段正常返回中文描述，
说明模型确实能看图，问题在预算与格式，不在模型能力。prompt 里的 `json` 特意用小写：
JSON 模式要求 prompt 里出现这个词。

**重试**：一次请求的 `finish_reason == "length"`，或 `content` 去掉空白后为空，
就用 `max_tokens: 1024` 把**同一段**再发一次（只重试一次；仍失败才记 `failed`）。
重试请求带的是**同样的三张图**（不会重新抽帧，也不会少发）。网络错误、超时、4xx/5xx
不重试。所以每个候选最多 2 次请求、3 张图 × 2。

**思考开关**：请求里带 `thinking: {"type": "disabled"}`（见上例）。`deepseek-flash` 若仍
在思考，日志里的 `reasoning_len` 会直接暴露它是否在吃预算。

**token 估算**：`estimateInputTokens` 按**图片张数**累加——每张按 JPEG SOF 里的尺寸算
28×28 patch，再各自封顶 1024，最后加一次 prompt 文本与信封。三张图的上限约
`3×1024 + 文本 + 32 ≈ 3500`/段；按 2026-10-29 实测每张 896×1008 约 711 token，三张图本身
约 **3×711 ≈ 2100/段**（另加 prompt 文本约 0.4k）。估算只在回包没有 `usage` 时用于补
`~prompt_tok`，真实花费以回包 `usage` 为准。

prompt 要求模型只回一个 JSON：`{"highlight": true|false, "kind": "goal|save|shot|other|none",
"description": "中文一句话"}`。解析容错：允许 ```json 围栏与前后废话；`content` 是数组时
按各 part 的 `text` 拼接；只取**第一个平衡的 `{...}`**（字符串里的花括号不算）；`kind` 不在
枚举里按 `other`；`highlight` 非 `true` 一律当"普通"；没有平衡块（被截断）或 JSON 非法
→ 该段 `failed`。

**串行**：一次只发一个请求（见 F）；唯一的例外是失败重试，而且重试也在同一个串行循环里。

## D. 容错

| 情况 | 行为 |
|---|---|
| 4xx 且错误信息提到 image / vision / content-type / modality | **立刻停止后续请求**并中止整批（后续文件不再请求），顶部醒目提示「该模型不支持图片输入，已只保留候选（未经 AI 判定）」，当前文件全部候选记为「未判定」，仍可保存 |
| 401 / 403 | 提示「API Key 无效，已停止分析。」，当前文件全部候选「未判定」，不再发请求、后续文件也不跑 |
| 回包被截断（`finish_reason=length`）或 `content` 为空 | 用 `max_tokens: 1024` 把同一段重试**一次**（重试仍带同样的 3 张图）；仍失败按下一行处理（每段最多 2 次请求） |
| 单个候选失败（超时、5xx、回包不是 JSON、重试后仍为空/截断） | 只把那一段记为「未判定」，累加失败计数，继续下一段；分析结束后显示「N 段判定失败(已跳过)」 |
| 找不到 ffmpeg | 「找不到 ffmpeg，无法分析。」，不开始 |
| 标定文件缺失 / 损坏 / 无权限 | **静默降级**：当作没有标定，图2/图3 回到上半部/下半部，分析照常跑；日志 `start` 行是 `calib=0` |
| 标定抽帧失败（ffmpeg 不可用、seek 失败、写出 0 字节） | 标定对话框提示「无法取帧，标定不可用」，只能取消；不影响之后的正常分析 |
| 标定保存失败（磁盘满、无权限） | 对话框提示「保存标定失败，本次不会使用它。」，不关闭；本次分析按无标定跑 |
| **画面运动不可用**（ffmpeg 无 `tblend`/`signalstats`、`metadata=print` 写不出文件、解析不到 `YAVG`、命令非零退出） | 只记一行 `motion unavailable`，顶部提示「画面运动不可用，仅用声音。」，**分析继续**：候选退化为纯声音通道（只影响**当前文件**，下一个文件重新尝试） |
| **单个文件打不开/解析失败**（ffmpeg 非零退出、WAV 不是 16 bit 单声道、候选检测抛异常） | 该文件记为「跳过」：日志 `file i/n skipped file=<名> elapsed=<秒> error=<≤200 字>`，界面累计「N 个文件失败」，高光列表里该文件分组写「已跳过（分析失败）」，**整批继续**；已跑完的文件结果不受影响 |
| 取消 | 杀当前 ffmpeg + 关闭在途 HTTP，**整批停止**，状态显示「已取消。」，当前文件临时文件删除；已完成文件的结果保留、仍可保存 |
| 没有候选（某个文件） | 该文件「完成」，候选 0 段；高光列表里它的分组写「无检出高光」，整批继续 |
| 没有候选（整批） | 直接「完成」，两个列表都只有分组标题，不写项目 |
| 没有通过的候选（整批） | 「保存为项目」不写文件，提示「没有判定为高光的候选，未写出项目文件。」 |

"未判定"的候选也会被保存（rating 2），这样模型不可用时用户至少拿到一份可用的候选清单。
跳过的文件**不进** `sources[]`：它没被分析，`durationMs` 也无从得知。

## E. 写 `.hlcproj`

字段按 `docs/hlcproj_format.md`，与现有 `buildProjectJson()` 同形。**整批写进同一个文件**：
`sources[]` 每个（跑完的）文件一条，`timeslots[].videoSourceId` 指向它自己的文件。

```json
{
  "name": "<排序后第一个文件的文件名去扩展名>",
  "date": "2026-10-29",
  "sources": [
    {"id": "src-ai-1", "filePath": "D:\\match\\GX01123.MP4", "durationMs": 689200, "width": 3840, "height": 2160},
    {"id": "src-ai-2", "filePath": "D:\\match\\GX01124.MP4", "durationMs": 701400, "width": 3840, "height": 2160}
  ],
  "timeslots": [
    {
      "id": "slot-ai-1", "videoSourceId": "src-ai-1",
      "inPointMs": 12000, "outPointMs": 20000,
      "description": "10 号禁区外远射破门",
      "rating": 4,
      "filename": "GX01123.MP4"
    },
    {
      "id": "slot-ai-2", "videoSourceId": "src-ai-2",
      "inPointMs": 33000, "outPointMs": 41000,
      "description": "门将单掌托出角球",
      "rating": 4,
      "filename": "GX01124.MP4"
    }
  ]
}
```

- `sources[]`：**每个跑完的文件一条**（跳过的文件不写），id 依次 `src-ai-1..n`，
  各自 `filePath` / `durationMs` / `width` / `height`；0 段高光的文件也在里面（它的分组说明它跑过）；
- `timeslots[]`：id 在**整批**范围内连续编号 `slot-ai-1..m`，`videoSourceId` 指向**该段所属
  文件**的 id（不是第一个文件），`filename` 也是该文件的文件名；每段内按 `inPointMs` 排序；
- `name`：排序后**第一个文件**的文件名去扩展名（一批连续分片属于同一场，用它命名最可预测）；
- `date`：同一个文件的文件名里的 `yyyy-mm-dd`（`projectDateFromFileName`），没有就用今天；
- rating：**高光 = 4**，**未判定 = 2**；"普通"根本不写；
- `description`：模型那一句；未判定时用「AI 候选 N」（N = 该段在整批 `timeslots` 里的序号）；
- 写出位置与文件名见上表（`<首个文件名>-<日期>-<时分秒>.hlcproj`），保存后在对话框里显示
  完整路径（可选中复制）。

## F. 并发与取消

- **文件之间**严格串行：`for` 循环里 `await` 完一个文件再进下一个，一次只有一个 ffmpeg、
  一个在途 HTTP；多选不会让限流或 CPU 争抢互相叠加；
- **文件内部**同样串行：VLM 请求 `await` 每一段，唯一的重试（§C，每段最多一次）也在同一个
  循环里；
- 取消按钮：`AiMarkingService.cancel()` 杀 ffmpeg 进程、`DeepSeekVisionClient.cancel()`
  `close(force: true)` 关掉在途连接；**整批**在下一个检查点退出（当前文件、文件之间各一次检查）；
- 每次运行有 `_runId`，被"重新分析"顶掉的那次运行不会再写界面（仍会写完它自己的日志行）；
- 临时文件：WAV 在该文件跑完（含失败/取消）立即删，画面运动的 `motion.txt` 在读成序列后
  立即删，每个候选的 3 张图判完立即删（含中途失败与取消），关闭对话框也会 cancel。
  多个文件**不共享**临时文件（文件名带各自的 hash），所以不会互相踩，也不会累积。

## Logging（日志）

一次分析跑完就没了：候选、阈值、每段的 HTTP 状态、token 与失败原因都只存在于那几分钟的
界面里。**不留日志就无法复盘**——同一份素材再跑一次，模型、阈值和网络状况都可能已经不是
上一轮的样子，出了问题只能靠猜。所以每次「开始分析」都把过程追加进现有的崩溃日志文件，
不另建第二个日志文件。

- 文件：`%USERPROFILE%\HighlightCreator\logs\error-YYYYMMDD.log`（与崩溃日志同一个，
  由 `ErrorLogger.line()` 追加，每天一个）
- 每行以 `[ai-marking]` 开头，一行一个事件，可直接 `Select-String` / `findstr` / `grep`
- **绝不记录** API key（不截断、不记长度）、完整请求体、Authorization 头，以及**原始响应
  body**——2026-10-29 那次 19 行失败日志里全是被截断的 200 body，又长又没用。失败只记
  `finish_reason` / usage / `reasoning_len` / `content_len` 这些形状字段

| 行 | 何时写 | 格式 |
|---|---|---|
| `batch` | 批量开始（读过标定之后、第一个文件之前） | `[ai-marking] batch files=<选中文件数> started` |
| `calib applied` | 批量开始时把一个文件的标定写给其它文件 | `[ai-marking] calib applied from=<文件名> files=<写入个数> boxes=<矩形数>` |
| `start` | 校验通过、抽音频之前（每个文件一行） | `[ai-marking] <file i/n >start file=<文件名> duration=<秒>s model=<模型> baseUrl=<端点> calib=<0/1/2>< candidates_before=<整批已产出候选数>>` |
| `audio` | 抽音频完成 | `[ai-marking] audio elapsed=<秒>s size=<WAV 字节数>B` |
| `motion` | 画面运动序列检测完成（仅成功时） | `[ai-marking] motion frames=<YAVG 采样数> elapsed=<秒>s mean=<1 秒窗口均值> p95=<1 秒窗口 p95> candidates=<n>` |
| `motion unavailable` | 画面运动降级 | `[ai-marking] motion unavailable elapsed=<秒>s error=<错误信息≤200 字>` |
| `detect` | 两条通道都跑完、合并结束 | `[ai-marking] <file i/n >detect audio=<声音候选数> motion=<运动候选数> merged=<合并后候选数> src_both=<n> src_motion=<n> src_audio=<n> win=peak-6s..peak+2s elapsed=<秒>s median=<全局 rms 中位数> energyFactor=<1.8 或 1.5> whistleFactor=<1.5 或 1.3> zcrFactor=<1.3> baselineWindowSec=<60> relaxed=<true/false>` |
| `cand` | 每段判定结束（成功或失败） | `[ai-marking] cand <i>/<n> in=HH:MM:SS.mmm out=HH:MM:SS.mmm win=<窗口起点−峰值 ms> src=<motion/audio/both> http=<码> verdict=<highlight/ordinary/undetermined/failed> kind=<kind> imgs=<图片张数> <秒>s prompt_tok=<n> desc=<描述≤60 字>`；`win=-6000` = 窗口正常从峰值前 6 秒开始；起点被文件头裁到 0 时大于 -6000，只在文件尾裁短时仍是 -6000 但 `out-in<8s`；重试过的段在 `prompt_tok` 后多一个 `attempts=2` |
| `error` | 单段失败（含重试后仍失败）/ 401 / 整体异常 | `[ai-marking] error cand=<i>/<n> http=<码> elapsed=<秒>s finish_reason=<值> usage.prompt_tokens=<n 或 -> usage.completion_tokens=<n 或 -> reasoning_len=<n> content_len=<n> error=<错误信息≤200 字>`；401 用 `stage=auth`（只有 http 与 error），整个流程异常用 `stage=run` |
| `degraded` | 模型不支持图片 | `[ai-marking] degraded reason=image-unsupported status=<码> firstError=<错误信息≤200 字>` |
| `cancelled` | 用户取消 | `[ai-marking] cancelled at=<已发起的段数>/<总段数>` |
| `skipped` | 单个文件失败，整批继续（批量时） | `[ai-marking] <file i/n >skipped file=<文件名> elapsed=<秒>s error=<错误信息≤200 字>` |
| `summary` | 每个文件结束（含取消、降级、失败） | 见下，字段顺序固定，前面可带 `file i/n ` |
| `batch done` | 整批结束（含取消、401 提前结束） | `[ai-marking] batch done files=<选中数> ok=<跑完数> skipped=<跳过数> highlight_total=<整批高光段数> prompt_tok=<整批输入 token> elapsed=<整批秒数>s` |

**前缀规则**（保证旧 grep 继续可用）：

- 只选了一个文件时，`start` / `detect` / `summary` **与旧格式逐字相同**（没有 `file 1/1 `
  前缀，`start` 行也没有 `candidates_before`）——单文件的日志读者不受影响；
- 批量（≥2 个文件）时，`start` / `detect` / `summary` 前面加 **`file i/n `**（i 从 1，
  n = 选中文件数），`start` 行末尾追加 `candidates_before=<进入这个文件时整批已产出的候选数>`；
- `audio` / `motion` / `cand` / `error` / `degraded` / `cancelled` 行**不加前缀**（旧 grep
  `\[ai-marking\] cand ` 原样可用）；它们属于**紧邻的上一条 `file i/n start` 与它自己的
  `file i/n summary` 之间**的那段——这就是批量日志读文件归属的方式：

```
[ai-marking] batch files=11 started
[ai-marking] file 2/11 start file=GX01123.MP4 duration=689.2s model=deepseek-flash baseUrl=… calib=2 candidates_before=47
[ai-marking] audio elapsed=8.2s size=22020123B
[ai-marking] motion frames=3446 elapsed=48.1s mean=2.31 p95=6.84 candidates=41
[ai-marking] detect audio=30 motion=41 merged=47 src_both=24 src_motion=17 src_audio=6 win=peak-6s..peak+2s elapsed=1.4s …
[ai-marking] cand 1/47 in=00:00:12.000 out=00:00:20.000 win=-6000 src=both http=200 verdict=highlight kind=goal imgs=3 2.1s prompt_tok=3190 desc=…
[ai-marking] file 2/11 summary candidates=47 highlight=4 undetermined=1 failed=0 http=200 model=deepseek-flash elapsed=183s degraded=false ordinary=42 prompt_tok=133198 completion_tok=1902 retried=1 src_both=24 src_motion=17 src_audio=6 motion_ok=true
[ai-marking] batch done files=11 ok=10 skipped=1 highlight_total=38 prompt_tok=1420000 elapsed=1980s
```

`summary` 的字段顺序（机器解析以这一行为准）：

```
[ai-marking] summary candidates=45 highlight=12 undetermined=2 failed=1 http=200 model=deepseek-flash elapsed=320s degraded=false ordinary=31 prompt_tok=112500 completion_tok=1900 retried=3 src_both=12 src_motion=40 src_audio=34 motion_ok=true
```

| 字段 | 含义 |
|---|---|
| `candidates` | **这个文件**的候选总数（= 界面里该文件分组的段数） |
| `highlight` | 判定为高光的段数 |
| `undetermined` | 未判定的段数，**包含** `failed`（失败的段也记为未判定，仍可保存为 rating 2） |
| `failed` | 其中「这一段自己失败」的段数（超时 / 5xx / 回包不是 JSON / 重试后仍为空或截断） |
| `http` | 这个文件最后一次拿到的 HTTP 状态码；一次请求都没发出时是 `-` |
| `model` | 使用的模型名（用户输入） |
| `elapsed` | 这个文件从 `start` 到结束的秒数（批量时是单文件耗时，不是整批） |
| `degraded` | 是否命中「不支持图片」降级 |
| `ordinary` | 判定为「普通」的段数（追加在固定字段之后：实现里这是第三个判定值，不记它 `candidates` 就对不上） |
| `prompt_tok` | 这个文件的输入 token 总和：**每次尝试都算**（重试的那次是第二次输入，也要计入）。优先用回包 `usage.prompt_tokens`，没有 usage 才用估算值（估算按图片张数累加、每张封顶 1024） |
| `completion_tok` | 同上，输出 token 总和；没有 usage 的段按 0 计 |
| `retried` | 这个文件实际重试的次数（每段最多 1 次；按拿到回包的尝试计，重试请求在传输层就失败时这条日志看不到） |
| `src_both` / `src_motion` / `src_audio` | 合并后候选的来源分布，**三者相加 = `candidates`** |
| `motion_ok` | **这个文件**的画面运动通道是否可用（`false` = 已降级为纯声音，此时会有对应一行 `motion unavailable`） |

前 8 个字段顺序固定；`ordinary`、`prompt_tok`、`completion_tok`、`retried`、以及
`src_both` / `src_motion` / `src_audio` / `motion_ok` 依次追加在后面
（按空白切分、再按第一个 `=` 拆 key/value 即可）。恒有
`highlight + ordinary + undetermined = candidates`；
`failed ≤ undetermined`，求和时不要把 `failed` 再加一遍；`retried ≤ failed + highlight + ordinary`。

失败行里的五个形状字段，就是 2026-10-29 那次「模型能看图，19/22 却为空」被定位出来的依据：

| 字段 | 含义 |
|---|---|
| `finish_reason` | `stop` / `length` / `-`（回包没带）；`length` = token 预算在 JSON 说完之前用光 |
| `usage.prompt_tokens` | 这次请求真实计入的输入 token（回包没有 usage 时是 `-`） |
| `usage.completion_tokens` | 输出 token；贴近 `max_tokens` 就是被截断 |
| `reasoning_len` | `reasoning_content` 的字符数，没有则 0——**思考是否在吃预算，看这个字段** |
| `content_len` | `message.content` 的字符数，0 就是「empty message in reply」 |

`cand` 行的 `verdict` 有四个取值：`highlight`（高光）、`ordinary`（普通）、
`undetermined`（未判定）、`failed`（这一段自己失败）。

`cand` 行的 `src`：`motion`（只有画面运动抓到）、`audio`（只有声音抓到）、`both`（两条通道
都抓到、合并成了一条）。**复盘的第一个问题就是"01:24 是哪个通道抓到的"**——如果那一行是
`in=00:01:24.000 ... src=motion`，说明画面通道补上了声音漏掉的扑救。

`cand` 行的 `win`：窗口起点相对峰值的毫秒偏移，正常是 `-6000`（窗口 = 峰值前 6 秒到
峰值后 2 秒，见 §窗口为什么前移）；起点被文件头裁到 0 时可能是 `-3500` 之类。
`detect` 行同时打印 `win=peak-6s..peak+2s`，两者对上就说明这一轮的窗口形状没被改回去。
`in/out` 是窗口的绝对时间（`out - in` 正常 8 秒，只在文件尾被裁短时更短），峰值时刻 =
`in - win`。

`cand` 行的 `http`：正常与 4xx/5xx 都是真实状态码，没发出去（抽帧失败、超时、网络断）是
`-`；`verdict=failed` 的段一定紧跟一行 `error cand=...`。

`cand` 行的 `imgs`：这次请求实际带上的图片张数，正常恒为 `3`（全景 + 两张放大；
有标定时是球门区，未标定时是上/下半部）；抽帧失败、一次请求都没发出时是 `0`。

`cand` 行的 `prompt_tok`：回包带 `usage` 就是真实值；不带时是估算值，前面加 `~`（估算按
图片张数累加、每张封顶 1024）；一次请求都没发出（抽帧失败）时是 `-`。重试过的段在
`prompt_tok` 之后多一个 `attempts=2`，值来自最后一次尝试的 `usage`，而 `summary` 里的
`prompt_tok` 会把两次都算上。

`start` 行的 `calib`：这个文件读到的**可用**球门矩形数。`0` = 没标定（走旧的上/下半部，
日志与旧版只差这一个字段）；`1` = 图2 是球门 1、图3 仍是下半部；`2` = 图2/图3 分别是
球门 1/球门 2。它只影响抽帧与 prompt，不影响候选列表；标定文件坏了也是 `0`。批量时这一行
是**每个文件各自**的值（自动应用之后一般是同一个数）。

`start` 行的 `candidates_before`（仅批量）：进入这个文件时整批**已经产出**的候选段数，
与界面文件级进度里的「已完成候选 N 段」同一个数；用它可以在日志里对上进度条。

`batch done` 行的字段：

| 字段 | 含义 |
|---|---|
| `files` | 选中的文件数（去重后） |
| `ok` | 实际跑完的文件数（含 0 候选、含判定期中断的那个） |
| `skipped` | 因打不开/解析失败被跳过的文件数 |
| `highlight_total` | 整批 `verdict=highlight` 的段数（= 高光列表标题里的数字） |
| `prompt_tok` | 整批输入 token 总和（各文件 `summary.prompt_tok` 相加） |
| `elapsed` | 整批秒数（从点「开始分析」到 `batch done`） |

`ok + skipped` 正常等于 `files`；**取消 / 401 提前结束时两者之和会小于 `files`**，差几个
就是没来得及跑的文件数——这是判断整批是否被中断的唯一依据。恒有
`highlight_total = 各文件 summary.highlight 之和`。

写日志失败（磁盘满、权限）只吞掉，**不影响分析**；界面没有任何新增文案。

### 怎么查

```powershell
# 最近几轮的汇总（含 src_both / src_motion / src_audio / motion_ok）
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\] summary' | Select-Object -Last 5

# 最近几批的收尾行（files / ok / skipped / highlight_total / prompt_tok / elapsed）
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\] batch done' | Select-Object -Last 3

# 某一批的文件顺序与每个文件的起点（含 candidates_before）
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\] (batch files=.* started|file \d+/\d+ start)'

# 哪些文件被跳过了
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\] file \d+/\d+ skipped'

# 某一轮的全部打点记录（start / audio / motion / detect / cand… / summary）
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\]'

# 只看失败、降级与取消（含 motion unavailable）
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\] (error|degraded|cancelled|motion unavailable)'

# 01:24 到底是谁抓到的
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern 'in=00:01:2'

# 只看只被画面运动抓到的候选
Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" `
  -Pattern '\[ai-marking\] cand .*src=motion '
```

某一批里某个 `cand` 属于哪个文件：往上找最近的 `file i/n start`（它的 `file=` 就是文件名），
直到遇到下一个 `file i/n start` 为止。同理，批量里 `error stage=run` 只表示**这个文件**的
流程异常（它后面紧跟该文件的 `summary` 与 `file i/n skipped`），不再是整批异常。

## 成本与耗时（12 分钟素材）

| 阶段 | 量 | 估时 |
|---|---|---|
| 抽音频 | 12 min → 23 MB WAV | 5–15 s（看源分辨率与码率） |
| 算画面运动 | 12 min × 5 fps ≈ 3450 个采样（4K 源要逐帧解码再缩到 320 宽） | **约 45–110 s**（实测 3840×2160：6 分钟 23.9 s、3 分钟 12.2 s，约 15× 实时；12 分钟约 45–50 s，弱机上翻倍） |
| 找候选 | 两通道各 720 个窗口 | < 2 s |
| 抽帧 | 每段 3 次 ffmpeg（三张各 8 帧：全景 + 两张放大；标定时裁球门区） | 约 1.5–4 s（3840×2160 实测 3 条约 1.4 s） |
| VLM | ≤ 60 段串行，每段最多 2 次请求（含 1 次重试），每次 3 张图 | 每段 2–6 s |
| 合计（单个 12 分钟文件） | — | **约 5–10 分钟**（候选 40–60 个；60 个时约 7–12 分钟） |
| 合计（11 个分片 ≈ 2 小时素材） | 11 × 单文件 | **约 1–2 小时**：文件之间**串行**，总耗时就是各文件之和（不并发是刻意的，见 §F）；日志里 `batch done ... elapsed=` 是实测值 |

画面运动是新增的一趟全片解码，它比抽音频慢（抽音频只解音轨）。**它的成本换的是召回**：
声音通道在固定远景机位的业余素材上召回上限本来就低（见 §B）。

token：DeepSeek 视觉文档写明**每张图最多 1024 token**，代码里的估算按张数累加、每张封顶
（`estimateInputTokens` → `maxImageTokens`）。三张图的上限约 3.5k/段；上一轮实测每张
896×1008 约 711 token，三张图约 **2100/段**（另加 prompt 文本约 0.4k/段），所以 12 分钟
素材 40–60 段约 **10 万–15 万输入 token**（估算上限约 14 万–21 万）+ **< 5 千输出**；
出现 `retried` 时每一段重试再加一份输入（同样三张图）。真实花费以日志里的 `prompt_tok` /
`completion_tok` 为准——它们来自回包 `usage`，不是估算。按 DeepSeek 当时的价格换算即可，
价格不写死在本文件里。

## 用户验证步骤

1. `cd app && flutter run -d windows`（需要 PATH 里或 `tools\ffmpeg\ffmpeg.exe` 有 ffmpeg）
2. 准备 **11 个同机位的分片**（mp4/mov/mkv，合计约 2 小时）；想验证「跳过」再截断其中一个。
3. 「我要」→「AI 打点」（该菜单项当前被注释隐藏，验证前先按文首说明取消注释）：
   粘贴 key、勾「记住」。
4. **多选**：点「选择比赛视频」，在文件对话框里用 Ctrl/Shift 一次选中 11 个 →
   文件行显示 **「已选 11 个文件（共 689.2 分钟）」**，鼠标悬停能看到按文件名排好的 11 个名字。
5. **两层进度**：点「开始分析」，进度条**上方**是文件级
   「第 1/11 个文件 · 已完成候选 0 段」，**下方**是阶段级
   「抽音频 → 算画面运动 → 找候选 → 逐段判定 i/n」；第一个文件跑完后上面变成
   「第 2/11 个文件 · 已完成候选 47 段」。
6. **高光片段**：整批跑完后对话框**上半部分**出现「**高光片段 · 共 12 段**」，下面按文件分组，
   组标题是「文件名 · N 段高光」，每行 `mm:ss–mm:ss`、kind 中文译名、模型描述。期望形状：

   ```
   高光片段 · 共 12 段
     ▸ 2026-10-25 联赛.MOV · 1 段高光
         00:12–00:20  进球  10 号禁区外远射破门，球擦立柱入网
     ▸ GX01123.MP4 · 2 段高光
         00:33–00:41  扑救  门将单掌托出角球，随后队友解围
         01:16–01:24  射门  边路传中，头球攻门被扑出
     ▸ part1.MP4 · 0 段高光
         无检出高光
     ▸ part10.MP4 · 0 段高光
         已跳过（分析失败）
     …
   ```

7. **点击归属**：点高光列表里任意一行 → 预览窗口从该段起点播 8 秒。**这段属于哪个文件**：
   看它上面最近的组标题；预览窗口放的必须是**那个文件**（不是排序后的第一个文件）。
   同一个时间点在不同分片里都可能出现，所以「01:24–01:32」到底是谁的，只能看分组标题。
8. **候选列表保留**：对话框下半部分仍是「候选片段」列表，按文件分组（「文件名 · N 段候选」），
   每行「mm:ss–mm:ss · 高光/普通/未判定 · 描述 · 查看」。整批候选段数 = 各文件
   `summary candidates=` 之和，**一个文件都没少**（判定标准与候选上限没动）。
9. **保存为项目**：点「保存为项目」→ 对话框底部显示
   `%USERPROFILE%\HighlightCreator\results\ai_marking\<首个文件名>-<日期>-<时分秒>.hlcproj`；
   打开它：`sources` 应有 **10 条**（11 个里被跳过的那 1 个不写），每条 `filePath` 是自己的文件；
   每个 `timeslots[]` 的 `videoSourceId` 指向**它自己的文件**、`filename` 与之一致；
   星级高光 = 4、未判定 = 2，普通不在文件里。
10. **单文件跳过**：把其中一个分片截断成 ffmpeg 打不开 → 该文件分组显示「已跳过（分析失败）」，
    状态行显示「1 个文件失败」，**整批继续**跑完；日志里 `file i/n skipped file=… error=…`，
    `batch done … skipped=1` 且 `ok + skipped = files`。
11. **标定自动应用**：只给排序后的第 1 个分片标定 2 个球门（**不勾**「应用到同目录所有视频」），
    然后一次选中 11 个文件「开始分析」→ 界面提示「**已将球门标定应用到 N 个文件**」，
    日志 `calib applied from=<文件名> files=N boxes=2`；每个文件的 `start` 行都是 `calib=2`；
    `%USERPROFILE%\HighlightCreator\calibration\` 下每个分片各有一个 `<sha1>.json`。
12. **取消整批**：在第 3 个文件的判定中点「取消」→ 状态变「已取消。」，**不再进入第 4 个文件**，
    `batch done` 的 `ok + skipped < files`，`temp\ai_marking` 为空，已跑完文件的结果仍在、
    「保存为项目」可用。
13. **旧行为未回归**：只选 1 个文件跑一遍 → 日志 `start` / `detect` / `summary` 行**没有**
    `file 1/1 ` 前缀、`start` 行也没有 `candidates_before`，与旧版逐字相同。
14. 降级验证：把模型改成文本模型（例如 `deepseek-chat`）再分析 → 顶部出现
    「该模型不支持图片输入…」，所有行「未判定」，请求立刻停止（整批不再跑后续文件），
    「保存为项目」仍可用（rating 2）。
15. 无效 key 验证：随便填一个 key → 「API Key 无效，已停止分析。」
16. 画面运动降级验证：把源文件改成 ffmpeg 打不开的扩展名/空文件 → 该文件顶部出现
    「画面运动不可用，仅用声音。」，但候选来自声音、这个文件正常结束，
    日志里是 `motion unavailable ...` + `summary ... motion_ok=false`。
17. 不联网也能验证候选检测：`flutter test test/services/motion_spike_detector_test.dart`
    与 `flutter test test/services/audio_spike_detector_test.dart`。
18. 复盘：跑完执行
    `Select-String -Path "$env:USERPROFILE\HighlightCreator\logs\error-*.log" -Pattern '\[ai-marking\]'`，
    应看到 `batch files=11 started` → 每个文件一段 `file i/n start` → `audio` → `motion` →
    `detect` → 每段一行 `cand`（含 `src=`、`imgs=3`）→ `file i/n summary` → 最后
    `batch done files=11 ok=10 skipped=1 highlight_total=… prompt_tok=… elapsed=…`；
    各文件 `summary` 的 `candidates` 之和 = 界面候选段数、`highlight` 之和 = 高光列表标题的数字、
    `src_both + src_motion + src_audio = candidates`、`motion_ok=true`；
    `prompt_tok` / `completion_tok` 是真实数字、`retried` 是 0 或个位数；
    仍然失败的段应紧跟一行 `error ... finish_reason=... usage.prompt_tokens=...
    usage.completion_tokens=... reasoning_len=... content_len=...`，日志里**没有**原始 body。
19. **画面运动通道的验收点**：在 11.5 分钟那份素材上，
    `Select-String ... -Pattern 'in=00:01:2'` 应出现一行 `cand ... in=00:01:24.000 ...
    src=motion ...`（上一轮它根本不在候选里）；`detect` 行里 `motion=` 应明显大于 0，
    `src_both + src_motion + src_audio = merged`。若 `motion` 为 0 且 `motion_ok=true`，
    说明这条素材上 `1.8×` 太严（见 §已知边界），先看 `motion` 行的 `mean` / `p95`
    再决定是否调阈值。
20. **球门标定界面**：选好文件后点「标定球门」（多选时标的是排序后的第一个文件）→
    应出现 30% 处的画面；拖出球门 1、球门 2 两个框（再拖一次应替换第 2 个），下方显示
    3 位小数坐标；点「保存」→ 提示「已标定 2 个球门」；`calibration\` 应出现一个
    `<sha1>.json`，`rects` 里是两个 0..1 的小数。勾「应用到同目录所有视频」再保存，
    同目录其它 mp4/mov/mkv 也各多一个 `<sha1>.json`。
21. **标定后重跑真进球（05:17 / 07:14 / 09:39）**：在 09:39 所在分片上标定两个球门
    （或勾选应用到同目录后直接选那个分片），重新「开始分析」：
    - 日志 `start` 行应为 `... calib=2`；
    - `detect` 行应带 `win=peak-6s..peak+2s`，每条 `cand` 应带 `win=-6000`（文件头尾
      被裁剪时才不是 -6000）；
    - 图像2/图3 应是球门区放大（不是上半/下半幅），三张图各 8 帧、覆盖完整 8 秒，
      失败时 `cand` 行仍写 `imgs=3`；
    - **05:17、07:14、09:39 这些上一轮判成「普通」的真进球**应从 `verdict=ordinary`
      变成 `verdict=highlight`、`kind=goal`——这是本轮两个修复（8 帧全覆盖 + 窗口前移）
      要看的直接结果；
    - 若仍是「普通」：先看那一行的 `desc=` 与 `in/out/win`，确认窗口确实覆盖了球过线的
      那 1–2 秒，再把同一时间点的三张图存下来核对球门框是否框准（框偏了会裁到观众席/
      边线），必要时重新标定。判定标准与 prompt 条款本轮未动，候选是否进入只取决于
      阈值，与标定无关。

## 已知边界

- 画面运动只认"比周围一分钟动得更厉害"：**换镜头、镜头被碰/拿起、灯光开关**都是巨大的
  帧间差异，会在候选里排到很前面（真实素材上最容易出现的一类假高光）。
  2026-10-29 用仓库里的真实业余素材验证：前 5 分钟固定机位踢球时 `YAVG` 只有 1.5–3.3
  （局部比值 < 1.8，0 个候选），最后 1 分钟有人把相机拿起来，`YAVG` 冲到 28–98，
  连出 3 个候选——**画面通道会抓住"镜头动"，这一点只能靠 VLM 那一步筛掉**，
  这也是 prompt 被收紧的原因之一。
- 阈值 `1.8×` 是照搬声音通道验证过的那一档，还没有在"进球"上标定过：远景小画面里
  禁区只占几十像素，一次射门的 `YAVG` 抬升可能不到 1.8 倍。先用本轮日志里的
  `motion=` 与 `p95` 观察，再决定要不要单独调 `MotionSpikeDetector.spikeFactor`。
- 画面运动**没有**"结果太少就放宽"的第二次机会（声音通道有）：放宽会立刻把换镜头、
  灯光变化全放进来。
- 声音通道只看"比周围一分钟更响"或"又响又高频"；安静的扑救（如 01:24）它看不到，
  这正是画面通道存在的理由。
- 相邻 5 s 以上的两个事件可能各自带出 8 秒窗口、时间上重叠；合并阶段按 **>50% 重叠**
  去重（不区分通道），所以最终列表里不会出现两条重叠大半的候选。
- 窗口被文件头/尾裁短（视频短于 8 秒，或候选紧贴文件末尾）时，拼图末尾几格会是黑格
  （`tile` 用黑格补齐，实测仍会输出 JPEG），模型看到的有效秒数随之变少，但这一段仍会
  正常发请求，不会因此整段失败。
- **相机被移动后标定失效**：矩形是相对画面的固定坐标，三脚架被碰、镜头被拿起、换了机位
  都会让球门不再落在框里——这时图2/图3 裁到的是观众席/边线，模型看到的东西反而更少。
  换机位/重新架机后必须重新标定（或删掉该源的 JSON）。同一目录批量应用只适用于
  **同一次架机、整场不动机位**的连续分片。
- 标定只放大球门区，不改变候选本身：进不了候选的片段，模型也看不到。图2/图3 的放大
  倍率取决于框的大小，框得越小倍率越高，但模型能看到的场景也越少；框太松则球门仍小。
- 未标定时上下半部放大只让"远处的动作看得清"，不改变候选本身：进不了候选的片段，模型也看不到。
- key 以明文存在 `settings.json` 的 `aiMarkingApiKey`（与其它设置同一个文件）；不勾「记住」
  时下一次会清掉它。
- **批量是串行的**：11 个文件的总耗时是各文件耗时之和，不会因为多选而变快，这是刻意的
  （并发会同时触发限流与 CPU 争抢，还让「取消」变得难以收拾）。想让 2 小时素材快一点，
  只能换更快的机器/更短的候选，而不是并发。
- **每个文件的候选上限仍是 60**：批量不会因为文件多而压缩单个文件的候选数量，也不会合并
  不同文件的候选；47 段就是 47 段，高光判定标准与单文件时完全一致。
- **跳过 ≠ 失败**：跳过的文件不写进 `sources[]`（它没被分析，`durationMs` 也没有可信值），
  但它会以「已跳过（分析失败）」的分组留在高光列表里，界面同时显示「N 个文件失败」；
  重新分析只跑选中的文件，跳过的那个会再试一次（想修好它就先修文件）。
- **同目录标定会被批量覆盖**：批量开始时的自动应用会写同目录**所有** mp4/mov/mkv 的标定
  （`applyToSiblings` 的原有语义）。两个选中文件带不同矩形时，后写的赢——同一机位是前提，
  换机位/换场次必须重新标定；这是已知边界，不是 bug。
- **ffprobe 不可用**时「已选 N 个文件（共 — 分钟）」显示破折号，分析照常跑（`start` 行的
  `duration` 也是 `-`，候选会失去首尾裁剪的时长依据，但不会失败）。
- **整批 0 段高光**（全部文件都只有「普通」）时「保存为项目」不写文件，提示「没有判定为
  高光的候选，未写出项目文件。」；想留一份候选清单，得先让模型不可用（降级）或手动改
  判定标准——这是既有规则，本轮没动。
- 高光列表与候选列表各自有固定高度（190 / 220 px）并在对话框内滚动；11 个文件 × 几十段
  时它们都能滚，但一次只看得到几组——分组标题的 `文件名 · N 段高光` 是唯一的定位依据。
