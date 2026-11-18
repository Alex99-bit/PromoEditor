import AppKit
import AVFoundation
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    @Published var library: [MediaClip] = []
    @Published var timeline: [TimelineClip] = []
    @Published var previewURL: URL?
    @Published var selectedLibraryPath: String?
    @Published var selectedTimelineID: UUID?
    @Published var sourceFolderURL: URL?
    @Published var isLoading = false
    @Published var isExporting = false
    @Published var statusMessage = "Abre una carpeta de videos para empezar."
    @Published var alertMessage: String?

    init() {
        let firstRunFolder = URL(fileURLWithPath: "/Volumes/AlexCoSSD/Videos/Limpieza/Seleccionados")
        if FileManager.default.fileExists(atPath: firstRunFolder.path) {
            loadFolder(firstRunFolder)
        }
    }

    var totalDuration: Double {
        timeline.reduce(0) { $0 + $1.selectedDuration }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Elige una carpeta de videos"
        panel.message = "Se cargarán los videos compatibles de esta carpeta."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let sourceFolderURL { panel.directoryURL = sourceFolderURL }
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    func loadFolder(_ folder: URL) {
        isLoading = true
        statusMessage = "Buscando videos…"
        sourceFolderURL = folder

        Task {
            let videos = await Task.detached(priority: .userInitiated) {
                await Self.scanVideos(in: folder)
            }.value
            library = videos
            isLoading = false
            statusMessage = videos.isEmpty
                ? "No encontré videos compatibles en esta carpeta."
                : "\(videos.count) videos listos."
            if timeline.isEmpty, let first = videos.first {
                selectForPreview(first)
            }
        }
    }

    nonisolated private static func scanVideos(in folder: URL) async -> [MediaClip] {
        let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return await urls
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .asyncCompactMap { url in
                do {
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration)
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
                    let naturalSize = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)

                    let seconds = CMTimeGetSeconds(duration)
                    guard seconds.isFinite, seconds > 0 else { return nil }
                    let displayedSize = CGRect(origin: .zero, size: naturalSize).applying(transform)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 320, height: 480)
                    let sampleTime = CMTime(seconds: min(seconds * 0.4, max(0, seconds - 0.05)), preferredTimescale: 600)
                    let thumbnailData: Data?
                    if let image = try? generator.copyCGImage(at: sampleTime, actualTime: nil) {
                        let data = NSMutableData()
                        if let destination = CGImageDestinationCreateWithData(
                            data,
                            UTType.jpeg.identifier as CFString,
                            1,
                            nil
                        ) {
                            CGImageDestinationAddImage(destination, image, nil)
                            if CGImageDestinationFinalize(destination) {
                                thumbnailData = data as Data
                            } else {
                                thumbnailData = nil
                            }
                        } else {
                            thumbnailData = nil
                        }
                    } else {
                        thumbnailData = nil
                    }

                    return MediaClip(
                        url: url,
                        duration: seconds,
                        width: Int(abs(displayedSize.width)),
                        height: Int(abs(displayedSize.height)),
                        thumbnailData: thumbnailData
                    )
                } catch {
                    return nil
                }
            }
    }

    func selectForPreview(_ clip: MediaClip) {
        selectedLibraryPath = clip.url.path
        previewURL = clip.url
    }

    func selectForPreview(_ clip: TimelineClip) {
        selectedTimelineID = clip.id
        previewURL = clip.url
    }

    func addToTimeline(_ media: MediaClip) {
        let clip = TimelineClip(media: media)
        timeline.append(clip)
        selectedTimelineID = clip.id
        previewURL = media.url
        statusMessage = "Añadido: \(media.name)"
    }

    func removeFromTimeline(_ clip: TimelineClip) {
        timeline.removeAll { $0.id == clip.id }
        if selectedTimelineID == clip.id {
            selectedTimelineID = timeline.last?.id
            if let next = timeline.last { previewURL = next.url }
        }
        statusMessage = "Toma quitada de la secuencia."
    }

    func move(_ clip: TimelineClip, by offset: Int) {
        guard let index = timeline.firstIndex(where: { $0.id == clip.id }) else { return }
        let destination = index + offset
        guard timeline.indices.contains(destination) else { return }
        timeline.swapAt(index, destination)
    }

    func updateTrim(for clip: TimelineClip, start: Double, end: Double) {
        guard let index = timeline.firstIndex(where: { $0.id == clip.id }) else { return }
        let safeStart = max(0, min(start, max(0, clip.duration - 0.1)))
        timeline[index].trimStart = safeStart
        timeline[index].trimEnd = min(clip.duration, max(safeStart + 0.1, end))
        statusMessage = "Recorte actualizado: \(clip.name)"
    }

    func saveProject() {
        let panel = NSSavePanel()
        panel.title = "Guarda el proyecto de edición"
        panel.nameFieldStringValue = "PromoEditor.promo.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project = PromoProject(sourceFolderPath: sourceFolderURL?.path, clips: timeline)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(project).write(to: url, options: .atomic)
            statusMessage = "Proyecto guardado."
        } catch {
            alertMessage = "No pude guardar el proyecto: \(error.localizedDescription)"
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Abre un proyecto de Promo Editor"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project = try JSONDecoder().decode(PromoProject.self, from: Data(contentsOf: url))
            timeline = project.clips.filter { FileManager.default.fileExists(atPath: $0.sourcePath) }
            sourceFolderURL = project.sourceFolderPath.map { URL(fileURLWithPath: $0) }
            selectedTimelineID = timeline.first?.id
            previewURL = timeline.first?.url
            statusMessage = "Proyecto abierto · \(timeline.count) tomas."
            if let sourceFolderURL { loadFolder(sourceFolderURL) }
        } catch {
            alertMessage = "No pude abrir ese proyecto: \(error.localizedDescription)"
        }
    }

    func exportPromo() {
        guard !timeline.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Exporta tu promocional vertical"
        panel.nameFieldStringValue = "promocional-vertical.mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isExporting = true
        statusMessage = "Preparando el video…"
        let clips = timeline
        Task {
            do {
                try await Self.render(clips: clips, to: outputURL)
                statusMessage = "Exportación terminada · \(outputURL.lastPathComponent)"
            } catch {
                alertMessage = "No se pudo exportar el video: \(error.localizedDescription)"
                statusMessage = "La exportación no se completó."
            }
            isExporting = false
        }
    }

    nonisolated private static func render(clips: [TimelineClip], to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let videoCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.couldNotCreateTrack
        }

        let audioCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let canvas = CGSize(width: 1080, height: 1920)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = tracks.first else { continue }
            let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let start = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
            let duration = CMTime(seconds: clip.selectedDuration, preferredTimescale: 600)
            guard CMTimeGetSeconds(duration) > 0.05 else { continue }
            let range = CMTimeRange(start: start, duration: duration)

            try videoCompositionTrack.insertTimeRange(range, of: sourceVideoTrack, at: cursor)
            if let sourceAudioTrack, let audioCompositionTrack {
                try? audioCompositionTrack.insertTimeRange(range, of: sourceAudioTrack, at: cursor)
            }

            let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let normalized = preferredTransform.concatenating(
                CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
            )
            let scale = max(canvas.width / max(sourceRect.width, 1), canvas.height / max(sourceRect.height, 1))
            let finalTransform = normalized
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(
                    translationX: (canvas.width - sourceRect.width * scale) / 2,
                    y: (canvas.height - sourceRect.height * scale) / 2
                ))

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
            layer.setTransform(finalTransform, at: cursor)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
            instruction.backgroundColor = NSColor.black.cgColor
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            cursor = CMTimeAdd(cursor, duration)
        }

        guard !instructions.isEmpty else { throw ExportError.noUsableVideo }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.couldNotCreateExportSession
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        let sessionBox = ExportSessionBox(session)

        try await withCheckedThrowingContinuation { continuation in
            sessionBox.session.exportAsynchronously {
                if sessionBox.session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: sessionBox.session.error ?? ExportError.exportFailed)
                }
            }
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private enum ExportError: LocalizedError {
    case couldNotCreateTrack
    case noUsableVideo
    case couldNotCreateExportSession
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .couldNotCreateTrack: "No se pudo preparar la pista de video."
        case .noUsableVideo: "No hay tomas válidas para exportar."
        case .couldNotCreateExportSession: "No se pudo iniciar el exportador."
        case .exportFailed: "La exportación falló."
        }
    }
}

private extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var values: [T] = []
        for element in self {
            if let value = await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
