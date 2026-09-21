import Foundation

// MARK: - 수면 HRV 추세
//
// 애플워치 HRV(SDNN)는 밤중에 드문드문 샘플링된다. 하룻밤 값은 새벽 1시 값과 4시 값이 크게 달라 노이즈가 크다.
// 그래서 밤별 중앙값 → 7일 평균 → 4주(28일) 기준선 비교로만 쓴다. 절대값을 상태어에 쓰지 않는다.
//
// 근거: 저강도 기간에는 HRV가 오르고 고강도 기간에는 눌린다(Plews·Buchheit). 하루 값은 10~20% 자연 변동.
//       HRV는 회복 상태 지표이지 체력 지표가 아니다(취미 러너 10주 연구에서 체력 향상을 추적하지 못함).

/// 밤별 중앙값. 창은 **전날 15:00 ~ 당일 12:00** — 15시 이후 샘플은 다음 날 키, 12시 전은 그날 키, 12~15시는 낮이라 버린다.
/// 10ms 미만은 측정 노이즈로 버린다. 반환은 날짜(자정) 오름차순.
func mrHRVNightMedians(samples: [(Date, Double)],
                       noiseFloor: Double = 10.0,
                       calendar: Calendar = .current) -> [(date: Date, value: Double)] {
    var buckets: [Date: [Double]] = [:]
    for (t, v) in samples where v >= noiseFloor {
        let hour = calendar.component(.hour, from: t)
        let dayStart = calendar.startOfDay(for: t)
        let key: Date
        if hour >= 15 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            key = next
        } else if hour < 12 {
            key = dayStart
        } else {
            continue
        }
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
func mrRecentHardRunCount(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                          days: Int, asOf: Date,
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
        if w.isInterval || overLT1 {
            hard += 1
            lastHard = min(lastHard ?? d, d)
        }
    }
    return (hard, total, lastHard)
}
