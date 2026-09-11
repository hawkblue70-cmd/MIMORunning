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
    /// **평활화 → 정점-골 검출** 두 단계를 거친다.
    /// 정점에서 `minStep` 이상 되돌아가야 그 상승을 확정한다 — 오르는 도중의 작은 흔들림에
    /// 끊기지 않고 봉우리 전체를 한 번에 센다.
    ///
    /// 앞서 쓰던 "마지막 인정 지점에서 minStep 넘을 때마다 더하기" 방식은 정점 직전의 잔여분을
    /// 통째로 버려서, 진폭 3m와 4m 기복이 **같은 값**(30.4m)을 내는 등 진폭에 비례하지 않았다.
    ///
    /// 지금 방식의 실측(평활 5점 + 2m, 8회 오르내림 기준):
    ///   진폭 3m → 47.8 (이론 48) · 4m → 63.8 (64) · 25m → 398.6 (400)
    ///   ±1.2m 톱니 떨림 → 0 · 떨림 속 실제 30m 상승 → 30.1
    static func cumulative(_ altitudes: [Double], minStep: Double = minStep) -> Double {
        guard let first = altitudes.first, altitudes.count > 1 else { return 0 }
        let values = smoothed(altitudes)
        var gain = 0.0
        var anchor = values.first ?? first   // 이번 상승이 시작된 골
        var peak = anchor                    // 진행 중인 상승의 정점 후보

        for value in values.dropFirst() {
            if value > peak { peak = value }
            if peak - value >= minStep {
                // 정점에서 충분히 내려왔다 → 이번 상승을 확정하고 새 골에서 다시 시작
                if peak - anchor >= minStep { gain += peak - anchor }
                anchor = value
                peak = value
            } else if value < anchor {
                // 아직 상승으로 인정되기 전인데 더 내려갔다 → 더 낮은 골로 갱신
                anchor = value
                peak = value
            }
        }
        // 끝에서 진행 중이던 상승 마무리 (오르막으로 끝나는 코스)
        if peak - anchor >= minStep { gain += peak - anchor }
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
