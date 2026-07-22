import Foundation
import Testing
@testable import BabelLyricsLib

@Suite("Audio segmenter workflow")
struct AudioSegmenterTests {
    @Test("Segments by silence, removes existing segment files, and records metadata")
    func segmentsBySilence() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioSegmenterTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("song.mp3")
        try Data("audio".utf8).write(to: audioURL)

        let staleSegment = outputDirectory.appendingPathComponent("vocal-segment-0001.mp3")
        try Data("stale".utf8).write(to: staleSegment)
        let unrelatedFile = outputDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelatedFile)

        var detectionArguments: [String] = []
        var segmentOutputFiles: [String] = []
        var segmentArguments: [[String]] = []

        let workflow = AudioSegmenter(
            ffmpegOverride: { arguments in
                if arguments.contains(where: { $0.contains("silencedetect=") }) {
                    detectionArguments = arguments
                    return """
                    Duration: 00:00:05.000, start: 0.000000, bitrate: 192 kb/s
                    [silencedetect @ 0x0] silence_start: 1.500
                    [silencedetect @ 0x0] silence_end: 2.000 | silence_duration: 0.500
                    [silencedetect @ 0x0] silence_start: 3.000
                    [silencedetect @ 0x0] silence_end: 3.400 | silence_duration: 0.400
                    """
                }

                let outputPath = arguments.last!
                segmentArguments.append(arguments)
                segmentOutputFiles.append(outputPath)
                try Data("segment".utf8).write(to: URL(fileURLWithPath: outputPath))
                return ""
            }
        )

        let result = try workflow.segmentAudio(at: audioURL, outputDirectory: outputDirectory)
        #expect(detectionArguments.contains("silencedetect=n=-35.0dB:d=0.35"))
        #expect(detectionArguments.contains("silencedetect=n=-35.0dB:d=0.35"))
        #expect(detectionArguments.contains(audioURL.path))
        #expect(!fileManager.fileExists(atPath: staleSegment.path))
        #expect(fileManager.fileExists(atPath: unrelatedFile.path))

        #expect(result.sourceAudioDuration == .seconds(5))
        #expect(result.segments.count == 3)
        #expect(result.segments[0].index == 1)
        #expect(result.segments[0].startTime == "0.000")
        #expect(result.segments[0].endTime == "1.500")
        #expect(result.segments[1].startTime == "2.000")
        #expect(result.segments[1].endTime == "3.000")
        #expect(result.segments[2].startTime == "3.400")
        #expect(result.segments[2].endTime == "5.000")
        #expect(segmentOutputFiles.count == 3)
        #expect(segmentArguments.first?.contains("-af") == true)
        #expect(segmentArguments.first?.contains(where: { $0.contains("adelay=500") }) == true)
        #expect(segmentArguments.first?.contains(where: { $0.contains("apad=pad_dur=0.5") }) == true)

        for segment in result.segments {
            let segmentURL = AudioSegment.segmentFileURL(
                from: audioURL,
                index: segment.index
            )
            #expect(fileManager.fileExists(atPath: segmentURL.path))
        }
    }

    @Test("Supports custom silence config, creates missing output directory, and remains Codable")
    func supportsConfigAndCodable() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioSegmenterTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("new-output", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("voice.wav")
        try Data("audio".utf8).write(to: audioURL)

        var detectionArguments: [String] = []
        let workflow = AudioSegmenter(
            ffmpegOverride: { arguments in
                if arguments.contains(where: { $0.contains("silencedetect=") }) {
                    detectionArguments = arguments
                    return "Duration: 00:00:02.250, start: 0.000000, bitrate: 192 kb/s"
                }

                try Data("segment".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        let result = try workflow.segmentAudio(
            at: audioURL,
            outputDirectory: outputDirectory,
            configuration: AudioSegmenterConfiguration(
                silenceThresholdDecibels: -20,
                minimumSilenceDurationSeconds: 0.5,
                segmentPaddingSeconds: 1.0
            )
        )

        #expect(fileManager.fileExists(atPath: outputDirectory.path))
        #expect(detectionArguments.contains("silencedetect=n=-20.0dB:d=0.5"))
        #expect(detectionArguments.contains(audioURL.path))
        #expect(result.sourceAudioDuration == .seconds(2.25))
        #expect(result.segments.count == 1)
        #expect(result.segments[0].startTime == "0.000")
        #expect(result.segments[0].endTime == "2.250")

        let encoded = try JSONEncoder().encode(result)
        let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect((encodedObject?["sourceAudioDuration"] as? Double) == 2.25)
        let decoded = try JSONDecoder().decode(AudioSegmenterModel.self, from: encoded)
        #expect(decoded.sourceAudioDuration == result.sourceAudioDuration)
        #expect(decoded.segments.count == result.segments.count)
        #expect(decoded.segments[0].index == result.segments[0].index)
    }

    @Test("Skips trailing zero-duration segments at audio end")
    func skipsTrailingZeroDurationSegment() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioSegmenterTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("episode.mp3")
        try Data("audio".utf8).write(to: audioURL)
        var segmentCommandCount = 0
        let workflow = AudioSegmenter(
            ffmpegOverride: { arguments in
                if arguments.contains(where: { $0.contains("silencedetect=") }) {
                    return """
                    Duration: 00:05:16.9704, start: 0.000000, bitrate: 192 kb/s
                    [silencedetect @ 0x0] silence_start: 0
                    [silencedetect @ 0x0] silence_end: 316.970 | silence_duration: 316.970
                    """
                }

                segmentCommandCount += 1
                try Data("segment".utf8).write(to: URL(fileURLWithPath: arguments.last!))
                return ""
            }
        )

        let result = try workflow.segmentAudio(at: audioURL, outputDirectory: outputDirectory)

        #expect(result.sourceAudioDuration == .seconds(316.9704))
        #expect(result.segments.isEmpty)
        #expect(segmentCommandCount == 0)
    }

    @Test("Skips tiny segments that are below minimum segment duration")
    func skipsTinySegmentsBelowMinimumDuration() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioSegmenterTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("episode.mp3")
        try Data("audio".utf8).write(to: audioURL)
        var segmentCommandCount = 0
        let workflow = AudioSegmenter(
            ffmpegOverride: { arguments in
                if arguments.contains(where: { $0.contains("silencedetect=") }) {
                    return """
                    Duration: 00:03:49.015, start: 0.000000, bitrate: 192 kb/s
                    [silencedetect @ 0x0] silence_start: 0
                    [silencedetect @ 0x0] silence_end: 229.014 | silence_duration: 229.014
                    [silencedetect @ 0x0] silence_start: 229.015
                    [silencedetect @ 0x0] silence_end: 229.015 | silence_duration: 0.000
                    """
                }

                segmentCommandCount += 1
                return ""
            }
        )

        let result = try workflow.segmentAudio(at: audioURL, outputDirectory: outputDirectory)
        #expect(result.segments.isEmpty)
        #expect(segmentCommandCount == 0)
    }

    @Test("Generates segment paths from source URL and index")
    func generatesSegmentPaths() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioSegmenterTests-\(UUID().uuidString)", isDirectory: true)
        let directorySource = workspace.appendingPathComponent("segments", isDirectory: true)
        let fileSource = workspace.appendingPathComponent("source-audio.mp3")
        try fileManager.createDirectory(at: directorySource, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: fileSource)
        defer { try? fileManager.removeItem(at: workspace) }

        let directoryResult = AudioSegment.segmentFileURL(from: directorySource, index: 3)
        let fileResult = AudioSegment.segmentFileURL(from: fileSource, index: 12)

        #expect(directoryResult.path == "\(directorySource.path)/vocal-segment-0003.wav")
        #expect(fileResult.path == "\(workspace.path)/vocal-segment-0012.mp3")
    }
}
