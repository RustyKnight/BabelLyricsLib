import Foundation

public extension AudioTranscriber {
    typealias ProgressHandler = @Sendable (Progress) -> Void

    struct Progress: Sendable {
        public let fractionCompleted: Double
        public let completedSegments: Int
        public let totalSegments: Int
        public let currentSegmentIndex: Int
        public let currentSegmentFraction: Double
        public let estimatedTimeRemaining: Duration?
        public let message: String?

        public init(
            fractionCompleted: Double,
            completedSegments: Int,
            totalSegments: Int,
            currentSegmentIndex: Int,
            currentSegmentFraction: Double,
            estimatedTimeRemaining: Duration?,
            message: String?
        ) {
            self.fractionCompleted = fractionCompleted
            self.completedSegments = completedSegments
            self.totalSegments = totalSegments
            self.currentSegmentIndex = currentSegmentIndex
            self.currentSegmentFraction = currentSegmentFraction
            self.estimatedTimeRemaining = estimatedTimeRemaining
            self.message = message
        }
    }

    enum ProgressEvent: Sendable {
        case progress(Progress)
        case completed(AudioTranscriberModel)
    }

    func transcribeAudioProgressStream(
        from segmentAudioResult: AudioSegmenterModel,
        audioSegmentSourceURL: URL,
        temporaryDirectory: URL? = nil,
        configuration: AudioTranscriberConfiguration = .init()
    ) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let result = try self.transcribeAudio(
                        from: segmentAudioResult,
                        audioSegmentSourceURL: audioSegmentSourceURL,
                        temporaryDirectory: temporaryDirectory,
                        configuration: configuration,
                        onProgress: { continuation.yield(.progress($0)) }
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
