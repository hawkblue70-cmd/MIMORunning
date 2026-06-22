import Foundation
import SwiftData
import UIKit

enum Mood: String, CaseIterable, Codable {
    case fantastic = "fantastic"
    case great     = "great"
    case okay      = "okay"
    case tough     = "tough"
    case terrible  = "terrible"

    var label: String {
        switch self {
        case .fantastic: "최고"
        case .great:     "좋음"
        case .okay:      "보통"
        case .tough:     "힘듦"
        case .terrible:  "최악"
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

@Model
final class WorkoutStory {
    @Attribute(.unique) var workoutID: String
    var memo: String
    var moodRaw: String
    var photoFilenames: [String] = []
    @Attribute(.externalStorage) var photoData: Data?  // legacy, kept for migration
    var updatedAt: Date
    var shoeID: String?  // UUID string of selected Shoe

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .okay }
        set { moodRaw = newValue.rawValue }
    }

    var hasContent: Bool { !memo.isEmpty || !photoFilenames.isEmpty || photoData != nil }

    var allPhotoImages: [UIImage] {
        if !photoFilenames.isEmpty {
            return photoFilenames.compactMap { WorkoutStory.loadPhoto(named: $0) }
        }
        if let data = photoData, let img = UIImage(data: data) { return [img] }
        return []
    }

    init(workoutID: String, memo: String = "", mood: Mood = .okay,
         photoFilenames: [String] = [], photoData: Data? = nil) {
        self.workoutID = workoutID
        self.memo = memo
        self.moodRaw = mood.rawValue
        self.photoFilenames = photoFilenames
        self.photoData = photoData
        self.updatedAt = Date()
    }

    // MARK: - File storage helpers

    private static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func savePhoto(_ image: UIImage, workoutID: String, index: Int) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.75) else { return nil }
        let filename = "\(workoutID)_\(index).jpg"
        let url = documentsDir.appendingPathComponent(filename)
        try? data.write(to: url)
        return filename
    }

    static func loadPhoto(named filename: String) -> UIImage? {
        let url = documentsDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deletePhoto(named filename: String) {
        let url = documentsDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
