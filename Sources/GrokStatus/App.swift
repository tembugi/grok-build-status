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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var monitor: GrokMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
