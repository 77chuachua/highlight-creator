# Windows UI — Layout Specification

> Specifies panel arrangement, sizing, and responsive behavior.

---

## 1. Main Window

### Default Size
- Width: 1400px (minimum)
- Height: 900px (minimum)
- Resizable with minimum constraints
- The application window starts **maximized** on launch

### Panel Grid

The window uses a **CSS Grid**-style 3-row, 2-column layout:

```
┌──────────────────┬──────────────┐
│   Row 1: Main    │ Col 1 (75%)  │ Col 2 (25%)
│                  │ Video Player │ Source Files
│                  │              │
├──────────────────┴──────────────┤
│   Row 2: Control Panel (100%)  │
├─────────────────────────────────┤
│   Row 3: Timeslots Table (100%)│
├─────────────────────────────────┤
│   Row 4: Status Bar (100%)     │
└─────────────────────────────────┘
```

### Flutter Implementation

```dart
// Pseudocode for the main layout
Column(
  children: [
    // Toolbar
    _buildToolbar(),
    // Main content area
    Expanded(
      child: Row(
        children: [
          // Video player (75% width)
          Expanded(flex: 3, child: VideoPlayerPanel()),
          // Vertical divider
          VerticalDivider(),
          // Right sidebar (25% width)
          SizedBox(
            width: 320,
            child: Column(
              children: [
                // Source file list
                Expanded(flex: 2, child: SourceFileList()),
                // Thumbnail strip
                ThumbnailStrip(),
              ],
            ),
          ),
        ],
      ),
    ),
    // Control panel
    ControlPanel(),
    // Timeslot table
    Expanded(child: TimeslotTable()),
    // Status bar
    StatusBar(),
  ],
)
```

---

## 2. Video Player Panel (Row 1, Col 1)

### Dimensions
- Default: 75% of window width × remaining height after toolbar
- Maintains 16:9 aspect ratio with letterboxing
- Minimum width: 640px

### States

| State | Display |
|---|---|
| **No video loaded** | Dark surface with centered text "Drop a video file or click Open", dashed border |
| **Loading** | Dark surface with centered `CircularProgressIndicator` |
| **Playing** | Video rendered at native resolution, controls overlay (auto-hide after 3s) |
| **Paused** | Last frame frozen, controls overlay always visible |
| **Error** | Dark surface with error icon, message, and "Dismiss" button |

### Video Controls Overlay (auto-hide)

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│              ┌──────────┐              │
│              │    ▶     │              │  ← Center play/pause (72×72 circle)
│              └──────────┘              │
│                                         │
│                                         │
│  00:32.5  ═══════════════●══════════  02:15.0  │  ← Timeline scrub bar
│  ⏮  ▶  ⏭  ■    1.0x    🔉 ═════●═══  │  ← Control row
└─────────────────────────────────────────┘
```

### Hover behavior
- Mouse movement → controls fade in over 200ms
- Mouse idle for 3s → controls fade out over 500ms
- Mouse over slider → controls stay visible

---

## 3. Source File List (Row 1, Col 2 — Top)

### Dimensions
- Width: 320px (fixed)
- Height: 60% of right sidebar

### Collapse / Expand

A small **arrow (▶)** is positioned on the left side of the header bar.
Clicking the arrow toggles the panel body between expanded and collapsed.
When collapsed only the header bar remains visible, saving vertical space.

### Structure

```
┌─ ▶ Source Files ──────── [+] ──┐  ← Arrow rotates 90° when expanded
├─────────────────────────────────┤
│  📹 match1_first_half.mp4       │  ← Selected (highlighted)
│     Duration: 45:30             │
│     1920×1080 · H.264 · 30fps  │
├─────────────────────────────────┤
│  📹 match1_second_half.mp4      │
│     Duration: 45:30             │
│     1920×1080 · H.264 · 30fps  │
├─────────────────────────────────┤
│  📹 post_game_interview.mp4     │
│     Duration: 05:15             │
│     3840×2160 · H.265 · 60fps  │
├─────────────────────────────────┤
│                                 │
│  (empty space)                  │
│                                 │
└─────────────────────────────────┘
```

### Interactions
- **Click**: Select source and load into player
- **Double-click**: Load and start playback
- **Right-click**: Context menu (Remove, Properties, Set as Primary)
- **Drag from Explorer**: Add file to list
- **Delete key**: Remove selected file

---

## 4. Startup Template Panel (Row 1, Col 2 — Middle)

### Dimensions
- Width: 320px
- Height: auto (collapsed: header only ~32px; expanded: header + content)

### Collapse / Expand
Same arrow toggle pattern as the Source File List. Collapsed by default.

### Structure
```
┌─ ▶ Startup Template ────────────┐  ← Arrow, collapsed by default
└─────────────────────────────────┘
      ↓ expanded
┌─ ▼ Startup Template ────────────┐
│  Configure the startup/intro    │
│  video template. Select a video │
│  file to use as the intro for   │
│  every render.                  │
└─────────────────────────────────┘
```

### Purpose
Holds configuration for the intro/startup clip that plays at the beginning of every rendered highlight reel.

Each template row exposes a **preview (▶)** icon and an **edit (✏️)** icon.
The edit icon opens the Template Editing and Preview dialog (components.md §12)
scoped to the selected template, allowing per-font preview across all templates.

---

## 5. Transition Template Panel (Row 1, Col 2 — Middle)

### Dimensions
- Width: 320px
- Height: auto (collapsed: header only ~32px; expanded: header + content)

### Collapse / Expand
Same arrow toggle pattern. Collapsed by default.

### Structure
```
┌─ ▶ Transition Template ─────────┐  ← Arrow, collapsed by default
└─────────────────────────────────┘
      ↓ expanded
┌─ ▼ Transition Template ─────────┐
│  Configure the transition video │
│  template. Set font, background │
│  color, duration, and position  │
│  of the timeslot description.   │
└─────────────────────────────────┘
```

### Purpose
Holds configuration for the per-timeslot transition clip (1s, 720p, text overlay).

---

## 6. Thumbnail Strip (Row 1, Col 2 — Bottom)

### Dimensions
- Width: 320px
- Height: 60px

### Structure

```
┌─ Timeline Preview ──────────────┐
│ [■][■][■][■][■][■][■][■][■][■] │  ← 10 thumbnails visible at a time
│  ▲                              │
│  └─ Current position indicator  │
└─────────────────────────────────┘
```

### Behavior
- Horizontally scrollable
- Each thumbnail represents ~30 seconds of video
- Current position is highlighted with a colored border
- Click a thumbnail → seek player to that position
- Hover a thumbnail → show timestamp tooltip

---

## 7. Control Panel (Row 2)

### Dimensions
- Full width
- Height: 56px (single row of controls)

### Structure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ [⏮] [▶] [⏭] [■] │ [🚩 Mark] │ Speed: [1.0x▼] │ [✨ Make] [📂 Result Folder] │
│                 │ [🪄 Auto Gen] [ℹ️]                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Controls Detail

| Control | Type | Shortcut | Description |
|---|---|---|---|
| ⏮ Seek Back | IconButton | ← | Jump back 5 seconds |
| ▶ Play/Pause | IconButton | Space | Toggle playback |
| ⏭ Seek Forward | IconButton | → | Jump forward 5 seconds |
| ■ Stop | IconButton | Esc | Stop playback, return to start |
| 🚩 Mark | FilledButton | O | Create a timeslot covering the 10s before the current position (elapse 10s; clamped at video start) |
| Speed | DropdownButton | — | Select playback speed |
| ✨ Make | FilledButton | — | Render the highlight reel from all timeslots. Opens ZoomInPointDialog (if remote timeslots), then PreviewDialog for template preview + resolution selection, then renders. |
| 📂 Result Folder | FilledButton | — | Open the output folder in Explorer |
| 🪄 Auto Gen | FilledButton | — | Open the Auto Gen dialog (components.md §13); disabled check happens on click |
| ℹ️ Auto Gen info | Icon + Tooltip | — | Hover shows the Auto Gen description (semi-automatic, local algorithm, free, may be slow on weak hardware) |

---

## 8. Timeslot Record List (Row 3)

### Dimensions
- Full width
- Minimum height: 150px, resizable up to 40% of window

### Structure

```
┌─ Timeslots (3) ─────────────── [Export ▼] [Sort: Time ▲] ───────┐
│  # │ Label      │ In Point │ Out Point│ Dur    │ ★ │ Color │ ✎  │
├────┼────────────┼──────────┼──────────┼────────┼───┼───────┼────┤
│  1 │ Goal!!     │ 00:15.30 │ 00:22.10 │ 0:06.8 │ 4 │  🔵   │ ✏️🗑️│
│  2 │ Red Card   │ 00:45.00 │ 00:48.50 │ 0:03.5 │ 2 │  🔴   │ ✏️🗑️│
│  3 │ Great Save │ 01:12.20 │ 01:18.70 │ 0:06.5 │ 5 │  🟢   │ ✏️🗑️│
├────┼────────────┼──────────┼──────────┼────────┼───┼───────┼────┤
│    │            │          │          │        │   │       │    │
│  (empty rows scroll into view as more timeslots are added)     │
└────────────────────────────────────────────────────────────────┘
```

### Column Specs

| Column | Width | Align | Description |
|---|---|---|---|
| # | 40px | Center | Auto-numbered |
| Label | Flex | Left | Editable inline (double-click to edit) |
| In Point | 90px | Right | Formatted mm:ss.ms |
| Out Point | 90px | Right | Formatted mm:ss.ms |
| Duration | 80px | Right | Auto-calculated |
| Rating | 60px | Center | Click to cycle 0–5 stars |
| Color | 60px | Center | Click to cycle 8 colors |
| Actions | 72px | Center | Edit (inline), Delete |

### Interactions
- **Click row**: Seek player to in-point of that timeslot
- **Double-click label**: Inline edit
- **Click rating**: Cycle 0→1→2→3→4→5→0
- **Click color**: Cycle through 8 preset colors
- **Right-click**: Context menu (Delete, Duplicate, Export this clip)
- **Drag row**: Reorder timeslots
- **Delete key**: Remove selected timeslot

### Export Submenu
- Export as JSON
- Export as CSV
- Export as EDL (Edit Decision List)
- Export as FFmpeg concat script

---

## 9. Status Bar (Row 4)

### Dimensions
- Full width, 24px height

### Content

```
Project: MyProject.hcp │ 5 source files │ 12 timeslots │ Total: 3:45.2 │ 1920×1080 @ 30fps
```

Left-aligned: project name, file count, timeslot count
Right-aligned: current video resolution and framerate

---

## 10. Menu Bar

### File
- **New Project** (Ctrl+N)
- **Open Project** (Ctrl+O)
- **Save Project** (Ctrl+S)
- **Save Project As...** (Ctrl+Shift+S)
- ─────────
- **Import Video Files...** (Ctrl+I)
- **Import Folder...** (Ctrl+Shift+I)
- ─────────
- **Export Rendered Video...** (Ctrl+E)
- ─────────
- **Exit** (Alt+F4)

### Edit
- **Undo** (Ctrl+Z)
- **Redo** (Ctrl+Y)
- ─────────
- **Select All Timeslots** (Ctrl+A)
- **Delete Selected** (Delete)
- ─────────
- **Preferences...**

### View
- **Toggle File List** — show/hide right sidebar
- **Toggle Timeslot Table** — show/hide bottom panel
- **Template Editor** (Ctrl+T) — open the Template Editing and Preview dialog (see components.md §12)
- ─────────
- **Zoom In Timeline** (Ctrl+=)
- **Zoom Out Timeline** (Ctrl+-)
- **Reset Zoom** (Ctrl+0)
- ─────────
- **Dark Theme** / **Light Theme**
- **Full Screen** (F11)

### Help
- **Keyboard Shortcuts** (F1)
- **About Highlight Creator**
