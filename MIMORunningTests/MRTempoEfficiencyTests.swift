import Testing
import Foundation
@testable import MIMORunning

@Suite("템포 구간 효율 — 같은 페이스 km의 심박", .korean)
struct MRTempoEfficiencyTests {

    private func split(_ id: Int, pace: Double, hr: Int?, m: Double = 1000) -> SplitData {
        SplitData(id: id, distanceM: m, duration: pace * m / 1000, avgHeartRate: hr, avgCadence: nil, avgPower: nil,
                  avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
    }
    private typealias T = MRTempoEfficiency

    @Test func kmRowsSkipWarmupLateKmPartialAndNoHR() {
        let s = (1...12).map { split($0, pace: 330, hr: 150 + $0) }
            + [split(13, pace: 330, hr: 170, m: 500)]
        var rows = T.kmRows(splits: s)
        #expect(rows.map(\.km) == Array(3...10))
        rows = T.kmRows(splits: [split(3, pace: 330, hr: nil), split(4, pace: 330, hr: 160)])
        #expect(rows.map(\.km) == [4])
    }

    @Test func runValueUsesBandAroundThresholdAndNeedsTwoKm() throws {
        // 역치 5'18"(318) → 띠 323~343. 330·340만 들어간다. 300(빠름)·360(느림)은 빠진다.
        let kms = [T.KmRow(km: 3, paceSec: 300, hr: 170), T.KmRow(km: 4, paceSec: 330, hr: 160),
                   T.KmRow(km: 5, paceSec: 340, hr: 164), T.KmRow(km: 6, paceSec: 360, hr: 150)]
        let r = T.RunRow(date: Date(), type: .tempo, tempC: nil, kms: kms)
        let v = try #require(T.runValue(r, thresholdPace: 318, heat: MRHeatHRModel()))
        #expect(v.kmCount == 2)
        #expect(v.hr == 162)
        #expect(v.paceSec == 335)
        // 한 km뿐이면 없음
        let one = T.RunRow(date: Date(), type: .tempo, tempC: nil, kms: [kms[1], kms[3]])
        #expect(T.runValue(one, thresholdPace: 318, heat: MRHeatHRModel()) == nil)
    }

    @Test func runValueHeatAdjustedAndIntervalExcluded() throws {
        let kms = [T.KmRow(km: 3, paceSec: 330, hr: 170), T.KmRow(km: 4, paceSec: 332, hr: 172)]
        // 25°C · 문헌 0.8bpm/°C → 8bpm 빼서 15°C 기준
        let hot = T.RunRow(date: Date(), type: .tempo, tempC: 25, kms: kms)
        let v = try #require(T.runValue(hot, thresholdPace: 318, heat: .fallback()))
        #expect(abs(v.hr - 163) < 1e-9)
        #expect(v.rawHR == 171)
        // 인터벌은 회복 구간이 섞인 km라 쓰지 않는다
        let iv = T.RunRow(date: Date(), type: .interval, tempC: nil, kms: kms)
        #expect(T.runValue(iv, thresholdPace: 318, heat: MRHeatHRModel()) == nil)
        // 대회도 제외 — 범위에 드는 대회 km는 후반에 지쳐 느려진 km라 심박이 높다(2026-11-03 실기기 10/4 169bpm)
        let race = T.RunRow(date: Date(), type: .race, tempC: nil, kms: kms)
        #expect(T.runValue(race, thresholdPace: 318, heat: MRHeatHRModel()) == nil)
    }

    // MARK: 평소 페이스 띠 — 본인 km 페이스 중앙값 ±10초 (표본 확보용)

    @Test func usualBandIsMedianKmPaceOfEligibleRuns() throws {
        let easy = T.RunRow(date: Date(), type: .easy, tempC: nil,
                            kms: [.init(km: 3, paceSec: 355, hr: 140), .init(km: 4, paceSec: 360, hr: 141),
                                  .init(km: 5, paceSec: 365, hr: 142)])
        // 대회·인터벌 km는 중앙값에 넣지 않는다
        let race = T.RunRow(date: Date(), type: .race, tempC: nil,
                            kms: [.init(km: 3, paceSec: 300, hr: 170), .init(km: 4, paceSec: 300, hr: 170),
                                  .init(km: 5, paceSec: 300, hr: 170), .init(km: 6, paceSec: 300, hr: 170)])
        let b = try #require(T.usualBand([easy, race]))
        #expect(b.lowerBound == 350)
        #expect(b.upperBound == 370)
    }

    @Test func runValueInUsualBand() throws {
        let r = T.RunRow(date: Date(), type: .easy, tempC: nil,
                         kms: [.init(km: 3, paceSec: 355, hr: 140), .init(km: 4, paceSec: 362, hr: 144),
                               .init(km: 5, paceSec: 330, hr: 160)])
        let v = try #require(T.runValue(r, band: 350...370, heat: MRHeatHRModel()))
        #expect(v.kmCount == 2)
        #expect(v.hr == 142)
    }

    @Test func paceCorrectedToBandCenter() throws {
        // 띠 350~370 가운데 360. 370으로 뛴 러닝은 느린 만큼 심박이 낮다 — 본인 기울기 0.5bpm/(m/min)로 360 기준 환산
        let r = T.RunRow(date: Date(), type: .easy, tempC: nil,
                         kms: [.init(km: 3, paceSec: 370, hr: 140), .init(km: 4, paceSec: 370, hr: 140)])
        let v = try #require(T.runValue(r, band: 350...370, heat: MRHeatHRModel(), bpmPerMetersPerMin: 0.5))
        let expected = 140 + 0.5 * (60_000.0 / 360 - 60_000.0 / 370)
        #expect(abs(v.hr - expected) < 1e-9)
        #expect(v.rawHR == 140)
    }

    @Test func trendKeepsMonthsWithFiveRuns() {
        let cal = Calendar(identifier: .gregorian)
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: 7))! }
        func row(_ date: Date) -> T.RunRow {
            T.RunRow(date: date, type: .easy, tempC: nil,
                     kms: [.init(km: 3, paceSec: 360, hr: 145), .init(km: 4, paceSec: 360, hr: 145)])
        }
        let may = (1...4).map { row(d(5, $0)) }, june = (1...5).map { row(d(6, $0)) }
        let t = T.trend(may + june, band: 350...370, heat: MRHeatHRModel(), bpmPerMetersPerMin: nil, calendar: cal)
        #expect(t.map(\.runs) == [5])
    }

    // MARK: 성장 탭 카드 — 주별 점(2번↑) + 최근 4주 중앙값 선(5번↑), 선 점 8개↑일 때만(2026-11-10)

    /// 2026-06-01(월)부터 주 2번(월·목) — hr(주 번호)로 주마다 심박
    private func weeklyRuns(_ cal: Calendar, weeks: Int, pace: Double, hr: (Int) -> Double) -> [T.RunRow] {
        let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7))!
        return (0..<weeks).flatMap { w in
            [0, 3].map { off in
                let d = cal.date(byAdding: .day, value: w * 7 + off, to: start)!
                return T.RunRow(date: d, type: .easy, tempC: nil,
                                kms: [.init(km: 3, paceSec: pace, hr: hr(w)), .init(km: 4, paceSec: pace, hr: hr(w))])
            }
        }
    }

    @Test func usualTrendWeeklyPointsAndFourWeekLine() throws {
        let cal = Calendar(identifier: .gregorian)
        // 9주면 4주 선 점이 7개(3주째부터 5번↑) — 카드 없음
        #expect(T.usualTrend(weeklyRuns(cal, weeks: 9, pace: 375, hr: { _ in 141 }), heat: MRHeatHRModel(),
                             bpmPerMetersPerMin: nil, calendar: cal) == nil)
        // 10주: 앞 6주 141, 뒤 4주 145 → 최근 4주 중앙값 145
        let t = try #require(T.usualTrend(weeklyRuns(cal, weeks: 10, pace: 375, hr: { $0 < 6 ? 141 : 145 }),
                                          heat: MRHeatHRModel(), bpmPerMetersPerMin: nil, calendar: cal))
        #expect(t.weeks.count == 10)
        #expect(t.rolling.count == 8)
        #expect(t.first.hr == 141)
        #expect(t.latest.hr == 145)
        #expect(t.latest.runs == 8)
        #expect(t.centerPace == 375)
        #expect(t.band == 365...385)
    }

    @Test func monthlyMediansGroupByCalendarMonth() {
        let cal = Calendar(identifier: .gregorian)
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: 7))! }
        func row(_ date: Date, _ hr: Double) -> T.RunRow {
            T.RunRow(date: date, type: .tempo, tempC: nil,
                     kms: [.init(km: 3, paceSec: 330, hr: hr), .init(km: 4, paceSec: 330, hr: hr)])
        }
        let months = T.monthly([row(d(9, 3), 160), row(d(9, 20), 164), row(d(9, 25), 170), row(d(10, 2), 158)],
                               thresholdPace: 318, heat: MRHeatHRModel(), calendar: cal)
        #expect(months.count == 2)
        #expect(months[0].runs == 3)
        #expect(months[0].kmCount == 6)
        #expect(months[0].hr == 164)
        #expect(months[1].hr == 158)
    }
}
