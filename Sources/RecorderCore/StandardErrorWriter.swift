import Foundation
import RecorderLogic
import Synchronization

/// The one place that writes on standard error, so that nothing prints
/// into the middle of the status line: on a terminal a write clears the
/// line, prints, and draws it again, in one write. The event, problem,
/// summary and debug lines of `msr record`, and every other line of the
/// process on standard error, come through here. Not a terminal: plain
/// text, never an escape code.
public final class StandardErrorWriter: Sendable {
    private static let eraseToEnd = "\u{1B}[K"

    /// The process's standard error.
    public static let shared = StandardErrorWriter(descriptor: STDERR_FILENO, term: getenv("TERM").map { String(cString: $0) })

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

    /// Writes on a file descriptor. It draws a status line only when that is
    /// a terminal and `term` (the `TERM` variable) names one that takes escape codes.
    public convenience init(descriptor: Int32, term: String?) {
        let takesEscapeCodes = term.map { !$0.isEmpty && $0 != "dumb" } ?? false
        self.init(
            isTerminal: isatty(descriptor) != 0 && takesEscapeCodes,
            width: {
                var size = winsize()
                guard ioctl(descriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else { return nil }
                return Int(size.ws_col)
            },
            sink: { text in
                // A failed write is ignored: there is nowhere left to report it, and a recording must not die of it.
                var bytes = Array(text.utf8)[...]
                while !bytes.isEmpty {
                    let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
                    guard written > 0 else { return }
                    bytes = bytes.dropFirst(written)
                }
            })
    }

    /// Whether a status line is drawn at all.
    public var drawsStatusLine: Bool { isTerminal }

    /// Text for people, with its newlines; the status line comes back below it.
    public func write(_ text: String) {
        status.withLock { status in
            guard let status else { return sink(text) }
            sink(clear + text + drawn(status))
        }
    }

    /// Shows the status line, replacing the previous one; nothing when not on a terminal.
    public func showStatusLine(_ text: String) {
        guard isTerminal else { return }
        status.withLock { status in
            status = text
            sink(drawn(text))
        }
    }

    /// Clears the status line and stops redrawing it.
    public func endStatusLine() {
        status.withLock { status in
            if status != nil { sink(clear) }
            status = nil
        }
    }

    private var clear: String { "\r" + Self.eraseToEnd }

    private func drawn(_ text: String) -> String {
        "\r" + StatusLine.fit(text, width: width()) + Self.eraseToEnd
    }
}
