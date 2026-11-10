import AppIntents
import SwiftUI
import WidgetKit

@main
struct CoffeeControlExtension: WidgetBundle {
    var body: some Widget {
        CoffeeControl()
    }
}

/// Control Center toggle: a cup with steam when the Mac is kept awake,
/// an empty cup when sleep is allowed.
struct CoffeeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: CoffeeShared.controlKind, provider: Provider()) { isOn in
            ControlWidgetToggle("Coffee", isOn: isOn, action: ToggleCoffeeIntent()) { isOn in
                Label(
                    isOn ? "Awake" : "Off",
                    systemImage: isOn ? "cup.and.heat.waves.fill" : "cup.and.saucer"
                )
            }
            .tint(.orange)
        }
        .displayName("Coffee Control")
        .description("Keeps this Mac awake while it is on.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            CoffeeState.isActive
        }
    }
}
