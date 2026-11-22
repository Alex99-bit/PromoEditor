import AVFoundation
import AppKit
import Foundation
import QuartzCore

public enum VideoExporter {
    public static func render(
        clips: [TimelineClip],
        to outputURL: URL,
        musicURL: URL? = nil,
        musicVolume: Double = 0.35,
        vfx: VFXSettings = VFXSettings(),
        overwriteExistingFile: Bool = false
    ) async throws {
        let normalizedOutputURL = outputURL.standardizedFileURL
        let logoURL = vfx.logoPath.map { URL(fileURLWithPath: $0) }
        let sourceURLs = clips.map(\.url) + (musicURL.map { [$0] } ?? []) + (logoURL.map { [$0] } ?? [])
        guard !sourceURLs.contains(where: { $0.standardizedFileURL == normalizedOutputURL }) else {
            throw ExportError.outputIsSource
        }

        let composition = AVMutableComposition()
        guard let videoCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.couldNotCreateTrack
        }

        let canvas = CGSize(width: 1080, height: 1920)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = tracks.first else { continue }
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let start = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
            let duration = CMTime(seconds: clip.selectedDuration, preferredTimescale: 600)
            guard CMTimeGetSeconds(duration) > 0.05 else { continue }
            let range = CMTimeRange(start: start, duration: duration)

            try videoCompositionTrack.insertTimeRange(range, of: sourceVideoTrack, at: cursor)

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
        videoComposition.animationTool = try makeAnimationTool(
            settings: vfx,
            canvas: canvas,
            totalDuration: CMTimeGetSeconds(cursor)
        )

        var audioMix: AVMutableAudioMix?
        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            guard let sourceMusicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first else {
                throw ExportError.musicHasNoAudio
            }
            guard let musicCompositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.couldNotCreateTrack
            }

            let musicDuration = try await musicAsset.load(.duration)
            let musicSeconds = CMTimeGetSeconds(musicDuration)
            let totalSeconds = CMTimeGetSeconds(cursor)
            guard musicSeconds.isFinite, musicSeconds > 0, totalSeconds.isFinite, totalSeconds > 0 else {
                throw ExportError.musicHasNoAudio
            }
            var destinationTime = CMTime.zero
            while CMTimeGetSeconds(destinationTime) < totalSeconds {
                let remainingSeconds = totalSeconds - CMTimeGetSeconds(destinationTime)
                let chunkSeconds = min(musicSeconds, remainingSeconds)
                let chunk = CMTime(seconds: chunkSeconds, preferredTimescale: 600)
                try musicCompositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: chunk),
                    of: sourceMusicTrack,
                    at: destinationTime
                )
                destinationTime = CMTimeAdd(destinationTime, chunk)
            }

            let parameters = AVMutableAudioMixInputParameters(track: musicCompositionTrack)
            let targetVolume = Float(max(0, min(musicVolume, 1)))
            let fadeSeconds = min(1.0, totalSeconds / 3)
            let fadeDuration = CMTime(seconds: fadeSeconds, preferredTimescale: 600)
            parameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: targetVolume,
                timeRange: CMTimeRange(start: .zero, duration: fadeDuration)
            )
            parameters.setVolumeRamp(
                fromStartVolume: targetVolume,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: CMTimeSubtract(cursor, fadeDuration), duration: fadeDuration)
            )
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            audioMix = mix
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            guard overwriteExistingFile else { throw ExportError.outputAlreadyExists }
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
        session.audioMix = audioMix
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

    private static func makeAnimationTool(
        settings: VFXSettings,
        canvas: CGSize,
        totalDuration: Double
    ) throws -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.bounds = CGRect(origin: .zero, size: canvas)
        parentLayer.position = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        if let logoPath = settings.logoPath {
            let logoURL = URL(fileURLWithPath: logoPath)
            guard let image = NSImage(contentsOf: logoURL) else {
                throw ExportError.logoUnavailable(logoURL.lastPathComponent)
            }
            var proposedRect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
                throw ExportError.logoUnavailable(logoURL.lastPathComponent)
            }
            let logoLayer = CALayer()
            logoLayer.contents = cgImage
            logoLayer.contentsGravity = .resizeAspect
            logoLayer.frame = CGRect(x: 72, y: 96, width: 210, height: 126)
            logoLayer.opacity = 0.96
            parentLayer.addSublayer(logoLayer)
        }

        let titleDuration = min(3.2, max(1.0, totalDuration * 0.18))
        if !settings.openingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try makeTitleLayers(
                text: settings.openingText,
                canvas: canvas,
                start: 0.15,
                duration: min(titleDuration, totalDuration)
            ).forEach(parentLayer.addSublayer)
        }
        if !settings.closingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let duration = min(titleDuration, totalDuration)
            try makeTitleLayers(
                text: settings.closingText,
                canvas: canvas,
                start: max(0, totalDuration - duration),
                duration: duration
            ).forEach(parentLayer.addSublayer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func makeTitleLayers(
        text: String,
        canvas: CGSize,
        start: Double,
        duration: Double
    ) throws -> [CALayer] {
        let cardFrame = CGRect(
            x: 84,
            y: canvas.height * 0.66,
            width: canvas.width - 168,
            height: 250
        )
        let card = CALayer()
        card.frame = cardFrame
        card.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        card.cornerRadius = 30
        card.borderWidth = 1
        card.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.28
        card.shadowRadius = 18
        card.shadowOffset = CGSize(width: 0, height: 8)

        let textSize = CGSize(width: cardFrame.width - 56, height: 100)
        guard let textImage = renderTitleImage(text, size: textSize) else {
            throw ExportError.titleRenderingFailed
        }
        let textLayer = CALayer()
        textLayer.frame = CGRect(
            x: cardFrame.minX + 28,
            y: cardFrame.minY + (cardFrame.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        textLayer.contents = textImage
        textLayer.contentsGravity = .resizeAspect

        card.opacity = 0
        textLayer.opacity = 0
        addTitleAnimation(to: card, start: start, duration: duration)
        addTitleAnimation(to: textLayer, start: start, duration: duration)
        return [card, textLayer]
    }

    private static func addTitleAnimation(to layer: CALayer, start: Double, duration: Double) {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.12, 0.88, 1]
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
        opacity.duration = duration
        opacity.fillMode = .both
        opacity.isRemovedOnCompletion = false
        layer.add(opacity, forKey: "promoEditorTitleOpacity")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.96, 1.0, 1.0, 0.99]
        scale.keyTimes = [0, 0.18, 0.88, 1]
        scale.beginTime = AVCoreAnimationBeginTimeAtZero + start
        scale.duration = duration
        scale.fillMode = .both
        scale.isRemovedOnCompletion = false
        layer.add(scale, forKey: "promoEditorTitleScale")
    }

    private static func renderTitleImage(_ text: String, size: CGSize) -> CGImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 64),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )
        attributedText.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
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
    case outputIsSource
    case outputAlreadyExists
    case musicHasNoAudio
    case logoUnavailable(String)
    case titleRenderingFailed

    var errorDescription: String? {
        switch self {
        case .couldNotCreateTrack: "No se pudo preparar la pista de video."
        case .noUsableVideo: "No hay tomas válidas para exportar."
        case .couldNotCreateExportSession: "No se pudo iniciar el exportador."
        case .exportFailed: "La exportación falló."
        case .outputIsSource: "El destino no puede ser uno de los videos originales."
        case .outputAlreadyExists: "El archivo de destino ya existe; elige otro nombre o confirma que quieres reemplazarlo."
        case .musicHasNoAudio: "El archivo de música no contiene una pista de audio válida."
        case let .logoUnavailable(name): "No se pudo cargar el logo \(name)."
        case .titleRenderingFailed: "No se pudo renderizar el texto del efecto visual."
        }
    }
}
