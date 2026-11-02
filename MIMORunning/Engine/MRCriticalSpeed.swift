import Foundation

// MARK: - 임계 속도(CS) — 평소 훈련 기록으로 추정 (1단계: 진단 로그만, 화면 없음)
//
// 설계: docs/research/2026-11-03-literature-and-suggestions.md 6절
//
// 근거: Hunter, Ledger & Muniz-Pumares 2023 (IJSPP 18(12):1449–1456, n=23) — 평소 훈련 6주의 최고 3·7·12분 구간으로
//   낸 CS가 타임트라이얼 CS와 같았다(3.44 vs 3.42 m/s, r 0.86, CoV 5.6%). D′는 방법마다 CoV 50%라 쓰지 않는다.
// 앱 적용(문헌 = 틀, 본인 데이터 = 값):
//   · 점 = km 스플릿의 연속 1·2·3·4km 창 최고 시간(5'00" 기준 5·10·15·20분). 2~20분 안의 점만.
//   · 모델 = 거리–시간 선형 D = CS·t + D′ (표준 2-모수 모델).
//   · 강한 러닝(인터벌·템포·빌드업·거리주·대회)만 — 평소 이지런은 최대 노력이 아니라 CS를 낮춘다.
// ⚠ CS는 LT2 쪽 지표다(LT1 앵커로 쓰지 않는다 — `MRPhysiology` 주석).
// ⚠ 8주 창은 논문 6주에 2주 여유를 둔 값(임의로 정함). 2~20분은 CS 문헌의 흔한 범위(논문은 3·7·12분).

enum MRCriticalSpeed {
    static let maxWindowKm = 4
    static let minTimeSec = 120.0
    static let maxTimeSec = 1200.0
    static let windowWeeks = 8
    /// 점이 나온 서로 다른 러닝 수 하한 ⚠ 임의로 정함 — 한 러닝이면 그 러닝 페이스일 뿐
    static let minDistinctRuns = 2
    /// 최대 노력으로 볼 수 있는 저장 유형
    static let hardTypes: Set<WorkoutType> = [.interval, .tempo, .buildUp, .distanceRun, .race]

    /// 러닝 한 건의 최고 연속 km 구간 — 캐시에 저장하는 단위
    struct RunBest: Equatable {
        let date: Date
        let type: WorkoutType?
        /// km 창(1…4) → 최고 시간(초)
        let best: [Int: Double]
    }

    struct Fit: Equatable {
        let csMps: Double
        let dPrimeM: Double
        let r2: Double
    }

    struct Point: Equatable {
        let km: Int
        let timeSec: Double
        let date: Date
    }

    struct Estimate: Equatable {
        let fit: Fit
        let points: [Point]
        var paceSecPerKm: Double { MRCriticalSpeed.paceSecPerKm(csMps: fit.csMps) }
    }

    static func paceSecPerKm(csMps: Double) -> Double { 1000 / csMps }

    /// 온전한 km 스플릿(990m↑)이 번호가 이어지는 구간에서 1…4km 창의 최고 시간. 마지막 부분 km·빠진 번호는 창을 끊는다.
    static func bestKmTimes(splits: [SplitData]) -> [Int: Double] {
        // 이어진 온전한 km 묶음들
        var runsOfKm: [[Double]] = []
        var cur: [Double] = []
        var lastID: Int? = nil
        for s in splits.sorted(by: { $0.id < $1.id }) {
            let full = s.distanceM >= 990 && s.duration > 0
            if full, let l = lastID, s.id == l + 1 {
                cur.append(s.duration)
            } else {
                if !cur.isEmpty { runsOfKm.append(cur) }
                cur = full ? [s.duration] : []
            }
            lastID = full ? s.id : nil
        }
        if !cur.isEmpty { runsOfKm.append(cur) }

        var best: [Int: Double] = [:]
        for seq in runsOfKm {
            for k in 1...maxWindowKm where seq.count >= k {
                var sum = seq.prefix(k).reduce(0, +)
                var m = sum
                for i in k..<seq.count {
                    sum += seq[i] - seq[i - k]
                    m = min(m, sum)
                }
                best[k] = min(best[k] ?? .infinity, m)
            }
        }
        return best
    }

    /// 거리–시간 선형 회귀(거리 = CS·시간 + D′). 2~20분 안의 점 3개↑, CS > 0일 때만.
    static func fit(points: [(distanceM: Double, timeSec: Double)]) -> Fit? {
        let p = points.filter { $0.timeSec >= minTimeSec && $0.timeSec <= maxTimeSec }
        guard p.count >= 3 else { return nil }
        let n = Double(p.count)
        let mt = p.map(\.timeSec).reduce(0, +) / n
        let md = p.map(\.distanceM).reduce(0, +) / n
        let stt = p.map { ($0.timeSec - mt) * ($0.timeSec - mt) }.reduce(0, +)
        guard stt > 0 else { return nil }
        let std = p.map { ($0.timeSec - mt) * ($0.distanceM - md) }.reduce(0, +)
        let slope = std / stt
        guard slope > 0 else { return nil }
        let icpt = md - slope * mt
        let sst = p.map { ($0.distanceM - md) * ($0.distanceM - md) }.reduce(0, +)
        let sse = p.map { (q: (distanceM: Double, timeSec: Double)) -> Double in
            let e = q.distanceM - (icpt + slope * q.timeSec)
            return e * e
        }.reduce(0, +)
        return Fit(csMps: slope, dPrimeM: icpt, r2: sst > 0 ? 1 - sse / sst : 0)
    }

    /// 최근 8주 강한 러닝에서 km 창마다 최고 시간을 골라 CS를 맞춘다. `hardOnly`가 false면 모든 러닝(진단 비교용).
    static func estimate(runs: [RunBest], asOf: Date, hardOnly: Bool = true) -> Estimate? {
        let from = asOf.addingTimeInterval(-Double(windowWeeks * 7) * 86400)
        let pool = runs.filter { $0.date >= from && $0.date <= asOf
            && (!hardOnly || $0.type.map { hardTypes.contains($0) } ?? false) }
        var pts: [Point] = []
        for k in 1...maxWindowKm {
            let cands = pool.compactMap { r in r.best[k].map { (t: $0, d: r.date) } }
            guard let b = cands.min(by: { $0.t < $1.t }), b.t >= minTimeSec, b.t <= maxTimeSec else { continue }
            pts.append(Point(km: k, timeSec: b.t, date: b.d))
        }
        // 점이 한 러닝에서만 나오면 CS가 아니라 그 러닝 페이스다 — 10K 대회 앞 1~3km 셋으로 CS = 10K 평균(2026-11-03 실기기)
        guard Set(pts.map(\.date)).count >= minDistinctRuns else { return nil }
        guard let f = fit(points: pts.map { (distanceM: Double($0.km) * 1000, timeSec: $0.timeSec) }) else { return nil }
        return Estimate(fit: f, points: pts)
    }
}

#if DEBUG
/// 진단 로그 비교용 — 엔진 스토어의 역치 페이스와 CS를 한 줄로 맞대기 위해 둘 중 늦게 나온 쪽이 비교 줄을 찍는다.
@MainActor enum MRCriticalSpeedDiag {
    static var thresholdPace: Double? { didSet { logComparison() } }
    static var csPace: Double? { didSet { logComparison() } }

    private static func logComparison() {
        guard let t = thresholdPace, let c = csPace else { return }
        let pct = (t / c - 1) * 100   // + = CS가 역치보다 빠름
        let verdict = (2...5).contains(pct) ? "문헌 기대 범위(2~5% 빠름)"
            : pct < 2 ? "기대보다 느림 — 최대 노력 부족 가능" : "기대보다 빠름 — 구간 기록 튐 확인"
        print("[CS] 비교: CS \(mrFormatPace(c)) · 역치 \(mrFormatPace(t)) · CS가 \(String(format: "%+.1f", pct))% → \(verdict)")
    }
}
#endif
