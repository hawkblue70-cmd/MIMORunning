import Foundation
import SwiftData
import UIKit
import SwiftUI

enum Mood: String, CaseIterable, Codable {
    case fantastic = "fantastic"
    case great     = "great"
    case okay      = "okay"
    case tough     = "tough"
    case terrible  = "terrible"

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .fantastic: L.s("최고", "Great!")
        case .great:     L.s("좋음", "Good")
        case .okay:      L.s("보통", "Okay")
        case .tough:     L.s("힘듦", "Tough")
        case .terrible:  L.s("최악", "Bad")
        }
    }

    var sfSymbol: String {
        switch self {
        case .fantastic: "bolt.fill"
        case .great:     "face.smiling.fill"
        case .okay:      "minus.circle.fill"
        case .tough:     "bolt.slash.fill"
        case .terrible:  "xmark.circle.fill"
        }
    }

    var cardColor: Color {
        switch self {
        case .fantastic: Theme.power
        case .great:     Theme.violet
        case .okay:      Theme.time
        case .tough:     Color.orange
        case .terrible:  Theme.heartRate
        }
    }
}

// MARK: - StoryPhoto

@Model
final class StoryPhoto {
    var imageData: Data = Data()
    var index: Int = 0
    /// Stable identifier used by OneLinerEntry.mediaRef ("photo:<photoUUID>").
    /// Generated once at creation; survives re-saves so OneLiner links stay valid.
    var photoUUID: String = UUID().uuidString
    var story: WorkoutStory?

    init(data: Data, index: Int, uuid: String = UUID().uuidString) {
        self.imageData = data
        self.index = index
        self.photoUUID = uuid
    }

    var image: UIImage? { UIImage(data: imageData) }

    /// Resize to ≤maxSide actual pixels on the long axis, encode as JPEG.
    /// Uses image.scale to get true pixel dimensions (UIImage(data:) → scale=1, but
    /// renderer-produced images on retina devices may have scale=2 or 3).
    /// format.scale=1.0 forces pixel-accurate output regardless of device display scale —
    /// without this, UIGraphicsImageRenderer inherits the screen scale (2×/3×) and
    /// produces an image 4–9× larger than intended, defeating the resize.
    static func thumbnailData(from image: UIImage, maxSide: CGFloat = 800, quality: CGFloat = 0.70) -> Data? {
        let sz  = image.size
        guard sz.width > 0, sz.height > 0 else { return nil }
        let pxW     = sz.width  * image.scale   // actual pixel width
        let pxH     = sz.height * image.scale   // actual pixel height
        let longest = max(pxW, pxH)
        if longest <= maxSide { return image.jpegData(compressionQuality: quality) }
        let ratio = maxSide / longest
        let outW  = (pxW * ratio).rounded()
        let outH  = (pxH * ratio).rounded()
        let fmt   = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0   // 1 pt = 1 px: output is exactly outW×outH pixels
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: fmt)
        let resized  = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: outW, height: outH)))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Convenience overload for migration paths: decode raw Data → resize → JPEG.
    /// Avoids intermediate UIImage allocation at call site and ensures the same
    /// resize logic is used whether saving new photos or re-compressing stored ones.
    static func thumbnailData(from data: Data, maxSide: CGFloat = 800, quality: CGFloat = 0.70) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return thumbnailData(from: image, maxSide: maxSide, quality: quality)
    }
}

// MARK: - WorkoutStory

@Model
final class WorkoutStory {
    var workoutID: String = ""
    var memo: String = ""
    var moodRaw: String = Mood.okay.rawValue
    var updatedAt: Date = Date()
    var shoeID: String?

    /// 사용자가 앱에서 입력한 운동 강도 1...10. nil = 미입력(Apple 값 사용).
    /// CloudKit: 옵셔널 + 기본값 nil.
    var effortRPE: Int?
    var effortUpdatedAt: Date?

    // CloudKit requires all relationships to be optional
    @Relationship(deleteRule: .cascade, inverse: \StoryPhoto.story)
    var photos: [StoryPhoto]?

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .okay }
        set { moodRaw = newValue.rawValue }
    }

    var hasContent: Bool { !memo.isEmpty || !(photos?.isEmpty ?? true) }

    var allPhotoImages: [UIImage] {
        (photos ?? []).sorted { $0.index < $1.index }.compactMap { UIImage(data: $0.imageData) }
    }

    /// UUIDs parallel to allPhotoImages — used by OneLinerEntry.mediaRef cross-references.
    var sortedPhotoUUIDs: [String] {
        (photos ?? []).sorted { $0.index < $1.index }.map { $0.photoUUID }
    }

    init(workoutID: String, memo: String = "", mood: Mood = .okay) {
        self.workoutID = workoutID
        self.memo = memo
        self.moodRaw = mood.rawValue
        self.updatedAt = Date()
    }
}
