import SwiftUI

@main
struct PromoEditorApp: App {
    @StateObject private var editor: EditorModel

    init() {
        let hasProjectArgument = CommandLine.arguments.contains("--project")
        let model = EditorModel(shouldAutoLoadDefaultFolder: !hasProjectArgument)
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--project"),
           CommandLine.arguments.indices.contains(argumentIndex + 1) {
            model.openProject(at: URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1]))
        }
        _editor = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(editor)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}
