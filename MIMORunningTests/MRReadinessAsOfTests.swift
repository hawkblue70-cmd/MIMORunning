import Testing
import Foundation
@testable import MIMORunning

/// 내보내기용 아침 제안 재계산(asOf) — 그 시각 이후 기록이 판정에 끼지 않아야 한다.
@Suite("아침 제안 asOf 재계산", .korean)
struct MRReadinessAsOfTests {

    private let cal = Calendar.current
    /// 기준 날 07:00 러닝 — 그 1초 전이 '그날 아침' asOf
    private var runDayStart: Date {
        let base = cal.date(byAdding: .day, value: -10, to: Date())!
        return cal.date(bySettingHour: 7, minute: 0, second: 0, of: base)!
    }
    private var asOf: Date { runDayStart.addingTimeInterval(-1) }

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: runDayStart)!)
    }

    private func run(dayOffset: Int, minutes: Double = 50, hr: Double = 140, hour: Int = 7) -> MRWorkout {
        MRWorkout(start: day(dayOffset).addingTimeInterval(Double(hour) * 3600), durationMin: minutes, distanceKm: 8,
                  hrAvg: hr, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }

    /// asOf 이전 5주 주 3회 이지런 — 만성 4주(7…34일)를 모두 채워 부하 비율이 튀지 않게.
    private func pastRuns() -> [MRWorkout] {
        [-34, -32, -29, -27, -25, -22, -20, -18, -15, -13, -11, -8, -6, -3, -1].map { run(dayOffset: $0) }
    }

    /// 4주 기준 + 최근 7일 밤(기준 날 키 포함) + 기준 날 이후 밤(미래 — 걸러져야 함)
    private func nights(futureValue: Double) -> [(date: Date, value: Double)] {
        var out: [(date: Date, value: Double)] = []
        for i in 0..<28 { out.append((day(-34 + i), 30 + (i % 2 == 0 ? 1 : -1))) }
        for d in -6...0 { out.append((day(d), 31)) }
        for d in 1...5 { out.append((day(d), futureValue)) }
        return out
    }

    private var phys: MRPhysiology {
        var p = MRPhysiology()
        p.lt1HR = MRInference(value: 150, confidence: .high, basis: [])
        return p
    }

    private func readiness(runs: [MRWorkout], nights: [(date: Date, value: Double)],
                           hardRunStarts: Set<Date> = []) -> MRReadiness? {
        mrReadinessAsOf(runs: runs, phys: phys, heatHR: MRHeatHRModel(), hrvNights: nights,
                        planPhase: nil, asOf: asOf, hardRunStarts: hardRunStarts)
    }

    @Test func runsAfterAsOfDoNotChangeResult() {
        let base = readiness(runs: pastRuns(), nights: nights(futureValue: 31))
        #expect(base != nil)
        // 그날 러닝(고강도)과 이후 며칠의 긴 러닝·낮은 HRV를 더해도 같은 판정
        var more = pastRuns()
        more.append(run(dayOffset: 0, minutes: 90, hr: 175))
        for d in 1...4 { more.append(run(dayOffset: d, minutes: 120, hr: 170)) }
        let hardFuture: Set<Date> = Set((0...4).map { day($0).addingTimeInterval(7 * 3600) })
        let after = readiness(runs: more, nights: nights(futureValue: 15), hardRunStarts: hardFuture)
        #expect(after == base)
    }

    @Test func sameDayRunAfterAsOfIsNotNil() {
        // 러닝 당일 asOf = 시작 − 1초 — 엔진의 "이미 뛴 날 nil"에 걸리지 않는다
        var runs = pastRuns()
        runs.append(run(dayOffset: 0))
        #expect(readiness(runs: runs, nights: nights(futureValue: 31)) != nil)
        // 거르지 않고 바로 부르면 nil(대조군)
        #expect(mrReadiness(runs: runs, phys: phys, heatHR: MRHeatHRModel(), hrvNights: nights(futureValue: 31),
                            planPhase: nil, asOf: runDayStart.addingTimeInterval(3600)) == nil)
    }
}
