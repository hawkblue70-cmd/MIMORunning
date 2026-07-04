import Foundation
import SwiftData
import Photos

// MARK: - OneLinerEntry

/// Text composition tied to a workout run, optionally linked to a photo or video background.
/// The TEXT is owned by the workout — it persists even if the backing media is deleted.
/// Up to 5 entries per workout; each has a distinct mediaRef.
@Model
final class OneLinerEntry {
    var id: UUID           = UUID()
    var workoutID: String  = ""
    var text: String       = ""
    var fontID: String     = OneLinerFont.pen.rawValue
    var colorID: String    = OneLinerTextColor.white.rawValue
    var anchorRaw: Int     = 0       // index into CardPosition.allCases
    var showDate: Bool     = true
    /// nil = SkyPalette gradient background (standalone entry)
    /// "photo:<storyPhotoUUID>" = locally stored StoryPhoto
    /// "video:<PHAsset.localIdentifier>" = Photos library video
    var mediaRef: String?  = nil
    var createdAt: Date    = Date()

    // MARK: Typed accessors

    var font: OneLinerFont {
        get { OneLinerFont(rawValue: fontID) ?? .pen }
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
