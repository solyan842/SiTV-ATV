import SwiftUI

@main
struct SiTVATVApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // SiTV draws its own Android-parity card/group selectors.
                // Disable tvOS's automatic white focus ring/hover bloom for
                // this whole hierarchy so it cannot spill outside channel rows.
                .focusEffectDisabled()
                .task {
                    await model.bootstrap()
                }
        }
    }
}
