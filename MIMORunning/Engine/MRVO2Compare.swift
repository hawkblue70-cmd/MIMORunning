import Foundation

// MARK: - VO2max 방식 예측 (검증용 비교)
//
// 가민·블로그의 "VO2max → 5K/10K/하프/풀" 표는 VO2max를 Daniels VDOT로 그대로 놓고
// 거리별 시간을 푼 것이다. 하프→풀은 사실상 Riegel 1.06이라 풀에서 앱(1.13~)보다 빠르다.
// 과거 대회에서 앱 예측(MRBacktest)과 오차를 나란히 보려는 용도 — 화면에는 쓰지 않는다(2026-10-02).

/// VO2max(=VDOT로 간주)로 거리를 뛰는 시간(분). vdot(d, t)는 t에 대해 감소하므로 이분법으로 푼다.
func mrTimeForVDOT(_ v: Double, distanceM: Double) -> Double? {
    guard v > 10, distanceM > 0 else { return nil }
    var lo = 1.0, hi = 1500.0
    guard vdot(distanceM: distanceM, timeMin: lo) > v,
          vdot(distanceM: distanceM, timeMin: hi) < v else { return nil }
    for _ in 0..<80 {
        let mid = (lo + hi) / 2
        if vdot(distanceM: distanceM, timeMin: mid) > v { lo = mid } else { hi = mid }
    }
    return (lo + hi) / 2
}

/// 대회 전날까지의 마지막 VO2max.
/// ⚠ 대회 당일 표본은 빼야 한다. 워치는 야외 러닝 뒤에 VO2max를 갱신하므로 그 대회 기록이 새어 들어온다.
/// maxAgeDays보다 오래된 값은 쓰지 않는다 — 그 사이 체력이 바뀌었을 수 있다.
func mrVO2Before(_ samples: [(date: Date, value: Double)], raceDate: Date,
                 maxAgeDays: Int = 60, calendar: Calendar = .current) -> (value: Double, ageDays: Int)? {
    let raceDay = calendar.startOfDay(for: raceDate)
    guard let last = samples.filter({ $0.date < raceDay }).max(by: { $0.date < $1.date }) else { return nil }
    let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.date), to: raceDay).day ?? Int.max
    return age <= maxAgeDays ? (last.value, age) : nil
}

struct MRVO2CompareRow {
    let date: Date
    let label: String
    let actualMin: Double
    let appMin: Double?        // 앱 예측 (그날 기온 반영)
    let vo2: Double?           // 대회 전 워치 VO2max
    let vo2AgeDays: Int?
    let vo2Min: Double?        // VO2max 방식 예측 (기온 무관 — 가민·블로그 표와 같은 조건)
    let raceVDOT: Double       // 실제 기록이 말하는 VDOT — 워치 VO2max와의 차이가 이코노미·측정 오차

    var appErrPct: Double? { appMin.map { ($0 - actualMin) / actualMin * 100 } }
    var vo2ErrPct: Double? { vo2Min.map { ($0 - actualMin) / actualMin * 100 } }
}

func mrVO2Compare(backtest: [MRBacktestRow],
                  vo2Samples: [(date: Date, value: Double)],
                  calendar: Calendar = .current) -> [MRVO2CompareRow] {
    backtest.compactMap { r in
        let dm = mrDistanceForLabel(r.label)
        guard dm > 0, r.actualMin > 0 else { return nil }
        let v = mrVO2Before(vo2Samples, raceDate: r.date, calendar: calendar)
        return MRVO2CompareRow(date: r.date, label: r.label, actualMin: r.actualMin,
                               appMin: r.predictedMin, vo2: v?.value, vo2AgeDays: v?.ageDays,
                               vo2Min: v.flatMap { mrTimeForVDOT($0.value, distanceM: dm) },
                               raceVDOT: vdot(distanceM: dm, timeMin: r.actualMin))
    }
}

struct MRVO2CompareSummary {
    let label: String
    let n: Int
    let appMAE: Double, appBias: Double     // % — 음수 = 실제보다 빠르게 예측
    let vo2MAE: Double, vo2Bias: Double
}

/// 거리별 요약. 두 예측이 모두 있는 행만 쓴다 — 같은 표본이어야 공정하다.
func mrVO2CompareSummary(_ rows: [MRVO2CompareRow]) -> [MRVO2CompareSummary] {
    ["5K", "10K", "하프", "풀"].compactMap { label in
        let pairs = rows.filter { $0.label == label }
            .compactMap { r -> (Double, Double)? in
                guard let a = r.appErrPct, let v = r.vo2ErrPct else { return nil }
                return (a, v)
            }
        guard !pairs.isEmpty else { return nil }
        let n = Double(pairs.count)
        return MRVO2CompareSummary(label: label, n: pairs.count,
                                   appMAE: pairs.map { abs($0.0) }.reduce(0, +) / n,
                                   appBias: pairs.map(\.0).reduce(0, +) / n,
                                   vo2MAE: pairs.map { abs($0.1) }.reduce(0, +) / n,
                                   vo2Bias: pairs.map(\.1).reduce(0, +) / n)
    }
}
