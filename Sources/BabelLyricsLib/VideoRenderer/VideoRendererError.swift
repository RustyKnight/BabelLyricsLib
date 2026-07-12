import Foundation

/// Errors thrown by ``VideoRenderer``.
public enum VideoRendererError: Error {
    /// The destination directory could not be created.
    case unableToCreateDestinationDirectory(URL)
    /// The render configuration is invalid.
    case invalidConfiguration(String)
    /// AVFoundation writer setup failed.
    case videoWriterSetupFailed(String)
    /// AVFoundation writer failed while encoding frames.
    case videoWriterFailed(String)
    /// Failed to create a pixel buffer for frame rendering.
    case failedToCreatePixelBuffer
    /// Output video was not generated.
    case missingVideoOutput(URL)
}
