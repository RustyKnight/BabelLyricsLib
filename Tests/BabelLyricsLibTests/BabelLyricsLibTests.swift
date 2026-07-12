import Testing
@testable import BabelLyricsLib
import Foundation

@Suite("Audio separation workflow")
struct AudioSeparatorTests {
    @Test("Uses htdemucs by default, writes output names, and cleans auto temp directory")
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
        #expect(result.vocalsURL.lastPathComponent == "vocals.wav")
        #expect(result.musicURL.lastPathComponent == "music.wav")
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
            model: .mdxExtraQ,
            temporaryDirectory: providedTemporaryDirectory
        )

        #expect(capturedArguments.contains("mdx_extra_q"))
        #expect(fileManager.fileExists(atPath: result.vocalsURL.path))
        #expect(fileManager.fileExists(atPath: result.musicURL.path))
        #expect(fileManager.fileExists(atPath: providedTemporaryDirectory.path))
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

private final class AudioSeparatorCapturingLogDelegate: LogDelegate {
    var messages: [LogMessage] = []

    func log(_ message: LogMessage) {
        messages.append(message)
    }
}
