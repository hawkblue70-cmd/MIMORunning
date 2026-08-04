import Foundation

struct MRPhysiology: Sendable {
    var age: Double?
    var restingHR: MRInference?
    var hrMax: MRInference?
    var lt1HR: MRInference?
    var lt1SD: Double = 0

    /// 이지 상한 — LT1보다 0.5σ 아래를 쓴다 (보수적)
    var easyCeilingHR: Double? {
        guard let lt1 = lt1HR else { return nil }
        return lt1.value - 0.5 * lt1SD
    }
}

enum MRSex: Sendable { case male, female, unknown }

func mrPhysiology(runs: [MRWorkout],
                  restingHRSamples: [(date: Date, value: Double)],
                  dateOfBirth: Date?,
                  sex: MRSex,
                  asOf: Date) -> MRPhysiology {

    var p = MRPhysiology()
    let cal = Calendar.current
    func daysAgo(_ d: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: d),
                           to: cal.startOfDay(for: asOf)).day ?? 0
    }

    if let dob = dateOfBirth {
        p.age = Double(cal.dateComponents([.day], from: dob, to: asOf).day ?? 0) / 365.25
    }

    // ── 안정시심박: 최근 28일 중앙값
    //
    // ⚠ Apple의 이 값은 기초심박이 아니라 "주간 정좌 심박"이다.
    //   수면 구간을 제외하고, 하루 중 가장 비활동적인 시간에서 산출한다.
    //   → Karvonen(예비심박) 존 계산에 쓰지 말 것. 우리는 %HRmax로 통일한다.
    let r28 = restingHRSamples
        .filter { daysAgo($0.date) >= 0 && daysAgo($0.date) < 28 }
        .map(\.value)
    if r28.count >= 5 {
        p.restingHR = MRInference(value: mrMedian(r28), confidence: .high,
                                  basis: ["최근 28일 안정시심박 \(r28.count)건 중앙값"])
    } else if !restingHRSamples.isEmpty {
        let last30 = restingHRSamples.suffix(30).map(\.value)
        p.restingHR = MRInference(value: mrMedian(last30), confidence: .medium,
                                  basis: ["전체 안정시심박 중앙값"])
    }

    // ── HRmax
    //
    // 광학 심박은 두 방향으로 오염돼 있다:
    //   ↑ 케이던스 락(160–180spm)으로 위로 튄다.
    //     Apple 문서: 러닝 중 ±5bpm 이내 정확도 88% (좌식 98%)
    //     Bent 2020 (npj Digit Med 3:18): 활동 중 절대오차가 안정 시보다 +30%
    //   ↓ 진짜 최대노력을 안 하는 러너에게 관측 최대치는 하한이다
    // → 단일 순위통계량("2번째 최고치")이 아니라 상위 5개의 중앙값.
    //   그리고 Tanaka+20bpm(≈2SD)을 넘는 값은 생리적으로 배제한다.
    let formula = p.age.map { 208 - 0.7 * $0 }      // Tanaka 2001, JACC 37(1):153–156
    let cap = (formula ?? 190) + 20
    let hrMaxes = runs
        .filter { $0.durationMin >= 10 && daysAgo($0.date) >= 0 && daysAgo($0.date) < 730 }
        .compactMap(\.hrMax)
        .filter { $0 <= cap }
        .sorted()

    if hrMaxes.count >= 10 {
        let top5 = Array(hrMaxes.suffix(5))
        p.hrMax = MRInference(value: mrMedian(top5), confidence: .high,
                              basis: ["최근 2년 러닝 \(hrMaxes.count)건 상위 5개 중앙값 (관측 기반 하한)"])
    } else if let f = formula {
        p.hrMax = MRInference(value: f, confidence: .low,
                              basis: ["Tanaka 공식 208−0.7×\(Int(p.age ?? 0))세 (SEE ≈10bpm → 95% 구간 ±20)"])
    }

    // ── LT1 (유산소 역치)
    //
    // ⚠ 이전 버전의 `0.70×HRmax` 사전확률은 단위 오류였다.
    //   70%는 %HRR(Karvonen) 값이고 %HRmax로 옮기면 약 79%다.
    //   그리고 0.70과 0.80을 정밀도 가중 병합한 것도 부당했다 —
    //   두 값이 같은 HRmax를 공유하므로 오차가 완전 상관인데
    //   역분산 가중은 독립을 가정한다. 신뢰구간이 근거 없이 좁아졌다.
    //
    // 실측: Nuuttila 2025 (Eur J Appl Physiol 125(8):2161–2171,
    //       레크리에이션 러너 n=165)
    //         LT1 남 78.5 ± 5.5 %HRmax / 여 80.0 ± 5.0
    if let hm = p.hrMax {
        let frac = (sex == .female) ? 0.800 : 0.785
        let lt1 = frac * hm.value
        let hrMaxSD: Double = (hm.confidence >= .high) ? 4.0 : 10.0
        let sd = ((frac * hrMaxSD) * (frac * hrMaxSD)
                  + (0.055 * hm.value) * (0.055 * hm.value)).squareRoot()
        p.lt1HR = MRInference(
            value: lt1,
            confidence: (hm.confidence >= .high) ? .medium : .low,
            basis: [String(format: "%.3f×HRmax %.0f = %.0fbpm (Nuuttila 2025, n=165) · 개인차 ±%.0fbpm",
                           frac, hm.value, lt1, sd)])
        p.lt1SD = sd
    }

    // ⚠ Critical Speed 앵커(v_LT1 = 0.823 × CS)는 구현하지 않는다.
    //   그 숫자는 인용한 논문(Smyth & Muniz-Pumares 2020)에 존재하지 않고,
    //   CS는 LT1이 아니라 LT2에 대응한다. 워크아웃 요약으로는 산출도 불가능하다.

    return p
}

func mrMedian(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m-1] + s[m]) / 2
}
