import AVFoundation
import AppKit
import Foundation

public enum VideoExporter {
    public static func render(
        clips: [TimelineClip],
        to outputURL: URL,
        musicURL: URL? = nil,
        musicVolume: Double = 0.35,
        overwriteExistingFile: Bool = false
    ) async throws {
        let normalizedOutputURL = outputURL.standardizedFileURL
        let sourceURLs = clips.map(\.url) + (musicURL.map { [$0] } ?? [])
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

    var errorDescription: String? {
        switch self {
        case .couldNotCreateTrack: "No se pudo preparar la pista de video."
        case .noUsableVideo: "No hay tomas válidas para exportar."
        case .couldNotCreateExportSession: "No se pudo iniciar el exportador."
        case .exportFailed: "La exportación falló."
        case .outputIsSource: "El destino no puede ser uno de los videos originales."
        case .outputAlreadyExists: "El archivo de destino ya existe; elige otro nombre o confirma que quieres reemplazarlo."
        case .musicHasNoAudio: "El archivo de música no contiene una pista de audio válida."
        }
    }
}
