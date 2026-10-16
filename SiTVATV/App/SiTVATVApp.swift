import SwiftUI

@main
struct SiTVATVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .focusEffectDisabled()
                .task {
                    await model.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        model.appDidEnterBackground()
                    case .active:
                        Task {
                            await model.appDidBecomeActive()
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
