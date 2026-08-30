import SwiftUI

@main
struct TrajetApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // El diseño es oscuro a propósito: se mira a contraluz.
                .preferredColorScheme(.dark)
                .tint(Palette.ink)
        }
    }
}
