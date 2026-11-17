import Foundation
import RecorderLogic
import Synchronization

/// Everything the process writes on standard error for people while
/// `msr record` runs goes through here, so that nothing prints into the
/// middle of the status line: on a terminal a write clears the line,
/// prints, and draws it again. Not a terminal: plain text, never an escape code.
public final class StandardErrorWriter: Sendable {
    private static let eraseToEnd = "\u{1B}[K"

    /// The process's standard error.
    public static let shared = StandardErrorWriter(
        isTerminal: isatty(STDERR_FILENO) != 0, width: terminalWidth,
        sink: { FileHandle.standardError.write(Data($0.utf8)) })

    private let isTerminal: Bool
    private let width: @Sendable () -> Int?
    private let sink: @Sendable (String) -> Void
    /// The status line as last shown; nil when none is.
    private let status = Mutex<String?>(nil)

    public init(isTerminal: Bool, width: @escaping @Sendable () -> Int?, sink: @escaping @Sendable (String) -> Void) {
        self.isTerminal = isTerminal
        self.width = width
        self.sink = sink
    }

    /// Whether a status line is drawn at all.
    public var drawsStatusLine: Bool { isTerminal }

    /// Text for people, with its newlines; the status line comes back below it.
    public func write(_ text: String) {
        status.withLock { status in
            if status != nil { sink(clear) }
            sink(text)
            if let status { draw(status) }
        }
    }

    /// Shows the status line, replacing the previous one; nothing when not on a terminal.
    public func showStatus(_ text: String) {
        guard isTerminal else { return }
        status.withLock { status in
            status = text
            draw(text)
        }
    }

    /// Clears the status line and stops redrawing it.
    public func endStatus() {
        status.withLock { status in
            if status != nil { sink(clear) }
            status = nil
        }
    }

    private var clear: String { "\r" + Self.eraseToEnd }

    private func draw(_ text: String) {
        sink("\r" + StatusLine.fit(text, width: width()) + Self.eraseToEnd)
    }

    private static func terminalWidth() -> Int? {
        var size = winsize()
        guard ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else { return nil }
        return Int(size.ws_col)
    }
}
