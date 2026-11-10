import Foundation
import IOKit.pwr_mgt

/// Holds the power assertions that keep the Mac awake.
///
/// Same effect as `caffeinate -d -i`: prevents idle display sleep and idle
/// system sleep. The assertions are tied to this process, so they disappear
/// when it exits or crashes. Other assertions (for example a `caffeinate`
/// running in a terminal) are independent and never touched.
@MainActor
final class PowerKeeper {
    static let shared = PowerKeeper()

    /// Called after every state change, used to reload the Control Center control.
    var onChange: (@MainActor (Bool) -> Void)?

    private var assertionIDs: [IOPMAssertionID] = []
    private var since: Date?

    var isOn: Bool { !assertionIDs.isEmpty }

    private init() {}

    func set(on: Bool) throws {
        if on {
            try turnOn()
        } else {
            turnOff()
        }
        try persist()
        onChange?(isOn)
    }

    func toggle() throws {
        try set(on: !isOn)
    }

    /// Writes the current state for the control extension.
    func persist() throws {
        let state = CoffeeState(
            on: isOn,
            pid: ProcessInfo.processInfo.processIdentifier,
            since: since
        )
        try state.save()
    }

    private func turnOn() throws {
        guard assertionIDs.isEmpty else { return }
        let types = [
            kIOPMAssertionTypePreventUserIdleDisplaySleep,  // caffeinate -d
            kIOPMAssertionTypePreventUserIdleSystemSleep,   // caffeinate -i
        ]
        var created: [IOPMAssertionID] = []
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                CoffeeShared.assertionName as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                created.forEach { IOPMAssertionRelease($0) }
                throw PowerKeeperError.assertionFailed(type: type, code: result)
            }
            created.append(id)
        }
        assertionIDs = created
        since = Date()
    }

    private func turnOff() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs = []
        since = nil
    }
}

enum PowerKeeperError: Error, CustomStringConvertible {
    case assertionFailed(type: String, code: IOReturn)

    var description: String {
        switch self {
        case let .assertionFailed(type, code):
            return "IOPMAssertionCreateWithName(\(type)) failed: \(String(format: "0x%08x", code))"
        }
    }
}
