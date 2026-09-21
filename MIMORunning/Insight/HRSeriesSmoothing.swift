import Foundation

/// 심박 시계열 평활화 — 리듬 카드 심박 차트와 총평(`RunSummaryBuilder`)의 "최고 N"이 **같은 값**을 보게
/// 이 파일 하나만 쓴다.

func hrMovingMedian(_ data: [Int], window: Int) -> [Double] {
    guard !data.isEmpty else { return [] }
    return data.indices.map { i in
        let lo = max(0, i - window / 2)
        let hi = min(data.count - 1, i + window / 2)
        let slice = data[lo...hi].sorted()
        let m = slice.count / 2
        return slice.count % 2 == 0 && slice.count > 1
            ? Double(slice[m - 1] + slice[m]) / 2
            : Double(slice[m])
    }
}

func hrMovingAverage(_ data: [Double], window: Int) -> [Double] {
    guard !data.isEmpty else { return [] }
    return data.indices.map { i in
        let lo = max(0, i - window / 2)
        let hi = min(data.count - 1, i + window / 2)
        let slice = data[lo...hi]
        return slice.reduce(0, +) / Double(slice.count)
    }
}

/// 심박 타임라인 차트와 같은 2단 평활화(이동 중앙값 9 → 이동 평균 25).
/// 차트 축 라벨과 총평 근거의 "최고 N"이 **같은 값**을 보게 이 함수 하나만 쓴다.
func hrChartSmoothed(_ bpm: [Int]) -> [Double] {
    hrMovingAverage(hrMovingMedian(bpm, window: 9), window: 25)
}

/// 출발 직후 광학 심박 오독 구간의 표본 수(nil = 없음).
/// 규칙: 첫 10%(60초~10분) 평균이 그 다음 10~40% 구간 평균보다 15bpm 이상 높고, 그 뒤로는 초반 평균 −5 위로
/// 다시 올라오지 않으면 초반 구간을 오독으로 본다. 생리적으로 출발 직후 심박은 낮게 시작해 올라가므로,
/// 출발이 가장 높고 곧 급락한 뒤 회복이 없는 모양은 측정 문제일 가능성이 크다(10분 미만 러닝은 판단하지 않음).
/// 존 비율·차트는 건드리지 않고, 전후반 비교·최고치 같은 **판정**에서만 제외한다.
func hrEarlyArtifactCount(_ samples: [(offset: TimeInterval, bpm: Int)]) -> Int? {
    guard samples.count >= 30, let first = samples.first, let last = samples.last else { return nil }
    let total = last.offset - first.offset
    guard total >= 600 else { return nil }
    let cut = first.offset + min(600, max(60, total * 0.10))
    let refEnd = first.offset + total * 0.40
    let early = samples.filter { $0.offset < cut }
    let ref = samples.filter { $0.offset >= cut && $0.offset < refEnd }
    guard early.count >= 10, ref.count >= 10 else { return nil }
    let earlyAvg = Double(early.map(\.bpm).reduce(0, +)) / Double(early.count)
    let refAvg = Double(ref.map(\.bpm).reduce(0, +)) / Double(ref.count)
    guard earlyAvg - refAvg >= 15 else { return nil }
    let laterMax = samples.filter { $0.offset >= cut }.map(\.bpm).max() ?? 0
    guard Double(laterMax) < earlyAvg - 5 else { return nil }
    return early.count
}
