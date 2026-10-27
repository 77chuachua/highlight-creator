# UX 原型（HTML）

`docs/ux/` 是五佳球与本地语音克隆功能的**静态界面原型**，逐屏对照当前实现绘制。
用浏览器直接打开 `index.html` 即可，无需构建、无需联网。

## 页面

| 文件 | 界面 | 对应实现 |
|---|---|---|
`index.html` | 总览：界面清单、设计令牌、尺寸字号、角色与产物 | — |
`top5-picker.html` | 五佳球步骤 1 · 选择 | `top5_dialog.dart → _buildPicker()` |
`top5-editor.html` | 五佳球步骤 2 · 预览与解说（含语音行与错误条） | `_buildEditor() / _buildVoiceRow() / _commentList()` |
`top5-generated.html` | 已生成（观看/重新生成/关闭）+ 生成中状态 | `_footer()` |
`dialogs.html` | 语音包指南、导入语音包、缓存文件、清空确认 | `voice_pack_guide_dialog.dart`、`cache_dialog.dart`、`_importVoicePack()` |
`studio.html` | 语音工作室五步 | `voice_clone/studio/studio.html` |
`assets/proto.css` | 共用样式（令牌、对话框框架、面板、按钮） | 与 `_gold`/`_ink` 等常量一致 |

## 约定

- **令牌唯一来源是代码**：颜色、尺寸取自 `top5_dialog.dart`
  （`_gold = #F2B933`、`_ink = #0A0A0C`、对话框 `1140×720`、名次徽章 `20px` 等）。
  改界面时先改代码，再回到这里同步。
- **文案逐字复制**：原型里的中文一律与实现里的字符串一致，方便评审时对比。
- 原型是**静态**的：没有 JS 交互，状态用并列的页面/片段展示（例如"生成中"与"已生成"）。
- **图标是替身**：应用里用的是 Material Icons，原型里用 emoji / 符号代替
  （▶ ✕ ⊘ ⟳ 等），评审时按位置和含义看，不要按字形看。
- 新增界面时：加一个页面 + 在每页顶部 `nav` 与 `index.html` 的清单里各加一条。

## 校验

修改原型后跑一次（标准库实现，检查标签平衡与本地引用是否存在）：

```bat
python docs\ux\check.py
```

六个页面通过时会打印 `6 个页面全部通过`。

## 与文档的关系

- `docs/voice_clone.md` —— 插件的安装、语音包格式、常见问题、进程协议
- `docs/template_plugins.md` —— 模板插件（另一套扩展点）
- `docs/BUILDING.md` —— 构建与测试命令

原型只负责"长什么样"；行为与参数以代码和上面三份文档为准。
