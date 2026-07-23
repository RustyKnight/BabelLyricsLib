import Foundation

/// Configuration for ``VideoRenderer``.
public struct VideoRendererConfiguration: Codable, Sendable {
    /// Render resolution.
    public let resolution: VideoRendererResolution
    /// Frames per second.
    public let framesPerSecond: Double
    /// Pre-roll padding in seconds before a line becomes active.
    public let preRollPaddingSeconds: Double
    /// Post-roll padding in seconds after a line ends.
    public let postRollPaddingSeconds: Double
    /// Horizontal subtitle padding in pixels.
    public let horizontalPadding: Int
    /// Bottom subtitle padding in pixels.
    public let bottomPadding: Int
    /// Output file extension.
    public let outputFileExtension: String

    /// Creates a render configuration.
    ///
    /// - Parameters:
    ///   - resolution: Render resolution. Defaults to ``VideoRendererResolution/hd1080``.
    ///   - framesPerSecond: Frames per second. Defaults to `25`.
    ///   - preRollPaddingSeconds: Pre-roll padding in seconds. Defaults to `1`.
    ///   - postRollPaddingSeconds: Post-roll padding in seconds. Defaults to `1`.
    ///   - horizontalPadding: Horizontal subtitle padding in pixels. Defaults to `128`.
    ///   - bottomPadding: Bottom subtitle padding in pixels. Defaults to `96`.
    ///   - outputFileExtension: Video file extension. Defaults to `mov`.
    public init(
        resolution: VideoRendererResolution = .hd1080,
        framesPerSecond: Double = 25,
        preRollPaddingSeconds: Double = 1,
        postRollPaddingSeconds: Double = 1,
        horizontalPadding: Int = 128,
        bottomPadding: Int = 96,
        outputFileExtension: String = "mov"
    ) {
        self.resolution = resolution
        self.framesPerSecond = framesPerSecond
        self.preRollPaddingSeconds = preRollPaddingSeconds
        self.postRollPaddingSeconds = postRollPaddingSeconds
        self.horizontalPadding = horizontalPadding
        self.bottomPadding = bottomPadding
        self.outputFileExtension = outputFileExtension
    }

    /// Render size in pixels.
    public var renderSize: (width: Int, height: Int) {
        (resolution.width, resolution.height)
    }
}
