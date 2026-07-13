import Foundation
import Testing
@testable import BabelLyricsLib

@Suite("Audio transcriber workflow")
struct AudioTranscriberTests {
    @Test("Transcribes segments, maps times to source context, and cleans auto temp directory")
    func transcribesAndMapsTimes() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioTranscriberTests-\(UUID().uuidString)", isDirectory: true)
        let segmentsDirectory = workspace.appendingPathComponent("segments", isDirectory: true)
        try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let segmentSourceURL = segmentsDirectory.appendingPathComponent("song.mp3")
        let segmentOneURL = AudioSegment.segmentFileURL(from: segmentSourceURL, index: 1)
        let segmentTwoURL = AudioSegment.segmentFileURL(from: segmentSourceURL, index: 2)
        try Data("one".utf8).write(to: segmentOneURL)
        try Data("two".utf8).write(to: segmentTwoURL)

        let segmentResult = AudioSegmenterModel(
            sourceAudioDuration: .seconds(12),
            segments: [
                AudioSegment(
                    index: 1,
                    startTime: "2.000",
                    endTime: "5.000"
                ),
                AudioSegment(
                    index: 2,
                    startTime: "9.500",
                    endTime: "12.000"
                ),
            ]
        )

        var capturedArguments: [String] = []
        var capturedOutputDirectory: URL?

        let workflow = AudioTranscriber(whisperOverride: { arguments in
            capturedArguments = arguments

            let outputIndex = arguments.firstIndex(of: "--output_dir")!
            let outputPath = arguments[outputIndex + 1]
            capturedOutputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)

            let inputURL = URL(fileURLWithPath: arguments.last!)
            let transcriptURL = URL(fileURLWithPath: outputPath)
                .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + ".json")

            let transcript: String
            switch inputURL.lastPathComponent {
            case "vocal-segment-0001.mp3":
                transcript = """
                {
                  "segments": [
                    {
                      "start": 0.100,
                      "end": 1.250,
                      "text": " hello world ",
                      "words": [
                        { "start": 0.100, "end": 0.500, "word": " hello" },
                        { "start": 0.500, "end": 1.250, "word": " world" }
                      ]
                    }
                  ]
                }
                """
            default:
                transcript = """
                {
                  "segments": [
                    {
                      "start": 0.000,
                      "end": 0.700,
                      "text": " goodbye",
                      "words": [
                        { "start": 0.000, "end": 0.700, "word": " goodbye" }
                      ]
                    }
                  ]
                }
                """
            }

            try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        })

        let result = try workflow.transcribeAudio(from: segmentResult, audioSegmentSourceURL: segmentSourceURL)

        #expect(capturedArguments.contains("--model"))
        #expect(capturedArguments.contains("large"))
        #expect(capturedArguments.contains("--language"))
        #expect(capturedArguments.contains("en"))
        #expect(capturedArguments.contains("--temperature"))
        #expect(capturedArguments.contains("0.0"))
        #expect(result.sourceAudioDuration == .seconds(12))
        #expect(result.lines.count == 2)
        #expect(result.lines[0].text == "hello world")
        #expect(result.lines[0].segmentIndex == 1)
        #expect(result.lines[0].startTime == .seconds(2.1))
        #expect(result.lines[0].endTime == .seconds(3.25))
        #expect(result.lines[0].words.count == 2)
        #expect(result.lines[0].words[0].text == "hello")
        #expect(result.lines[0].words[0].startTime == .seconds(2.1))
        #expect(result.lines[0].words[1].endTime == .seconds(3.25))
        #expect(result.lines[1].text == "goodbye")
        #expect(result.lines[1].segmentIndex == 2)
        #expect(result.lines[1].startTime == .seconds(9.5))
        #expect(result.lines[1].endTime == .seconds(10.2))

        let autoTempRemoved = capturedOutputDirectory.map { !fileManager.fileExists(atPath: $0.path) } ?? false
        #expect(autoTempRemoved)

        let encoded = try JSONEncoder().encode(result)
        let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect((encodedObject?["sourceAudioDuration"] as? Double) == 12)
        let lines = encodedObject?["lines"] as? [[String: Any]]
        let firstLine = lines?.first
        #expect((firstLine?["startTime"] as? Double) == 2.1)
        #expect((firstLine?["endTime"] as? Double) == 3.25)
        let decoded = try JSONDecoder().decode(AudioTranscriberModel.self, from: encoded)
        #expect(decoded.lines.count == result.lines.count)
        #expect(decoded.lines[0].words[0].text == result.lines[0].words[0].text)
    }

    @Test("Preserves a provided temp directory and uses custom whisper config")
    func preservesProvidedTempDirectoryAndConfig() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioTranscriberTests-\(UUID().uuidString)", isDirectory: true)
        let providedTempDirectory = workspace.appendingPathComponent("whisper-temp", isDirectory: true)
        let segmentsDirectory = workspace.appendingPathComponent("segments", isDirectory: true)
        try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: providedTempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let segmentSourceURL = segmentsDirectory.appendingPathComponent("line.mp3")
        let segmentURL = AudioSegment.segmentFileURL(from: segmentSourceURL, index: 1)
        try Data("one".utf8).write(to: segmentURL)

        let segmentResult = AudioSegmenterModel(
            sourceAudioDuration: .seconds(3),
            segments: [
                AudioSegment(
                    index: 1,
                    startTime: "0.500",
                    endTime: "3.000"
                ),
            ]
        )

        var capturedArguments: [String] = []
        let workflow = AudioTranscriber(
            whisperOverride: { arguments in
                capturedArguments = arguments
                let outputIndex = arguments.firstIndex(of: "--output_dir")!
                let outputPath = arguments[outputIndex + 1]
                let transcriptURL = URL(fileURLWithPath: outputPath)
                    .appendingPathComponent("line.json")
                let transcript = """
                {
                  "segments": [
                    {
                      "start": 0.000,
                      "end": 0.250,
                      "text": " hey",
                      "words": [
                        { "start": 0.000, "end": 0.250, "word": " hey" }
                      ]
                    }
                  ]
                }
                """
                try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
            }
        )

        let result = try workflow.transcribeAudio(
            from: segmentResult,
            audioSegmentSourceURL: segmentSourceURL,
            temporaryDirectory: providedTempDirectory,
            configuration: AudioTranscriberConfiguration(model: "medium", language: "fr", temperature: 0.2)
        )

        #expect(capturedArguments.contains("medium"))
        #expect(capturedArguments.contains("fr"))
        #expect(capturedArguments.contains("0.2"))
        #expect(fileManager.fileExists(atPath: providedTempDirectory.path))
        #expect(result.lines.count == 1)
        #expect(result.lines[0].segmentIndex == 1)
        #expect(result.lines[0].startTime == .seconds(0.5))
        #expect(result.lines[0].endTime == .seconds(0.75))
        #expect(result.lines[0].text == "hey")
    }

    @Test("Uses discovered JSON when Whisper output file name differs")
    func usesDiscoveredJSONWhenFilenameDiffers() throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("AudioTranscriberTests-\(UUID().uuidString)", isDirectory: true)
        let providedTempDirectory = workspace.appendingPathComponent("whisper-temp", isDirectory: true)
        let segmentsDirectory = workspace.appendingPathComponent("segments", isDirectory: true)
        try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: providedTempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let segmentSourceURL = segmentsDirectory.appendingPathComponent("line.mp3")
        let segmentURL = AudioSegment.segmentFileURL(from: segmentSourceURL, index: 1)
        try Data("one".utf8).write(to: segmentURL)

        let segmentResult = AudioSegmenterModel(
            sourceAudioDuration: .seconds(2),
            segments: [
                AudioSegment(index: 1, startTime: "0.000", endTime: "2.000"),
            ]
        )

        let workflow = AudioTranscriber(
            whisperOverride: { arguments in
                let outputIndex = arguments.firstIndex(of: "--output_dir")!
                let outputPath = arguments[outputIndex + 1]
                let transcriptURL = URL(fileURLWithPath: outputPath)
                    .appendingPathComponent("unexpected-name.json")
                let transcript = """
                {
                  "segments": [
                    {
                      "start": 0.000,
                      "end": 0.500,
                      "text": " test",
                      "words": [
                        { "start": 0.000, "end": 0.500, "word": " test" }
                      ]
                    }
                  ]
                }
                """
                try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
            }
        )

        let result = try workflow.transcribeAudio(
            from: segmentResult,
            audioSegmentSourceURL: segmentSourceURL,
            temporaryDirectory: providedTempDirectory
        )

        #expect(result.lines.count == 1)
        #expect(result.lines[0].segmentIndex == 1)
        #expect(result.lines[0].text == "test")
    }
}
