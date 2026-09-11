import Foundation

/// 고도 누적 상승 계산 — 화면 표시(고도 획득)와 판정(고도 배경 표시 여부)이 **같은 값**을 쓰게 한다.
///
/// GPS 고도는 샘플마다 ±1~3m씩 떨린다. 그 떨림의 오르는 쪽을 전부 더하면 실제보다 훨씬 큰 값이
/// 쌓인다(평지 코스 시뮬레이션에서 실제 40m → 원본 합산 1636m). 그래서 **최소 변화 임계값**을 둔다:
/// 마지막으로 인정한 고도에서 `minStep` 이상 움직였을 때만 그 변화를 반영하고,
/// 그보다 작은 흔들림은 같은 고도로 본다. 평활화보다 실제값에 가깝다(같은 시뮬레이션에서 41m).
enum ElevationGain {

    /// GPS 떨림으로 볼 최대 변화(m).
    static let minStep: Double = 2

    /// 임계값 앞에 거는 이동 평균 창(점). 고주파 떨림을 먼저 눌러야 임계값을 낮게 쓸 수 있다.
    static let smoothingWindow = 5

    /// 누적 상승(m). 내려간 구간은 세지 않는다.
    ///
    /// **평활화 → 임계값** 두 단계를 거친다. 실제 러닝과 비슷한 고도열로 맞춰본 결과다.
    /// (실제 0m 떨림 / 실제 30m 상승 / 실제 32m 완만한 기복 세 경우)
    ///   · 평활화 없이 2m  → 2398 / 733 / 34   — 떨림에 완전히 무너진다
    ///   · 평활화 없이 3m  →    0 /  27 / 25   — 완만한 기복을 20% 깎는다
    ///   · 평활화 5점 + 3m →    0 /  27 /  0   — 기복이 통째로 사라진다
    ///   · **평활화 5점 + 2m →  0 /  28 / 34** — 세 경우 모두 실제값에 가깝다
    static func cumulative(_ altitudes: [Double], minStep: Double = minStep) -> Double {
        guard let first = altitudes.first, altitudes.count > 1 else { return 0 }
        let values = smoothed(altitudes)
        var gain = 0.0
        var anchor = values.first ?? first   // 마지막으로 "진짜 움직였다"고 인정한 고도
        for altitude in values.dropFirst() {
            let delta = altitude - anchor
            guard abs(delta) >= minStep else { continue }
            if delta > 0 { gain += delta }
            anchor = altitude
        }
        return gain
    }

    /// 이동 평균 — 창보다 짧은 고도열은 그대로 둔다
    private static func smoothed(_ altitudes: [Double]) -> [Double] {
        guard altitudes.count > smoothingWindow else { return altitudes }
        let half = smoothingWindow / 2
        return altitudes.indices.map { i in
            let lo = max(0, i - half), hi = min(altitudes.count - 1, i + half)
            return altitudes[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
    }
}
