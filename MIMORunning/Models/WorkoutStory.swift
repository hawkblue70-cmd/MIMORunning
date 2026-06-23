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
}

// MARK: - StoryPhoto

@Model
final class StoryPhoto {
    var imageData: Data = Data()
    var index: Int = 0
    var story: WorkoutStory?

    init(data: Data, index: Int) {
        self.imageData = data
        self.index = index
    }

    var image: UIImage? { UIImage(data: imageData) }
}

// MARK: - WorkoutStory

@Model
final class WorkoutStory {
    var workoutID: String = ""
    var memo: String = ""
    var moodRaw: String = Mood.okay.rawValue
    var updatedAt: Date = Date()
    var shoeID: String?

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

    init(workoutID: String, memo: String = "", mood: Mood = .okay) {
        self.workoutID = workoutID
        self.memo = memo
        self.moodRaw = mood.rawValue
        self.updatedAt = Date()
    }
}
