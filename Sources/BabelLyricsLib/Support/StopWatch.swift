import Foundation

/// A simple stopwatch that measures elapsed time between start and stop points.
///
/// The stopwatch is queryable at any time. Starting always resets accumulated time.
/// Paused time is excluded from elapsed duration.
public final class StopWatch {
    private let nowProvider: () -> Date
    private var accumulated: Duration
    private var segmentStart: Date?

    /// Indicates whether the stopwatch has been started and not yet stopped.
    public private(set) var isRunning: Bool

    /// Indicates whether the stopwatch is currently paused.
    public private(set) var isPaused: Bool

    /// Creates a new stopwatch.
    public init() {
        self.nowProvider = Date.init
        self.accumulated = .zero
        self.segmentStart = nil
        self.isRunning = false
        self.isPaused = false
    }

    init(nowProvider: @escaping () -> Date) {
        self.nowProvider = nowProvider
        self.accumulated = .zero
        self.segmentStart = nil
        self.isRunning = false
        self.isPaused = false
    }

    @discardableResult
    /// Starts the stopwatch and resets any previously recorded duration.
    public func start() -> Self {
        accumulated = .zero
        segmentStart = nowProvider()
        isRunning = true
        isPaused = false
        return self
    }

    /// Stops the stopwatch and preserves the measured duration.
    ///
    /// Querying elapsed time after stop returns the same value until restarted.
    @discardableResult
    public func stop() -> Duration {
        guard isRunning else { return accumulated }

        if let segmentStart {
            accumulated += Duration.seconds(nowProvider().timeIntervalSince(segmentStart))
        }

        self.segmentStart = nil
        isRunning = false
        isPaused = false
        return accumulated
    }

    /// Pauses active time accumulation while keeping the stopwatch running.
    @discardableResult
    public func pause() -> Duration {
        guard isRunning, !isPaused, let segmentStart else { return elapsed }

        accumulated += Duration.seconds(nowProvider().timeIntervalSince(segmentStart))
        self.segmentStart = nil
        isPaused = true
        return accumulated
    }

    /// Resumes accumulation after a pause.
    public func resume() {
        guard isRunning, isPaused else { return }
        segmentStart = nowProvider()
        isPaused = false
    }

    /// The elapsed active duration.
    ///
    /// While running, this includes current active segment time.
    /// While stopped, this is the preserved stopped duration.
    public var elapsed: Duration {
        var total = accumulated
        if isRunning, !isPaused, let segmentStart {
            total += Duration.seconds(nowProvider().timeIntervalSince(segmentStart))
        }
        return total
    }
}

public extension StopWatch {
    
    /// Returns a human-readable elapsed duration string, based the default formatting of `Duration`.
    func formattedDuration() -> String {
        elapsed.formatted()
    }

    /// Returns elapsed duration formatted with a time format style.
    func formattedTimeStyle(_ timeStyle: Duration.TimeFormatStyle) -> String {
        elapsed.formatted(timeStyle)
    }

    /// Returns elapsed duration formatted with a units format style.
    func formattedUnitsStyle(_ unitsStyle: Duration.UnitsFormatStyle = .units(width: .narrow)) -> String {
        elapsed.formatted(unitsStyle)
    }

}

public extension StopWatch {
    
    /// A human friendly description of the elapsed duration.
    var durationDescription: String {
        formattedUnitsStyle()
    }
}
