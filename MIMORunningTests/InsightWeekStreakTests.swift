import Testing
import Foundation
@testable import MIMORunning

/// "N주 연속" — 홈(월요일 시작 ISO 주)과 같은 주 경계를 쓰는가
@MainActor
@Suite("주 연속 — 월요일 시작 주", .korean)
struct InsightWeekStreakTests {
    private func run(_ y: Int, _ m: Int, _ d: Int, id: UUID = UUID()) -> Activity {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 19
        let date = Calendar(identifier: .gregorian).date(from: c)!
        return Activity(id: id, type: .running, date: date, duration: 2400, distance: 6_000,
                        calories: nil, avgHeartRate: 135, temperatureC: 22, humidityPercent: nil)
    }

    @Test func sundayRunKeepsMondayWeekStreak() {
        // 오늘 = 2026-09-20(일). 앞 14주는 매주 수요일에 뛰었는데, 7/6(월)~7/12(일) 주만 일요일(7/12)에 뛰었다.
        // 월요일 시작 주로는 끊김이 없다(15주). 일요일 시작 주로 자르면 7/5~7/11 주가 비어 11주에서 끊겼다.
        let today = run(2026, 9, 20)
        var prior: [Activity] = []
        let cal = InsightEngine.weekCalendar
        let thisMonday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today.date))!
        for k in 1...14 {
            let monday = cal.date(byAdding: .weekOfYear, value: -k, to: thisMonday)!
            let comps = cal.dateComponents([.year, .month, .day], from: monday)
            if comps.month == 7 && comps.day == 6 {
                prior.append(run(2026, 7, 12))                       // 그 주의 일요일
            } else {
                let wed = cal.date(byAdding: .day, value: 2, to: monday)!
                let w = cal.dateComponents([.year, .month, .day], from: wed)
                prior.append(run(w.year!, w.month!, w.day!))
            }
        }
        let r = InsightEngine.consistent(today, prior)
        #expect(r?.detail == "15주 연속 러닝")
    }
}
