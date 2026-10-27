# Highlight Creator — Architecture Design

> **Document version**: 1.0  
> **Date**: 2026-06-18  
> **Status**: Draft

---

## Table of Contents

1. [Overview](#1-overview)
2. [Technology Stack](#2-technology-stack)
3. [Architecture Pattern](#3-architecture-pattern)
4. [High-Level System Diagram](#4-high-level-system-diagram)
5. [Module Design](#5-module-design)
   - [5.1 Video Player Module](#51-video-player-module)
   - [5.2 Record System Module](#52-record-system-module)
   - [5.3 Video Process Module](#53-video-process-module)
   - [5.4 User Module](#54-user-module)
6. [Cross-Platform Strategy](#6-cross-platform-strategy)
7. [Data Layer](#7-data-layer)
8. [Performance Considerations](#8-performance-considerations)
9. [Security & Licensing](#9-security--licensing)

---

## 1. Overview

**Highlight Creator** is a cross-platform application that enables users to create highlight reels by slicing, applying effects, and combining clips from multiple source videos. It ships on **Windows** today; the same Flutter codebase also builds for macOS, Android
and iOS, which are not released yet.

### Core Capabilities

| Capability | Description |
|---|---|
| **Video Playback** | Play local video files with standard controls and custom overlays. |
| **Time-slot Recording** | Mark in/out points on source videos; store annotated timeslots. |
| **Video Processing** | Slice clips, apply filters/transitions/overlays, and render a final combined video. |
| **User Management** | Profiles, preset configurations, and project history. |

### Design Goals

- **Code sharing ≥ 85%** across the Flutter targets (Windows is the released one).
- **Smooth 60 fps** UI with hardware-accelerated video preview.
- **Offline-first** — all core features work without a network connection.
- **Modular** — each of the four modules can be developed, tested, and shipped independently.

---

## 2. Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| **UI Framework** | Flutter 3.x (Dart) | Single codebase → 4 platforms; mature video plugin ecosystem; 60 fps rendering via Skia/Impeller. |
| **Video Playback** | `media_kit` (Flutter) | Wraps libmpv/FFmpeg; hardware decoding on all platforms; precise seeking. |
| **Video Processing Engine** | Rust via `flutter_rust_bridge` + FFmpeg C API | Near-native speed; memory safety from Rust; FFmpeg is the gold standard for video manipulation. |
| **GPU Effects** | OpenGL ES (Android) / Metal (iOS/macOS) / Direct3D (Windows) — abstracted via a thin Rust layer | Real-time effect preview; shader-based filters. |
| **Local Database** | `drift` (SQLite for Flutter) | Typed, reactive SQLite ORM; cross-platform; good for structured timeslot and preset data. |
| **File I/O** | `path_provider` + Rust `std::fs` | Platform-correct paths for cache, temp, and output directories. |
| **State Management** | Riverpod 2.x | Compile-safe, testable, and scales from a single widget to the whole app. |
| **DI / Service Locator** | `get_it` + Riverpod overrides | Glue between Dart UI and Rust native layer. |
| **Testing** | Flutter test + `mocktail` + Rust `cargo test` | Unit, widget, integration, and golden-image tests. |

---

## 3. Architecture Pattern

The application follows **Clean Architecture** with three concentric layers, adapted for a Flutter + Rust hybrid:

```
┌──────────────────────────────────────────┐
│              PRESENTATION                 │
│  (Flutter Widgets, Pages, ViewModels)     │
├──────────────────────────────────────────┤
│               DOMAIN                      │
│     (Entities, Use Cases, Interfaces)     │
├──────────────────────────────────────────┤
│                 DATA                      │
│  (Repositories, DB, FFI Bridge, FFmpeg)   │
│    ┌─────────────┬──────────────────┐     │
│    │  Dart Side  │   Rust Side      │     │
│    │  (drift DB, │  (FFmpeg engine, │     │
│    │   API,      │   GPU shaders,   │     │
│    │   caching)  │   file I/O)      │     │
│    └─────────────┴──────────────────┘     │
└──────────────────────────────────────────┘
```

### Dependency Rule

Dependencies point **inward**. The inner circles know nothing about the outer circles.

- **Presentation** → depends on Domain
- **Domain** → depends on nothing (pure Dart, zero platform dependencies)
- **Data** → implements Domain interfaces; spans Dart (SQLite, preferences) and Rust (FFmpeg, GPU)

### MVVM in the Presentation Layer

Each screen uses a **ViewModel** (Riverpod `Notifier`) that:

1. Exposes immutable **state** objects.
2. Calls **domain use-cases** for business logic.
3. Delegates long-running work (export, render) to the Rust engine via async FFI.

---

## 4. High-Level System Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         FLUTTER UI LAYER                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐   │
│  │  Player  │  │ Recorder │  │ Process  │  │   User        │   │
│  │  Screen  │  │  Screen  │  │  Screen  │  │   Screen      │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───────┬───────┘   │
│       │              │              │               │           │
│  ┌────┴──────────────┴──────────────┴───────────────┴────┐      │
│  │                 RIVERPOD STATE LAYER                   │      │
│  │  PlayerVM  │  RecordVM  │  ProcessVM  │  UserVM       │      │
│  └────┬───────┴────┬───────┴────┬────────┴───────┬───────┘      │
├───────┼────────────┼────────────┼────────────────┼──────────────┤
│       │      DOMAIN LAYER (Use Cases)              │              │
│  ┌────┴────────────┴────────────┴────────────────┴────┐         │
│  │  PlayVideo  │  RecordTimeslot  │  RenderProject    │         │
│  │  SeekTo     │  AnnotateSlot    │  ApplyEffects     │         │
│  │  TogglePlay │  ExportTimeslots │  CombineClips     │         │
│  └────┬────────┴────┬─────────────┴────┬──────────────┘         │
├───────┼─────────────┼──────────────────┼────────────────────────┤
│       │     DATA LAYER (Repository Interfaces)                   │
│  ┌────┴─────────────┴──────────────────┴──────────────────┐     │
│  │  VideoRepository  │  ProjectRepository  │ UserRepo     │     │
│  └───┬───────────────┴───┬──────────────────┴──┬──────────┘     │
│      │                   │                     │                 │
│  ┌───┴───────────────────┴─────────────────────┴──────────┐     │
│  │                  FLUTTER_RUST_BRIDGE (FFI)              │     │
│  └───┬───────────────────┬─────────────────────┬──────────┘     │
├──────┼───────────────────┼─────────────────────┼────────────────┤
│      │         RUST NATIVE CORE                 │                │
│  ┌───┴──────────┐ ┌──────┴──────┐ ┌────────────┴───────────┐   │
│  │  FFmpeg      │ │  GPU        │ │  File/Project          │   │
│  │  Engine      │ │  Pipeline   │ │  Manager               │   │
│  │  - decode    │ │  - shaders  │ │  - temp dirs           │   │
│  │  - encode    │ │  - filters  │ │  - export paths        │   │
│  │  - slice     │ │  - trans.   │ │  - cleanup             │   │
│  │  - mux       │ │  - overlay  │ │                        │   │
│  └──────────────┘ └─────────────┘ └────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. Module Design

### 5.1 Video Player Module

**Purpose**: Play local video files with precise seeking, frame stepping, and custom overlay rendering.

#### Features

| Feature | Priority | Notes |
|---|---|---|
| Play / Pause / Stop | P0 | Standard transport controls |
| Seek (scrub) with thumbnail preview | P0 | Generate sprite-sheet thumbnails on load |
| Frame step forward/backward | P1 | Essential for precise timeslot marking |
| Playback speed (0.25× – 4×) | P1 | Pitch-preserved audio optional |
| A/B loop | P2 | Repeat a marked region |
| Custom subtitle/overlay rendering | P1 | Time markers, effect previews, labels |
| Hardware-accelerated decode | P0 | Via `media_kit` (mpv/FFmpeg HW accel) |
| Audio waveform display | P2 | Extracted via FFmpeg |

#### Key Types (Domain Layer)

```dart
// Entities
class VideoSource {
  final String id;
  final String filePath;
  final Duration duration;
  final VideoMetadata metadata; // resolution, codec, fps, bitrate
}

class PlaybackState {
  final VideoSource source;
  final Duration position;
  final bool isPlaying;
  final double speed;
  final Duration? loopStart;
  final Duration? loopEnd;
}
```

#### Architecture Notes

- The ViewModel holds `PlaybackState` and issues commands to the `media_kit` player controller.
- Thumbnail sprite-sheets are generated by the Rust FFmpeg engine at import time and cached on disk.
- Custom overlays (time markers, effect preview regions) are drawn on a Flutter `CustomPainter` canvas layered above the video surface.

---

### 5.2 Record System Module

**Purpose**: Let users mark time-slot regions (in/out points) on source videos, annotate them, and organize them into a project.

#### Features

| Feature | Priority | Notes |
|---|---|---|
| Mark in-point / out-point | P0 | Keyboard shortcuts + touch buttons |
| Visual timeline with waveform / thumbnails | P0 | Drag handles to adjust boundaries |
| Slot annotation (label, color, rating) | P0 | Free-text tags + star rating |
| Multi-track timeline | P1 | Overlay slots from multiple source videos |
| Slot list with sorting/filtering | P1 | Search by label, sort by duration, color |
| Export slots as EDL / CSV | P2 | Interop with other editing tools |
| Undo/redo for slot edits | P1 | Command pattern |

#### Key Types (Domain Layer)

```dart
class Timeslot {
  final String id;
  final String videoSourceId;
  final Duration inPoint;
  final Duration outPoint;
  final String label;
  final int colorIndex;
  final int rating; // 0-5
  final DateTime createdAt;

  // Extended fields (per issues.md)
  final String filename;
  final String description;
  final int elapse;   // duration in ms
  final bool remote;  // remote timeslot triggers zoom-pan effect

  // Zoom-in center point for remote timeslots (normalized 0.0–1.0).
  // Set via the Zoom-in Point Configuration dialog before rendering.
  final double? centerX;
  final double? centerY;
}

class Project {
  final String id;
  final String name;
  final List<Timeslot> timeslots;
  final List<VideoSource> sources;
  final ProjectSettings settings;
  final DateTime updatedAt;
}
```

#### Data Flow

```
User taps "Mark In"  ──►  RecordVM.markIn()
                              │
                     PlayerVM.currentPosition  ──►  new Timeslot(inPoint: position)
                              │
                     ProjectRepository.save(timeslot)
                              │
                     drift DB (SQLite)
```

#### Architecture Notes

- The timeline widget is a custom Flutter `CustomScrollView` with synchronized horizontal scroll across tracks.
- Timeslot boundaries snap to the nearest keyframe (I-frame) for clean slicing — the Rust engine provides keyframe indices on video import.
- All mutations go through a `Command` pattern so undo/redo is trivial.

---

### 5.3 Video Process Module

**Purpose**: Slice source videos according to timeslot definitions, apply effects, and render a final combined video file.

This is the **computationally heaviest** module and lives primarily in Rust.

#### Features

| Feature | Priority | Notes |
|---|---|---|
| Slice clips from source videos (lossless where possible) | P0 | GOP-aligned copy; re-encode only at cut boundaries |
| Apply visual effects (color grading, LUT, blur, speed ramp) | P0 | GPU shader pipeline |
| Transitions between clips (fade, wipe, dissolve) | P1 | Cross-fade = two decoders + compositor |
| Text overlays / watermarks | P1 | libass or custom text renderer |
| Audio mixing (background music, volume envelope) | P1 | FFmpeg audio filter graph |
| Combine into single MP4/MOV output | P0 | FFmpeg muxer; H.264/H.265 encode |
| Export presets (resolution, bitrate, codec) | P0 | 720p/1080p/4K; H.264/H.265/AV1 |
| Background rendering with progress | P0 | Isolate/thread; notification on completion |
| Preview render (draft quality in-app) | P1 | Low-res proxy for quick feedback |

#### Rust Engine Architecture

```
┌───────────────────────────────────────────────┐
│               RENDER PIPELINE                 │
│                                               │
│  ┌─────────┐   ┌──────────┐   ┌───────────┐  │
│  │ Demuxer │──►│ Decoder  │──►│ Filter    │  │
│  │ (input) │   │ (HW acc) │   │ Graph     │  │
│  └─────────┘   └──────────┘   │ - color   │  │
│                               │ - scale   │  │
│  ┌─────────┐   ┌──────────┐   │ - overlay │  │
│  │ Demuxer │──►│ Decoder  │──►│ - trans.  │  │
│  │ (src 2) │   │          │   └─────┬─────┘  │
│  └─────────┘   └──────────┘         │        │
│                               ┌─────▼─────┐  │
│                               │ Encoder   │  │
│                               │ (H.264)   │  │
│                               └─────┬─────┘  │
│                                     │        │
│                               ┌─────▼─────┐  │
│                               │ Muxer     │  │
│                               │ → output  │  │
│                               └───────────┘  │
└───────────────────────────────────────────────┘
```

#### Key Types (Domain Layer)

```dart
class RenderConfig {
  final String projectId;
  final Resolution outputResolution;
  final VideoCodec codec;
  final int bitrateKbps;
  final int frameRate;
  final List<ClipSpec> clips;
  final List<EffectSpec> globalEffects;
  final AudioMixSpec? audioMix;
}

class ClipSpec {
  final String sourceVideoPath;
  final Duration inPoint;
  final Duration outPoint;
  final List<EffectSpec> effects;
  final TransitionSpec? transitionIn;
}

class RenderProgress {
  final double percentComplete;
  final Duration elapsed;
  final Duration estimatedRemaining;
  final RenderPhase currentPhase; // slicing, encoding, muxing
}
```

#### Architecture Notes

- The Rust side exposes a single async entry point: `render(RenderConfig) -> Stream<RenderProgress>`.
- Lossless slicing is used when the cut point aligns with a GOP boundary and no effects are applied to that clip — the Rust engine copies the encoded bitstream directly.
- GPU filter graph is a directed acyclic graph (DAG) of shader nodes compiled to the platform's shading language (GLSL → SPIR-V → Metal/D3D via `naga` or `shaderc`).
- **Remote timeslot zoom-pan**: When a timeslot is marked `remote`, the `sliceSubVideo` pipeline applies a smooth zoom (1.0×→1.7×) via ffmpeg's `zoompan` filter using `pzoom` accumulation. If the user sets a zoom-in center point (`centerX`/`centerY`) via the Zoom-in Point Configuration dialog, the zoom centers on that point instead of using the default center+pan. The filter pre-scales to 4000px width and fps-normalizes to 60fps before zoompan for crisp, smooth results.
- **Zoom-in Point Configuration dialog**: Before rendering, if any timeslot is remote, a modal dialog shows the first frame of each remote timeslot's video (extracted via `VideoProcessingService.extractFrame`). The user clicks to set a red mark — the (x, y) position is stored as normalized `centerX`/`centerY` (0.0–1.0) in the Timeslot. "Apply to all" (default) propagates the first mark to all remote timeslots; when unchecked, the "Next" button lets the user mark each timeslot individually.

---

### 5.4 User Module

**Purpose**: Manage user identity, per-user preferences, effect presets, and project history.

#### Features

| Feature | Priority | Notes |
|---|---|---|
| Local user profile (avatar, display name) | P0 | Stored in SQLite + app preferences |
| Effect preset library (save/load/share) | P0 | JSON-serialized filter parameters |
| Project history with thumbnails | P1 | Recent projects list |
| Export preset management | P1 | User-defined quality profiles |
| Cloud sync (optional, future) | P3 | iCloud / Google Drive backup of presets |
| App theme / language preferences | P2 | Dark/light mode; l10n |

#### Key Types (Domain Layer)

```dart
class UserProfile {
  final String id;
  final String displayName;
  final String? avatarPath;
  final DateTime createdAt;
}

class EffectPreset {
  final String id;
  final String name;
  final EffectCategory category; // color, blur, transition, text
  final Map<String, dynamic> parameters;
  final bool isBuiltIn;
  final DateTime updatedAt;
}

class UserPreferences {
  final ThemeMode themeMode;
  final String locale;
  final ExportPreset defaultExportPreset;
  final List<String> recentProjectIds;
}
```

---

## 6. Cross-Platform Strategy

### Code Sharing Breakdown

| Component | Shared % | Platform-Specific |
|---|---|---|
| Flutter UI (Widgets, Pages) | **98%** | Minimal per-platform theme tweaks |
| Domain Layer (Entities, Use Cases) | **100%** | Pure Dart; no platform deps |
| Data Layer — Dart (SQLite, prefs) | **95%** | Path resolution differs |
| Data Layer — Rust (FFmpeg, GPU) | **90%** | GPU backend binding, file-path encoding |
| **Overall** | **~92%** | |

### Platform-Specific Bridges

| Concern | Windows | macOS | Android | iOS |
|---|---|---|---|---|
| **GPU Backend** | Direct3D 11 | Metal 2 | OpenGL ES 3.0 / Vulkan | Metal 2 |
| **HW Decode** | DXVA2 / D3D11VA | VideoToolbox | MediaCodec | VideoToolbox |
| **File Picker** | `file_picker` | `file_picker` | SAF / `file_picker` | UIDocumentPicker |
| **Background Work** | Win32 job object | `NSBackgroundActivity` | `WorkManager` | `BGTaskScheduler` |
| **Notifications** | Toast (WinRT) | UserNotifications | NotificationCompat | UserNotifications |
| **FFmpeg Binary** | `.dll` bundled | `.dylib` bundled | `.so` via NDK | `.a` static link |

### Build System

```
highlight-creator/
├── app/                      # Flutter app entry point
│   ├── lib/
│   │   ├── presentation/     # Screens, Widgets, ViewModels
│   │   ├── domain/           # Entities, Use Cases, Interfaces
│   │   └── data/             # Repository impls, drift DAOs, FFI bridge
│   ├── android/
│   ├── ios/
│   ├── macos/
│   └── windows/
├── native/                   # Rust workspace
│   ├── core/                 # FFmpeg engine, render pipeline
│   ├── gpu/                  # GPU filter pipeline
│   ├── bridge/               # flutter_rust_bridge generated code
│   └── Cargo.toml
├── scripts/                  # Build scripts (FFmpeg compilation per target)
├── test/                     # Integration + e2e tests
└── docs/                     # Architecture, API docs
```

---

## 7. Data Layer

### Database Schema (SQLite via `drift`)

```
┌──────────────┐       ┌──────────────┐       ┌──────────────────┐
│  user_profile │       │   project    │       │    timeslot      │
├──────────────┤       ├──────────────┤       ├──────────────────┤
│ id (PK)      │◄──┐   │ id (PK)      │◄──┐   │ id (PK)          │
│ display_name │   │   │ name         │   │   │ project_id (FK)  │
│ avatar_path  │   │   │ user_id (FK) │───┘   │ video_source_id  │
│ created_at   │   │   │ created_at   │       │ in_point_ms      │
└──────────────┘   │   │ updated_at   │       │ out_point_ms     │
                   │   └──────────────┘       │ label            │
┌──────────────┐   │                          │ color_index      │
│   preset     │   │   ┌──────────────────┐   │ rating           │
├──────────────┤   │   │  video_source    │   │ created_at       │
│ id (PK)      │   │   ├──────────────────┤   └──────────────────┘
│ user_id (FK) │───┘   │ id (PK)          │
│ name         │       │ project_id (FK)  │
│ category     │       │ file_path        │
│ parameters   │       │ duration_ms      │
│ is_built_in  │       │ width / height   │
│ updated_at   │       │ codec_name       │
└──────────────┘       │ fps              │
                       │ thumbnail_path   │
                       └──────────────────┘
```

### File System Layout

```
{app_data_dir}/
├── database.sqlite
├── thumbnails/
│   └── {video_id}/
│       ├── sprite.jpg          # Thumbnail sprite sheet
│       └── waveform.png        # Audio waveform
├── cache/
│   └── preview/                # Low-res render previews
├── exports/                    # Final rendered videos
└── temp/                       # Intermediate encode files (cleaned on launch)
```

---

## 8. Performance Considerations

| Concern | Strategy |
|---|---|
| **Large video files (4K, long duration)** | Stream from disk; never load full video into RAM. Use FFmpeg's `avio` for buffered I/O. |
| **Scrubbing latency** | Pre-generate thumbnail sprite sheet (e.g., one thumbnail every 2 seconds). Seek to nearest keyframe + decode delta. |
| **Render time** | Parallel encode using `ffmpeg` filter graph with GPU acceleration. Show estimated time based on clip count × resolution. |
| **Memory pressure on mobile** | Cap concurrent decoders at 2. Use `media_kit`'s low-memory mode. Flush GPU textures when navigating away. |
| **Battery drain (mobile)** | Pause background render when battery < 20%. Use hardware encoder when available. |
| **Startup time** | Lazy-load Rust engine DLL/SO on first use. Defer FFmpeg codec registration until needed. |

---

## 9. Security & Licensing

### Security

- All file access is sandboxed per platform (App Sandbox on macOS/iOS, SAF on Android, app-local on Windows).
- User data never leaves the device unless the user explicitly enables a cloud-sync feature.
- FFmpeg input validation: reject files with suspicious codec parameters before opening.

### Licensing

The project is released under **LGPL-3.0** (see `LICENSE` / `COPYING`). To keep
that possible, the pipeline must not invoke GPL-only FFmpeg parts.

| Component | License | Obligation |
|---|---|---|
| Flutter | BSD-3 | Attribution |
| FFmpeg (CLI, separate process) | LGPL / GPL | Ship only an **LGPL build** (`configure` without `--enable-gpl`). Never bundle the GPL build (`libx264`, `libx265`, `libxvid`, `frei0r`, `libvidstab`, …). |
| Output video encoder | BSD-2 | `libopenh264` (LGPL-safe). GPL `libx264` is **not** used. |
| Rust crates | LGPL-3.0 | Attribution in about page |
| `media_kit` (preview) | MIT wrapper / LGPL libmpv | The Windows package ships a GPLv2+ `libmpv-2.dll`; `fetch_lgpl_deps.ps1` fetches an LGPL build and `app/windows/CMakeLists.txt` installs it over media_kit's after every build. |

**Rules**: FFmpeg is invoked as an external executable (never linked), and only
LGPL-compatible filters are used (`scale`, `pad`, `drawtext`, `drawbox`,
`zoompan`, `geq`, `overlay`, `fade`, `trim`, `concat`, `format`, `fps`, …).
The GPL-only `eq`, `boxblur`, and `hqdn3d` filters must stay unused. The H.264
encoder is `libopenh264` (BSD). Add a GPL filter/encoder only after explicit
legal review — it would relicense the whole distribution.

**LGPL binaries**: run `fetch_lgpl_deps.ps1` once per checkout. It verifies and
unpacks the LGPL FFmpeg (BtbN) into `tools/ffmpeg/` and the LGPL libmpv
(zhongfly) into `tools/mpv/`, and confirms the FFmpeg build has no
`--enable-gpl` and still provides `libopenh264`/`drawtext`/`geq`/`zoompan`.
