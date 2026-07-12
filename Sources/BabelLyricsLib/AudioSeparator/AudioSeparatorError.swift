import Foundation

/// Errors thrown by ``AudioSeparator``.
public enum AudioSeparatorError: Error {
    /// The input URL is not a file URL.
    case inputMustBeFileURL
    /// The input audio file does not exist.
    case inputFileMissing(URL)
    /// Demucs failed to execute successfully.
    case demucsCommandFailed(String)
    /// Expected Demucs output file is missing.
    case missingDemucsOutput(URL)
    /// Cleanup of an auto-created temporary directory failed.
    case failedToRemoveTemporaryDirectory(URL, String)
}
