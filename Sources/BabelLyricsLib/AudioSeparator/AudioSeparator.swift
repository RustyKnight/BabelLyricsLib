import Foundation

/// Separates an input audio file into vocals and music tracks using Demucs.
public struct AudioSeparator: @unchecked Sendable {
    private let fileManager: FileManager
    private let demucsOverride: (([String]) throws -> Void)?
    private let ffmpegOverride: (([String]) throws -> String)?
    private let logger: LogService?

    /// Creates an audio separator.
    ///
    /// - Parameters:
    ///   - fileManager: File manager used for filesystem operations.
    ///   - demucsOverride: Optional command override for Demucs execution. If omitted, uses `python3 -m demucs.separate`.
    ///   - ffmpegOverride: Optional command override used for FFmpeg calls.
    ///   - logger: Optional log delegate that receives lifecycle, command, and error messages.
    public init(
        fileManager: FileManager = .default,
        demucsOverride: (([String]) throws -> Void)? = nil,
        ffmpegOverride: (([String]) throws -> String)? = nil,
        logger: (any LogDelegate)? = nil
    ) {
        self.fileManager = fileManager
        self.demucsOverride = demucsOverride
        self.ffmpegOverride = ffmpegOverride
        if let logger {
            self.logger = .init(delegate: logger)
        } else {
            self.logger = nil
        }
    }

    /// Splits an audio file into vocal-only and music-only WAV tracks.
    ///
    /// Output files are written alongside the input file using ``AudioSeparator/Files`` names.
    ///
    /// - Parameters:
    ///   - audioURL: Local URL to the input audio file.
    ///   - configuration: Optional Demucs command configuration. Defaults to ``AudioSeparator/DemucsConfiguration``.
    ///   - destinationDirectory: Optional directory where ``AudioSeparator/Files`` entries are exported.
    ///     When omitted, files are written beside the source audio file.
    ///   - temporaryDirectory: Optional output working directory for Demucs intermediate output.
    ///     When omitted, a temporary directory is created and removed after processing.
    ///   - onProgress: Optional callback for normalized separation progress updates.
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
        temporaryDirectory: URL? = nil,
        onProgress: ProgressHandler? = nil
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
                destinationDirectory: destinationDirectory ?? audioURL.deletingLastPathComponent(),
                onProgress: onProgress
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
        destinationDirectory: URL,
        onProgress: ProgressHandler?
    ) throws -> AudioSeparatorModel {
        var arguments = [
            "--two-stems", "vocals",
            "--float32",
            "--name", configuration.model.demucsName,
            "--device", configuration.device.demucsName,
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

        let totalPasses = max(1, configuration.shifts ?? 1)
        onProgress?(
            .init(
                fractionCompleted: 0,
                completedPasses: 0,
                totalPasses: totalPasses,
                currentPassFraction: 0,
                estimatedTimeRemaining: nil,
                message: "Starting Demucs separation"
            )
        )

        if let demucsOverride {
            logger?.debug("Execute override Demucs")
            try demucsOverride(arguments)
            onProgress?(
                .init(
                    fractionCompleted: 1,
                    completedPasses: totalPasses,
                    totalPasses: totalPasses,
                    currentPassFraction: 1,
                    estimatedTimeRemaining: .zero,
                    message: "Demucs override completed"
                )
            )
        } else {
            try executeDemucs(arguments: arguments, shifts: configuration.shifts ?? 1, onProgress: onProgress)
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
        let destinationVocalsURL = Files.vocals.url(in: destinationDirectory)
        let destinationMusicURL = Files.music.url(in: destinationDirectory)
        let destinationMonoVocalsURL = Files.vocalsMono.url(in: destinationDirectory)

        if fileManager.fileExists(atPath: destinationVocalsURL.path) {
            try fileManager.removeItem(at: destinationVocalsURL)
        }
        if fileManager.fileExists(atPath: destinationMusicURL.path) {
            try fileManager.removeItem(at: destinationMusicURL)
        }

        try fileManager.moveItem(at: sourceVocalsURL, to: destinationVocalsURL)
        try fileManager.moveItem(at: sourceMusicURL, to: destinationMusicURL)
        try createMonoAudio(sourceAudioURL: destinationVocalsURL, monoAudioURL: destinationMonoVocalsURL)

        return AudioSeparatorModel(vocalsURL: destinationVocalsURL, musicURL: destinationMusicURL)
    }

    private func createMonoAudio(
        sourceAudioURL: URL,
        monoAudioURL: URL
    ) throws {
        logger?.debug("Create mono vocal file at \(monoAudioURL.lastPathComponent)")
        _ = try runFFmpeg([
            "-hide_banner",
            "-y",
            "-i", sourceAudioURL.path,
            "-vn",
            "-af", "pan=mono|c0=0.5*c0+0.5*c1",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            monoAudioURL.path,
        ])
    }

    private func executeDemucs(
        arguments: [String],
        shifts: Int,
        onProgress: ProgressHandler?
    ) throws {
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
        let progressMonitor = DemucsProgressMonitor(
            fileURL: logFileURL,
            expectedShifts: shifts,
            onProgress: onProgress
        )
        progressMonitor.start()
        process.waitUntilExit()
        progressMonitor.stop()
        try logHandle.close()

        let outputData = try Data(contentsOf: logFileURL)
        try? fileManager.removeItem(at: logFileURL)
        let output = String(data: outputData, encoding: .utf8) ?? "Demucs command failed."
        if process.terminationStatus == 0 {
            onProgress?(
                .init(
                    fractionCompleted: 1,
                    completedPasses: progressMonitor.totalPasses,
                    totalPasses: progressMonitor.totalPasses,
                    currentPassFraction: 1,
                    estimatedTimeRemaining: .zero,
                    message: "Demucs separation completed"
                )
            )
        }
        guard process.terminationStatus == 0 else {
            throw AudioSeparatorError.demucsCommandFailed(output)
        }
    }

    private func runFFmpeg(_ arguments: [String]) throws -> String {
        if let ffmpegOverride {
            logger?.debug("Execute override ffmpeg")
            return try ffmpegOverride(arguments)
        }

        let ffmpegExecutable = try resolveFFmpegExecutable()

        logger?.debug("\(ffmpegExecutable) \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegExecutable)
        process.arguments = ["-nostdin"] + arguments

        let logFileURL = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLib-ffmpeg-\(UUID().uuidString).log")
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFileURL)
        process.standardInput = FileHandle.nullDevice
        process.standardError = logHandle
        process.standardOutput = logHandle

        try process.run()
        process.waitUntilExit()
        try logHandle.close()

        let stderrData = try Data(contentsOf: logFileURL)
        try? fileManager.removeItem(at: logFileURL)
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw AudioSeparatorError.ffmpegCommandFailed(stderr)
        }
        return stderr
    }

    private func resolveFFmpegExecutable() throws -> String {
        let commonPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        if let resolved = commonPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return resolved
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0, !stdout.isEmpty {
            return stdout
        }

        throw AudioSeparatorError.ffmpegCommandFailed(
            "Unable to locate ffmpeg executable via common install paths or `which ffmpeg`.\n\(stderr)"
        )
    }
}

private struct DemucsProgressEstimator {
    private var modelPasses = 1
    private let shifts: Int
    private let startedAt = Date()
    private var completedPasses = 0
    private var currentPassFraction: Double = 0
    private var lastPercent: Double?
    private var lastEmittedFraction: Double = -1

    init(shifts: Int) {
        self.shifts = max(1, shifts)
    }

    var totalPasses: Int {
        max(1, modelPasses * shifts)
    }

    mutating func progressUpdates(from text: String) -> [AudioSeparator.Progress] {
        var updates: [AudioSeparator.Progress] = []
        for line in splitProgressLines(in: text) {
            if let parsedModelPasses = parseModelPasses(from: line), parsedModelPasses > 0 {
                modelPasses = parsedModelPasses
            }
            guard let percent = parsePercent(from: line) else {
                continue
            }

            if let lastPercent, percent + 3 < lastPercent, lastPercent >= 90, completedPasses < totalPasses {
                completedPasses += 1
            }
            lastPercent = percent
            currentPassFraction = max(0, min(1, percent / 100))

            let normalized = normalizedProgress()
            if normalized <= lastEmittedFraction {
                continue
            }
            lastEmittedFraction = normalized
            updates.append(
                .init(
                    fractionCompleted: normalized,
                    completedPasses: completedPasses,
                    totalPasses: totalPasses,
                    currentPassFraction: currentPassFraction,
                    estimatedTimeRemaining: estimatedRemaining(for: normalized),
                    message: line
                )
            )
        }
        return updates
    }

    private func normalizedProgress() -> Double {
        let value = (Double(completedPasses) + currentPassFraction) / Double(totalPasses)
        return max(0, min(1, value))
    }

    private func estimatedRemaining(for fractionCompleted: Double) -> Duration? {
        guard fractionCompleted > 0.01 else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        let estimatedTotal = elapsed / fractionCompleted
        let remaining = max(0, estimatedTotal - elapsed)
        return .seconds(remaining)
    }

    private func splitProgressLines(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline || $0 == "\r" })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseModelPasses(from line: String) -> Int? {
        guard let matchRange = line.range(of: #"bag of (\d+) models"#, options: .regularExpression) else {
            return nil
        }
        let matchedText = String(line[matchRange])
        guard let numberRange = matchedText.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        return Int(matchedText[numberRange])
    }

    private func parsePercent(from line: String) -> Double? {
        guard let percentRange = line.range(of: #"\d{1,3}(?:\.\d+)?%"#, options: .regularExpression) else {
            return nil
        }
        let percentText = String(line[percentRange]).replacingOccurrences(of: "%", with: "")
        return Double(percentText)
    }
}

private final class DemucsProgressMonitor: @unchecked Sendable {
    private let fileURL: URL
    private let onProgress: AudioSeparator.ProgressHandler?
    private let lock = NSLock()
    private var isRunning = false
    private var thread: Thread?
    private var estimator: DemucsProgressEstimator

    init(fileURL: URL, expectedShifts: Int, onProgress: AudioSeparator.ProgressHandler?) {
        self.fileURL = fileURL
        self.onProgress = onProgress
        estimator = .init(shifts: expectedShifts)
    }

    var totalPasses: Int {
        lock.lock()
        defer { lock.unlock() }
        return estimator.totalPasses
    }

    func start() {
        guard onProgress != nil else {
            return
        }
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        thread = Thread { [weak self] in
            self?.run()
        }
        thread?.name = "BabelLyricsLib-DemucsProgressMonitor"
        thread?.start()
    }

    func stop() {
        lock.lock()
        isRunning = false
        let runningThread = thread
        lock.unlock()

        while runningThread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.05)
        }
        thread = nil
    }

    private func run() {
        guard let onProgress else {
            return
        }
        var fileOffset: UInt64 = 0
        while true {
            lock.lock()
            let running = isRunning
            lock.unlock()
            if !running {
                break
            }
            do {
                let handle = try FileHandle(forReadingFrom: fileURL)
                try handle.seek(toOffset: fileOffset)
                let data = try handle.readToEnd() ?? Data()
                fileOffset += UInt64(data.count)
                try handle.close()
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    lock.lock()
                    let updates = estimator.progressUpdates(from: text)
                    lock.unlock()
                    for update in updates {
                        onProgress(update)
                    }
                }
            } catch {
                // Ignore transient file read errors while process is still running.
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
