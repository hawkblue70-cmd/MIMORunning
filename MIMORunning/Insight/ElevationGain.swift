import Foundation

/// 고도 누적 상승 계산 — 화면 표시(고도 획득)와 판정(고도 배경 표시 여부)이 **같은 값**을 쓰게 한다.
///
/// GPS 고도는 샘플마다 ±1~3m씩 떨린다. 그 떨림의 오르는 쪽을 전부 더하면 실제보다 훨씬 큰 값이
/// 쌓인다(평지 코스 시뮬레이션에서 실제 40m → 원본 합산 1636m). 그래서 **최소 변화 임계값**을 둔다:
/// 마지막으로 인정한 고도에서 `minStep` 이상 움직였을 때만 그 변화를 반영하고,
/// 그보다 작은 흔들림은 같은 고도로 본다. 평활화보다 실제값에 가깝다(같은 시뮬레이션에서 41m).
enum ElevationGain {

    /// GPS 떨림으로 볼 최대 변화(m).
    /// 실제 러닝과 비슷한 고도열로 맞춰본 값 — 1m는 노이즈에 무너지고(실제 32m가 486m),
    /// 3m는 완만한 기복을 20%씩 깎는다(32m → 25m). 2m가 네 유형 모두에서 실제값에 가장 가깝다.
    static let minStep: Double = 2

    /// 누적 상승(m). 내려간 구간은 세지 않는다.
    static func cumulative(_ altitudes: [Double], minStep: Double = minStep) -> Double {
        guard let first = altitudes.first, altitudes.count > 1 else { return 0 }
        var gain = 0.0
        var anchor = first          // 마지막으로 "진짜 움직였다"고 인정한 고도
        for altitude in altitudes.dropFirst() {
            let delta = altitude - anchor
            guard abs(delta) >= minStep else { continue }
            if delta > 0 { gain += delta }
            anchor = altitude
        }
        return gain
    }
}
