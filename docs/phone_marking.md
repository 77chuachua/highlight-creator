# Phone marking (phone as a second screen)

Marking clips on a phone while the footage lives on the PC. The phone never sees
the original: the desktop transcodes a 720p proxy and serves it, the phone records
in/out points against that proxy, and the marks land in the open project.

Decisions locked with the product owner:

| Item | Decision |
|---|---|
| Multi-user | **No.** One phone, one person. |
| Proxy | Generated **in the background** on first open of a source. |
| Playback quality | **Proxy only** (720p). The phone never sees 4K. |
| Entry point | **QR code** shown by the desktop. |
| Desktop flow | Open app → import sources → show QR → phone marks. |

## Flow

```
PC    import sources (card copied in) → project with a date
PC    click "Phone marking" → dialog: QR + URL
Phone scan QR (same Wi-Fi) → page lists sources
Phone pick a source → plays the 720p proxy → mark in → mark out → description → rating → save
PC    the new time slots appear (poll every 2 s; manual refresh too)
PC    tweak (snap to keyframe, edit text) → Make / Top-5 (optionally cloned voice)
```

The phone produces **time slots in the open project**; nothing is exported or
imported. (`docs/hlcproj_format.md` is for the *offline* companion case only.)

## Why the proxy keeps the timeline identical

```
ffmpeg -i <source> -vf scale=-2:720 -c:v libx264 -preset veryfast -crf 28 -c:a aac <proxy>.mp4
```

Only the resolution changes: no trim, no fps change, no audio offset. So a mark at
`00:12:34.2` on the proxy **is** `00:12:34.2` on the source — no time mapping code,
no rounding bugs. This single rule is what keeps the feature small.

Cost: 24 GB 4K → roughly 2–4 GB per proxy, 5–10 minutes of background CPU.

## Storage

`%USERPROFILE%\HighlightCreator\temp\proxy\<sha1-of-source-path>.mp4`

Under `temp\` on purpose: the existing **Cache files** dialog can clear it, so the
feature needs no new cleanup UI. A `.json` sidecar next to it records
`{sourcePath, proxyPath, state: queued|working|ready|failed, progress: 0-100,
error, sizeBytes, updatedAt}` so an interrupted transcode restarts instead of
being served half-written.

`ProxyCache` (`lib/services/proxy_cache.dart`) owns the queue:

- one ffmpeg at a time, `-progress pipe:1` parsed against the source duration the
  project already knows (no ffprobe round trip);
- output goes to `<sha1>.tmp.mp4` and is renamed to `<sha1>.mp4` only on exit
  code 0, so a killed or failed run can never be played;
- the ffmpeg path comes from `VideoProcessingService.findFfmpeg()` — the same
  PATH / beside-the-exe / `tools\` / `C:\ffmpeg\bin` chain the renderer uses;
- stopping the server or closing the app kills the child process
  (`ProxyCache.shutdownAll()` sits beside `LocalVoiceService.shutdown()` in
  `main_window.dart`, because `exit(0)` gives no chance to await anything). A
  hard kill from Task Manager can still orphan ffmpeg; the `.tmp.mp4` it leaves
  is simply transcoded again next time.

## HTTP surface (loopback + LAN, token in the URL)

| Method | Path | Purpose |
|---|---|---|
| GET | `/?t=<token>` | The marking page |
| GET | `/api/sources?t=` | `[{id, name, durationMs, proxy: "ready"\|"working"\|"queued"\|"failed", progress}]` |
| GET | `/media/<id>?t=` | The proxy file, **Range** supported (the browser needs it to seek) |
| POST | `/api/slot?t=` | `{sourceId, inPointMs, outPointMs, description, rating}` → creates a time slot |
| GET | `/api/slots?t=` | Current slots, so the phone shows what it already marked |

`/media/<id>` answers: 200 with the whole file and `Accept-Ranges: bytes` when
there is no `Range` header, 206 + `Content-Range: bytes start-end/total` for a
range, 416 (+ `Content-Range: bytes */total`) when the range starts past EOF, 409
with **no body** while the proxy is not ready, 404 for an id that is not in the
open project. Always `Content-Type: video/mp4`.

`/api/sources` reports the live `state.name` (`queued`, `working`, `ready`,
`failed`) and `progress` 0–100. The first `/api/sources` or `/media` request of a
server run queues every source without a proxy; the page polls it every 2 s and
starts playing a source as soon as it flips to `ready`.

Rules:

- token compared in constant time; wrong token → 403, no content
- `/media/` only serves ids from the whitelist built from the **open project's**
  sources — never a path from the request. The file name is recomputed from the
  source's path (`sha1`), and a path inside the sidecar is ignored
- listen on the LAN but answer only for the token; no directory listing
- a transcode that fails stays `failed` for that server run; Stop → Open retries

## Desktop side

- A `PhoneMarkingServer` service: start/stop, owns the `HttpServer`, the proxy
  queue (one ffmpeg at a time, background), and the token.
- One button in the control panel ("手机打点" / "Phone marking") → dialog with the
  QR and the URL. The proxy progress is shown on the phone page; a progress list in
  the desktop dialog is still to do.
- The QR is rendered in Flutter (`qr_flutter`, pure Dart) so no native dependency
  and no network.
- After each poll the project's slots refresh; new slots are tagged as
  phone-originated so the user knows where they came from.

## Build order (each step independently testable)

1. **Server skeleton + QR.** `HttpServer`, token check, `/api/sources`,
   QR dialog. Success test: scan → page loads → source list visible. If the phone
   cannot reach it, stop here — that is almost always the Windows firewall blocking
   inbound connections on the port.
2. **Proxy + playback.** Background transcode, `/media/<id>` with Range, `<video>`
   and in/out buttons. Success test: scrub a 24 GB source on the phone smoothly.
   *Implemented* (step 2): `ProxyCache` + `/media` + selectable source list with a
   live progress bar; the in/out buttons belong to step 3.
3. **Write-back.** `POST /api/slot` → project slot → desktop refresh. Success test:
   mark three moments on the phone, run Top-5 on the PC, they are in the reel.

## Known ceilings (state them in the UI, not just here)

- Browser seek accuracy is a few frames → phone marks are **coarse**; the desktop
  step must offer "snap to nearest keyframe".
- First open of a source is slow until its proxy exists; show progress instead of
  a spinner.
- Windows firewall prompts on first listen; the dialog should say "allow on private
  networks".
- One phone at a time is the supported mode (by decision, not by limitation).
