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

        if CommandLine.arguments.contains("--uninstall") {
            try? LoginItem.setEnabled(false)
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
    private var monitor: GrokMonitor?
    private let installLifetime = InstallLifetime()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installLifetime.start()
        let statusItem = StatusItemController()
        statusItem.setLight(StatusEvaluator().evaluate(home: GrokPaths.home()))
        self.statusItem = statusItem

        let monitor = GrokMonitor { light in
            DispatchQueue.main.async {
                statusItem.setLight(light)
            }
        }
        self.monitor = monitor
        monitor.start()
    }
}
