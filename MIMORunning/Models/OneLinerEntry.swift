import Foundation
import SwiftData
import Photos

// MARK: - OneLinerEntry

/// Text composition tied to a workout day, optionally linked to a photo or video background.
/// The TEXT is owned by the day — it persists even if the backing media is deleted.
///
/// workoutID formats:
///   • "<UUID string>"          — a HealthKit workout (running day)
///   • "date:yyyy-MM-dd"        — a rest day (no workout); key is the calendar date
///
/// mediaRef formats:
///   • nil                      — SkyPalette gradient background
///   • "photo:<storyPhotoUUID>" — locally stored StoryPhoto
///   • "video:<PHAsset.localIdentifier>" — Photos library video
///
/// Video multi-slot: text may contain "\n"-separated lines, each line = one display slot
/// for the multi-page typing animation. Single-line text = legacy single-page mode.
///
/// Up to 5 entries per workout/day; each has a distinct mediaRef.
@Model
final class OneLinerEntry {
    var id: UUID           = UUID()
    var workoutID: String  = ""
    var text: String       = ""
    var fontID: String     = OneLinerFont.pen.rawValue
    var colorID: String    = OneLinerTextColor.white.rawValue
    var anchorRaw: Int     = 0       // index into CardPosition.allCases
    var showDate: Bool     = true
    var mediaRef: String?  = nil
    var createdAt: Date    = Date()

    // MARK: Typed accessors

    var font: OneLinerFont {
        get { OneLinerFont.migrate(fontID) }
        set { fontID = newValue.rawValue }
    }

    var textColor: OneLinerTextColor {
        get { OneLinerTextColor(rawValue: colorID) ?? .white }
        set { colorID = newValue.rawValue }
    }

    var position: CardPosition {
        get {
            let cases = Array(CardPosition.allCases)
            guard anchorRaw >= 0, anchorRaw < cases.count else { return .center }
            return cases[anchorRaw]
        }
        set { anchorRaw = CardPosition.allCases.firstIndex(of: newValue) ?? 0 }
    }

    // MARK: workoutID helpers

    /// True when this entry belongs to a rest day (no workout).
    var isRestDay: Bool { workoutID.hasPrefix("date:") }

    /// Calendar date string → workoutID for a rest day entry ("date:yyyy-MM-dd").
    static func restDayWorkoutID(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return "date:\(fmt.string(from: date))"
    }

    // MARK: mediaRef helpers

    var isGradientBacked: Bool { mediaRef == nil }

    /// PHAsset localIdentifier if this entry is backed by a Photos library asset.
    var phAssetLocalIdentifier: String? {
        guard let ref = mediaRef, ref.hasPrefix("video:") else { return nil }
        return String(ref.dropFirst("video:".count))
    }

    /// StoryPhoto UUID string if backed by a locally stored story photo.
    var linkedPhotoUUID: String? {
        guard let ref = mediaRef, ref.hasPrefix("photo:") else { return nil }
        return String(ref.dropFirst("photo:".count))
    }

    // MARK: PHAsset availability

    /// Whether the linked PHAsset still exists. Always true for non-video entries.
    var isPHAssetAvailable: Bool {
        guard let assetID = phAssetLocalIdentifier else { return true }
        return PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).count > 0
    }

    init(workoutID: String, mediaRef: String? = nil) {
        self.workoutID = workoutID
        self.mediaRef  = mediaRef
        self.createdAt = Date()
    }

    // MARK: - Preview text helpers

    /// First non-empty display text, extracting from v4recipes/v3recipes JSON or plain text.
    var previewText: String {
        let raw = text
        if raw.hasPrefix("v4recipes\n") {
            return Self.firstLine(fromV4JSON: String(raw.dropFirst("v4recipes\n".count)))
        } else if raw.hasPrefix("v3recipes\n") {
            return Self.firstLine(fromV3JSON: String(raw.dropFirst("v3recipes\n".count)))
        } else if raw.hasPrefix("v3slide\n") {
            let json = String(raw.dropFirst("v3slide\n".count))
            if let data = json.data(using: .utf8),
               let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let lines = obj["lines"] as? [String] {
                return lines.first(where: {
                    let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return false }
                    if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                        || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                        || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return false }
                    return true
                }) ?? ""
            }
            return ""
        } else if raw.hasPrefix("v2clips\n") {
            return ""
        } else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var hasContent: Bool { !previewText.isEmpty || hasMedia }

    // MARK: - Media info for list thumbnail

    struct RestDayMediaInfo {
        let photoRef:  String?  // "restphoto:<uuid>.jpg" — photo-slide source (full quality)
        let thumbRef:  String?  // "clipthumb:<uuid>.jpg" — video clip mini-thumbnail
        let clipCount: Int
        let isSlide:   Bool
    }

    /// Extracts media metadata for the list-row thumbnail, clip count, and slide indicator.
    var restDayMediaInfo: RestDayMediaInfo {
        let raw = text
        if raw.hasPrefix("v4recipes\n") {
            return Self.v4MediaInfo(String(raw.dropFirst("v4recipes\n".count)))
        } else if raw.hasPrefix("v3recipes\n") {
            return Self.v3MediaInfo(String(raw.dropFirst("v3recipes\n".count)))
        }
        return RestDayMediaInfo(photoRef: nil, thumbRef: nil, clipCount: 0, isSlide: false)
    }

    /// True when the entry has any stored photo or video thumbnail.
    var hasMedia: Bool {
        let info = restDayMediaInfo
        return (info.photoRef.map { !$0.isEmpty } ?? false) ||
               (info.thumbRef.map { !$0.isEmpty } ?? false)
    }

    private static func v4MediaInfo(_ json: String) -> RestDayMediaInfo {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mode = obj["activeMode"] as? String else {
            return RestDayMediaInfo(photoRef: nil, thumbRef: nil, clipCount: 0, isSlide: false)
        }
        let key: String
        switch mode {
        case "스토리":   key = "story"
        case "영상":    key = "video"
        case "슬라이드":  key = "slide"
        default:        key = mode.lowercased()
        }
        guard let modeObj = obj[key] as? [String: Any],
              let clips   = modeObj["clips"] as? [[String: Any]] else {
            return RestDayMediaInfo(photoRef: nil, thumbRef: nil, clipCount: 0, isSlide: mode == "슬라이드")
        }
        let first = clips.first
        return RestDayMediaInfo(
            photoRef:  first?["photoRef"] as? String,
            thumbRef:  first?["thumbRef"] as? String,
            clipCount: clips.count,
            isSlide:   mode == "슬라이드"
        )
    }

    private static func v3MediaInfo(_ json: String) -> RestDayMediaInfo {
        guard let data  = json.data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clips = obj["clips"] as? [[String: Any]] else {
            return RestDayMediaInfo(photoRef: nil, thumbRef: nil, clipCount: 0, isSlide: false)
        }
        let first   = clips.first
        let isSlide = obj["isPhotoSlide"] as? Bool ?? false
        return RestDayMediaInfo(
            photoRef:  first?["photoRef"] as? String,
            thumbRef:  first?["thumbRef"] as? String,
            clipCount: clips.count,
            isSlide:   isSlide
        )
    }

    private static func firstLine(fromV4JSON json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let activeMode = obj["activeMode"] as? String else { return "" }
        let key: String
        switch activeMode {
        case "스토리":   key = "story"
        case "영상":    key = "video"
        case "슬라이드":  key = "slide"
        default:        key = activeMode.lowercased()
        }
        guard let modeObj = obj[key] as? [String: Any],
              let clips = modeObj["clips"] as? [[String: Any]] else { return "" }
        for clip in clips {
            if let lines = clip["lines"] as? [String] {
                for line in lines {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
        }
        return ""
    }

    private static func firstLine(fromV3JSON json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clips = obj["clips"] as? [[String: Any]] else { return "" }
        for clip in clips {
            if let lines = clip["lines"] as? [String] {
                for line in lines {
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
        }
        return ""
    }

    // MARK: - Shared fetch helper
    // 스토리 섹션·공유 화면이 동일한 조건으로 entry를 필터/정렬하도록 단일 경로 제공.
    static func visible(from all: [OneLinerEntry], workoutID: String) -> [OneLinerEntry] {
        all.filter {
                $0.workoutID == workoutID &&
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
