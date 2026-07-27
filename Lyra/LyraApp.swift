import SwiftUI

extension Notification.Name {
    static let lyraSaveNote = Notification.Name("lyraSaveNote")
    static let lyraExportPDF = Notification.Name("lyraExportPDF")
}

@main
struct LyraApp: App {
    init() {
        LyraFonts.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("Lyra") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .lyraSaveNote, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Export PDF…") {
                    NotificationCenter.default.post(name: .lyraExportPDF, object: nil)
                }
            }
        }
    }
}
