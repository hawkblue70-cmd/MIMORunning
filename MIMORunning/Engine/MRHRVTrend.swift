import Foundation

// MARK: - 수면 HRV 추세
//
// 애플워치 HRV(SDNN)는 밤중에 드문드문 샘플링된다. 하룻밤 값은 새벽 1시 값과 4시 값이 크게 달라 노이즈가 크다.
// 그래서 밤별 중앙값 → 7일 평균 → 4주(28일) 기준선 비교로만 쓴다. 절대값을 상태어에 쓰지 않는다.
//
// 근거: 저강도 기간에는 HRV가 오르고 고강도 기간에는 눌린다(Plews·Buchheit). 하루 값은 10~20% 자연 변동.
//       HRV는 회복 상태 지표이지 체력 지표가 아니다(취미 러너 10주 연구에서 체력 향상을 추적하지 못함).

/// 밤 키 — 15시 이후는 다음 날, 12시 전은 그날, 12~15시는 낮이라 nil.
private func mrHRVNightKey(_ t: Date, calendar: Calendar) -> Date? {
    let hour = calendar.component(.hour, from: t)
    let dayStart = calendar.startOfDay(for: t)
    if hour >= 15 { return calendar.date(byAdding: .day, value: 1, to: dayStart) }
    if hour < 12 { return dayStart }
    return nil
}

/// 밤별 중앙값.
/// - `asleep`(잠든 구간)이 있으면 **잠든 동안 찍힌 값만** 그 밤에 넣는다(구간 끝 = 기상 시각의 밤 키). 기상 후 깨어 있을 때 값은
///   수면 값보다 낮아 중앙값을 끌어내리므로 버린다 — 애플 건강의 '수면' HRV와 같은 재료. 구간 경계 ±15분은 포함.
/// - 수면 기록이 없는 밤은 창 규칙으로 폴백: **전날 15:00 ~ 당일 12:00** — 15시 이후 샘플은 다음 날 키, 12시 전은 그날 키, 12~15시는 버림.
/// 10ms 미만은 측정 노이즈로 버린다. 반환은 날짜(자정) 오름차순.
func mrHRVNightMedians(samples: [(Date, Double)],
                       asleep: [(start: Date, end: Date)] = [],
                       noiseFloor: Double = 10.0,
                       calendar: Calendar = .current) -> [(date: Date, value: Double)] {
    let margin: TimeInterval = 15 * 60
    // 잠든 구간 → 밤 키(기상 시각 기준). 여백을 미리 더하고 시작 시각으로 정렬해 이진 탐색한다 —
    // 수면 단계 샘플은 60일에 수천 개, HRV 샘플은 천 개 남짓이라 선형 탐색(수백만 비교)은 메인 스레드를 초 단위로 세운다.
    let keyed: [(start: TimeInterval, end: TimeInterval, key: Date)] = asleep.compactMap { iv in
        guard let k = mrHRVNightKey(iv.end, calendar: calendar) ?? mrHRVNightKey(iv.start, calendar: calendar) else { return nil }
        return (iv.start.timeIntervalSinceReferenceDate - margin, iv.end.timeIntervalSinceReferenceDate + margin, k)
    }.sorted { $0.start < $1.start }
    let nightsWithSleep = Set(keyed.map(\.key))
    /// t를 품는 구간 — 시작이 t 이하인 마지막 구간부터 몇 개만 거슬러 본다(구간이 겹칠 수 있어 최대 8개).
    func containing(_ t: TimeInterval) -> Date? {
        var lo = 0, hi = keyed.count
        while lo < hi { let mid = (lo + hi) / 2; if keyed[mid].start <= t { lo = mid + 1 } else { hi = mid } }
        var i = lo - 1, steps = 0
        while i >= 0 && steps < 8 {
            if keyed[i].end >= t { return keyed[i].key }
            i -= 1; steps += 1
        }
        return nil
    }

    var buckets: [Date: [Double]] = [:]
    for (t, v) in samples where v >= noiseFloor {
        if let key = containing(t.timeIntervalSinceReferenceDate) {
            buckets[key, default: []].append(v)
            continue
        }
        guard let key = mrHRVNightKey(t, calendar: calendar) else { continue }
        // 그 밤에 수면 기록이 있는데 잠든 구간 밖이면(기상 후 낮 값) 버린다. 수면 기록이 없는 밤만 창 규칙.
        if nightsWithSleep.contains(key) { continue }
        buckets[key, default: []].append(v)
    }
    return buckets.keys.sorted().map { ($0, mrMedian(buckets[$0]!)) }
}

struct MRHRVTrend: Equatable {
    enum State: Equatable { case above, within, below }
    let state: State
    /// 7일 변동계수가 4주 변동계수의 1.5배를 넘는다
    let isVolatile: Bool
    let sevenDayMean: Double     // ms
    let baseline: Double         // 4주 중앙값, ms
    let baselineSD: Double       // 4주 표본 표준편차(하한 적용 전)
    let sevenDayCV: Double
    let baselineCV: Double
    let sevenDayNights: Int
    let baselineNights: Int

    /// 안정 상승 — 기준선 위이면서 7일 변동계수가 4주의 절반 미만. 평균이 유지·상승하며 변동이 줄면
    /// 훈련을 잘 소화하는 상태(Plews·Buchheit, Flatt·Esco). 밴드(±0.5SD)에는 못 미쳐도 "위·안정"으로 인정한다.
    var isStableRise: Bool {
        sevenDayMean > baseline && baselineCV > 0 && sevenDayCV < MRHRVTrend.stableRiseCVRatio * baselineCV
    }
    /// 위·안정 — 강도 세션 제안 조건. 밴드 위이거나 안정 상승.
    var isReadyHigh: Bool { (state == .above && !isVolatile) || isStableRise }
    /// 아래 또는 불안정 — "충분히 회복" 억제 조건
    var isSuppressed: Bool { state == .below || isVolatile }

    /// 상태어 — 본인 4주 기준선 대비 관찰어(절대 등급 아님). 억제(불안정·아래)가 좋음보다 먼저. 총평 근거·아침 제안이 같이 쓴다.
    var gradeLabel: String {
        let L = AppLanguage.shared
        if isVolatile { return L.s("불안정", "unstable") }
        if state == .below { return L.s("낮음", "low") }
        if isReadyHigh { return L.s("좋음", "good") }
        return L.s("보통", "normal")
    }

    static let minRecentNights = 4
    static let minBaselineNights = 14
    static let bandSD = 0.5
    static let volatileRatio = 1.5
    static let stableRiseCVRatio = 0.5
    /// SD 하한 = 기준선의 10% — 4주가 너무 고르면 밴드가 0에 가까워져 판정이 튄다
    static let sdFloorFraction = 0.10
}

/// 표본 표준편차(n−1). n < 2면 0.
private func mrSampleSD(_ v: [Double]) -> Double {
    guard v.count >= 2 else { return 0 }
    let mean = v.reduce(0, +) / Double(v.count)
    let variance = v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count - 1)
    return variance.squareRoot()
}

/// `asOf`(러닝 날짜) 기준 — 7일 창 = day(asOf)−6…day(asOf), 4주 창 = day(asOf)−34…day(asOf)−7.
/// 러닝 전날 밤이 day(asOf) 키다. 유효 밤이 7일 4 미만 또는 4주 14 미만이면 nil.
func mrHRVTrend(nights: [(date: Date, value: Double)], asOf: Date,
                calendar: Calendar = .current) -> MRHRVTrend? {
    let today = calendar.startOfDay(for: asOf)
    func daysBefore(_ d: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: today).day ?? Int.min
    }
    var recent: [Double] = []
    var base: [Double] = []
    for n in nights {
        let d = daysBefore(n.date)
        if d >= 0 && d <= 6 { recent.append(n.value) }
        else if d >= 7 && d <= 34 { base.append(n.value) }
    }
    guard recent.count >= MRHRVTrend.minRecentNights,
          base.count >= MRHRVTrend.minBaselineNights else { return nil }

    let mean7 = recent.reduce(0, +) / Double(recent.count)
    let baseline = mrMedian(base)
    let baseMean = base.reduce(0, +) / Double(base.count)
    let sd28 = mrSampleSD(base)
    let sdEff = max(sd28, baseline * MRHRVTrend.sdFloorFraction)
    let cv7 = mean7 > 0 ? mrSampleSD(recent) / mean7 : 0
    let cv28 = baseMean > 0 ? sd28 / baseMean : 0

    let state: MRHRVTrend.State
    if mean7 > baseline + MRHRVTrend.bandSD * sdEff { state = .above }
    else if mean7 < baseline - MRHRVTrend.bandSD * sdEff { state = .below }
    else { state = .within }

    let volatile = cv28 > 0 && cv7 > MRHRVTrend.volatileRatio * cv28

    return MRHRVTrend(state: state, isVolatile: volatile,
                      sevenDayMean: mean7, baseline: baseline, baselineSD: sd28,
                      sevenDayCV: cv7, baselineCV: cv28,
                      sevenDayNights: recent.count, baselineNights: base.count)
}

// MARK: - 최근 N일 고강도 횟수 (조언 큐용, MRWorkout 세계)

/// 인터벌이거나 15°C 보정 평균심박이 LT1 이상이면 고강도. LT1이 없으면 인터벌만 센다.
/// 창은 `asOf` 자정 기준 직전 `days`일(오늘 포함). `lastHardDaysAgo`는 창 안 가장 최근 고강도까지의 일수(없으면 nil).
/// `extraHardStarts`: 앱 쪽 판정(분류된 유형·체감 강도·존 분포)으로 고강도인 러닝의 시작 시각 — 엔진의 `isInterval`은
/// WorkoutKit 구조화 운동만 잡아서, 앱이 "인터벌"로 분류한 러닝을 놓친다.
func mrRecentHardRunCount(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                          days: Int, asOf: Date,
                          extraHardStarts: Set<Date> = [],
                          calendar: Calendar = .current) -> (hard: Int, total: Int, lastHardDaysAgo: Int?) {
    let today = calendar.startOfDay(for: asOf)
    var hard = 0, total = 0
    var lastHard: Int? = nil
    for w in runs {
        let d = calendar.dateComponents([.day], from: w.date, to: today).day ?? Int.min
        guard d >= 0 && d < days else { continue }
        total += 1
        // refHR는 hrAvg가 nil일 때만 nil — 심박 없는 러닝은 고강도로 세지 않는다
        let overLT1: Bool = {
            guard let lt1 = phys.lt1HR?.value, let hr = heatHR.refHR(of: w) else { return false }
            return hr >= lt1
        }()
        if w.isInterval || overLT1 || extraHardStarts.contains(w.start) {
            hard += 1
            lastHard = min(lastHard ?? d, d)
        }
    }
    return (hard, total, lastHard)
}
