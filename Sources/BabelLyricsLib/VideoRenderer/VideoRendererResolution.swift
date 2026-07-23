import Foundation

/// Common and custom render sizes for ``VideoRenderer``.
public enum VideoRendererResolution: Codable, Sendable {
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

extension VideoRendererResolution {
    private enum CodingKeys: String, CodingKey {
        case kind
        case width
        case height
        case aspectRatio
    }

    private enum Kind: String, Codable {
        case hd720
        case hd1080
        case uhd4k
        case custom
        case widthRatio
        case heightRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .hd720:
            self = .hd720
        case .hd1080:
            self = .hd1080
        case .uhd4k:
            self = .uhd4k
        case .custom:
            self = .custom(
                width: try container.decode(Int.self, forKey: .width),
                height: try container.decode(Int.self, forKey: .height)
            )
        case .widthRatio:
            self = .widthRatio(
                width: try container.decode(Int.self, forKey: .width),
                aspectRatio: try container.decode(Double.self, forKey: .aspectRatio)
            )
        case .heightRatio:
            self = .heightRatio(
                height: try container.decode(Int.self, forKey: .height),
                aspectRatio: try container.decode(Double.self, forKey: .aspectRatio)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hd720:
            try container.encode(Kind.hd720, forKey: .kind)
        case .hd1080:
            try container.encode(Kind.hd1080, forKey: .kind)
        case .uhd4k:
            try container.encode(Kind.uhd4k, forKey: .kind)
        case let .custom(width, height):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case let .widthRatio(width, aspectRatio):
            try container.encode(Kind.widthRatio, forKey: .kind)
            try container.encode(width, forKey: .width)
            try container.encode(aspectRatio, forKey: .aspectRatio)
        case let .heightRatio(height, aspectRatio):
            try container.encode(Kind.heightRatio, forKey: .kind)
            try container.encode(height, forKey: .height)
            try container.encode(aspectRatio, forKey: .aspectRatio)
        }
    }
}
