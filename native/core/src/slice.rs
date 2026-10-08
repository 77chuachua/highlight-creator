// hc-core: Video slicing engine.
// Cuts segments from source videos — fast path (GOP-aligned copy)
// and normal path (decode → optional filter → encode → mux).

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

/// Specification for a single clip segment in the output.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipSpec {
    /// Path to the source video file.
    pub source_path: String,
    /// Start time in seconds.
    pub start_secs: f64,
    /// End time in seconds.
    pub end_secs: f64,
    /// Output path for the sliced intermediate segment.
    pub output_path: String,
    /// If true, attempt lossless (GOP-aligned) bitstream copy.
    pub prefer_lossless: bool,
    /// Optional effect parameters to apply (JSON-encoded filter graph).
    pub effects_json: Option<String>,
}

/// Result of a slice operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SliceResult {
    /// Duration of the output segment in seconds.
    pub duration_secs: f64,
    /// Whether lossless copy was used.
    pub lossless: bool,
    /// Output file path (same as ClipSpec.output_path).
    pub output_path: String,
}

impl SliceResult {
    pub fn new(duration_secs: f64, lossless: bool, output_path: String) -> Self {
        SliceResult { duration_secs, lossless, output_path }
    }
}

/// Slice a segment from a source video according to the given spec.
///
/// Phase 3: validates input and returns placeholder result.
/// Full FFmpeg implementation gated behind `ffmpeg` feature.
pub fn slice_segment(spec: &ClipSpec) -> CoreResult<SliceResult> {
    // Validate time range
    if spec.start_secs < 0.0 || spec.end_secs <= spec.start_secs {
        return Err(CoreError::Config(format!(
            "Invalid time range: {} – {}",
            spec.start_secs, spec.end_secs
        )));
    }

    if spec.output_path.is_empty() {
        return Err(CoreError::Config("Output path must not be empty".into()));
    }

    #[cfg(feature = "ffmpeg")]
    {
        // Phase 3 full implementation:
        // 1. Open input via avformat_open_input
        // 2. Find video/audio streams
        // 3. If prefer_lossless && GOP-aligned → bitstream copy via avio
        // 4. Else → decode → optional filter graph → encode → mux
        // For now, return placeholder as it requires system FFmpeg.
    }

    let _ = spec; // silence unused warning without ffmpeg feature
    let duration = spec.end_secs - spec.start_secs;
    Ok(SliceResult::new(duration, false, spec.output_path.clone()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_range() {
        let spec = ClipSpec {
            source_path: "test.mp4".into(),
            start_secs: 0.0,
            end_secs: 10.0,
            output_path: "out.mp4".into(),
            prefer_lossless: false,
            effects_json: None,
        };
        let result = slice_segment(&spec).unwrap();
        assert!((result.duration_secs - 10.0).abs() < 0.01);
        assert_eq!(result.output_path, "out.mp4");
    }

    #[test]
    fn test_invalid_range() {
        let spec = ClipSpec {
            source_path: "test.mp4".into(),
            start_secs: 10.0,
            end_secs: 5.0,
            output_path: "out.mp4".into(),
            prefer_lossless: false,
            effects_json: None,
        };
        assert!(slice_segment(&spec).is_err());
    }

    #[test]
    fn test_negative_start() {
        let spec = ClipSpec {
            source_path: "test.mp4".into(),
            start_secs: -1.0,
            end_secs: 10.0,
            output_path: "out.mp4".into(),
            prefer_lossless: false,
            effects_json: None,
        };
        assert!(slice_segment(&spec).is_err());
    }

    #[test]
    fn test_empty_output_path() {
        let spec = ClipSpec {
            source_path: "test.mp4".into(),
            start_secs: 0.0,
            end_secs: 10.0,
            output_path: "".into(),
            prefer_lossless: false,
            effects_json: None,
        };
        assert!(slice_segment(&spec).is_err());
    }
}
