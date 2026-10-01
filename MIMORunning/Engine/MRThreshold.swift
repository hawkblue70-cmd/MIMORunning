import Foundation

// MARK: - 역치(LT2) 추정
//
// 설계: docs/superpowers/specs/2026-10-01-threshold-estimate-design.md
//
// 가민의 "젖산 역치(페이스·심박)"는 HealthKit으로 넘어오지 않는다 → 본인 기록으로 직접 추정한다.
// 원칙(문헌 = 틀, 본인 데이터 = 값):
//   · 역치 페이스 = 60분 대회 페이스 — Daniels T 페이스 정의(Daniels' Running Formula, "about the pace you could race for 60 min").
//     값은 본인 예측 하프 등가에서 앱 공통 Riegel 1.06으로 60분 거리를 풀어 낸다.
//   · 역치 심박 = (a) 심박–페이스 회귀의 역함수 × (b) 20~70분 대회급 노력의 실측 심박, 두 갈래를 교차한다.

/// 역치 페이스 정의의 대회 시간(분) — Daniels T 페이스 ≈ 60분 대회 페이스.
let MR_THRESHOLD_RACE_MIN = 60.0
/// 두 갈래 역치 심박이 "일치"로 보는 폭. ⚠ 임의로 정함 — 광학 심박 러닝 중 ±5bpm(Apple 문서)에 맞춤.
let MR_THRESHOLD_HR_AGREE_BPM = 5.0
/// 역치 페이스가 "좋아졌다"로 보는 문턱(초/km). ⚠ 임의로 정함 — 추세 문장·헤드라인 후보 문턱.
let MR_THRESHOLD_IMPROVE_SEC = 3.0

/// 한 시점(asOf) 기준 역치 추정.
struct MRThresholdEstimate: Equatable, Sendable {
    let asOf: Date
    let paceSecPerKm: Double
    let paceConfidence: MRConfidence     // 하프 예측의 confidence
    let hr: Double?
    let hrConfidence: MRConfidence       // hr nil이면 .none
    let basis: [String]                  // 화면 근거줄 (예측 근거 · 회귀 n · 노력 n)
}

/// 역치 페이스(초/km) — 하프 등가 기록(분)에서 Riegel 1.06으로 60분에 갈 수 있는 거리를 풀어 페이스로.
///
///   t = halfMin × (d / dH)^1.06  →  d = dH × (60 / halfMin)^(1/1.06),  pace = 3600 / (d/1000)
///
/// 지수 1.06은 `mrPointPaces`·`mrProjectedRefMin`과 같은 값(Riegel 1981).
func mrThresholdPace(halfEquivMin: Double) -> Double? {
    guard halfEquivMin > 10 else { return nil }
    let d = MRDistance.dH * pow(MR_THRESHOLD_RACE_MIN / halfEquivMin, 1.0 / 1.06)
    guard d > 0 else { return nil }
    return MR_THRESHOLD_RACE_MIN * 60.0 / (d / 1000.0)
}

extension MRHRPaceModel {
    /// 이 페이스(초/km, 15°C·30분 기준)로 달리면 심박이 얼마인가 — `paceAtHR`의 역함수.
    ///
    /// ⚠ 외삽 금지: 결과가 학습 데이터 심박 범위(dataHRMin...dataHRMax) 밖이면 nil.
    func hrAtPace(_ paceSec: Double) -> Double? {
        guard ok, bSpeed > 0, paceSec > 0, dataHRMax > 0 else { return nil }
        let v = 60_000.0 / paceSec               // m/min
        let hr = b0 + bSpeed * v
        guard hr >= dataHRMin && hr <= dataHRMax else { return nil }
        return hr
    }
}

/// 대회급 노력 중 20~70분짜리(역치 근처 강도)의 실측 평균 심박 중앙값.
///
/// 노력(`MRRaceEffort`)에는 심박이 없으므로 같은 날·같은 시간(±5%) 러닝을 찾아 그 `hrAvg`를 쓴다.
/// ±5%는 표준 거리 정규화(±2% 거리 → 시간 비례 보정)를 흡수하는 폭이다.
/// 인터벌 러닝은 평균 심박이 질주+회복의 평균이라 뺀다(`mrDetectEfforts`와 같은 이유).
/// ⚠ 20~70분·180일은 임의로 정함 — 60분 대회 정의 앞뒤로 역치 근처에서 버틸 수 있는 시간대, 최근 반년.
func mrSustainedEffortHR(runs: [MRWorkout], efforts: [MRRaceEffort], asOf: Date) -> (hr: Double, n: Int)? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: asOf)
    var hrs: [Double] = []
    for e in efforts where e.timeMin >= 20 && e.timeMin <= 70 {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: e.date), to: today).day ?? -1
        guard days >= 0, days <= 180 else { continue }
        let match = runs
            .filter {
                !$0.isInterval && $0.hrAvg != nil && $0.start <= asOf
                && cal.isDate($0.start, inSameDayAs: e.date)
                && abs($0.durationMin - e.timeMin) / e.timeMin <= 0.05
            }
            .min { abs($0.durationMin - e.timeMin) < abs($1.durationMin - e.timeMin) }
        if let hr = match?.hrAvg { hrs.append(hr) }
    }
    guard !hrs.isEmpty else { return nil }
    return (mrMedian(hrs), hrs.count)
}

/// 두 갈래 역치 심박을 합친다.
/// 둘 다 있고 ±`MR_THRESHOLD_HR_AGREE_BPM` 안이면 평균(보통), 어긋나면 표시 안 함(nil), 한쪽만이면 그 값(낮음).
func mrCombineThresholdHR(regression: Double?, sustained: (hr: Double, n: Int)?) -> (hr: Double, confidence: MRConfidence)? {
    switch (regression, sustained) {
    case let (r?, s?):
        guard abs(r - s.hr) <= MR_THRESHOLD_HR_AGREE_BPM else { return nil }
        return ((r + s.hr) / 2, .medium)
    case let (r?, nil):
        return (r, .low)
    case let (nil, s?):
        return (s.hr, .low)
    case (nil, nil):
        return nil
    }
}

/// 한 시점(asOf) 기준 역치 추정. 그 시점까지의 러닝만 본다 — 대회 비교와 같은 as-of 파이프라인
/// (physiology → 노력+더위 → 지수 적합 → 프로필 → 예측 → 심박–페이스 회귀). 하프 예측이 없으면 nil.
func mrThresholdAsOf(runs: [MRWorkout], restingHRSamples: [(date: Date, value: Double)],
                     dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, asOf: Date) -> MRThresholdEstimate? {
    let L = AppLanguage.shared
    let past = runs.filter { $0.start <= asOf }
    // 안정시 심박도 그 시점까지만 — 미래 샘플이 과거 추정에 새지 않게
    let phys = mrPhysiology(runs: past, restingHRSamples: restingHRSamples.filter { $0.date <= asOf },
                            dateOfBirth: dateOfBirth, sex: sex, asOf: asOf)
    let efforts = mrApplyHeat(mrDetectEfforts(runs: past, phys: phys), heat: heat)
    let fit = mrFitExponent(efforts)
    let prof = mrProfile(runs: past, efforts: efforts, asOf: asOf)
    let preds = mrPredict(efforts: efforts, fit: fit, profile: prof, heat: heat, asOf: asOf)
    guard let half = preds.first(where: { $0.label == "하프" }),
          let pace = mrThresholdPace(halfEquivMin: half.midMin) else { return nil }
    let hrp = mrFitHRPaceModel(runs: past, asOf: asOf)

    let reg = hrp.hrAtPace(pace)
    let sus = mrSustainedEffortHR(runs: past, efforts: efforts, asOf: asOf)
    let combined = mrCombineThresholdHR(regression: reg, sustained: sus)

    var basis = [L.s("하프 예측 \(mrFormatHMS(half.midMin))에서 60분 대회 페이스로 환산",
                     "60-min race pace from half prediction \(mrFormatHMS(half.midMin))")]
    if let r = reg {
        basis.append(L.s("심박–페이스 회귀(러닝 \(hrp.n)회) \(Int(r.rounded()))bpm",
                         "HR–pace regression (\(hrp.n) runs) \(Int(r.rounded()))bpm"))
    }
    if let s = sus {
        basis.append(L.s("20~70분 대회급 노력 \(s.n)회 심박 중앙값 \(Int(s.hr.rounded()))bpm",
                         "Median HR of \(s.n) race-level 20–70 min efforts \(Int(s.hr.rounded()))bpm"))
    }
    if reg != nil, sus != nil, combined == nil {
        basis.append(L.s("두 심박 추정이 \(Int(MR_THRESHOLD_HR_AGREE_BPM))bpm 넘게 어긋나 심박은 표시하지 않아요",
                         "HR not shown — the two estimates differ by more than \(Int(MR_THRESHOLD_HR_AGREE_BPM))bpm"))
    }

    return MRThresholdEstimate(asOf: asOf, paceSecPerKm: pace, paceConfidence: half.confidence,
                               hr: combined?.hr, hrConfidence: combined?.confidence ?? .none,
                               basis: basis)
}

/// 최근 6개월 월별 추세 — 5~1개월 전 각 달 말일 23:59:59 + now, 총 6시점. 추정 불가 시점은 건너뛴다. 날짜 오름차순.
func mrThresholdTrend(runs: [MRWorkout], restingHRSamples: [(date: Date, value: Double)],
                      dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, now: Date) -> [MRThresholdEstimate] {
    let cal = Calendar.current
    guard let thisMonth = cal.dateInterval(of: .month, for: now)?.start else { return [] }
    var points: [Date] = (1...5).reversed().compactMap { k in
        // k개월 전 달의 말일 23:59:59 = (이번 달 1일 − (k−1)개월) − 1초
        cal.date(byAdding: .month, value: -(k - 1), to: thisMonth)?.addingTimeInterval(-1)
    }
    points.append(now)
    return points.compactMap {
        mrThresholdAsOf(runs: runs, restingHRSamples: restingHRSamples,
                        dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: $0)
    }
    .sorted { $0.asOf < $1.asOf }
}

/// 추세 문장 — 첫 점 대비 마지막 점이 `MR_THRESHOLD_IMPROVE_SEC` 이상 빨라졌을 때만. 아니면 nil(좋아졌을 때만 말한다).
/// 개월 수 = 두 시점의 달력 월 차이(최소 1).
func mrThresholdTrendSentence(_ points: [MRThresholdEstimate]) -> String? {
    let sorted = points.sorted { $0.asOf < $1.asOf }
    guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
    let gain = first.paceSecPerKm - last.paceSecPerKm
    guard gain >= MR_THRESHOLD_IMPROVE_SEC else { return nil }
    let cal = Calendar.current
    let a = cal.dateComponents([.year, .month], from: first.asOf)
    let b = cal.dateComponents([.year, .month], from: last.asOf)
    let m = max(1, ((b.year ?? 0) - (a.year ?? 0)) * 12 + (b.month ?? 0) - (a.month ?? 0))
    let s = Int(gain.rounded())
    let L = AppLanguage.shared
    return L.s("\(m)개월간 \(s)초 빨라졌어요", "\(s)s/km faster over \(m) months")
}
