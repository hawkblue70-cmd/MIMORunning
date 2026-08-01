import Foundation
import SwiftData

@Model
final class MyPlannedRace {
    var id: UUID = UUID()
    var raceName: String = ""
    var dateString: String = ""     // "yyyy-MM-dd"
    var startTime: String?          // "08:00"
    var startPlace: String = ""
    var distancesRaw: String = ""    // "10.0,21.0975,42.195"
    var selectedDistanceKm: Double = 0  // 0 = 미선택
    var addedAt: Date = Date()

    init(from race: BundledRace) {
        self.id = UUID()
        self.raceName = race.name
        self.dateString = race.dateString
        self.startTime = race.startTimeString
        self.startPlace = race.start
        self.distancesRaw = race.distancesKm.map { String($0) }.joined(separator: ",")
        self.addedAt = Date()
    }

    var raceDate: Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: dateString)
    }

    var distancesKm: [Double] {
        guard !distancesRaw.isEmpty else { return [] }
        return distancesRaw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    var formattedDistances: String {
        let parts = distancesKm.map { km -> String in
            if km == 42.195  { return AppLanguage.shared.s("풀", "Full") }
            if km == 21.0975 { return AppLanguage.shared.s("하프", "Half") }
            let i = Int(km)
            return km == Double(i) ? "\(i)K" : "\(km)K"
        }
        return parts.joined(separator: " · ")
    }

    var isPast: Bool {
        guard let d = raceDate else { return false }
        return d < Calendar.current.startOfDay(for: Date())
    }
}
