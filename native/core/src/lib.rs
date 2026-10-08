// hc-core: Video processing engine
// Handles FFmpeg decode/encode, slicing, muxing, and audio processing.

pub mod engine;
pub mod slice;
pub mod audio;
pub mod thumbnail;

/// Core error types for the video processing engine.
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("FFmpeg error: {0}")]
    Ffmpeg(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Invalid configuration: {0}")]
    Config(String),

    #[error("Codec not supported: {0}")]
    UnsupportedCodec(String),
}

pub type CoreResult<T> = Result<T, CoreError>;
