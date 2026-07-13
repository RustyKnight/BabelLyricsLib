import Foundation

/// Configuration options for ``AudioTranscriber``.
public struct AudioTranscriberConfiguration: Codable, Sendable {
    /// Whisper model name.
    public let model: String
    /// Whisper language code.
    public let language: String
    /// Whisper temperature.
    public let temperature: Double

    /// Creates a Whisper transcription configuration.
    ///
    /// - Parameters:
    ///   - model: Whisper model name. Defaults to `large`.
    ///   - language: Whisper language code. Defaults to `en`.
    ///   - temperature: Whisper temperature. Defaults to `0.0`.
    public init(
        model: String = "large",
        language: String = "en",
        temperature: Double = 0.0
    ) {
        self.model = model
        self.language = language
        self.temperature = temperature
    }
}
