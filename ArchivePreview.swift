import Darwin
import Foundation
import QingArchive

enum ArchivePreview {
    struct Member: Equatable, Sendable {
        let index: Int
        let path: [String]
        let isDirectory: Bool
        let isRegularFile: Bool
        let isEncrypted: Bool
        let size: Int64?
    }

    struct Listing {
        let members: [Member]
        let isPartial: Bool
    }

    private static let containers: Set<String> = [
        "zip", "zipx", "7z", "rar", "tar", "tgz", "tbz", "tbz2", "txz", "tlz",
        "cab", "cpio", "xar", "iso", "lha", "lzh", "ar", "a", "deb"
    ]
    private static let compressedStreams: Set<String> = ["gz", "bz2", "xz", "lzma", "lz", "z"]
    private static let limit = 512 * 1024 * 1024

    static func supports(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return containers.contains(ext) || compressedStreams.contains(ext)
    }

    static func list(_ url: URL, limit: Int, cancelled: () -> Bool) throws -> Listing {
        var members: [Member] = []
        let complete = try scan(url, cancelled: cancelled) { _, index, member in
            guard index < limit else { return false }
            if let member { members.append(member) }
            return true
        }
        return Listing(members: members, isPartial: !complete)
    }

    // The archive name is never used as an output path or applied as metadata.
    static func materialize(_ member: Member, in url: URL,
                            cancelled: () -> Bool) throws -> URL {
        guard member.isRegularFile, !member.isEncrypted, let name = member.path.last else {
            throw FileServiceError.invalid("This entry requires a password or is not a regular file.")
        }
        guard (member.size ?? 0) <= Int64(limit) else { throw sizeError }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("QingFiles-Preview-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let ext = (name as NSString).pathExtension
        let file = directory.appendingPathComponent(ext.isEmpty ? "Preview" : "Preview.\(ext)")
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: directory) } }
        let complete = try scan(url, cancelled: cancelled) { reader, index, current in
            guard index == member.index else { return true }
            guard current == member else { throw FileServiceError.invalid("The archive changed. Select it again.") }
            try writeEntry(reader, to: file, cancelled: cancelled)
            return false
        }
        guard !complete else { throw FileServiceError.invalid("The archive entry is no longer available.") }
        succeeded = true
        return file
    }

    private static func scan(_ url: URL, cancelled: () -> Bool,
                             visit: (OpaquePointer, Int, Member?) throws -> Bool) throws -> Bool {
        if cancelled() { throw CancellationError() }
        guard let reader = archive_read_new() else { throw FileServiceError.invalid("Cannot create an archive reader.") }
        defer { archive_read_free(reader) }
        // Use the system readers for common filters and containers.
        archive_read_support_filter_gzip(reader)
        archive_read_support_filter_bzip2(reader)
        archive_read_support_filter_xz(reader)
        archive_read_support_filter_lzma(reader)
        archive_read_support_filter_compress(reader)
        archive_read_support_filter_lzip(reader)
        archive_read_support_format_all(reader)
        let ext = url.pathExtension.lowercased()
        let rawName = url.deletingPathExtension().lastPathComponent
        let allowRaw = compressedStreams.contains(ext) && !rawName.lowercased().hasSuffix(".tar")
        if allowRaw { archive_read_support_format_raw(reader) }
        let status = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw FileServiceError.invalid("Cannot read this archive path.") }
            return archive_read_open_filename(reader, path, 128 * 1024)
        }
        guard status == 0 else { throw readError(reader) }
        var index = 0
        while !cancelled() {
            var header: OpaquePointer?
            let status = archive_read_next_header(reader, &header)
            if status == QING_ARCHIVE_EOF { return true }
            guard (status == 0 || status == QING_ARCHIVE_WARN), let header else { throw readError(reader) }
            let isRaw = archive_format(reader) == QING_ARCHIVE_FORMAT_RAW
            if isRaw && archive_filter_count(reader) < 2 { throw readError(reader) }
            let bytes = archive_entry_pathname_utf8(header) ?? archive_entry_pathname(header)
            let name = isRaw ? rawName : bytes.map { String(cString: $0) }
            let member = name.flatMap(safeComponents).map { path in
                let fileType = Int32(archive_entry_filetype(header))
                return Member(index: index, path: path, isDirectory: fileType == S_IFDIR,
                              isRegularFile: fileType == S_IFREG && archive_entry_hardlink(header) == nil
                                  && archive_entry_symlink(header) == nil,
                              isEncrypted: archive_entry_is_encrypted(header) > 0,
                              size: archive_entry_size_is_set(header) > 0 ? archive_entry_size(header) : nil)
            }
            if try !visit(reader, index, member) { return false }
            index += 1
        }
        throw CancellationError()
    }

    private static func safeComponents(_ name: String) -> [String]? {
        guard !name.hasPrefix("/"), name.utf8.count <= 4096 else { return nil }
        let parts = name.split(separator: "/").filter { $0 != "." }
        guard !parts.isEmpty, parts.count <= 128, !parts.contains("..") else { return nil }
        return parts.map(String.init)
    }

    private static var sizeError: FileServiceError {
        .invalid("Individual archive previews are limited to 512 MiB.")
    }

    private static func readError(_ reader: OpaquePointer) -> FileServiceError {
        let description = archive_error_string(reader).map { String(cString: $0) }
        return .invalid(description ?? "Cannot read this archive.")
    }

    private static func writeEntry(_ reader: OpaquePointer, to url: URL,
                                   cancelled: () -> Bool) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw FileServiceError.invalid("Cannot create the temporary preview.")
        }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        var buffer = Data(count: 128 * 1024)
        var total = 0
        while !cancelled() {
            let count = buffer.withUnsafeMutableBytes { archive_read_data(reader, $0.baseAddress, $0.count) }
            if count == 0 { return }
            guard count > 0 else { throw readError(reader) }
            total += count
            guard total <= limit else { throw sizeError }
            try file.write(contentsOf: buffer.prefix(count))
        }
        throw CancellationError()
    }
}
