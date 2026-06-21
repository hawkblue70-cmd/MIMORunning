import SwiftUI

@Observable final class CustomMiniMeStore {
    var image: UIImage?

    init() { load() }

    func save(_ uiImage: UIImage) {
        image = uiImage
        if let data = uiImage.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL)
        }
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let uiImage = UIImage(data: data) else { return }
        image = uiImage
    }

    private var fileURL: URL {
        URL.documentsDirectory.appendingPathComponent("customMiniMe.jpg")
    }
}
