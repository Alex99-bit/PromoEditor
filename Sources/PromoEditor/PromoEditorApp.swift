import SwiftUI

@main
struct PromoEditorApp: App {
    @StateObject private var editor = EditorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(editor)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}
