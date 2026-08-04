import Foundation
import SwiftData

// MARK: - 주차 요약 (weeksJSON 직렬화용)

struct MRPlanWeekSummary: Codable {
    let idx: Int
    let monday: Date
    let phase: String
    let longRunKm: Double
    let weeklyKm: Double
}

// MARK: - 계획 시작 시점 스냅샷

/// 대회 계획이 처음 만들어질 때 1회 저장. 덮어쓰지 않는다.
/// 목적: "그때 앱이 뭐라고 했나"를 보존.
@Model final class RacePlanSnapshot {
    var raceDate: Date = Date()
    var raceName: String = ""
    var distanceM: Double = 0
    var createdAt: Date = Date()
    var projectedFinalMin: Double = 0
    var projectedNowMin: Double = 0
    var goalMin: Double = 0          // 0 = 목표 미설정
    var weeksJSON: String = ""       // [MRPlanWeekSummary] JSON
    var metaJSON: String = ""        // 모델 파라미터

    init(raceDate: Date, raceName: String, distanceM: Double,
         projectedFinalMin: Double, projectedNowMin: Double, goalMin: Double,
         weeksJSON: String, metaJSON: String) {
        self.raceDate = raceDate
        self.raceName = raceName
        self.distanceM = distanceM
        self.createdAt = Date()
        self.projectedFinalMin = projectedFinalMin
        self.projectedNowMin = projectedNowMin
        self.goalMin = goalMin
        self.weeksJSON = weeksJSON
        self.metaJSON = metaJSON
    }

    var planWeeks: [MRPlanWeekSummary] {
        guard !weeksJSON.isEmpty,
              let data = weeksJSON.data(using: .utf8),
              let weeks = try? JSONDecoder().decode([MRPlanWeekSummary].self, from: data)
        else { return [] }
        return weeks
    }
}
