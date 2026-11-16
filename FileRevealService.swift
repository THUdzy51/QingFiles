import AppKit

enum FileRevealService {
    static func fileURLs(from pasteboard: NSPasteboard) throws -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return urls }
        let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: filenames) as? [String],
           !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") }) {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        throw FileServiceError.invalid("Select a local file or folder to reveal in QingFiles.")
    }
}
