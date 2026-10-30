import Foundation

struct FileEntry: Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isHidden: Bool
    let isSymbolicLink: Bool
    let size: Int64
    let modifiedDate: Date?

    var typeLabel: String {
        if isSymbolicLink { return isDirectory ? "Folder Link" : "Symbolic Link" }
        if isDirectory { return "Folder" }
        let ext = url.pathExtension
        return ext.isEmpty ? "File" : "\(ext.uppercased()) File"
    }
}

enum FileTransferMode: Sendable { case copy, move }

struct FileOperationFailure: Sendable {
    let source: URL
    let message: String
}

struct FileOperationReport: Sendable {
    var succeeded: [URL] = []
    var failures: [FileOperationFailure] = []
}

enum FileServiceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// All operations use local file URLs and preserve existing destinations.
/// Transfer success URLs identify their new destinations; trash success URLs
/// identify the original items that were moved to the system Trash.
enum FileService {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey
    ]

    static func list(_ directory: URL, showHidden: Bool) throws -> [FileEntry] {
        try requireDirectory(directory)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(resourceKeys), options: []
        )
        var result: [FileEntry] = []
        for url in urls {
            // A concurrently removed entry should not make the whole folder fail.
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            let hidden = (values.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
            if hidden && !showHidden { continue }
            var isDir = values.isDirectory ?? false
            if values.isSymbolicLink == true {
                var targetIsDir: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &targetIsDir)
                isDir = targetIsDir.boolValue
            }
            result.append(FileEntry(
                url: url, name: url.lastPathComponent, isDirectory: isDir,
                isHidden: hidden, isSymbolicLink: values.isSymbolicLink ?? false,
                size: Int64(values.fileSize ?? 0), modifiedDate: values.contentModificationDate
            ))
        }
        return result.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func createDirectory(named name: String, in parent: URL) throws -> URL {
        try validateName(name)
        try requireDirectory(parent)
        let target = parent.appendingPathComponent(name, isDirectory: true)
        try requireAbsent(target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    static func rename(_ url: URL, to name: String) throws -> URL {
        try requireLocal(url)
        try validateName(name)
        try protectRoot(url)
        try requireExists(url)
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if url.standardizedFileURL.path == target.standardizedFileURL.path { return url }
        // On case-insensitive volumes a case-only rename is intentionally rejected
        // by this conservative no-overwrite policy.
        try requireAbsent(target)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    static func transfer(_ sources: [URL], to destination: URL, mode: FileTransferMode) -> FileOperationReport {
        var report = FileOperationReport()
        do { try requireDirectory(destination) }
        catch {
            report.failures = sources.map { FileOperationFailure(source: $0, message: error.localizedDescription) }
            return report
        }
        let selectionErrors = invalidSelection(sources)
        for (index, source) in sources.enumerated() {
            do {
                if let reason = selectionErrors[index] { throw FileServiceError.invalid(reason) }
                try requireLocal(source)
                try protectRoot(source)
                try requireExists(source)
                let target = destination.appendingPathComponent(source.lastPathComponent)
                let sourcePath = canonicalPath(source)
                let targetPath = canonicalPath(target)
                guard sourcePath != targetPath else {
                    throw FileServiceError.invalid("Source and destination are the same. No action was taken.")
                }
                if isDirectory(source) && isDescendant(canonicalPath(destination), of: sourcePath) {
                    throw FileServiceError.invalid("A folder cannot be copied or moved into itself or a descendant.")
                }
                if isDirectory(source) && canonicalPath(destination) == sourcePath {
                    throw FileServiceError.invalid("A folder cannot be copied or moved into itself.")
                }
                try requireAbsent(target)
                switch mode {
                case .copy: try FileManager.default.copyItem(at: source, to: target)
                case .move: try FileManager.default.moveItem(at: source, to: target)
                }
                report.succeeded.append(target)
            } catch {
                // Do not remove a partial destination here: another process may
                // have changed it. Existing files are never automatically deleted.
                report.failures.append(FileOperationFailure(source: source, message: error.localizedDescription))
            }
        }
        return report
    }

    static func trash(_ sources: [URL]) -> FileOperationReport {
        var report = FileOperationReport()
        let selectionErrors = invalidSelection(sources)
        for (index, source) in sources.enumerated() {
            do {
                if let reason = selectionErrors[index] { throw FileServiceError.invalid(reason) }
                try requireLocal(source)
                try protectRoot(source)
                try requireExists(source)
                try FileManager.default.trashItem(at: source, resultingItemURL: nil)
                report.succeeded.append(source)
            } catch {
                report.failures.append(FileOperationFailure(source: source, message: error.localizedDescription))
            }
        }
        return report
    }

    private static func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            name == "." || name == ".." || name.contains("/") || name.contains("\0") {
            throw FileServiceError.invalid("Enter a nonempty name other than . or .., without a slash or null character.")
        }
    }

    private static func requireLocal(_ url: URL) throws {
        guard url.isFileURL else { throw FileServiceError.invalid("This version supports local file paths only.") }
    }

    private static func requireDirectory(_ url: URL) throws {
        try requireLocal(url)
        guard isDirectory(url) else { throw FileServiceError.invalid("Folder not found or inaccessible: \(url.path)") }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &value) && value.boolValue
    }

    private static func requireExists(_ url: URL) throws {
        // attributesOfItem detects broken symbolic links, unlike fileExists.
        _ = try FileManager.default.attributesOfItem(atPath: url.path)
    }

    private static func requireAbsent(_ url: URL) throws {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            throw FileServiceError.invalid("An item named \"\(url.lastPathComponent)\" already exists. Skipped to preserve existing data.")
        } catch let error as FileServiceError { throw error }
        catch {
            let cocoaError = error as NSError
            // Only a definite missing item permits writing. Permission and I/O
            // failures must never be mistaken for an absent target.
            if cocoaError.domain == NSCocoaErrorDomain &&
                (cocoaError.code == NSFileReadNoSuchFileError || cocoaError.code == NSFileNoSuchFileError) { return }
            throw error
        }
    }

    private static func protectRoot(_ url: URL) throws {
        guard canonicalPath(url) != "/" else { throw FileServiceError.invalid("This operation is not allowed on the filesystem root.") }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isDescendant(_ child: String, of parent: String) -> Bool {
        child.hasPrefix(parent == "/" ? "/" : parent + "/")
    }

    /// Ambiguous selections are rejected before any mutations. This avoids a
    /// parent move invalidating a selected child, or copying the same file twice.
    private static func invalidSelection(_ sources: [URL]) -> [Int: String] {
        var errors: [Int: String] = [:]
        let paths = sources.map(canonicalPath)
        for i in sources.indices {
            for j in sources.indices where j > i {
                if paths[i] == paths[j] {
                    errors[i] = "The selection contains duplicate items. Select each item only once."
                    errors[j] = "The selection contains duplicate items. Select each item only once."
                } else if (isDirectory(sources[i]) && isDescendant(paths[j], of: paths[i])) ||
                    (isDirectory(sources[j]) && isDescendant(paths[i], of: paths[j])) {
                    errors[i] = "A folder and its contents are selected together. Select only one level."
                    errors[j] = "A folder and its contents are selected together. Select only one level."
                }
            }
        }
        return errors
    }
}
