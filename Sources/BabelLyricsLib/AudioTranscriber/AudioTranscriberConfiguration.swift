import Foundation

/// Configuration options for ``AudioTranscriber``.
public struct AudioTranscriberConfiguration: Codable, Sendable {
    /// Whisper model name.
    public let model: AudioTranscriberConfiguration.Model
    /// Whisper language selector.
    public let language: AudioTranscriberConfiguration.Language
    /// Whisper task mode.
    public let task: AudioTranscriberConfiguration.Task
    /// Whisper beam size.
    public let beamSize: Int
    /// Whisper temperature.
    public let temperature: Double
    /// Whisper `best_of` candidate count. Used for sampling decode.
    public let bestOf: Int?
    /// Whisper context carry-over between segments.
    public let conditionOnPreviousText: Bool
    /// Whisper initial prompt text.
    public let initialPrompt: String?
    /// Whisper thread count.
    public let threads: Int?

    /// Creates a Whisper transcription configuration.
    ///
    /// - Parameters:
    ///   - model: Whisper model name. Defaults to `largeV3`.
    ///   - language: Whisper language selector. Defaults to `en`.
    ///   - task: Whisper task mode. Defaults to `transcribe`.
    ///   - beamSize: Whisper beam size. Defaults to `5`.
    ///   - temperature: Whisper temperature. Defaults to `0.0`.
    ///   - bestOf: Optional Whisper `best_of` candidate count. Defaults to `nil`.
    ///   - conditionOnPreviousText: Whisper context carry-over behavior. Defaults to `true`.
    ///   - initialPrompt: Optional initial prompt for domain-specific vocabulary. Defaults to `nil`.
    ///   - threads: Whisper thread count. When `nil`, `--threads` is not passed.
    public init(
        model: AudioTranscriberConfiguration.Model = .largeV3,
        language: AudioTranscriberConfiguration.Language = .en,
        task: AudioTranscriberConfiguration.Task = .transcribe,
        beamSize: Int = 5,
        temperature: Double = 0.0,
        bestOf: Int? = nil,
        conditionOnPreviousText: Bool = true,
        initialPrompt: String? = nil,
        threads: Int? = nil
    ) {
        self.model = model
        self.language = language
        self.task = task
        self.beamSize = beamSize
        self.temperature = temperature
        self.bestOf = bestOf
        self.conditionOnPreviousText = conditionOnPreviousText
        self.initialPrompt = initialPrompt
        self.threads = threads
    }
}

public extension AudioTranscriberConfiguration {
    /// Whisper task mode.
    enum Task: String, Codable, Sendable {
        /// Transcribe in the source language.
        case transcribe
        /// Translate speech output to English.
        case translate
    }
}

public extension AudioTranscriberConfiguration {
    /// Supported Whisper model names.
    enum Model: Codable, Sendable, Equatable {
        case tiny
        case base
        case small
        case medium
        case large
        case largeV2
        case largeV3
        case largeV3Turbo
        case turbo

        /// Whisper CLI model argument value.
        var name: String {
            switch self {
            case .tiny: return "tiny"
            case .base: return "base"
            case .small: return "small"
            case .medium: return "medium"
            case .large: return "large"
            case .largeV2: return "large-v2"
            case .largeV3: return "large-v3"
            case .largeV3Turbo: return "large-v3-turbo"
            case .turbo: return "turbo"
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self).lowercased()
            switch value {
            case "tiny": self = .tiny
            case "base": self = .base
            case "small": self = .small
            case "medium": self = .medium
            case "large": self = .large
            case "large-v2": self = .largeV2
            case "large-v3": self = .largeV3
            case "large-v3-turbo": self = .largeV3Turbo
            case "turbo": self = .turbo
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported Whisper model: \(value)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(name)
        }
    }
}

public extension AudioTranscriberConfiguration {
    /// Whisper language selector.
    enum Language: Codable, Sendable, Equatable {
        case af, am, ar, `as`, az, ba, be, bg, bn, bo, br, bs, ca, cs, cy, da, de, el, en, es, et, eu
        case fa, fi, fo, fr, gl, gu, ha, haw, he, hi, hr, ht, hu, hy, id, `is`, it, ja, jw, ka, kk
        case km, kn, ko, la, lb, ln, lo, lt, lv, mg, mi, mk, ml, mn, mr, ms, mt, my, ne, nl, nn, no
        case oc, pa, pl, ps, pt, ro, ru, sa, sd, si, sk, sl, sn, so, sq, sr, su, sv, sw, ta, te, tg
        case th, tk, tl, tr, tt, uk, ur, uz, vi, yi, yo, yue, zh
        case custom(String)

        /// Whisper CLI language argument value.
        var code: String {
            switch self {
            case .af: return "af"
            case .am: return "am"
            case .ar: return "ar"
            case .`as`: return "as"
            case .az: return "az"
            case .ba: return "ba"
            case .be: return "be"
            case .bg: return "bg"
            case .bn: return "bn"
            case .bo: return "bo"
            case .br: return "br"
            case .bs: return "bs"
            case .ca: return "ca"
            case .cs: return "cs"
            case .cy: return "cy"
            case .da: return "da"
            case .de: return "de"
            case .el: return "el"
            case .en: return "en"
            case .es: return "es"
            case .et: return "et"
            case .eu: return "eu"
            case .fa: return "fa"
            case .fi: return "fi"
            case .fo: return "fo"
            case .fr: return "fr"
            case .gl: return "gl"
            case .gu: return "gu"
            case .ha: return "ha"
            case .haw: return "haw"
            case .he: return "he"
            case .hi: return "hi"
            case .hr: return "hr"
            case .ht: return "ht"
            case .hu: return "hu"
            case .hy: return "hy"
            case .id: return "id"
            case .`is`: return "is"
            case .it: return "it"
            case .ja: return "ja"
            case .jw: return "jw"
            case .ka: return "ka"
            case .kk: return "kk"
            case .km: return "km"
            case .kn: return "kn"
            case .ko: return "ko"
            case .la: return "la"
            case .lb: return "lb"
            case .ln: return "ln"
            case .lo: return "lo"
            case .lt: return "lt"
            case .lv: return "lv"
            case .mg: return "mg"
            case .mi: return "mi"
            case .mk: return "mk"
            case .ml: return "ml"
            case .mn: return "mn"
            case .mr: return "mr"
            case .ms: return "ms"
            case .mt: return "mt"
            case .my: return "my"
            case .ne: return "ne"
            case .nl: return "nl"
            case .nn: return "nn"
            case .no: return "no"
            case .oc: return "oc"
            case .pa: return "pa"
            case .pl: return "pl"
            case .ps: return "ps"
            case .pt: return "pt"
            case .ro: return "ro"
            case .ru: return "ru"
            case .sa: return "sa"
            case .sd: return "sd"
            case .si: return "si"
            case .sk: return "sk"
            case .sl: return "sl"
            case .sn: return "sn"
            case .so: return "so"
            case .sq: return "sq"
            case .sr: return "sr"
            case .su: return "su"
            case .sv: return "sv"
            case .sw: return "sw"
            case .ta: return "ta"
            case .te: return "te"
            case .tg: return "tg"
            case .th: return "th"
            case .tk: return "tk"
            case .tl: return "tl"
            case .tr: return "tr"
            case .tt: return "tt"
            case .uk: return "uk"
            case .ur: return "ur"
            case .uz: return "uz"
            case .vi: return "vi"
            case .yi: return "yi"
            case .yo: return "yo"
            case .yue: return "yue"
            case .zh: return "zh"
            case let .custom(value): return value
            }
        }

        init(code: String) {
            switch code.lowercased() {
            case "af": self = .af
            case "am": self = .am
            case "ar": self = .ar
            case "as": self = .`as`
            case "az": self = .az
            case "ba": self = .ba
            case "be": self = .be
            case "bg": self = .bg
            case "bn": self = .bn
            case "bo": self = .bo
            case "br": self = .br
            case "bs": self = .bs
            case "ca": self = .ca
            case "cs": self = .cs
            case "cy": self = .cy
            case "da": self = .da
            case "de": self = .de
            case "el": self = .el
            case "en": self = .en
            case "es": self = .es
            case "et": self = .et
            case "eu": self = .eu
            case "fa": self = .fa
            case "fi": self = .fi
            case "fo": self = .fo
            case "fr": self = .fr
            case "gl": self = .gl
            case "gu": self = .gu
            case "ha": self = .ha
            case "haw": self = .haw
            case "he": self = .he
            case "hi": self = .hi
            case "hr": self = .hr
            case "ht": self = .ht
            case "hu": self = .hu
            case "hy": self = .hy
            case "id": self = .id
            case "is": self = .`is`
            case "it": self = .it
            case "ja": self = .ja
            case "jw": self = .jw
            case "ka": self = .ka
            case "kk": self = .kk
            case "km": self = .km
            case "kn": self = .kn
            case "ko": self = .ko
            case "la": self = .la
            case "lb": self = .lb
            case "ln": self = .ln
            case "lo": self = .lo
            case "lt": self = .lt
            case "lv": self = .lv
            case "mg": self = .mg
            case "mi": self = .mi
            case "mk": self = .mk
            case "ml": self = .ml
            case "mn": self = .mn
            case "mr": self = .mr
            case "ms": self = .ms
            case "mt": self = .mt
            case "my": self = .my
            case "ne": self = .ne
            case "nl": self = .nl
            case "nn": self = .nn
            case "no": self = .no
            case "oc": self = .oc
            case "pa": self = .pa
            case "pl": self = .pl
            case "ps": self = .ps
            case "pt": self = .pt
            case "ro": self = .ro
            case "ru": self = .ru
            case "sa": self = .sa
            case "sd": self = .sd
            case "si": self = .si
            case "sk": self = .sk
            case "sl": self = .sl
            case "sn": self = .sn
            case "so": self = .so
            case "sq": self = .sq
            case "sr": self = .sr
            case "su": self = .su
            case "sv": self = .sv
            case "sw": self = .sw
            case "ta": self = .ta
            case "te": self = .te
            case "tg": self = .tg
            case "th": self = .th
            case "tk": self = .tk
            case "tl": self = .tl
            case "tr": self = .tr
            case "tt": self = .tt
            case "uk": self = .uk
            case "ur": self = .ur
            case "uz": self = .uz
            case "vi": self = .vi
            case "yi": self = .yi
            case "yo": self = .yo
            case "yue": self = .yue
            case "zh": self = .zh
            default: self = .custom(code)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = .init(code: try container.decode(String.self))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(code)
        }
    }
}
