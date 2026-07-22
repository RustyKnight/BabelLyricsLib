//
//  AudioSeparator+DemucsDevice.swift
//  BabelLyricsLib
//
//  Created by Shane Whitehead on 22/7/2026.
//

/// Demucs device options supported by ``AudioSeparator``.
public extension AudioSeparator {
    enum DemucsDevice: String, Codable, Sendable {
        /// Run Demucs on CPU.
        case cpu
        /// Run Demucs on CUDA-capable GPU.
        case cuda
        /// Run Demucs on Apple Metal Performance Shaders.
        case mps

        var demucsName: String {
            switch self {
            case .cpu: "cpu"
            case .cuda: "cuda"
            case .mps: "mps"
            }
        }
    }
}
