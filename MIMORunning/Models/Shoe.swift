import Foundation
import SwiftData

@Model
final class Shoe {
    var id: UUID
    var name: String
    var brand: String
    var addedDate: Date

    init(name: String, brand: String = "") {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.addedDate = Date()
    }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) \(name)"
    }
}
