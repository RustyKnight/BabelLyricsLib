import Foundation

/// Demucs-specific configuration options used by ``AudioSeparator``.
public extension AudioSeparator {
    struct DemucsConfiguration: Codable, Sendable {
        /// Demucs model to use.
        public let model: AudioSeparator.DemucsModel
        /// Optional segment length in seconds passed to Demucs `--segment`.
        public let segment: Int?
        /// Optional overlap ratio passed to Demucs `--overlap`.
        public let overlap: Double?
        /// Optional number of random shifts passed to Demucs `--shifts`.
        public let shifts: Int?
        /// Optional number of workers passed to Demucs `--jobs`.
        public let jobs: Int?

        /// Creates a Demucs configuration.
        ///
        /// - Parameters:
        ///   - model: Demucs model to use. Defaults to ``AudioSeparator/DemucsModel/htdemucs``.
        ///   - segment: Segment length in seconds. When `nil`, `--segment` is not passed.
        ///   - overlap: Overlap ratio. Valid range is `0.0...0.99`. When `nil`, `--overlap` is not passed.
        ///   - shifts: Number of random shifts. When `nil`, `--shifts` is not passed.
        ///   - jobs: Number of workers. When `nil`, `--jobs` is not passed.
        public init(
            model: AudioSeparator.DemucsModel = .htdemucs,
            segment: Int? = nil,
            overlap: Double? = nil,
            shifts: Int? = nil,
            jobs: Int? = nil
        ) {
            self.model = model
            self.segment = segment
            self.overlap = overlap
            self.shifts = shifts
            self.jobs = jobs
        }
    }
}
