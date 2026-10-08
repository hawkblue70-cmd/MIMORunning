import Foundation

/// 내 폼 변화 · 신발 성격(2026-10-08 사용자 결정).
///
/// 1) 보정 — 최근 1년 모든 러닝(신발 기록 없는 러닝 포함)으로 "이 속도·거리(·기온)면 내 값은 보통 얼마"를 회귀로 만들고,
///    러닝마다 기준과의 차이(잔차) 하나만 본다. 러닝 종류로 쪼개면 칸마다 1~2회라 우연이 크다.
/// 2) 내 폼의 흐름 — 잔차의 날짜별 이동평균. 신발과 상관없이 같은 조건에서 접지가 짧아지는지 등.
/// 3) 신발 성격 — 신발 러닝의 잔차에서 **같은 시기(앞뒤 14일) 다른 신발 러닝**의 잔차 평균을 뺀다.
///    1년 평균을 기준으로 하면 여름에 신은 신발과 가을에 신은 신발이 계절·체력 차이를 떠안는다.
/// 신발 수명(닳음)은 다루지 않는다 — 몸이 쿠션 변화를 보상해 워치의 몸통 지표(접지·진폭)에는 거의 드러나지 않는다.
enum ShoeFormComparison {

    enum Metric: CaseIterable {
        case contact, oscillation, efficiency

        /// 좋은 쪽 — 지면접촉·수직진폭은 낮게, 심박 효율은 높게
        var higherIsBetter: Bool { self == .efficiency }

        /// 말할 만한 차이 — 하루 사이 자연 변동보다 큰 값으로 정함(통제 연구 없음)
        var noticeable: Double {
            switch self {
            case .contact:     return 8      // ms
            case .oscillation: return 0.3    // cm
            case .efficiency:  return 3      // %
            }
        }

        /// 표시·판정에 같은 반올림 — "+8ms인데 같음"이 나오지 않게
        func rounded(_ v: Double) -> Double {
            switch self {
            case .contact:                  return v.rounded()
            case .oscillation, .efficiency: return (v * 10).rounded() / 10
            }
        }

        /// 기온을 보정에 넣는가 — 심박 효율만(더위에 심박이 오른다). 접지·진폭은 기온 영향이 작다.
        var usesTemperature: Bool { self == .efficiency }

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
        let temperatureC: Double?
        /// nil = 신발 기록 없음(기준·흐름에만 쓰인다)
        let shoeID: String?

        var speed: Double { paceSecPerKm > 0 ? 1000 / paceSecPerKm : 0 }   // m/s
        var km: Double { distanceM / 1000 }
        /// 심박 효율 — 심박 1회에 가는 거리(m). 속도(m/분) ÷ 평균 심박
        var efficiency: Double? {
            guard let hr = avgHeartRate, hr > 0, paceSecPerKm > 0 else { return nil }
            return (60_000 / paceSecPerKm) / Double(hr)
        }
    }

    static func samples(inputs: [FormInput], shoeOf: (UUID) -> String?, temperatureOf: (UUID) -> Double?) -> [Sample] {
        inputs.map {
            Sample(date: $0.date, distanceM: $0.distanceM, paceSecPerKm: $0.paceSecPerKm,
                   avgHeartRate: $0.avgHeartRate, contact: $0.avgGroundContactTime,
                   oscillation: $0.avgVerticalOscillation, temperatureC: temperatureOf($0.activityID),
                   shoeID: shoeOf($0.activityID))
        }
    }

    // MARK: - 기준(이 속도·거리·기온이면 보통 얼마)

    /// 보정 변수 — 절편은 항상
    enum Feature: CaseIterable { case speed, distance, temperature }

    /// 값 = c0 + Σ cᵢ·변수ᵢ (쓰는 변수만)
    struct Model {
        let features: [Feature]
        let coef: [Double]           // [절편] + features 순서
        let meanTemperature: Double
        let n: Int
        var usesTemperature: Bool { features.contains(.temperature) }
        func coefficient(_ f: Feature) -> Double? { features.firstIndex(of: f).map { coef[$0 + 1] } }
        func value(_ f: Feature, _ s: Sample) -> Double {
            switch f {
            case .speed:       return s.speed
            case .distance:    return s.km
            case .temperature: return s.temperatureC ?? meanTemperature
            }
        }
        func expected(_ s: Sample) -> Double {
            coef[0] + zip(features, coef.dropFirst()).reduce(0) { $0 + $1.1 * value($1.0, s) }
        }
    }

    static let minModelRuns = 20
    static let modelWindowDays = 365

    /// 최근 1년, 값 있는 러닝 20회 이상일 때만. 풀리지 않으면 변수를 하나씩 빼고, 끝내 안 되면 평균.
    static func fit(_ m: Metric, samples: [Sample], asOf: Date) -> Model? {
        let since = Calendar.current.date(byAdding: .day, value: -modelWindowDays, to: asOf) ?? .distantPast
        let pts = samples.filter { $0.date >= since && $0.date <= asOf && $0.speed > 0 && m.raw($0) != nil }
        guard pts.count >= minModelRuns else { return nil }
        let temps = pts.compactMap(\.temperatureC)
        let meanT = temps.isEmpty ? 15 : temps.reduce(0, +) / Double(temps.count)
        let ys = pts.map { m.raw($0)! }
        // 기온은 기록이 충분할 때만(없는 러닝은 평균 기온으로 채운다)
        let tryTemp = m.usesTemperature && temps.count >= minModelRuns
        // 풀리는 조합을 차례로 — 거리가 다 같으면 거리만 빼고 기온은 살린다
        let candidates: [[Feature]] = (tryTemp
            ? [[.speed, .distance, .temperature], [.speed, .temperature]]
            : []) + [[.speed, .distance], [.speed], []]
        for feats in candidates {
            let probe = Model(features: feats, coef: [], meanTemperature: meanT, n: 0)
            let rows = pts.map { s in [1.0] + feats.map { probe.value($0, s) } }
            if let c = leastSquares(rows, ys) {
                return Model(features: feats, coef: c, meanTemperature: meanT, n: pts.count)
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

    /// 기준과의 차이 — 지면접촉 ms·수직진폭 cm, 심박 효율은 %
    static func residual(_ m: Metric, _ s: Sample, model: Model) -> Double? {
        guard let y = m.raw(s), s.speed > 0 else { return nil }
        let e = model.expected(s)
        if m == .efficiency { return e > 0 ? (y - e) / e * 100 : nil }
        return y - e
    }

    // MARK: - 내 폼의 흐름

    struct Point {
        let date: Date
        let value: Double
        let shoeID: String?
    }

    static func points(_ m: Metric, samples: [Sample], model: Model, from: Date) -> [Point] {
        samples.filter { $0.date >= from }.compactMap { s in
            residual(m, s, model: model).map { Point(date: s.date, value: $0, shoeID: s.shoeID) }
        }.sorted { $0.date < $1.date }
    }

    static let trendHalfWindowDays = 14

    /// 4주 이동평균(앞뒤 14일, 3회 이상) — 7일 간격으로. 모든 러닝(신발 무관)
    static func trend(_ pts: [Point], from: Date, to: Date) -> [(date: Date, value: Double)] {
        let cal = Calendar.current
        var out: [(Date, Double)] = []
        var d = from
        while d <= to {
            let lo = cal.date(byAdding: .day, value: -trendHalfWindowDays, to: d)!
            let hi = cal.date(byAdding: .day, value: trendHalfWindowDays, to: d)!
            let w = pts.filter { $0.date >= lo && $0.date <= hi }.map(\.value)
            if w.count >= 3 { out.append((d, w.reduce(0, +) / Double(w.count))) }
            d = cal.date(byAdding: .day, value: 7, to: d)!
        }
        return out
    }

    /// 최근 4주 vs 3개월 전 4주(76~104일 전) 평균 — 양쪽 3회 이상
    static func recentChange(_ pts: [Point], asOf: Date) -> (then: Double, now: Double)? {
        let cal = Calendar.current
        func win(_ a: Int, _ b: Int) -> [Double] {
            let lo = cal.date(byAdding: .day, value: -b, to: asOf)!, hi = cal.date(byAdding: .day, value: -a, to: asOf)!
            return pts.filter { $0.date >= lo && $0.date <= hi }.map(\.value)
        }
        let now = win(0, 28), then = win(76, 104)
        guard now.count >= 3, then.count >= 3 else { return nil }
        return (then.reduce(0, +) / Double(then.count), now.reduce(0, +) / Double(now.count))
    }

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
            let lo = cal.date(byAdding: .day, value: -trendHalfWindowDays, to: p.date)!
            let hi = cal.date(byAdding: .day, value: trendHalfWindowDays, to: p.date)!
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
}
