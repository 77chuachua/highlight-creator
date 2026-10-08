# highlight_creator

Cross-platform video highlight creator with effects.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.22.0
- [Rust toolchain](https://rustup.rs/) (stable, edition 2024) — for the native FFI bridge
- [ffmpeg](https://ffmpeg.org/) (optional) — bundled under `tools/ffmpeg/` for Windows;
  the app falls back to simulation mode when ffmpeg is unavailable

## Building

### Windows (desktop)

```bash
# From the project root:
cd app
flutter pub get
flutter build windows
```

The executable lands in `app/build/windows/x64/runner/Release/`.

For a debug build with hot-reload:

```bash
flutter run -d windows
```

### Web

```bash
flutter run -d chrome
```

## Running tests

All commands are run from the `app/` directory.

### Unit / widget tests

```bash
flutter test
```

### Run a single test file or test case

```bash
# One file
flutter test test/e2e/use_case_test.dart

# One test by name (substring match)
flutter test --plain-name "Timeslot ordering" test/e2e/use_case_test.dart
```

### End-to-end test (full pipeline)

The E2E test (`test/e2e/use_case_test.dart`) exercises the complete
highlight-creator pipeline: add videos, mark timeslots via UI, run the Make
pipeline, and verify output files.  It requires the test video fixtures under
`test/e2e/videoSource/`.

The Make step calls ffmpeg to encode transition + sub-clip videos — this can
take **2–5 minutes** depending on your CPU.  You can run the faster tests
without the full pipeline:

```bash
# Skip the slow full-pipeline test
flutter test --plain-name "ordering" test/e2e/use_case_test.dart
flutter test --plain-name "zero"     test/e2e/use_case_test.dart
```

### Analyze (lint / static checks)

```bash
dart analyze
```

## Project structure (highlights)

| Path | Purpose |
|------|---------|
| `lib/main.dart` | App entry point |
| `lib/presentation/` | UI layer (screens, widgets, Riverpod ViewModels) |
| `lib/domain/` | Entities and repository interfaces |
| `lib/data/` | Repository implementations, FFI bridge, video processing |
| `lib/di/` | Dependency injection (GetIt + Riverpod) |
| `test/` | Unit, widget, and E2E tests |
| `test/e2e/videoSource/` | Fixture video files for E2E tests |
| `../native/` | Rust native library (bridge, core, GPU) |
| `../tools/ffmpeg/` | Portable ffmpeg binaries for Windows |
