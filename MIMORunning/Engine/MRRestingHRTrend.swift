import Foundation

/// 성장 탭 '안정시 심박' 추세 — 월별 중앙값 선 + 기준 대비 변화.
///
/// 문헌(틀): 지구력 훈련은 안정시 심박을 평균 4~6bpm 낮춘다(Reimers 2018 메타분석, 121개 지구력 개입).
///   효과가 작아 두 점 비교로는 계절·측정 흔들림에 묻힌다 → 달마다 중앙값을 잇는 선으로 보여준다.
/// 본인 데이터(값): 기준은 "러닝 시작 전 90일"(데이터가 있으면), 없으면 조회 창의 첫 90일.
/// ⚠ 의료적 해석(사망 위험·심폐 향상)은 문장에 넣지 않는다 — 숫자 변화만.
struct MRRestingHRTrend: Equatable, Sendable {
    struct Month: Equatable, Sendable {
        let month: Date      // 그 달 1일 0시
        let median: Double
        let days: Int        // 그 달 안정시 심박 표본 수(하루 1개)
    }
    enum BaselineKind: Equatable, Sendable {
        case beforeRunning   // 첫 러닝 전 90일
        case windowStart     // 조회 창 첫 90일(러닝 시작 전 데이터가 없을 때)
    }

    let months: [Month]          // 표본 MR_RHR_MONTH_MIN_DAYS일 이상인 달만, 오래된 순
    let recent: Double           // 최근 90일 중앙값
    let recentDays: Int
    let baseline: Double?
    let baselineKind: BaselineKind?
    let baselineStart: Date?     // 기준 창 시작일

    /// 최근 − 기준 (음수 = 낮아짐)
    var change: Double? { baseline.map { recent - $0 } }

    /// 기준 창 시작부터 지금까지 개월 수(반올림, 최소 1)
    func monthsSinceBaseline(asOf: Date) -> Int? {
        guard let s = baselineStart else { return nil }
        let d = Calendar.current.dateComponents([.day], from: s, to: asOf).day ?? 0
        return max(1, Int((Double(d) / 30.4).rounded()))
    }

    /// 한 줄 문장 — 낮아졌을 때만 말한다(설계 원칙 5: 좌절 방지, 오른 건 선으로만 보인다).
    /// ⚠ 3bpm 문턱은 임의값 — 월 중앙값의 흔들림(대개 1~2bpm)보다 크고, 문헌 효과(4~6)보다 작게. 실기기 로그로 재검토.
    func sentence(asOf: Date) -> String? {
        guard let c = change, c <= -MR_RHR_SENTENCE_MIN_DROP, let kind = baselineKind else { return nil }
        let n = Int((-c).rounded())
        let L = AppLanguage.shared
        switch kind {
        case .beforeRunning:
            return L.s("러닝을 시작한 뒤 \(n)bpm 낮아졌습니다",
                       "\(n) bpm lower since you started running")
        case .windowStart:
            let m = monthsSinceBaseline(asOf: asOf) ?? 0
            return L.s("\(m)개월 전보다 \(n)bpm 낮습니다",
                       "\(n) bpm lower than \(m) months ago")
        }
    }
}

let MR_RHR_MONTH_MIN_DAYS = 10       // 달 중앙값을 믿을 최소 표본 일수
let MR_RHR_WINDOW_MIN_DAYS = 20      // 90일 창(최근·기준) 최소 표본 일수
let MR_RHR_MIN_MONTHS = 3            // 선을 그릴 최소 달 수
let MR_RHR_SENTENCE_MIN_DROP = 3.0   // 문장을 붙일 최소 하락(bpm)

/// 월별 중앙값과 기준 대비 변화. 표본이 모자라면 nil(카드가 조용히 빠진다).
/// - firstRunDate: 첫 러닝 시작일. 그 전 90일에 표본이 충분하면 그 창이 기준.
func mrRestingHRTrend(samples: [(date: Date, value: Double)],
                      firstRunDate: Date?,
                      asOf: Date) -> MRRestingHRTrend? {
    let cal = Calendar.current
    let past = samples.filter { $0.date <= asOf }.sorted { $0.date < $1.date }
    guard let first = past.first else { return nil }

    // 월별 중앙값
    var byMonth: [Date: [Double]] = [:]
    for s in past {
        let m = cal.date(from: cal.dateComponents([.year, .month], from: s.date))!
        byMonth[m, default: []].append(s.value)
    }
    let months = byMonth
        .filter { $0.value.count >= MR_RHR_MONTH_MIN_DAYS }
        .map { MRRestingHRTrend.Month(month: $0.key, median: mrMedian($0.value), days: $0.value.count) }
        .sorted { $0.month < $1.month }
    guard months.count >= MR_RHR_MIN_MONTHS else { return nil }

    // 최근 90일
    let recentStart = cal.date(byAdding: .day, value: -90, to: asOf)!
    let recentVals = past.filter { $0.date > recentStart }.map(\.value)
    guard recentVals.count >= MR_RHR_WINDOW_MIN_DAYS else { return nil }

    // 기준: 러닝 시작 전 90일 → 없으면 창 첫 90일(최근 90일과 겹치지 않을 때만)
    var baseline: Double? = nil
    var kind: MRRestingHRTrend.BaselineKind? = nil
    var baseStart: Date? = nil
    if let fr = firstRunDate {
        let lo = cal.date(byAdding: .day, value: -90, to: fr)!
        let vals = past.filter { $0.date >= lo && $0.date < fr }.map(\.value)
        if vals.count >= MR_RHR_WINDOW_MIN_DAYS {
            baseline = mrMedian(vals); kind = .beforeRunning; baseStart = lo
        }
    }
    if baseline == nil {
        let hi = cal.date(byAdding: .day, value: 90, to: first.date)!
        if hi <= recentStart {
            let vals = past.filter { $0.date < hi }.map(\.value)
            if vals.count >= MR_RHR_WINDOW_MIN_DAYS {
                baseline = mrMedian(vals); kind = .windowStart; baseStart = first.date
            }
        }
    }

    return MRRestingHRTrend(months: months,
                            recent: mrMedian(recentVals), recentDays: recentVals.count,
                            baseline: baseline, baselineKind: kind, baselineStart: baseStart)
}

/// 단기 상승 구간 수 — 아침 제안 보조 규칙(검토 중)의 발동 빈도 확인용. 로그 전용.
/// 규칙(문헌 틀): 그날 값이 직전 28일 중앙값보다 `rise`bpm 이상 높은 날이 `run`일 이상 이어지면 1회.
/// 직전 28일에 표본 14일 미만이면 그날은 판정하지 않는다(연속이 끊긴다).
func mrRestingHRRiseEpisodes(samples: [(date: Date, value: Double)],
                             from: Date, to: Date,
                             rise: Double = 5, run: Int = 3) -> (episodes: Int, flaggedDays: Int) {
    let cal = Calendar.current
    let sorted = samples.sorted { $0.date < $1.date }
    var episodes = 0, flagged = 0, streak = 0
    var prevDay: Date? = nil
    for (i, s) in sorted.enumerated() where s.date >= from && s.date <= to {
        let day = cal.startOfDay(for: s.date)
        let lo = cal.date(byAdding: .day, value: -28, to: day)!
        let window = sorted[..<i].filter { $0.date >= lo && $0.date < day }.map(\.value)
        // 날짜가 하루 넘게 비면 연속을 끊는다
        if let p = prevDay, (cal.dateComponents([.day], from: p, to: day).day ?? 0) > 1 { streak = 0 }
        prevDay = day
        guard window.count >= 14 else { streak = 0; continue }
        if s.value >= mrMedian(window) + rise {
            flagged += 1
            streak += 1
            if streak == run { episodes += 1 }
        } else {
            streak = 0
        }
    }
    return (episodes, flagged)
}
