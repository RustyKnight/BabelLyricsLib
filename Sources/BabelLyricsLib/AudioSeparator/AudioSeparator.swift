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

    /// Splits an audio file into vocal-only and music-only WAV tracks.
    ///
    /// Output files are written alongside the input file as `vocals.wav` and `music.wav`.
    ///
    /// - Parameters:
    ///   - audioURL: Local URL to the input audio file.
    ///   - configuration: Optional Demucs command configuration. Defaults to ``AudioSeparator/DemucsConfiguration``.
    ///   - destinationDirectory: Optional directory where `vocals.wav` and `music.wav` are exported.
    ///     When omitted, files are written beside the source audio file.
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
        configuration: AudioSeparator.DemucsConfiguration = .init(),
        destinationDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) throws -> AudioSeparatorModel {
        guard audioURL.isFileURL else {
            logger?.error("Audio source must be a file")
            throw AudioSeparatorError.inputMustBeFileURL
        }
        if let destinationDirectory, !destinationDirectory.isFileURL {
            logger?.error("Audio destination directory must be a file URL")
            throw AudioSeparatorError.destinationDirectoryMustBeFileURL
        }
        guard fileManager.fileExists(atPath: audioURL.path) else {
            logger?.error("Audio source is missing")
            throw AudioSeparatorError.inputFileMissing(audioURL)
        }

        if let segment = configuration.segment, segment <= 0 {
            logger?.error("Demucs segment must be greater than zero")
            throw AudioSeparatorError.invalidDemucsConfiguration("segment must be greater than 0")
        }
        if let shifts = configuration.shifts, shifts <= 0 {
            logger?.error("Demucs shifts must be greater than zero")
            throw AudioSeparatorError.invalidDemucsConfiguration("shifts must be greater than 0")
        }
        if let jobs = configuration.jobs, jobs <= 0 {
            logger?.error("Demucs jobs must be greater than zero")
            throw AudioSeparatorError.invalidDemucsConfiguration("jobs must be greater than 0")
        }
        if let overlap = configuration.overlap, !(0.0...0.99).contains(overlap) {
            logger?.error("Demucs overlap must be between 0.0 and 0.99")
            throw AudioSeparatorError.invalidDemucsConfiguration("overlap must be between 0.0 and 0.99")
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

        var result: AudioSeparatorModel?
        var operationError: Error?

        do {
            logger?.info("Start separating audio")
            let stopWatch = StopWatch().start()
            result = try separate(
                audioURL: audioURL,
                configuration: configuration,
                outputDirectory: workingTemporaryDirectory,
                destinationDirectory: destinationDirectory ?? audioURL.deletingLastPathComponent()
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
        configuration: AudioSeparator.DemucsConfiguration,
        outputDirectory: URL,
        destinationDirectory: URL
    ) throws -> AudioSeparatorModel {
        var arguments = [
            "--two-stems", "vocals",
            "--name", configuration.model.demucsName,
        ]
        if let segment = configuration.segment {
            arguments.append(contentsOf: ["--segment", String(segment)])
        }
        if let overlap = configuration.overlap {
            arguments.append(contentsOf: ["--overlap", String(overlap)])
        }
        if let shifts = configuration.shifts {
            arguments.append(contentsOf: ["--shifts", String(shifts)])
        }
        if let jobs = configuration.jobs {
            arguments.append(contentsOf: ["--jobs", String(jobs)])
        }
        arguments.append(contentsOf: ["--out", outputDirectory.path, audioURL.path])
        if let demucsOverride {
            logger?.debug("Execute override Demucs")
            try demucsOverride(arguments)
        } else {
            try executeDemucs(arguments: arguments)
        }

        let sourceStemDirectory = outputDirectory
            .appendingPathComponent(configuration.model.demucsName, isDirectory: true)
            .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        let sourceVocalsURL = sourceStemDirectory.appendingPathComponent("vocals.wav")
        let sourceMusicURL = sourceStemDirectory.appendingPathComponent("no_vocals.wav")

        guard fileManager.fileExists(atPath: sourceVocalsURL.path) else {
            throw AudioSeparatorError.missingDemucsOutput(sourceVocalsURL)
        }
        guard fileManager.fileExists(atPath: sourceMusicURL.path) else {
            throw AudioSeparatorError.missingDemucsOutput(sourceMusicURL)
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationVocalsURL = destinationDirectory.appendingPathComponent("vocals.wav")
        let destinationMusicURL = destinationDirectory.appendingPathComponent("music.wav")

        if fileManager.fileExists(atPath: destinationVocalsURL.path) {
            try fileManager.removeItem(at: destinationVocalsURL)
        }
        if fileManager.fileExists(atPath: destinationMusicURL.path) {
            try fileManager.removeItem(at: destinationMusicURL)
        }

        try fileManager.moveItem(at: sourceVocalsURL, to: destinationVocalsURL)
        try fileManager.moveItem(at: sourceMusicURL, to: destinationMusicURL)

        return AudioSeparatorModel(vocalsURL: destinationVocalsURL, musicURL: destinationMusicURL)
    }

    private func executeDemucs(arguments: [String]) throws {
        let process = Process()
        
        let executable = "/usr/bin/env"
        let commandArguments = ["python3", "-m", "demucs.separate"] + arguments
        
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["python3", "-m", "demucs.separate"] + arguments

        logger?.debug("\(executable) \(commandArguments.joined(separator: " "))")

        let logFileURL = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLib-demucs-\(UUID().uuidString).log")
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFileURL)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()
        try logHandle.close()

        let outputData = try Data(contentsOf: logFileURL)
        try? fileManager.removeItem(at: logFileURL)
        let output = String(data: outputData, encoding: .utf8) ?? "Demucs command failed."
        guard process.terminationStatus == 0 else {
            throw AudioSeparatorError.demucsCommandFailed(output)
        }
    }
}
