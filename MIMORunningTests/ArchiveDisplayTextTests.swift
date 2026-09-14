import Testing
import Foundation
@testable import MIMORunning

/// 아카이브 상세 표시 — MIMO-META 주석은 저장만 하고 화면에는 안 보인다.
@Suite("아카이브 표시 텍스트")
struct ArchiveDisplayTextTests {

    @Test func stripsTrailingMetaBlock() {
        let md = """
        # 2025 서울하프마라톤 · 2025-04-27

        실제  53:46

        <!-- MIMO-META
        modelVersion: m2
        distanceM: 10000
        actualMin: 53.77
        -->
        """
        let shown = mrArchiveDisplayText(md)
        #expect(!shown.contains("MIMO-META"))
        #expect(!shown.contains("modelVersion"))
        #expect(!shown.contains("-->"))
        #expect(shown.hasSuffix("실제  53:46"))
    }

    @Test func keepsContentAfterTheMetaBlock() {
        // META가 끝이 아닌 위치에 있어도 뒤 내용은 살린다
        let md = "앞\n<!-- MIMO-META\nx: 1\n-->\n뒤"
        #expect(mrArchiveDisplayText(md) == "앞\n\n뒤")
    }

    @Test func passesThroughWhenNoMeta() {
        let md = "# 대회\n\n실제  1:57:53"
        #expect(mrArchiveDisplayText(md) == md)
    }

    @Test func keepsUserFacingRetroNote() {
        let md = "> 이 계획은 나중에 소급 재구성한 것입니다.\n\n# 대회\n\n<!-- MIMO-META\na: 1\n-->"
        let shown = mrArchiveDisplayText(md)
        #expect(shown.hasPrefix("> 이 계획은 나중에 소급 재구성한 것입니다."))
        #expect(!shown.contains("MIMO-META"))
    }

    @Test func handlesUnterminatedMetaBlock() {
        // 닫는 --> 가 없어도 남은 부분을 전부 잘라낸다 (무한 루프 없이)
        let md = "본문\n\n<!-- MIMO-META\nmodelVersion: m2"
        #expect(mrArchiveDisplayText(md) == "본문")
    }

    @Test func buildArchiveMarkdownStillStoresMeta() {
        // 저장되는 마크다운 자체에는 META가 남아 있어야 한다 — 표시만 자르는 것
        let snap = RacePlanSnapshot(raceDate: Date(), raceName: "테스트", distanceM: 10000,
                                    projectedFinalMin: 55, projectedNowMin: 57,
                                    goalMin: 0, weeksJSON: "", metaJSON: "")
        let md = mrBuildArchiveMarkdown(snapshot: snap, actualMin: 53.77,
                                        preRaceProjectedMin: nil, runs: [])
        #expect(md.contains("<!-- MIMO-META"))
        #expect(md.contains("actualMin: 53.77"))
        #expect(!mrArchiveDisplayText(md).contains("MIMO-META"))
    }
}
