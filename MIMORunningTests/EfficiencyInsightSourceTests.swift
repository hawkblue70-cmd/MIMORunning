import XCTest
@testable import MIMORunning

final class EfficiencyInsightSourceTests: XCTestCase {
    func testDriftWithEfficiencyCategoryIsNotComparison() {
        let drift = RunInsight(category: .efficiency, tone: .good, badge: "", message: "전반/후반 심박 차이 4bpm", highlights: ["4bpm"])
        let comp = RunInsight(category: .efficiency, tone: .good, badge: "", message: "…심박이 6bpm 낮았습니다.", highlights: ["6bpm"],
                              source: .efficiencyComparison)
        XCTAssertNil(RunInsight.efficiencyComparison(in: [drift]))
        XCTAssertEqual(RunInsight.efficiencyComparison(in: [drift, comp])?.highlights, ["6bpm"])
    }
}
