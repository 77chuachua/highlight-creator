# Windows UI Design — Table of Contents

> **Version**: 1.1  
> **Date**: 2026-08-31  
> **Target Platform**: Windows 10 / 11 Desktop  
> **Framework**: Flutter with Material 3

---

## Documents

| File | Description |
|---|---|
| [layout.md](layout.md) | Main window layout, panel arrangement, responsive breakpoints |
| [components.md](components.md) | Detailed specs for each UI component |
| [style-guide.md](style-guide.md) | Color palette, typography, spacing, iconography |

## Design Principles

1. **Desktop-first** — Optimized for 1920×1080 minimum, mouse + keyboard primary input
2. **Single-window** — All tools visible in one resizable window; no modal workflows
3. **Dark default** — Dark theme as primary, light theme available
4. **Keyboard-driven** — Every action has a keyboard shortcut; power-user friendly
5. **Immediate feedback** — No save buttons; all changes are auto-persisted

## Window Layout Overview

```
┌─ Title Bar ───────────────────────────────────────────────────────┐
│  🎬 Highlight Creator — MyProject.hcp                    ─ □ ×   │
├─ Toolbar ─────────────────────────────────────────────────────────┤
│  [📹 Open Video] [📂 New Project] │ [↩ Undo] [↪ Redo] │ Project  │
├───────────────────────────────────┬───────────────────────────────┤
│                                   │  📁 Source Files              │
│                                   │  ┌──────────────────────────┐ │
│         VIDEO PLAYER              │  │ 📹 match1_first_half.mp4 │ │
│         (16:9 aspect)             │  │ 📹 match1_second_half.mp4│ │
│                                   │  │ 📹 post_game_interview   │ │
│     ┌───────────────────────┐     │  │                          │ │
│     │     ▶  ═══════●══════ │     │  │  + Add Video Files       │ │
│     │  01:23.5 / 05:30.0    │     │  └──────────────────────────┘ │
│     └───────────────────────┘     │                               │
│                                   │  🎨 Thumbnail Strip           │
│                                   │  ┌──────────────────────────┐ │
│                                   │  │[■][■][■][■][■][■][■][■] │ │
│                                   │  └──────────────────────────┘ │
├───────────────────────────────────┴───────────────────────────────┤
│  🎛️ Control Panel                                                  │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ [⏮ -5s] [▶ Play] [⏭ +5s] [■ Stop]  │ Speed: [1.0x ▼]      │ │
│  │ [🏁 Mark In (I)] [🚩 Mark Out (O)]  │ [↩ Undo] [↪ Redo]     │ │
│  └──────────────────────────────────────────────────────────────┘ │
├───────────────────────────────────────────────────────────────────┤
│  📋 Timeslots                                                     │
│  ┌─────┬────────────┬──────────┬──────────┬────────┬────────────┐ │
│  │  #  │ Label      │ In Point │ Out Point│ Rating │ Actions    │ │
│  ├─────┼────────────┼──────────┼──────────┼────────┼────────────┤ │
│  │  1  │ Goal!!     │ 00:15.30 │ 00:22.10 │ ★★★★☆  │ ✏️ 🗑️     │ │
│  │  2  │ Red Card   │ 00:45.00 │ 00:48.50 │ ★★☆☆☆  │ ✏️ 🗑️     │ │
│  │  3  │ Save       │ 01:12.20 │ 01:18.70 │ ★★★★★  │ ✏️ 🗑️     │ │
│  └─────┴────────────┴──────────┴──────────┴────────┴────────────┘ │
├─ Status Bar ──────────────────────────────────────────────────────┤
│  Project: MyProject │ 3 timeslots │ Timeline: 00:00 – 05:30      │
└───────────────────────────────────────────────────────────────────┘
```

## Responsive Breakpoints

| Width | Layout |
|---|---|
| ≥ 1400px | Full layout: player left, files right, timeline bottom |
| 1100–1399px | Player + controls full width, files + timeslots as collapsible drawers |
| 800–1099px | Single-column: player on top, everything else stacked below |
| < 800px | Mobile-style: one panel at a time with tab navigation |
