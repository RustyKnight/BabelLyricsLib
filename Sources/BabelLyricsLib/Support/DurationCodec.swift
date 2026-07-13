import Foundation

enum DurationCodec {
    static func encode(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    static func decode(_ seconds: Double) -> Duration {
        return .seconds((seconds * 1000).rounded() / 1000)
    }
}
