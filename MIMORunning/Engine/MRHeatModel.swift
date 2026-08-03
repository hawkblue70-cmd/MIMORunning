import Foundation

let MR_REF_TEMP = 15.0      // 표준 조건

struct MRHeatModel {
    var ok = false
    var bHot1 = 0.0
    var bHot2 = 0.0
    var bCold = 0.0
    var trendPerYear = 0.0
    var n = 0
    var residSD = 0.0
    var slopePerC = 0.0         // 25°C vs 15°C 기울기 (%/°C). 타당성 검사 결과 노출용.
    var rejectReason = ""       // ok=false 이유 (디버그·로그용)

    // MARK: ok에 의존하지 않는 내부 계산
    //
    // ⚠ ok를 정하는 과정에서 타당성을 검사할 때 logDelta/pct를 쓰면 안 된다.
    //   logDelta는 ok가 false이면 0을 반환하므로 검사가 항상 통과해 버린다.
    //   rawDelta/rawPct는 ok를 읽지 않는다.

    func rawDelta(_ t: Double) -> Double {
        let hot = max(0, t - MR_REF_TEMP)
        let cold = max(0, MR_REF_TEMP - t)
        return bHot1 * hot + bHot2 * hot * hot + bCold * cold
    }

    func rawPct(_ t: Double) -> Double { (exp(rawDelta(t)) - 1.0) * 100.0 }

    /// log(속도) 변화량
    func logDelta(_ tempC: Double?) -> Double {
        guard ok, let t = tempC else { return 0 }
        return rawDelta(t)
    }

    /// 15°C 대비 몇 % 느려지는가 (음수 = 느려짐)
    func pct(_ tempC: Double?) -> Double {
        (exp(logDelta(tempC)) - 1.0) * 100.0
    }

    /// 실제 기록 → 15°C 환산
    func toRef(timeMin: Double, tempC: Double?) -> Double {
        guard ok, tempC != nil else { return timeMin }
        return timeMin * exp(logDelta(tempC))
    }

    /// 15°C 기준값 → 목표 기온의 기록
    func fromRef(timeRefMin: Double, tempC: Double) -> Double {
        guard ok else { return timeRefMin }
        return timeRefMin / exp(logDelta(tempC))
    }
}

/// 그 날짜에 이 사람이 실제로 겪는 기온.
///
/// ⚠ 고정값(12°C 같은)을 쓰면 안 된다. 8월 대회와 11월 대회에
///   같은 기온을 적용하면 예상이 통째로 틀린다.
///   본인 러닝의 **연중 같은 시기(±10일, 모든 연도)** 기온 중앙값을 쓴다.
///   지역·시간대·야간 여부까지 자동으로 반영된다 —
///   기상청 평년값보다 이 사람에게 정확하다.
func mrSeasonalTemp(runs: [MRWorkout], for raceDate: Date,
                    windowDays: Int = 10) -> Double? {
    let cal = Calendar.current
    guard let targetDOY = cal.ordinality(of: .day, in: .year, for: raceDate)
    else { return nil }

    var vals: [Double] = []
    for r in runs {
        guard let t = r.tempC, !r.indoor,
              let doy = cal.ordinality(of: .day, in: .year, for: r.date)
        else { continue }
        // 연말·연초를 가로지르는 경우를 처리한다
        let raw = abs(doy - targetDOY)
        let diff = min(raw, 365 - raw)
        if diff <= windowDays { vals.append(t) }
    }
    // 표본이 너무 적으면 창을 넓혀 다시 시도
    if vals.count < 8 && windowDays < 25 {
        return mrSeasonalTemp(runs: runs, for: raceDate, windowDays: windowDays + 7)
    }
    guard vals.count >= 5 else { return nil }
    return mrMedian(vals)
}

/// 본인 러닝에서 개인 더위 반응을 추정한다.
///
///   log(speed) ~ 1 + log(distanceKm) + timeTrend(년) + hot + hot² + cold
///
/// ❌ 절대 넣지 말 것: 평균 심박
///
///      더위 ──→ 심박 ──→ (관측)
///        │                 ↑
///        └────→ 속도 ──────┘
///
///   Lafrenz 2008 (MSSE 40(6):1065–1071): 동일 절대 강도에서 35°C는
///   HR +11%, VO2max −15%. 즉 더위→심박이 인과적으로 확립돼 있다.
///   심박은 더위→속도 경로의 매개변수이면서 동시에 충돌변수다.
///   통제하면 추정 대상이 총효과가 아니라 "심박 고정 시 잔여 효과"가 된다.
///
/// ⚠ 그리고 이 계수를 절대적으로 믿지 말 것. 훈련 주행은 자율 페이스라
///   더우면 그냥 늦추면 되고, 레이스처럼 4~5시간 열을 축적하지 않는다.
///   훈련에서 적합한 값은 레이스 페널티의 하한이다.
func mrFitHeatModel(runs: [MRWorkout]) -> MRHeatModel {
    var m = MRHeatModel()

    let rows = runs.filter {
        !$0.indoor && $0.tempC != nil
        && ($0.distanceKm ?? 0) >= 3 && $0.durationMin >= 15
    }
    guard rows.count >= 40 else { return m }

    let t0 = rows.map { $0.date.timeIntervalSince1970 / 86400.0 / 365.25 }.min()!

    var X: [[Double]] = []
    var y: [Double] = []
    for w in rows {
        guard let km = w.distanceKm, let t = w.tempC else { continue }
        let hot = max(0, t - MR_REF_TEMP)
        let cold = max(0, MR_REF_TEMP - t)
        let years = w.date.timeIntervalSince1970 / 86400.0 / 365.25 - t0
        X.append([1.0, log(km), years, hot, hot * hot, cold])
        y.append(log(km * 1000.0 / w.durationMin))
    }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else { return m }

    m.trendPerYear = c[2]
    m.bHot1 = c[3]
    m.bHot2 = c[4]
    m.bCold = c[5]
    m.n = rows.count
    m.residSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: 6)

    // 물리적으로 말이 되는 방향인지 확인 (더울수록 느려야 한다)
    //
    // ⚠ m.pct()를 쓰면 안 된다. pct → logDelta → guard ok → 0 반환으로
    //   ok가 false인 동안 abs(0) < 15 가 항상 참이 된다.
    //   rawPct/rawDelta는 ok 플래그를 읽지 않으므로 여기서만 쓴다.
    //
    // 문헌 상한: 기온 10°C 구간당 0.8–1.2%/°C (Ely 2007, Knechtle 2019)
    let slope = (m.rawPct(25) - m.rawPct(15)) / 10.0   // %/°C (음수 = 더울수록 느림)
    m.slopePerC = slope
    m.ok = (m.bHot1 + 2 * m.bHot2 * 10) < 0
        && slope < 0
        && abs(slope) <= 1.2
        && abs(m.rawPct(30)) < 15
    if !m.ok {
        m.rejectReason = String(format: "기울기 %+.2f%%/°C · 30°C %+.1f%% — 문헌 범위 밖이라 쓰지 않는다",
                                slope, m.rawPct(30))
    }
    #if DEBUG
    print("[더위] \(m.ok ? "채택" : "거부") · 기울기 \(String(format: "%+.3f", m.slopePerC))%/°C · n=\(m.n)")
    #endif
    return m
}
