import AppKit
import os
import WidgetKit

let log = Logger(subsystem: CoffeeShared.appBundleID, category: "app")

/// Agent app without a window or Dock icon (`LSUIElement`).
///
/// Ways to control it:
/// - the Control Center toggle (runs `ToggleCoffeeIntent` in this process);
/// - URLs: `open coffeecontrol://on`, `coffeecontrol://off`, `coffeecontrol://toggle`
///   (handy for testing and as a Shortcuts fallback);
/// - quitting the app (`osascript -e 'quit app "CoffeeControl"'`) turns it off.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let keeper = PowerKeeper.shared
        keeper.onChange = { on in
            log.info("keep awake: \(on ? "on" : "off", privacy: .public)")
            ControlCenter.shared.reloadControls(ofKind: CoffeeShared.controlKind)
        }
        // A fresh process holds no assertions: overwrite whatever an earlier
        // run left behind, unless an intent already turned us on.
        do {
            try keeper.persist()
        } catch {
            log.error("cannot write state: \(String(describing: error), privacy: .public)")
        }
        ControlCenter.shared.reloadControls(ofKind: CoffeeShared.controlKind)
        installSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutDown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "coffeecontrol" else { return }
        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let keeper = PowerKeeper.shared
        do {
            switch command {
            case "on": try keeper.set(on: true)
            case "off": try keeper.set(on: false)
            case "toggle": try keeper.toggle()
            case "quit": NSApp.terminate(nil)
            default: log.error("unknown command: \(url.absoluteString, privacy: .public)")
            }
        } catch {
            log.error("\(command, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// `kill` / `killall` must also leave a correct state file behind.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutDown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private var didShutDown = false

    private func shutDown() {
        guard !didShutDown else { return }
        didShutDown = true
        let keeper = PowerKeeper.shared
        keeper.onChange = nil
        try? keeper.set(on: false)
        try? CoffeeState.off.save()
        ControlCenter.shared.reloadControls(ofKind: CoffeeShared.controlKind)
    }
}
