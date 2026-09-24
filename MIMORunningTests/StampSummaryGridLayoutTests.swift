import XCTest
import SwiftUI
@testable import MIMORunning

/// "요약 그리드" 스탬프가 가장 좁은 렌더 폭(211pt · 영상/슬라이드 논리 폭) 안에 들어가는지 실제 렌더로 검증한다.
///
/// 이 스탬프는 3열 고정 격자라 폭이 크기 배율표에 직접 매여 있다. 배율을 올리거나 열 폭·폰트를
/// 건드리면 조용히 카드 밖으로 삐져나가므로, 잉크의 실제 경계를 재서 여백 안에 있는지 본다.
/// (가로 3열 스탬프에서 겪은 줄바꿈 회귀와 같은 부류 — StampCard가 `.fixedSize()`로 감싼다.)
final class StampSummaryGridLayoutTests: XCTestCase {

    private static let cardW: CGFloat = 211
    private static let cardH: CGFloat = 375
    private static let renderScale: CGFloat = 2
    /// StampCard가 스탬프에 주는 좌우 여백 — 워드마크 잉크 왼쪽 선과 같은 기준
    private static var sideInset: CGFloat { 14 + MIMOWordmark.inkLeadingInset(size: 11) }
    private static let bottomPadding: CGFloat = 12

    @MainActor
    func testSummaryGridFitsInsideCardAtEverySize() throws {
        var data = StampData(distance: "10.06", distanceUnit: "KM", pace: "6'43\"", time: "1:07:35",
                             heartRate: "148", calories: "451",
                             dateText: "2026. 9. 11", locationText: "KR", weekday: "FRI",
                             cadence: "182", elevGain: "142")
        data.date = Date()

        for level in [TextSizeLevel.small, .medium, .large, .xlarge] {
            let view = ZStack(alignment: .top) {
                Color(hex: "3A4038")
                StampCard(data: data, template: .summaryGrid, colorMode: .auto,
                          position: .topLeading, sizeLevel: level, isBrightBackground: false,
                          showHeartRate: true, showCalories: true, showTextOutline: true,
                          renderOnlyStamp: true)
            }
            .frame(width: Self.cardW, height: Self.cardH)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = .init(width: Self.cardW, height: Self.cardH)
            renderer.scale = Self.renderScale
            _ = renderer.uiImage   // ImageRenderer 워밍업 (첫 렌더는 레이아웃 미정착)
            _ = renderer.uiImage
            let img = try XCTUnwrap(renderer.uiImage)

            let box = try XCTUnwrap(inkBounds(in: img), "\(level) — 스탬프가 렌더되지 않았다")
            let rightLimit  = (Self.cardW - Self.sideInset + 1) * Self.renderScale
            let bottomLimit = (Self.cardH - Self.bottomPadding + 1) * Self.renderScale
            XCTAssertLessThanOrEqual(box.maxX, rightLimit,
                "\(level): 격자가 오른쪽 여백 밖으로 나갔다 — 배율 또는 열 폭이 너무 크다")
            XCTAssertLessThanOrEqual(box.maxY, bottomLimit,
                "\(level): 스탬프가 아래 여백 밖으로 나갔다")
        }
    }

    /// 심박이 붙으면서 폭이 늘어난 스탬프들 — 배율표를 다시 재지 않으면 조용히 카드 밖으로 나간다.
    @MainActor
    func testHeartRateStampsFitInsideCard() throws {
        for tpl in [StampTemplate.scoreboard, .circleBadge, .routeHero] {
            for level in [TextSizeLevel.small, .medium, .large, .xlarge] {
                let view = ZStack(alignment: .top) {
                    Color(hex: "3A4038")
                    StampCard(data: StampData.sample, template: tpl, colorMode: .auto,
                              position: .topLeading, sizeLevel: level, isBrightBackground: false,
                              showHeartRate: true, showCalories: false, showTextOutline: true,
                              renderOnlyStamp: true)
                }
                .frame(width: Self.cardW, height: Self.cardH)

                let r = ImageRenderer(content: view)
                r.proposedSize = .init(width: Self.cardW, height: Self.cardH)
                r.scale = Self.renderScale
                _ = r.uiImage
                _ = r.uiImage
                let img = try XCTUnwrap(r.uiImage)
                let box = try XCTUnwrap(inkBounds(in: img), "\(tpl.rawValue) \(level) — 렌더되지 않았다")
                let rightLimit = (Self.cardW - Self.sideInset + 1) * Self.renderScale
                XCTAssertLessThanOrEqual(box.maxX, rightLimit,
                    "\(tpl.rawValue) \(level): 오른쪽 여백 밖으로 나갔다 — 배율표를 다시 재야 한다")
            }
        }
    }

    /// 묶음 규칙 — 16km 이하 1km, 40km 이하 2km, 그 이상 3km. 줄 수는 최대 20(40km).
    func testSummaryGridPaceBuckets() {
        func splits(_ n: Int) -> [StampSplit] {
            (0 ..< n).map { i in StampSplit(distanceM: 1000, duration: 360 + Double(i), heartRate: 140 + i) }
        }
        XCTAssertEqual(StampSplit.rows(splits(16)).count, 16)
        XCTAssertEqual(StampSplit.rows(splits(17)).count, 9)
        XCTAssertEqual(StampSplit.rows(splits(40)).count, 20)
        XCTAssertEqual(StampSplit.rows(splits(42)).count, 14)
        let two = StampSplit.rows(splits(20))[0]   // 1·2km 묶음: (360+361)/2km, 심박 (140+141)/2
        XCTAssertEqual(two.endKm, 2, accuracy: 0.001)
        XCTAssertEqual(two.paceSecPerKm, 360.5, accuracy: 0.001)
        XCTAssertEqual(two.heartRate, 141)   // 140.5 반올림
    }

    /// "요약 그리드+페이스" — 격자 아래 세로 목록이 붙어 키가 크다. 특대가 없으니(대로 그림)
    /// 모든 크기에서 오른쪽·아래 여백 안에 들어가야 한다. 줄이 가장 많은 40km(2km×20줄)로 잰다.
    @MainActor
    func testSummaryGridPaceFitsInsideCardAtEverySize() throws {
        var data = StampData.sample
        data.splits = (0 ..< 40).map { i in
            StampSplit(distanceM: 1000, duration: 330 + Double(i % 7) * 6, heartRate: 140 + i % 20)
        }
        XCTAssertFalse(StampTemplate.summaryGridPace.supportsXLarge)
        XCTAssertEqual(StampTemplate.summaryGridPace.stampScale(for: .xlarge),
                       StampTemplate.summaryGridPace.stampScale(for: .large))

        for level in [TextSizeLevel.small, .medium, .large, .xlarge] {
            let view = ZStack(alignment: .top) {
                Color(hex: "3A4038")
                StampCard(data: data, template: .summaryGridPace, colorMode: .auto,
                          position: .topLeading, sizeLevel: level, isBrightBackground: false,
                          showHeartRate: true, showCalories: true, showTextOutline: true,
                          renderOnlyStamp: true)
            }
            .frame(width: Self.cardW, height: Self.cardH)

            let r = ImageRenderer(content: view)
            r.proposedSize = .init(width: Self.cardW, height: Self.cardH)
            r.scale = Self.renderScale
            _ = r.uiImage
            _ = r.uiImage
            let img = try XCTUnwrap(r.uiImage)
            let box = try XCTUnwrap(inkBounds(in: img), "\(level) — 렌더되지 않았다")
            XCTAssertLessThanOrEqual(box.maxX, (Self.cardW - Self.sideInset + 1) * Self.renderScale,
                "\(level): 오른쪽 여백 밖으로 나갔다")
            XCTAssertLessThanOrEqual(box.maxY, (Self.cardH - Self.bottomPadding + 1) * Self.renderScale,
                "\(level): 아래 여백 밖으로 나갔다")
        }
    }

    /// 이 스탬프는 다른 스탬프와 달리 심박·칼로리 토글을 따르지 않는다 —
    /// 격자를 채우는 게 목적이라 있는 지표를 전부(최대 6칸) 보여주는 것이 기본값이다.
    @MainActor
    func testTogglesDoNotChangeSummaryGrid() throws {
        var data = StampData(distance: "10.06", distanceUnit: "KM", pace: "6'43\"", time: "1:07:35",
                             heartRate: "148", calories: "451",
                             dateText: "2026. 9. 11", locationText: "KR", weekday: "FRI",
                             cadence: "182", elevGain: "142")
        data.date = Date()

        func render(hr: Bool, cal: Bool) throws -> Data {
            let view = ZStack(alignment: .top) {
                Color(hex: "3A4038")
                StampCard(data: data, template: .summaryGrid, colorMode: .auto,
                          position: .topLeading, sizeLevel: .large, isBrightBackground: false,
                          showHeartRate: hr, showCalories: cal, showTextOutline: true,
                          renderOnlyStamp: true)
            }
            .frame(width: Self.cardW, height: Self.cardH)
            let r = ImageRenderer(content: view)
            r.proposedSize = .init(width: Self.cardW, height: Self.cardH)
            r.scale = Self.renderScale
            _ = r.uiImage
            _ = r.uiImage
            return try XCTUnwrap(XCTUnwrap(r.uiImage).pngData())
        }

        XCTAssertEqual(try render(hr: false, cal: false), try render(hr: true, cal: true),
                       "요약 그리드는 심박·칼로리 토글과 무관하게 같은 그림이어야 한다")
    }

    /// 배경보다 밝은 픽셀들의 경계 상자(픽셀 좌표).
    @MainActor
    private func inkBounds(in image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let lum = 0.299 * Double(px[i]) + 0.587 * Double(px[i+1]) + 0.114 * Double(px[i+2])
                guard lum > 140 else { continue }
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
