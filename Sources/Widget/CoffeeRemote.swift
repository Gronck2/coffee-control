import AppKit
import Foundation
import os

private let log = Logger(subsystem: CoffeeShared.appBundleID, category: "control")

/// Sends on/off requests from the sandboxed extension to the app.
enum CoffeeRemote {
    struct Timeout: Error, CustomStringConvertible {
        var description: String { "Coffee Control app did not apply the change in time" }
    }

    /// Opens `coffeecontrol://on|off` (launching the app in the background if
    /// needed) and waits until the app has written the new state, so that the
    /// control reloads with the right value after `perform()` returns.
    static func request(on: Bool) async throws {
        let url = URL(string: "coffeecontrol://\(on ? "on" : "off")")!
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        log.info("request \(url.absoluteString, privacy: .public)")
        _ = try await NSWorkspace.shared.open(url, configuration: config)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if CoffeeState.isActive == on { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        log.error("state did not become \(on ? "on" : "off", privacy: .public)")
        throw Timeout()
    }
}
