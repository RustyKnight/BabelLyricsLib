import Foundation

/// Separates an input audio file into vocals and music tracks using Demucs.
public struct AudioSeparator {
    private let fileManager: FileManager
    private let demucsOverride: (([String]) throws -> Void)?
    
    private let logger: LogService?

    /// Creates an audio separator.
    ///
    /// - Parameters:
    ///   - fileManager: File manager used for filesystem operations.
    ///   - demucsOverride: Optional command override for Demucs execution. If omitted, uses `python3 -m demucs.separate`.
    ///   - logger: Optional log delegate that receives lifecycle, command, and error messages.
    public init(
        fileManager: FileManager = .default,
        demucsOverride: (([String]) throws -> Void)? = nil,
        logger: (any LogDelegate)? = nil
    ) {
        self.fileManager = fileManager
        self.demucsOverride = demucsOverride
        if let logger {
            self.logger = .init(delegate: logger)
        } else {
            self.logger = nil
        }
    }

    /// Splits an audio file into vocal-only and music-only MP3 tracks.
    ///
    /// Output files are written alongside the input file as `<name>-vocals.mp3` and `<name>-music.mp3`.
    ///
    /// - Parameters:
    ///   - audioURL: Local URL to the input audio file.
    ///   - model: Demucs model to use. Defaults to ``AudioSeparatorModel/htdemucs``.
    ///   - temporaryDirectory: Optional output working directory for Demucs intermediate output.
    ///     When omitted, a temporary directory is created and removed after processing.
    ///
    /// When a logger delegate is supplied at initialization, this method emits debug, info, and
    /// error messages describing validation, command execution, and cleanup steps.
    ///
    /// - Returns: The URLs of the generated vocals and music files.
    /// - Throws: ``AudioSeparatorError`` or filesystem/process errors.
    public func separateAudio(
        at audioURL: URL,
        model: AudioSeparatorModel = .htdemucs,
        temporaryDirectory: URL? = nil
    ) throws -> AudioSeparatorResult {
        guard audioURL.isFileURL else {
            logger?.error("Audio source must be a file")
            throw AudioSeparatorError.inputMustBeFileURL
        }
        guard fileManager.fileExists(atPath: audioURL.path) else {
            logger?.error("Audio source is missing")
            throw AudioSeparatorError.inputFileMissing(audioURL)
        }

        let shouldCleanupTemporaryDirectory = temporaryDirectory == nil
        let workingTemporaryDirectory: URL
        if let temporaryDirectory {
            logger?.debug("Make use of provided temporary directory")
            workingTemporaryDirectory = temporaryDirectory
        } else {
            logger?.debug("Use system temporary, transient directory")
            workingTemporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("BabelLyricsLib-\(UUID().uuidString)", isDirectory: true)
        }

        try fileManager.createDirectory(at: workingTemporaryDirectory, withIntermediateDirectories: true)

        var result: AudioSeparatorResult?
        var operationError: Error?

        do {
            logger?.info("Start separating audio")
            let stopWatch = StopWatch().start()
            result = try separate(
                audioURL: audioURL,
                model: model,
                outputDirectory: workingTemporaryDirectory
            )
            logger?.info("Completed separating audio in \(stopWatch.formattedUnitsStyle())")
        } catch {
            logger?.error("Audio separation failed")
            operationError = error
        }

        if shouldCleanupTemporaryDirectory {
            logger?.debug("Clean up transient temporary directory")
            do {
                try fileManager.removeItem(at: workingTemporaryDirectory)
            } catch {
                if operationError == nil {
                    logger?.error("Failed to clean up transient temporary directory")
                    throw AudioSeparatorError.failedToRemoveTemporaryDirectory(
                        workingTemporaryDirectory,
                        String(describing: error)
                    )
                }
            }
        }

        if let operationError {
            throw operationError
        }

        guard let result else {
            throw AudioSeparatorError.demucsCommandFailed("Unknown separation failure.")
        }
        return result
    }

    private func separate(
        audioURL: URL,
        model: AudioSeparatorModel,
        outputDirectory: URL
    ) throws -> AudioSeparatorResult {
        let arguments = [
            "--two-stems", "vocals",
            "--mp3",
            "--mp3-bitrate", "320",
            "--name", model.demucsName,
            "--out", outputDirectory.path,
            audioURL.path,
        ]
        if let demucsOverride {
            logger?.debug("Execute override Demucs")
            try demucsOverride(arguments)
        } else {
            try executeDemucs(arguments: arguments)
        }

        let sourceStemDirectory = outputDirectory
            .appendingPathComponent(model.demucsName, isDirectory: true)
            .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        let sourceVocalsURL = sourceStemDirectory.appendingPathComponent("vocals.mp3")
        let sourceMusicURL = sourceStemDirectory.appendingPathComponent("no_vocals.mp3")

        guard fileManager.fileExists(atPath: sourceVocalsURL.path) else {
            throw AudioSeparatorError.missingDemucsOutput(sourceVocalsURL)
        }
        guard fileManager.fileExists(atPath: sourceMusicURL.path) else {
            throw AudioSeparatorError.missingDemucsOutput(sourceMusicURL)
        }

        let destinationDirectory = audioURL.deletingLastPathComponent()
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let destinationVocalsURL = destinationDirectory.appendingPathComponent("\(baseName)-vocals.mp3")
        let destinationMusicURL = destinationDirectory.appendingPathComponent("\(baseName)-music.mp3")

        if fileManager.fileExists(atPath: destinationVocalsURL.path) {
            try fileManager.removeItem(at: destinationVocalsURL)
        }
        if fileManager.fileExists(atPath: destinationMusicURL.path) {
            try fileManager.removeItem(at: destinationMusicURL)
        }

        try fileManager.moveItem(at: sourceVocalsURL, to: destinationVocalsURL)
        try fileManager.moveItem(at: sourceMusicURL, to: destinationMusicURL)

        return AudioSeparatorResult(vocalsURL: destinationVocalsURL, musicURL: destinationMusicURL)
    }

    private func executeDemucs(arguments: [String]) throws {
        let process = Process()
        
        let executable = "/usr/bin/env"
        let commandArguments = ["python3", "-m", "demucs.separate"] + arguments
        
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["python3", "-m", "demucs.separate"] + arguments

        logger?.debug("\(executable) \(commandArguments.joined(separator: " "))")
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errorData, encoding: .utf8) ?? "Demucs command failed."
            throw AudioSeparatorError.demucsCommandFailed(stderr)
        }
    }
}
