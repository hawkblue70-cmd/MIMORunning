import Foundation

/// 내 폼 변화 · 신발 성격(2026-10-08 사용자 결정).
///
/// 1) 보정 — 최근 1년 모든 러닝(신발 기록 없는 러닝 포함)으로 "이 속도·거리면 내 값은 보통 얼마"를 회귀로 만들고,
///    러닝마다 기준과의 차이(잔차) 하나만 본다. 러닝 종류로 쪼개면 칸마다 1~2회라 우연이 크다.
/// 2) 신발 성격 — 신발 러닝의 잔차에서 **같은 시기(앞뒤 14일) 다른 신발 러닝**의 잔차 평균을 뺀다(계절·체력 제거).
/// 3) 내 폼의 흐름 — 잔차에서 신발 효과를 빼고 4주 이동평균. 보스턴12(+8ms)를 자주 신기 시작한 시점이 폼 변화로 보이지 않게.
///    선이 방향을 바꾼 곳(정점·바닥)을 지그재그 규칙으로 찾는다 — 충분히 움직였다가 돌아설 때만, 4주 간격 이상.
/// 신발 수명(닳음)·심박 효율은 다루지 않는다 — 쿠션 변화는 몸이 보상해 워치 지표에 거의 안 나타나고,
/// 심박 효율은 폼·신발보다 체력·날씨를 보여 준다.
enum ShoeFormComparison {

    enum Metric: CaseIterable {
        case contact, oscillation, stride

        /// 말할 만한 차이 — 하루 사이 자연 변동보다 큰 값으로 정함(통제 연구 없음)
        var noticeable: Double {
            switch self {
            case .contact:     return 8      // ms
            case .oscillation: return 0.3    // cm
            case .stride:      return 0.03   // m
            }
        }

        /// 흐름선이 꺾였다고 볼 움직임 — 말할 만한 차이의 절반
        var turnThreshold: Double {
            switch self {
            case .contact:     return 4
            case .oscillation: return 0.15
            case .stride:      return 0.015
            }
        }

        /// 표시·판정에 같은 반올림 — "+8ms인데 같음"이 나오지 않게
        func rounded(_ v: Double) -> Double {
            switch self {
            case .contact:     return v.rounded()
            case .oscillation: return (v * 10).rounded() / 10
            case .stride:      return (v * 100).rounded() / 100
            }
        }

        func raw(_ s: Sample) -> Double? {
            switch self {
            case .contact:     return s.contact
            case .oscillation: return s.oscillation
            case .stride:      return s.stride
            }
        }
    }

    struct Sample {
        let date: Date
        let distanceM: Double
        let paceSecPerKm: Double
        let contact: Double?
        let oscillation: Double?
        /// 보폭(m) — 같은 페이스로 보정하면 케이던스의 거울(속도 = 케이던스 × 보폭)이라 하나만 쓴다(2026-10-08)
        var stride: Double? = nil
        /// nil = 신발 기록 없음(기준·흐름에만 쓰인다)
        let shoeID: String?

        var speed: Double { paceSecPerKm > 0 ? 1000 / paceSecPerKm : 0 }   // m/s
        var km: Double { distanceM / 1000 }
    }

    static func samples(inputs: [FormInput], shoeOf: (UUID) -> String?) -> [Sample] {
        inputs.map {
            Sample(date: $0.date, distanceM: $0.distanceM, paceSecPerKm: $0.paceSecPerKm,
                   contact: $0.avgGroundContactTime, oscillation: $0.avgVerticalOscillation,
                   stride: $0.avgStrideLength, shoeID: shoeOf($0.activityID))
        }
    }

    // MARK: - 기준(이 속도·거리면 보통 얼마)

    /// 값 = c0 + c1·속도 [+ c2·거리]
    struct Model {
        let coef: [Double]
        let n: Int
        func expected(_ s: Sample) -> Double {
            let f = [1, s.speed, s.km]
            return zip(coef, f).reduce(0) { $0 + $1.0 * $1.1 }
        }
    }

    static let minModelRuns = 20
    static let modelWindowDays = 365

    /// 최근 1년, 값 있는 러닝 20회 이상일 때만. 풀리지 않으면 거리 → 속도 순으로 빼고, 끝내 안 되면 평균.
    static func fit(_ m: Metric, samples: [Sample], asOf: Date) -> Model? {
        let since = Calendar.current.date(byAdding: .day, value: -modelWindowDays, to: asOf) ?? .distantPast
        let pts = samples.filter { $0.date >= since && $0.date <= asOf && $0.speed > 0 && m.raw($0) != nil }
        guard pts.count >= minModelRuns else { return nil }
        let ys = pts.map { m.raw($0)! }
        for k in [3, 2, 1] {
            let rows = pts.map { Array([1, $0.speed, $0.km].prefix(k)) }
            if let c = leastSquares(rows, ys) {
                return Model(coef: Array((c + [0, 0, 0]).prefix(3)), n: pts.count)
            }
        }
        return nil
    }

    /// 정규방정식 — 가우스 소거(부분 피벗). 풀리지 않으면 nil.
    static func leastSquares(_ x: [[Double]], _ y: [Double]) -> [Double]? {
        let k = x.first?.count ?? 0
        guard k > 0, x.count >= k else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: k + 1), count: k)
        for (row, yv) in zip(x, y) {
            for i in 0..<k {
                for j in 0..<k { a[i][j] += row[i] * row[j] }
                a[i][k] += row[i] * yv
            }
        }
        let scale = max(1, a.map { abs($0[0]) }.max() ?? 1)
        for col in 0..<k {
            guard let piv = (col..<k).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }),
                  abs(a[piv][col]) > 1e-9 * scale else { return nil }
            a.swapAt(col, piv)
            for r in 0..<k where r != col {
                let f = a[r][col] / a[col][col]
                for c in col...k { a[r][c] -= f * a[col][c] }
            }
        }
        let sol = (0..<k).map { a[$0][k] / a[$0][$0] }
        return sol.allSatisfy(\.isFinite) ? sol : nil
    }

    static func residual(_ m: Metric, _ s: Sample, model: Model) -> Double? {
        guard let y = m.raw(s), s.speed > 0 else { return nil }
        return y - model.expected(s)
    }

    struct Point {
        let date: Date
        let value: Double
        let shoeID: String?
    }

    static let windowHalfDays = 14

    // MARK: - 신발 성격 — 같은 시기 다른 신발 대비

    struct ShoeStat {
        let shoeID: String
        let n: Int
        let mean: Double
        /// 95% 범위 반폭(1.96·표준오차). 2회 미만이면 nil
        let half: Double?
        /// 5회 이상이고 범위가 0을 넘나들지 않는다
        var differs: Bool { n >= minShoeRuns && half.map { abs(mean) > $0 } == true }
    }

    static let minShoeRuns = 5

    /// 신발 러닝마다 — 그 러닝 잔차 − 앞뒤 14일 안 **다른 신발(또는 신발 기록 없음)** 러닝 잔차 평균(2회 이상일 때만)
    static func shoeStats(_ m: Metric, samples: [Sample], model: Model) -> [ShoeStat] {
        let all = samples.compactMap { s in residual(m, s, model: model).map { Point(date: s.date, value: $0, shoeID: s.shoeID) } }
        let cal = Calendar.current
        var by: [String: [Double]] = [:]
        for p in all {
            guard let id = p.shoeID else { continue }
            let lo = cal.date(byAdding: .day, value: -windowHalfDays, to: p.date)!
            let hi = cal.date(byAdding: .day, value: windowHalfDays, to: p.date)!
            let others = all.filter { $0.shoeID != id && $0.date >= lo && $0.date <= hi }.map(\.value)
            guard others.count >= 2 else { continue }
            by[id, default: []].append(p.value - others.reduce(0, +) / Double(others.count))
        }
        return by.map { id, v in
            let n = Double(v.count), mean = v.reduce(0, +) / n
            let half: Double? = v.count >= 2
                ? 1.96 * (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)).squareRoot() / n.squareRoot()
                : nil
            return ShoeStat(shoeID: id, n: v.count, mean: mean, half: half)
        }.sorted { $0.n > $1.n }
    }

    // MARK: - 내 폼의 흐름 — 신발 효과를 뺀 잔차

    /// 신발 효과를 뺀 점 — 5회 이상 비교된 신발만 뺀다(그보다 적으면 효과 추정이 우연에 좌우된다)
    static func formPoints(_ m: Metric, samples: [Sample], model: Model, from: Date) -> [Point] {
        let effect = Dictionary(shoeStats(m, samples: samples, model: model)
            .filter { $0.n >= minShoeRuns }.map { ($0.shoeID, $0.mean) }, uniquingKeysWith: { a, _ in a })
        return samples.filter { $0.date >= from }.compactMap { s in
            residual(m, s, model: model).map {
                Point(date: s.date, value: $0 - (s.shoeID.flatMap { effect[$0] } ?? 0), shoeID: s.shoeID)
            }
        }.sorted { $0.date < $1.date }
    }

    /// 4주 이동평균(앞뒤 14일, 3회 이상) — 7일 간격. `to`보다 14일 안쪽 끝은 앞쪽 데이터가 없어 흔들린다(진행 중).
    static func trend(_ pts: [Point], from: Date, to: Date) -> [(date: Date, value: Double)] {
        let cal = Calendar.current
        var out: [(Date, Double)] = []
        var d = from
        while d <= to {
            let lo = cal.date(byAdding: .day, value: -windowHalfDays, to: d)!
            let hi = cal.date(byAdding: .day, value: windowHalfDays, to: d)!
            let w = pts.filter { $0.date >= lo && $0.date <= hi }.map(\.value)
            if w.count >= 3 { out.append((d, w.reduce(0, +) / Double(w.count))) }
            d = cal.date(byAdding: .day, value: 7, to: d)!
        }
        return out
    }

    struct Turn {
        let date: Date
        let value: Double
        /// true = 정점(위로 갔다 내려옴), false = 바닥
        let isPeak: Bool
    }

    static let minTurnGapDays = 28

    /// 흐름선이 방향을 바꾼 곳 — 지그재그: 직전 꺾임 이후 `threshold` 이상 움직인 극값에서
    /// 반대로 다시 `threshold` 이상 돌아서면 그 극값을 꺾임으로 확정. 직전 꺾임과 4주 미만이면 버린다.
    static func turns(_ line: [(date: Date, value: Double)], threshold: Double) -> [Turn] {
        guard let first = line.first else { return [] }
        var out: [Turn] = []
        var anchor = first.value                // 직전 꺾임(또는 시작) 값
        var ext = first                          // 지금 방향의 극값
        var dir = 0                              // +1 오르는 중, −1 내리는 중, 0 미정
        for p in line.dropFirst() {
            switch dir {
            case 0:
                if p.value - anchor >= threshold { dir = 1; ext = p }
                else if anchor - p.value >= threshold { dir = -1; ext = p }
            case 1:
                if p.value > ext.value { ext = p }
                else if ext.value - p.value >= threshold {
                    append(Turn(date: ext.date, value: ext.value, isPeak: true), to: &out)
                    anchor = ext.value; dir = -1; ext = p
                }
            default:
                if p.value < ext.value { ext = p }
                else if p.value - ext.value >= threshold {
                    append(Turn(date: ext.date, value: ext.value, isPeak: false), to: &out)
                    anchor = ext.value; dir = 1; ext = p
                }
            }
        }
        return out
    }

    private static func append(_ t: Turn, to out: inout [Turn]) {
        if let last = out.last,
           (Calendar.current.dateComponents([.day], from: last.date, to: t.date).day ?? 0) < minTurnGapDays {
            return
        }
        out.append(t)
    }

    /// 마지막 꺾임(없으면 선 시작) 이후 변화 — 결론 한 줄용
    static func lastSegment(_ line: [(date: Date, value: Double)], turns: [Turn]) -> (from: Date, change: Double)? {
        guard let end = line.last, let start = line.first else { return nil }
        let startDate = turns.last?.date ?? start.date
        let startValue = turns.last?.value ?? start.value
        return (startDate, end.value - startValue)
    }
}
