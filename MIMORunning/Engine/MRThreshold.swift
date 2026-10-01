import Foundation

// MARK: - 역치(LT2) 추정
//
// 설계: docs/superpowers/specs/2026-10-01-threshold-estimate-design.md
//
// 가민의 "젖산 역치(페이스·심박)"는 HealthKit으로 넘어오지 않는다 → 본인 기록으로 직접 추정한다.
// 원칙(문헌 = 틀, 본인 데이터 = 값):
//   · 역치 페이스 = 60분 대회 페이스 — Daniels T 페이스 정의(Daniels' Running Formula, "about the pace you could race for 60 min").
//     값은 **기준 기록**(최근 24개월 확정 대회 중 최고, 대회가 없으면 대회급 노력 중 최고)을 하프 등가로 옮긴 뒤
//     Riegel 1.06으로 60분 거리를 풀어 낸다.
//   · 역치 심박 = (a) 심박–페이스 회귀의 역함수 × (b) 20~70분 대회급 노력의 실측 심박, 두 갈래를 교차한다.

/// 역치 페이스 정의의 대회 시간(분) — Daniels T 페이스 ≈ 60분 대회 페이스.
let MR_THRESHOLD_RACE_MIN = 60.0
/// 두 갈래 역치 심박이 "일치"로 보는 폭. ⚠ 임의로 정함 — 광학 심박 러닝 중 ±5bpm(Apple 문서)에 맞춤.
let MR_THRESHOLD_HR_AGREE_BPM = 5.0
/// 역치 페이스가 "좋아졌다"로 보는 문턱(초/km). ⚠ 임의로 정함 — 추세 문장·헤드라인 후보 문턱.
let MR_THRESHOLD_IMPROVE_SEC = 3.0
/// 역치 기준 기록 창(일) — 최근 24개월(사용자 결정 2026-10-01).
/// 이력: 180일은 강한 러닝이 빠질 때마다 한 달 30초 출렁, 365일 훈련 노력은 대회 아닌 러닝이 섞여 흩어졌다.
/// 대회는 1년에 몇 번뿐이라 24개월로 넓힌다. ⚠ 기간 자체는 임의로 정함.
/// ⚠ 대회 예측(`mrPredict`)은 550일 밖 노력을 버린다 → 역치는 mrPredict를 거치지 않고 기준 기록에서 바로 환산한다.
let MR_THRESHOLD_WINDOW_DAYS = 730

/// 한 시점(asOf) 기준 역치 추정.
struct MRThresholdEstimate: Equatable, Sendable {
    let asOf: Date
    let paceSecPerKm: Double
    let paceConfidence: MRConfidence     // 대회 기준 = 보통, 훈련 노력 기준 = 낮음
    let hr: Double?
    let hrConfidence: MRConfidence       // hr nil이면 .none
    let basis: [String]                  // 화면 근거줄 (예측 근거 · 회귀 n · 노력 n)
    /// 큰 숫자의 기준 기록(앵커) — 카드가 그 점을 굵게, 추세 문장이 갱신 시점을 말할 때 쓴다
    var anchor: MRRaceEffort? = nil
    /// 기준 기록이 확정 대회면 그 이름
    var anchorName: String? = nil
}

/// 확정 대회 한 건 — 이름을 달고 다니는 노력(`MRRaceEffort.isConfirmedRace == true`).
struct MRThresholdRace: Equatable, Sendable {
    let effort: MRRaceEffort
    let name: String
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

/// 앵커 규칙 — 거리 차이를 지우고 가장 빠른 기록(`mrPredict`와 같은 환산시간 / 거리^1.06 최소).
private func mrThresholdBest(_ es: [MRRaceEffort]) -> MRRaceEffort? {
    es.min { $0.timeMinRef / pow($0.distanceM, 1.06) < $1.timeMinRef / pow($1.distanceM, 1.06) }
}

/// 점·앵커에 쓰는 대회 거리 — 풀은 60분 환산이 지구력(후반 저하)을 섞어 느리게 나와 뺀다.
private let mrThresholdRaceLabels: Set<String> = ["5K", "10K", "하프"]

/// 한 노력의 60분 대회 페이스 — 개인 지수(하프 쪽)로 하프 등가로 옮긴 뒤 `mrThresholdPace`.
/// `mrPredict`의 하프 계산과 같은 식이라, 같은 앵커면 예측 화면의 하프와 맞는다.
func mrThresholdPace(effort e: MRRaceEffort, fit: MRExponentFit) -> Double? {
    let bHalf = fit.bFor(distanceM: MRDistance.dH, prior: 1.06).b
    return mrThresholdPace(halfEquivMin: e.timeMinRef * pow(MRDistance.dH / e.distanceM, bHalf))
}

/// 한 시점(asOf) 기준 역치 재료 — 그 시점까지 러닝만, 창(24개월) 안 대회·노력.
private struct MRThresholdInputs {
    let past: [MRWorkout]
    let fit: MRExponentFit
    let races: [MRThresholdRace]        // 창 안 확정 대회(5K·10K·하프), 더위 환산 적용
    let efforts: [MRRaceEffort]         // 창 안 대회급 노력(대회 없을 때 폴백)
}

private func mrThresholdInputs(runs: [MRWorkout], races: [MRThresholdRace],
                               restingHRSamples: [(date: Date, value: Double)],
                               dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, asOf: Date) -> MRThresholdInputs {
    let cal = Calendar.current
    func inWindow(_ d: Date) -> Bool {
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: asOf)).day ?? -1
        return n >= 0 && n <= MR_THRESHOLD_WINDOW_DAYS
    }
    let past = runs.filter { $0.start <= asOf }
    // 안정시 심박도 그 시점까지만 — 미래 샘플이 과거 추정에 새지 않게
    let phys = mrPhysiology(runs: past, restingHRSamples: restingHRSamples.filter { $0.date <= asOf },
                            dateOfBirth: dateOfBirth, sex: sex, asOf: asOf)
    // 지수 적합은 전체 노력으로. 노력은 창 안 러닝만으로 다시 고른다 —
    // ⚠ `mrDetectEfforts`는 전 기간 거리대별 최고 하나씩만 남겨, 전체 결과를 창으로 자르면 최근 노력이 거의 없다.
    let fit = mrFitExponent(mrApplyHeat(mrDetectEfforts(runs: past, phys: phys), heat: heat))
    let windowRuns = past.filter { inWindow($0.date) }
    let efforts = mrApplyHeat(mrDetectEfforts(runs: windowRuns, phys: phys), heat: heat)
        .filter { $0.distanceM <= MRDistance.dH * 1.02 }   // 풀·30km 롱런 제외(대회 점과 같은 이유)
    let rs = races
        .filter { $0.effort.date <= asOf && inWindow($0.effort.date) && mrThresholdRaceLabels.contains($0.effort.label) }
        .map { r in MRThresholdRace(effort: mrApplyHeat([r.effort], heat: heat)[0], name: r.name) }
    return MRThresholdInputs(past: past, fit: fit, races: rs, efforts: efforts)
}

/// 한 시점(asOf) 기준 역치 추정. 기준 기록 = 창 안 확정 대회 중 최고, 대회가 없으면 대회급 노력 중 최고.
/// 기준 기록이 없으면 nil.
func mrThresholdAsOf(runs: [MRWorkout], races: [MRThresholdRace] = [],
                     restingHRSamples: [(date: Date, value: Double)],
                     dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, asOf: Date) -> MRThresholdEstimate? {
    let L = AppLanguage.shared
    let cal = Calendar.current
    let inp = mrThresholdInputs(runs: runs, races: races, restingHRSamples: restingHRSamples,
                                dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: asOf)
    let fromRace = !inp.races.isEmpty
    let anchor = fromRace ? mrThresholdBest(inp.races.map(\.effort)) : mrThresholdBest(inp.efforts)
    guard let a = anchor, let pace = mrThresholdPace(effort: a, fit: inp.fit) else { return nil }
    let anchorName = fromRace ? inp.races.first { $0.effort == a }?.name : nil
    #if DEBUG
    print("[역치:앵커] asOf \(asOf.formatted(date: .numeric, time: .omitted)) · 대회 \(inp.races.count)건 · 노력 \(inp.efforts.count)건 · 기준 \(anchorName ?? "훈련") \(a.label) \(mrFormatHMS(a.timeMin)) → \(mrFormatPace(pace))")
    #endif

    let hrp = mrFitHRPaceModel(runs: inp.past, asOf: asOf)
    let reg = hrp.hrAtPace(pace)
    let sus = mrSustainedEffortHR(runs: inp.past, efforts: inp.efforts + inp.races.map(\.effort), asOf: asOf)
    let combined = mrCombineThresholdHR(regression: reg, sustained: sus)

    let ago = cal.dateComponents([.day], from: a.date, to: cal.startOfDay(for: asOf)).day ?? 0
    let dist = a.label == "하프" ? L.s("하프", "Half") : a.label
    let what = anchorName.map { "\($0) \(dist)" } ?? L.s("훈련 중 \(dist)", "training \(dist)")
    var basis = [L.s("기준 기록: \(what) \(mrFormatDisplay(a.timeMin)) (\(ago)일 전)을 60분 대회 페이스로 환산",
                     "Anchor: \(what) \(mrFormatDisplay(a.timeMin)) (\(ago) days ago) as 1-hour race pace")]
    if !fromRace {
        basis.append(L.s("최근 24개월 확정 대회가 없어 대회급 훈련 기록으로 냈어요",
                         "No confirmed race in 24 months — estimated from race-level training runs"))
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

    return MRThresholdEstimate(asOf: asOf, paceSecPerKm: pace, paceConfidence: fromRace ? .medium : .low,
                               hr: combined?.hr, hrConfidence: combined?.confidence ?? .none,
                               basis: basis, anchor: a, anchorName: anchorName)
}

// MARK: - 성장 탭 카드: 현재 추정 + 대회 점

/// 카드 점 하나 — 대회(또는 대회급 노력) 한 건을 60분 대회 페이스로 환산한 값.
struct MRThresholdEffortPoint: Equatable, Sendable {
    let date: Date
    let label: String          // "10K" / "하프"
    let name: String?          // 확정 대회 이름
    let paceSecPerKm: Double
    let isAnchor: Bool         // 큰 숫자의 기준 기록
}

/// 성장 탭 카드 재료 — 큰 숫자(현재 추정)와 최근 24개월 대회 점.
///
/// ⚠ 추세"선"은 네 번 실패했다(2026-10-01 실기기): 창 안 최고 기록(출렁/평평) · 90일 심박–페이스 회귀(심박 141~160
///   좁은 띠라 기울기 붕괴) · 역치 심박 ±3bpm 평소 러닝(6'00", 역치가 아닌 다른 지표) · 심박 상위 12% 훈련(대회 아닌 러닝이
///   섞여 5'20"~7'40" 흩어짐). 역치는 전력으로 달린 기록에서만 보인다 → **확정 대회만 점으로**(사용자 결정).
///   대회가 없으면 대회급 노력(거리대별 최고)으로 폴백.
struct MRThresholdTrendResult: Equatable, Sendable {
    let current: MRThresholdEstimate
    let points: [MRThresholdEffortPoint]
    /// 점이 확정 대회인가(아니면 대회급 훈련 폴백) — 카드 설명 줄이 달라진다
    let pointsAreRaces: Bool
    /// 최근 기준 기록이 역치를 앞당겼을 때만 — 좋아졌을 때만 말한다
    let sentence: String?
}

/// 추세 문장 — 기준 기록이 이 기간 안의 것일 때만 "갱신"을 말한다. ⚠ 60일은 임의로 정함.
let MR_THRESHOLD_SENTENCE_DAYS = 60

func mrThresholdTrend(runs: [MRWorkout], races: [MRThresholdRace],
                      restingHRSamples: [(date: Date, value: Double)],
                      dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, now: Date) -> MRThresholdTrendResult? {
    guard let current = mrThresholdAsOf(runs: runs, races: races, restingHRSamples: restingHRSamples,
                                        dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: now) else { return nil }
    let inp = mrThresholdInputs(runs: runs, races: races, restingHRSamples: restingHRSamples,
                                dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: now)
    let fromRace = !inp.races.isEmpty
    let src: [(MRRaceEffort, String?)] = fromRace ? inp.races.map { ($0.effort, $0.name) } : inp.efforts.map { ($0, nil) }
    let points = src.compactMap { e, name in
        mrThresholdPace(effort: e, fit: inp.fit).map {
            MRThresholdEffortPoint(date: e.date, label: e.label, name: name, paceSecPerKm: $0,
                                   isAnchor: e == current.anchor)
        }
    }
    .sorted { $0.date < $1.date }

    // 문장 — 기준 기록이 최근 60일 안이고, 그 기록 직전 추정보다 3초/km 이상 빨라졌을 때만
    var sentence: String?
    let cal = Calendar.current
    if let a = current.anchor,
       let ago = cal.dateComponents([.day], from: a.date, to: cal.startOfDay(for: now)).day,
       ago <= MR_THRESHOLD_SENTENCE_DAYS {
        let before = mrThresholdAsOf(runs: runs, races: races, restingHRSamples: restingHRSamples,
                                     dateOfBirth: dateOfBirth, sex: sex, heat: heat,
                                     asOf: a.date.addingTimeInterval(-1))
        sentence = mrThresholdUpdateSentence(anchor: a, beforePace: before?.paceSecPerKm,
                                             afterPace: current.paceSecPerKm)
    }
    return MRThresholdTrendResult(current: current, points: points, pointsAreRaces: fromRace, sentence: sentence)
}

/// 갱신 문장 — 직전 추정보다 `MR_THRESHOLD_IMPROVE_SEC` 이상 빨라졌을 때만. 직전 추정이 없으면(첫 기록) 말하지 않는다.
func mrThresholdUpdateSentence(anchor: MRRaceEffort, beforePace: Double?, afterPace: Double) -> String? {
    guard let b = beforePace else { return nil }
    let gain = b - afterPace
    guard gain >= MR_THRESHOLD_IMPROVE_SEC else { return nil }
    let L = AppLanguage.shared
    let df = DateFormatter()
    df.locale = Locale(identifier: L.isEnglish ? "en_US" : "ko_KR")
    df.setLocalizedDateFormatFromTemplate("MMMd")
    let name = anchor.label == "하프" ? L.s("하프", "Half") : anchor.label
    let s = Int(gain.rounded())
    return L.s("\(df.string(from: anchor.date)) \(name) 기록으로 \(s)초 빨라졌어요",
               "\(s)s/km faster after your \(name) on \(df.string(from: anchor.date))")
}
