import Foundation

/// 신발별 폼 변화·수명(2026-10-08 사용자 결정).
///
/// 질문은 둘이다 — (1) 이 신발은 내 폼을 어떻게 바꾸나, (2) 이 신발은 거리가 쌓이며 변하나(수명).
/// 러닝 종류·거리 묶음으로 잘게 나누면 칸마다 1~2회라 우연이 신발 차이보다 크다. 그래서 묶지 않고 **보정한다**:
/// 최근 1년 모든 러닝(신발 기록 없는 러닝 포함)으로 "이 속도·이 거리면 내 값은 보통 얼마"를 직선 회귀로 만들고,
/// 러닝마다 기준과의 차이(잔차) 하나만 본다. 페이스·거리 영향이 빠지므로 신발별 러닝을 한데 모을 수 있다.
/// 신발이 닳을 때 폼 지표가 어느 쪽으로 움직이는지 정한 연구는 거의 없다 — "새 신발 때보다 이만큼 달라졌다"까지만 말한다.
enum ShoeFormComparison {

    enum Metric: CaseIterable {
        case contact, efficiency, oscillation

        /// 좋은 쪽 — 지면접촉·수직진폭은 낮게, 심박 효율은 높게
        var higherIsBetter: Bool { self == .efficiency }

        /// 말할 만한 차이 — 하루 사이 자연 변동보다 큰 값으로 정함(통제 연구 없음)
        var noticeable: Double {
            switch self {
            case .contact:     return 8      // ms
            case .efficiency:  return 3      // %
            case .oscillation: return 0.3    // cm
            }
        }

        func raw(_ s: Sample) -> Double? {
            switch self {
            case .contact:     return s.contact
            case .oscillation: return s.oscillation
            case .efficiency:  return s.efficiency
            }
        }
    }

    struct Sample {
        let date: Date
        let distanceM: Double
        let paceSecPerKm: Double
        let avgHeartRate: Int?
        let contact: Double?
        let oscillation: Double?
        /// nil = 신발 기록 없음(기준 만들기에만 쓰인다)
        let shoeID: String?

        var speed: Double { paceSecPerKm > 0 ? 1000 / paceSecPerKm : 0 }   // m/s
        var km: Double { distanceM / 1000 }
        /// 심박 효율 — 심박 1회에 가는 거리(m). 속도(m/분) ÷ 평균 심박
        var efficiency: Double? {
            guard let hr = avgHeartRate, hr > 0, paceSecPerKm > 0 else { return nil }
            return (60_000 / paceSecPerKm) / Double(hr)
        }
    }

    static func samples(inputs: [FormInput], shoeOf: (UUID) -> String?) -> [Sample] {
        inputs.map {
            Sample(date: $0.date, distanceM: $0.distanceM, paceSecPerKm: $0.paceSecPerKm,
                   avgHeartRate: $0.avgHeartRate, contact: $0.avgGroundContactTime,
                   oscillation: $0.avgVerticalOscillation, shoeID: shoeOf($0.activityID))
        }
    }

    // MARK: - 기준(이 속도·거리면 보통 얼마)

    /// 값 = a + b·속도 + c·거리(km)
    struct Model {
        let a: Double, b: Double, c: Double
        let n: Int
        func expected(_ s: Sample) -> Double { a + b * s.speed + c * s.km }
    }

    static let minModelRuns = 20
    static let modelWindowDays = 365

    /// 최근 1년, 값 있는 러닝 20회 이상일 때만. 거리 계수가 풀리지 않으면 속도만, 그것도 안 되면 평균.
    static func fit(_ m: Metric, samples: [Sample], asOf: Date) -> Model? {
        let since = Calendar.current.date(byAdding: .day, value: -modelWindowDays, to: asOf) ?? .distantPast
        let pts: [(x1: Double, x2: Double, y: Double)] = samples.compactMap { s in
            guard s.date >= since, s.date <= asOf, s.speed > 0, let y = m.raw(s) else { return nil }
            return (s.speed, s.km, y)
        }
        guard pts.count >= minModelRuns else { return nil }
        let n = Double(pts.count)
        let my = pts.map(\.y).reduce(0, +) / n
        if let (a, b, c) = solve3(pts) { return Model(a: a, b: b, c: c, n: pts.count) }
        if let (a, b) = solve2(pts.map { ($0.x1, $0.y) }) { return Model(a: a, b: b, c: 0, n: pts.count) }
        return Model(a: my, b: 0, c: 0, n: pts.count)
    }

    private static func solve2(_ p: [(Double, Double)]) -> (Double, Double)? {
        let n = Double(p.count)
        let mx = p.map(\.0).reduce(0, +) / n, my = p.map(\.1).reduce(0, +) / n
        let sxx = p.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
        guard sxx > 1e-9 else { return nil }
        let sxy = p.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let b = sxy / sxx
        return (my - b * mx, b)
    }

    /// 정규방정식 3×3 — 가우스 소거. 거리가 다 같아 풀리지 않으면 nil.
    private static func solve3(_ p: [(x1: Double, x2: Double, y: Double)]) -> (Double, Double, Double)? {
        var m = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 3)
        for q in p {
            let x = [1, q.x1, q.x2]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += x[i] * x[j] }
                m[i][3] += x[i] * q.y
            }
        }
        for col in 0..<3 {
            guard let piv = (col..<3).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[piv][col]) > 1e-9 else { return nil }
            m.swapAt(col, piv)
            for r in 0..<3 where r != col {
                let f = m[r][col] / m[col][col]
                for k in col..<4 { m[r][k] -= f * m[col][k] }
            }
        }
        // 상대 크기로 다시 한 번 — 거리 열이 거의 상수면 피벗이 작아 계수가 튄다
        guard abs(m[2][2]) > 1e-6 * max(1, abs(m[0][0])) else { return nil }
        return (m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2])
    }

    /// 기준과의 차이 — 지면접촉 ms·수직진폭 cm, 심박 효율은 % (값 크기가 작아 %가 읽기 쉽다)
    static func residual(_ m: Metric, _ s: Sample, model: Model) -> Double? {
        guard let y = m.raw(s), s.speed > 0 else { return nil }
        let e = model.expected(s)
        if m == .efficiency { return e > 0 ? (y - e) / e * 100 : nil }
        return y - e
    }

    // MARK: - 신발 비교

    struct ShoeStat {
        let shoeID: String
        let n: Int
        let mean: Double
        /// 95% 범위 반폭(1.96·표준오차). 2회 미만이면 nil
        let half: Double?
        /// 범위가 0을 넘나들지 않는다 — 평소와 다르다고 말할 수 있다(5회 이상일 때만)
        var differs: Bool { n >= 5 && half.map { abs(mean) > $0 } == true }
    }

    static let minShoeRuns = 5

    static func shoeStats(_ m: Metric, samples: [Sample], model: Model) -> [ShoeStat] {
        var by: [String: [Double]] = [:]
        for s in samples {
            guard let id = s.shoeID, let r = residual(m, s, model: model) else { continue }
            by[id, default: []].append(r)
        }
        return by.map { id, v in
            let n = Double(v.count), mean = v.reduce(0, +) / n
            let half: Double? = v.count >= 2
                ? 1.96 * (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)).squareRoot() / n.squareRoot()
                : nil
            return ShoeStat(shoeID: id, n: v.count, mean: mean, half: half)
        }.sorted { $0.n > $1.n }
    }

    // MARK: - 수명(누적 km)

    struct WearPoint {
        let km: Double
        let value: Double
        /// 최근 5회 평균(이 러닝 포함). 5회 전까지 nil
        let rolling: Double?
    }

    static let rollingRuns = 5
    static let earlyKm = 100.0

    /// 이 신발 러닝을 누적 km 위에 — 누적은 신발을 고른 모든 러닝 거리(폼 데이터 없는 러닝 포함)
    static func wear(_ m: Metric, shoeID: String, samples: [Sample], model: Model,
                     shoeDistances: [(date: Date, meters: Double)]) -> [WearPoint] {
        let dists = shoeDistances.sorted { $0.date < $1.date }
        func cumKm(_ d: Date) -> Double { dists.filter { $0.date <= d }.reduce(0) { $0 + $1.meters } / 1000 }
        let pts = samples.filter { $0.shoeID == shoeID }.sorted { $0.date < $1.date }
            .compactMap { s in residual(m, s, model: model).map { (km: cumKm(s.date), v: $0) } }
        return pts.indices.map { i in
            let w = i + 1 >= rollingRuns ? pts[(i + 1 - rollingRuns)...i].map(\.v) : []
            return WearPoint(km: pts[i].km, value: pts[i].v,
                             rolling: w.isEmpty ? nil : w.reduce(0, +) / Double(w.count))
        }
    }

    struct WearVerdict {
        /// 새 신발 때(처음 100km, 3회 미만이면 처음 3회) 평균·표준편차
        let earlyMean: Double
        let earlySD: Double
        let earlyRuns: Int
        /// 최근 5회 평균 — 새 신발 구간 뒤 러닝이 5회 이상일 때만
        let recent: Double?
        var change: Double? { recent.map { $0 - earlyMean } }
    }

    static func verdict(_ pts: [WearPoint]) -> WearVerdict? {
        guard pts.count >= 3 else { return nil }
        var early = pts.filter { $0.km <= earlyKm }
        if early.count < 3 { early = Array(pts.prefix(3)) }
        let v = early.map(\.value), n = Double(v.count), mean = v.reduce(0, +) / n
        let sd = n >= 2 ? (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)).squareRoot() : 0
        let after = pts.dropFirst(early.count)
        let recent: Double? = after.count >= rollingRuns ? pts.last?.rolling : nil
        return WearVerdict(earlyMean: mean, earlySD: sd, earlyRuns: early.count, recent: recent)
    }
}
