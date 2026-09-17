import Foundation
import GrokBuildStatusCore

enum AppUpdateError: Error {
    case badResponse
    case noRelease
}

/// Fetches the GitHub release so the menu can offer the releases page.
enum AppUpdate {
    static let latestAPI = URL(string: "https://api.github.com/repos/tembugi/grok-build-status/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/tembugi/grok-build-status/releases")!

    /// Info.plist version.
    static var installedVersion: SemanticVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return SemanticVersion(raw ?? "") ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    static func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: latestAPI)
        request.setValue("GrokBuildStatus/\(installedVersion.display)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await GitHubHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppUpdateError.badResponse
        }
        guard let release = GitHubRelease.parseLatest(from: data) else {
            throw AppUpdateError.noRelease
        }
        return release
    }
}

private enum GitHubHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "GrokBuildStatus/\(AppUpdate.installedVersion.display)",
            "Accept": "application/vnd.github+json",
        ]
        return URLSession(configuration: config)
    }()
}
