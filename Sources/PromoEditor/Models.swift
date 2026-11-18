import Foundation
import AppKit

struct MediaClip: Identifiable, Hashable, Sendable {
    let url: URL
    let duration: Double
    let width: Int
    let height: Int
    let thumbnailData: Data?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct TimelineClip: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourcePath: String
    var duration: Double
    var trimStart: Double
    var trimEnd: Double

    init(media: MediaClip) {
        sourcePath = media.url.path
        duration = media.duration
        trimStart = 0
        trimEnd = media.duration
    }

    var url: URL { URL(fileURLWithPath: sourcePath) }
    var name: String { url.lastPathComponent }
    var selectedDuration: Double { max(0, trimEnd - trimStart) }
}

struct PromoProject: Codable {
    var version = 1
    var sourceFolderPath: String?
    var clips: [TimelineClip]
}
