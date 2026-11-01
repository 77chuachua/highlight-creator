# 本地语音克隆插件（语音包）

五佳球的「我的声音」不是内置功能：它依赖一个**单独安装、单独升级**的插件。
插件不随安装包分发，因为运行时需要 Python + CUDA + 5 GB 模型（整套约 15 GB），
装进安装包会让每个用户都背一份。

装好之后，插件提供两样东西：

| 组成 | 作用 | 位置 |
|---|---|---|
| 引擎（worker.py） | 把文字合成成你的声音 | `%USERPROFILE%\HighlightCreator\voice_clone\` |
| 语音工作室（studio） | 录音、试听、保存语音包 | 同上 `studio\` |

插件与应用的唯一契约是 `voice_clone\plugin.json`。

界面原型（静态，浏览器直接打开）：[`ux/index.html`](ux/index.html)。应用只读这个清单，不猜路径，
所以换引擎（新版本 CosyVoice、云端后端）只需要换一份清单。

## 一、要求

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10 / 11，64 位 |
| 显卡 | NVIDIA，**显存 ≥ 6 GB**（RTX 3060 笔记本 6 GB 可用，已实测） |
| 无独显 | 可跑 CPU 模式，速度慢 5~10 倍 |
| 磁盘 | **≥ 20 GB**（venv + 源码 + 5.2 GB 模型） |
| Python | **3.10 ~ 3.11**（安装器会在缺 venv 时用系统 Python 创建） |
| 网络 | 首次安装需要（下模型与依赖），之后全离线 |

> 音频不会离开本机：没有云端调用，参考音频和合成结果都只写在本机磁盘上。

## 二、安装

在仓库根目录执行：

```bat
tools\voice_clone\setup.bat
```

`setup.bat` 是一个单行启动器，真正的逻辑在 `setup.py`。它会依次完成：

1. **仓库**：浅克隆 CosyVoice 到引擎目录，并拉取 `third_party/Matcha-TTS` 子模块
2. **虚拟环境**：创建 `venv`
3. **依赖**：装 CosyVoice 的 requirements，并**强制安装 CUDA 版 torch**
   （PyPI 的 Windows 轮子是 CPU-only，必须显式指定 `--index-url .../cu121`）
4. **模型**：从 ModelScope 拉 `CosyVoice2-0.5B`（5.2 GB，支持断点续传）
5. **worker + 工作室**：复制 `worker.py` 与 `studio\`
6. **清单**：写 `plugin.json`

安装器是**可重入**的：中断后重跑会跳过已完成的步骤。
想先看状态而不下载任何东西：

```bat
tools\voice_clone\setup.bat --check
```

装完会做一次试加载（`worker.py --prefetch`），打印 `ready` 即成功。

## 三、验证

1. 打开应用 → 五佳球 → 「解说语音」下拉框里应出现 `语音包 · …`
2. 点「创建语音包」→ 浏览器打开语音工作室
3. 照着提示词读一段（7~10 秒）→ 试听 → 保存
4. 回到应用，列表里出现新语音包

工作室单独运行也可以：

```bat
%USERPROFILE%\HighlightCreator\voice_clone\studio\studio.bat
```

### 一套音色，生成多个语音包

工作室支持「载入已有语音包」后只换语调、换文本，再另存：

1. ① 选一个已有语音包 → 「载入」（音色和它的语调都会带过来）
2. ④ 换一个语调参考（或「清除」用你原本的语调）
3. ⑤ 在文本框里输入任意句子，**seed 填 42（默认）或任意 0 – 4294967295 的整数** →「试听」确认
4. ⑥ 改个名字（默认已填「<原名> 改语调」）→「保存」

同名不会覆盖，会自动变成 `<名字> (2)`。回到应用的「解说语音」下拉即可看到全部语音包。

### 五佳球里的「试听 → 生成」（抽卡）

克隆出来的每一版质量不一样，所以**试听就是抽卡**，而抽到哪一版由 **seed** 决定：

1. 步骤 2 的语音行下面有 `seed` 输入框：默认 **50**，范围 **0 – 4294967295**。
   超出范围（或不是整数）时输入框变红、右侧提示变成「⚠ seed 必须是 0 – 4294967295 之间的整数」，
   此时「试听」和「生成」都拒绝执行。
2. 每条解说点一次 🔊「试听这句解说」= 用当前 seed 重新克隆一版并播放；改 seed 再点 = 换一版。
3. 听到满意的那一版，卡片状态会变成 `解说:我的声音(本地克隆 · 用已试听版本)`
4. 试听右边的 ▶「播放上次试听」直接放保存下来的那一版，**不重新克隆**（没有 take 时按钮是灰的）；
   ▶ 右边的 `seed 123456789` 就是那一版的种子。
5. 点「生成」时，只要台词和语音包没变，**直接复用最后试听的那一版，不再克隆**。

seed 与可复现性（2026-10-30 实测，本机 fp16 / CosyVoice2-0.5B）：

- 同文本 + 同参考录音 + 同 `seed`：直接调 `inference_zero_shot` 连跑 3 次（每次前
  `set_all_random_seed(42)`），**PCM 数据完全相同**——53,760 个样本逐点差值 0；
  二进制不同只是因为 WAV 头里 PEAK 块记的保存时间戳差了 1 个字节（偏移 60）。
  产物留在 `C:\Code\temp\repeat_0..2.wav`。
- 换 `seed`：换的是采样到的语音 token 序列，得到另一版（音色/韵律都会变）。
  所以 seed 是「抽到哪一版」，不是音质旋钮；同一 seed 只能复现同一版，不会变好。
- 应用保存的是**音频字节**而不是「记住 seed 重放」：换机器/换显卡/换引擎版本/改 fp16，
  同一 seed 不保证逐位一致；存下来的 wav 才能保证「生成的就是你听到的那一版」。
- 把应用里显示的 seed 填进语音工作室 ⑤ 的 seed 输入框，可以在工作室里复现同一版
  （前提：同一个语音包、同一句文本、同样的语速/语调/指令）。
- 工作室的 seed 输入框范围 **0 – 4294967295**，默认 **42**（上限来自 `numpy.random.seed`；
  worker 把它原样交给 `set_all_random_seed`）。填非法值会直接报错，不会静默回退。
- 工作室的 `studio.py` / `studio.html` 由 `tools\voice_clone\setup.bat` 复制到
  `%USERPROFILE%\HighlightCreator\voice_clone\studio\`：改了这两个文件后要重跑一次 `setup.bat`
  （或直接用 `studio-debug.bat`，它跑仓库里的源码）才生效。

细节：

- take 保存在 `%USERPROFILE%\HighlightCreator\temp\5best_narration\takes\`，
  每条解说一个 `<片段 id>.wav` + 一个 `.sig`（记录它是哪段台词、哪个语音包、语速/语调参数、
  以及抽中它的 seed）。在「我要 → 查看缓存 → 五佳球配音」里清理时一起清掉，清掉后生成会重新克隆。
- 改了台词、换了语音包或改了语速/语调参考，签名对不上，旧 take 自动失效（否则念的就不是屏幕上的字）。
  重新录了同一个语音包（`reference.wav` / `style.wav` 变了）也会失效，不会拿旧音色顶上。
- 不试听直接点生成：用 seed 输入框里的值（默认 50）克隆；同一个 seed + 同一句话每次结果一样，
  想换一版就改 seed 再试听。

### 服务生命周期（不会再留下死服务）

| 行为 | 结果 |
|---|---|
默认端口 | **固定 17321**（`--port 0` 才是随机） |
重复启动 | 探测到已在运行 → 只打开那个页面然后退出，不会起第二个服务 |
页面「重启服务」 | 拉起新进程后自己退出，端口不变，页面自动重连 |
页面「关闭服务」 | 先杀录音进程与引擎，再退出 |
关掉标签页 | 页面每 60 秒发一次心跳；心跳停止后 **15 分钟自动退出**（`--idle-minutes 0` 关闭） |

> 为什么要靠页面关：工作室常常是**提权**运行的（应用以管理员启动时子进程也提权），
> 普通权限的任务管理器会报 `Access is denied`。页面里的「关闭服务」是进程自杀，不受限制。

不打开浏览器也能验证（一条命令跑完 状态 → 录音 → 载入语音包 → 自定义文本试听 → 保存）：

```bat
cd %USERPROFILE%\HighlightCreator\voice_clone\studio
..\venv\Scripts\python.exe -X utf8 selftest.py --start
```

工作室先从 `PATH` 找 ffmpeg；找不到时再加 `--ffmpeg "<任意 ffmpeg.exe 的路径>"`。
从应用里点「创建语音包」时应用会自动传入，平时不用管。

它会自己启动工作室、录 3 秒、走一遍克隆、然后停掉，逐项打 `[OK]/[FAIL]`，失败时退出码非 0。

| 参数 | 作用 |
|---|---|
`--seconds N` | 录多久，默认 3 |
`--no-preview` | 跳过试听（省掉 20~40 秒的模型加载） |
`--save 名字` | 顺便保存一个语音包（测完后自己删） |
`--url URL` | 测一个已经开着的工作室，不自己启动 |
`--log 文件` | 把工作室的输出（含引擎日志）写进文件，排查用 |

## 四、语音包格式

一个语音包就是一个文件夹，可以直接拷给别人：

```
我的声音.voicepack\
├── manifest.json     {schema:1, name, createdAt, engine, referenceSeconds,
│                      sampleRate, speed, instruct, promptText}
├── reference.wav     16bit 单声道 44.1kHz，3~30 秒（你的音色）
├── style.wav         可选，语调参考（沿用它的语气，保留你的音色）
└── preview.wav       可选，试听样本
```

- 放在 `%USERPROFILE%\HighlightCreator\voices\` 下，应用启动时自动扫描
- 也可以在应用里点「导入」，选一个 `.voicepack` 文件夹，或直接选一个录音文件（会自动转换）
- `speed` / `instruct` / `promptText` 是**发声参数**，跟着包走：
  在应用里选中这个包，合成时用的就是它们（所以在工作室里听到的效果能被复现）
  - `speed` 语速 0.85~1.30（引擎对频谱插值，放慢会同时变低沉）
  - `instruct` 自然语言语气指令，如「用激动的语气喊出这句话」；留空则不启用。
  引擎要求指令以 `<|endofprompt|>` 结尾（见引擎 `example.py`），worker 会自动补上；
  少了这个标记，模型会把指令当成正文一起念出来
  - `promptText` 参考录音真正念的内容，引擎用它做对齐；留空则用引导语
- 参考录音**下限 3 秒**（太短音色不稳），**上限 30 秒**（引擎的语音分词器硬限制，
  超了自动裁到最后 30 秒）

## 五、常见问题

**「我的声音」生成出来飘忽不定？**
引擎的语音 token 是采样的，所以同样的文字每次都是一次新的「抽卡」。
在应用里点「试听这句解说」，每点一次换一个随机种子出一版，满意了再点生成——
生成会复用最后试听的那一版（见上文「五佳球里的『试听 → 生成』」）。
命令行/工作室里想换版本，设环境变量 `HIGHLIGHT_TTS_SEED`（默认 42）或给 worker 的请求加 `seed` 字段。

**显存不足 / 加载失败？**
6 GB 卡需要 fp16，安装器已默认开启；关掉其它占显存的程序。
安装器会在 fp16 失败时自动回退 fp32（更慢、更占显存）。

**拉不到模型？**
在 ModelScope 上手动下载 `CosyVoice2-0.5B`，解压到
`voice_clone\models\CosyVoice2-0.5B\`，要求该目录下存在 `cosyvoice2.yaml`。

**录音提示没有声音？**
工作室用 ffmpeg 的 dshow 采集。先在 Windows 设置里确认麦克风可用，
再在工作室里点「刷新麦克风」选中正确的设备。

**点「创建语音包」只提示"语音列表已刷新"，没有窗口出现？**
启动器的退出码和错误行现在会显示在对话框里。手动运行可以看完整输出：

```bat
%USERPROFILE%\HighlightCreator\voice_clone\studio\studio.bat --no-browser
```

最常见的原因是 `studio.bat` 被编辑器/解压工具改成了 **LF 行尾**——cmd 会把整个文件
当成一行，第二条命令起全部报 `'xxx' is not recognized`。这个文件必须是 **CRLF + 纯 ASCII**；
`setup.bat` 每次都会重新写成 CRLF，所以重跑一次安装即可修好。

**关掉页面后还能看到 python 进程？**
15 分钟内会自己退出（心跳停了才开始计时）。想立刻结束：重新打开 `studio.bat`
（会复用同一个服务），点页面底部「关闭服务」。

**「创建语音包」直接打开了指南？**
说明 `plugin.json` 里的 `studio` 路径不存在——插件没装完整，重跑 `setup.bat`。

**升级插件？**
重跑 `setup.bat` 即可；语音包和 `voices\` 不受影响。

## 六、卸载

删除 `%USERPROFILE%\HighlightCreator\voice_clone\` 整个目录即可
（约 15 GB）。语音包在 `voices\` 下，可单独保留。

也可以在应用「我要 → 查看缓存」里看到相关缓存占用并清理。

## 七、给开发者的接口

`plugin.json`：

```json
{
  "schema": 1,
  "kind": "tts-clone",
  "name": "CosyVoice2 本地克隆",
  "version": "1.0.0",
  "protocol": "hlc-voice-jsonl/1",
  "engine": "cosyvoice2",
  "python": "venv\\Scripts\\python.exe",
  "worker": "worker.py",
  "repo": "CosyVoice",
  "model": "models\\CosyVoice2-0.5B",
  "studio": "studio\\studio.bat",
  "limits": { "minReferenceSeconds": 3, "maxReferenceSeconds": 30 }
}
```

进程协议（`protocol: hlc-voice-jsonl/1`）：向 `python worker.py` 的 stdin 写一行 JSON，
从 stdout 读一行 JSON。

```json
// 请求
{"text":"解说词","prompt_text":"参考音频对应文本","reference":"…\\reference.wav",
 "output":"…\\out.wav","prosody_reference":"…\\style.wav",
 "speed":1.0,"instruct":"…（可选，instruct 模式）","seed":123456789}
// 省略 seed 时用进程的 HIGHLIGHT_TTS_SEED（默认 42）；应用里的试听每次都传一个新 seed

// 成功
{"ok":true,"path":"…\\out.wav"}
// 失败
{"ok":false,"error":"…"}
```

开发时想改工作室源码，用 `tools\voice_clone\studio\studio-debug.bat`：

- 代码：本仓库 `tools\voice_clone\studio\studio.py` / `.html`（改完重启即生效）
- 引擎：已安装插件的 `voice_clone\`（venv + 模型 + worker），靠环境变量
  `HIGHLIGHT_STUDIO_PLUGIN` 指过去
- ffmpeg：仓库自带的 `tools\ffmpeg\ffmpeg.exe`，不用手输
- 端口 **17322**（可与正常工作室的 17321 同时开），`--idle-minutes 0` 不会自己退；
  额外参数会被透传（例如 `studio-debug.bat --port 0`）

工作室的 HTTP 接口（仅监听 `127.0.0.1`，默认端口 17321）：

| 方法 | 路径 | 作用 |
|---|---|---|
GET | `/api/state` | 提示词、示例句、麦克风列表、语音包列表、引擎状态、当前录音 |
GET | `/api/packs` 等价信息 | 在 `/api/state` 的 `packs` 字段里：`{id, name, seconds, hasStyle}` |
POST | `/api/packs/load` | `{id}` 载入已有语音包：用它的 reference 当音色、style 当语调 |
POST | `/api/record/start` | `{device}` 开始录音 |
POST | `/api/record/stop` | 停止并返回 `{seconds, peak, envelope}` |
POST | `/api/style` | 原始音频字节（`X-Filename`），转成语调参考 |
POST | `/api/style/clear` | 清除语调参考 |
GET | `/api/ping` | 身份探测：`{app:"hlc-studio", pid, port, started}`，页面也用它做心跳 |
POST | `/api/restart` | 拉起新进程后自己退出，端口不变 |
POST | `/api/quit` | 先杀录音进程与引擎，再退出 |
POST | `/api/preview` | `{text, speed, instruct, promptText}` 合成指定文本，返回 `{seconds, peak, envelope}` |
POST | `/api/save` | `{name, speed, instruct, promptText}` 保存成语音包，返回 `{dir, name, seconds}` |
GET | `/api/audio/take` | 当前录音的 WAV 字节 |
GET | `/api/audio/preview` | 试听克隆的 WAV 字节 |

音频走独立的二进制端点而不是塞进 JSON：base64 把响应撑到数百 KB 后，
连接会在传输中途被重置。

`prosody_reference` 可选：给了就走两段式（先用它生成语调草稿，再做音色转换），
不给就是普通的零样本克隆。输出固定为 PCM16 WAV。
