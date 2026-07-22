import Foundation
import Testing
@testable import BabelLyricsLib

@Suite("Video renderer")
struct VideoRendererTests {
    @Test("Renders lyrics video using AVFoundation/CoreGraphics request")
    func rendersLyricsVideo() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("VideoRendererTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let transcription = AudioTranscriberModel(
            sourceAudioDuration: .seconds(8),
            lines: [
                TranscribedLine(
                    segmentIndex: 1,
                    startTime: .seconds(1.0),
                    endTime: .seconds(3.5),
                    text: "hello world",
                    words: [
                        TranscribedWord(startTime: .seconds(0.0), endTime: .seconds(0.8), text: "hello"),
                        TranscribedWord(startTime: .seconds(0.8), endTime: .seconds(2.5), text: "world"),
                    ]
                ),
                TranscribedLine(
                    segmentIndex: 2,
                    startTime: .seconds(5.0),
                    endTime: .seconds(7.0),
                    text: "goodbye",
                    words: [
                        TranscribedWord(startTime: .seconds(0.0), endTime: .seconds(2.0), text: "goodbye"),
                    ]
                ),
            ]
        )

        var capturedRequest: VideoRenderRequest?

        let renderer = VideoRenderer(renderOverride: { request in
            capturedRequest = request
            try Data("video".utf8).write(to: request.videoURL)
        })

        let videoURL = try renderer.renderVideo(from: transcription, destinationDirectory: destinationDirectory)
        let request = try #require(capturedRequest)

        #expect(videoURL.lastPathComponent == "Video-Lyrics.mov")
        #expect(fileManager.fileExists(atPath: videoURL.path))
        #expect(request.width == 1920)
        #expect(request.height == 1080)
        #expect(request.framesPerSecond == 25)
        #expect(request.durationSeconds == 8)
        #expect(request.displayLines.count == 2)

        let firstLine = try #require(request.displayLines.first)
        #expect(firstLine.displayStartSeconds == 0)
        #expect(firstLine.activeStartSeconds == 1)
        #expect(firstLine.activeEndSeconds == 3.5)
        #expect(firstLine.displayEndSeconds == 4.5)
        #expect(firstLine.stackLevel == 0)
        #expect(firstLine.words.count == 2)
        #expect(firstLine.words[0].startSeconds == 1.0)
        #expect(firstLine.words[0].endSeconds == 1.8)
        #expect(firstLine.words[1].startSeconds == 1.8)
        #expect(firstLine.words[1].endSeconds == 3.5)

        let secondLine = try #require(request.displayLines.last)
        #expect(secondLine.displayStartSeconds == 4)
        #expect(secondLine.displayEndSeconds == 8)
        #expect(secondLine.stackLevel == 1)
    }

    @Test("Overlapping lines are stacked above existing lines")
    func stacksOverlappingLines() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("VideoRendererTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let transcription = AudioTranscriberModel(
            sourceAudioDuration: .seconds(10),
            lines: [
                TranscribedLine(
                    segmentIndex: 1,
                    startTime: .seconds(1),
                    endTime: .seconds(5),
                    text: "line one",
                    words: [TranscribedWord(startTime: .seconds(0), endTime: .seconds(4), text: "line")]
                ),
                TranscribedLine(
                    segmentIndex: 2,
                    startTime: .seconds(3),
                    endTime: .seconds(6),
                    text: "line two",
                    words: [TranscribedWord(startTime: .seconds(0), endTime: .seconds(3), text: "line")]
                ),
                TranscribedLine(
                    segmentIndex: 3,
                    startTime: .seconds(6),
                    endTime: .seconds(8),
                    text: "line three",
                    words: [TranscribedWord(startTime: .seconds(0), endTime: .seconds(2), text: "line")]
                ),
            ]
        )

        var capturedRequest: VideoRenderRequest?
        let renderer = VideoRenderer(renderOverride: { request in
            capturedRequest = request
            try Data("video".utf8).write(to: request.videoURL)
        })

        _ = try renderer.renderVideo(from: transcription, destinationDirectory: destinationDirectory)
        let request = try #require(capturedRequest)
        #expect(request.displayLines.count == 3)

        let firstLine = request.displayLines[0]
        let secondLine = request.displayLines[1]
        let thirdLine = request.displayLines[2]

        #expect(firstLine.stackLevel == 0)
        #expect(secondLine.stackLevel == 1)
        #expect(thirdLine.stackLevel == 2)
    }

    @Test("New lines are added on top and remaining lines collapse down when lower lines end")
    func collapsesStackWhenLowerLineEnds() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("VideoRendererTests-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let transcription = AudioTranscriberModel(
            sourceAudioDuration: .seconds(14),
            lines: [
                TranscribedLine(
                    segmentIndex: 1,
                    startTime: .seconds(1),
                    endTime: .seconds(5),
                    text: "line one",
                    words: [TranscribedWord(startTime: .seconds(0), endTime: .seconds(4), text: "line")]
                ),
                TranscribedLine(
                    segmentIndex: 2,
                    startTime: .seconds(2),
                    endTime: .seconds(10),
                    text: "line two",
                    words: [TranscribedWord(startTime: .seconds(0), endTime: .seconds(8), text: "line")]
                ),
                TranscribedLine(
                    segmentIndex: 3,
                    startTime: .seconds(4),
                    endTime: .seconds(8),
                    text: "line three",
                    words: [TranscribedWord(startTime: .seconds(0), endTime: .seconds(4), text: "line")]
                ),
            ]
        )

        var capturedRequest: VideoRenderRequest?
        let renderer = VideoRenderer(renderOverride: { request in
            capturedRequest = request
            try Data("video".utf8).write(to: request.videoURL)
        })

        _ = try renderer.renderVideo(from: transcription, destinationDirectory: destinationDirectory)
        let request = try #require(capturedRequest)
        #expect(request.displayLines.count == 3)

        let firstLine = request.displayLines[0]
        let secondLine = request.displayLines[1]
        let thirdLine = request.displayLines[2]

        #expect(firstLine.stackLevel == 0)
        #expect(secondLine.stackLevel == 1)
        #expect(thirdLine.stackLevel == 2)
        #expect(secondLine.displayEndSeconds > thirdLine.displayStartSeconds)

        let beforeFirstLineEnds = renderer.visibleLines(at: 5.5, from: request.displayLines)
        #expect(beforeFirstLineEnds.count == 3)
        #expect(beforeFirstLineEnds[0].text == "line one")
        #expect(beforeFirstLineEnds[1].text == "line two")
        #expect(beforeFirstLineEnds[2].text == "line three")

        let afterFirstLineEnds = renderer.visibleLines(at: 6.3, from: request.displayLines)
        #expect(afterFirstLineEnds.count == 2)
        #expect(afterFirstLineEnds[0].text == "line two")
        #expect(afterFirstLineEnds[1].text == "line three")
    }

    @Test("Supports custom resolution based on height and ratio")
    func supportsCustomResolutionMath() {
        let configuration = VideoRendererConfiguration(
            resolution: .heightRatio(height: 720, aspectRatio: 4.0 / 3.0),
            framesPerSecond: 30
        )

        #expect(configuration.renderSize.width == 960)
        #expect(configuration.renderSize.height == 720)
        #expect(configuration.framesPerSecond == 30)
    }

    @Test("Rejects non-positive frame rate")
    func rejectsInvalidFrameRate() throws {
        let renderer = VideoRenderer()
        let transcription = AudioTranscriberModel(sourceAudioDuration: .seconds(1), lines: [])
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoRendererTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destinationDirectory) }

        do {
            _ = try renderer.renderVideo(
                from: transcription,
                destinationDirectory: destinationDirectory,
                configuration: .init(framesPerSecond: 0)
            )
            Issue.record("Expected invalid configuration error.")
        } catch let error as VideoRendererError {
            guard case let .invalidConfiguration(message) = error else {
                Issue.record("Expected invalidConfiguration but received \(error).")
                return
            }
            #expect(message == "framesPerSecond must be greater than zero.")
        } catch {
            Issue.record("Expected VideoRendererError but received \(error).")
        }
    }
}
