import Foundation

/// Configuration options for ``AudioTranscriber``.
public struct AudioTranscriberConfiguration: Codable, Sendable {
    /// Whisper model name.
    public let model: String
    /// Whisper language code.
    public let language: String
    /// Whisper temperature.
    public let temperature: Double
    /// Whisper beam size, used only when temperature is `0`.
    public let beamSize: Int?
    /// Whisper thread count.
    public let threads: Int?

    /// Creates a Whisper transcription configuration for temperature-based decoding.
    ///
    /// - Parameters:
    ///   - model: Whisper model name. Defaults to `large`.
    ///   - language: Whisper language code. Defaults to `en`.
    ///   - temperature: Whisper temperature. Defaults to `0.0`.
    ///   - threads: Whisper thread count. When `nil`, `--threads` is not passed.
    public init(
        model: String = "large",
        language: String = "en",
        temperature: Double = 0.0,
        threads: Int? = nil
    ) {
        self.model = model
        self.language = language
        self.temperature = temperature
        self.beamSize = nil
        self.threads = threads
    }

    /// Creates a Whisper transcription configuration for beam-size decoding.
    ///
    /// - Parameters:
    ///   - model: Whisper model name. Defaults to `large`.
    ///   - language: Whisper language code. Defaults to `en`.
    ///   - beamSize: Whisper beam size. Passed together with `--temperature 0`.
    ///   - threads: Whisper thread count. When `nil`, `--threads` is not passed.
    public init(
        model: String = "large",
        language: String = "en",
        beamSize: Int,
        threads: Int? = nil
    ) {
        self.model = model
        self.language = language
        self.temperature = 0
        self.beamSize = beamSize
        self.threads = threads
    }
}
