import Foundation

/// Configuration options for ``SegmentAudio`` silence detection.
public struct SegmentAudioConfiguration: Codable, Sendable {
    /// Silence threshold in decibels.
    public let silenceThresholdDecibels: Double
    /// Minimum silence duration in seconds.
    public let minimumSilenceDurationSeconds: Double

    /// Creates a segmentation configuration.
    ///
    /// - Parameters:
    ///   - silenceThresholdDecibels: Silence threshold in decibels. Defaults to `-35`.
    ///   - minimumSilenceDurationSeconds: Minimum silence duration in seconds. Defaults to `0.35`.
    public init(
        silenceThresholdDecibels: Double = -35,
        minimumSilenceDurationSeconds: Double = 0.35
    ) {
        self.silenceThresholdDecibels = silenceThresholdDecibels
        self.minimumSilenceDurationSeconds = minimumSilenceDurationSeconds
    }
}
