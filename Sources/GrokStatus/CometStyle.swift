import Foundation

enum CometStyle: String, CaseIterable {
    case planar
    case orbit3D

    var title: String {
        switch self {
        case .planar: "Planar"
        case .orbit3D: "3D orbit"
        }
    }

    private static let defaultsKey = "cometStyle"

    static var current: CometStyle {
        get {
            CometStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .orbit3D
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
