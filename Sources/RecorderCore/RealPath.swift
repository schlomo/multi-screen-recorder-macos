import Foundation

/// EX_OSERR from sysexits: `msr` could not re-execute itself.
public let reexecutionFailedExitCode: Int32 = 71

/// Started through a symbolic link, `Bundle.main` finds no app bundle, so
/// `msr` re-executes itself at its fully resolved real path with the same
/// arguments. Returns only when the executable path already is the real path.
public func reexecuteAtRealPathIfLinked() {
    let path = executablePath()
    guard let resolved = realpath(path, nil) else { stopReexecution("cannot resolve \(path)") }
    let realPath = String(cString: resolved)
    free(resolved)
    guard realPath != path else { return }
    execv(realPath, CommandLine.unsafeArgv)
    stopReexecution("cannot execute \(realPath)")
}

private func executablePath() -> String {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { stopReexecution("cannot read the executable path") }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

private func stopReexecution(_ problem: String) -> Never {
    let reason = String(cString: strerror(errno))
    FileHandle.standardError.write(Data("Error: msr \(problem) (\(reason))\n".utf8))
    exit(reexecutionFailedExitCode)
}
