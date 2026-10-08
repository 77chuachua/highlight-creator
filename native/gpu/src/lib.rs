// hc-gpu: GPU-accelerated video effect pipeline.
// Abstracted over Metal (macOS/iOS), D3D11 (Windows), and OpenGL ES (Android).

pub mod filter;
pub mod shader;

/// Error types for GPU operations.
#[derive(Debug, thiserror::Error)]
pub enum GpuError {
    #[error("Shader compilation failed: {0}")]
    ShaderCompilation(String),

    #[error("Texture allocation failed: {0}")]
    TextureAllocation(String),

    #[error("GPU backend not available: {0}")]
    BackendUnavailable(String),
}

pub type GpuResult<T> = Result<T, GpuError>;

/// Initialize the GPU backend for the current platform.
pub fn initialize_backend() -> GpuResult<()> {
    // Placeholder: select backend based on platform.
    // Phase 3 will implement per-platform initialization.
    log::info!("hc-gpu backend initialized (no-op placeholder)");
    Ok(())
}
