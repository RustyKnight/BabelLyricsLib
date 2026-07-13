@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import CoreVideo
import Foundation

/// Renders a transparent lyrics video from timed transcription output.
public struct VideoRenderer {
    private let fileManager: FileManager
    private let renderOverride: ((VideoRenderRequest) throws -> Void)?
    private let logger: LogService?

    /// Creates a lyrics video renderer.
    ///
    /// - Parameters:
    ///   - fileManager: File manager used for filesystem operations.
    ///   - logger: Optional log delegate for workflow lifecycle and error messages.
    public init(
        fileManager: FileManager = .default,
        logger: (any LogDelegate)? = nil
    ) {
        self.fileManager = fileManager
        self.renderOverride = nil
        if let logger {
            self.logger = .init(delegate: logger)
        } else {
            self.logger = nil
        }
    }

    init(
        fileManager: FileManager = .default,
        renderOverride: ((VideoRenderRequest) throws -> Void)? = nil,
        logger: (any LogDelegate)? = nil
    ) {
        self.fileManager = fileManager
        self.renderOverride = renderOverride
        if let logger {
            self.logger = .init(delegate: logger)
        } else {
            self.logger = nil
        }
    }

    /// Renders a transparent lyrics video.
    ///
    /// - Parameters:
    ///   - transcription: Transcribed lyrics with source-aligned timings.
    ///   - destinationDirectory: Destination directory for the final video.
    ///   - configuration: Render configuration. Defaults to 1080p at 25fps.
    /// - Returns: The generated video URL.
    /// - Throws: ``VideoRendererError`` when rendering fails.
    public func renderVideo(
        from transcription: AudioTranscriberModel,
        destinationDirectory: URL,
        configuration: VideoRendererConfiguration = .init()
    ) throws -> URL {
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw VideoRendererError.unableToCreateDestinationDirectory(destinationDirectory)
        }

        guard configuration.framesPerSecond > 0 else {
            throw VideoRendererError.invalidConfiguration("framesPerSecond must be greater than zero.")
        }

        let videoURL = destinationDirectory.appendingPathComponent("Lyrics.\(configuration.outputFileExtension)")
        if fileManager.fileExists(atPath: videoURL.path) {
            try fileManager.removeItem(at: videoURL)
        }

        let duration = max(sourceDurationSeconds(for: transcription), 1.0 / configuration.framesPerSecond)
        let sortedLines = transcription.lines.sorted { $0.startTime < $1.startTime }
        let displayLines = buildDisplayLines(
            from: sortedLines,
            sourceDurationSeconds: duration,
            configuration: configuration
        )

        let request = VideoRenderRequest(
            transcription: transcription,
            displayLines: displayLines,
            videoURL: videoURL,
            width: configuration.resolution.width,
            height: configuration.resolution.height,
            framesPerSecond: configuration.framesPerSecond,
            durationSeconds: duration
        )

        let stopWatch = StopWatch().start()
        logger?.info("Start rendering lyrics video")
        if let renderOverride {
            try renderOverride(request)
        } else {
            try render(request: request, configuration: configuration)
        }
        logger?.info("Completed rendering lyrics video in \(stopWatch.formattedUnitsStyle())")

        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw VideoRendererError.missingVideoOutput(videoURL)
        }
        return videoURL
    }

    private func render(
        request: VideoRenderRequest,
        configuration: VideoRendererConfiguration
    ) throws {
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: request.width,
            AVVideoHeightKey: request.height,
        ]

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(url: request.videoURL, fileType: .mov)
        } catch {
            throw VideoRendererError.videoWriterSetupFailed(error.localizedDescription)
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let adaptorAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: request.width,
            kCVPixelBufferHeightKey as String: request.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: adaptorAttributes
        )

        guard writer.canAdd(input) else {
            throw VideoRendererError.videoWriterSetupFailed("Cannot add video writer input.")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw VideoRendererError.videoWriterSetupFailed(writer.error?.localizedDescription ?? "Unknown startWriting error.")
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(ceil(request.durationSeconds * request.framesPerSecond)))
        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }

            guard let pixelBuffer = try makePixelBuffer(
                pool: adaptor.pixelBufferPool,
                request: request,
                frameIndex: frameIndex,
                configuration: configuration
            ) else {
                throw VideoRendererError.failedToCreatePixelBuffer
            }

            let presentationTime = CMTime(seconds: Double(frameIndex) / request.framesPerSecond, preferredTimescale: 600)
            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                throw VideoRendererError.videoWriterFailed(writer.error?.localizedDescription ?? "Unable to append frame.")
            }
        }

        input.markAsFinished()
        try finishWriting(writer: writer)
    }

    private func makePixelBuffer(
        pool: CVPixelBufferPool?,
        request: VideoRenderRequest,
        frameIndex: Int,
        configuration: VideoRendererConfiguration
    ) throws -> CVPixelBuffer? {
        guard let pool else { return nil }
        var maybeBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = maybeBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: request.width,
            height: request.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: request.width, height: request.height))

        let timestampSeconds = Double(frameIndex) / request.framesPerSecond
        drawLyrics(
            in: context,
            at: timestampSeconds,
            request: request,
            configuration: configuration
        )

        return pixelBuffer
    }

    private func drawLyrics(
        in context: CGContext,
        at timestampSeconds: Double,
        request: VideoRenderRequest,
        configuration: VideoRendererConfiguration
    ) {
        guard let activeLine = request.displayLines.last(where: {
            timestampSeconds >= $0.displayStartSeconds && timestampSeconds <= $0.displayEndSeconds
        }) else {
            return
        }

        let text = activeLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let font = CTFontCreateWithName("Arial Rounded MT Bold" as CFString, 48, nil)
        let availableWidth = max(1, CGFloat(request.width - (configuration.horizontalPadding * 2)))
        let maximumTextHeight = max(1, CGFloat(request.height) * 0.35)
        let paragraphStyle = makeParagraphStyle()
        let strokeWidth: CGFloat = 6.0

        let baseStrokeAttributes = makeStrokeAttributes(
            font: font,
            strokeColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            strokeWidth: strokeWidth,
            paragraphStyle: paragraphStyle
        )
        let baseFillAttributes = makeFillAttributes(
            font: font,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            paragraphStyle: paragraphStyle
        )
        let attributedText = NSAttributedString(string: text, attributes: baseFillAttributes)
        let layoutFramesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            layoutFramesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(width: availableWidth, height: maximumTextHeight),
            nil
        )
        let textHeight = max(ceil(suggestedSize.height), 56)
        let originY = CGFloat(configuration.bottomPadding)
        let textRect = CGRect(
            x: CGFloat(configuration.horizontalPadding),
            y: originY,
            width: availableWidth,
            height: min(maximumTextHeight, textHeight)
        )

        let textPath = CGPath(rect: textRect, transform: nil)
        let baseStrokeFrame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: baseStrokeAttributes)),
            CFRange(location: 0, length: attributedText.length),
            textPath,
            nil
        )
        let baseFillFrame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributedText),
            CFRange(location: 0, length: attributedText.length),
            textPath,
            nil
        )
        context.textMatrix = .identity
        CTFrameDraw(baseStrokeFrame, context)
        CTFrameDraw(baseFillFrame, context)

        let highlightedLength = highlightedUTF16Length(for: activeLine, at: timestampSeconds)
        if highlightedLength > 0 {
            let highlightStrokeAttributes = makeStrokeAttributes(
                font: font,
                strokeColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                strokeWidth: strokeWidth,
                paragraphStyle: paragraphStyle
            )
            let highlightFillAttributes = makeFillAttributes(
                font: font,
                color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                paragraphStyle: paragraphStyle
            )
            let transparentFillAttributes = makeFillAttributes(
                font: font,
                color: CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                paragraphStyle: paragraphStyle
            )
            drawHighlightedPortion(
                in: context,
                text: text,
                highlightedUTF16Length: highlightedLength,
                textPath: textPath,
                transparentAttributes: transparentFillAttributes,
                strokeAttributes: highlightStrokeAttributes,
                fillAttributes: highlightFillAttributes
            )
        }
    }

    private func drawHighlightedPortion(
        in context: CGContext,
        text: String,
        highlightedUTF16Length: Int,
        textPath: CGPath,
        transparentAttributes: [NSAttributedString.Key: Any],
        strokeAttributes: [NSAttributedString.Key: Any],
        fillAttributes: [NSAttributedString.Key: Any]
    ) {
        let highlightRange = NSRange(location: 0, length: min(highlightedUTF16Length, text.utf16.count))
        guard highlightRange.length > 0 else { return }

        let strokeOverlay = NSMutableAttributedString(string: text, attributes: transparentAttributes)
        strokeOverlay.addAttributes(strokeAttributes, range: highlightRange)
        let strokeFrame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(strokeOverlay),
            CFRange(location: 0, length: strokeOverlay.length),
            textPath,
            nil
        )
        CTFrameDraw(strokeFrame, context)

        let fillOverlay = NSMutableAttributedString(string: text, attributes: transparentAttributes)
        fillOverlay.addAttributes(fillAttributes, range: highlightRange)
        let fillFrame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(fillOverlay),
            CFRange(location: 0, length: fillOverlay.length),
            textPath,
            nil
        )
        CTFrameDraw(fillFrame, context)
    }

    private func makeStrokeAttributes(
        font: CTFont,
        strokeColor: CGColor,
        strokeWidth: CGFloat,
        paragraphStyle: CTParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): strokeColor,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): strokeWidth,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle,
        ]
    }

    private func makeFillAttributes(
        font: CTFont,
        color: CGColor,
        paragraphStyle: CTParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle,
        ]
    }

    private func makeParagraphStyle() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        var lineBreakMode = CTLineBreakMode.byWordWrapping
        var lineSpacing: CGFloat = 8
        let alignmentSize = MemoryLayout.size(ofValue: alignment)
        let lineBreakModeSize = MemoryLayout.size(ofValue: lineBreakMode)
        let lineSpacingSize = MemoryLayout.size(ofValue: lineSpacing)

        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreakMode) { lineBreakModePointer in
                withUnsafePointer(to: &lineSpacing) { lineSpacingPointer in
                    var settings: [CTParagraphStyleSetting] = [
                        .init(
                            spec: .alignment,
                            valueSize: alignmentSize,
                            value: alignmentPointer
                        ),
                        .init(
                            spec: .lineBreakMode,
                            valueSize: lineBreakModeSize,
                            value: lineBreakModePointer
                        ),
                        .init(
                            spec: .lineSpacingAdjustment,
                            valueSize: lineSpacingSize,
                            value: lineSpacingPointer
                        ),
                    ]
                    return CTParagraphStyleCreate(&settings, settings.count)
                }
            }
        }
    }

    private func highlightedUTF16Length(for line: VideoRenderLine, at timestampSeconds: Double) -> Int {
        let textLength = line.text.utf16.count
        guard textLength > 0 else { return 0 }

        if line.words.isEmpty {
            let duration = max(line.activeEndSeconds - line.activeStartSeconds, 0.001)
            let progress = max(0, min(1, (timestampSeconds - line.activeStartSeconds) / duration))
            return Int((Double(textLength) * progress).rounded())
        }

        let totalWordUnits = line.words.reduce(0) { partialResult, word in
            partialResult + max(word.text.count, 1)
        } + max(0, line.words.count - 1)

        guard totalWordUnits > 0 else { return 0 }

        var highlightedUnits = 0
        for (index, word) in line.words.enumerated() {
            let wordUnitLength = max(word.text.count, 1)
            if timestampSeconds >= word.endSeconds {
                highlightedUnits += wordUnitLength
                if index + 1 < line.words.count {
                    highlightedUnits += 1
                }
                continue
            }

            if timestampSeconds <= word.startSeconds {
                break
            }

            let wordDuration = max(word.endSeconds - word.startSeconds, 0.001)
            let progress = max(0, min(1, (timestampSeconds - word.startSeconds) / wordDuration))
            highlightedUnits += Int((Double(wordUnitLength) * progress).rounded(.towardZero))
            break
        }

        let ratio = Double(highlightedUnits) / Double(totalWordUnits)
        return min(textLength, max(0, Int((Double(textLength) * ratio).rounded())))
    }

    private func buildDisplayLines(
        from lines: [TranscribedLine],
        sourceDurationSeconds: Double,
        configuration: VideoRendererConfiguration
    ) -> [VideoRenderLine] {
        var output: [VideoRenderLine] = []
        for (index, line) in lines.enumerated() {
            let lineStart = seconds(from: line.startTime)
            let lineEnd = max(lineStart, seconds(from: line.endTime))
            let previousEnd = index > 0 ? seconds(from: lines[index - 1].endTime) : 0
            let nextStart = index + 1 < lines.count ? seconds(from: lines[index + 1].startTime) : sourceDurationSeconds

            let displayStart = max(previousEnd, max(0, lineStart - configuration.preRollPaddingSeconds))
            let displayEnd = min(nextStart, min(sourceDurationSeconds, lineEnd + configuration.postRollPaddingSeconds))
            guard displayEnd > displayStart else { continue }

            let words = line.words
                .sorted { $0.startTime < $1.startTime }
                .map { word in
                    VideoRenderWord(
                        text: word.text,
                        startSeconds: seconds(from: word.startTime),
                        endSeconds: max(seconds(from: word.startTime), seconds(from: word.endTime))
                    )
                }

            output.append(
                VideoRenderLine(
                    text: line.text,
                    activeStartSeconds: lineStart,
                    activeEndSeconds: lineEnd,
                    displayStartSeconds: displayStart,
                    displayEndSeconds: displayEnd,
                    words: words
                )
            )
        }
        return output
    }

    private func sourceDurationSeconds(for transcription: AudioTranscriberModel) -> Double {
        let declaredDuration = seconds(from: transcription.sourceAudioDuration)
        let inferredDuration = transcription.lines.map { seconds(from: $0.endTime) }.max() ?? 0
        return max(declaredDuration, inferredDuration)
    }

    private func finishWriting(writer: AVAssetWriter) throws {
        let finishState = VideoWriterFinishState(writer: writer)
        let semaphore = DispatchSemaphore(value: 0)
        finishState.writer.finishWriting {
            if let error = finishState.writer.error {
                finishState.setError(error.localizedDescription)
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let capturedError = finishState.error {
            throw VideoRendererError.videoWriterFailed(capturedError)
        }
        if finishState.writer.status != .completed {
            throw VideoRendererError.videoWriterFailed(
                finishState.writer.error?.localizedDescription
                    ?? "Video writer finished with status \(finishState.writer.status.rawValue)."
            )
        }
    }

    private func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

struct VideoRenderRequest {
    let transcription: AudioTranscriberModel
    let displayLines: [VideoRenderLine]
    let videoURL: URL
    let width: Int
    let height: Int
    let framesPerSecond: Double
    let durationSeconds: Double
}

struct VideoRenderLine {
    let text: String
    let activeStartSeconds: Double
    let activeEndSeconds: Double
    let displayStartSeconds: Double
    let displayEndSeconds: Double
    let words: [VideoRenderWord]
}

struct VideoRenderWord {
    let text: String
    let startSeconds: Double
    let endSeconds: Double
}

private final class VideoWriterFinishState: @unchecked Sendable {
    let writer: AVAssetWriter
    private let lock = NSLock()
    private var completionError: String?

    init(writer: AVAssetWriter) {
        self.writer = writer
    }

    func setError(_ error: String) {
        lock.lock()
        completionError = error
        lock.unlock()
    }

    var error: String? {
        lock.lock()
        defer { lock.unlock() }
        return completionError
    }
}
