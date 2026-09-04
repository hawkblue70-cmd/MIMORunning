import Foundation

/// 심박 존 체류 시간 기반 강도 분포 (K-1 · K-4). 연속 알림은 여기 없음 — 이지런 회차 기준(K-7)으로 카드에서 센다.
///
/// 유형(이지런·템포런 …)은 훈련 의도이지 생리적 강도가 아니다.
/// 여기서는 리듬 카드 도넛이 이미 쓰는 `HRZoneData.seconds`를 창 안의 모든 러닝에 대해 합산한다.
///
///   저강도  Zone 1 + Zone 2                 (AT1 이하)
///   중간    Zone 3 + Zone 4 중 AT2 미만      (AT1 ~ AT2)
///   고강도  Zone 4 중 AT2 이상 + Zone 5      (AT2 이상)
///
/// AT2는 Zone 4 안의 실제 심박값(Karvonen HRR 85%)이다. 존 계산 시점에 Zone 4 항목에
/// `splitBPM`(AT2)과 `upperSeconds`(AT2 이상 체류 시간)를 함께 저장해 두고, 여기서는 그 값을 쓴다.
/// 러닝별 RHR이 다르므로 AT1·AT2도 러닝별로 다르다.
enum MRIntensityTime {

    enum Zone4Policy: CaseIterable {
        /// 채택안 — Zone 4를 AT2 심박값에서 자른다 (`HRZoneData.upperSeconds`).
        case at2Split
        /// 비교용 — Zone 4 전체를 중간, Zone 5만 고강도.
        case allMedium

        var label: String {
            switch self {
            case .at2Split:  return "Zone4를 AT2 심박값에서 분할"
            case .allMedium: return "Zone4 전체를 중간으로 처리"
            }
        }
    }

    /// Zone 4 항목에 AT2 분할 정보가 있는가. 없는 캐시(구버전)는 `at2Split`에 쓸 수 없다.
    static func hasAT2Split(_ zones: [HRZoneData]) -> Bool {
        guard let z4 = zones.first(where: { $0.id == 4 }) else { return false }
        return z4.splitBPM != nil && z4.upperSeconds != nil
    }

    struct RunInput {
        let id: UUID
        let date: Date
        /// 활동 요약에 평균 심박이 있는가 (심박 자체가 없는 러닝 판별용)
        let hasHR: Bool
        /// 캐시된 존 체류 시간. nil / 빈 배열 = 존 미계산. 지연 조회 + 1회 메모.
        var zones: [HRZoneData]? { box.get() }
        private let box: LazyZones

        init(id: UUID, date: Date, hasHR: Bool, zones: [HRZoneData]?) {
            self.id = id; self.date = date; self.hasHR = hasHR
            self.box = LazyZones { zones }
        }

        /// 디스크 캐시 조회처럼 비용이 있는 소스 — 검사되는 러닝만 실제로 읽는다.
        init(id: UUID, date: Date, hasHR: Bool, zonesProvider: @escaping () -> [HRZoneData]?) {
            self.id = id; self.date = date; self.hasHR = hasHR
            self.box = LazyZones(zonesProvider)
        }

        var hasZones: Bool { !(zones?.isEmpty ?? true) }

        private final class LazyZones {
            private var cached: [HRZoneData]?? = nil
            private let provider: () -> [HRZoneData]?
            init(_ provider: @escaping () -> [HRZoneData]?) { self.provider = provider }
            func get() -> [HRZoneData]? {
                if let c = cached { return c }
                let v = provider(); cached = .some(v); return v
            }
        }
    }

    struct Buckets: Equatable {
        var lowSec: Double = 0
        var midSec: Double = 0
        var highSec: Double = 0

        var totalSec: Double { lowSec + midSec + highSec }
        var lowFrac:  Double { totalSec > 0 ? lowSec  / totalSec : 0 }
        var midFrac:  Double { totalSec > 0 ? midSec  / totalSec : 0 }
        var highFrac: Double { totalSec > 0 ? highSec / totalSec : 0 }

        static func + (a: Buckets, b: Buckets) -> Buckets {
            Buckets(lowSec: a.lowSec + b.lowSec, midSec: a.midSec + b.midSec, highSec: a.highSec + b.highSec)
        }
    }

    struct Result {
        let runsTotal: Int
        let runsWithZones: Int
        /// 평균 심박조차 없는 러닝 (심박 데이터 없음)
        let runsNoHR: [RunInput]
        /// 심박은 있으나 존 캐시가 없는 러닝
        let runsZonesMissing: [RunInput]
        let buckets: Buckets
    }

    // MARK: - 러닝 1건 → 버킷

    static func buckets(for zones: [HRZoneData], policy: Zone4Policy) -> Buckets {
        func sec(_ id: Int) -> Double { zones.first(where: { $0.id == id })?.seconds ?? 0 }
        let z4 = sec(4)
        switch policy {
        case .allMedium:
            return Buckets(lowSec: sec(1) + sec(2), midSec: sec(3) + z4, highSec: sec(5))
        case .at2Split:
            // 분할 정보 없는 구버전 캐시는 Zone 4 전체를 중간으로 (호출 측에서 걸러 주는 것이 원칙)
            let upper = min(z4, zones.first(where: { $0.id == 4 })?.upperSeconds ?? 0)
            return Buckets(lowSec: sec(1) + sec(2), midSec: sec(3) + (z4 - upper), highSec: upper + sec(5))
        }
    }

    // MARK: - 창 합산

    static func aggregate(runs: [RunInput], policy: Zone4Policy) -> Result {
        var acc = Buckets()
        var noHR: [RunInput] = []
        var missing: [RunInput] = []
        var withZones = 0
        for r in runs {
            if let z = r.zones, !z.isEmpty {
                acc = acc + buckets(for: z, policy: policy)
                withZones += 1
            } else if r.hasHR {
                missing.append(r)
            } else {
                noHR.append(r)
            }
        }
        return Result(runsTotal: runs.count, runsWithZones: withZones,
                      runsNoHR: noHR, runsZonesMissing: missing, buckets: acc)
    }

    // MARK: - 주 단위 저강도 비율 (K-5)

    struct WeekLow {
        let label: String          // "2026-W36"
        let shortLabel: String     // "W36"
        let runs: Int
        let runsWithZones: Int
        let lowFrac: Double?       // nil = 존 데이터 없음 (러닝 없음 포함)
        /// `now`가 속한 주 — 아직 끝나지 않아 비율이 흔들린다. 요약 통계에서 제외.
        let inProgress: Bool
    }

    /// `anchor`가 속한 ISO 주부터 역순으로 `weeks`주의 저강도 시간 비율. 최신 → 과거.
    static func weeklyLowFractions(runs: [RunInput],
                                   anchor: Date,
                                   weeks: Int,
                                   policy: Zone4Policy,
                                   now: Date = Date(),
                                   calendar: Calendar = MRIntensityTime.isoCalendar) -> [WeekLow] {
        let eligible = runs.filter { $0.date <= anchor }
        let nowWY = calendar.component(.weekOfYear, from: now)
        let nowYR = calendar.component(.yearForWeekOfYear, from: now)
        var out: [WeekLow] = []
        for offset in 0..<weeks {
            guard let ref = calendar.date(byAdding: .weekOfYear, value: -offset, to: anchor) else { break }
            let wy = calendar.component(.weekOfYear,        from: ref)
            let yr = calendar.component(.yearForWeekOfYear, from: ref)
            let weekRuns = eligible.filter {
                calendar.component(.weekOfYear,        from: $0.date) == wy &&
                calendar.component(.yearForWeekOfYear, from: $0.date) == yr
            }
            let agg = aggregate(runs: weekRuns, policy: policy)
            let low: Double? = (agg.runsWithZones > 0 && agg.buckets.totalSec > 0) ? agg.buckets.lowFrac : nil
            out.append(WeekLow(label: "\(yr)-W\(String(format: "%02d", wy))",
                               shortLabel: "W\(String(format: "%02d", wy))",
                               runs: weekRuns.count, runsWithZones: agg.runsWithZones,
                               lowFrac: low, inProgress: wy == nowWY && yr == nowYR))
        }
        return out
    }

    /// 완료된 주 중 존 데이터가 있는 주의 저강도 비율 요약.
    static func summary(of weeks: [WeekLow]) -> (median: Double, min: Double, max: Double, count: Int)? {
        let vals = weeks.filter { !$0.inProgress }.compactMap(\.lowFrac).sorted()
        guard !vals.isEmpty else { return nil }
        let n = vals.count
        let med = n % 2 == 0 ? (vals[n / 2 - 1] + vals[n / 2]) / 2 : vals[n / 2]
        return (med, vals[0], vals[n - 1], n)
    }

    static var isoCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone.current
        return c
    }
}
