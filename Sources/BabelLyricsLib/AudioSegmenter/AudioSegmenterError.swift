import Foundation

/// Errors thrown by ``AudioSegmenter``.
public enum AudioSegmenterError: Error {
    /// The input URL is not a file URL.
    case inputMustBeFileURL
    /// The input audio file does not exist.
    case inputFileMissing(URL)
    /// FFmpeg command execution failed.
    case ffmpegCommandFailed(String)
    /// Could not parse source duration from FFmpeg output.
    case sourceDurationMissing
}
