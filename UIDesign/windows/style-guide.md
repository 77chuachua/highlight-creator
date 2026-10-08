# Windows UI — Visual Style Guide

> Color palette, typography, spacing, and iconography for the Windows desktop app.

---

## 1. Color Palette

### Dark Theme (Default)

| Token | Hex | Usage |
|---|---|---|
| `surface` | `#0D0D0D` | Window background |
| `surfaceContainer` | `#1A1A2E` | Cards, panels, control bar |
| `surfaceContainerHighest` | `#262640` | Elevated surfaces, table rows |
| `primary` | `#6C63FF` | Accent color (purple-blue) |
| `primaryContainer` | `#1A1A3E` | Selected items, chips |
| `onPrimary` | `#FFFFFF` | Text on primary |
| `onSurface` | `#E0E0E0` | Primary text |
| `onSurfaceVariant` | `#9E9E9E` | Secondary text |
| `outline` | `#3A3A5C` | Borders, dividers |
| `error` | `#EF5350` | Error states |

### Timeslot Colors

| Index | Name | Hex | Preview |
|---|---|---|---|
| 0 | Blue | `#42A5F5` | 🔵 |
| 1 | Red | `#EF5350` | 🔴 |
| 2 | Green | `#66BB6A` | 🟢 |
| 3 | Orange | `#FFA726` | 🟠 |
| 4 | Purple | `#AB47BC` | 🟣 |
| 5 | Cyan | `#26C6DA` | 🔷 |
| 6 | Pink | `#EC407A` | 🩷 |
| 7 | Brown | `#8D6E63` | 🟤 |

### Rating Colors
- Stars: `#FFD700` (Gold)
- Empty stars: `#616161` (Grey)

### Video Player
- Background: `#000000` (Pure black)
- Controls overlay gradient: `#000000` @ 80% → transparent
- Scrub bar track: `#FFFFFF` @ 24% opacity
- Scrub bar filled: `primary`
- Scrub bar thumb: `primary`, 12px diameter
- Playhead: `#FF3D00` (Red), 2px wide

### Export Progress
- Progress bar fill: `primary`
- Progress bar track: `#3A3A5C`
- Complete icon: `#4CAF50` (Green)

---

## 2. Typography

### Font Family
- **Primary**: `Segoe UI` (Windows system font)
- **Monospace**: `Cascadia Code` / `Consolas` (timestamps, code)

### Type Scale

| Token | Size | Weight | Letter Spacing | Usage |
|---|---|---|---|---|
| `displayLarge` | 32px | 700 | -0.5px | (reserved) |
| `headlineMedium` | 24px | 600 | 0 | Video title, section headers |
| `titleLarge` | 20px | 600 | 0 | Panel titles |
| `titleMedium` | 16px | 500 | 0.15px | List item titles |
| `titleSmall` | 14px | 500 | 0.1px | Section headers, button labels |
| `bodyLarge` | 16px | 400 | 0.5px | Body text |
| `bodyMedium` | 14px | 400 | 0.25px | Secondary text, table cells |
| `bodySmall` | 12px | 400 | 0.4px | Captions, metadata |
| `labelMedium` | 12px | 500 | 0.5px | Button text, chips |
| `labelSmall` | 10px | 400 | 0.5px | Status bar, timestamps |

### Monospace Variants (for timestamps, codec info)
- 14px / 400: `Duration: 45:30`
- 12px / 400: `1920×1080 · H.264 · 30fps`
- 11px / 400: `01:23.5 / 05:30.0`

---

## 3. Spacing

### Grid System (8px base unit)

| Token | Value | Usage |
|---|---|---|
| `xxs` | 4px | Icon padding, tight gaps |
| `xs` | 8px | Item padding, small gaps |
| `sm` | 12px | Card padding, list item gaps |
| `md` | 16px | Section margins, panel padding |
| `lg` | 24px | Major section spacing |
| `xl` | 32px | Page margins |
| `xxl` | 48px | Hero spacing |

### Panel Dimensions

| Element | Size |
|---|---|
| Toolbar height | 40px |
| Control panel height | 56px |
| Status bar height | 24px |
| Source file list width | 320px |
| Thumbnail strip height | 60px |
| Timeslot table min height | 150px |
| Timeslot table row height | 40px |
| Video controls overlay margin | 16px from edges |
| Center play button | 72×72px |
| Scrub bar height | 32px (touch area) / 4px (visual) |

---

## 4. Border Radius

| Element | Radius |
|---|---|
| Cards, panels | 8px |
| Buttons (filled) | 20px (pill shape) |
| Buttons (outlined) | 8px |
| Input fields | 4px |
| Thumbnails | 4px |
| Color swatches | Circle (50%) |
| Tooltips | 4px |
| Menu dropdowns | 8px |

---

## 5. Elevation (Shadows)

| Level | Value | Usage |
|---|---|---|
| 0 | None | Flat surfaces |
| 1 | `0 1px 3px rgba(0,0,0,0.4)` | Cards, control panel |
| 2 | `0 4px 8px rgba(0,0,0,0.5)` | Dropdowns, tooltips |
| 3 | `0 8px 24px rgba(0,0,0,0.6)` | Dialogs, menus |

---

## 6. Iconography

### Icon Set: Material Icons (Rounded)

| Context | Icon | Size |
|---|---|---|
| Video file | `video_library_outlined` | 20px |
| Play | `play_arrow` | 24px / 44px |
| Pause | `pause` | 24px / 44px |
| Stop | `stop` | 24px |
| Seek back 5s | `replay_5` | 24px |
| Seek forward 5s | `forward_5` | 24px |
| Mark In | `flag` | 20px |
| Mark Out | `outlined_flag` | 20px |
| Undo | `undo` | 20px |
| Redo | `redo` | 20px |
| Volume | `volume_up` / `volume_down` / `volume_off` | 20px |
| Speed | `speed` | 20px |
| Add file | `add` | 20px |
| Remove file | `close` | 16px |
| Folder | `folder_open` | 20px |
| Export | `file_download` | 20px |
| Settings | `settings` | 20px |
| Star (filled) | `star` | 16px |
| Star (empty) | `star_border` | 16px |
| Edit | `edit` | 16px |
| Delete | `delete_outline` | 16px |
| Template editor | `tune` | 20px |
| Font family | `font_download` | 20px |
| Color palette | `palette` | 20px |
| Restore defaults | `restart_alt` | 20px |

---

## 7. Animations & Transitions

| Animation | Duration | Curve |
|---|---|---|
| Controls overlay fade in | 200ms | `easeOut` |
| Controls overlay fade out | 500ms | `easeIn` |
| Panel collapse/expand | 250ms | `easeInOut` |
| Button press feedback | 100ms | `easeInOut` |
| Page transitions | 200ms | `easeOut` |
| Progress bar fill | 300ms | `linear` |
| Hover scale (thumbnails) | 150ms | `easeOut` |
| List item insert/remove | 200ms | `easeInOut` |
| Preview regen scrim fade | 200ms | `easeOut` |
| Template card select | 120ms | `easeOut` |

---

## 8. Scrollbar Styling

- Width: 6px
- Track: transparent
- Thumb: `Colors.white24`
- Thumb hover: `Colors.white38`
- Border radius: 3px
