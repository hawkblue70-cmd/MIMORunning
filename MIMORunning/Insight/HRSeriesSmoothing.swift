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
