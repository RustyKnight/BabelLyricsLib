import Foundation

/// Configuration options for ``AudioSegmenter`` silence detection.
public struct AudioSegmenterConfiguration: Codable, Sendable {
    /// Silence threshold in decibels.
    public let silenceThresholdDecibels: Double
    /// Minimum silence duration in seconds.
    public let minimumSilenceDurationSeconds: Double
    /// Minimum generated segment duration in seconds.
    public let minimumSegmentDurationSeconds: Double

    /// Creates a segmentation configuration.
    ///
    /// - Parameters:
    ///   - silenceThresholdDecibels: Silence threshold in decibels. Defaults to `-35`.
    ///   - minimumSilenceDurationSeconds: Minimum silence duration in seconds. Defaults to `0.35`.
    ///   - minimumSegmentDurationSeconds: Minimum generated segment duration in seconds. Defaults to `0.026`.
    public init(
        silenceThresholdDecibels: Double = -35,
        minimumSilenceDurationSeconds: Double = 0.35,
        minimumSegmentDurationSeconds: Double = 0.026
    ) {
        self.silenceThresholdDecibels = silenceThresholdDecibels
        self.minimumSilenceDurationSeconds = minimumSilenceDurationSeconds
        self.minimumSegmentDurationSeconds = minimumSegmentDurationSeconds
    }
}
