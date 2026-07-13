import Foundation

/// Errors thrown by ``AudioTranscriber``.
public enum AudioTranscriberError: Error {
    /// A segment URL was missing or invalid.
    case segmentFileMissing(URL)
    /// The caller-provided temporary directory does not exist.
    case providedTemporaryDirectoryMissing(URL)
    /// Whisper failed to execute successfully.
    case whisperCommandFailed(String)
    /// Whisper transcript output file was not created.
    case missingTranscriptOutput(URL)
    /// Could not parse a segment offset from ``AudioSegmenterModel``.
    case invalidSegmentOffset(String)
    /// Cleanup of an auto-created temporary directory failed.
    case failedToRemoveTemporaryDirectory(URL, String)
}
