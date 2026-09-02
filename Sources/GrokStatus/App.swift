import AppKit
import GrokStatusCore

@main
enum GrokStatusApp {
    static func main() {
        if CommandLine.arguments.contains("--print") {
            let light = StatusEvaluator().evaluate(home: GrokPaths.home())
            FileHandle.standardOutput.write(Data((light.name + "\n").utf8))
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var store: SessionStore?
    private let installLifetime = InstallLifetime()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installLifetime.start()
        let statusItem = StatusItemController()
        self.statusItem = statusItem

        let store = SessionStore { snapshot in
            // Common modes so the menu can update while it is open
            // (default-mode GCD waits until the menu closes).
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated {
                    statusItem.apply(snapshot)
                }
            }
        }
        self.store = store
        store.start()
    }
}
