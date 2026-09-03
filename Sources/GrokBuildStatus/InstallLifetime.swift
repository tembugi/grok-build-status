import AppKit
import Darwin
import Foundation

/// Clears the login item if the app is moved to Trash or deleted, even when
/// Start on login was left on. Code cannot run if the app is already gone and
/// not launched; the next launch (including from Trash at login) still cleans up.
@MainActor
final class InstallLifetime {
    private var watcher: FolderWatcher?
    private var bundleWatch: DispatchSourceFileSystemObject?
    private var removing = false

    func start() {
        handleIfUninstalled()
        let bundleURL = Bundle.main.bundleURL
        let folder = bundleURL.deletingLastPathComponent().path
        let watcher = FolderWatcher(path: folder, queue: .main) { [weak self] in
            Task { @MainActor in
                self?.handleIfUninstalled()
            }
        }
        watcher.start()
        self.watcher = watcher
        watchBundle(bundleURL)
    }

    private func watchBundle(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .revoke, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleIfUninstalled()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        bundleWatch = source
    }

    deinit {
        bundleWatch?.cancel()
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
