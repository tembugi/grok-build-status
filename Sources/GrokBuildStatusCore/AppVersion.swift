import Foundation

public struct SemanticVersion: Equatable, Comparable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `1.0.0`, `v1.0.0`, and `v.1.0.1`.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: true)
        let numbers = parts.prefix(3).map { Int($0) }
        guard numbers.count >= 1, numbers.allSatisfy({ $0 != nil }) else { return nil }
        let values = numbers.compactMap { $0 }
        self.major = values[0]
        self.minor = values.count > 1 ? values[1] : 0
        self.patch = values.count > 2 ? values[2] : 0
    }

    public var display: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct GitHubRelease: Equatable, Sendable {
    public var tag: String
    public var version: SemanticVersion
    public var dmgURL: URL
    public var dmgBytes: Int

    public init(tag: String, version: SemanticVersion, dmgURL: URL, dmgBytes: Int) {
        self.tag = tag
        self.version = version
        self.dmgURL = dmgURL
        self.dmgBytes = dmgBytes
    }

    public static let dmgName = "GrokBuildStatus.dmg"

    /// Latest published release that ships `GrokBuildStatus.dmg`.
    public static func parseLatest(from data: Data) -> GitHubRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if object["prerelease"] as? Bool == true { return nil }
        guard let tag = object["tag_name"] as? String, let version = SemanticVersion(tag) else {
            return nil
        }
        guard let assets = object["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            guard asset["name"] as? String == dmgName else { continue }
            guard let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString)
            else { continue }
            let size = (asset["size"] as? Int) ?? (asset["size"] as? Double).map(Int.init) ?? 0
            return GitHubRelease(tag: tag, version: version, dmgURL: url, dmgBytes: size)
        }
        return nil
    }
}

public enum DownloadSafety {
    /// GitHub API and release-asset hosts only.
    public static func isTrustedGitHub(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host == "githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }
}
