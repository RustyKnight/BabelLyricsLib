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
                        TranscribedWord(startTime: .seconds(1.0), endTime: .seconds(1.8), text: "hello"),
                        TranscribedWord(startTime: .seconds(1.8), endTime: .seconds(3.5), text: "world"),
                    ]
                ),
                TranscribedLine(
                    segmentIndex: 2,
                    startTime: .seconds(5.0),
                    endTime: .seconds(7.0),
                    text: "goodbye",
                    words: [
                        TranscribedWord(startTime: .seconds(5.0), endTime: .seconds(7.0), text: "goodbye"),
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

        #expect(videoURL.lastPathComponent == "Lyrics.mov")
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
        #expect(firstLine.words.count == 2)

        let secondLine = try #require(request.displayLines.last)
        #expect(secondLine.displayStartSeconds == 4)
        #expect(secondLine.displayEndSeconds == 8)
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
