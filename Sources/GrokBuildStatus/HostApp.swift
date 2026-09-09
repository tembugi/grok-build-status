import Foundation

/// Terminal hosts this extra can talk to. English titles stay fixed so the
/// menu does not pick up a localized app name such as Pääte.
enum HostApp: Equatable {
    case terminal
    case iTerm

    init?(bundleID: String) {
        switch bundleID {
        case "com.apple.Terminal": self = .terminal
        case "com.googlecode.iterm2": self = .iTerm
        default: return nil
        }
    }

    var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        }
    }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        }
    }
}
