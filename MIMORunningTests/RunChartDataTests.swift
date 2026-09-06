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

    @Test func valueOnlyLayersDoNotDrawLines() {
        // 유산소·칼로리는 선을 그리지 않는 값 전용 타일이다.
        #expect(RunChartLayer.aerobic.isValueOnly)
        #expect(RunChartLayer.calories.isValueOnly)
        #expect(!RunChartLayer.heartRate.isValueOnly)
    }
}
