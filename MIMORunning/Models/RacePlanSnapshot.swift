import Foundation
import SwiftData

// MARK: - 주차 요약 (weeksJSON 직렬화용)

struct MRPlanWeekSummary: Codable {
    let idx: Int
    let monday: Date
    let phase: String
    let longRunKm: Double
    let weeklyKm: Double
    var breakdown: String   // 실행 안내

    init(idx: Int, monday: Date, phase: String,
         longRunKm: Double, weeklyKm: Double, breakdown: String = "") {
        self.idx = idx; self.monday = monday; self.phase = phase
        self.longRunKm = longRunKm; self.weeklyKm = weeklyKm
        self.breakdown = breakdown
    }

    // breakdown은 신규 필드 — 구버전 스냅샷 JSON에 없을 때 빈 문자열로 폴백.
    // Swift 자동 합성 Decodable은 키 누락 시 keyNotFound를 던지므로 커스텀 구현이 필요하다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idx       = try c.decode(Int.self,    forKey: .idx)
        monday    = try c.decode(Date.self,   forKey: .monday)
        phase     = try c.decode(String.self, forKey: .phase)
        longRunKm = try c.decode(Double.self, forKey: .longRunKm)
        weeklyKm  = try c.decode(Double.self, forKey: .weeklyKm)
        breakdown = (try? c.decodeIfPresent(String.self, forKey: .breakdown)) ?? ""
    }
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

    /// metaJSON에서 저장된 targetLongKm을 읽는다.
    /// 구버전 스냅샷(키 없음)은 nil → 호출자가 기본값(21.0)으로 폴백.
    var storedTargetLongKm: Double? { metaDouble("targetLongKm") }

    /// metaJSON에서 저장된 startingLongKm(계획 수립 시점 fitness)을 읽는다.
    /// 구버전 스냅샷(키 없음)은 nil → 과거 주 보정 migration 트리거.
    var storedStartingLongKm: Double? { metaDouble("startingLongKm") }

    private func metaDouble(_ key: String) -> Double? {
        guard !metaJSON.isEmpty,
              let data = metaJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let v = dict[key],
              let d = Double(v) else { return nil }
        return d
    }

    var planWeeks: [MRPlanWeekSummary] {
        guard !weeksJSON.isEmpty,
              let data = weeksJSON.data(using: .utf8)
        else { return [] }
        // ⚠ 인코더가 .secondsSince1970을 쓰므로 디코더도 반드시 맞춰야 한다.
        //   기본값(.deferredToDate = 2001 기준)과 섞이면 날짜가 31년 어긋난다.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([MRPlanWeekSummary].self, from: data)) ?? []
    }
}
