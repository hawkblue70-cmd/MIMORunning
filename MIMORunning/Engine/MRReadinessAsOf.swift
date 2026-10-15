import Foundation

// 아침 제안 asOf 재계산 — 인사이트 내보내기가 "그날 아침 앱이 했을 말"을 보여 줄 때 쓴다(앱을 안 연 날도).
// 설계 docs/superpowers/specs/2026-10-15-insight-export-morning-design.md §3.
// mrReadiness는 asOf에 대해 순수하지만, 입력에 asOf 이후 기록이 섞이면 그 주 집계·부하·HRV가 미래를 센다.
// 여기서 모든 시계열을 asOf 기준으로 자른 뒤 부른다. 리듬·회색 지대 같은 조립 입력은 호출부가 거른 runs로 만든다.

/// asOf 이전에 시작한 러닝만 — 그날 러닝을 빼야 엔진의 "이미 뛴 날 nil"을 피한다.
func mrRunsBefore(_ runs: [MRWorkout], asOf: Date) -> [MRWorkout] {
    runs.filter { $0.start < asOf }
}

/// asOf 날 키까지의 밤 값 — 다음 날 키(그날 15시 이후 샘플 포함)는 그 아침엔 없던 값이다.
func mrNightsThrough(_ nights: [(date: Date, value: Double)], asOf: Date,
                     calendar: Calendar = .current) -> [(date: Date, value: Double)] {
    let today = calendar.startOfDay(for: asOf)
    return nights.filter { calendar.startOfDay(for: $0.date) <= today }
}

/// `mrReadiness`를 asOf 시점 그대로 다시 계산한다. 러닝·고강도 시작·포인트 유형·밤 값을 모두 asOf 기준으로 자른다.
func mrReadinessAsOf(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                     hrvNights: [(date: Date, value: Double)], planPhase: String?,
                     asOf: Date, hardRunStarts: Set<Date> = [],
                     planWeek: MRPlanWeekContext? = nil,
                     pointRunTypes: [Date: WorkoutType] = [:],
                     rhythm: MRRhythmContext? = nil,
                     easyTarget: MREasyTarget? = nil,
                     grayZone: MRGrayZoneWeek? = nil,
                     restingHR: [(date: Date, value: Double)] = [],
                     respNights: [(date: Date, value: Double)] = [],
                     tempNights: [(date: Date, value: Double)] = [],
                     calendar: Calendar = .current) -> MRReadiness? {
    mrReadiness(runs: mrRunsBefore(runs, asOf: asOf), phys: phys, heatHR: heatHR,
                hrvNights: mrNightsThrough(hrvNights, asOf: asOf, calendar: calendar),
                planPhase: planPhase, asOf: asOf,
                hardRunStarts: hardRunStarts.filter { $0 < asOf },
                planWeek: planWeek,
                pointRunTypes: pointRunTypes.filter { $0.key < asOf },
                rhythm: rhythm, easyTarget: easyTarget, grayZone: grayZone,
                restingHR: mrNightsThrough(restingHR, asOf: asOf, calendar: calendar),
                respNights: mrNightsThrough(respNights, asOf: asOf, calendar: calendar),
                tempNights: mrNightsThrough(tempNights, asOf: asOf, calendar: calendar),
                calendar: calendar)
}
