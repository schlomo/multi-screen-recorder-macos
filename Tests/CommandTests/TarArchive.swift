import Foundation

/// A ustar archive written member by member, so a test can build archives
/// no tar would write from a file system: a member below a symbolic link,
/// a hard link to anything.
struct TarArchive {
    enum Kind {
        case file(String, executable: Bool = false)
        case folder
        case symbolicLink(to: String)
        case hardLink(to: String)
    }

    private(set) var data = Data()

    mutating func add(_ name: String, _ kind: Kind) {
        var content = Data()
        var mode = 0o644
        var type: UInt8 = UInt8(ascii: "0")
        var linkName = ""
        switch kind {
        case .file(let text, let executable):
            content = Data(text.utf8)
            mode = executable ? 0o755 : 0o644
        case .folder:
            mode = 0o755
            type = UInt8(ascii: "5")
        case .symbolicLink(let target):
            mode = 0o755
            type = UInt8(ascii: "2")
            linkName = target
        case .hardLink(let target):
            type = UInt8(ascii: "1")
            linkName = target
        }
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int, width: Int) {
            for (index, byte) in text.utf8.prefix(width).enumerated() { header[offset + index] = byte }
        }
        func octal(_ value: Int, at offset: Int, width: Int) {
            let digits = String(value, radix: 8)
            put(String(repeating: "0", count: max(0, width - 1 - digits.count)) + digits, at: offset, width: width - 1)
        }
        put(name, at: 0, width: 100)
        octal(mode, at: 100, width: 8)
        octal(0, at: 108, width: 8)
        octal(0, at: 116, width: 8)
        octal(content.count, at: 124, width: 12)
        octal(0, at: 136, width: 12)
        header[156] = type
        put(linkName, at: 157, width: 100)
        put("ustar", at: 257, width: 6)
        put("00", at: 263, width: 2)
        for offset in 148..<156 { header[offset] = UInt8(ascii: " ") }
        let checksum = header.reduce(0) { $0 + Int($1) }
        octal(checksum, at: 148, width: 7)
        data.append(contentsOf: header)
        data.append(content)
        data.append(Data(count: (512 - content.count % 512) % 512))
    }

    func write(to url: URL) throws {
        try (data + Data(count: 1024)).write(to: url)
    }
}
