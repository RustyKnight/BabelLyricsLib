import Foundation

/// Transcribes segmented audio with Whisper and maps timings back to the source audio timeline.
public struct AudioTranscriber {
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
    ///   - configuration: Whisper configuration. Defaults to model `large`, language `en`, temperature `0.0`.
    /// - Returns: A Codable transcription result containing lines and timed words in source order.
    /// - Throws: ``AudioTranscriberError`` or underlying filesystem/process errors.
    public func transcribeAudio(
        from segmentAudioResult: AudioSegmenterModel,
        audioSegmentSourceURL: URL,
        temporaryDirectory: URL? = nil,
        configuration: AudioTranscriberConfiguration = .init()
    ) throws -> AudioTranscriberModel {
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
                configuration: configuration
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
        configuration: AudioTranscriberConfiguration
    ) throws -> AudioTranscriberModel {
        var lines: [TranscribedLine] = []
        lines.reserveCapacity(segmentAudioResult.segments.count)

        for segment in segmentAudioResult.segments {
            let segmentURL = AudioSegment.segmentFileURL(from: audioSegmentSourceURL, index: segment.index)
            guard fileManager.fileExists(atPath: segmentURL.path) else {
                logger?.warning("Skip missing segment file at \(segmentURL.lastPathComponent)")
                continue
            }

            logger?.info("Start transcribing segment \(segment.index)")
            
            let segmentOffsetSeconds = try seconds(from: segment.startTime)
            let stopWatch = StopWatch().start()
            let transcript = try transcribeSegment(
                segmentURL: segmentURL,
                outputDirectory: outputDirectory,
                configuration: configuration
            )
            
            logger?.debug("Took \(stopWatch.formattedUnitsStyle()) to transcribe segment \(segment.index)")
            if transcript.segments.isEmpty {
                logger?.warning("Transcribe for segment \(segment.index) completed with NO lines")
            } else {
                logger?.debug("Transcribe for segment \(segment.index) completed with \(transcript.segments.count) lines")
            }

            for whisperLine in transcript.segments {
                let whisperWords: [WhisperTranscriptWord] = whisperLine.words ?? []
                let words: [TranscribedWord] = whisperWords.map { word in
                    TranscribedWord(
                        startTime: duration(fromSeconds: segmentOffsetSeconds + word.start),
                        endTime: duration(fromSeconds: segmentOffsetSeconds + word.end),
                        text: word.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    )
                }

                let lineStart: Duration
                let lineEnd: Duration
                if let firstWord = words.first, let lastWord = words.last {
                    lineStart = firstWord.startTime
                    lineEnd = lastWord.endTime
                } else {
                    lineStart = duration(fromSeconds: segmentOffsetSeconds + whisperLine.start)
                    lineEnd = duration(fromSeconds: segmentOffsetSeconds + whisperLine.end)
                }

                let text = whisperLine.text.isEmpty ? words.map({ $0.text }).joined(separator: " ") : whisperLine.text
                lines.append(
                    TranscribedLine(
                        segmentIndex: segment.index,
                        startTime: lineStart,
                        endTime: lineEnd,
                        text: text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                        words: words
                    )
                )
            }
        }

        return AudioTranscriberModel(
            sourceAudioDuration: segmentAudioResult.sourceAudioDuration,
            lines: lines
        )
    }

    private func transcribeSegment(
        segmentURL: URL,
        outputDirectory: URL,
        configuration: AudioTranscriberConfiguration
    ) throws -> WhisperTranscriptFile {
        let segmentOutputDirectory = outputDirectory
            .appendingPathComponent("segment-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: segmentOutputDirectory, withIntermediateDirectories: true)

        let effectiveTemperature = configuration.beamSize == nil ? configuration.temperature : 0.0
        var arguments = [
            "--model", configuration.model,
            "--language", configuration.language,
            "--temperature", String(effectiveTemperature),
            "--device", "cpu",
            "--task", "transcribe",
            "--output_format", "json",
            "--word_timestamps", "True",
        ]
        if let beamSize = configuration.beamSize {
            arguments.append(contentsOf: ["--beam_size", String(beamSize)])
        }
        if let threads = configuration.threads {
            arguments.append(contentsOf: ["--threads", String(threads)])
        }
        arguments.append(contentsOf: ["--output_dir", segmentOutputDirectory.path, segmentURL.path])

        let processOutput: String
        if let whisperOverride {
            logger?.debug("Execute override Whisper")
            try whisperOverride(arguments)
            processOutput = ""
        } else {
            processOutput = try executeWhisper(arguments: arguments)
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

    private func executeWhisper(arguments: [String]) throws -> String {
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

        try process.run()
        process.waitUntilExit()
        try logHandle.close()

        let outputData = try Data(contentsOf: logFileURL)
        try? fileManager.removeItem(at: logFileURL)
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

    private func seconds(from time: String) throws -> Double {
        guard let seconds = Double(time) else {
            throw AudioTranscriberError.invalidSegmentOffset(time)
        }
        return seconds
    }

    private func duration(fromSeconds seconds: Double) -> Duration {
        .seconds((seconds * 1000).rounded() / 1000)
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
