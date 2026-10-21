import Foundation

// MARK: - 개인 속도→폼 곡선
//
// 지표 ~ 1 + x + x², x = GAP 속도(m/min) − 평균 속도. 최근 6개월 가중치 2배, 최소 25회.
// 설계: docs/superpowers/specs/2026-10-21-stride-speed-curve-design.md
// 검증 하네스(FormCurveValidation, DEBUG)도 이 타입을 그대로 쓴다 — 검증한 것과 출시하는 것이 같아야 한다.
//
// 지금은 보폭에만 쓴다. 실기기 검증(195회)에서 보폭은 walk-forward 오차가 구간 0.010 → 곡선 0.006m로 줄었고,
// 케이던스·수직진폭은 비김, 지면접촉은 구간이 나았다.
//
// ⚠ 외삽 금지 — 관측 속도 범위 밖에서는 `stat(atPace:)`가 nil을 돌려 호출 쪽이 구간 기준으로 폴백한다.

struct FormSpeedCurve: Codable {
    let centerSpeed: Double
    let coef: [Double]
    let residualSD: Double
    let speedMin: Double
    let speedMax: Double
    let n: Int

    static let minPoints = 25
    static let recentWeightDays = 182

    /// 최근 6개월 가중치 2배 최소제곱. 점이 minPoints 미만이거나 특이행렬이면 nil.
    static func fit(_ pts: [(date: Date, speed: Double, value: Double)], asOf: Date) -> FormSpeedCurve? {
        guard pts.count >= minPoints else { return nil }
        let center = pts.map(\.speed).reduce(0, +) / Double(pts.count)
        let recentCut = asOf.addingTimeInterval(-Double(recentWeightDays) * 86400)
        var X: [[Double]] = [], y: [Double] = []
        for p in pts {
            let w = (p.date >= recentCut ? 2.0 : 1.0).squareRoot()
            let x = p.speed - center
            X.append([w, w * x, w * x * x])
            y.append(w * p.value)
        }
        guard let c = MRLinAlg.lstsq(X: X, y: y) else { return nil }
        let res = pts.map { p -> Double in
            let x = p.speed - center
            return p.value - (c[0] + c[1] * x + c[2] * x * x)
        }
        let sd = (res.map { $0 * $0 }.reduce(0, +) / Double(max(res.count - 3, 1))).squareRoot()
        let speeds = pts.map(\.speed)
        return FormSpeedCurve(centerSpeed: center, coef: c, residualSD: sd,
                              speedMin: speeds.min()!, speedMax: speeds.max()!, n: pts.count)
    }

    /// 관측 속도 범위 밖은 끝값으로 고정 (검증 하네스용). 출시 판정은 `stat(atPace:)`로 범위 밖을 아예 쓰지 않는다.
    func predict(speed: Double) -> Double {
        let s = min(max(speed, speedMin), speedMax)
        let x = s - centerSpeed
        return coef[0] + coef[1] * x + coef[2] * x * x
    }

    func covers(speed: Double) -> Bool { speed >= speedMin && speed <= speedMax }

    /// 그 페이스(초/km, GAP 우선)에서의 평소 범위. FormStat.lower/upper = 기대값 ± 1.2 × 잔차 SD (구간과 같은 1.2).
    /// p10/p90은 nil — 표본 부족 띠(P10~P90) 분기를 타지 않는다. 관측 속도 범위 밖이면 nil.
    func stat(atPace paceSecPerKm: Double) -> FormStat? {
        guard paceSecPerKm > 0 else { return nil }
        let speed = 60000.0 / paceSecPerKm
        guard covers(speed: speed) else { return nil }
        return FormStat(median: predict(speed: speed), sd: residualSD, count: n, p10: nil, p90: nil)
    }
}

// MARK: - 보폭 평소 범위 (소비처 공용)

extension RunningFormBaseline {
    /// 보폭 평소 범위 — 소비처(폼 카드 바·km 띠·문장·인사이트 탭·단계 표)는 모두 이것만 읽는다.
    /// 구간이 판정 가능하고 곡선이 그 페이스를 덮을 때만 곡선 기대값, 아니면 구간 값 그대로.
    /// 판정 가능 여부·참고 밴드·인터벌 생략 게이트는 바꾸지 않는다.
    func strideStat(_ bb: BandBaseline?, paceSecPerKm: Double?) -> FormStat? {
        curveStrideStat(bb, paceSecPerKm: paceSecPerKm) ?? bb?.strideLength
    }

    /// true = 보폭 범위가 곡선 기준 (범례 한 줄 표시용).
    func usesStrideCurve(_ bb: BandBaseline?, paceSecPerKm: Double?) -> Bool {
        curveStrideStat(bb, paceSecPerKm: paceSecPerKm) != nil
    }

    private func curveStrideStat(_ bb: BandBaseline?, paceSecPerKm: Double?) -> FormStat? {
        guard let bb, bb.isJudgeable, bb.strideLength != nil,
              let pace = paceSecPerKm, let curve = strideCurve else { return nil }
        return curve.stat(atPace: pace)
    }
}
