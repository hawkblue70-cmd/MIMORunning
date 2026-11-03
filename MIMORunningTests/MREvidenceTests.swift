import Testing
import Foundation
@testable import MIMORunning

@Suite("근거 표기 — 본인 기록 줄 + 문헌 줄", .korean)
struct MREvidenceTests {

    @Test func citationTextHasKindAndDetail() {
        #expect(MRCitation.pugh2018.text == "Pugh 2018(관찰 연구, n=96)")
        #expect(MRCitation.blagrove2018.text == "Blagrove 2018(메타분석)")
        #expect(MRCitation.heiderscheit2011.text == "Heiderscheit 2011(실험 연구)")
        #expect(MRCitation.frielDecoupling.text == "Friel 유산소 디커플링 5%(코칭 관행)")
        #expect(MRCitation.acsm2016.with("1~2.5시간 30~60 g/h").text == "ACSM/AND/DC 2016(리뷰·합의, 1~2.5시간 30~60 g/h)")
    }

    @Test func catalogCoversAdviceSourcesOnce() {
        let names = MREvidence.catalog.flatMap(\.cites).map(\.name)
        #expect(names.contains("Frandsen 2025"))
        #expect(names.contains("Int J Sports Med 2023"))
        #expect(Set(names).count == names.count)        // 같은 문헌이 두 기능에 겹쳐 나오지 않는다
        #expect(MREvidence.catalog.allSatisfy { !$0.cites.isEmpty })
    }
}
