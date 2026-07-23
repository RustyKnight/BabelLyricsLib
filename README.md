# BabelLyricsLib

Babel Lyrics is a working concept for taking a music audio file and building transparent, "karaoke" like, overlay video, which can be added to video editors.

The library makes use of AI driven workflows and is local first focused.

Because it uses AI, it's results should always be reviewed and not consider correct without review.

The library is deliberatly separated into individual phases or workflows.  This allows individual phases to be re-run independently.

- vocal/music separation (Demucs)
- silence-based audio segmentation (FFmpeg)
- segment transcription with word timing (Whisper)
- transparent lyrics video rendering (AVFoundation/CoreGraphics)

## AI

The library is built using AI (copilot) and makes use of AI libraries.  This is very much a learning process.

## Swift package integration

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/<owner>/BabelLyricsLib.git", branch: "main")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "BabelLyricsLib", package: "BabelLyricsLib")
        ]
    )
]
```

## External dependencies

`AudioSeparator`, `AudioSegmenter`, and `AudioTranscriber` shell out to external tools.

### macOS (Homebrew + pip) quick setup

```bash
# system tools
brew install python@3.11 ffmpeg libsndfile rust

# Python packages (choose your preferred Python environment)
python3 -m pip install --upgrade pip wheel setuptools
python3 -m pip install torch torchaudio
python3 -m pip install demucs openai-whisper soundfile
```

### Notes on transitive/runtime dependencies

- **Demucs** depends on Python ML stack (notably `torch` / `torchaudio`).
- **Whisper** uses FFmpeg at runtime and may require `rust` if `tiktoken` must build from source.
- **SoundFile / libsndfile** are sometimes required by audio backends used by Demucs/Whisper pipelines.
- Ensure these commands succeed in your shell:

```bash
python3 --version
python3 -m demucs.separate --help
whisper --help
ffmpeg -version
```

## Public API surface

### Audio separation

- `AudioSeparator`
  - `init(fileManager:demucsOverride:ffmpegOverride:logger:)`
  - `separateAudio(at:configuration:destinationDirectory:temporaryDirectory:onProgress:) -> AudioSeparatorModel`
  - `separateAudioProgressStream(at:configuration:destinationDirectory:temporaryDirectory:) -> AsyncThrowingStream<AudioSeparator.ProgressEvent, Error>`
- `AudioSeparator.DemucsModel` (`.htdemucs`, `.htdemucsFT`, `.htdemucs6s`, `.mdxExtra`, `.mdxExtraQ`)
- `AudioSeparator.DemucsDevice` (`.cpu`, `.cuda`, `.mps`)
- `AudioSeparator.DemucsConfiguration` (`model`, `device`, `segment`, `overlap`, `shifts`, `jobs`)
- `AudioSeparator.Files` (`.vocals`, `.music`, `.vocalsMono`)
- `AudioSeparator.Progress` (`fractionCompleted`, `completedPasses`, `totalPasses`, `currentPassFraction`, `estimatedTimeRemaining`, `message`)
- `AudioSeparator.ProgressEvent` (`.progress`, `.completed`)
- `AudioSeparatorModel` (`vocalsURL`, `musicURL`)
- `AudioSeparatorError`

### Audio segmentation

- `AudioSegmenter`
  - `init(fileManager:ffmpegOverride:logger:)`
  - `segmentAudio(at:outputDirectory:configuration:) -> AudioSegmenterModel`
- `AudioSegmenterConfiguration`
- `AudioSegmenterModel`
- `AudioSegment` (`index`, `startTime`, `endTime`)
  - `AudioSegment.segmentFileURL(from:index:) -> URL`
- `AudioSegmenterError`

### Audio transcription

- `AudioTranscriber`
  - `init(fileManager:whisperOverride:logger:)`
  - `transcribeAudio(from:audioSegmentSourceURL:temporaryDirectory:configuration:onProgress:) -> AudioTranscriberModel`
  - `transcribeAudioProgressStream(from:audioSegmentSourceURL:temporaryDirectory:configuration:) -> AsyncThrowingStream<AudioTranscriber.ProgressEvent, Error>`
- `AudioTranscriberConfiguration` (`model`, `language`, `task`, `beamSize`, `temperature`, `bestOf`, `conditionOnPreviousText`, `initialPrompt`, `threads`)
- `AudioTranscriberModel` (`plainLines`)
- `AudioTranscriber.Progress` (`fractionCompleted`, `completedSegments`, `totalSegments`, `currentSegmentIndex`, `currentSegmentFraction`, `estimatedTimeRemaining`, `message`)
- `AudioTranscriber.ProgressEvent` (`.progress`, `.completed`)
- `TranscribedLine` (`segmentIndex`, `startTime`, `endTime`, `text`, `words`)
- `TranscribedWord` (`startTime`, `endTime`, `text`)
- `AudioTranscriberError`

`TranscribedLine.startTime` and `TranscribedLine.endTime` are source-audio absolute times.
`TranscribedWord.startTime` and `TranscribedWord.endTime` are relative to the containing line's `startTime`.

### Video rendering

- `VideoRenderer`
  - `init(fileManager:logger:)`
  - `renderVideo(from:destinationDirectory:configuration:) -> URL`
- `VideoRendererConfiguration`
- `VideoRendererResolution`
- `VideoRendererError`
- `VideoRendererModel`

`VideoRenderer` supports overlapping lyric lines. Newer overlapping lines are rendered above existing visible lines, each line keeps its assigned vertical position until it leaves the screen, and newly arriving lines reuse the lowest available empty slot.

### Logging

- `LogDelegate`
- `LogMessage`
- `LogLevel`

## Usage examples

```swift
import Foundation
import BabelLyricsLib
```

### 1) Separate audio (vocals/music)

```swift
let separator = AudioSeparator()
let separated = try separator.separateAudio(
    at: URL(fileURLWithPath: "/path/to/song.mp3"),
    destinationDirectory: URL(fileURLWithPath: "/path/to/output", isDirectory: true),
    configuration: .init(model: .htdemucs)
)

print(separated.vocalsURL.path) // .../vocals.wav
print(separated.musicURL.path)  // .../music.wav
// Also generated in the same directory:
// .../vocals-mono.wav

let monoURL = AudioSeparator.Files.vocalsMono.url(
    in: URL(fileURLWithPath: "/path/to/output", isDirectory: true)
)
print(monoURL.lastPathComponent) // vocals-mono.wav
```

### 1a) Separate audio with closure-based progress callback

```swift
let separator = AudioSeparator()
let separated = try separator.separateAudio(
    at: URL(fileURLWithPath: "/path/to/song.mp3"),
    configuration: .init(model: .htdemucsFT, device: .mps)
) { progress in
    let percent = Int(progress.fractionCompleted * 100)
    print("Demucs progress: \(percent)% (\(progress.completedPasses)/\(progress.totalPasses) passes)")
    if let eta = progress.estimatedTimeRemaining {
        print("ETA: \(eta)")
    }
}
```

### 1b) Separate audio with async/await progress stream (SwiftUI)

```swift
import SwiftUI
import BabelLyricsLib

@MainActor
final class SeparationViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var status: String = "Idle"

    private let separator = AudioSeparator()

    func run(inputURL: URL, outputURL: URL) {
        Task {
            do {
                for try await event in separator.separateAudioProgressStream(
                    at: inputURL,
                    destinationDirectory: outputURL
                ) {
                    switch event {
                    case let .progress(update):
                        progress = update.fractionCompleted
                        status = update.message ?? "Separating..."
                    case .completed:
                        progress = 1
                        status = "Completed"
                    }
                }
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
```

### 1c) Separate audio with Combine progress publisher

```swift
import Foundation
import Combine
import BabelLyricsLib

final class SeparationService {
    private let separator = AudioSeparator()

    func separatePublisher(
        inputURL: URL,
        outputURL: URL
    ) -> AnyPublisher<AudioSeparator.ProgressEvent, Error> {
        let subject = PassthroughSubject<AudioSeparator.ProgressEvent, Error>()

        Task {
            do {
                for try await event in separator.separateAudioProgressStream(
                    at: inputURL,
                    destinationDirectory: outputURL
                ) {
                    subject.send(event)
                }
                subject.send(completion: .finished)
            } catch {
                subject.send(completion: .failure(error))
            }
        }

        return subject.eraseToAnyPublisher()
    }
}
```

### 2) Segment vocals/music by silence

```swift
let segmenter = AudioSegmenter()
let segmentsDirectory = URL(fileURLWithPath: "/path/to/work/segments", isDirectory: true)

let segmented = try segmenter.segmentAudio(
    at: separated.vocalsURL,
    outputDirectory: segmentsDirectory,
    configuration: .init(
        silenceThresholdDecibels: -35,
        minimumSilenceDurationSeconds: 0.35,
        minimumSegmentDurationSeconds: 0.026,
        segmentPaddingSeconds: 0.5
    )
)

print(segmented.segments.count)
```

### 3) Transcribe segments

```swift
let transcriber = AudioTranscriber()

// Must point to the segment directory + extension used by segment files.
// Generated segment names are: vocal-segment-0001.<ext>, ...
let audioSegmentSourceURL = segmentsDirectory.appendingPathComponent("source.wav")

let transcription = try transcriber.transcribeAudio(
    from: segmented,
    audioSegmentSourceURL: audioSegmentSourceURL,
    configuration: .init(model: .large, language: .en, beamSize: 5)
)

for line in transcription.lines {
    print("[segment \(line.segmentIndex)] \(line.text)")
}
```

### 3a) Transcribe with closure-based progress callback

```swift
let transcription = try transcriber.transcribeAudio(
    from: segmented,
    audioSegmentSourceURL: audioSegmentSourceURL
) { progress in
    let percent = Int(progress.fractionCompleted * 100)
    print("Whisper progress: \(percent)%")
    if let eta = progress.estimatedTimeRemaining {
        print("ETA: \(eta)")
    }
}
```

### 3b) Transcribe with async/await progress stream

```swift
import SwiftUI
import BabelLyricsLib

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var status: String = "Idle"

    private let transcriber = AudioTranscriber()

    func run(segmentResult: AudioSegmenterModel, sourceURL: URL) {
        Task {
            do {
                for try await event in transcriber.transcribeAudioProgressStream(
                    from: segmentResult,
                    audioSegmentSourceURL: sourceURL
                ) {
                    switch event {
                    case let .progress(update):
                        progress = update.fractionCompleted
                        status = update.message ?? "Transcribing..."
                    case .completed:
                        progress = 1
                        status = "Completed"
                    }
                }
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
```

### 4) Render transparent lyrics video

```swift
let renderer = VideoRenderer()
let videoOutputDirectory = URL(fileURLWithPath: "/path/to/output", isDirectory: true)

let videoURL = try renderer.renderVideo(
    from: transcription,
    destinationDirectory: videoOutputDirectory,
    configuration: .init(
        resolution: .hd1080,
        framesPerSecond: 25,
        preRollPaddingSeconds: 1,
        postRollPaddingSeconds: 1,
        horizontalPadding: 128,
        bottomPadding: 96
    )
)

print(videoURL.path) // .../Video-Lyrics.mov
```

## End-to-end flow

1. `AudioSeparator.separateAudio(...)`
2. `AudioSegmenter.segmentAudio(...)`
3. `AudioTranscriber.transcribeAudio(...)`
4. `VideoRenderer.renderVideo(...)`
