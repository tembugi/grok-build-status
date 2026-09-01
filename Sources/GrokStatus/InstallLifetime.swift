import AppKit
import Foundation

/// Clears the login item if the app is moved to Trash or deleted, even when
/// Start on login was left on. Code cannot run if the app is already gone and
/// not launched; the next launch (including from Trash at login) still cleans up.
@MainActor
final class InstallLifetime {
    private var watcher: FolderWatcher?
    private var timer: Timer?
    private var removing = false

    func start() {
        handleIfUninstalled()
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
        let watcher = FolderWatcher(path: folder, queue: .main) { [weak self] in
            Task { @MainActor in
                self?.handleIfUninstalled()
            }
        }
        watcher.start()
        self.watcher = watcher

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleIfUninstalled()
            }
        }
        timer?.tolerance = 1
    }

    private func handleIfUninstalled() {
        guard !removing else { return }
        guard Self.isUninstalled else { return }
        removing = true
        try? LoginItem.setEnabled(false)
        NSApp.terminate(nil)
    }

    private static var isUninstalled: Bool {
        let url = Bundle.main.bundleURL
        let path = url.path
        if path.contains("/.Trash/") || path.contains("/Trash/") {
            return true
        }
        if let trash = try? FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: false
        ), path.hasPrefix(trash.path) {
            return true
        }
        return !FileManager.default.fileExists(atPath: path)
    }
}
