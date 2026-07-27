import SwiftUI

@main
struct LyraApp: App {
    var body: some Scene {
        WindowGroup("Lyra") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // New Note is handled in the toolbar with ⌘N.
            }
        }
    }
}
