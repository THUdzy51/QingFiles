import AppKit
import CoreServices
import UniformTypeIdentifiers

@main
struct DocumentRegistrationTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass the path to a built QingFiles.app bundle.")
        }
        let app = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == "local.qingfiles.app" else {
            fatalError("Expected a built QingFiles.app bundle.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QingFiles-Registration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let extensions = ["pdf", "zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
        let files = try extensions.compactMap { ext -> URL? in
            // Additional archive type definitions can depend on the macOS installation.
            guard ext == "pdf" || ext == "zip" || UTType(filenameExtension: ext)?.conforms(to: .archive) == true else {
                print("SKIP: .\(ext) has no archive type definition on this Mac")
                return nil
            }
            let file = root.appendingPathComponent("中文 Archive.\(ext)")
            try Data().write(to: file)
            return file
        }
        let defaults = files.map { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        precondition(LSRegisterURL(app as CFURL, true) == noErr, "Launch Services registration failed")
        for file in files {
            var accepts = DarwinBoolean(false)
            let status = LSCanURLAcceptURL(file as CFURL, app as CFURL, .viewer, [], &accepts)
            precondition(status == noErr && accepts.boolValue,
                         "QingFiles is not a Viewer candidate for .\(file.pathExtension)")
            print("PASS: Launch Services accepts .\(file.pathExtension) for QingFiles")
        }
        precondition(defaults == files.map { NSWorkspace.shared.urlForApplication(toOpen: $0) },
                     "Registering QingFiles changed a default application")
        print("PASS: default document and archive applications remain unchanged")
        print("SUCCESS: \(files.count + 1) document registration checks passed.")
    }
}
