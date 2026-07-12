import Foundation

/// Common and custom render sizes for ``VideoRenderer``.
public enum VideoRendererResolution: Sendable {
    case hd720
    case hd1080
    case uhd4k
    case custom(width: Int, height: Int)
    case widthRatio(width: Int, aspectRatio: Double)
    case heightRatio(height: Int, aspectRatio: Double)

    /// The render width in pixels.
    public var width: Int {
        switch self {
        case .hd720:
            1280
        case .hd1080:
            1920
        case .uhd4k:
            3840
        case let .custom(width, _):
            width
        case let .widthRatio(width, _):
            width
        case let .heightRatio(height, aspectRatio):
            evenInteger(Double(height) * aspectRatio)
        }
    }

    /// The render height in pixels.
    public var height: Int {
        switch self {
        case .hd720:
            720
        case .hd1080:
            1080
        case .uhd4k:
            2160
        case let .custom(_, height):
            height
        case let .widthRatio(width, aspectRatio):
            evenInteger(Double(width) / aspectRatio)
        case let .heightRatio(height, _):
            height
        }
    }

    /// Render dimensions as a `WxH` string suitable for FFmpeg.
    public var ffmpegSize: String {
        "\(width)x\(height)"
    }

    private func evenInteger(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}
