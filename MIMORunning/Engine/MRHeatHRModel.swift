import Foundation

/// 관측 심박 → 15°C 기준 심박.
///
/// 더운 날엔 같은 페이스라도 피부 혈류 때문에 심박이 오른다(Lafrenz 2008: 35°C에서 같은 강도에 심박 +11%).
/// 이 모델은 본인 기록에서 "15°C 초과 1°C당 bpm"을 학습하고, 심박을 과거와 **비교·판정할 때만** 빼 준다.
/// 원본 심박·존 시간은 건드리지 않는다.
///
/// - 기온이 nil이거나 모델을 쓸 수 없으면 항등.
/// - 15°C 아래는 보정하지 않는다(추위 계수는 미신뢰 — `RunFormCardView` 추위 분기와 같은 태도).
/// - 학습 최고 기온 밖은 외삽하지 않는다(그 기온에서의 값으로 고정).
/// - 학습이 안 되면 문헌 계수로 폴백하되 `isFallback`으로 표시해 문장 톤을 "참고"로 낮춘다.
struct MRHeatHRModel: Sendable {
    var ok = false
    var isFallback = false
    var bpmPerC = 0.0          // 15°C 초과 1°C당 bpm
    var n = 0
    var tempSpanC = 0.0        // 진단용 — 학습 표본의 기온 폭
    var tempMaxC = 0.0         // 학습 표본의 최고 기온 (외삽 방지 상한)
    var residSD = 0.0
    var rejectReason = ""      // 학습 거부 이유(디버그·"참고" 근거)

    /// 문헌 근사(더위 실험에서 같은 강도 심박 +10~16bpm, 약 1 bpm/°C 휴리스틱).
    static let fallbackBpmPerC = 0.8
    static let maxBpmPerC = 1.5
    static let minRuns = 30
    /// 더위 계수를 배우려면 더운 날(hotRowTempC 이상) 표본이 이만큼은 있어야 한다.
    static let minHotRuns = 8
    /// 학습 표본의 최고 기온이 이 이상이어야 더위 반응을 관측했다고 본다.
    static let minMaxTempC = 25.0
    /// "더운 날"의 기준 기온.
    static let hotRowTempC = 20.0
    /// 보정이 이만큼 이상일 때만 문장에서 "기온 감안"을 말한다
    static let explainThresholdBpm = 3.0

    static func fallback(reason: String = "", n: Int = 0, tempSpanC: Double = 0,
                         tempMaxC: Double = 0, residSD: Double = 0) -> MRHeatHRModel {
        var m = MRHeatHRModel()
        m.ok = true
        m.isFallback = true
        m.bpmPerC = fallbackBpmPerC
        m.rejectReason = reason
        m.n = n
        m.tempSpanC = tempSpanC
        m.tempMaxC = tempMaxC
        m.residSD = residSD
        return m
    }

    // ok에 의존하지 않는 계산 — 타당성 검사용 (MRHeatModel과 같은 이유)
    //
    // ⚠ 학습 최고 기온(tempMaxC) 밖으로 외삽하지 않는다 — 그 기온에서 관측을 멈췄으니
    //   그 이상은 그 기온에서의 값으로 고정한다. 폴백은 문헌 곡선이라 40°C까지 허용한다.
    func rawDelta(_ t: Double) -> Double {
        let effectiveMaxC = isFallback ? 40.0 : tempMaxC
        return bpmPerC * max(0, min(t, effectiveMaxC) - MR_REF_TEMP)
    }

    /// 이 기온에서 예상되는 심박 상승분(bpm). 기온 없음·모델 불가 → 0.
    func delta(_ tempC: Double?) -> Double {
        guard ok, let t = tempC else { return 0 }
        return rawDelta(t)
    }

    /// 관측 심박 → 15°C 기준
    func toRef(_ hr: Double, tempC: Double?) -> Double { hr - delta(tempC) }

    /// 보정이 표시할 만큼 큰가
    func explains(tempC: Double?) -> Bool { delta(tempC) >= Self.explainThresholdBpm }

    /// 러닝 한 건의 15°C 기준 평균 심박. 심박이 없으면 nil.
    func refHR(of a: Activity) -> Double? {
        guard let hr = a.avgHeartRate else { return nil }
        return toRef(Double(hr), tempC: a.temperatureC)
    }
}

/// HR ~ 1 + speed + durationMin + max(0, temp−15) + years 에서 기온 계수만 꺼낸다.
/// `mrFitHRPaceModel`과 같은 행 필터를 쓰되 기온이 없는 행은 **제외**한다(15°C로 채우면 계수가 눌린다).
///
/// 학습 조건: 행 ≥ 30 · 더운 날(20°C↑) 러닝 ≥ 8회 · 학습 표본 최고 기온 ≥ 25°C · 계수 0~1.5.
/// 아니면 문헌 폴백.
///
/// ⚠ 기온 폭이 넓어도 전부 선선한 날 + 극단적으로 추운 날 몇 개면 "더위 반응"을 배운 게 아니다.
///   그래서 폭 대신 **더운 쪽 레버리지**(20°C 이상 표본 수 · 최고 기온)를 직접 본다.
func mrFitHeatHRModel(runs: [MRWorkout], asOf: Date) -> MRHeatHRModel {
    let cal = Calendar.current

    func log(_ m: MRHeatHRModel) -> MRHeatHRModel {
        #if DEBUG
        print(String(format: "[더위심박] %@ · n=%d · 폭 %.0f°C · 최고 %.0f°C · %.2f bpm/°C %@",
                     (m.ok && !m.isFallback) ? "학습" : "폴백", m.n, m.tempSpanC, m.tempMaxC, m.bpmPerC, m.rejectReason))
        #endif
        return m
    }

    // 행 필터 — mrFitHRPaceModel(MRHRPaceModel.swift:192-199)과 같은 날짜·실내·기간·거리·속도 조건.
    // 다른 점: 기온이 없는 행은 여기서 제외한다(15°C로 채우면 계수가 눌린다).
    let rows = runs.filter { w in
        let days = cal.dateComponents([.day], from: w.date,
                                      to: cal.startOfDay(for: asOf)).day ?? -1
        guard days >= 0, days <= 365 else { return false }
        guard !w.indoor, let hr = w.hrAvg, let km = w.distanceKm, let t = w.tempC else { return false }
        guard w.durationMin >= 20, km >= 2.0, hr > 0 else { return false }
        let speed = km * 1000 / w.durationMin
        return speed > 100 && speed < 400 && t > -50 && t < 60
    }
    guard rows.count >= MRHeatHRModel.minRuns else {
        return log(.fallback(reason: "러닝 \(rows.count)회 < \(MRHeatHRModel.minRuns) — 기온 있는 야외 러닝 부족",
                             n: rows.count))
    }

    let temps = rows.map { $0.tempC! }
    let span = (temps.max() ?? 0) - (temps.min() ?? 0)
    let maxTemp = temps.max() ?? 0
    let hotRows = rows.filter { $0.tempC! >= MRHeatHRModel.hotRowTempC }
    guard maxTemp >= MRHeatHRModel.minMaxTempC && hotRows.count >= MRHeatHRModel.minHotRuns else {
        return log(.fallback(reason: String(format: "더운 날(%.0f°C↑) 러닝 %d회 · 최고 %.0f°C — 더위 계수를 배울 표본 부족",
                                            MRHeatHRModel.hotRowTempC, hotRows.count, maxTemp),
                             n: rows.count, tempSpanC: span, tempMaxC: maxTemp))
    }

    // 시간 추세 — MRHeatModel(mrFitHeatModel)의 years 열과 같은 방식.
    // 없으면 "요즘 더위 적응이 좋아짐/나빠짐"이 기온 계수에 섞여 들어간다.
    let t0 = rows.map { $0.start.timeIntervalSince1970 / 86400.0 / 365.25 }.min() ?? 0
    let X: [[Double]] = rows.map { w in
        let speed = w.distanceKm! * 1000 / w.durationMin
        let years = w.start.timeIntervalSince1970 / 86400.0 / 365.25 - t0
        return [1.0, speed, w.durationMin, max(0, w.tempC! - MR_REF_TEMP), years]
    }
    let y: [Double] = rows.map { $0.hrAvg! }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else {
        return log(.fallback(reason: "회귀 실패", n: rows.count, tempSpanC: span, tempMaxC: maxTemp))
    }

    var m = MRHeatHRModel()
    m.n = rows.count
    m.tempSpanC = span
    m.tempMaxC = maxTemp
    m.bpmPerC = c[3]
    m.residSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: 5)

    // 비대칭 타당성 밴드 — 정밀하게 배운 작은 계수(더위 적응)는 그대로 쓴다.
    // 음수(더울수록 심박이 낮아짐)나 문헌 상한을 넘는 값만 회귀가 잘못됐다고 본다.
    if m.bpmPerC < 0 {
        return log(.fallback(reason: "계수 음수 — 회귀가 더위를 못 잡음",
                             n: m.n, tempSpanC: m.tempSpanC, tempMaxC: m.tempMaxC, residSD: m.residSD))
    }
    guard m.bpmPerC <= MRHeatHRModel.maxBpmPerC else {
        return log(.fallback(reason: String(format: "계수 %+.2f bpm/°C > 상한 %.1f",
                                            m.bpmPerC, MRHeatHRModel.maxBpmPerC),
                             n: m.n, tempSpanC: m.tempSpanC, tempMaxC: m.tempMaxC, residSD: m.residSD))
    }
    m.ok = true
    return log(m)
}
