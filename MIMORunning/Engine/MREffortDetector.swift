import Foundation

/// 표준 거리(±2%)에 들어오면 공식 거리로 정규화하고 시간도 비례 보정한다.
///
/// GPS는 하프에서 40~50m씩 어긋난다. 그대로 두면 21.14km / 1:58:06이 되어
/// 공식 기록 21.0975km / 1:57:53과 다른 값으로 계산된다.
func mrNormalizeDistance(distanceM: Double, timeMin: Double)
    -> (distanceM: Double, timeMin: Double, label: String) {

    for (label, std) in [("5K", MRDistance.d5), ("10K", MRDistance.d10),
                         ("하프", MRDistance.dH), ("풀", MRDistance.dF)] {
        if abs(std - distanceM) / std <= 0.02 {
            return (std, timeMin * (std / distanceM), label)
        }
    }
    return (distanceM, timeMin, String(format: "%.1fK", distanceM / 1000.0))
}

/// 훈련 기록 중 '대회급 노력'을 골라낸다.
func mrDetectEfforts(runs: [MRWorkout], phys: MRPhysiology) -> [MRRaceEffort] {

    let candidates = runs.filter {
        !$0.indoor && !$0.isInterval          // ★ 인터벌은 제외 — 평균 페이스가 대회 페이스가 아니다
        && ($0.distanceKm ?? 0) >= 3.0 && $0.durationMin >= 12
    }
    guard candidates.count >= 10 else { return [] }

    // ⚠ 절대 임계(0.88 × HRmax)를 쓰면 HRmax 추정 오차가 그대로 전파된다.
    //   → 본인 심박 분포의 88 백분위수를 쓴다.
    let hrs = candidates.compactMap(\.hrAvg).sorted()
    let hrGate: Double? = hrs.count >= 20
        ? hrs[min(Int(Double(hrs.count) * 0.88), hrs.count - 1)]
        : nil

    var subs: [MRRaceEffort] = []      // 마라톤 미만
    var fulls: [MRRaceEffort] = []     // 마라톤

    for w in candidates {
        guard let km = w.distanceKm else { continue }
        let rawM = km * 1000.0
        let isFull = rawM >= 40_000

        // ★ 수정 1 — 마라톤에는 심박 게이트를 적용하지 않는다.
        //   5시간을 뛰면 10K보다 낮은 심박으로 갈 수밖에 없다(그게 생리다).
        //   전체 러닝의 88퍼센타일은 짧고 빠른 러닝 기준으로 잡히므로
        //   마라톤이 구조적으로 탈락한다. 실제로 데니 님 마라톤은
        //   평균 151.6bpm, 게이트는 153.1bpm이었다.
        //   그리고 레크리에이션 러너가 42km를 실수로 달리지는 않는다.
        if !isFull, let gate = hrGate, let hr = w.hrAvg, hr < gate { continue }

        // ★ 수정 2 — 표준 거리 정규화
        let n = mrNormalizeDistance(distanceM: rawM, timeMin: w.durationMin)

        let e = MRRaceEffort(date: w.date, distanceM: n.distanceM,
                             timeMin: n.timeMin, timeMinRef: n.timeMin,
                             tempC: w.tempC, label: n.label,
                             isConfirmedRace: false)
        if isFull { fulls.append(e) } else { subs.append(e) }
    }

    // ★ 수정 3 — VDOT 이상치 필터를 마라톤에 적용하지 않는다.
    //   마라톤 VDOT가 낮은 것은 노이즈가 아니라 **신호**다.
    //   그게 우리가 재려는 durability 자체다.
    //   데니 님: 하프 37.2 vs 풀 29.2 → 비율 0.78. 이걸 걸러내면
    //   마라톤 지수를 측정할 재료를 스스로 버리는 셈이 된다.
    if let best = subs.map(\.vdot).max() {
        subs = subs.filter { $0.vdot >= best * 0.88 }
    }

    // 거리대별 최고 하나씩 (중복 제거)
    var byBucket: [Int: MRRaceEffort] = [:]
    for e in subs + fulls {
        let bucket = Int((e.distanceM / 1000.0).rounded())
        if let cur = byBucket[bucket], cur.vdot >= e.vdot { continue }
        byBucket[bucket] = e
    }
    return byBucket.values.sorted { $0.date < $1.date }
}

func mrLabelFor(distanceM: Double) -> String {
    for (name, d) in [("5K", MRDistance.d5), ("10K", MRDistance.d10),
                      ("하프", MRDistance.dH), ("풀", MRDistance.dF)] {
        if abs(d - distanceM) / d <= 0.02 { return name }
    }
    return String(format: "%.1fK", distanceM / 1000.0)
}

/// 각 노력에 기온을 붙이고 15°C 환산 기록을 채운다.
func mrApplyHeat(_ efforts: [MRRaceEffort], heat: MRHeatModel) -> [MRRaceEffort] {
    efforts.map { e in
        var x = e
        x.timeMinRef = heat.ok ? heat.toRef(timeMin: e.timeMin, tempC: e.tempC) : e.timeMin
        return x
    }
}
