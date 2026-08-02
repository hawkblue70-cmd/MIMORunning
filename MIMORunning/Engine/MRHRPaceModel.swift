import Foundation

struct MRHRPaceModel {
    var ok = false
    var b0 = 0.0            // 절편 (30분 기준으로 흡수)
    var bSpeed = 0.0        // bpm per (m/min)
    var bTemp = 0.0
    var residSD = 0.0
    var n = 0
    var speedSpan = 0.0     // m/s
    var tier = "T0"

    /// 이 심박으로 달리면 페이스가 얼마인가 (초/km)
    func paceAtHR(_ hr: Double, tempC: Double = 15.0) -> Double? {
        guard ok, bSpeed > 0 else { return nil }
        let adj = hr - b0 - bTemp * max(0, tempC - MR_REF_TEMP)
        let v = adj / bSpeed        // m/min
        guard v > 60 else {
            // ⚠ 여기 걸리면 절편이 목표 심박보다 높다는 뜻 —
            //   회귀가 잘못된 관계를 잡았다는 신호다. 조용히 넘기지 말 것.
            print("[HRPace] paceAtHR(\(hr)) 실패: b0=\(b0) bSpeed=\(bSpeed) v=\(v)")
            return nil
        }
        return 60_000.0 / v
    }
}

/// 워크아웃 단위 심박–속도 회귀.
///
///   HR ~ 1 + speed(m/min) + max(0, temp−15) + durationMin
///
/// duration 항은 심혈관 드리프트를 흡수한다. 절편에 30분치를 미리 더해
/// "30분짜리 러닝 기준"으로 해석하게 만든다.
///
/// ⚠ 여기는 심박이 **종속변수**다. 더위 모델과 반대 방향이므로 문제없다.
func mrFitHRPaceModel(runs: [MRWorkout], asOf: Date) -> MRHRPaceModel {
    var m = MRHRPaceModel()
    let cal = Calendar.current

    var X: [[Double]] = []
    var y: [Double] = []
    var speeds: [Double] = []

    for w in runs {
        let days = cal.dateComponents([.day], from: w.date,
                                      to: cal.startOfDay(for: asOf)).day ?? -1
        guard days >= 0, days <= 365 else { continue }
        guard !w.indoor, let hr = w.hrAvg, let km = w.distanceKm else { continue }
        guard w.durationMin >= 20, km >= 2.0 else { continue }
        let speed = km * 1000.0 / w.durationMin
        guard speed > 100, speed < 400 else { continue }

        X.append([1.0, speed, max(0, (w.tempC ?? MR_REF_TEMP) - MR_REF_TEMP), w.durationMin])
        y.append(hr)
        speeds.append(speed)
    }
    guard X.count >= 8, let c = MRLinAlg.lstsq(X: X, y: y) else { return m }

    m.b0 = c[0] + c[3] * 30.0        // 30분 기준으로 흡수
    m.bSpeed = c[1]
    m.bTemp = c[2]
    m.residSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: min(4, X.count - 1))
    m.n = X.count
    m.speedSpan = (speeds.max()! - speeds.min()!) / 60.0
    m.ok = m.bSpeed > 0.005 && m.speedSpan >= 0.35
    m.tier = !m.ok ? "T1" : ((m.n >= 20 && m.speedSpan >= 0.6) ? "T2" : "T1")
    return m
}

/// 심혈관 드리프트 — 같은 페이스에서 시간이 갈수록 심박이 오르는 정도.
///
/// 세션 **내부** 데이터로만 잴 수 있는 값이라 세그먼트가 필요하다.
/// (이건 세션 내 관계가 맞는 질문인 경우다 — 이지 페이스와 다르다)
///
/// ⚠ 예측식에는 넣지 않는다. Smyth & Muniz-Pumares 2022의 decoupling은
///   마라톤 레이스 전후반 비교이고, 훈련 주행의 드리프트가 같은 것이라는
///   근거가 없다. 화면에 **보여주기만** 한다.
struct MRDriftModel {
    var ok = false
    var bpmPer10Min = 0.0
    var sessions = 0
}

func mrFitDrift(segments: [MRSegment],
                excludeIntervalStarts: Set<Date>) -> MRDriftModel {
    var m = MRDriftModel()
    let rows = segments.filter { !excludeIntervalStarts.contains($0.workoutStart) }
    let sessions = Set(rows.map(\.workoutStart))
    guard rows.count >= 200, sessions.count >= 8 else { return m }

    var X: [[Double]] = [], y: [Double] = []
    for s in rows {
        X.append([1.0, s.speedMPerMin, s.elapsedMin])
        y.append(s.hr)
    }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else { return m }
    m.bpmPer10Min = c[2] * 10.0
    m.sessions = sessions.count
    m.ok = m.bpmPer10Min > 0 && m.bpmPer10Min < 15
    return m
}

/// 세그먼트 단위 심박–속도 회귀 (T3).
///
///   HR ~ 1 + speed + max(0, temp−15) + elapsedMin
///
/// elapsedMin 항이 **심혈관 드리프트**를 흡수한다. 같은 페이스라도
/// 40분째 심박이 10분째보다 높은데, 그걸 통제하지 않으면
/// "느리게 뛸수록 심박이 높다"는 거꾸로 된 관계가 섞인다.
///
/// ⚠ **표본 크기를 그대로 믿으면 안 된다.**
///   한 세션에서 나온 40개 점은 서로 독립이 아니다(같은 날, 같은 몸, 같은 코스).
///   n=8,000으로 신뢰구간을 계산하면 **근거 없이 좁아진다.**
///   → 유효 표본을 **세션 수**로 잡고 잔차 SD를 그만큼 부풀린다.
///     (이게 1·2차 감사에서 반복해서 걸렸던 함정이다 —
///      LT1의 두 사전확률이 같은 HRmax를 공유하던 것과 같은 종류)
func mrFitHRPaceModelT3(segments: [MRSegment],
                        excludeIntervalStarts: Set<Date>) -> MRHRPaceModel {
    var m = MRHRPaceModel()

    // 인터벌 세션은 뺀다. 회복 구간의 (낮은 속도 + 높은 심박) 점이
    // 관계를 통째로 왜곡한다.
    let rows = segments.filter { !excludeIntervalStarts.contains($0.workoutStart) }
    let sessions = Set(rows.map(\.workoutStart))
    guard rows.count >= 200, sessions.count >= 8 else { return m }

    var X: [[Double]] = []
    var y: [Double] = []
    for s in rows {
        X.append([1.0, s.speedMPerMin,
                  max(0, (s.tempC ?? MR_REF_TEMP) - MR_REF_TEMP), s.elapsedMin])
        y.append(s.hr)
    }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else { return m }

    m.b0 = c[0] + c[3] * 30.0            // 30분 시점 기준
    m.bSpeed = c[1]
    m.bTemp = c[2]

    let rawSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: 4)
    // 군집 보정: 유효 표본은 점 개수가 아니라 세션 수다
    let inflate = (Double(rows.count) / Double(sessions.count)).squareRoot()
    m.residSD = rawSD * inflate

    m.n = sessions.count                 // ★ 세션 수를 보고한다
    let sp = rows.map(\.speedMPerMin)
    m.speedSpan = (sp.max()! - sp.min()!) / 60.0
    m.ok = m.bSpeed > 0.005 && m.speedSpan >= 0.35
    m.tier = m.ok ? "T3" : "T1"
    return m
}
