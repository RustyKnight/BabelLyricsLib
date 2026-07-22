import Foundation

/// Demucs-specific configuration options used by ``AudioSeparator``.
public extension AudioSeparator {
    struct DemucsConfiguration: Codable, Sendable {
        /// Demucs model to use.
        public let model: AudioSeparator.DemucsModel
        /// Demucs execution device passed to `--device`.
        public let device: AudioSeparator.DemucsDevice
        /// Optional whole-second segment length passed to Demucs `--segment`.
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
        ///   - model: Demucs model to use. Defaults to ``AudioSeparator/DemucsModel/htdemucsFT``.
        ///   - device: Demucs execution device. Defaults to ``AudioSeparator/DemucsDevice/mps``.
        ///   - segment: Whole-second segment length. When `nil`, `--segment` is not passed.
        ///   - overlap: Overlap ratio. Valid range is `0.0...0.99`. When `nil`, `--overlap` is not passed.
        ///   - shifts: Number of random shifts. When `nil`, `--shifts` is not passed.
        ///   - jobs: Number of workers. When `nil`, `--jobs` is not passed.
        public init(
            model: AudioSeparator.DemucsModel = .htdemucsFT,
            device: AudioSeparator.DemucsDevice = .mps,
            shifts: Int? = 10,
            overlap: Double? = 0.5,
            segment: Int? = 7,
            jobs: Int? = nil
        ) {
            self.model = model
            self.device = device
            self.segment = segment
            self.overlap = overlap
            self.shifts = shifts
            self.jobs = jobs
        }
    }
}
