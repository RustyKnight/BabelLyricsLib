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

    @Test("Uses htdemucs by default without extra demucs flags, writes output names, and cleans auto temp directory")
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

        let workflow = AudioSeparator(demucsOverride: { arguments in
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
        })

        let result = try workflow.separateAudio(at: audioURL)

        #expect(capturedArguments.contains("--name"))
        #expect(capturedArguments.contains("htdemucs"))
        #expect(argumentValue("--segment", in: capturedArguments) == nil)
        #expect(argumentValue("--overlap", in: capturedArguments) == nil)
        #expect(argumentValue("--shifts", in: capturedArguments) == nil)
        #expect(argumentValue("--jobs", in: capturedArguments) == nil)
        #expect(result.vocalsURL.lastPathComponent == "vocals.wav")
        #expect(result.musicURL.lastPathComponent == "music.wav")
        #expect(result.vocalsURL.deletingLastPathComponent() == audioDirectory)
        #expect(result.musicURL.deletingLastPathComponent() == audioDirectory)
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))

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

        let workflow = AudioSeparator(demucsOverride: { arguments in
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
        })

        let result = try workflow.separateAudio(
            at: audioURL,
            configuration: .init(model: .mdxExtraQ, segment: 48, overlap: 0.5, shifts: 2, jobs: 4),
            temporaryDirectory: providedTemporaryDirectory
        )

        #expect(capturedArguments.contains("mdx_extra_q"))
        #expect(argumentValue("--segment", in: capturedArguments) == "48")
        #expect(argumentValue("--overlap", in: capturedArguments) == "0.5")
        #expect(argumentValue("--shifts", in: capturedArguments) == "2")
        #expect(argumentValue("--jobs", in: capturedArguments) == "4")
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))
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

        let workflow = AudioSeparator(demucsOverride: { arguments in
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
        })

        let result = try workflow.separateAudio(
            at: audioURL,
            destinationDirectory: destinationDirectory
        )

        #expect(result.vocalsURL == destinationDirectory.appendingPathComponent("vocals.wav"))
        #expect(result.musicURL == destinationDirectory.appendingPathComponent("music.wav"))
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))
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
