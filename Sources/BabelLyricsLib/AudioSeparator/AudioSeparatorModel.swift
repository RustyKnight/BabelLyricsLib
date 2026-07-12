/// Demucs model options supported by ``AudioSeparator``.
public enum AudioSeparatorModel: Sendable {
    /// The default Demucs model.
    case htdemucs
    /// The MDX extra quality model.
    case mdxExtraQ

    var demucsName: String {
        switch self {
        case .htdemucs:
            "htdemucs"
        case .mdxExtraQ:
            "mdx_extra_q"
        }
    }
}
