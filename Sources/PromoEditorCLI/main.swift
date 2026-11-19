import Foundation
import PromoEditorCore

@main
enum PromoEditorCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard
            let projectPath = value(after: "--project", in: arguments),
            let outputPath = value(after: "--output", in: arguments)
        else {
            fputs(
                "Uso: PromoEditorCLI --project archivo.promo.json --output resultado.mp4\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: projectPath))
            let project = try JSONDecoder().decode(PromoProject.self, from: data)
            try await VideoExporter.render(
                clips: project.clips,
                to: URL(fileURLWithPath: outputPath),
                musicURL: project.musicPath.map { URL(fileURLWithPath: $0) },
                musicVolume: project.musicVolume,
                overwriteExistingFile: arguments.contains("--overwrite")
            )
            print("Exportación terminada: \(outputPath)")
        } catch {
            fputs("Error al exportar: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
