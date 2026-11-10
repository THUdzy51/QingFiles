import Foundation
// OpenSSH invokes this helper only for authentication, never host trust.
let prompt = CommandLine.arguments.dropFirst().joined(separator: " ").lowercased()
if prompt.contains("password") || prompt.contains("passphrase") {
    let value = ProcessInfo.processInfo.environment["QINGFILES_PASSWORD"] ?? ""
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
} else { exit(1) }
