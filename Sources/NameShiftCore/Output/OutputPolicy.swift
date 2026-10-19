import Darwin
import Foundation

public enum OutputError: Error, CustomStringConvertible {
    case notWritable(URL)
    case writeFailed(String)
    case tooManyCollisions(URL)

    public var description: String {
        switch self {
        case .notWritable(let dir): return "Can't write to “\(dir.lastPathComponent)”"
        case .writeFailed(let why): return why
        case .tooManyCollisions(let url): return "Too many files named like “\(url.lastPathComponent)”"
        }
    }
}

/// Outputs go next to the source and never overwrite anything.
///
/// Writing happens in a temp file on the same volume, then the file is moved into place with
/// `renamex_np(RENAME_EXCL)`, which fails atomically if the name exists — so even a file that
/// appears between "pick a name" and "write" is never clobbered.
public enum OutputPolicy {
    static let maxAttempts = 9_999

    /// attempt 1 → "base.ext", attempt 2 → "base 2.ext", ...
    public static func candidateName(baseName: String, ext: String, attempt: Int) -> String {
        let stem = attempt <= 1 ? baseName : "\(baseName) \(attempt)"
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// First candidate that doesn't exist. Advisory only; `write` re-checks atomically.
    public static func uniqueURL(in directory: URL, baseName: String, ext: String,
                                 exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        for attempt in 1...maxAttempts {
            let url = directory.appendingPathComponent(candidateName(baseName: baseName, ext: ext, attempt: attempt))
            if !exists(url) { return url }
        }
        return directory.appendingPathComponent(candidateName(baseName: baseName, ext: ext, attempt: maxAttempts + 1))
    }

    /// Produce a file via `body(tempURL)` and move it to the first free name in `directory`.
    @discardableResult
    public static func write(in directory: URL, baseName: String, ext: String,
                             _ body: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        let tempDir = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                   appropriateFor: directory, create: true))
            ?? fm.temporaryDirectory.appendingPathComponent("NameShift-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        var temp = tempDir.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
        try body(temp)
        guard fm.fileExists(atPath: temp.path) else { throw OutputError.writeFailed("No output was produced") }

        var attempt = 1
        while attempt <= maxAttempts {
            let dest = directory.appendingPathComponent(candidateName(baseName: baseName, ext: ext, attempt: attempt))
            if renamex_np(temp.path, dest.path, UInt32(RENAME_EXCL)) == 0 { return dest }
            switch errno {
            case EEXIST:
                attempt += 1
            case EXDEV:
                // Temp landed on another volume; stage a hidden copy in the destination folder.
                let staged = directory.appendingPathComponent(".nameshift-\(UUID().uuidString).tmp")
                do { try fm.copyItem(at: temp, to: staged) } catch { throw OutputError.notWritable(directory) }
                try? fm.removeItem(at: temp)
                temp = staged
            case EACCES, EPERM, EROFS:
                throw OutputError.notWritable(directory)
            default:
                throw OutputError.writeFailed(String(cString: strerror(errno)))
            }
        }
        if temp.path.hasPrefix(directory.path) { try? fm.removeItem(at: temp) }
        throw OutputError.tooManyCollisions(directory.appendingPathComponent(baseName))
    }
}
