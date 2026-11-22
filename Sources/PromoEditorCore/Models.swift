import Foundation
import AppKit

public struct MediaClip: Identifiable, Hashable, Sendable {
    public let url: URL
    public let duration: Double
    public let width: Int
    public let height: Int
    public let thumbnailData: Data?

    public init(url: URL, duration: Double, width: Int, height: Int, thumbnailData: Data?) {
        self.url = url
        self.duration = duration
        self.width = width
        self.height = height
        self.thumbnailData = thumbnailData
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
}

public struct TimelineClip: Identifiable, Codable, Equatable {
    public var id: UUID
    public var sourcePath: String
    public var duration: Double
    public var trimStart: Double
    public var trimEnd: Double

    public init(media: MediaClip) {
        id = UUID()
        sourcePath = media.url.path
        duration = media.duration
        trimStart = 0
        trimEnd = media.duration
    }

    public init(
        id: UUID = UUID(),
        sourcePath: String,
        duration: Double,
        trimStart: Double = 0,
        trimEnd: Double? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd ?? duration
    }

    public var url: URL { URL(fileURLWithPath: sourcePath) }
    public var name: String { url.lastPathComponent }
    public var selectedDuration: Double { max(0, trimEnd - trimStart) }
}

public struct VFXSettings: Codable, Equatable {
    public var openingText: String
    public var closingText: String
    public var logoPath: String?

    public init(
        openingText: String = "",
        closingText: String = "",
        logoPath: String? = nil
    ) {
        self.openingText = openingText
        self.closingText = closingText
        self.logoPath = logoPath
    }

    private enum CodingKeys: String, CodingKey {
        case openingText
        case closingText
        case logoPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        openingText = try container.decodeIfPresent(String.self, forKey: .openingText) ?? ""
        closingText = try container.decodeIfPresent(String.self, forKey: .closingText) ?? ""
        logoPath = try container.decodeIfPresent(String.self, forKey: .logoPath)
    }
}

public struct PromoProject: Codable {
    public var version: Int
    public var sourceFolderPath: String?
    public var clips: [TimelineClip]
    public var musicPath: String?
    public var musicVolume: Double
    public var vfx: VFXSettings

    public init(
        version: Int = 1,
        sourceFolderPath: String? = nil,
        clips: [TimelineClip],
        musicPath: String? = nil,
        musicVolume: Double = 0.35,
        vfx: VFXSettings = VFXSettings()
    ) {
        self.version = version
        self.sourceFolderPath = sourceFolderPath
        self.clips = clips
        self.musicPath = musicPath
        self.musicVolume = musicVolume
        self.vfx = vfx
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sourceFolderPath
        case clips
        case musicPath
        case musicVolume
        case vfx
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sourceFolderPath = try container.decodeIfPresent(String.self, forKey: .sourceFolderPath)
        clips = try container.decode([TimelineClip].self, forKey: .clips)
        musicPath = try container.decodeIfPresent(String.self, forKey: .musicPath)
        musicVolume = try container.decodeIfPresent(Double.self, forKey: .musicVolume) ?? 0.35
        vfx = try container.decodeIfPresent(VFXSettings.self, forKey: .vfx) ?? VFXSettings()
    }
}
