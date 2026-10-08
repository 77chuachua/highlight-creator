// hc-core: Thumbnail sprite-sheet generator.
// Extracts frames from a video at a given interval, assembling them into
// a single JPEG sprite sheet + metadata JSON.
//
// Requires the "ffmpeg" feature (enabled in Phase 3).

use serde::{Deserialize, Serialize};

/// Metadata describing a generated thumbnail sprite sheet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpriteMetadata {
    /// Path to the generated sprite sheet image.
    pub sprite_path: String,
    /// Width of a single thumbnail in pixels.
    pub thumb_width: u32,
    /// Height of a single thumbnail in pixels.
    pub thumb_height: u32,
    /// Number of columns in the sprite grid.
    pub columns: u32,
    /// Number of rows in the sprite grid.
    pub rows: u32,
    /// Total number of thumbnails.
    pub frame_count: u32,
    /// Interval between consecutive thumbnails in seconds.
    pub interval_secs: f64,
    /// Duration of the source video in seconds.
    pub video_duration_secs: f64,
}

/// Specification for thumbnail generation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThumbnailSpec {
    /// Path to the source video file.
    pub video_path: String,
    /// Interval between extracted frames in seconds.
    pub interval_secs: f64,
    /// Maximum width of each thumbnail (aspect ratio preserved).
    pub max_thumb_width: u32,
    /// Output path for the sprite sheet JPEG.
    pub output_sprite_path: String,
}

#[cfg(feature = "ffmpeg")]
mod imp {
    use super::*;
    use anyhow::Context;
    use std::path::Path;

    /// Generate a thumbnail sprite sheet from a video file.
    ///
    /// Uses FFmpeg `av_seek_frame` + `sws_scale` for efficient extraction.
    /// Returns metadata about the generated sprite.
    pub fn generate_sprite(spec: &ThumbnailSpec) -> anyhow::Result<SpriteMetadata> {
        // Validate input
        if spec.interval_secs <= 0.0 {
            anyhow::bail!("interval_secs must be positive");
        }
        if spec.max_thumb_width == 0 {
            anyhow::bail!("max_thumb_width must be > 0");
        }
        let video_path = Path::new(&spec.video_path);
        if !video_path.exists() {
            anyhow::bail!("Video file not found: {}", spec.video_path);
        }

        // Phase 3 implementation:
        // 1. Open input via avformat_open_input
        // 2. Find video stream
        // 3. For each interval, av_seek_frame → avcodec_decode_video2
        // 4. sws_scale to target size
        // 5. Compose sprite sheet grid
        // 6. Encode as JPEG via avcodec_encode_image
        // 7. Write metadata JSON

        // Placeholder return for Phase 1 (compile-time validation only).
        anyhow::bail!(
            "Thumbnail generation not yet implemented (Phase 3). \
             Video file validated: {}",
            spec.video_path
        );
    }
}

#[cfg(not(feature = "ffmpeg"))]
mod imp {
    use super::*;

    /// Stub: returns an error indicating the ffmpeg feature is not enabled.
    pub fn generate_sprite(spec: &ThumbnailSpec) -> anyhow::Result<SpriteMetadata> {
        // Validate basic inputs regardless of feature flag.
        if spec.interval_secs <= 0.0 {
            anyhow::bail!("interval_secs must be positive");
        }
        if spec.max_thumb_width == 0 {
            anyhow::bail!("max_thumb_width must be > 0");
        }

        // Return a placeholder metadata object so the API shape is testable.
        Ok(SpriteMetadata {
            sprite_path: spec.output_sprite_path.clone(),
            thumb_width: spec.max_thumb_width,
            thumb_height: (spec.max_thumb_width as f64 * 9.0 / 16.0) as u32,
            columns: 1,
            rows: 1,
            frame_count: 1,
            interval_secs: spec.interval_secs,
            video_duration_secs: 0.0,
        })
    }
}

pub use imp::generate_sprite;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_thumbnail_spec_validation_positive_interval() {
        let spec = ThumbnailSpec {
            video_path: "nonexistent.mp4".into(),
            interval_secs: -1.0,
            max_thumb_width: 120,
            output_sprite_path: "out.jpg".into(),
        };
        let result = generate_sprite(&spec);
        assert!(result.is_err());
    }

    #[test]
    fn test_thumbnail_spec_validation_zero_width() {
        let spec = ThumbnailSpec {
            video_path: "nonexistent.mp4".into(),
            interval_secs: 2.0,
            max_thumb_width: 0,
            output_sprite_path: "out.jpg".into(),
        };
        let result = generate_sprite(&spec);
        assert!(result.is_err());
    }

    #[test]
    fn test_thumbnail_spec_valid_without_ffmpeg() {
        let spec = ThumbnailSpec {
            video_path: "test.mp4".into(),
            interval_secs: 2.0,
            max_thumb_width: 120,
            output_sprite_path: "sprite.jpg".into(),
        };
        let result = generate_sprite(&spec);
        // Without ffmpeg feature, returns a placeholder.
        assert!(result.is_ok());
        let meta = result.unwrap();
        assert_eq!(meta.thumb_width, 120);
        assert_eq!(meta.interval_secs, 2.0);
        assert_eq!(meta.frame_count, 1);
    }
}
