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
    /// 큰 숫자의 기준 기록(앵커) — 카드가 그 점을 굵게, 추세 문장이 갱신 시점을 말할 때 쓴다
    var anchor: MRRaceEffort? = nil
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
    let anchor = recent.min(by: { $0.timeMinRef / pow($0.distanceM, 1.06) < $1.timeMinRef / pow($1.distanceM, 1.06) })
    if let a = anchor {
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
                               basis: basis, anchor: anchor)
}

// MARK: - 성장 탭 카드: 현재 추정 + 강한 러닝 점

/// 카드 점 하나 — 실제 강한 러닝 한 건을 60분 대회 페이스로 환산한 값.
struct MRThresholdEffortPoint: Equatable, Sendable {
    let date: Date
    let label: String          // "10K" / "하프" / "12.4K"
    let paceSecPerKm: Double
    let isAnchor: Bool         // 큰 숫자의 기준 기록
}

/// 성장 탭 카드 재료 — 큰 숫자(현재 추정)와 최근 12개월 강한 러닝 점.
///
/// ⚠ 추세"선"은 세 번 실패했다(2026-10-01 실기기):
///   ① 창 안 최고 기록 — 180일이면 한 달 30초 출렁, 365일이면 평평(최댓값은 드물게 바뀐다)
///   ② 90일 심박–페이스 회귀 — 평균 심박이 141~160 좁은 띠에 몰려 기울기 붕괴
///   ③ 역치 심박 ±3bpm 평소 러닝 중앙값 — 6'00" 근처, 큰 숫자보다 40~60초 느림.
///      평소 러닝은 길고(심박 드리프트) 워밍업·오르막이 섞여 역치가 아니라 다른 지표다.
///   역치 페이스는 강한 러닝(대회·템포)에서만 직접 보인다 → 그 러닝들을 **점**으로 찍는다(선 없음, 사용자 선택 A).
struct MRThresholdTrendResult: Equatable, Sendable {
    let current: MRThresholdEstimate
    let points: [MRThresholdEffortPoint]
    /// 최근 기준 기록이 역치를 앞당겼을 때만 — 좋아졌을 때만 말한다
    let sentence: String?
}

/// 점으로 찍을 강한 러닝의 거리 상한(km). 풀·울트라는 60분 환산이 지구력(후반 저하)을 섞어 느리게 나온다.
/// ⚠ 25km는 임의로 정함 — 하프(21.1)는 넣고 30km 롱런·풀은 뺀다.
let MR_THRESHOLD_POINT_MAX_KM = 25.0
/// 추세 문장 — 기준 기록이 이 기간 안의 것일 때만 "갱신"을 말한다. ⚠ 60일은 임의로 정함.
let MR_THRESHOLD_SENTENCE_DAYS = 60

/// 한 노력의 60분 대회 페이스 — `mrPredict`의 하프 계산과 같은 식(같은 개인 지수)이라 앵커 점 = 큰 숫자.
func mrThresholdPace(effort e: MRRaceEffort, fit: MRExponentFit) -> Double? {
    let bHalf = fit.bFor(distanceM: MRDistance.dH, prior: 1.06).b
    return mrThresholdPace(halfEquivMin: e.timeMinRef * pow(MRDistance.dH / e.distanceM, bHalf))
}

/// 최근 12개월(`MR_THRESHOLD_WINDOW_DAYS`) 강한 러닝 — 본인 심박 상위 12%(대회급 노력 감지와 같은 게이트) 러닝 전부.
/// 대회급 노력 감지(`mrDetectEfforts`)는 거리대별 최고 하나씩만 남겨 점이 4개뿐이라, 여기선 중복 제거·VDOT 필터를 하지 않는다.
/// 심박 게이트를 못 만들면(심박 있는 러닝 20회 미만 — 폰 러닝) 대회급 노력만 점으로. 앵커는 항상 포함.
func mrThresholdEffortPoints(windowRuns: [MRWorkout], recentEfforts: [MRRaceEffort], anchor: MRRaceEffort?,
                             fit: MRExponentFit, heat: MRHeatModel) -> [MRThresholdEffortPoint] {
    let cal = Calendar.current
    let cands = windowRuns.filter {
        !$0.indoor && !$0.isInterval && $0.durationMin >= 12
            && ($0.distanceKm ?? 0) >= 3 && ($0.distanceKm ?? 0) <= MR_THRESHOLD_POINT_MAX_KM
    }
    let hrs = cands.compactMap(\.hrAvg).sorted()
    var efforts: [MRRaceEffort]
    if hrs.count >= 20 {
        let gate = hrs[min(Int(Double(hrs.count) * 0.88), hrs.count - 1)]
        #if DEBUG
        // 최근 몇 달 점이 비는 이유 확인용 — 그 달 후보 수·최고 평균 심박·게이트 통과 수
        do {
            let df = DateFormatter(); df.dateFormat = "yy.MM"
            let byMonth = Dictionary(grouping: cands) { df.string(from: $0.start) }
            let rows = byMonth.keys.sorted().suffix(6).map { k -> String in
                let ws = byMonth[k] ?? []
                let mx = ws.compactMap(\.hrAvg).max().map { String(format: "%.0f", $0) } ?? "-"
                let pass = ws.filter { ($0.hrAvg ?? 0) >= gate }.count
                return "\(k) \(ws.count)회·최고 \(mx)·통과 \(pass)"
            }
            print(String(format: "[역치:점] 게이트 %.0fbpm(후보 %d회 상위 12%%) · ", gate, hrs.count) + rows.joined(separator: " / "))
        }
        #endif
        efforts = mrApplyHeat(cands.compactMap { w -> MRRaceEffort? in
            guard let hr = w.hrAvg, hr >= gate, let km = w.distanceKm else { return nil }
            let n = mrNormalizeDistance(distanceM: km * 1000, timeMin: w.durationMin)
            return MRRaceEffort(date: w.date, distanceM: n.distanceM, timeMin: n.timeMin, timeMinRef: n.timeMin,
                                tempC: w.tempC, label: n.label, isConfirmedRace: false)
        }, heat: heat)
    } else {
        efforts = recentEfforts.filter { $0.distanceM <= MR_THRESHOLD_POINT_MAX_KM * 1000 }
    }
    func same(_ a: MRRaceEffort, _ b: MRRaceEffort) -> Bool {
        cal.isDate(a.date, inSameDayAs: b.date) && abs(a.distanceM - b.distanceM) / b.distanceM < 0.05
    }
    if let a = anchor, !efforts.contains(where: { same($0, a) }) { efforts.append(a) }
    return efforts.compactMap { e in
        mrThresholdPace(effort: e, fit: fit).map {
            MRThresholdEffortPoint(date: e.date, label: e.label, paceSecPerKm: $0,
                                   isAnchor: anchor.map { same(e, $0) } ?? false)
        }
    }
    .sorted { $0.date < $1.date }
}

func mrThresholdTrend(runs: [MRWorkout], restingHRSamples: [(date: Date, value: Double)],
                      dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, now: Date) -> MRThresholdTrendResult? {
    guard let current = mrThresholdAsOf(runs: runs, restingHRSamples: restingHRSamples,
                                        dateOfBirth: dateOfBirth, sex: sex, heat: heat, asOf: now) else { return nil }
    // 점 재료 — mrThresholdAsOf와 같은 파이프라인(전체 노력으로 지수, 창 안 러닝으로 노력)
    let cal = Calendar.current
    let past = runs.filter { $0.start <= now }
    let phys = mrPhysiology(runs: past, restingHRSamples: restingHRSamples.filter { $0.date <= now },
                            dateOfBirth: dateOfBirth, sex: sex, asOf: now)
    let fit = mrFitExponent(mrApplyHeat(mrDetectEfforts(runs: past, phys: phys), heat: heat))
    let windowRuns = past.filter {
        let d = cal.dateComponents([.day], from: $0.date, to: cal.startOfDay(for: now)).day ?? -1
        return d >= 0 && d <= MR_THRESHOLD_WINDOW_DAYS
    }
    let recent = mrApplyHeat(mrDetectEfforts(runs: windowRuns, phys: phys), heat: heat)
    let points = mrThresholdEffortPoints(windowRuns: windowRuns, recentEfforts: recent, anchor: current.anchor,
                                         fit: fit, heat: heat)

    // 문장 — 기준 기록이 최근 60일 안이고, 그 기록 직전 추정보다 3초/km 이상 빨라졌을 때만
    var sentence: String?
    if let a = current.anchor,
       let ago = cal.dateComponents([.day], from: a.date, to: cal.startOfDay(for: now)).day,
       ago <= MR_THRESHOLD_SENTENCE_DAYS {
        let before = mrThresholdAsOf(runs: runs, restingHRSamples: restingHRSamples, dateOfBirth: dateOfBirth,
                                     sex: sex, heat: heat, asOf: a.date.addingTimeInterval(-1))
        sentence = mrThresholdUpdateSentence(anchor: a, beforePace: before?.paceSecPerKm,
                                             afterPace: current.paceSecPerKm)
    }
    return MRThresholdTrendResult(current: current, points: points, sentence: sentence)
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
