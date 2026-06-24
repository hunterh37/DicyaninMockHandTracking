import SwiftUI

@main
struct GloveDemoApp: App {
    var body: some Scene {
        WindowGroup(id: "control") {
            ContentView()
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "gloves") {
            ImmersiveView()
        }
    }
}
