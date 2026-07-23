import Foundation

public extension AudioSeparator {
    typealias ProgressHandler = @Sendable (Progress) -> Void

    /// Progress details emitted while Demucs is running.
    struct Progress: Sendable {
        /// Normalized progress from `0.0` to `1.0` across all passes.
        public let fractionCompleted: Double
        /// Completed pass count.
        public let completedPasses: Int
        /// Total pass count (model count × shifts).
        public let totalPasses: Int
        /// Current pass progress from `0.0` to `1.0`.
        public let currentPassFraction: Double
        /// Estimated remaining time for all passes.
        public let estimatedTimeRemaining: Duration?
        /// Raw progress line emitted by Demucs.
        public let message: String?

        public init(
            fractionCompleted: Double,
            completedPasses: Int,
            totalPasses: Int,
            currentPassFraction: Double,
            estimatedTimeRemaining: Duration?,
            message: String?
        ) {
            self.fractionCompleted = fractionCompleted
            self.completedPasses = completedPasses
            self.totalPasses = totalPasses
            self.currentPassFraction = currentPassFraction
            self.estimatedTimeRemaining = estimatedTimeRemaining
            self.message = message
        }
    }

    /// Async progress event stream for audio separation.
    enum ProgressEvent: Sendable {
        case progress(Progress)
        case completed(AudioSeparatorModel)
    }

    /// Separates audio while emitting progress updates as an async stream.
    ///
    /// Progress and completion are emitted as ``AudioSeparator/ProgressEvent`` values.
    func separateAudioProgressStream(
        at audioURL: URL,
        configuration: AudioSeparator.DemucsConfiguration = .init(),
        destinationDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.separateAudio(
                        at: audioURL,
                        configuration: configuration,
                        destinationDirectory: destinationDirectory,
                        temporaryDirectory: temporaryDirectory
                    ) { progress in
                        continuation.yield(.progress(progress))
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
