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

/// 상세 화면을 열 가치가 있는지 — 주차별 이행표 유무로 판정.
@Suite("아카이브 상세 진입 가능 여부")
struct ArchiveHasDetailTests {

    @Test func noWeeklyTableMeansNothingToShow() {
        // 소급 재구성에서 계획 주차를 못 만든 경우 — 실제·예측은 목록 행에 이미 있다
        let md = """
        > 이 계획은 나중에 소급 재구성한 것입니다.

        # 2025 서울하프마라톤 · 2025-04-27

        실제  53:46
        계획 시작 시점 예측  1:02:47 (2026-08-06)

        <!-- MIMO-META
        actualMin: 53.77
        -->
        """
        #expect(!mrArchiveHasDetail(md))
    }

    @Test func weeklyTablePresentMeansOpenable() {
        let md = """
        # 대회 · 2025-04-27

        실제  53:46

        \(mrArchiveWeeklySectionHeader)

          주   날짜    단계          롱런(계획/실제)   주간(계획/실제)
        ●  1  01/06  늘리기      12.0 / 13.2       45 / 48
        """
        #expect(mrArchiveHasDetail(md))
    }

    @Test func builderOutputWithWeeksIsOpenable() {
        let cal = Calendar.current
        let raceDate = cal.date(from: DateComponents(year: 2025, month: 4, day: 27))!
        let weeks = (0..<4).map { i in
            MRPlanWeekSummary(idx: i + 1,
                              monday: cal.date(byAdding: .weekOfYear, value: -(5 - i), to: raceDate)!,
                              phase: "늘리기", longRunKm: 12 + Double(i), weeklyKm: 40)
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let weeksJSON = String(data: try! enc.encode(weeks), encoding: .utf8)!

        let snap = RacePlanSnapshot(raceDate: raceDate, raceName: "대회", distanceM: 21097.5,
                                    projectedFinalMin: 118, projectedNowMin: 120, goalMin: 0,
                                    weeksJSON: weeksJSON, metaJSON: "")
        let md = mrBuildArchiveMarkdown(snapshot: snap, actualMin: 117.88,
                                        preRaceProjectedMin: nil, runs: [])
        #expect(mrArchiveHasDetail(md))
    }

    @Test func builderOutputWithoutWeeksIsNotOpenable() {
        let snap = RacePlanSnapshot(raceDate: Date(), raceName: "대회", distanceM: 21097.5,
                                    projectedFinalMin: 118, projectedNowMin: 120, goalMin: 0,
                                    weeksJSON: "", metaJSON: "")
        let md = mrBuildArchiveMarkdown(snapshot: snap, actualMin: 117.88,
                                        preRaceProjectedMin: nil, runs: [])
        #expect(!mrArchiveHasDetail(md))
    }
}
