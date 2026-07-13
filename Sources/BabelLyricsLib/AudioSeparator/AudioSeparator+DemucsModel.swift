/// Demucs model options supported by ``AudioSeparator``.
public extension AudioSeparator {
    enum DemucsModel: String, Codable, Sendable {
        /// The default Demucs model.
        case htdemucs
        /// Fine-tuned variant of the default Demucs model.
        case htdemucsFT
        /// Six-stem variant of the default Demucs model.
        case htdemucs6s
        /// The MDX extra model.
        case mdxExtra
        /// The MDX extra quality model.
        case mdxExtraQ

        var demucsName: String {
            switch self {
            case .htdemucs:
                "htdemucs"
            case .htdemucsFT:
                "htdemucs_ft"
            case .htdemucs6s:
                "htdemucs_6s"
            case .mdxExtra:
                "mdx_extra"
            case .mdxExtraQ:
                "mdx_extra_q"
            }
        }
    }
}
