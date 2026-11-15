import Foundation

/// Owns only WeChat's NSFileViewer preference and QingFiles' restoration record.
final class WeChatRevealSetting {
    private struct Backup: Codable {
        let previousViewer: String?
    }

    private let domain: String
    private let storage: UserDefaults
    private let bundleIdentifier: String
    private let backupKey = "weChatRevealBackup.v1"

    init(domain: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.tencent.xinWeChat/Data/Library/Preferences/com.tencent.xinWeChat").path,
         storage: UserDefaults = .standard,
         bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "local.qingfiles.app") {
        self.domain = domain
        self.storage = storage
        self.bundleIdentifier = bundleIdentifier
    }

    func isEnabled() throws -> Bool { try currentViewer() == bundleIdentifier }

    func setEnabled(_ enabled: Bool) throws {
        let current = try currentViewer()
        if enabled {
            guard current != bundleIdentifier else { return }
            let data = try PropertyListEncoder().encode(Backup(previousViewer: current))
            storage.set(data, forKey: backupKey)
            guard storage.synchronize() else {
                throw FileServiceError.invalid("Could not save the previous file viewer setting. Try again.")
            }
            try writeViewer(bundleIdentifier)
        } else {
            let data = storage.data(forKey: backupKey)
            let backup = try data.map { try PropertyListDecoder().decode(Backup.self, from: $0) }
            // Preserve a setting changed outside QingFiles after this feature was enabled.
            if current == bundleIdentifier { try writeViewer(backup?.previousViewer) }
            storage.removeObject(forKey: backupKey)
            storage.synchronize()
        }
    }

    private func currentViewer() throws -> String? {
        let data = try defaults(["export", domain, "-"])
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw FileServiceError.invalid("WeChat's preferences could not be read.")
        }
        guard let value = values["NSFileViewer"] else { return nil }
        guard let viewer = value as? String else {
            throw FileServiceError.invalid("WeChat's file viewer preference has an unsupported format.")
        }
        return viewer
    }

    private func writeViewer(_ viewer: String?) throws {
        if let viewer { _ = try defaults(["write", domain, "NSFileViewer", "-string", viewer]) }
        else { _ = try defaults(["delete", domain, "NSFileViewer"]) }
        guard try currentViewer() == viewer else {
            throw FileServiceError.invalid("The file viewer setting could not be verified. Try again.")
        }
    }

    private func defaults(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FileServiceError.invalid("Cannot access WeChat's preferences. Open WeChat once and check that QingFiles can access its settings, then try again.")
        }
        return data
    }
}
