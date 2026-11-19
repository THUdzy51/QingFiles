import AppKit

@main
struct SettingsSleepTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
        print("PASS: \(message)")
    }

    static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(condition(), "Settings did not finish updating.")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QingFiles-SleepSettings-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let domain = root.appendingPathComponent("wechat")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["unrelated": true], format: .xml, options: 0)
        try plist.write(to: domain.appendingPathExtension("plist"))
        let suiteName = "local.qingfiles.sleep-ui-tests.\(UUID())"
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }

        var active = false
        var cancel = false
        var readFailure = false
        var applyChanges = true
        let power = LidSleepSetting { executable, arguments in
            if executable == "/usr/bin/pmset" {
                if readFailure { throw LidSleepSetting.Failure.message("Cannot read the fixture sleep setting.") }
                return "SleepDisabled \(active ? 1 : 0)"
            }
            precondition(executable == "/usr/bin/osascript")
            if cancel { throw LidSleepSetting.Failure.cancelled }
            if applyChanges { active = arguments[1].contains("disablesleep 1") }
            return ""
        }
        let finder = FinderFolderOpening(canOpen: { false }, openFolder: { _ in })
        let settings = SettingsWindow(finderFolderOpening: finder,
                                      setting: WeChatRevealSetting(domain: domain.path, storage: storage),
                                      lidSleep: power)
        settings.showWindow(nil)
        let window = settings.window!
        defer { window.orderOut(nil) }
        let controls = descendants(window.contentView!)
        let control = controls.compactMap { $0 as? NSSwitch }.first!
        func textContains(_ value: String) -> Bool {
            controls.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains(value) }
        }
        func request(_ state: NSControl.StateValue) {
            control.state = state
            precondition(app.sendAction(control.action!, to: control.target, from: control))
        }
        wait { control.isEnabled }
        expect(control.state == .off, "Settings starts from the current macOS sleep state")
        expect(textContains("until switched off") && textContains("administrator approval"),
               "the switch explains persistence and administrator approval")
        window.contentView!.layoutSubtreeIfNeeded()
        let frame = window.contentView!.convert(control.bounds, from: control)
        expect(window.contentView!.bounds.contains(frame), "the sleep switch fits inside Settings")

        request(.on)
        expect(!control.isEnabled && control.state == .off && settings.isChangingSleepSetting,
               "a pending change keeps the verified state and prevents repeated requests")
        wait { control.isEnabled }
        expect(active && control.state == .on && !settings.isChangingSleepSetting, "successful enable updates the switch")

        cancel = true
        request(.off)
        wait { control.isEnabled }
        expect(active && control.state == .on && textContains("cancelled"),
               "cancelled authorization restores the verified state")
        cancel = false
        applyChanges = false
        request(.off)
        wait { control.isEnabled }
        expect(active && control.state == .on && textContains("did not apply"),
               "an unapplied change is reported without displaying success")
        applyChanges = true
        request(.off)
        wait { control.isEnabled }
        expect(!active && control.state == .off, "successful disable restores normal sleep")

        active = true
        settings.refreshSleepSetting()
        wait { control.isEnabled }
        expect(control.state == .on, "Settings reflects changes made outside QingFiles")
        readFailure = true
        settings.refreshSleepSetting()
        wait { textContains("Cannot read the fixture sleep setting.") }
        expect(!control.isEnabled, "an unreadable setting disables changes")
        readFailure = false
        settings.refreshSleepSetting()
        wait { control.isEnabled }
        expect(control.state == .on, "a subsequent refresh recovers from a read failure")

        // Only rendering and fixture commands run here. No real power setting is changed.
        if let path = ProcessInfo.processInfo.environment["QINGFILES_SETTINGS_SNAPSHOT"] {
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        print("SUCCESS: \(checks) Settings sleep switch checks passed.")
    }
}
