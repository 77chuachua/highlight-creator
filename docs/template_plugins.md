# Template plugins

The four built-in template sets ship with the app and never change. On top of
those, a **plugin template** is published in a catalogue (a `manifest.json`
hosted on GitHub, served over raw.githubusercontent.com). When the template
config dialog opens it fetches the catalogue; picking a catalogue card
downloads that template's script and renders it with the same ffmpeg the
built-in sets already use.

Nothing downloaded is code. A script is an **ffmpeg filtergraph** — the same
`geq` / `drawtext` / `fade` language the built-in scenes are written in — and it
is vetted before ffmpeg sees it.

## Catalogue format

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-10-04",
  "templates": [
    {
      "id": "ember-grid",
      "name": "Ember Grid",
      "description": "Warm grid intro with a slow ember bloom.",
      "author": "your-name",
      "type": "startup",
      "previewUrl": "https://.../ember-grid.jpg",
      "script": {
        "url": "https://raw.githubusercontent.com/<you>/<repo>/main/ember-grid.ffscript",
        "sha256": "9f2c…64 hex chars…",
        "sizeBytes": 812,
        "revision": "r1"
      },
      "render": {
        "durationSecs": 4.0,
        "width": 1280,
        "height": 720,
        "withBgm": false
      }
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `schemaVersion` | no | Omit or use `1`. A newer number is refused with "update Highlight Creator". |
| `templates[].id` | yes | Unique in the file, `[A-Za-z0-9._-]`, ≤64 chars. Doubles as the cache key. |
| `templates[].name` | yes | Shown on the card. |
| `templates[].type` | yes | `startup`, `transition` or `ending`. |
| `templates[].description`, `author`, `previewUrl` | no | `previewUrl` is best-effort; a broken image never blocks generation. |
| `script.url` | yes | Must be `http://` or `https://`. |
| `script.sha256` | no | 64 lowercase hex. Strongly recommended — see below. |
| `script.sizeBytes` | yes | Byte length of the file, **including** the trailing newline. Always checked. |
| `script.revision` | no | `[A-Za-z0-9._-]`. Defaults to the first 12 chars of the hash, then `1`. |
| `render.*` | no | Defaults: 4.0 s, 1280×720, no BGM. Width/height must be even. |

Unknown fields are ignored, so you can add metadata without breaking older
builds. Anything malformed is refused by name — the error names the template and
the field, so a bad catalogue is never silently half-loaded.

### Publishing an update

Bump `revision` (or change the script so its hash changes). The cache filename
embeds it, so a new revision is a new file and the old render is bypassed with
no cache bookkeeping on either side.

## Script format

A single line of ffmpeg filter syntax. Leading/trailing whitespace is fine;
interior newlines are not.

```
format=rgb24,geq=r='18+26*(Y/H)':g='12+16*(Y/H)':b='10+14*(Y/H)',format=yuv420p,scale=1280:720:flags=lanczos,fps=30,fade=t=in:st=0:d=0.5,fade=t=out:st=3.4:d=0.6
```

The graph is handed to ffmpeg as `-vf`, and `geq` runs at **half** the render
resolution before being scaled up — the same trick the built-in sets use, so
scale up inside your graph with `scale=W:H`.

### Limits

- **30 000 characters.** Windows caps a command line at 32767 and the graph is
  inlined into it. The built-in nocturne scene is ~14 kB.
- Only the allowlisted filters below are accepted.
- No interior newlines, and no file-reading options.

## Filter allowlist

Accepted: `color` `anullsrc` `nullsrc` `format` `geq` `scale` `fps` `fade`
`drawtext` `drawbox` `trim` `setpts` `split` `copy` `setsar` `pad` `crop`
`overlay` `negate` `curves` `hue` `colorchannelmixer` `colorbalance` `rotate`
`loop` `reverse` `select` `tile` `hstack` `vstack` `volume` `afade` `aformat`
`aresample` `apad` `atrim` `asetpts` `amerge` `channelsplit`

Rejected, with a reason:

- Anything not on the list — including `movie` / `amovie`, which read the disk.
- `drawtext=textfile=…` — use inline `text=` instead.
- The **GPL** filters. `eq`, `boxblur`, `hqdn3d`, `delogo`, `pp*`, `frei0r*`,
  `ocr`, `vidstab*` are not compiled into the LGPL ffmpeg this app ships, so
  naming one would only produce a template that fails at render time. The
  allowlist is generated from what the build actually contains, which keeps the
  two constraints from drifting apart.

The list and the parser live in `app/lib/services/template_filter_policy.dart`.

## Integrity

`sizeBytes` is always verified. `sha256` is strongly recommended: without it a
wrong-but-same-size file renders into a **wrong template** under the right name,
which is worse than a loud failure. With it, a tampered or corrupted download is
rejected before anything touches disk.

Compute it with:

```powershell
Get-FileHash ember-grid.ffscript -Algorithm SHA256 | % Hash
```

## Failure reporting

The three failure modes are separate types with separate messages, because the
remedies differ:

| Failure | Meaning |
|---|---|
| `TemplatePluginManifestError` | The catalogue could not be fetched or parsed. A cached copy is used when one exists; the dialog shows a note, not an error, and the built-in sets stay fully usable. |
| `TemplatePluginDownloadError` | Network failure, HTTP status, size mismatch, or hash mismatch. Reports the URL. |
| `TemplatePluginRejectedError` | Downloaded fine, but the policy refuses it. Reports the offending filter. |
| `TemplatePluginRenderError` | Allowed and downloaded, but ffmpeg refused or produced nothing. Carries the tail of ffmpeg's stderr. |

A failed render deletes its partial file, so the next click retries instead of
caching a broken video.

## Caching

Under `%USERPROFILE%\HighlightCreator\templates\`:

```
manifest.json                    last good catalogue (reused for 6 h)
plugins/<id>_<revision>.ffscript verified filtergraph
plugins/<id>_<revision>.mp4      rendered result
```

Because the rendered file is cached, a second click is instant and costs no
network. `TemplatePluginService.invalidateAll()` clears everything.

## Pointing at your own catalogue

`TemplatePluginService.manifestUrl` is a static field. Change its default, or set
it at startup to point at a fork:

```dart
TemplatePluginService.manifestUrl =
    'https://raw.githubusercontent.com/you/templates/main/manifest.json';
```

## Authoring a script

The fastest way to write one is to copy what the app generates. Every render
appends its full ffmpeg command line to `ffmpeg_command` at the repo root, so
you can build a look in the app, open `ffmpeg_command`, lift the `-vf` value,
and trim it into a script.

Start from the built-in scenes:

- `app/lib/data/ffi/video_processing_service.dart` — `_nocturneLayers`
  (volumetric shafts, mowed pitch, anamorphic streak), `_sunLayers`,
  `_skyLayers`, `_greenLayers`.
- `app/test/e2e/design_sets_test.dart` — renders each set and logs its command.
