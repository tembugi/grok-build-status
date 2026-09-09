import AppKit

enum AppleScript {
    static func string(from script: NSAppleScript?) -> String? {
        guard let script else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error == nil, let text = result.stringValue, !text.isEmpty {
            return text
        }
        return nil
    }

    static func string(fromSource source: String) -> String? {
        if let text = string(from: NSAppleScript(source: source)) {
            return text
        }
        return osascript(source)
    }

    private static func osascript(_ source: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
