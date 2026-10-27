# `.hlcproj` format — companion-app interface

`*.hlcproj` is Highlight Creator's project file: a UTF-8 JSON document that a
project is saved as (and autosaved as, named after the project date, e.g.
`2026-10-21.hlcproj`).

It exists so that **the picking can happen somewhere other than the desktop**.
A phone or tablet app can read footage straight off the camera card, record the
moments the user wants, and hand the desktop the resulting file: the desktop
then does the heavy work (re-encode, transitions, Top-5 reels, voice cloning)
where the CPU and GPU are. The companion never renders anything.

Target version: **schema 1** (the reader tolerates unknown keys and missing
optional keys, so a companion can start with the minimal shape below).

## Minimal file a companion has to produce

```json
{
  "name": "2026-10-21 训练赛",
  "date": "2026-10-21",
  "sources": [
    {
      "id": "src-1",
      "filePath": "D:\\DCIM\\GOPR0001.MP4",
      "durationMs": 1520000,
      "width": 3840,
      "height": 2160,
      "codecName": "hevc",
      "fps": 59.94
    }
  ],
  "timeslots": [
    {
      "id": "slot-1",
      "videoSourceId": "src-1",
      "inPointMs": 634000,
      "outPointMs": 642000,
      "description": "10 号远射破门",
      "rating": 5
    }
  ]
}
```

That is enough for the desktop to open the project with the clips marked. Every
other field below is optional and the desktop fills in defaults.

## Top level

| Key | Type | Required | Meaning |
|---|---|---|---|
| `name` | string | no (default `New Project`) | Shown in the title bar. |
| `date` | string `yyyy-mm-dd` | **recommended** | The day the footage belongs to. It decides which week/month/year a Top-5 reel lands in — without it the desktop falls back to the file name, then to today. **Send this.** |
| `sources` | array | yes (may be empty) | The video files. |
| `timeslots` | array | yes (may be empty) | The marked moments. |
| `templateSelections` | object `string → string?` | no | Ids of the startup / transition / ending / bgm templates chosen in the desktop app. A companion should omit it: the desktop keeps whatever the user picked last. |

## `sources[]`

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | **yes** | Any unique string. `timeslots[].videoSourceId` must match it exactly. |
| `filePath` | string | **yes** | Absolute path as the *desktop* will see it. See "Paths" below. |
| `durationMs` | int | recommended | Length in milliseconds; the desktop re-probes the file and corrects it if you are wrong, but a wrong value makes the first open slower. |
| `width`, `height` | int | recommended | Pixels. `0` is accepted. |
| `codecName` | string | no | e.g. `hevc`, `h264`. Informational. |
| `fps` | number | no | e.g. `59.94`. Informational. |

## `timeslots[]`

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | **yes** | Any unique string. |
| `videoSourceId` | string | **yes** | Must equal one `sources[].id`. A slot whose source is missing is ignored on load. |
| `inPointMs`, `outPointMs` | int | **yes** | Mark in/out in milliseconds from the start of the source. `outPointMs` must be greater than `inPointMs`; non-positive clips are dropped. |
| `description` | string | recommended | The caption. It is burned into the transition card and is what the narration is written against, so this is the field that carries the user's intent. |
| `rating` | int `0–5` | recommended | Star rating; 5 is best. The top-5 picker sorts and filters by it. `0` means unrated. |
| `label` | string | no | Coloured tag text. |
| `colorIndex` | int | no (default 0) | Which tag colour, 0–n. |
| `remote` | bool | no (default false) | Marks a remote-camera shot; the desktop applies its 1×→1.7× zoom-pan to these. |
| `centerX`, `centerY` | number `0–1` | no (default 0.5) | Where the zoom should look, as a fraction of the frame. Only read when `remote` is true. |
| `elapse` | int | no (default 0) | Reserved; send `0`. |
| `filename` | string | no | Base name of the source file. The desktop uses it as a fallback to re-link a source whose path moved, so sending it makes projects portable between machines. |

## Paths

`filePath` must be the path **on the machine that renders**. Two practical
consequences:

- A phone writing `content://…` or a card-relative path produces a project the
  desktop cannot open. Write the path the user will see after copying the card
  in, or let the companion export and the user fix the root on the desktop.
- `filename` is the portable half: the desktop can re-link by base name when the
  absolute path is wrong. Always send `filename` too.

## What the desktop does with the file

1. Creates a project whose date is `date` (this is the Top-5 period anchor).
2. Loads the sources, probing each file for real duration/size/codec.
3. Loads the slots, dropping any whose source is missing or whose range is empty.
4. Opens the project — the user then runs Make (transition reel) or picks a
   Top-5/Top-10 reel, optionally with a cloned voice.

## Writing a companion: order of work

1. `sources` + `inPointMs/outPointMs` only — the smallest thing that is useful.
2. Add `description` and `rating`; they are what make the Top-5 picker usable.
3. Add `remote` + `centerX/centerY` if the camera is a remote/wide rig.
4. Never write `templateSelections` or Top-5 entries: those belong to the desktop.

## Compatibility rules for the desktop side

- Unknown keys are ignored, never rejected.
- A missing `date` falls back to the file name, then to today.
- Invalid slots (unknown source, empty range, both points `0`) are skipped, not
  fatal — a partially valid file still opens.
- `schema` is not written today; treat the file as schema 1 and keep any new
  required field additive.
