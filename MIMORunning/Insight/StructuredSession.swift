import Foundation

/// 몸 풀기 → 본 구간(빠르게) → 마무리로 나눠 뛴 러닝 — km 구간만으로 알아본다(2026-11-11 사용자: 몸 풀기 2km · 하프 대회
/// 페이스 2km · 마무리 1km를 '일반 러닝'·'마지막 2km 페이스 떨어짐'·'다음엔 중반을 늦게'로 읽었다).
///
/// 조건(모두):
/// - 본 구간 = 이어진 1km 구간 2개 이상. 안쪽 페이스 차 20초/km 이하(고르게 빠름).
/// - 앞(몸 풀기)·뒤(마무리)가 모두 있다 — 앞 0.9km↑, 뒤 0.4km↑. 뒤가 없으면 빌드업 쪽 판정이 맡는다.
/// - 본 구간 평균이 앞·뒤 평균보다 각각 20초/km 이상 빠르다.
/// - 본 구간에서 가장 느린 km가 바깥에서 가장 빠른 km(0.5km↑ 구간)보다 10초/km 이상 빠르다.
/// 후보가 여럿이면 본 구간이 긴 쪽, 같으면 대비가 큰 쪽.
struct MRStructuredSession {
    let warmup: [SplitData]
    let main: [SplitData]
    let cooldown: [SplitData]
    /// 입력(정렬된) 구간 배열에서 본 구간 마지막 인덱스
    let mainEndIndex: Int

    static let contrastSec = 20.0
    static let edgeGapSec = 10.0
    static let mainSpreadSec = 20.0
    static let minMainSplits = 2

    var warmupKm: Double { Self.km(warmup) }
    var mainKm: Double { Self.km(main) }
    var cooldownKm: Double { Self.km(cooldown) }
    /// 본 구간 시간 가중 페이스(초/km)
    var mainPace: Double { Self.pace(main) }
    /// 본 구간 시간 가중 평균 심박 — 심박 있는 구간만
    var mainHR: Int? {
        var sum = 0.0, t = 0.0
        for s in main { if let hr = s.avgHeartRate { sum += Double(hr) * s.duration; t += s.duration } }
        guard t > 0 else { return nil }
        return Int((sum / t).rounded())
    }
    /// 본 구간이 끝난 시점(달린 시간, 멈춤 제외) — 심박 표본을 자를 때
    var mainEndActiveSec: TimeInterval { (warmup + main).map(\.duration).reduce(0, +) }

    static func km(_ s: [SplitData]) -> Double { s.map(\.distanceM).reduce(0, +) / 1000 }
    static func pace(_ s: [SplitData]) -> Double {
        let d = s.map(\.distanceM).reduce(0, +), t = s.map(\.duration).reduce(0, +)
        return d > 0 ? t / (d / 1000) : 0
    }

    static func detect(_ splits: [SplitData]) -> MRStructuredSession? {
        let s = splits.filter { $0.distanceM > 0 && $0.duration > 0 }.sorted { $0.id < $1.id }
        guard s.count >= minMainSplits + 2 else { return nil }
        var best: (i: Int, j: Int, contrast: Double)? = nil
        for i in 1..<s.count {
            // 본 구간 끝 후보의 시작 — 뒤에 마무리 구간이 하나 이상 남아야 한다. 넘으면 이후 i도 모두 넘으니 끝낸다.
            // ⚠ 이 확인 없이 `(i + minMainSplits - 1)..<s.count`로 쓰면 minMainSplits가 3 이상일 때 범위가 뒤집혀 종료된다.
            let jStart = i + minMainSplits - 1
            guard jStart < s.count - 1 else { break }
            for j in jStart..<(s.count - 1) {
                let main = Array(s[i...j]), before = Array(s[..<i]), after = Array(s[(j + 1)...])
                guard main.allSatisfy({ $0.distanceM >= 900 }),
                      km(before) >= 0.9, km(after) >= 0.4 else { continue }
                let mp = main.map(\.paceSecPerKm)
                guard let slow = mp.max(), let fast = mp.min(), slow - fast <= mainSpreadSec else { continue }
                let outside = (before + after).filter { $0.distanceM >= 500 }.map(\.paceSecPerKm)
                guard let outFast = outside.min(), outFast - slow >= edgeGapSec else { continue }
                let p = pace(main)
                let cb = pace(before) - p, ca = pace(after) - p
                guard cb >= contrastSec, ca >= contrastSec else { continue }
                let c = min(cb, ca)
                if let b = best {
                    let bl = b.j - b.i, nl = j - i
                    if nl > bl || (nl == bl && c > b.contrast) { best = (i, j, c) }
                } else {
                    best = (i, j, c)
                }
            }
        }
        guard let b = best else { return nil }
        return MRStructuredSession(warmup: Array(s[..<b.i]), main: Array(s[b.i...b.j]),
                                   cooldown: Array(s[(b.j + 1)...]), mainEndIndex: b.j)
    }

    /// 판정용 구간 — 구성을 알아본 러닝이면 마무리를 뺀다(마무리 감속을 "페이스 떨어짐"으로 읽지 않게). 아니면 그대로.
    static func splitsWithoutCooldown(_ splits: [SplitData]) -> [SplitData] {
        guard let x = detect(splits) else { return splits }
        return x.warmup + x.main
    }
}
