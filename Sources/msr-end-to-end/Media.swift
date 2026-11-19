import EndToEndLogic
import Foundation

/// Reads recorded files through `ffprobe` and `ffmpeg`, found on the PATH.
struct Media {
    let ffprobe: String
    let ffmpeg: String
    let scratch: URL

    /// Requires both tools on the PATH up front.
    init(scratch: URL) throws {
        ffprobe = try Self.onPath("ffprobe")
        ffmpeg = try Self.onPath("ffmpeg")
        self.scratch = scratch
    }

    static func onPath(_ tool: String) throws -> String {
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        guard let found = folders.map({ "\($0)/\(tool)" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw DriverError("\(tool) is not on the PATH; install it (brew install ffmpeg)")
        }
        return found
    }

    /// Every stream with its decoded frame count.
    func probe(_ file: URL) throws -> ProbedFile {
        let output = try run(ffprobe, ["-v", "error", "-count_frames", "-show_entries",
                                       "stream=index,codec_type,codec_name,width,height,channels,sample_rate,duration,nb_read_frames:stream_tags=title,timecode",
                                       "-of", "json", file.path])
        return try ProbedFile(ffprobeJSON: output.output)
    }

    /// Decodes every stream to the end; the errors `ffmpeg` reports, if any.
    func decodeErrors(_ file: URL) throws -> String? {
        let errors = scratch.appending(path: "ffmpeg-decode.err")
        let status = try run(ffmpeg, ["-nostdin", "-v", "error", "-i", file.path, "-map", "0:v?", "-map", "0:a?", "-f", "null", "-"],
                             standardError: errors).status
        let text = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
        return status == 0 && text.isEmpty ? nil : "exit \(status): \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// One audio stream's samples, its channels averaged to mono, as 32-bit floats.
    func samples(_ file: URL, stream index: Int, sampleRate: Int) throws -> [Float] {
        let raw = scratch.appending(path: "samples.f32")
        _ = try run(ffmpeg, ["-nostdin", "-v", "error", "-y", "-i", file.path, "-map", "0:\(index)", "-ac", "1",
                             "-ar", "\(sampleRate)", "-f", "f32le", raw.path])
        let data = try Data(contentsOf: raw)
        try? FileManager.default.removeItem(at: raw)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String], standardError: URL? = nil) throws -> (output: Data, status: Int32) {
        let output = scratch.appending(path: "tool.out")
        let errors = standardError ?? scratch.appending(path: "tool.err")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = try FileHandle(forWritingTo: output)
        process.standardError = try FileHandle(forWritingTo: errors)
        try process.run()
        process.waitUntilExit()
        let data = try Data(contentsOf: output)
        if standardError == nil, process.terminationStatus != 0 {
            let text = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
            throw DriverError("\(URL(filePath: tool).lastPathComponent) failed (exit \(process.terminationStatus)): \(text)")
        }
        return (data, process.terminationStatus)
    }
}
