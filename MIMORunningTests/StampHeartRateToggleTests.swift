import XCTest
import SwiftUI
@testable import MIMORunning

/// `supportsHeartRateToggle`이 실제 그림과 맞는지 렌더로 검사한다.
///
/// 이 값은 심박 칩을 보여줄지 정한다. 코드와 어긋나면 눌러도 아무 일이 없는 칩이 뜨거나,
/// 반대로 켤 수 있는 스탬프에서 칩이 사라진다. 목록을 손으로 관리하므로 검사가 필요하다.
@MainActor
final class StampHeartRateToggleTests: XCTestCase {

    private func render(_ tpl: StampTemplate, hr: Bool) throws -> Data {
        let data = StampData.sample
        let view = ZStack {
            Color(hex: "3A4038")
            StampCard(data: data, template: tpl, colorMode: .brand, position: .center,
                      sizeLevel: .large, isBrightBackground: false,
                      showHeartRate: hr, showCalories: false, showTextOutline: false,
                      renderOnlyStamp: true)
        }
        .frame(width: 300, height: 220)

        let r = ImageRenderer(content: view)
        r.proposedSize = .init(width: 300, height: 220)
        r.scale = 1
        _ = r.uiImage   // ImageRenderer 워밍업
        _ = r.uiImage
        return try XCTUnwrap(XCTUnwrap(r.uiImage).pngData())
    }

    func testFlagMatchesActualRendering() throws {
        for tpl in StampTemplate.allCases {
            let off = try render(tpl, hr: false)
            let on  = try render(tpl, hr: true)
            let changed = off != on
            XCTAssertEqual(changed, tpl.supportsHeartRateToggle,
                           "\(tpl.rawValue): 심박 토글이 그림을 \(changed ? "바꾸는데 supportsHeartRateToggle=false" : "안 바꾸는데 supportsHeartRateToggle=true")")
        }
    }

    /// 요약 그리드는 토글과 무관하게 심박을 항상 넣는다 — 칩도 뜨지 않아야 한다.
    func testSummaryGridHasNoToggle() {
        XCTAssertFalse(StampTemplate.summaryGrid.supportsHeartRateToggle)
    }
}
