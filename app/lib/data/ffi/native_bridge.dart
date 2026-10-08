/// FFI bridge to the Rust native engine.
///
/// In production, this calls into the hc-bridge crate via flutter_rust_bridge.
/// During Phase 0, it provides stub implementations so the app compiles
/// and the architecture is wired correctly.
library;

/// Ping the native engine to verify the FFI link is alive.
Future<String> nativePing(String name) async {
  // When flutter_rust_bridge codegen is run:
  // return RustLib.instance.api.ping(name: name);
  return 'Hello, $name! Native engine stub (flutter_rust_bridge not yet generated).';
}

/// Initialize the native engine.
Future<void> initializeNativeEngine() async {
  // await RustLib.instance.api.initializeEngine();
}

/// Get version info from the native side.
Future<String> nativeEngineVersionInfo() async {
  // return RustLib.instance.api.engineVersionInfo();
  return 'hc-core: FFmpeg (LGPL build)\n'
      'hc-gpu: 0.1.0\n'
      'hc-bridge: 0.1.0 (stub)';
}
