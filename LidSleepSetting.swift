import Foundation

/// Reads and changes the system-wide sleep override, including changes made outside QingFiles.
final class LidSleepSetting {
    enum Failure: LocalizedError {
        case cancelled
        case message(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Administrator approval was cancelled."
            case .message(let text): return text
            }
        }
    }

    private let run: (String, [String]) throws -> String

    init(run: @escaping (String, [String]) throws -> String = LidSleepSetting.runCommand) {
        self.run = run
    }

    func isEnabled() throws -> Bool {
        try Self.parseStatus(run("/usr/bin/pmset", ["-g"]))
    }

    func setEnabled(_ enabled: Bool) throws {
        guard try isEnabled() != enabled else { return }
        let value = enabled ? "1" : "0"
        // Only a fixed command and a Boolean reach the administrator-authorized shell.
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        _ = try run("/usr/bin/osascript", ["-e", script])
        guard try isEnabled() == enabled else {
            throw Failure.message("macOS did not apply the requested sleep setting. Open Settings again to check its current state.")
        }
    }

    static func parseStatus(_ output: String) throws -> Bool {
        let lines = output.components(separatedBy: .newlines).map {
            $0.split(whereSeparator: \.isWhitespace)
        }
        let flags = lines.filter { $0.first == "SleepDisabled" }
        if let flag = flags.first {
            guard flags.count == 1, flag.count == 2, ["0", "1"].contains(flag[1]) else {
                throw Failure.message("macOS returned an unsupported SleepDisabled value.")
            }
            return flag[1] == "1"
        }
        // pmset omits SleepDisabled when the system-wide override has never been set.
        guard output.contains("Currently in use:"), lines.contains(where: { $0.first == "sleep" && $0.count >= 2 }) else {
            throw Failure.message("Could not read the system sleep setting from pmset.")
        }
        return false
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            if executable == "/usr/bin/osascript", text.contains("(-128)") {
                throw Failure.cancelled
            }
            throw Failure.message(text.isEmpty ? "The system sleep command failed. Try again." : String(text.prefix(2000)))
        }
        return text
    }
}
