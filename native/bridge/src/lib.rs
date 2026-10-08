// hc-bridge: flutter_rust_bridge API surface.
// This crate exposes Rust functions to Dart via FFI.
//
// flutter_rust_bridge codegen scans this file's public functions
// and generates the corresponding Dart bindings.

use anyhow::Context;

/// Ping the Rust side to verify FFI connectivity.
/// Returns a greeting string.
#[flutter_rust_bridge::frb(sync)]
pub fn ping(name: String) -> String {
    format!("Hello, {}! Rust engine is alive.", name)
}

/// Initialize the native engine (FFmpeg + GPU backends).
/// Call once at app startup before any video processing.
pub fn initialize_engine() -> anyhow::Result<()> {
    log::info!("Initializing native engine...");

    hc_core::engine::initialize()
        .context("Failed to initialize hc-core engine")?;

    hc_gpu::initialize_backend()
        .context("Failed to initialize hc-gpu backend")?;

    log::info!("Native engine initialized successfully");
    Ok(())
}

/// Return version info for the native engine components.
pub fn engine_version_info() -> String {
    format!(
        "hc-core: {}\nhc-gpu: {}\nhc-bridge: {}",
        hc_core::engine::ffmpeg_version(),
        "0.1.0",
        env!("CARGO_PKG_VERSION"),
    )
}

/// Validate that a video file can be opened and its format is recognized.
pub fn validate_video_file(path: String) -> anyhow::Result<String> {
    // Phase 3: use ffmpeg-next to probe the file.
    // For Phase 0, just validate the path is non-empty and the file exists
    // as a basic smoke test of the FFI plumbing.
    if path.is_empty() {
        anyhow::bail!("Empty file path");
    }

    let file_path = std::path::Path::new(&path);
    if !file_path.exists() {
        anyhow::bail!("File not found: {}", path);
    }

    Ok(format!("File validated: {} ({} bytes)", path, std::fs::metadata(&path)?.len()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ping_returns_greeting() {
        let result = ping("World".into());
        assert!(result.contains("Hello"));
        assert!(result.contains("World"));
    }

    #[test]
    fn test_validate_rejects_empty_path() {
        assert!(validate_video_file("".into()).is_err());
    }

    #[test]
    fn test_engine_version_info_is_non_empty() {
        let info = engine_version_info();
        assert!(!info.is_empty());
    }
}
