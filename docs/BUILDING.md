# Building Highlight Creator

This document describes how to set up a development environment and build
Highlight Creator on each supported platform.

## Prerequisites (all platforms)

- **Flutter SDK** ≥ 3.22 ([install guide](https://docs.flutter.dev/get-started/install))
- **Rust** ≥ 1.78 ([install via rustup](https://rustup.rs))
- **Git**

### Verify installations

```bash
flutter --version
rustc --version
cargo --version
git --version
```

---

## Windows

1. **Install Visual Studio 2022** with "Desktop development with C++" workload
   (required for Rust's MSVC toolchain and Windows FFI).

2. **Install Flutter desktop support**:
   ```powershell
   flutter config --enable-windows-desktop
   ```

3. **Install Rust Windows target** (if not default):
   ```powershell
   rustup target add x86_64-pc-windows-msvc
   ```

4. **Clone and install dependencies**:
   ```powershell
   git clone <repo-url> highlight-creator
   cd highlight-creator\app
   flutter pub get
   ```

5. **Build and run**:
   ```powershell
   cd app
   flutter run -d windows
   ```

---

## macOS

1. **Install Xcode** (from App Store) and command-line tools:
   ```bash
   xcode-select --install
   ```

2. **Install Flutter desktop support**:
   ```bash
   flutter config --enable-macos-desktop
   ```

3. **Install Rust macOS target**:
   ```bash
   rustup target add aarch64-apple-darwin x86_64-apple-darwin
   ```

4. **Clone and install**:
   ```bash
   git clone <repo-url> highlight-creator
   cd highlight-creator/app
   flutter pub get
   ```

5. **Build and run**:
   ```bash
   flutter run -d macos
   ```

---

## Android

1. **Install Android Studio** with Android SDK (API 34+).

2. **Install Rust Android targets**:
   ```bash
   rustup target add aarch64-linux-android x86_64-linux-android
   ```

3. **Install Android NDK** (via Android Studio SDK Manager).

4. **Clone and install**:
   ```bash
   git clone <repo-url> highlight-creator
   cd highlight-creator/app
   flutter pub get
   ```

5. **Build APK**:
   ```bash
   flutter build apk --debug
   ```

6. **Run on device/emulator**:
   ```bash
   flutter run -d android
   ```

---

## iOS

1. **Install Xcode** (App Store, macOS required).

2. **Install Rust iOS target**:
   ```bash
   rustup target add aarch64-apple-ios
   ```

3. **Clone and install**:
   ```bash
   git clone <repo-url> highlight-creator
   cd highlight-creator/app
   flutter pub get
   cd ios && pod install && cd ..
   ```

4. **Build for simulator**:
   ```bash
   flutter build ios --no-codesign --debug
   ```

5. **Run on simulator**:
   ```bash
   flutter run -d ios
   ```

---

## Rust Native Engine

The native engine is built as part of the Flutter build when
`flutter_rust_bridge` is configured. To build and test the Rust code
independently:

```bash
cd native

# Build all crates
cargo build --workspace

# Run all tests
cargo test --workspace

# Run clippy lints
cargo clippy --all-targets -- -D warnings

# Format
cargo fmt --all
```

---

## Optional: local voice cloning plugin

The Top-5 "my own voice" feature needs a separately installed plugin (Python +
CUDA + a 5.2 GB model, ~15 GB total). It is never bundled with the app.

    tools\voice_clone\setup.bat          # install / re-run to repair
    tools\voice_clone\setup.bat --check  # report state only

See [voice_clone.md](voice_clone.md) for prerequisites, the voice-pack format,
troubleshooting and the worker protocol.
## Code Generation

After modifying database tables or adding new `flutter_rust_bridge` API
functions, regenerate the binding code:

```bash
# Drift database code
cd app
dart run build_runner build

# flutter_rust_bridge code (when configured)
cd native/bridge
flutter_rust_bridge_codegen generate
```
