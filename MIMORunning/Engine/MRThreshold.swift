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
/// 역치 기준 노력 창(일). 대회 예측은 최근 550일 최고 기록을 앵커로 쓰지만(최고 기록 = 예측의 근거),
/// 역치는 "지금 체력"이라 550일 앵커로는 새 최고 기록 전까지 추세가 평평하다(2026-10-01 실기기).
/// ⚠ 365일은 임의로 정함. 처음 180일은 강한 러닝이 창에서 빠질 때마다 한 달에 30초씩 출렁였다(2026-10-01 실기기
///   5'27→5'58→5'23) — 체력 변화가 아니라 근거 기록의 들고 남. 1년이면 계절마다 한 번쯤 있는 대회·강한 러닝이 창에 남는다.
let MR_THRESHOLD_WINDOW_DAYS = 365

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
/// ⚠ 20~70분은 임의로 정함 — 60분 대회 정의 앞뒤로 역치 근처에서 버틸 수 있는 시간대. 기간은 앵커와 같은 창.
func mrSustainedEffortHR(runs: [MRWorkout], efforts: [MRRaceEffort], asOf: Date) -> (hr: Double, n: Int)? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: asOf)
    var hrs: [Double] = []
    for e in efforts where e.timeMin >= 20 && e.timeMin <= 70 {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: e.date), to: today).day ?? -1
        guard days >= 0, days <= MR_THRESHOLD_WINDOW_DAYS else { continue }
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
    // 지수 적합·프로필은 전체 노력으로, 앵커만 최근 창 안에서 고른다. 창 안에 노력이 없으면 그 시점은 nil(빈 점).
    // ⚠ 전체 노력을 창으로 자르면 안 된다 — `mrDetectEfforts`는 **전 기간** 거리대별 최고 하나씩만 남기고
    //   최고 VDOT의 88% 미만을 버려서, 최근 노력은 대부분 이미 탈락해 있다(2026-10-01 실기기: 카드 사라짐).
    //   → 창 안의 러닝만으로 노력을 다시 고른다(심박 게이트·VDOT 필터도 창 안 기준).
    let cal = Calendar.current
    let windowRuns = past.filter {
        let d = cal.dateComponents([.day], from: $0.date, to: cal.startOfDay(for: asOf)).day ?? -1
        return d >= 0 && d <= MR_THRESHOLD_WINDOW_DAYS
    }
    let recent = mrApplyHeat(mrDetectEfforts(runs: windowRuns, phys: phys), heat: heat)
    let preds = mrPredict(efforts: recent, fit: fit, profile: prof, heat: heat, asOf: asOf)
    guard let half = preds.first(where: { $0.label == "하프" }),
          let pace = mrThresholdPace(halfEquivMin: half.midMin) else { return nil }
    let hrp = mrFitHRPaceModel(runs: past, asOf: asOf)
    #if DEBUG
    print("[역치:앵커] asOf \(asOf.formatted(date: .numeric, time: .omitted)) · 창 노력 \(recent.count)건 · \(half.basis.first ?? "") → \(mrFormatPace(pace))")
    #endif

    let reg = hrp.hrAtPace(pace)
    let sus = mrSustainedEffortHR(runs: past, efforts: recent, asOf: asOf)
    let combined = mrCombineThresholdHR(regression: reg, sustained: sus)

    var basis = [L.s("하프 예측 \(mrFormatHMS(half.midMin))에서 60분 대회 페이스로 환산",
                     "60-min race pace from half prediction \(mrFormatHMS(half.midMin))")]
    // 기준 기록 — mrPredict와 같은 앵커 규칙(환산시간 / 거리^1.06 최소). 언제 빠질지 보이게 며칠 전인지 밝힌다.
    if let a = recent.min(by: { $0.timeMinRef / pow($0.distanceM, 1.06) < $1.timeMinRef / pow($1.distanceM, 1.06) }) {
        let ago = cal.dateComponents([.day], from: a.date, to: cal.startOfDay(for: asOf)).day ?? 0
        let name = a.label == "하프" ? L.s("하프", "Half") : a.label
        basis.append(L.s("기준 기록: \(name) \(mrFormatDisplay(a.timeMin)) (\(ago)일 전)",
                         "Anchor: \(name) \(mrFormatDisplay(a.timeMin)) (\(ago) days ago)"))
    }
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

/// 추세 시점 — 오늘에서 5~0개월 전, 매달 같은 날짜로 6시점(간격 고르게). 날짜 오름차순.
/// (처음엔 "각 달 말일 + now"였는데 월초에는 지난달 말일과 하루 차이로 점이 겹쳤다 — 2026-10-01 실기기)
func mrThresholdTrendDates(now: Date) -> [Date] {
    let cal = Calendar.current
    return (0...5).reversed().compactMap { k in
        k == 0 ? now : cal.date(byAdding: .month, value: -k, to: now)
    }
}

/// 심박 기준 추세의 창(일). ⚠ 90일은 임의로 정함 — 레벨 판정 창과 같게. 최근 체력만 본다.
let MR_THRESHOLD_TREND_HR_WINDOW_DAYS = 90
/// 역치 심박 ± 이 폭 안의 러닝을 모은다. ⚠ 3bpm은 임의로 정함 — 이지 페이스 실측 구간(±5)보다 좁게: 역치 근처만.
let MR_THRESHOLD_TREND_HR_BAND = 3.0
/// 한 점에 필요한 최소 러닝 수. ⚠ 임의로 정함 — 중앙값이 한두 건에 끌려가지 않게.
let MR_THRESHOLD_TREND_MIN_RUNS = 3

/// 역치 심박으로 실제 달린 러닝의 페이스 중앙값 — 그 시점까지 최근 90일, 평균 심박(15°C 기준) 역치 ±3bpm.
///
/// ⚠ 처음엔 90일 심박–페이스 회귀였는데 실기기에서 무너졌다(2026-10-01): 러닝 평균 심박이 141~160bpm 좁은 띠에
///   몰려 있어 페이스가 달라도 심박이 거의 같다 → 기울기가 0 근처 → 3개월 빈 점, 나머지는 4'47"~5'14" 잡음.
///   코드베이스 원칙대로 회귀 대신 **실측 구간 중앙값**을 쓰고 표본 수를 밝힌다(`MRHRPaceLookup`과 같은 방식).
/// 기온은 1년치 더위–심박 모델(`MRHeatHRModel`, 더운 날 카드와 같은 것)로 15°C 기준 심박에 맞춘 뒤 고른다.
/// 인터벌은 평균 심박·페이스가 질주+회복의 평균이라 뺀다.
func mrPaceAtThresholdHR(runs: [MRWorkout], thresholdHR: Double, heatHR: MRHeatHRModel,
                         asOf: Date) -> MRThresholdEstimate? {
    let cal = Calendar.current
    let paces: [Double] = runs.compactMap { w in
        let d = cal.dateComponents([.day], from: w.date, to: cal.startOfDay(for: asOf)).day ?? -1
        guard w.start <= asOf, d >= 0, d <= MR_THRESHOLD_TREND_HR_WINDOW_DAYS,
              !w.indoor, !w.isInterval, w.durationMin >= 20, (w.distanceKm ?? 0) >= 2,
              let ref = heatHR.refHR(of: w), abs(ref - thresholdHR) <= MR_THRESHOLD_TREND_HR_BAND
        else { return nil }
        return w.paceSecPerKm
    }
    let lo = Int((thresholdHR - MR_THRESHOLD_TREND_HR_BAND).rounded())
    let hi = Int((thresholdHR + MR_THRESHOLD_TREND_HR_BAND).rounded())
    guard paces.count >= MR_THRESHOLD_TREND_MIN_RUNS else {
        #if DEBUG
        print("[역치:심박추세] asOf \(asOf.formatted(date: .numeric, time: .omitted)) · \(lo)~\(hi)bpm 러닝 \(paces.count)회 → 빈 점")
        #endif
        return nil
    }
    let pace = mrMedian(paces)
    #if DEBUG
    print("[역치:심박추세] asOf \(asOf.formatted(date: .numeric, time: .omitted)) · \(lo)~\(hi)bpm 러닝 \(paces.count)회 → \(mrFormatPace(pace))")
    #endif
    let L = AppLanguage.shared
    return MRThresholdEstimate(
        asOf: asOf, paceSecPerKm: pace, paceConfidence: paces.count >= 8 ? .medium : .low,
        hr: thresholdHR, hrConfidence: .none,
        basis: [L.s("최근 90일 평균 심박 \(lo)~\(hi)bpm(15°C 기준) 러닝 \(paces.count)회의 중간 페이스",
                    "Median pace of \(paces.count) runs at \(lo)–\(hi)bpm avg HR (15°C) in the last 90 days")])
}

/// 성장 탭 카드 재료 — 큰 숫자(현재 추정)와 추세선을 따로 낸다.
///
/// 추세선을 기록 기준(창 안 최고 노력)으로 그리면 창 길이에 따라 출렁이거나(180일, 한 달 30초) 평평했다(365일) —
/// 최고 기록은 드물게 바뀌는 최댓값이라서다(2026-10-01 실기기). 그래서 심박이 있으면 추세선은
/// **역치 심박으로 실제 달린 러닝의 페이스**(최근 90일 실측 구간 중앙값)로 그린다 — 가민 자동 감지와 같은 원리(심박·페이스 패턴).
/// 심박이 없으면(폰 러닝) 기록 기준 점으로 그린다.
struct MRThresholdTrendResult: Equatable, Sendable {
    let current: MRThresholdEstimate
    let line: [MRThresholdEstimate]
    /// 추세선이 심박 기준인가 — 카드 설명 줄이 달라진다
    let lineIsHRBased: Bool
}

func mrThresholdTrend(runs: [MRWorkout], restingHRSamples: [(date: Date, value: Double)],
                      dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, heatHR: MRHeatHRModel,
                      now: Date) -> MRThresholdTrendResult? {
    guard let current = mrThresholdAsOf(runs: runs, restingHRSamples: restingHRSamples,
                                        dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: now) else { return nil }
    let dates = mrThresholdTrendDates(now: now)
    if let lthr = current.hr {
        let line = dates.compactMap { mrPaceAtThresholdHR(runs: runs, thresholdHR: lthr, heatHR: heatHR, asOf: $0) }
        return MRThresholdTrendResult(current: current, line: line, lineIsHRBased: true)
    }
    let line = dates.dropLast().compactMap {
        mrThresholdAsOf(runs: runs, restingHRSamples: restingHRSamples,
                        dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: $0)
    } + [current]
    return MRThresholdTrendResult(current: current, line: line, lineIsHRBased: false)
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
