import Foundation

/// Transcribes segmented audio with Whisper and maps timings back to the source audio timeline.
public struct AudioTranscriber: @unchecked Sendable {
    private let fileManager: FileManager
    private let whisperOverride: (([String]) throws -> Void)?
    private let logger: LogService?

    /// Creates a transcription workflow.
    ///
    /// - Parameters:
    ///   - fileManager: File manager used for filesystem operations.
    ///   - whisperOverride: Optional command override used for Whisper execution.
    ///   - logger: Optional log delegate for workflow lifecycle and error messages.
    public init(
        fileManager: FileManager = .default,
        whisperOverride: (([String]) throws -> Void)? = nil,
        logger: (any LogDelegate)? = nil
    ) {
        self.fileManager = fileManager
        self.whisperOverride = whisperOverride
        if let logger {
            self.logger = .init(delegate: logger)
        } else {
            self.logger = nil
        }
    }

    /// Transcribes each segment in a ``AudioSegmenterModel`` and maps timings back to source audio time.
    ///
    /// - Parameters:
    ///   - segmentAudioResult: Segments to transcribe.
    ///   - audioSegmentSourceURL: Source URL used to generate segment file paths.
    ///     Segment file paths are resolved via ``AudioSegment/segmentFileURL(from:index:)``.
    ///   - temporaryDirectory: Optional working directory for Whisper output.
    ///     When omitted, a temporary directory is created and removed after processing.
    ///   - configuration: Whisper configuration. Defaults to model `large-v3`, language `en`,
    ///     task `transcribe`, beam size `5`, and temperature `0.0`.
    ///   - onProgress: Optional callback that receives normalized progress and ETA across segments.
    /// - Returns: A Codable transcription result containing lines and timed words in source order.
    /// - Throws: ``AudioTranscriberError`` or underlying filesystem/process errors.
    public func transcribeAudio(
        from segmentAudioResult: AudioSegmenterModel,
        audioSegmentSourceURL: URL,
        temporaryDirectory: URL? = nil,
        configuration: AudioTranscriberConfiguration = .init(),
        onProgress: ProgressHandler? = nil
    ) throws -> AudioTranscriberModel {
        if configuration.beamSize <= 0 {
            logger?.error("Whisper beam size must be greater than zero")
            throw AudioTranscriberError.invalidWhisperConfiguration("beamSize must be greater than 0")
        }
        if let bestOf = configuration.bestOf, bestOf <= 0 {
            logger?.error("Whisper best_of must be greater than zero")
            throw AudioTranscriberError.invalidWhisperConfiguration("bestOf must be greater than 0")
        }

        let shouldCleanupTemporaryDirectory = temporaryDirectory == nil
        let workingTemporaryDirectory: URL
        if let temporaryDirectory {
            logger?.debug("Use provided temporary directory for Whisper")
            workingTemporaryDirectory = temporaryDirectory
        } else {
            logger?.debug("Use system temporary directory for Whisper")
            workingTemporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("BabelLyricsLib-AudioTranscriber-\(UUID().uuidString)", isDirectory: true)
        }

        try fileManager.createDirectory(at: workingTemporaryDirectory, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: workingTemporaryDirectory.path, isDirectory: nil) else {
            logger?.error("Provided Whisper temporary directory does not exist")
            throw AudioTranscriberError.providedTemporaryDirectoryMissing(workingTemporaryDirectory)
        }

        var result: AudioTranscriberModel?
        var operationError: Error?

        do {
            logger?.info("Start transcribing audio segments")
            let stopWatch = StopWatch().start()
            result = try transcribe(
                segmentAudioResult: segmentAudioResult,
                audioSegmentSourceURL: audioSegmentSourceURL,
                outputDirectory: workingTemporaryDirectory,
                configuration: configuration,
                onProgress: onProgress
            )
            logger?.info("Completed transcribing audio in \(stopWatch.formattedUnitsStyle())")
        } catch {
            logger?.error("Transcribing audio failed")
            operationError = error
        }

        if shouldCleanupTemporaryDirectory {
            logger?.debug("Clean up Whisper temporary directory")
            do {
                try fileManager.removeItem(at: workingTemporaryDirectory)
            } catch {
                if operationError == nil {
                    logger?.error("Failed to clean up Whisper temporary directory")
                    throw AudioTranscriberError.failedToRemoveTemporaryDirectory(
                        workingTemporaryDirectory,
                        String(describing: error)
                    )
                }
            }
        } else {
            logger?.debug("Preserve provided Whisper temporary directory")
        }

        if let operationError {
            throw operationError
        }

        guard let result else {
            throw AudioTranscriberError.whisperCommandFailed("Unknown transcription failure.")
        }
        return result
    }

    private func transcribe(
        segmentAudioResult: AudioSegmenterModel,
        audioSegmentSourceURL: URL,
        outputDirectory: URL,
        configuration: AudioTranscriberConfiguration,
        onProgress: ProgressHandler?
    ) throws -> AudioTranscriberModel {
        let segmentCount = segmentAudioResult.segments.count
        var lines: [TranscribedLine] = []
        lines.reserveCapacity(segmentCount)
        let startedAt = Date()

        for (offset, segment) in segmentAudioResult.segments.enumerated() {
            let progressSegmentIndex = offset + 1
            let segmentURL = AudioSegment.segmentFileURL(from: audioSegmentSourceURL, index: segment.index)
            guard fileManager.fileExists(atPath: segmentURL.path) else {
                logger?.warning("Skip missing segment file at \(segmentURL.lastPathComponent)")
                continue
            }

            logger?.info("Transcribing segment \(segment.index) / \(segmentCount)")
            emitProgress(
                onProgress: onProgress,
                startedAt: startedAt,
                segmentIndex: progressSegmentIndex,
                totalSegments: segmentCount,
                segmentFraction: 0,
                message: "Starting segment \(progressSegmentIndex) of \(segmentCount)"
            )
            
            let segmentOffsetSeconds = try seconds(from: segment.startTime)
            let stopWatch = StopWatch().start()
            let transcript = try transcribeSegment(
                segmentURL: segmentURL,
                outputDirectory: outputDirectory,
                configuration: configuration,
                segmentIndex: progressSegmentIndex,
                totalSegments: segmentCount,
                startedAt: startedAt,
                onProgress: onProgress
            )
            
            logger?.debug("Took \(stopWatch.formattedUnitsStyle()) to transcribe segment \(segment.index)")
            if transcript.segments.isEmpty {
                logger?.warning("Transcribing segment \(segment.index) completed with NO lines")
            } else {
                logger?.debug("Transcribing segment \(segment.index) completed with \(transcript.segments.count) lines")
            }

            for whisperLine in transcript.segments {
                let whisperWords: [WhisperTranscriptWord] = whisperLine.words ?? []
                let absoluteWords: [(start: Double, end: Double, text: String)] = whisperWords.map { word in
                    (
                        start: segmentOffsetSeconds + word.start,
                        end: segmentOffsetSeconds + word.end,
                        text: word.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    )
                }

                let lineStartSeconds: Double
                let lineEndSeconds: Double
                if let firstWord = absoluteWords.first, let lastWord = absoluteWords.last {
                    lineStartSeconds = firstWord.start
                    lineEndSeconds = lastWord.end
                } else {
                    lineStartSeconds = segmentOffsetSeconds + whisperLine.start
                    lineEndSeconds = segmentOffsetSeconds + whisperLine.end
                }

                let words: [TranscribedWord] = absoluteWords.map { word in
                    let relativeStart = max(0, word.start - lineStartSeconds)
                    let relativeEnd = max(relativeStart, word.end - lineStartSeconds)
                    return TranscribedWord(
                        startTime: duration(fromSeconds: relativeStart),
                        endTime: duration(fromSeconds: relativeEnd),
                        text: word.text
                    )
                }

                let text = whisperLine.text.isEmpty ? words.map({ $0.text }).joined(separator: " ") : whisperLine.text
                lines.append(
                    TranscribedLine(
                        segmentIndex: segment.index,
                        startTime: duration(fromSeconds: lineStartSeconds),
                        endTime: duration(fromSeconds: lineEndSeconds),
                        text: text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                        words: words
                    )
                )
            }

            emitProgress(
                onProgress: onProgress,
                startedAt: startedAt,
                segmentIndex: progressSegmentIndex,
                totalSegments: segmentCount,
                segmentFraction: 1,
                message: "Completed segment \(progressSegmentIndex) of \(segmentCount)"
            )
        }

        if segmentCount > 0 {
            emitProgress(
                onProgress: onProgress,
                startedAt: startedAt,
                segmentIndex: segmentCount,
                totalSegments: segmentCount,
                segmentFraction: 1,
                message: "Completed Whisper transcription"
            )
        }

        return AudioTranscriberModel(
            sourceAudioDuration: segmentAudioResult.sourceAudioDuration,
            lines: lines
        )
    }

    private func transcribeSegment(
        segmentURL: URL,
        outputDirectory: URL,
        configuration: AudioTranscriberConfiguration,
        segmentIndex: Int,
        totalSegments: Int,
        startedAt: Date,
        onProgress: ProgressHandler?
    ) throws -> WhisperTranscriptFile {
        let segmentOutputDirectory = outputDirectory
            .appendingPathComponent("segment-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: segmentOutputDirectory, withIntermediateDirectories: true)

        let preferredDevice = preferredWhisperDevice()
        var arguments = buildWhisperArguments(
            configuration: configuration,
            outputDirectory: segmentOutputDirectory,
            segmentURL: segmentURL,
            device: preferredDevice
        )

        var processOutput = ""
        if let whisperOverride {
            logger?.debug("Execute override Whisper")
            emitProgress(
                onProgress: onProgress,
                startedAt: startedAt,
                segmentIndex: segmentIndex,
                totalSegments: totalSegments,
                segmentFraction: 0,
                message: "Whisper override started for segment \(segmentIndex)"
            )
            try whisperOverride(arguments)
            emitProgress(
                onProgress: onProgress,
                startedAt: startedAt,
                segmentIndex: segmentIndex,
                totalSegments: totalSegments,
                segmentFraction: 1,
                message: "Whisper override completed for segment \(segmentIndex)"
            )
        } else {
            let relayProgress: @Sendable (Double, String?) -> Void = { segmentFraction, message in
                emitProgress(
                    onProgress: onProgress,
                    startedAt: startedAt,
                    segmentIndex: segmentIndex,
                    totalSegments: totalSegments,
                    segmentFraction: segmentFraction,
                    message: message
                )
            }

            do {
                processOutput = try executeWhisper(arguments: arguments, onProgress: relayProgress)
            } catch let error as AudioTranscriberError {
                guard case let .whisperCommandFailed(commandOutput) = error,
                      preferredDevice == "mps",
                      isMPSFloat64UnsupportedError(commandOutput) else {
                    throw error
                }

                logger?.warning("Whisper failed on MPS float64, retrying on CPU for segment \(segmentIndex)")
                emitProgress(
                    onProgress: onProgress,
                    startedAt: startedAt,
                    segmentIndex: segmentIndex,
                    totalSegments: totalSegments,
                    segmentFraction: 0,
                    message: "Retrying segment \(segmentIndex) on CPU due to MPS float64 limitation"
                )
                arguments = buildWhisperArguments(
                    configuration: configuration,
                    outputDirectory: segmentOutputDirectory,
                    segmentURL: segmentURL,
                    device: "cpu"
                )
                processOutput = try executeWhisper(arguments: arguments, onProgress: relayProgress)
            }
            if !processOutput.isEmpty {
                logger?.debug("Whisper process output for \(segmentURL.lastPathComponent):\n\(processOutput)")
            } else {
                logger?.warning("Whisper process output for \(segmentURL.lastPathComponent) was empty")
            }
        }

        let expectedTranscriptURL = segmentOutputDirectory.appendingPathComponent(
            segmentURL.deletingPathExtension().lastPathComponent + ".json"
        )

        let transcriptURL: URL
        if fileManager.fileExists(atPath: expectedTranscriptURL.path) {
            transcriptURL = expectedTranscriptURL
        } else if let discoveredURL = try discoverTranscriptJSON(in: segmentOutputDirectory) {
            transcriptURL = discoveredURL
        } else {
            if !processOutput.isEmpty {
                logger?.error("Whisper produced no transcript file. Process output:\n\(processOutput)")
            } else {
                logger?.error("Whisper produced no transcript file and no process output.")
            }
            throw AudioTranscriberError.missingTranscriptOutput(expectedTranscriptURL)
        }

        let data = try Data(contentsOf: transcriptURL)
        return try JSONDecoder().decode(WhisperTranscriptFile.self, from: data)
    }

    private func discoverTranscriptJSON(in directory: URL) throws -> URL? {
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "json" }

        if candidates.count == 1 {
            return candidates[0]
        }
        return nil
    }

    private func executeWhisper(
        arguments: [String],
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) throws -> String {
        let whisperExecutable = try resolveWhisperExecutable()

        logger?.debug("\(whisperExecutable) \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperExecutable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let logFileURL = fileManager.temporaryDirectory
            .appendingPathComponent("BabelLyricsLib-whisper-\(UUID().uuidString).log")
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
        logger?.debug("Log file created at \(logFileURL.path)")
        let logHandle = try FileHandle(forWritingTo: logFileURL)
        process.standardError = logHandle
        process.standardOutput = logHandle

        let monitor = WhisperProgressMonitor(logFileURL: logFileURL, onProgress: onProgress)
        monitor.start()
        defer {
            monitor.stop()
            try? logHandle.close()
            try? fileManager.removeItem(at: logFileURL)
        }

        try process.run()
        process.waitUntilExit()

        let outputData = try Data(contentsOf: logFileURL)
        let processOutput = String(data: outputData, encoding: .utf8) ?? ""
        logger?.debug("Whisper exited with \(process.terminationStatus)")
        guard process.terminationStatus == 0 else {
            throw AudioTranscriberError.whisperCommandFailed(processOutput)
        }
        return processOutput
    }

    private func resolveWhisperExecutable() throws -> String {
        let commonPaths = [
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper",
            "/usr/bin/whisper",
        ]
        if let resolved = commonPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return resolved
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["whisper"]

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

        throw AudioTranscriberError.whisperCommandFailed(
            "Unable to locate whisper executable via common install paths or `which whisper`.\n\(stderr)"
        )
    }

    private func preferredWhisperDevice() -> String {
        return "cpu"
    }

    private func buildWhisperArguments(
        configuration: AudioTranscriberConfiguration,
        outputDirectory: URL,
        segmentURL: URL,
        device: String
    ) -> [String] {
        let fp16Enabled = device != "cpu"
        var arguments = [
            "--model", configuration.model.name,
            "--language", configuration.language.code,
            "--task", configuration.task.rawValue,
            "--beam_size", String(configuration.beamSize),
            "--temperature", String(configuration.temperature),
            "--condition_on_previous_text", configuration.conditionOnPreviousText ? "True" : "False",
            "--output_format", "json",
            "--word_timestamps", "True",
            "--device", device,
            "--fp16", fp16Enabled ? "True" : "False",
            "--verbose", "False",
        ]
        if let bestOf = configuration.bestOf {
            arguments.append(contentsOf: ["--best_of", String(bestOf)])
        }
        if let initialPrompt = configuration.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !initialPrompt.isEmpty {
            arguments.append(contentsOf: ["--initial_prompt", initialPrompt])
        }
        if let threads = configuration.threads {
            arguments.append(contentsOf: ["--threads", String(threads)])
        }
        arguments.append(contentsOf: ["--output_dir", outputDirectory.path, segmentURL.path])
        return arguments
    }

    private func isMPSFloat64UnsupportedError(_ output: String) -> Bool {
        output.contains("MPS Tensor")
            && output.contains("float64")
            && output.contains("Please use float32 instead")
    }

    private func seconds(from time: String) throws -> Double {
        guard let seconds = Double(time) else {
            throw AudioTranscriberError.invalidSegmentOffset(time)
        }
        return seconds
    }

    private func duration(fromSeconds seconds: Double) -> Duration {
        .seconds((seconds * 1000).rounded() / 1000)
    }

    private func emitProgress(
        onProgress: ProgressHandler?,
        startedAt: Date,
        segmentIndex: Int,
        totalSegments: Int,
        segmentFraction: Double,
        message: String?
    ) {
        guard let onProgress else { return }
        let normalizedSegmentFraction = min(max(segmentFraction, 0), 1)
        let overallFraction = totalSegments == 0
            ? 1
            : min(max((Double(segmentIndex - 1) + normalizedSegmentFraction) / Double(totalSegments), 0), 1)
        let estimatedTimeRemaining: Duration?
        if overallFraction > 0 {
            let elapsed = Date().timeIntervalSince(startedAt)
            let estimatedTotal = elapsed / overallFraction
            estimatedTimeRemaining = .seconds(max(0, estimatedTotal - elapsed))
        } else {
            estimatedTimeRemaining = nil
        }

        onProgress(
            Progress(
                fractionCompleted: overallFraction,
                completedSegments: max(0, segmentIndex - 1),
                totalSegments: totalSegments,
                currentSegmentIndex: segmentIndex,
                currentSegmentFraction: normalizedSegmentFraction,
                estimatedTimeRemaining: estimatedTimeRemaining,
                message: message
            )
        )
    }
}

private final class WhisperProgressMonitor: @unchecked Sendable {
    private let logFileURL: URL
    private let onProgress: @Sendable (Double, String?) -> Void
    private let stateLock = NSLock()
    private var isRunning = false
    private var thread: Thread?

    init(logFileURL: URL, onProgress: @escaping @Sendable (Double, String?) -> Void) {
        self.logFileURL = logFileURL
        self.onProgress = onProgress
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning else { return }
        isRunning = true

        thread = Thread { [weak self, logFileURL, onProgress] in
            guard let handle = try? FileHandle(forReadingFrom: logFileURL) else {
                return
            }
            defer { try? handle.close() }

            var offset: UInt64 = 0
            let parser = WhisperProgressParser()
            while self?.shouldContinueRunning() == true {
                do {
                    try handle.seek(toOffset: offset)
                    let data = handle.readDataToEndOfFile()
                    if !data.isEmpty {
                        offset += UInt64(data.count)
                        let text = String(data: data, encoding: .utf8) ?? ""
                        for update in parser.updates(from: text) {
                            onProgress(update.fractionCompleted, update.message)
                        }
                    }
                } catch {
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        thread?.qualityOfService = .utility
        thread?.start()
    }

    func stop() {
        stateLock.lock()
        isRunning = false
        let thread = thread
        self.thread = nil
        stateLock.unlock()
        thread?.cancel()
    }

    private func shouldContinueRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }
}

private struct WhisperProgressUpdate {
    let fractionCompleted: Double
    let message: String?
}

private struct WhisperProgressParser {
    private let percentPattern = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,3}(?:\.\d+)?)%"#, options: [])

    func updates(from text: String) -> [WhisperProgressUpdate] {
        guard let percentPattern else { return [] }
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return percentPattern.matches(in: normalized, options: [], range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let percentRange = Range(match.range(at: 1), in: normalized),
                  let percent = Double(normalized[percentRange]) else {
                return nil
            }
            return WhisperProgressUpdate(
                fractionCompleted: min(max(percent / 100, 0), 1),
                message: "Whisper \(normalized[percentRange])%"
            )
        }
    }
}

private struct WhisperTranscriptFile: Codable {
    let segments: [WhisperTranscriptSegment]
}

private struct WhisperTranscriptSegment: Codable {
    let start: Double
    let end: Double
    let text: String
    let words: [WhisperTranscriptWord]?
}

private struct WhisperTranscriptWord: Codable {
    let start: Double
    let end: Double
    let text: String

    init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case text
        case word
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        text = try container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decode(String.self, forKey: .word)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(text, forKey: .text)
    }
}
