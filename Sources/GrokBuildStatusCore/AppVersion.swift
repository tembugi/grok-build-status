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

    public init(tag: String, version: SemanticVersion) {
        self.tag = tag
        self.version = version
    }

    /// Latest published release. Prereleases are ignored.
    public static func parseLatest(from data: Data) -> GitHubRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if object["prerelease"] as? Bool == true { return nil }
        guard let tag = object["tag_name"] as? String, let version = SemanticVersion(tag) else {
            return nil
        }
        return GitHubRelease(tag: tag, version: version)
    }
}

/// Menu version row: label, Update pill, tooltip.
public struct VersionLine: Equatable, Sendable {
    public var label: String
    public var showUpdate: Bool
    public var toolTip: String?

    /// Failed check with no release must not say `(current)`.
    public static func make(
        installed: SemanticVersion,
        latest: GitHubRelease?,
        checking: Bool,
        failed: Bool
    ) -> VersionLine {
        if let latest, latest.version > installed {
            return VersionLine(
                label: "v.\(installed.display) (\(latest.version.display) available)",
                showUpdate: true,
                toolTip: "Open the GitHub releases page."
            )
        }
        if latest == nil, checking {
            return VersionLine(
                label: "v.\(installed.display)",
                showUpdate: false,
                toolTip: nil
            )
        }
        if latest == nil, failed {
            return VersionLine(
                label: "v.\(installed.display)",
                showUpdate: false,
                toolTip: "Could not reach GitHub releases."
            )
        }
        return VersionLine(
            label: "v.\(installed.display) (current)",
            showUpdate: false,
            toolTip: nil
        )
    }
}
