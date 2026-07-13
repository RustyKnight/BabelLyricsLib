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
  - `init(fileManager:demucsOverride:logger:)`
  - `separateAudio(at:configuration:temporaryDirectory:) -> AudioSeparatorModel`
- `AudioSeparator.DemucsModel` (`.htdemucs`, `.htdemucsFT`, `.htdemucs6s`, `.mdxExtra`, `.mdxExtraQ`)
- `AudioSeparator.DemucsConfiguration` (`model`, `segment`, `overlap`, `shifts`, `jobs`)
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
  - `transcribeAudio(from:audioSegmentSourceURL:temporaryDirectory:configuration:) -> AudioTranscriberModel`
- `AudioTranscriberConfiguration` (`model`, `language`, `temperature`, `beamSize`, `threads`)
- `AudioTranscriberModel` (`plainLines`)
- `TranscribedLine` (`segmentIndex`, `startTime`, `endTime`, `text`, `words`)
- `TranscribedWord` (`startTime`, `endTime`, `text`)
- `AudioTranscriberError`

### Video rendering

- `VideoRenderer`
  - `init(fileManager:logger:)`
  - `renderVideo(from:destinationDirectory:configuration:) -> URL`
- `VideoRendererConfiguration`
- `VideoRendererResolution`
- `VideoRendererError`
- `VideoRendererModel`

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
    configuration: .init(model: .htdemucs)
)

print(separated.vocalsURL.path) // .../vocals.wav
print(separated.musicURL.path)  // .../music.wav
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
        minimumSegmentDurationSeconds: 0.026
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
    configuration: .init(model: "large", language: "en", beamSize: 5)
)

for line in transcription.lines {
    print("[segment \(line.segmentIndex)] \(line.text)")
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

print(videoURL.path) // .../Lyrics.mov
```

## End-to-end flow

1. `AudioSeparator.separateAudio(...)`
2. `AudioSegmenter.segmentAudio(...)`
3. `AudioTranscriber.transcribeAudio(...)`
4. `VideoRenderer.renderVideo(...)`
