import Foundation
import Testing
@testable import BabelLyricsLib

@Suite("Logger service")
struct LoggerTests {
    @Test("Forwards explicit log messages to delegate")
    func forwardsLogMessage() {
        let delegate = TestLogDelegate()
        let service = LogService(delegate: delegate)
        let date = Date(timeIntervalSince1970: 123)
        let message = LogMessage(
            level: .info,
            message: "hello logger",
            file: "/tmp/AudioSeparator.swift",
            function: "separateAudio",
            line: 42,
            timeStamp: date
        )

        service.log(message)

        #expect(delegate.messages.count == 1)
        #expect(delegate.messages[0].message == "hello logger")
        #expect(delegate.messages[0].level.description == "info ")
        #expect(delegate.messages[0].file == "/tmp/AudioSeparator.swift")
        #expect(delegate.messages[0].function == "separateAudio")
        #expect(delegate.messages[0].line == 42)
        #expect(delegate.messages[0].timeStamp == date)
    }

    @Test("Creates formatted messages with payload and metadata")
    func formatsMessage() {
        let message = LogMessage(
            level: .warning,
            message: "demucs output missing",
            file: "/tmp/AudioSeparator.swift",
            function: "separate(_:)",
            line: 88,
            timeStamp: Date(timeIntervalSince1970: 0)
        )

        let formatted = message.formatted
        #expect(formatted.contains("[⚠️]"))
        #expect(formatted.contains("[AudioSeparator:separate(_:)@88]"))
        #expect(formatted.hasSuffix(" demucs output missing"))
    }

    @Test("Convenience methods map to expected log levels")
    func convenienceMethodsUseCorrectLevels() {
        let delegate = TestLogDelegate()
        let service = LogService(delegate: delegate)
        let date = Date(timeIntervalSince1970: 1)

        service.debug("debug", file: "debug.swift", function: "dbg()", line: 1, date: date)
        service.info("info", file: "info.swift", function: "inf()", line: 2, date: date)
        service.warning("warn", file: "warn.swift", function: "wrn()", line: 3, date: date)
        service.error("error", file: "error.swift", function: "err()", line: 4, date: date)

        #expect(delegate.messages.count == 4)
        #expect(delegate.messages[0].level.description == "debug")
        #expect(delegate.messages[1].level.description == "info ")
        #expect(delegate.messages[2].level.description == "warn ")
        #expect(delegate.messages[3].level.description == "error")
    }
}

private final class TestLogDelegate: LogDelegate {
    var messages: [LogMessage] = []

    func log(_ message: LogMessage) {
        messages.append(message)
    }
}
