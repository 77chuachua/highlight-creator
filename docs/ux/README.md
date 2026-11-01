# UX 原型（HTML）

`docs/ux/` 是 **Highlight Creator 全界面**的静态原型，逐屏对照当前实现绘制：
主窗口（播放器 / 源文件 / 模板面板 / 控制条 / 时间轴 / 时间片段表 / 状态栏）、各对话框、
五佳球两步流程、语音工作室、手机打点、AI 打点。
用浏览器直接打开 `index.html` 即可，无需构建、无需联网。

## 页面

| 文件 | 界面 | 对应实现 |
|---|---|---|
`index.html` | 总览：界面清单、设计令牌、尺寸字号、角色与产物 | — |
`main-window.html` | 主窗口全貌：40px 工具栏（项目菜单 / 项目名 / 设置）、播放器 + 20px 折叠条 + 320px 右栏（源文件 + 四组模板面板）、56px 控制条（跳转 / 标记 / 速度 / 我要）、时间轴（收起 / 展开）、200px 时间片段表、状态栏；含空项目与「我要」菜单展开态 | `main_window.dart`、`control_panel.dart`、`player_screen.dart`、`source_file_list.dart`、`template_panel.dart`、`timeline_track.dart`、`timeslot_table.dart`、`status_bar.dart` |
`template-editor.html` | 模板编辑器（开场/转场/结尾、字体/字号/颜色/位置、实时预览）、模板面板（选中 / 未配置 / 背景音乐变体）、预览与确认（分辨率、确认并制作、正在渲染、缺少模板文件） | `template_editor_dialog.dart`、`template_panel.dart`、`preview_dialog.dart`、`control_panel._make()` |
`marking-dialogs.html` | 前往时间（空 / 已填 / 非法 + 三种提示条）、时间片段分类明细（进攻/防守/未分类 + 复制）、放大定位点（正常 / 取帧失败）、新手指引（8 步） | `go_to_dialog.dart`、`clip_breakdown_dialog.dart`、`zoom_in_point_dialog.dart`、`guide_dialog.dart` |
`phone-marking.html` | 手机打点：二维码 / 监听地址 / 令牌 / 打开·停止；运行中、已停止、无局域网、启动失败 | `phone_marking_dialog.dart`、`docs/phone_marking.md` |
`settings.html` | 设置：主题 / 语言 / 快捷键 / 新手指引 / 关于，以及主题与语言两个单选对话框 | `settings_screen.dart` |
`top5-picker.html` | 五佳球步骤 1 · 选择（含「已恢复 …的成片」标签：`5best_clips` 里有本周期的成片就自动回填名次与解说） | `top5_dialog.dart → _buildPicker() / _restoreFromCache()` |
`top5-editor.html` | 五佳球步骤 2 · 预览与解说（语音行、seed 输入行（默认 50，0–4294967295，越界提示）、错误条；单播放器预览、点同片段直接播放、模态；试听保存最后一版 take、▶ 回放并显示 seed、生成时复用；预览黑屏的日志与自愈） | `_buildEditor() / _buildVoiceRow() / _buildSeedRow() / _commentList() / _preview() / _previewVoice() / _playTake()` |
`top5-generated.html` | 已生成（观看/重新生成/关闭）+ 生成中状态 | `_footer()` |
`dialogs.html` | 语音包指南、导入语音包、缓存文件、清空确认 | `voice_pack_guide_dialog.dart`、`cache_dialog.dart`、`_importVoicePack()` |
`ai-marking.html` | AI 打点：批量判定中（多选 + 两层进度）/ 批量完成（高光片段列表 + 分组候选）/ 模型不支持图片（降级）/ 画面运动不可用 / 球门标定（**「我要」里的入口菜单项当前被注释隐藏**） | `ai_marking_dialog.dart`、`ai_marking_batch.dart`、`goal_calibration_dialog.dart`、`ai_marking_service.dart`、`docs/ai_marking.md` |
`studio.html` | 语音工作室五步（⑤ 试听带 seed 输入框：默认 42，范围 0–4294967295） | `voice_clone/studio/studio.html` |
`assets/proto.css` | 共用样式（令牌、对话框框架、面板、按钮） | 与 `_gold`/`_ink` 等常量一致 |

## 约定

- **令牌唯一来源是代码**：颜色、尺寸取自代码
  （`_gold = #F2B933`、`_ink = #0A0A0C`、五佳球对话框 `1140×720`、主窗口 `1280×720`、名次徽章 `20px` 等）。
  改界面时先改代码，再回到这里同步。
- **文案逐字复制**：原型里的中文一律与实现里的字符串（`l10n.dart` 的 `_zh`）一致，方便评审时对比。
- 原型是**静态**的：没有 JS 交互，状态用并列的页面/片段展示（例如"生成中"与"已生成"）。
- **图标是替身**：应用里用的是 Material Icons，原型里用 emoji / 符号代替
  （▶ ✕ ⊘ ⟳ 等），评审时按位置和含义看，不要按字形看。
- **二维码、截图是占位**：手机打点的二维码用纯 CSS 画，新手指引的截图是占位框（仓库里没有对应 png，
  真 `<img>` 会让 `check.py` 报缺文件）。
- 新增界面时：加一个页面 + 在每页顶部 `nav`（`main-window / template-editor / marking-dialogs /
  phone-marking / settings / top5 三页 / dialogs / studio / ai-marking`）+ `index.html` 的清单里各加一条。

## 校验

修改原型后跑一次（标准库实现，检查标签平衡与本地引用是否存在）：

```bat
python docs\ux\check.py
```

全部页面通过时会打印 `N 个页面全部通过`（N = 目录下的页面数，随新增页面自动变化）。

## 与文档的关系

- `docs/voice_clone.md` —— 插件的安装、语音包格式、常见问题、进程协议
- `docs/ai_marking.md` —— AI 打点的流程、候选阈值、模型契约、降级行为
- `docs/phone_marking.md` —— 手机打点：代理转码、Range、令牌
- `docs/template_plugins.md` —— 模板插件（另一套扩展点）
- `docs/BUILDING.md` —— 构建与测试命令

原型只负责"长什么样"；行为与参数以代码和上面几份文档为准。
