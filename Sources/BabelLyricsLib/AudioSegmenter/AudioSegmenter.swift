import Foundation

/// Splits an audio file into non-silent segments using FFmpeg silence detection.
///
/// Generated files are stored in the caller-provided output directory and are named
/// `vocal-segment-<index>.wav`.
public struct AudioSegmenter {
    private let fileManager: FileManager
    private let ffmpegOverride: (([String]) throws -> String)?
    private let logger: LogService?

    /// Creates a segment-audio workflow.
    ///
    /// - Parameters:
    ///   - fileManager: File manager used for filesystem operations.
    ///   - ffmpegOverride: Optional command override used for FFmpeg calls.
    ///   - logger: Optional log delegate for workflow lifecycle and error messages.
    public init(
        fileManager: FileManager = .default,
        ffmpegOverride: (([String]) throws -> String)? = nil,
        logger: (any LogDelegate)? = nil
    ) {
        self.fileManager = fileManager
        self.ffmpegOverride = ffmpegOverride
        if let logger {
            self.logger = .init(delegate: logger)
        } else {
            self.logger = nil
        }
    }

    /// Segments an audio file by silence boundaries and stores segment files in the output directory.
    ///
    /// Existing files whose name contains `-segment-` are removed from the output directory before
    /// segment generation starts.
    ///
    /// - Parameters:
    ///   - audioURL: Local source audio file URL.
    ///   - outputDirectory: Required destination directory for generated segment files.
    ///   - configuration: Silence detection configuration. Defaults to ``AudioSegmenterConfiguration`` defaults.
    /// - Returns: A Codable model containing source duration and ordered segment metadata.
    ///   Segment times are formatted as `{seconds}.{milliseconds}`.
    /// - Throws: ``AudioSegmenterError`` or underlying filesystem/process errors.
    public func segmentAudio(
        at audioURL: URL,
        outputDirectory: URL,
        configuration: AudioSegmenterConfiguration = .init()
    ) throws -> AudioSegmenterModel {
        logger?.info("Started segmenting audio for \(audioURL.lastPathComponent)")
        guard audioURL.isFileURL else {
            logger?.error("Audio source must be a file")
            throw AudioSegmenterError.inputMustBeFileURL
        }
        guard fileManager.fileExists(atPath: audioURL.path) else {
            logger?.error("Audio source must exist")
            throw AudioSegmenterError.inputFileMissing(audioURL)
        }

        logger?.debug("Create output directory")
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        logger?.debug("Clean output directory as required")
        try removeExistingSegmentFiles(in: outputDirectory)

        logger?.debug("Convert source audio to mono")
        let monoAudioURL = outputDirectory
            .appendingPathComponent("\(audioURL.deletingPathExtension().lastPathComponent)-mono.wav")
        try createMonoAudio(sourceAudioURL: audioURL, monoAudioURL: monoAudioURL)

        let detectionOutput = try detectSilences(audioURL: monoAudioURL, configuration: configuration)
        let segmentCount = detectionOutput.silences.count
        
        logger?.debug("Detected duration: \(detectionOutput.durationSeconds)")
        logger?.debug("Detected silences: \(segmentCount)")
        
        logger?.debug("Build segments")
        let segmentRanges = buildSegmentRanges(from: detectionOutput.silences, duration: detectionOutput.durationSeconds)

        let segmentSourceURL = monoAudioURL

        var segments: [AudioSegment] = []
        segments.reserveCapacity(segmentRanges.count)

        let stopWatch = StopWatch().start()
        for (offset, range) in segmentRanges.enumerated() {
            let index = offset + 1
            let segmentDuration = range.end - range.start
            let startTime = formatTime(range.start)
            let endTime = formatTime(range.end)
            
            logger?.debug("Split segment: \(index) / \(segmentCount)")

            guard range.end > range.start, startTime != endTime else {
                logger?.warning("Skip zero-duration segment at index \(index) (\(startTime) -> \(endTime))")
                continue
            }
            guard segmentDuration >= configuration.minimumSegmentDurationSeconds else {
                logger?.warning(
                    "Skip short segment at index \(index) (\(startTime) -> \(endTime), duration=\(segmentDuration))"
                )
                continue
            }

            let outputFileURL = AudioSegment.segmentFileURL(from: segmentSourceURL, index: index)

            try createSegment(
                sourceAudioURL: monoAudioURL,
                startTime: startTime,
                endTime: endTime,
                segmentDuration: segmentDuration,
                paddingSeconds: configuration.segmentPaddingSeconds,
                outputFileURL: outputFileURL
            )

            segments.append(
                AudioSegment(
                    index: index,
                    startTime: startTime,
                    endTime: endTime
                )
            )
        }
        logger?.debug("Took \(stopWatch.formattedUnitsStyle())")

        return AudioSegmenterModel(
            sourceAudioDuration: .seconds(detectionOutput.durationSeconds),
            segments: segments
        )
    }

    private func removeExistingSegmentFiles(in outputDirectory: URL) throws {
        guard fileManager.fileExists(atPath: outputDirectory.path) else {
            return
        }

        for fileURL in try fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ) {
            if fileURL.lastPathComponent.contains("-segment-") {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func detectSilences(
        audioURL: URL,
        configuration: AudioSegmenterConfiguration
    ) throws -> (durationSeconds: Double, silences: [(start: Double, end: Double)]) {
        logger?.debug("Detecting silences")
        let stopWatch = StopWatch().start()
        let silenceFilter = "silencedetect=n=\(configuration.silenceThresholdDecibels)dB:d=\(configuration.minimumSilenceDurationSeconds)"
        let output = try runFFmpeg([
            "-hide_banner",
            "-i", audioURL.path,
            "-af", silenceFilter,
            "-f", "null",
            "-"
        ])
        
        logger?.debug("Took \(stopWatch.formattedUnitsStyle())")

        guard let duration = parseDuration(from: output) else {
            throw AudioSegmenterError.sourceDurationMissing
        }
        return (duration, parseSilenceRanges(from: output))
    }

    private func buildSegmentRanges(
        from silences: [(start: Double, end: Double)],
        duration: Double
    ) -> [(start: Double, end: Double)] {
        var ranges: [(start: Double, end: Double)] = []
        var cursor: Double = 0

        for silence in silences {
            if silence.start > cursor {
                ranges.append((start: cursor, end: silence.start))
            }
            cursor = max(cursor, silence.end)
        }

        if duration > cursor {
            ranges.append((start: cursor, end: duration))
        }
        return ranges
    }

    private func createSegment(
        sourceAudioURL: URL,
        startTime: String,
        endTime: String,
        segmentDuration: Double,
        paddingSeconds: Double,
        outputFileURL: URL
    ) throws {
        let paddingMilliseconds = Int((paddingSeconds * 1000).rounded())
        let paddedDuration = formatTime(segmentDuration + (paddingSeconds * 2))
        _ = try runFFmpeg([
            "-hide_banner",
            "-y",
            "-i", sourceAudioURL.path,
            "-ss", startTime,
            "-to", endTime,
            "-af", "adelay=\(paddingMilliseconds):all=1,apad=pad_dur=\(paddingSeconds)",
            "-t", paddedDuration,
            "-c:a", "pcm_s16le",
            outputFileURL.path
        ])
    }

    private func createMonoAudio(
        sourceAudioURL: URL,
        monoAudioURL: URL
    ) throws {
        logger?.debug("Create mono source file at \(monoAudioURL.lastPathComponent)")
        _ = try runFFmpeg([
            "-hide_banner",
            "-y",
            "-i", sourceAudioURL.path,
            "-vn",
            "-ac", "1",
            monoAudioURL.path,
        ])
    }

    private func parseDuration(from output: String) -> Double? {
        guard
            let regex = try? NSRegularExpression(pattern: #"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)"#),
            let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output)
            )
        else {
            return nil
        }

        func part(_ index: Int) -> Double {
            guard let range = Range(match.range(at: index), in: output) else { return 0 }
            return Double(output[range]) ?? 0
        }

        let hours = part(1)
        let minutes = part(2)
        let seconds = part(3)
        return (hours * 3600) + (minutes * 60) + seconds
    }

    private func parseSilenceRanges(from output: String) -> [(start: Double, end: Double)] {
        let lines = output.split(separator: "\n")
        var ranges: [(start: Double, end: Double)] = []
        var activeStart: Double?

        for line in lines {
            if let start = parseValue(after: "silence_start:", from: String(line)) {
                activeStart = start
            }
            if let end = parseValue(after: "silence_end:", from: String(line)) {
                if let activeStart {
                    ranges.append((start: activeStart, end: end))
                }
                activeStart = nil
            }
        }
        return ranges
    }

    private func parseValue(after prefix: String, from line: String) -> Double? {
        guard let range = line.range(of: prefix) else {
            return nil
        }

        let suffix = line[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
        var numberText = ""
        for character in suffix {
            if character.isNumber || character == "." {
                numberText.append(character)
            } else {
                break
            }
        }
        return Double(numberText)
    }

    private func formatTime(_ value: Double) -> String {
        String(format: "%.3f", value)
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
            throw AudioSegmenterError.ffmpegCommandFailed(stderr)
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

        throw AudioSegmenterError.ffmpegCommandFailed(
            "Unable to locate ffmpeg executable via common install paths or `which ffmpeg`.\n\(stderr)"
        )
    }
}
