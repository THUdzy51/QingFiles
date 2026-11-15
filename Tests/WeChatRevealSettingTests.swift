import Foundation

@main
struct WeChatRevealSettingTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
        print("PASS: \(message)")
    }

    static func main() throws {
        setbuf(stdout, nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QingFiles-Settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let domain = root.appendingPathComponent("wechat").path
        let suiteName = "local.qingfiles.setting-tests.\(UUID().uuidString)"
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let setting = WeChatRevealSetting(domain: domain, storage: storage, bundleIdentifier: "local.qingfiles.app")
        func write(_ arguments: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            p.arguments = arguments
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            precondition(p.terminationStatus == 0)
        }
        func values() throws -> [String: Any] {
            let p = Process()
            let output = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            p.arguments = ["export", domain, "-"]
            p.standardOutput = output
            try p.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        }
        try write(["write", domain, "unrelated", "-string", "preserve me"])
        expect(try !setting.isEnabled(), "the setting is off when WeChat has no viewer override")
        try setting.setEnabled(true)
        expect(try setting.isEnabled(), "enabling persists the QingFiles viewer in the target preference domain")
        let reopened = WeChatRevealSetting(domain: domain, storage: storage, bundleIdentifier: "local.qingfiles.app")
        expect(try reopened.isEnabled(), "the enabled state survives recreating the settings controller")
        try reopened.setEnabled(true)
        try reopened.setEnabled(false)
        expect(try values()["NSFileViewer"] == nil, "disable restores an originally absent preference after repeated enable")
        expect(try values()["unrelated"] as? String == "preserve me", "other WeChat preferences are preserved")

        try write(["write", domain, "NSFileViewer", "-string", "com.example.previous-viewer"])
        try setting.setEnabled(true)
        try reopened.setEnabled(false)
        expect(try values()["NSFileViewer"] as? String == "com.example.previous-viewer", "disable restores the exact previous viewer across controller recreation")
        try setting.setEnabled(true)
        try write(["write", domain, "NSFileViewer", "-string", "com.example.new-viewer"])
        try setting.setEnabled(false)
        expect(try values()["NSFileViewer"] as? String == "com.example.new-viewer", "disable preserves a viewer selected outside QingFiles")

        try write(["write", domain, "NSFileViewer", "-int", "42"])
        do {
            try setting.setEnabled(true)
            preconditionFailure("invalid preference type was overwritten")
        } catch {
            expect(try values()["NSFileViewer"] as? Int == 42, "an unsupported preference fails without overwriting it")
        }
        let newDomain = WeChatRevealSetting(domain: root.appendingPathComponent("new-domain").path,
                                           storage: storage, bundleIdentifier: "local.qingfiles.app")
        try newDomain.setEnabled(true)
        expect(try newDomain.isEnabled(), "a previously empty preference domain can be configured")
        try newDomain.setEnabled(false)
        let blockedParent = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedParent)
        let unavailable = WeChatRevealSetting(domain: blockedParent.appendingPathComponent("wechat").path,
                                             storage: storage, bundleIdentifier: "local.qingfiles.app")
        do {
            try unavailable.setEnabled(true)
            preconditionFailure("inaccessible domain was modified")
        } catch {
            expect(!FileManager.default.fileExists(atPath: blockedParent.appendingPathComponent("wechat.plist").path),
                   "a write failure is reported without changing an inaccessible domain")
        }
        print("SUCCESS: \(checks) persistent reveal setting checks passed.")
    }
}
