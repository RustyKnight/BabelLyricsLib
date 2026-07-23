import Foundation

public extension AudioSeparator {
    /// Stable output filenames produced by ``AudioSeparator``.
    enum Files: String, CaseIterable, Sendable {
        /// The separated vocal track.
        case vocals = "vocals.wav"
        /// The separated instrumental track.
        case music = "music.wav"
        /// The downmixed mono vocal track.
        case vocalsMono = "vocals-mono.wav"

        /// Resolves this output filename within a destination directory.
        ///
        /// - Parameter directory: Target output directory.
        /// - Returns: Full URL for this output file in `directory`.
        public func url(in directory: URL) -> URL {
            directory.appendingPathComponent(rawValue)
        }
    }
}
