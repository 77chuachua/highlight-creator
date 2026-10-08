# Windows UI — Component Specifications

> Detailed specs for each UI component. See [layout.md](layout.md) for positioning.

---

## 1. VideoPlayerPanel

**Purpose**: Displays video content with playback controls overlay.

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `videoPath` | `String?` | `null` | Path to loaded video file |
| `isPlaying` | `bool` | `false` | Current playback state |
| `position` | `Duration` | `0` | Current playback position |
| `duration` | `Duration` | `0` | Total video duration |
| `playbackSpeed` | `double` | `1.0` | Playback speed multiplier |
| `volume` | `double` | `1.0` | Audio volume 0.0–1.0 |
| `onSeek` | `ValueChanged<Duration>` | — | Seek callback |
| `onPlayPause` | `VoidCallback` | — | Play/pause toggle |
| `onSpeedChange` | `ValueChanged<double>` | — | Speed change callback |

### Visual States

**Idle (no video)**
```
┌─────────────────────────────────────┐
│                                     │
│          ┌──────────────┐          │
│          │  📹  Drop     │          │
│          │  video file   │          │
│          │  or click     │          │
│          │  Open         │          │
│          └──────────────┘          │
│                                     │
└─────────────────────────────────────┘
```
- Dashed border (`Border(bottom: BorderSide(style: dashed))`)
- Background: `Colors.grey[900]`
- Icon: `Icons.video_library_outlined`, size 48, opacity 0.38

**Loading**
- Centered `CircularProgressIndicator(strokeWidth: 3)`
- Text below: "Loading video..."

**Error**
- Centered `Icons.error_outline`, size 48, color `Colors.red`
- Error message text
- `OutlinedButton("Dismiss")` to clear error

### Implementation Notes
- Use `AspectRatio(aspectRatio: 16/9)` for the video surface
- Overlay controls use `AnimatedOpacity` for fade in/out
- Keyboard listener on the panel (not the window) for shortcuts

---

## 2. SourceFileList

**Purpose**: Lists all video files added to the current project.
Includes a collapse/expand arrow on the left side of the header bar.

### Collapse / Expand
A small ▶ arrow on the left of the header toggles the file list body.
The arrow rotates 90° (▼) when expanded. When collapsed only the header bar
remains visible, freeing space for the template panels below.

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `files` | `List<VideoSource>` | `[]` | Source files |
| `selectedId` | `String?` | `null` | Currently selected file ID |
| `onSelect` | `ValueChanged<String>` | — | Selection callback |
| `onRemove` | `ValueChanged<String>` | — | Remove callback |
| `onAdd` | `VoidCallback` | — | Open file picker |

### Item Layout

```
┌────────────────────────────────────┐
│ 📹 filename.mp4                    │  ← 14px, white, bold
│    Duration: 45:30                 │  ← 12px, grey, monospace
│    1920×1080 · H.264 · 30fps      │  ← 11px, grey
└────────────────────────────────────┘
```

- Selected item: background `primaryContainer` with left border accent
- Each item: 72px height, 8px horizontal padding
- Hover: background opacity change

### Implementation
- `ListView.builder` with fixed item extent
- Drag-and-drop support via `DragTarget<File>`
- Right-click context menu via `showMenu()`

---

## 3. ThumbnailStrip

**Purpose**: Horizontally scrollable strip of video frame thumbnails for quick navigation.

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `thumbnails` | `List<ThumbnailData>` | `[]` | Thumbnail metadata |
| `currentIndex` | `int` | `0` | Current position index |
| `onThumbnailTap` | `ValueChanged<int>` | — | Seek callback |

### Thumbnail Item
- Width: 80px, Height: 45px (16:9)
- Border radius: 4px
- Current: 2px solid `primary` border
- Others: 1px solid `Colors.white24` border
- Hover: scale to 1.05×, elevation 4

### Implementation
- `SingleChildScrollView(scrollDirection: Axis.horizontal)` containing a `Row` of thumbnail widgets
- Each thumbnail is a `GestureDetector` wrapping a `Container` with a background color (placeholder) or `Image` (Phase 3)

---

## 4. ControlPanel

**Purpose**: Transport controls, mark in/out, speed, zoom, volume.

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `isPlaying` | `bool` | `false` | Playback state |
| `speed` | `double` | `1.0` | Current speed |
| `volume` | `double` | `1.0` | Current volume |
| `zoomLevel` | `double` | `50` | px per second |
| `canMarkIn` | `bool` | `true` | Mark In enabled |
| `canMarkOut` | `bool` | `false` | Mark Out enabled (only after Mark In) |
| `canUndo` | `bool` | `false` | Undo available |
| `canRedo` | `bool` | `false` | Redo available |
| `callbacks` | — | — | All action callbacks |

### Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│ │ Transport          │ │ Marking           │ │ Speed    │ │ Zoom       │ │
│ │ [⏮] [▶/⏸] [⏭] [■] │ │ [🏁 In] [🚩 Out]  │ │ [1.0x ▼] │ │ [1s][5s]  │ │
│ │                    │ │                   │ │          │ │ [10s][30s] │ │
│ │ Volume: [══●═════] │ │                   │ │          │ │            │ │
│ │                    │ │                   │ │          │ │ [↩] [↪]   │ │
└──────────────────────────────────────────────────────────────────────────┘
```

### Button Specs

| Button | Size | Color | Active State |
|---|---|---|---|
| Transport (⏮ ▶ ⏭ ■) | 36×36 | `Colors.white70` | `primary` when playing |
| Mark | 110×34 | `Colors.amber.shade700` | Enabled only when a video is loaded |
| Speed dropdown | 75×auto | `surfaceContainer` | — |
| Make | 100×34 | `Colors.green.shade700` | Dimmed if no timeslots |
| Result Folder | 90×34 | `Colors.blueGrey.shade600` | Always active |
| Auto Gen | 110×34 | `Colors.deepPurple.shade400` | Always active; environment check on click |
| Auto Gen info | 16px icon | `Colors.white54` | Hover shows the Auto Gen tooltip |

### Implementation
- `Container` with fixed height 56px, full width
- `Row` with `MainAxisAlignment.spaceEvenly` or explicit spacing
- Separator `VerticalDivider` between logical groups

---

## 5. TimeslotTable

**Purpose**: Displays all marked timeslots in a sortable table.

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `timeslots` | `List<Timeslot>` | `[]` | All timeslots |
| `selectedId` | `String?` | `null` | Selected timeslot |
| `sortBy` | `SortField` | `time` | Current sort field |
| `sortAsc` | `bool` | `true` | Sort direction |
| `callbacks` | — | — | All action callbacks |

### Header

```
┌─ Timeslots (12) ────────────────── [Export ▼] [Sort: Time ▲] ──────┐
```

- Title shows count in parentheses
- Export dropdown: JSON, CSV, EDL, FFmpeg concat
- Sort dropdown: Time, Label, Rating, Duration; toggle ▲/▼
- Header row is sticky (always visible when scrolling)

### Row Layout

```
│  1 │ Goal!!     │ 00:15.30 │ 00:22.10 │ 0:06.8 │ ★★★★☆ │ 🔵 │ ✏️ 🗑️ │
```

### Row States

| State | Visual |
|---|---|
| Default | Alternating row colors (`surface` / `surfaceContainerHighest`) |
| Selected | `primaryContainer` background |
| Hover | Slight brightness increase |
| Playing through | Pulsing border animation on the row whose time range contains current playback position |

### Color Column
- 8 preset colors: Blue, Red, Green, Orange, Purple, Cyan, Pink, Brown
- Rendered as a filled circle (12×12)
- Click to cycle to next color

### Rating Column
- 0–5 star icons (`Icons.star` / `Icons.star_border`)
- Click to increment rating (wraps 0→1→...→5→0)

### Implementation
- `DataTable` or custom `ListView` with fixed column widths
- Sticky header via `SliverPersistentHeader`
- Resizable columns via drag handles

---

## 6. StatusBar

**Purpose**: Shows project summary and current video info.

### Content (left to right)
1. Project name (ellipsized if too long)
2. Separator `│`
3. File count: "5 source files"
4. Separator `│`
5. Timeslot count: "12 timeslots"
6. Separator `│`
7. Total timeslot duration: "Total: 3:45.2"
8. Spacer
9. Current video resolution: "1920×1080"
10. Separator `·`
11. Current video codec: "H.264"
12. Separator `·`
13. Current video framerate: "30fps"

### Implementation
- `Container` height 24px, background `surfaceContainer`
- `Row` with text widgets
- 11px font size, `Colors.white54`

---

## 7. CollapsiblePanel

**Purpose**: Reusable expandable panel with a header bar and toggle arrow.
Used by SourceFileList, StartupTemplatePanel, and TransitionTemplatePanel.

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `title` | `String` | — | Header label text |
| `icon` | `IconData` | `Icons.folder_outlined` | Icon next to the title |
| `child` | `Widget` | — | Body content (hidden when collapsed) |
| `initiallyExpanded` | `bool` | `false` | Whether the panel starts expanded |
| `headerColor` | `Color?` | `null` | Override header background |

### Visual States

**Collapsed**
```
┌─ ▶ Panel Title ──────────────────┐
└──────────────────────────────────┘
```

**Expanded**
```
┌─ ▼ Panel Title ──────────────────┐
│                                  │
│  (child widget content)          │
│                                  │
└──────────────────────────────────┘
```

### Behavior
- Arrow rotates 90° with a 200ms animation when toggled
- Click target includes the entire header bar
- Cursor changes to `click` on hover over the arrow area

### Implementation
- `StatefulWidget` with a local `_expanded` boolean
- `AnimatedRotation` for the arrow icon
- `if (_expanded)` conditionally renders the child

---

## 8. StartupTemplatePanel

**Purpose**: Configuration panel for the startup/intro video template.

### Content (placeholder)
Displays instructional text: "Configure the startup/intro video template. Select a video file to use as the intro for every render."

### Future
- File picker to select the startup video
- Preview thumbnail
- Duration trim controls

---

## 9. TransitionTemplatePanel

**Purpose**: Configuration panel for per-timeslot transition clips.

### Content (placeholder)
Displays instructional text: "Configure the transition video template. Set font, background color, duration, and position of the timeslot description text."

### Future
- Font family selector
- Background color picker
- Font size slider
- Duration spinner (default: 1s)
- Live preview area

---

## 10. MenuBar

### Implementation
- Use Flutter's `MenuBar` widget (Material 3)
- Keyboard shortcuts shown right-aligned in menu items
- Disabled items greyed out when not applicable

---

## 11. ZoomInPointDialog

**Purpose**: Modal dialog shown before rendering when any timeslot is
remote.  Lets the user set the zoom-in center point for the smooth
zoom-pan effect applied to remote timeslot sub-videos.

### Trigger
Shown automatically when the user clicks "Make" and at least one
timeslot has `remote == true`.  If no remote timeslots exist, the
dialog is skipped and rendering proceeds immediately.

### Layout

```
┌─ Zoom in point configuration ───────────────────────────── [✕] ─┐
│                                                                   │
│  Timeslot 1/3: remote_mark                                       │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                                                           │  │
│  │                   ✗ (crosshair cursor)                    │  │
│  │                   ○ (red mark)                            │  │
│  │                                                           │  │
│  │              [ first frame of remote timeslot ]           │  │
│  │                                                           │  │
│  │                                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  [✓] Apply to all   [Next]                    [Done]             │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### Parts

| Part | Component | Description |
|---|---|---|
| **1. Image panel** | 800×450 (16:9) | First frame of the remote timeslot's video at the mark position, extracted via ffmpeg. Scaled to 1280×720 with letterboxing. |
| **2. Mouse interaction** | MouseRegion + GestureDetector | Mouse move shows a white crosshair overlay. Left-click draws a red mark (circle + cross) and records normalized (x, y) as `centerX`/`centerY`. Right-click clears the mark. Only 1 mark at a time. |
| **3. Apply to all** | Checkbox | Default checked. When checked, the mark is applied to all remote timeslots and the "Next" button is disabled. When unchecked, "Next" is enabled. |
| **4. Next button** | FilledButton | Advances to the next remote timeslot's first frame. Disabled when "Apply to all" is checked or on the last timeslot. If the next timeslot already has a mark, it is displayed. |
| **5. Done button** | FilledButton (green) | Finalizes marks and dismisses the dialog, resuming video generation. Both "Done" and the close (✕) button resume generation. |

### Behavior

- **Left-click**: Set red mark at cursor position (normalized 0.0–1.0)
- **Right-click**: Clear the current mark
- **Apply to all checked**: Single mark applies to all remote timeslots; "Next" disabled
- **Apply to all unchecked**: Each timeslot gets its own mark; "Next" navigates between timeslots
- **Done / ✕**: Returns the marks map and resumes rendering. Timeslots without marks use the default center+pan zoom behavior.

### Implementation
- `StatefulWidget` with `CustomPainter` for crosshair and mark overlay
- `VideoProcessingService.extractFrame()` for first-frame extraction (PNG output)
- Frame images are cleaned up in `dispose()`

---

## 12. TemplateEditorDialog

**Purpose**: Modal editor for previewing how a chosen font renders inside each
startup / transition / ending template before rendering a highlight reel.
Regenerates a short live-preview MP4 on every parameter change so the user can
scrub the whole template catalogue with different typefaces, sizes, colors and
copy.

### Trigger
- Click the **edit (✏️) / preview** icon on any template row in the template
  panels (right sidebar), or
- Menu **View → Template Editor** (`Ctrl+T`).

### Layout

```
┌─ Template Editing and Preview ───────────────────────────── [✕] ─┐
│                                                                    │
│  ┌─ Left rail (300px) ─────────────┐  ┌─ Live preview ──────────┐ │
│  │ TEMPLATE                        │  │                         │ │
│  │ [Startup] [Transition] [Ending] │  │  ┌───────────────────┐  │ │
│  │                                 │  │  │                   │  │ │
│  │ ┌────┐ ┌────┐ ┌────┐            │  │  │   16:9 video      │  │ │
│  │ │ s1 │ │ s2 │ │ s3 │  ← cards   │  │  │   (looping)       │  │ │
│  │ └────┘ └────┘ └────┘            │  │  │                   │  │ │
│  │                                 │  │  └───────────────────┘  │ │
│  │ FONT                            │  │   ▶ ─────●───── 0:03.0  │ │
│  │ Preview text                    │  │                         │ │
│  │ [精彩进球集锦______________]    │  │  Generating preview…    │ │
│  │ Family    [Microsoft YaHei ▼]   │  │  ▓▓▓▓▓▓▓▓░░░░  62%      │ │
│  │           [Browse font file…]   │  │                         │ │
│  │ Size      ═══════●════  42 px   │  │                         │ │
│  │ Color     [■] #F5C42D [🎨]      │  │                         │ │
│  │ Position  ◉Top  ○Middle  ○Bottom│  │                         │ │
│  │                                 │  │                         │ │
│  └─────────────────────────────────┘  └─────────────────────────┘ │
│                                                                    │
│  [Cancel]                              [Restore defaults] [Apply]  │
└────────────────────────────────────────────────────────────────────┘
```

### Left rail — template catalogue

| Part | Component | Description |
|---|---|---|
| **Category tabs** | `SegmentedButton` | Startup / Transition / Ending. Switching category reloads the card grid. |
| **Template cards** | 84×47 (16:9) thumbnails | One card per template in the current category, sourced from `TemplateRepository.listByType`. First frame rendered via `extractFrame()`. Selected card gets a 2px `primary` border + check badge; hover lifts to 1.04× with elevation 2. |

### Left rail — font controls

| Control | Component | Default | Notes |
|---|---|---|---|
| **Preview text** | `TextField` | `精彩进球集锦` | Empty → renders the template's reserved text zone blank. |
| **Font family** | `DropdownButton` | First system font | Enumerates system font families (`C:\Windows\Fonts`). Selecting re-renders. |
| **Browse font file** | `OutlinedButton` | — | `FilePicker` for `.ttf`/`.otf`; overrides the dropdown when set. |
| **Size** | `Slider` | 42 px | Range 16–96, step 2. Live value label on the right. |
| **Color** | Swatch + picker | `#F5C42D` (gold) | 8 preset swatches + a full color-picker popover. |
| **Position** | `Radio` group | Bottom | Top / Middle / Bottom — vertical anchor of the text plate. |

### Live preview pane

- `media_kit` player, **loop playback**, muted by default with a 🔉 toggle.
- Aspect ratio locked to 16:9 with letterboxing; minimum 640×360.
- While a preview is regenerating, the previous frame stays visible under a
  scrim with an indeterminate `LinearProgressIndicator` across the top edge —
  no blank flash between regenerations.
- Scrub bar mirrors the player position; preview clips are short (3–4 s).

### Regeneration pipeline

1. Any parameter change marks the preview **dirty**.
2. Changes are **debounced 400 ms** (slider drags, typing) before triggering.
3. `VideoProcessingService` regenerates to a temp file
   (`%TEMP%\highlight-creator\preview\<category>_<id>.mp4`) with the selected
   font injected into the template's reserved text zone.
4. On completion the player hot-swaps the media source and resumes looping.
5. A stale request (superseded by a newer edit) is cancelled / ignored by
   comparing a monotonically increasing generation token.

### Behavior

- **Switch template card** → regenerate immediately (no debounce).
- **Switch category** → regenerate with the first template of that category,
  preserving all font settings.
- **Apply** → persists the font settings as the render default and closes.
- **Restore defaults** → resets font controls to defaults and regenerates.
- **✕ / Cancel** → discards nothing (previews are ephemeral) and closes.
- **Esc** → same as Cancel.

### Implementation
- `StatefulWidget` inside `showDialog(barrierDismissible: false)`, fixed
  content size 1100×680, `surfaceContainer` background.
- Player lifecycle in `initState`/`dispose`; generation runs on an isolate-free
  async chain guarded by a `_generation` counter.
- Temp previews deleted on dialog `dispose()`.
- Font enumeration cached for the session.

---

## 13. AutoGenDialog

**Purpose**: Semi-automatic highlight generation workspace. The user reviews
the source video, scrubs it with a dedicated track, and curates the timeslot
list that the local (on-device) algorithm assists with. Safe and free — no
cloud. May be slow on low-end hardware.

### Trigger

Click **Auto Gen** on the control panel (next to **Result Folder**).

An **info label (ℹ️)** sits next to the Auto Gen button. Hovering it shows the
tooltip:

- EN: "It will assist you to generate highlight semi-auto. It might be very
  slow if the hardware is not good enough. Rely on local algrithm. Safe and
  free."
- 中文: "利用本地算法协助剪辑视频中的高光时刻，仍需要人工甄别，安全，免费。注意：对硬件有一定要求，低配硬件可能会非常慢！"

Button labels: EN "Auto Gen" / 中文 "AI辅助生成".

### Environment check (before the dialog opens)

| Condition | Behavior |
|---|---|
| Source file list is empty | Error dialog: "Please add video source files first." with a single **OK** button that closes it. The Auto Gen dialog does not open. |
| Otherwise | The modal Auto Gen dialog opens and plays **all source files sequentially** as a playlist, starting at the video currently in the main player (or the first source if none is loaded). |

### Multi-file playback (playlist, no concat file)

The dialog plays every source file in one continuous session using a
`media_kit` **Playlist** — no temporary concatenated file is created
(zero conversion time, zero disk usage, no 4K size blow-up).

- Per-file durations are probed upfront with `ffprobe` (header-only, fast);
  a failed probe is self-healed once the live player reports the duration.
- The track is a **global timeline** spanning the combined duration of all
  sources. The playhead, ruler and progress fill use global time; seeking
  across a file boundary jumps to the corresponding playlist segment.
- Thin white **segment boundary** lines on the track mark where each file
  starts; the current file name and `(i/n)` index are shown above the ruler.
- Timeslot markers are placed at their global position (segment offset +
  in-point). A timeslot is matched to a segment by `videoSourceId`, falling
  back to filename.
- Playback auto-advances through the files and stops at the end of the
  playlist (`PlaylistMode.none`).

### Layout

```
┌─ ✨ Auto Gen ─────────────────────────────────── [⛶] [✕] ─┐
│                                                            │
│         ┌────────────────────────────────┐                 │
│         │                                │                 │
│         │        VIDEO PLAYER            │  ← centered,    │
│         │        (tap to play/pause)     │    16:9         │
│         │                                │                 │
│         └────────────────────────────────┘                 │
│         0:00  0:10  0:20  0:30 ...        ← seconds ruler  │
│         ▓▓▓▓░░│▓▓░░░░░░│▓▓▓░░░░░░░│░░░░  ← 48px track,    │
│         ▼ Timeslots                        same width as   │
│         ┌────────────────────────────────┐ the player      │
│         │ (same TimeslotTable as the     │  ← expandable   │
│         │  main window)                  │    panel        │
│         └────────────────────────────────┘                 │
└────────────────────────────────────────────────────────────┘
```

### Parts

| Part | Component | Description |
|---|---|---|
| **1. Video player** | `media_kit` `Video`, centered | Dedicated player instance (separate from the main window player), letterboxed 16:9, tap to play/pause. Plays all sources sequentially via a playlist. |
| **2. Time ruler** | Tick labels above the track | Minimal unit: 1 second (mm:ss / h:mm:ss), global time across all files. Tick spacing auto-scales (1s, 2s, 5s, 10s, …) so labels stay readable. |
| **3. Track** | Custom seek bar, 48px height | Global timeline over the combined duration: progress fill + red playhead, segment boundary lines per file, and timeslot markers drawn as colored blocks (table color) at their global in-point, width = elapse (min 4px). Zoomable (see below) and horizontally scrollable. |

### Track zoom, scroll and editing

- **Zoom in / out buttons** sit on the right of the file-label row. They
  change the ruler's **minimal time unit** between **1s** (most zoomed in,
  80px per second) and **10s** (most zoomed out, 8px per second).
  Zoom-in is disabled at 1s; zoom-out is disabled at 10s. The scroll offset
  is preserved proportionally across zoom.
- **Horizontal scrollbar** (always-visible thumb) scrolls the ruler + track
  when the zoomed content is wider than the viewport.
- **Click the track** → seek to the exact point **and pause** the player.
  Click the video to resume (tap toggles play/pause).
- **Drag a marker's start or end edge** (8px handles, resize cursor) to
  extend or reduce the timeslot's elapse; edges are clamped to the slot's
  own source segment. The change is committed on release via the shared
  record state, so the dialog's timeslot list **and** the main-window
  timeslot list update together.
| **4. Expandable panel** | `CollapsiblePanel` | Directly below the track. Contains the exact same timeslot list (`TimeslotTable`) as the main window. Collapsed by default; body height 200px. |

### Behavior

- **Modal** — the dialog is opened with `barrierDismissible: false`; clicking
  outside it does not dismiss it. Only ✕ / Close exits.
- **⛶ Maximize** → toggles between the normal dialog (max 1000px wide, 85%
  screen height) and full screen. Full screen also maximizes the host OS
  window itself (Win32 `ShowWindow(SW_MAXIMIZE)` via `Win32Window`), so the
  dialog covers the whole screen, not just the current app window area; the
  previous window state is restored on un-maximize or close (unless the
  window was already maximized before).
- **Timeslot panel** — collapsed by default; expand via the header arrow.
- **✕ / Close** → disposes the dialog's player and returns to the main window.
- Timeslot edits inside the dialog (add via main Mark flow, edit, delete,
  rating, color) operate on the same shared record state as the main window,
  and marker colors on the track follow the timeslot's current color.

### Implementation
- `ConsumerStatefulWidget` inside `showDialog(barrierDismissible: false)`,
  `Dialog` constrained to max 1000px wide / 85% screen height,
  `surfaceContainer` background.
- Own `Player`/`VideoController` created in `initState`, disposed in
  `dispose`.
- Player width derived from available space via `LayoutBuilder` (fit 16:9),
  track shares that width.
- OS-window maximize/restore via `data/ffi/win32_window.dart`
  (`user32.dll`: `GetActiveWindow` / `IsZoomed` / `ShowWindow`).
- Per-file durations via `VideoProcessingService.probeDurationMs`
  (ffprobe, header-only). Global→local seek mapping is the pure function
  `globalToLocal()` (unit-tested).

---

## 14. PreviewDialog

**Purpose**: Pre-render confirmation dialog shown after ZoomInPointDialog
(and before rendering). Shows template thumbnails, timeslot count, output
resolution picker, and Confirm / Cancel buttons.

### Trigger

Shown automatically when the user clicks "Make" after the ZoomInPointDialog
step (if remote timeslots exist) or immediately if no remote timeslots exist.

### Layout

```
┌─ Preview & Confirm ──────────────────────────────────── [✕] ─┐
│                                                                │
│  ┌─ Startup ───┐ ─── ┌─ Transition ─┐ ─── ┌─ Ending ──┐     │
│  │  [thumbnail] │  >  │  [thumbnail] │  >  │ [thumbnail]│     │
│  │  template    │     │  template    │     │ template   │     │
│  │  title       │     │  title       │     │ —          │     │
│  └──────────────┘     └──────────────┘     └────────────┘     │
│                                                                │
│  📋 3 timeslots                                               │
│                                                                │
│  Output Resolution                                             │
│  [480P] [720P] [1080P] [4K]                                   │
│                                                                │
│  ─────────────────────────────────────────────────────────── │
│                                      [Cancel]  [Confirm & Make]│
└────────────────────────────────────────────────────────────────┘
```

### Parts

| Part | Component | Description |
|---|---|---|
| **1. Template previews** | 3-column row | Each column shows a card with thumbnail (200×112 via `extractFrame`), template name, and title (for startup). Cards separated by chevron arrows. |
| **2. Timeslot summary** | Icon + text | Shows count of timeslots to be rendered (e.g. "3 timeslots"). |
| **3. Resolution picker** | `ChoiceChip` row | 480P / 720P / 1080P / 4K. Chips disabled when resolution exceeds source video height. Default: 720P. |
| **4. Confirm button** | `FilledButton` (green) | Key: `preview_confirm_button`. Returns `(width, height)` tuple. |
| **5. Cancel button** | `TextButton` | Returns `null`, closes dialog without rendering. |

### Behavior

- **Template thumbnails**: Extracted via `VideoProcessingService.extractFrame()` at 0.4s. Thumbnails cached in a map. If extraction fails (no service, missing file), a placeholder is shown.
- **Resolution chips**: Disabled when `minSourceH > maxSourceHeight` (probed from source videos). 720P is always available.
- **Confirm**: Returns the selected `(width, height)` tuple to the caller.
- **Cancel / ✕**: Returns `null`, aborting the render.

### Implementation

- `ConsumerStatefulWidget` inside `showDialog`, `ConstrainedBox` max 700×600.
- Accepts optional `VideoProcessingService?` parameter for thumbnail extraction
  (bypasses `findFfmpeg()` when null — used in tests).
- Template resolution uses `templateRepositoryProvider` and
  `selectedTemplatesProvider` from Riverpod.
- Path resolution walks up from `Directory.current` to find `AGENTS.md` or
  `app/` (same pattern as `_onMake` in `control_panel.dart`).
- Error-safe: `_loadTemplates()` wrapped in try-catch, returns empty template
  list on failure.

### Make Workflow (Updated)

```
User clicks [Make] button in ControlPanel
  │
  ▼
_onMakePressed() — probe source resolutions
  │
  ▼
If remote timeslots exist:
  ZoomInPointDialog — user clicks zoom centers
  (marks merged back into timeslots)
  │
  ▼
PreviewDialog — template previews + resolution selection
  │  (cancelled? → exit)
  ▼
_onMake(width, height, timeslotsOverride) — resolves templates
  │
  ▼
Validate template files exist
  │  (missing? → error dialog, exit)
  ▼
Show CircularProgressIndicator dialog
  │
  ▼
VideoProcessingService.makeAll() — full 5-step pipeline
  │
  ▼
Pop dialog, show success SnackBar, load result into player
```
