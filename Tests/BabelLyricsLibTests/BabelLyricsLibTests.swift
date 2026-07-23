import Testing
@testable import BabelLyricsLib
import Foundation

@Suite("Audio separation workflow")
struct AudioSeparatorTests {
    @Test("Demucs model enum maps to expected demucs names")
    func demucsModelNames() {
        #expect(AudioSeparator.DemucsModel.htdemucs.demucsName == "htdemucs")
        #expect(AudioSeparator.DemucsModel.htdemucsFT.demucsName == "htdemucs_ft")
        #expect(AudioSeparator.DemucsModel.htdemucs6s.demucsName == "htdemucs_6s")
        #expect(AudioSeparator.DemucsModel.mdxExtra.demucsName == "mdx_extra")
        #expect(AudioSeparator.DemucsModel.mdxExtraQ.demucsName == "mdx_extra_q")
    }

    @Test("Demucs device enum maps to expected demucs names")
    func demucsDeviceNames() {
        #expect(AudioSeparator.DemucsDevice.cpu.demucsName == "cpu")
        #expect(AudioSeparator.DemucsDevice.cuda.demucsName == "cuda")
        #expect(AudioSeparator.DemucsDevice.mps.demucsName == "mps")
    }

    @Test("Output file enum maps to expected output filenames")
    func outputFilenames() {
        #expect(AudioSeparator.Files.vocals.rawValue == "vocals.wav")
        #expect(AudioSeparator.Files.music.rawValue == "music.wav")
        #expect(AudioSeparator.Files.vocalsMono.rawValue == "vocals-mono.wav")
    }

    @Test("Uses default demucs flags, writes output names, and cleans auto temp directory")
    func separatesUsingDefaultModel() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: audioDirectory) }

        let audioURL = audioDirectory.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        var capturedArguments: [String] = []
        var capturedOutputDirectory: URL?
        var capturedFFmpegArguments: [String] = []

        let workflow = AudioSeparator(
            demucsOverride: { arguments in
                capturedArguments = arguments

                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]
                capturedOutputDirectory = URL(fileURLWithPath: outPath, isDirectory: true)

                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                capturedFFmpegArguments = arguments
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        let result = try workflow.separateAudio(at: audioURL)

        #expect(capturedArguments.contains("--name"))
        #expect(capturedArguments.contains("htdemucs_ft"))
        #expect(argumentValue("--device", in: capturedArguments) == "mps")
        #expect(argumentValue("--segment", in: capturedArguments) == "7")
        #expect(argumentValue("--overlap", in: capturedArguments) == "0.5")
        #expect(argumentValue("--shifts", in: capturedArguments) == nil)
        #expect(argumentValue("--jobs", in: capturedArguments) == nil)
        #expect(capturedFFmpegArguments.contains("-af"))
        #expect(capturedFFmpegArguments.contains("pan=mono|c0=0.5*c0+0.5*c1"))
        #expect(capturedFFmpegArguments.contains("-ac"))
        #expect(capturedFFmpegArguments.contains("1"))
        #expect(capturedFFmpegArguments.contains("-c:a"))
        #expect(capturedFFmpegArguments.contains("pcm_s16le"))
        #expect(capturedFFmpegArguments.contains(result.vocalsURL.path))
        #expect(capturedFFmpegArguments.last == "\(audioDirectory.path)/vocals-mono.wav")
        #expect(result.vocalsURL.lastPathComponent == "vocals.wav")
        #expect(result.musicURL.lastPathComponent == "music.wav")
        #expect(result.vocalsURL.deletingLastPathComponent() == audioDirectory)
        #expect(result.musicURL.deletingLastPathComponent() == audioDirectory)
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))
        #expect(fileManager.fileExists(atPath: audioDirectory.appendingPathComponent("vocals-mono.wav").path))

        let autoTempDirectoryWasRemoved = capturedOutputDirectory.map { !fileManager.fileExists(atPath: $0.path) } ?? false
        #expect(autoTempDirectoryWasRemoved)
    }

    @Test("Supports mdxExtraQ model and preserves supplied temp directory")
    func supportsMdxExtraQAndProvidedTempDirectory() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        let providedTemporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-Provided-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: providedTemporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: audioDirectory)
            try? fileManager.removeItem(at: providedTemporaryDirectory)
        }

        let audioURL = audioDirectory.appendingPathComponent("track.mp3")
        try Data("demo".utf8).write(to: audioURL)

        var capturedArguments: [String] = []

        let workflow = AudioSeparator(
            demucsOverride: { arguments in
                capturedArguments = arguments

                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]

                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        let result = try workflow.separateAudio(
            at: audioURL,
            configuration: .init(model: .mdxExtraQ, device: .cpu, shifts: 2, overlap: 0.5, segment: 48, jobs: 4),
            temporaryDirectory: providedTemporaryDirectory
        )

        #expect(capturedArguments.contains("mdx_extra_q"))
        #expect(argumentValue("--device", in: capturedArguments) == "cpu")
        #expect(argumentValue("--segment", in: capturedArguments) == "48")
        #expect(argumentValue("--overlap", in: capturedArguments) == "0.5")
        #expect(argumentValue("--shifts", in: capturedArguments) == "2")
        #expect(argumentValue("--jobs", in: capturedArguments) == "4")
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))
        #expect(fileManager.fileExists(atPath: audioDirectory.appendingPathComponent("vocals-mono.wav").path))
        #expect(fileManager.fileExists(atPath: providedTemporaryDirectory.path))
    }

    @Test("Writes separated tracks to the provided destination directory")
    func writesSeparatedTracksToProvidedDestinationDirectory() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-Destination-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: audioDirectory)
            try? fileManager.removeItem(at: destinationDirectory)
        }

        let audioURL = audioDirectory.appendingPathComponent("track.mp3")
        try Data("demo".utf8).write(to: audioURL)

        let workflow = AudioSeparator(
            demucsOverride: { arguments in
                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]
                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                #expect(arguments.contains("-af"))
                #expect(arguments.contains("pan=mono|c0=0.5*c0+0.5*c1"))
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        let result = try workflow.separateAudio(
            at: audioURL,
            destinationDirectory: destinationDirectory
        )

        #expect(result.vocalsURL == destinationDirectory.appendingPathComponent("vocals.wav"))
        #expect(result.musicURL == destinationDirectory.appendingPathComponent("music.wav"))
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))
        #expect(fileManager.fileExists(atPath: destinationDirectory.appendingPathComponent("vocals-mono.wav").path))
    }

    @Test("Rejects overlap outside 0.0 to 0.99")
    func rejectsInvalidDemucsOverlap() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: audioDirectory) }

        let audioURL = audioDirectory.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        let workflow = AudioSeparator(demucsOverride: { _ in
            Issue.record("Demucs should not execute when configuration is invalid")
        })

        do {
            _ = try workflow.separateAudio(
                at: audioURL,
                configuration: .init(overlap: 1.0)
            )
            Issue.record("Expected invalidDemucsConfiguration error")
        } catch let error as AudioSeparatorError {
            switch error {
            case .invalidDemucsConfiguration:
                break
            default:
                Issue.record("Expected invalidDemucsConfiguration but got \(error)")
            }
        } catch {
            Issue.record("Expected AudioSeparatorError but got \(error)")
        }
    }

    @Test("Rejects jobs less than or equal to zero")
    func rejectsInvalidDemucsJobs() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: audioDirectory) }

        let audioURL = audioDirectory.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        let workflow = AudioSeparator(demucsOverride: { _ in
            Issue.record("Demucs should not execute when configuration is invalid")
        })

        do {
            _ = try workflow.separateAudio(
                at: audioURL,
                configuration: .init(jobs: 0)
            )
            Issue.record("Expected invalidDemucsConfiguration error")
        } catch let error as AudioSeparatorError {
            switch error {
            case .invalidDemucsConfiguration:
                break
            default:
                Issue.record("Expected invalidDemucsConfiguration but got \(error)")
            }
        } catch {
            Issue.record("Expected AudioSeparatorError but got \(error)")
        }
    }

    @Test("Rejects segment values less than or equal to zero")
    func rejectsInvalidDemucsSegment() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: audioDirectory) }

        let audioURL = audioDirectory.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        let workflow = AudioSeparator(demucsOverride: { _ in
            Issue.record("Demucs should not execute when configuration is invalid")
        })

        do {
            _ = try workflow.separateAudio(
                at: audioURL,
                configuration: .init(segment: 0)
            )
            Issue.record("Expected invalidDemucsConfiguration error")
        } catch let error as AudioSeparatorError {
            switch error {
            case .invalidDemucsConfiguration:
                break
            default:
                Issue.record("Expected invalidDemucsConfiguration but got \(error)")
            }
        } catch {
            Issue.record("Expected AudioSeparatorError but got \(error)")
        }
    }

    @Test("Rejects non-file URLs")
    func rejectsNonFileURL() throws {
        let workflow = AudioSeparator(demucsOverride: { _ in })
        do {
            _ = try workflow.separateAudio(at: URL(string: "https://example.com/audio.mp3")!)
            Issue.record("Expected inputMustBeFileURL error")
        } catch let error as AudioSeparatorError {
            switch error {
            case .inputMustBeFileURL:
                break
            default:
                Issue.record("Expected inputMustBeFileURL but got \(error)")
            }
        } catch {
            Issue.record("Expected AudioSeparatorError but got \(error)")
        }
    }

    @Test("Rejects non-file destination directory URLs")
    func rejectsNonFileDestinationDirectoryURL() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: audioDirectory) }

        let audioURL = audioDirectory.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        let workflow = AudioSeparator(demucsOverride: { _ in
            Issue.record("Demucs should not execute when destination directory is invalid")
        })

        do {
            _ = try workflow.separateAudio(
                at: audioURL,
                destinationDirectory: URL(string: "https://example.com/output")!
            )
            Issue.record("Expected destinationDirectoryMustBeFileURL error")
        } catch let error as AudioSeparatorError {
            switch error {
            case .destinationDirectoryMustBeFileURL:
                break
            default:
                Issue.record("Expected destinationDirectoryMustBeFileURL but got \(error)")
            }
        } catch {
            Issue.record("Expected AudioSeparatorError but got \(error)")
        }
    }

    @Test("Emits lifecycle logs when using provided temporary directory")
    func emitsLifecycleLogsForProvidedTemporaryDirectory() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        let providedTemporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-Provided-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: providedTemporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: audioDirectory)
            try? fileManager.removeItem(at: providedTemporaryDirectory)
        }

        let audioURL = audioDirectory.appendingPathComponent("track.wav")
        try Data("demo".utf8).write(to: audioURL)

        let delegate = AudioSeparatorCapturingLogDelegate()

        let separator = AudioSeparator(
            demucsOverride: { arguments in
                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]
                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                #expect(arguments.contains("-af"))
                #expect(arguments.contains("pan=mono|c0=0.5*c0+0.5*c1"))
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            },
            logger: delegate
        )

        _ = try separator.separateAudio(
            at: audioURL,
            temporaryDirectory: providedTemporaryDirectory
        )

        let loggedMessages = delegate.messages.map(\.message)
        #expect(loggedMessages.contains("Make use of provided temporary directory"))
        #expect(loggedMessages.contains("Start separating audio"))
        #expect(loggedMessages.contains("Execute override Demucs"))
        #expect(loggedMessages.contains(where: { $0.hasPrefix("Completed separating audio in ") }))
    }

    @Test("Emits cleanup logs when using transient temporary directory")
    func emitsCleanupLogsForTransientTemporaryDirectory() throws {
        let fileManager = FileManager.default
        let audioDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: audioDirectory) }

        let audioURL = audioDirectory.appendingPathComponent("track.wav")
        try Data("demo".utf8).write(to: audioURL)

        let delegate = AudioSeparatorCapturingLogDelegate()

        let separator = AudioSeparator(
            demucsOverride: { arguments in
                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]
                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                #expect(arguments.contains("-af"))
                #expect(arguments.contains("pan=mono|c0=0.5*c0+0.5*c1"))
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            },
            logger: delegate
        )

        _ = try separator.separateAudio(at: audioURL)

        let loggedMessages = delegate.messages.map(\.message)
        #expect(loggedMessages.contains("Use system temporary, transient directory"))
        #expect(loggedMessages.contains("Clean up transient temporary directory"))
    }

    @Test("Logs validation error for non-file URL")
    func logsValidationErrorForNonFileURL() throws {
        let delegate = AudioSeparatorCapturingLogDelegate()
        let separator = AudioSeparator(demucsOverride: { _ in }, logger: delegate)

        do {
            _ = try separator.separateAudio(at: URL(string: "https://example.com/audio.mp3")!)
            Issue.record("Expected inputMustBeFileURL error")
        } catch {
            // Intentionally ignored; assertion is about emitted logs.
        }

        #expect(delegate.messages.last?.level.description == "error")
        #expect(delegate.messages.last?.message == "Audio source must be a file")
    }

    @Test("Emits closure progress updates for separation")
    func emitsClosureProgressUpdates() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        let progressStore = ThreadSafeProgressStore()
        let separator = AudioSeparator(
            demucsOverride: { arguments in
                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]
                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        _ = try separator.separateAudio(at: audioURL) { progress in
            progressStore.append(progress)
        }
        let progressUpdates = progressStore.snapshot()

        #expect(progressUpdates.count >= 2)
        #expect(progressUpdates.first?.fractionCompleted == 0)
        #expect(progressUpdates.last?.fractionCompleted == 1)
        #expect(progressUpdates.last?.totalPasses == 1)
    }

    @Test("Emits async progress stream events")
    func emitsAsyncProgressStreamEvents() async throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLibTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("input.wav")
        try Data("demo".utf8).write(to: audioURL)

        let separator = AudioSeparator(
            demucsOverride: { arguments in
                let outIndex = arguments.firstIndex(of: "--out")!
                let outPath = arguments[outIndex + 1]
                let nameIndex = arguments.firstIndex(of: "--name")!
                let modelName = arguments[nameIndex + 1]

                let stemDirectory = URL(fileURLWithPath: outPath, isDirectory: true)
                    .appendingPathComponent(modelName, isDirectory: true)
                    .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
                try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
                try Data("music".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
            },
            ffmpegOverride: { arguments in
                try Data("mono".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        let stream = separator.separateAudioProgressStream(at: audioURL)
        var progressFractions: [Double] = []
        var completedResult: AudioSeparatorModel?
        for try await event in stream {
            switch event {
            case let .progress(progress):
                progressFractions.append(progress.fractionCompleted)
            case let .completed(result):
                completedResult = result
            }
        }

        #expect(progressFractions.contains(0))
        #expect(progressFractions.contains(1))
        #expect(completedResult?.vocalsURL.lastPathComponent == "vocals.wav")
        #expect(completedResult?.musicURL.lastPathComponent == "music.wav")
    }
}

private func argumentValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

private final class AudioSeparatorCapturingLogDelegate: LogDelegate {
    var messages: [LogMessage] = []

    func log(_ message: LogMessage) {
        messages.append(message)
    }
}

private final class ThreadSafeProgressStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AudioSeparator.Progress] = []

    func append(_ value: AudioSeparator.Progress) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    func snapshot() -> [AudioSeparator.Progress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
