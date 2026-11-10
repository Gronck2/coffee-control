import AppIntents
import Foundation

/// Action of the Control Center toggle.
///
/// Compiled into both the app and the control extension. The system runs it in
/// the extension (`openAppWhenRun = false`): running it in the app process
/// (`openAppWhenRun = true`) needs a team-signed app, because linkd rejects
/// ad-hoc signed clients ("requiresValidatedBundle", "Unable to get teamId").
/// The extension cannot hold a power assertion itself (sandboxed, short-lived),
/// so it forwards the request to the app through the `coffeecontrol://` URL
/// scheme, which also launches the app if it is not running.
struct ToggleCoffeeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Turns Coffee Control on or off.")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "Awake")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        #if COFFEE_APP
        try await PowerKeeper.shared.set(on: value)
        #else
        try await CoffeeRemote.request(on: value)
        #endif
        return .result()
    }
}
