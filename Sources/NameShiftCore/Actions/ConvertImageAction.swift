import Foundation

/// Converts every selected image that isn't already in the target format.
public struct ConvertImageAction: FileAction {
    public let format: ImageFormat
    let writableTypes: Set<String>

    public init(format: ImageFormat, writableTypes: Set<String> = ImageFormat.systemWritableTypes) {
        self.format = format
        self.writableTypes = writableTypes
    }

    public var id: String { "convert.\(format.rawValue)" }
    public var title: String { "To \(format.displayName)" }
    public var symbolName: String { "photo.on.rectangle.angled" }

    public var canEncode: Bool { writableTypes.contains(format.utType.identifier) }

    func targets(in files: [FileDescriptor]) -> [FileDescriptor] {
        files.filter { $0.kind == .image && !($0.contentType?.conforms(to: format.utType) ?? false) }
    }

    public func unavailableReason(for files: [FileDescriptor]) -> String? {
        guard canEncode else { return "\(format.displayName) needs libvips (Phase 2)" }
        guard files.contains(where: { $0.kind == .image }) else { return "Select images" }
        guard !targets(in: files).isEmpty else { return "Already \(format.displayName)" }
        return nil
    }

    public func run(on files: [FileDescriptor], progress: @escaping @Sendable (Double) -> Void) async throws -> ActionResult {
        let todo = targets(in: files)
        var result = ActionResult(outputs: [])
        for (i, file) in todo.enumerated() {
            if Task.isCancelled {
                guard !result.outputs.isEmpty else { throw CancellationError() }
                result.wasCancelled = true
                break
            }
            do {
                result.outputs.append(try ImageConverter.convert(file.url, to: format, writableTypes: writableTypes))
            } catch {
                result.failures.append(.init(input: file.url, message: String(describing: error)))
            }
            progress(Double(i + 1) / Double(todo.count))
        }
        if result.outputs.isEmpty, let first = result.failures.first {
            throw ActionFailure(message: first.message)
        }
        return result
    }
}

public struct ActionFailure: Error, CustomStringConvertible {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}
