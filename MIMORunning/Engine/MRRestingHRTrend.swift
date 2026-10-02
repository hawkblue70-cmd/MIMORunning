import Foundation

/// 성장 탭 '안정시 심박' 추세 — 월별 중앙값 선 + 12개월 이동평균(추세선) + 1년 전 같은 기간 숫자 + 오르내림의 일반 원인.
///
/// 문헌(틀): 지구력 훈련은 안정시 심박을 평균 4~6bpm 낮추고(Reimers 2018 메타분석), 훈련을 쉬면 몇 주 안에 2~9bpm 오른다(디트레이닝 리뷰).
///   효과가 작아 계절 흔들림(겨울에 몇 bpm↑)과 크기가 같다 → 추세는 계절을 지운 값으로만 말한다.
/// ⚠ 계절을 지우는 방법(2026-10-02 검토):
///   - 두 90일 창 비교(겨울 vs 여름)는 계절 차이를 훈련 효과로 말했다(실기기: 36개월 전 64 vs 최근 60).
///   - 최근 12개월 직선 회귀도 안 된다 — 5bpm 계절 곡선만 있어도 지금이 몇 월이냐에 따라 ±5bpm "추세"가 나온다.
///   → 같은 달끼리 비교(올해 3월 − 작년 3월)의 평균. 계절이 정확히 빠진다. 선은 12개월 이동평균.
/// ⚠ 의료적 해석(사망 위험·질병)은 넣지 않는다 — 일반적으로 알려진 훈련 반응만.
struct MRRestingHRTrend: Equatable, Sendable {
    struct Month: Equatable, Sendable {
        let month: Date      // 그 달 1일 0시
        let median: Double
        let days: Int        // 그 달 안정시 심박 표본 수(하루 1개)
    }
    struct Point: Equatable, Sendable {
        let date: Date
        let value: Double   // bpm(이동평균) 또는 km(월별 거리)
    }

    let months: [Month]          // 표본 MR_RHR_MONTH_MIN_DAYS일 이상인 달만, 오래된 순
    let recent: Double           // 최근 90일 중앙값
    let recentDays: Int
    /// 12개월 이동평균(그 달까지 12개 달력 달 중 MR_RHR_ROLLING_MIN_MONTHS달 이상일 때만) — 차트 점선.
    let rolling: [Point]
    /// 최근 12개월 각 달 − 1년 전 같은 달의 평균(계절 제거). 짝이 MR_RHR_YOY_MIN_PAIRS개 미만이면 nil.
    /// 화면에는 쓰지 않는다 — 12개월 평균이라 부상·복귀 같은 최근 변화를 늦게 반영한다. 로그·검토용.
    let yearChange: Double?
    let yearPairs: Int

    /// 1년 전 같은 90일 중앙값 — 큰 숫자 옆 비교(계절을 맞춘 사실). 표본 부족이면 nil.
    let recentLY: Double?
    /// 월별 러닝 거리(km) — 선과 같은 달 범위, 안 달린 달은 0. 앱이 아는 유일한 맥락이라 막대로 깔아
    /// 오르내림을 본인이 훈련과 맞춰 보게 한다(2026-10-02 사용자 요청 — 부상 휴식 달이 빈 막대로 보인다).
    let monthlyKm: [Point]

    /// 오르내림의 일반적인 원인 — 판정하지 않고 늘 같은 문장(2026-10-02 사용자 결정).
    /// ⚠ 앱은 부상·질병·생활 변화를 모른다. 실기기: 2026년 3월 부상 휴식으로 70까지 올랐다가 복귀 후 60으로 내려왔는데,
    ///   같은 달 비교(+2.8)는 "높아지는 추세"라고 말했다 — 원인은 본인이 그래프를 보고 판단한다.
    static var explainer: String {
        AppLanguage.shared.s("훈련이 쌓이면 낮아집니다(훈련 연구 평균 4~6bpm). 쉬거나 부상·질병·수면 부족·스트레스가 있으면 몇 주 안에 2~9bpm 오릅니다. 오르내린 시기를 그때의 훈련·생활과 맞춰 보세요.",
                             "It drops as training builds up (studies average 4–6 bpm). Rest, injury, illness, poor sleep or stress can raise it 2–9 bpm within weeks. Match the rises and falls to what was happening in your training and life.")
    }
}

let MR_RHR_MONTH_MIN_DAYS = 10       // 달 중앙값을 믿을 최소 표본 일수
let MR_RHR_WINDOW_MIN_DAYS = 20      // 최근 90일 최소 표본 일수
let MR_RHR_MIN_MONTHS = 3            // 선을 그릴 최소 달 수
let MR_RHR_ROLLING_MIN_MONTHS = 10   // 12개월 이동평균에 필요한 최소 달 수(빠진 달이 많으면 계절이 덜 지워진다)
let MR_RHR_YOY_MIN_PAIRS = 6         // 같은 달 비교 최소 짝 수(최근 12개월 중)

/// 월별 중앙값·12개월 이동평균·1년 전 같은 달 대비 변화. 표본이 모자라면 nil(카드가 조용히 빠진다).
func mrRestingHRTrend(samples: [(date: Date, value: Double)],
                      runs: [(date: Date, km: Double)] = [],
                      asOf: Date) -> MRRestingHRTrend? {
    let cal = Calendar.current
    let past = samples.filter { $0.date <= asOf }.sorted { $0.date < $1.date }
    guard !past.isEmpty else { return nil }

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
    let medianOf = Dictionary(uniqueKeysWithValues: months.map { ($0.month, $0.median) })
    func shift(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: d)! }

    // 최근 90일
    let recentStart = cal.date(byAdding: .day, value: -90, to: asOf)!
    let recentVals = past.filter { $0.date > recentStart }.map(\.value)
    guard recentVals.count >= MR_RHR_WINDOW_MIN_DAYS else { return nil }

    // 12개월 이동평균 — 그 달 포함 앞 12개 달력 달
    let rolling: [MRRestingHRTrend.Point] = months.compactMap { m in
        let vals = (0..<12).compactMap { medianOf[shift(m.month, -$0)] }
        guard vals.count >= MR_RHR_ROLLING_MIN_MONTHS else { return nil }
        return .init(date: m.month, value: vals.reduce(0, +) / Double(vals.count))
    }

    // 같은 달 비교 — 이번 달 포함 최근 12개 달력 달 각각 − 12개월 전
    let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: asOf))!
    let diffs: [Double] = (0..<12).compactMap { k in
        let m = shift(thisMonth, -k)
        guard let now = medianOf[m], let ago = medianOf[shift(m, -12)] else { return nil }
        return now - ago
    }
    let yearChange = diffs.count >= MR_RHR_YOY_MIN_PAIRS ? diffs.reduce(0, +) / Double(diffs.count) : nil

    // 월별 러닝 거리 — 선의 첫 달 ~ 이번 달, 빈 달은 0
    var kmBy: [Date: Double] = [:]
    for r in runs where r.date <= asOf {
        kmBy[cal.date(from: cal.dateComponents([.year, .month], from: r.date))!, default: 0] += r.km
    }
    var monthlyKm: [MRRestingHRTrend.Point] = []
    var m = months.first!.month
    while m <= thisMonth {
        monthlyKm.append(.init(date: m, value: kmBy[m] ?? 0))
        m = shift(m, 1)
    }

    // 1년 전 같은 90일
    let lyLo = cal.date(byAdding: .year, value: -1, to: recentStart)!
    let lyHi = cal.date(byAdding: .year, value: -1, to: asOf)!
    let lyVals = past.filter { $0.date > lyLo && $0.date <= lyHi }.map(\.value)

    return MRRestingHRTrend(months: months,
                            recent: mrMedian(recentVals), recentDays: recentVals.count,
                            rolling: rolling, yearChange: yearChange, yearPairs: diffs.count,
                            recentLY: lyVals.count >= MR_RHR_WINDOW_MIN_DAYS ? mrMedian(lyVals) : nil,
                            monthlyKm: monthlyKm)
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

// MARK: - 아침 제안 — 안정시 심박 며칠째 높음

/// 문헌(틀): 기준선보다 5~10bpm 높은 안정시 심박이 3일 이상 이어지면 과부하·회복 부족·몸살 신호로 강도를 낮춘다.
/// 본인 데이터(값): 기준선 = 그날 전 28일 중앙값(표본 14일↑). 사용자 실기기 1년 = +5bpm 3일 연속 4회(분기 1회꼴, 2026-10-02 로그).
let MR_RHR_ELEVATED_RISE = 5.0
let MR_RHR_ELEVATED_DAYS = 3

struct MRRestingHRElevation: Equatable {
    let days: Int        // 마지막 날부터 거꾸로 이어진 높은 날 수
    let latest: Double   // 마지막 날 값
    let usual: Double    // 마지막 날 기준선(전 28일 중앙값)
}

/// 가장 최근 날(오늘 또는 어제여야 함)부터 거꾸로, 기준선 + 5bpm 이상인 날이 며칠 이어졌나.
/// 높은 날이 없거나 자료가 이틀 넘게 끊겼으면 nil. 문턱(3일) 판단은 호출부가 한다.
/// ⚠ 애플의 오늘자 안정시 심박은 하루 동안 갱신된다 — 아침엔 없을 수 있어 어제까지로도 판정한다.
func mrRestingHRElevation(samples: [(date: Date, value: Double)], asOf: Date,
                          calendar cal: Calendar = .current) -> MRRestingHRElevation? {
    // 하루 1개 — 같은 날 여러 개면 마지막 값
    var byDay: [Date: Double] = [:]
    for s in samples where s.date <= asOf { byDay[cal.startOfDay(for: s.date)] = s.value }
    let today = cal.startOfDay(for: asOf)
    guard let last = byDay.keys.max(),
          let gap = cal.dateComponents([.day], from: last, to: today).day, gap <= 1 else { return nil }

    func usual(before day: Date) -> Double? {
        let lo = cal.date(byAdding: .day, value: -28, to: day)!
        let vals = byDay.filter { $0.key >= lo && $0.key < day }.map(\.value)
        return vals.count >= 14 ? mrMedian(vals) : nil
    }

    guard let lastUsual = usual(before: last), byDay[last]! >= lastUsual + MR_RHR_ELEVATED_RISE else { return nil }
    var days = 1
    var d = cal.date(byAdding: .day, value: -1, to: last)!
    while let v = byDay[d], let u = usual(before: d), v >= u + MR_RHR_ELEVATED_RISE {
        days += 1
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return MRRestingHRElevation(days: days, latest: byDay[last]!, usual: lastUsual)
}
