import Testing
import Foundation
@testable import MIMORunning

@Suite("RunChartData 표시 정규화")
struct RunChartDataTests {

    @Test func elevationSpanUsesMinimumForFlatCourses() {
        // 4~11m 평지 → 7m 범위. 최소 스팬 30m가 분모가 되어 평평하게 그려진다.
        #expect(RunChartBuilder.displaySpan(range: 7, minSpan: RunChartBuilder.elevationMinSpanM) == 30)
        // 실제 고저차가 크면 실제 범위를 쓴다.
        #expect(RunChartBuilder.displaySpan(range: 120, minSpan: RunChartBuilder.elevationMinSpanM) == 120)
        // 최소 스팬 0이면 예전 동작(자동 스케일)과 같다.
        #expect(RunChartBuilder.displaySpan(range: 7, minSpan: 0) == 7)
    }

    @Test @MainActor func longRunHRKeepsLateRise() {
        // 21km(20km 초과 → 1km 평균 점) · 마지막 2km 심박 160~165 — 예전 창(15/13점)은 끝값을 141 근처로 뭉갰다(2026-10-26)
        let dur: TimeInterval = 7925
        let act = Activity(id: UUID(), type: .running, date: Date(), duration: dur,
                           distance: 21000, calories: nil, avgHeartRate: 146)
        let hr: [(offset: TimeInterval, bpm: Int)] = stride(from: 0.0, through: dur, by: 5).map { t in
            (offset: t, bpm: t > dur * 19 / 21 ? 163 : 140)
        }
        let data = RunChartBuilder.build(activity: act, detail: nil, hrSamples: hr, cadenceSamples: [], powerSamples: [])
        let last = data.series[.heartRate]?.lastValue ?? 0
        #expect(last >= 155)
    }

    @Test @MainActor func elapsedToActiveRemovesPauses() {
        // 0~600초 달리고 300초 멈춘 뒤(심박 표본 없음) 900~1500초 달림 → 이동 시간 1200초
        let offs = stride(from: 0.0, through: 600, by: 5).map { $0 } + stride(from: 900.0, through: 1500, by: 5).map { $0 }
        let f = RunChartBuilder.elapsedToActiveMapper(hrOffsets: offs, activeTotal: 1200)
        #expect(abs(f(600) - 600) < 5)
        #expect(abs(f(1500) - 1200) < 5)
        // 멈춤이 거의 없으면(경과 − 이동 < 60초) 그대로
        let g = RunChartBuilder.elapsedToActiveMapper(hrOffsets: stride(from: 0.0, through: 1200, by: 5).map { $0 }, activeTotal: 1190)
        #expect(g(1000) == 1000)
    }

    @Test func tileOrderFollowsMetricGrid() {
        // 타일 순서 = 러닝 상세 데이터 격자 순서. 페이스는 타일이 없다.
        let tiles = RunChartLayer.allCases.filter(\.hasTile)
        #expect(tiles == [.heartRate, .cadence, .groundContact, .power, .strideLength,
                          .verticalOsc, .aerobic, .calories, .elevation])
        #expect(!RunChartLayer.pace.hasTile)
    }

    @Test @MainActor func groundContactSeriesIsBuiltFromSamples() {
        let act = Activity(id: UUID(), type: .running, date: Date(), duration: 1800,
                           distance: 5000, calories: nil, avgHeartRate: nil)
        let gct: [(offset: TimeInterval, value: Double)] = (0..<120).map {
            (offset: TimeInterval($0) * 15, value: 250 + 20 * sin(Double($0) / 7))
        }
        let data = RunChartBuilder.build(activity: act, detail: nil, hrSamples: [],
                                         cadenceSamples: [], powerSamples: [], gctSamples: gct)
        #expect(data.availableLayers.contains(.groundContact))
        let s = data.series[.groundContact]
        #expect(s != nil && !s!.isEmpty)
        #expect(s!.minValue >= 150 && s!.maxValue <= 400)
        #expect(RunChartLayer.groundContact.unit == "ms")
        #expect(RunChartLayer.groundContact.formatted(257.4) == "257")
    }

    @Test func valueOnlyLayersDoNotDrawLines() {
        // 유산소·칼로리는 선을 그리지 않는 값 전용 타일이다.
        #expect(RunChartLayer.aerobic.isValueOnly)
        #expect(RunChartLayer.calories.isValueOnly)
        #expect(!RunChartLayer.heartRate.isValueOnly)
    }
}
