import Foundation

/// Output of a lyrics video render.
public struct VideoRendererResult: Sendable {
    /// Final video file URL.
    public let videoURL: URL

    /// Creates a render result.
    public init(videoURL: URL) {
        self.videoURL = videoURL
    }
}
