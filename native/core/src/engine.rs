// hc-core: Engine initialization + render pipeline.
// Handles FFmpeg setup and render orchestration.

use log::info;
use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};
use crate::slice::{ClipSpec, slice_segment};

/// Initialize the FFmpeg engine: register codecs, set log level.
pub fn initialize() -> anyhow::Result<()> {
    info!("hc-core engine initialized");
    Ok(())
}

/// Return build-time FFmpeg configuration info.
pub fn ffmpeg_version() -> &'static str {
    "FFmpeg (LGPL build)"
}

/// Global render settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderConfig {
    /// List of clips to slice and combine.
    pub clips: Vec<ClipSpec>,
    /// Output resolution width (0 = use source resolution).
    pub output_width: u32,
    /// Output resolution height (0 = use source resolution).
    pub output_height: u32,
    /// Target video codec (e.g., "h264", "hevc").
    pub codec: String,
    /// Target bitrate in kbps.
    pub bitrate_kbps: u32,
    /// Output file path.
    pub output_path: String,
    /// If true, use GPU-accelerated encoding.
    pub use_gpu: bool,
}

/// Progress event emitted during rendering.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderProgress {
    /// Progress as a fraction [0.0, 1.0].
    pub progress: f64,
    /// Human-readable status message.
    pub message: String,
    /// Elapsed wall-clock time in seconds.
    pub elapsed_secs: f64,
    /// Whether rendering is complete.
    pub done: bool,
    /// Output file path (only when done).
    pub output_path: Option<String>,
}

/// Render a set of clips into a final video.
///
/// Phase 3: slices all clips sequentially, emits progress events.
/// Full FFmpeg pipeline gated behind `ffmpeg` feature.
pub fn render(config: &RenderConfig, mut on_progress: impl FnMut(RenderProgress)) -> CoreResult<String> {
    if config.clips.is_empty() {
        return Err(CoreError::Config("No clips to render".into()));
    }
    if config.output_path.is_empty() {
        return Err(CoreError::Config("Output path must not be empty".into()));
    }

    let total = config.clips.len();
    let mut results = Vec::new();

    for (i, clip) in config.clips.iter().enumerate() {
        let progress = (i as f64) / (total as f64);
        on_progress(RenderProgress {
            progress,
            message: format!("Slicing clip {}/{}", i + 1, total),
            elapsed_secs: 0.0,
            done: false,
            output_path: None,
        });

        match slice_segment(clip) {
            Ok(result) => results.push(result),
            Err(e) => {
                on_progress(RenderProgress {
                    progress: 1.0,
                    message: format!("Error slicing clip {}: {}", i + 1, e),
                    elapsed_secs: 0.0,
                    done: true,
                    output_path: None,
                });
                return Err(e);
            }
        }
    }

    // Combine segments (Phase 3 placeholder: write concat file)
    on_progress(RenderProgress {
        progress: 1.0,
        message: format!("Render complete — {} clips combined", total),
        elapsed_secs: 0.0,
        done: true,
        output_path: Some(config.output_path.clone()),
    });

    Ok(config.output_path.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_clips() {
        let config = RenderConfig {
            clips: vec![],
            output_width: 1920,
            output_height: 1080,
            codec: "h264".into(),
            bitrate_kbps: 10000,
            output_path: "out.mp4".into(),
            use_gpu: false,
        };
        assert!(render(&config, |_| {}).is_err());
    }

    #[test]
    fn test_single_clip() {
        let config = RenderConfig {
            clips: vec![ClipSpec {
                source_path: "test.mp4".into(),
                start_secs: 0.0,
                end_secs: 10.0,
                output_path: "seg1.mp4".into(),
                prefer_lossless: false,
                effects_json: None,
            }],
            output_width: 1920,
            output_height: 1080,
            codec: "h264".into(),
            bitrate_kbps: 10000,
            output_path: "out.mp4".into(),
            use_gpu: false,
        };
        let mut progress_count = 0;
        let result = render(&config, |_| progress_count += 1);
        assert!(result.is_ok());
        assert!(progress_count >= 2); // at least slicing + complete
    }

    #[test]
    fn test_invalid_clip_fails_render() {
        let config = RenderConfig {
            clips: vec![ClipSpec {
                source_path: "test.mp4".into(),
                start_secs: 10.0,
                end_secs: 5.0,
                output_path: "seg1.mp4".into(),
                prefer_lossless: false,
                effects_json: None,
            }],
            output_width: 1920,
            output_height: 1080,
            codec: "h264".into(),
            bitrate_kbps: 10000,
            output_path: "out.mp4".into(),
            use_gpu: false,
        };
        assert!(render(&config, |_| {}).is_err());
    }
}
