import AppKit
import GrokBuildStatusCore

enum AppUpdateError: Error {
    case badResponse
    case noRelease
    case untrustedURL
    case tooLarge
    case notInApplications
    case mountFailed
    case invalidApp
    case notNewer
    case installFailed
}

/// Fetches the GitHub release and replaces the app in Applications.
enum AppUpdate {
    static let latestAPI = URL(string: "https://api.github.com/repos/tembugi/grok-build-status/releases/latest")!
    static let maxDMGBytes = 20 * 1_048_576
    static let appFileName = "Grok Build Status.app"

    /// Info.plist version. Install never uses a pretended number.
    static var installedVersion: SemanticVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return SemanticVersion(raw ?? "") ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    /// `--pretend-version 1.0.0` lies to the menu so Update can be laid out.
    static var pretendVersion: SemanticVersion? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--pretend-version") else { return nil }
        let value = args.index(after: flag)
        guard value < args.endIndex else { return nil }
        return SemanticVersion(args[value])
    }

    static var current: SemanticVersion {
        pretendVersion ?? installedVersion
    }

    static var installedInApplications: Bool {
        LoginItem.isInstalledInApplications
    }

    static func fetchLatest() async throws -> GitHubRelease {
        guard DownloadSafety.isTrustedGitHub(latestAPI) else {
            throw AppUpdateError.untrustedURL
        }
        var request = URLRequest(url: latestAPI)
        request.setValue("GrokBuildStatus/\(installedVersion.display)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await GitHubHTTP.shared.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppUpdateError.badResponse
        }
        guard let release = GitHubRelease.parseLatest(from: data) else {
            throw AppUpdateError.noRelease
        }
        guard DownloadSafety.isTrustedGitHub(release.dmgURL) else {
            throw AppUpdateError.untrustedURL
        }
        if release.dmgBytes > maxDMGBytes {
            throw AppUpdateError.tooLarge
        }
        return release
    }

    /// Downloads, verifies, and schedules a replace after this process exits.
    static func install(_ release: GitHubRelease) async throws {
        guard installedInApplications else { throw AppUpdateError.notInApplications }
        guard release.version > installedVersion else { throw AppUpdateError.notNewer }
        guard DownloadSafety.isTrustedGitHub(release.dmgURL) else { throw AppUpdateError.untrustedURL }

        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(appFileName)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("gbs-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var mounted: URL?
        do {
            let dmg = try await downloadDMG(release, to: work)
            let volume = try attach(dmg)
            mounted = volume
            let payload = volume.appendingPathComponent(appFileName)
            try verify(app: payload, expecting: release.version)
            stripQuarantine(payload)
            let staged = work.appendingPathComponent(appFileName)
            try ditto(from: payload, to: staged)
            try verify(app: staged, expecting: release.version)
            stripQuarantine(staged)
            try? detach(volume)
            mounted = nil
            try launchReplacer(from: staged, to: dest)
        } catch {
            if let mounted { try? detach(mounted) }
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    private static func downloadDMG(_ release: GitHubRelease, to work: URL) async throws -> URL {
        let (temp, response) = try await GitHubHTTP.shared.session.download(from: release.dmgURL)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppUpdateError.badResponse
        }
        if let url = http.url, !DownloadSafety.isTrustedGitHub(url) {
            throw AppUpdateError.untrustedURL
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: temp.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maxDMGBytes else { throw AppUpdateError.tooLarge }
        let dmg = work.appendingPathComponent(GitHubRelease.dmgName)
        try FileManager.default.moveItem(at: temp, to: dmg)
        return dmg
    }

    private static func verify(app: URL, expecting version: SemanticVersion) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: app.path, isDirectory: &isDir), isDir.boolValue else {
            throw AppUpdateError.invalidApp
        }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard let info else { throw AppUpdateError.invalidApp }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw AppUpdateError.invalidApp
        }
        guard let raw = info["CFBundleShortVersionString"] as? String,
              let found = SemanticVersion(raw),
              found == version,
              found > installedVersion
        else {
            throw AppUpdateError.notNewer
        }
        let executable = (info["CFBundleExecutable"] as? String) ?? "GrokBuildStatus"
        let binary = app.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw AppUpdateError.invalidApp
        }
    }

    private static func attach(_ dmg: URL) throws -> URL {
        let text = try run(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", dmg.path]
        )
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            if let range = line.range(of: "/Volumes/") {
                let path = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        throw AppUpdateError.mountFailed
    }

    private static func detach(_ volume: URL) throws {
        _ = try run("/usr/bin/hdiutil", ["detach", volume.path, "-quiet"])
    }

    private static func ditto(from: URL, to: URL) throws {
        _ = try run("/usr/bin/ditto", [from.path, to.path])
    }

    private static func stripQuarantine(_ url: URL) {
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path])
    }

    private static func launchReplacer(from staged: URL, to dest: URL) throws {
        let script = staged.deletingLastPathComponent().appendingPathComponent("replace.sh")
        let body = """
        #!/bin/bash
        set -euo pipefail
        PID="$1"
        SRC="$2"
        DEST="$3"
        for _ in $(seq 1 80); do
          if ! /bin/kill -0 "$PID" 2>/dev/null; then
            break
          fi
          sleep 0.1
        done
        sleep 0.2
        /bin/rm -rf "$DEST"
        /usr/bin/ditto "$SRC" "$DEST"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" || true
        /usr/bin/open "$DEST"
        /bin/rm -rf "$(dirname "$SRC")"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = [
            "/bin/bash",
            script.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            staged.path,
            dest.path,
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }

    private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            throw AppUpdateError.installFailed
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw AppUpdateError.installFailed }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

private final class GitHubHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = GitHubHTTP()

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "GrokBuildStatus/\(AppUpdate.installedVersion.display)",
            "Accept": "application/vnd.github+json",
        ]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, DownloadSafety.isTrustedGitHub(url) else { return nil }
        return request
    }
}
