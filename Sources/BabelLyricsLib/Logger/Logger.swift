//
//  Logger.swift
//  BabelLyricsLib
//
//  Created by Shane Whitehead on 12/7/2026.
//

import Foundation

/// Receives log messages emitted by the library.
public protocol LogDelegate {
    /// Handles a log message.
    ///
    /// - Parameter message: The message emitted by the library.
    func log(_ message: LogMessage)
}

/// Severity levels for ``LogMessage`` values.
public enum LogLevel {
    /// Diagnostic details for development and troubleshooting.
    case debug
    /// General informational events.
    case info
    /// Recoverable or notable conditions.
    case warning
    /// Failures or unrecoverable conditions.
    case error
    
    /// Human-readable level text.
    public var description: String {
        switch self {
        case .debug:
            "debug"
        case .info:
            "info "
        case .warning:
            "warn "
        case .error:
            "error"
        }
    }
    
    /// Display token used in formatted output.
    public var token: String {
        switch self {
        case .debug:
            "🔍"
        case .info:
            "💡"
        case .warning:
            "⚠️"
        case .error:
            "🔥"
        }
    }
}

/// A single structured log message.
public struct LogMessage {
    /// The severity of the log message.
    public let level: LogLevel
    /// The log text payload.
    public let message: String
    
    /// Source file that emitted the message.
    public let file: String
    /// Source function that emitted the message.
    public let function: String
    /// Source line that emitted the message.
    public let line: UInt
    /// Timestamp for when the message was created.
    public let timeStamp: Date
}

public extension LogMessage {
    
    /// Returns a human-readable formatted log line.
    var formatted: String {
        let fileName = String(
            file
            .split(separator: "/")
            .last ?? "[Unknown]"
        ).replacingOccurrences(of: ".swift", with: "")
        
        var formattedMessage = "\(level.token)["
        formattedMessage += Self.timestampFormatter.string(from: timeStamp)
        formattedMessage += "]["
        formattedMessage += "\(fileName):\(function)@\(line)"
        formattedMessage += "]"
        formattedMessage += "\t\n\(self.message)"
        
        return formattedMessage
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd@HH:mm:ss.SSS"
        return formatter
    }()
}

public extension StaticString {
    
    /// Converts the static string value into a `String`.
    var asString: String {
        self.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
    }
}

/// Internal helper that builds structured log messages and forwards them to a delegate.
struct LogService {
    
    let delegate: any LogDelegate
    
    /// Creates a log service.
    ///
    /// - Parameter delegate: Delegate that receives structured messages.
    init(delegate: any LogDelegate) {
        self.delegate = delegate
    }
    
    /// Forwards a prebuilt log message to the delegate.
    ///
    /// - Parameter message: Structured log message.
    func log(_ message: LogMessage) {
        delegate.log(message)
    }
    
    /// Emits a debug log message.
    ///
    /// - Parameters:
    ///   - message: Log payload.
    ///   - file: Source file.
    ///   - function: Source function.
    ///   - line: Source line.
    ///   - date: Timestamp override, useful for tests.
    func debug(
        _ message: String,
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        date: Date = Date()
    ) {
        log(
            .init(
                level: .debug,
                message: message,
                file: file.asString,
                function: function.asString,
                line: line,
                timeStamp: date
            )
        )
    }
    
    /// Emits an info log message.
    ///
    /// - Parameters:
    ///   - message: Log payload.
    ///   - file: Source file.
    ///   - function: Source function.
    ///   - line: Source line.
    ///   - date: Timestamp override, useful for tests.
    func info(
        _ message: String,
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        date: Date = Date()
    ) {
        log(
            .init(
                level: .info,
                message: message,
                file: file.asString,
                function: function.asString,
                line: line,
                timeStamp: date
            )
        )
    }
    
    /// Emits a warning log message.
    ///
    /// - Parameters:
    ///   - message: Log payload.
    ///   - file: Source file.
    ///   - function: Source function.
    ///   - line: Source line.
    ///   - date: Timestamp override, useful for tests.
    func warning(
        _ message: String,
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        date: Date = Date()
    ) {
        log(
            .init(
                level: .warning,
                message: message,
                file: file.asString,
                function: function.asString,
                line: line,
                timeStamp: date
            )
        )
    }
    
    /// Emits an error log message.
    ///
    /// - Parameters:
    ///   - message: Log payload.
    ///   - file: Source file.
    ///   - function: Source function.
    ///   - line: Source line.
    ///   - date: Timestamp override, useful for tests.
    func error(
        _ message: String,
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        date: Date = Date()
    ) {
        log(
            .init(
                level: .error,
                message: message,
                file: file.asString,
                function: function.asString,
                line: line,
                timeStamp: date
            )
        )
    }
}
