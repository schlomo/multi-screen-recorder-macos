import Foundation
import RecorderLogic

public struct MissingHomeFolderError: Error, CustomStringConvertible {
    public var description: String { "HOME is not set, so the settings file cannot be found" }
}

/// The home folder from `HOME`, so the settings file follows the environment.
public func homeFolder() throws -> URL {
    guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else {
        throw MissingHomeFolderError()
    }
    return URL(filePath: home, directoryHint: .isDirectory)
}

/// The version of the running build, from its bundle's Info.plist.
public var runningVersion: AppVersion {
    AppVersion(infoDictionary: Bundle.main.infoDictionary)
}

/// The Mac's model identifier, such as `Mac15,8` (`hw.model`); nil when
/// macOS does not give it.
public func macModel() -> String? {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
    return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
