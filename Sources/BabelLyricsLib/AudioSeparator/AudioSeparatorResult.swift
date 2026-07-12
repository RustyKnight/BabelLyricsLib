import Foundation

/// The output of an audio separation operation.
public struct AudioSeparatorResult: Sendable {
    /// The generated vocal-only WAV file URL.
    public let vocalsURL: URL
    /// The generated music-only WAV file URL.
    public let musicURL: URL

    /// Creates a separation result.
    ///
    /// - Parameters:
    ///   - vocalsURL: Location of the generated vocals track.
    ///   - musicURL: Location of the generated music track.
    public init(vocalsURL: URL, musicURL: URL) {
        self.vocalsURL = vocalsURL
        self.musicURL = musicURL
    }
}
