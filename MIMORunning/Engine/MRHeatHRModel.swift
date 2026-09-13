import Foundation

/// 관측 심박 → 15°C 기준 심박.
///
/// 더운 날엔 같은 페이스라도 피부 혈류 때문에 심박이 오른다(Lafrenz 2008: 35°C에서 같은 강도에 심박 +11%).
/// 이 모델은 본인 기록에서 "15°C 초과 1°C당 bpm"을 학습하고, 심박을 과거와 **비교·판정할 때만** 빼 준다.
/// 원본 심박·존 시간은 건드리지 않는다.
///
/// - 기온이 nil이거나 모델을 쓸 수 없으면 항등.
/// - 15°C 아래는 보정하지 않는다(추위 계수는 미신뢰 — `RunFormCardView` 추위 분기와 같은 태도).
/// - 학습이 안 되면 문헌 계수로 폴백하되 `isFallback`으로 표시해 문장 톤을 "참고"로 낮춘다.
struct MRHeatHRModel: Sendable {
    var ok = false
    var isFallback = false
    var bpmPerC = 0.0          // 15°C 초과 1°C당 bpm
    var n = 0
    var tempSpanC = 0.0
    var residSD = 0.0
    var rejectReason = ""      // 학습 거부 이유(디버그·"참고" 근거)

    /// 문헌 폴백 계수. 35°C에서 +11%(≈150bpm 기준 +16bpm) → 20°C 폭 ÷ ≈ 0.8 bpm/°C.
    static let fallbackBpmPerC = 0.8
    static let minBpmPerC = 0.2
    static let maxBpmPerC = 1.5
    static let minRuns = 30
    static let minTempSpanC = 12.0
    /// 보정이 이만큼 이상일 때만 문장에서 "기온 감안"을 말한다
    static let explainThresholdBpm = 3.0

    static func fallback(reason: String = "") -> MRHeatHRModel {
        var m = MRHeatHRModel()
        m.ok = true
        m.isFallback = true
        m.bpmPerC = fallbackBpmPerC
        m.rejectReason = reason
        return m
    }

    // ok에 의존하지 않는 계산 — 타당성 검사용 (MRHeatModel과 같은 이유)
    func rawDelta(_ t: Double) -> Double { bpmPerC * max(0, t - MR_REF_TEMP) }

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

/// HR ~ 1 + speed + durationMin + max(0, temp−15) 에서 기온 계수만 꺼낸다.
/// `mrFitHRPaceModel`과 같은 행 필터를 쓰되 기온이 없는 행은 **제외**한다(15°C로 채우면 계수가 눌린다).
/// 학습 조건: 행 ≥ 30 · 기온 폭 ≥ 12°C · 0.2 ≤ 계수 ≤ 1.5. 아니면 문헌 폴백.
func mrFitHeatHRModel(runs: [MRWorkout], asOf: Date) -> MRHeatHRModel {
    let cal = Calendar.current
    let rows = runs.filter { w in
        guard let hr = w.hrAvg, let km = w.distanceKm, let t = w.tempC, !w.indoor else { return false }
        let days = cal.dateComponents([.day], from: w.start, to: asOf).day ?? -1
        guard days >= 0 && days <= 365 else { return false }
        guard w.durationMin >= 20, km >= 2.0, hr > 0 else { return false }
        let speed = km * 1000 / w.durationMin
        return speed > 100 && speed < 400 && t > -50 && t < 60
    }
    guard rows.count >= MRHeatHRModel.minRuns else {
        return .fallback(reason: "러닝 \(rows.count)회 < \(MRHeatHRModel.minRuns) — 기온 있는 야외 러닝 부족")
    }
    let temps = rows.map { $0.tempC! }
    let span = (temps.max() ?? 0) - (temps.min() ?? 0)
    guard span >= MRHeatHRModel.minTempSpanC else {
        return .fallback(reason: String(format: "기온 폭 %.0f°C < %.0f°C", span, MRHeatHRModel.minTempSpanC))
    }
    // OLS — mrFitHRPaceModel의 X/y 구성과 MRLinAlg 호출을 그대로 따른다.
    let X: [[Double]] = rows.map { w in
        let speed = w.distanceKm! * 1000 / w.durationMin
        return [1.0, speed, w.durationMin, max(0, w.tempC! - MR_REF_TEMP)]
    }
    let y: [Double] = rows.map { $0.hrAvg! }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else {
        return .fallback(reason: "회귀 실패")
    }
    var m = MRHeatHRModel()
    m.n = rows.count
    m.tempSpanC = span
    m.bpmPerC = c[3]
    m.residSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: 4)
    let plausible = m.bpmPerC >= MRHeatHRModel.minBpmPerC && m.bpmPerC <= MRHeatHRModel.maxBpmPerC
    guard plausible else {
        return .fallback(reason: String(format: "계수 %+.2f bpm/°C — 문헌 범위(%.1f~%.1f) 밖", m.bpmPerC,
                                        MRHeatHRModel.minBpmPerC, MRHeatHRModel.maxBpmPerC))
    }
    m.ok = true
    return m
}
