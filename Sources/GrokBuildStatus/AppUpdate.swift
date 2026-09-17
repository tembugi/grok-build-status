import Foundation
import GrokBuildStatusCore

enum AppUpdateError: Error {
    case badResponse
    case noRelease
    case untrustedURL
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
        return release
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
