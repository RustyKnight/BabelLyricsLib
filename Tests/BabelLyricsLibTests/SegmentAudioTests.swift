import Foundation
import Testing
@testable import BabelLyricsLib

@Suite("Segment audio workflow")
struct SegmentAudioTests {
    @Test("Segments by silence, removes existing segment files, and records metadata")
    func segmentsBySilence() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("SegmentAudioTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("song.mp3")
        try Data("audio".utf8).write(to: audioURL)

        let staleSegment = outputDirectory.appendingPathComponent("song-segment-0001.mp3")
        try Data("stale".utf8).write(to: staleSegment)
        let unrelatedFile = outputDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelatedFile)

        var detectionArguments: [String] = []
        var segmentOutputFiles: [String] = []

        let workflow = SegmentAudio(
            ffmpegOverride: { arguments in
                if arguments.contains("-af") {
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
                segmentOutputFiles.append(outputPath)
                try Data("segment".utf8).write(to: URL(fileURLWithPath: outputPath))
                return ""
            }
        )

        let result = try workflow.segmentAudio(at: audioURL, outputDirectory: outputDirectory)

        #expect(detectionArguments.contains("silencedetect=n=-35.0dB:d=0.35"))
        #expect(String(decoding: try Data(contentsOf: staleSegment), as: UTF8.self) == "segment")
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

        for segment in result.segments {
            #expect(fileManager.fileExists(atPath: segment.filePath))
        }
    }

    @Test("Supports custom silence config, creates missing output directory, and remains Codable")
    func supportsConfigAndCodable() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("SegmentAudioTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("new-output", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("voice.wav")
        try Data("audio".utf8).write(to: audioURL)

        var detectionArguments: [String] = []
        let workflow = SegmentAudio(
            ffmpegOverride: { arguments in
                if arguments.contains("-af") {
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
            configuration: SegmentAudioConfiguration(
                silenceThresholdDecibels: -20,
                minimumSilenceDurationSeconds: 0.5
            )
        )

        #expect(fileManager.fileExists(atPath: outputDirectory.path))
        #expect(detectionArguments.contains("silencedetect=n=-20.0dB:d=0.5"))
        #expect(result.sourceAudioDuration == .seconds(2.25))
        #expect(result.segments.count == 1)
        #expect(result.segments[0].startTime == "0.000")
        #expect(result.segments[0].endTime == "2.250")

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SegmentAudioResult.self, from: encoded)
        #expect(decoded.sourceAudioDuration == result.sourceAudioDuration)
        #expect(decoded.segments.count == result.segments.count)
        #expect(decoded.segments[0].filePath == result.segments[0].filePath)
    }

    @Test("Skips trailing zero-duration segments at audio end")
    func skipsTrailingZeroDurationSegment() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("SegmentAudioTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let audioURL = workspace.appendingPathComponent("episode.mp3")
        try Data("audio".utf8).write(to: audioURL)

        var segmentCommandCount = 0
        let workflow = SegmentAudio(
            ffmpegOverride: { arguments in
                if arguments.contains("-af") {
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
}
