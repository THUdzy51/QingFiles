import Foundation

@main
struct LidSleepSettingTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
        print("PASS: \(message)")
    }

    static func expectFailure(_ message: String, operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure(message)
        } catch {
            checks += 1
            print("PASS: \(message)")
        }
    }

    static func main() throws {
        expect(try LidSleepSetting.parseStatus("System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1"),
               "read the enabled system-wide sleep override")
        expect(try !LidSleepSetting.parseStatus(" SleepDisabled  0\r\nCurrently in use:\r\n sleep 0 (sleep prevented by powerd)"),
               "idle sleep timers and assertions do not change the override state")
        expect(try !LidSleepSetting.parseStatus("Currently in use:\n sleep 1\n displaysleep 10\n"),
               "an unset system override defaults to normal sleep")
        for text in ["", "unknown output", "SleepDisabled 2", "SleepDisabled",
                     "SleepDisabled 1\nSleepDisabled 0", "SleepDisabled 0 extra", "NotSleepDisabled 1"] {
            expectFailure("reject malformed or ambiguous pmset output") {
                _ = try LidSleepSetting.parseStatus(text)
            }
        }

        var active = false
        var commands: [(String, [String])] = []
        var cancelApproval = false
        var applyChanges = true
        var denyChanges = false
        var unreadable = false
        let setting = LidSleepSetting { executable, arguments in
            commands.append((executable, arguments))
            if executable == "/usr/bin/pmset" {
                precondition(arguments == ["-g"])
                if unreadable { throw LidSleepSetting.Failure.message("Cannot read power settings.") }
                return "System-wide power settings:\n SleepDisabled \(active ? 1 : 0)"
            }
            precondition(executable == "/usr/bin/osascript" && arguments.count == 2 && arguments[0] == "-e")
            if cancelApproval { throw LidSleepSetting.Failure.cancelled }
            if denyChanges { throw LidSleepSetting.Failure.message("Administrator approval was denied.") }
            precondition(arguments[1] == "do shell script \"/usr/bin/pmset -a disablesleep \(active ? 0 : 1)\" with administrator privileges")
            if applyChanges { active.toggle() }
            return ""
        }
        try setting.setEnabled(true)
        expect(active && commands.count == 3, "enable changes only disablesleep and verifies the system result")
        expect(try setting.isEnabled(), "read back enabled state without an app preference")
        try setting.setEnabled(false)
        expect(!active, "disable restores normal system sleep")
        let writes = commands.filter { $0.0 == "/usr/bin/osascript" }.count
        try setting.setEnabled(false)
        expect(commands.filter { $0.0 == "/usr/bin/osascript" }.count == writes,
               "an unchanged setting does not request administrator approval")

        active = true
        expect(try setting.isEnabled(), "reflect a change made outside QingFiles")
        try setting.setEnabled(true)
        expect(commands.filter { $0.0 == "/usr/bin/osascript" }.count == writes,
               "an externally enabled override is already on")
        cancelApproval = true
        do {
            try setting.setEnabled(false)
            preconditionFailure("Cancelled approval succeeded.")
        } catch LidSleepSetting.Failure.cancelled {
            expect(active, "cancelled authorization preserves the actual state")
        }
        cancelApproval = false
        denyChanges = true
        expectFailure("report authorization failures") { try setting.setEnabled(false) }
        expect(active, "failed authorization preserves the enabled override")
        denyChanges = false
        applyChanges = false
        expectFailure("reject a successful command when its setting was not applied") { try setting.setEnabled(false) }
        unreadable = true
        let beforeFailure = commands.count
        expectFailure("a failed preflight read prevents changes") { try setting.setEnabled(false) }
        expect(commands.count == beforeFailure + 1 && commands.last?.0 == "/usr/bin/pmset",
               "an unreadable setting never launches the authorized command")
        print("SUCCESS: \(checks) system sleep setting checks passed without changing macOS power settings.")
    }
}
