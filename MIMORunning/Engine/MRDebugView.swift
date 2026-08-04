import SwiftUI
import HealthKit


struct MRDebugView: View {
    @State private var log = "권한 요청 대기 중"
    private let hk = MRHealthKit()

    var body: some View {
        ScrollView {
            Text(log)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .task {
            do {
                try await hk.requestAuthorization()
                let runs = try await hk.fetchRuns()
                let rhr = try await hk.fetchRestingHR()
                let outdoor = runs.filter { !$0.indoor }
                let withHR = runs.filter { $0.hrAvg != nil }
                let withTemp = runs.filter { $0.tempC != nil }
                let totalKm = runs.compactMap(\.distanceKm).reduce(0, +)

                let dob = hk.dateOfBirth()
                let sexRaw = hk.biologicalSex()
                let sex: MRSex = sexRaw == .female ? .female : (sexRaw == .male ? .male : .unknown)
                let phys = mrPhysiology(runs: runs, restingHRSamples: rhr,
                                        dateOfBirth: dob, sex: sex, asOf: Date())

                let heat = mrFitHeatModel(runs: runs)
                let hrp = mrFitHRPaceModel(runs: runs, asOf: Date())
                let easyPace = phys.easyCeilingHR.flatMap { hrp.paceAtHR($0) }

                let rawEfforts = mrDetectEfforts(runs: runs, phys: phys)
                let efforts = mrApplyHeat(rawEfforts, heat: heat)

                let fit = mrFitExponent(efforts)
                let prof = mrProfile(runs: runs, efforts: efforts, asOf: Date())
                let preds = mrPredict(efforts: efforts, fit: fit, profile: prof,
                                      heat: heat, asOf: Date())

                log = """
                러닝           \(runs.count) 건
                  실외          \(outdoor.count)
                  심박 있음     \(withHR.count)
                  기온 있음     \(withTemp.count)
                누적 거리       \(String(format: "%.0f", totalKm)) km
                첫 기록         \(runs.first?.date.formatted(date: .numeric, time: .omitted) ?? "-")
                마지막 기록     \(runs.last?.date.formatted(date: .numeric, time: .omitted) ?? "-")
                안정시심박      \(rhr.count) 건

                ── 생리
                나이            \(String(format: "%.1f", phys.age ?? 0)) 세
                HRmax           \(String(format: "%.0f", phys.hrMax?.value ?? 0)) bpm
                안정시심박      \(String(format: "%.0f", phys.restingHR?.value ?? 0)) bpm
                LT1             \(String(format: "%.0f", phys.lt1HR?.value ?? 0)) ± \(String(format: "%.0f", phys.lt1SD)) bpm
                이지 상한       \(String(format: "%.0f", phys.easyCeilingHR ?? 0)) bpm

                ── 더위 모델
                적합            \(heat.ok ? "성공" : "실패") · n=\(heat.n)
                 20°C           \(String(format: "%+.1f", heat.pct(20)))%
                 25°C           \(String(format: "%+.1f", heat.pct(25)))%
                 30°C           \(String(format: "%+.1f", heat.pct(30)))%

                ── 심박–페이스
                적합            \(hrp.ok ? hrp.tier : "실패") · n=\(hrp.n)
                이지 페이스     \(easyPace.map { mrFormatPace($0) + "/km" } ?? "-")
                """

                let intervalRuns = runs.filter(\.isInterval)
                log += "\n\n인터벌 인식  \(intervalRuns.count)건\n"
                for w in intervalRuns.suffix(5) {
                    log += String(format: "  %@  %.1fkm  %d분  %.0fbpm\n",
                                  w.date.formatted(date: .numeric, time: .omitted),
                                  w.distanceKm ?? 0, Int(w.durationMin), w.hrAvg ?? 0)
                }

                log += "\n── 대회급 노력 \(efforts.count)건\n"
                for e in efforts.suffix(12) {
                    log += String(format: "%@  %-5@ %6.2fkm  %@  (15°C환산 %@)\n",
                                  e.date.formatted(date: .numeric, time: .omitted),
                                  e.label, e.distanceM / 1000,
                                  mrFormatHMS(e.timeMin), mrFormatHMS(e.timeMinRef))
                }

                log += String(format: """

                ── 지수
                개인 지수       %.4f ± %.4f (n=%d, Sxx=%.3f)
                실측 마라톤     %@
                주간 거리       %.1f km · 최장 롱런 %.1f km · 완주 %d회

                ── 예상 기록
                """, fit.b, fit.bCI, fit.n, fit.sxx,
                     fit.measuredMarathonB.map { String(format: "%.4f", $0) } ?? "-",
                     prof.weeklyKm4w, prof.longestRun16wKm, prof.marathonFinishes)

                log += "\n"
                for p in preds {
                    log += "\(p.label)\t\(mrFormatHMS(p.midMin))  (\(mrFormatHMS(p.loMin))–\(mrFormatHMS(p.hiMin)))  \(p.confidence.label)\n"
                }

                func mrDate(_ s: String) -> Date {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    f.timeZone = .current
                    return f.date(from: s)!
                }
                var input = MRUserInputStore.load()
                if input.races.isEmpty {
                    input.races = [
                        MRTargetRace(date: mrDate("2026-08-30"), distanceM: 10000,
                                     name: "제3회 한강 서울 하프 마라톤",
                                     startTime: "08:00", place: "여의도 한강공원 물빛광장"),
                        MRTargetRace(date: mrDate("2026-09-20"), distanceM: 21097.5,
                                     name: "제19회 가평자라섬 전국마라톤",
                                     startTime: "08:30", place: "가평종합운동장"),
                        MRTargetRace(date: mrDate("2026-11-01"), distanceM: 42195,
                                     name: "2026 JTBC 마라톤",
                                     startTime: "08:00", place: "상암 월드컵공원 평화광장"),
                    ]
                    input.goals = MRGoals(tenKSec: 52*60+30, halfSec: 115*60, fullSec: 260*60)
                    MRUserInputStore.save(input)
                }
                let myRaces = input.upcomingRaces(asOf: Date())
                let halfEquiv = preds.first { $0.label == "하프" }!.midMin

                log += "\n── 대회 플랜\n"
                for r in myRaces {
                    guard let pl = mrBuildPlan(raceDate: r.date, distanceM: r.distanceM,
                                               today: Date(), profile: prof,
                                               halfEquivMin: halfEquiv,
                                               easyPaceSecPerKm: easyPace, heat: heat,
                                               raceTempC: MR_REF_TEMP,
                                               runsPerWeek: prof.runsPerWeek) else {
                        log += "\(r.name): 준비 기간 3주 미만\n"; continue
                    }
                    log += String(format: "%@ %d주\n  지금 %@ → 계획후 %@\n  롱런 %.1f/%.0fkm · %@\n",
                                  r.name, pl.weeks.count,
                                  mrFormatHMS(pl.projectedNow), mrFormatHMS(pl.projectedFinal),
                                  pl.reachableLongKm, pl.targetLongKm, pl.verdict)
                }

                let plans = myRaces.compactMap {
                    mrBuildPlan(raceDate: $0.date, distanceM: $0.distanceM, today: Date(),
                                profile: prof, halfEquivMin: halfEquiv,
                                easyPaceSecPerKm: easyPace, heat: heat,
                                raceTempC: MR_REF_TEMP,
                                runsPerWeek: prof.runsPerWeek)
                }
                let advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                                           gaps: [], strengthPerWeek: 0,
                                           log: MRAdviceLog(), asOf: Date())

                log += "\n── 목표끼리\n"
                for l in mrGoalLinks(input.goals) {
                    log += String(format: "%@  b=%.3f (%.2f–%.2f)  %@\n",
                                  l.name, l.b, l.lo, l.hi, l.note)
                }

                log += "\n── 목표 대비\n"
                for (r, pl) in zip(myRaces, plans) {
                    let c = mrCheckGoal(race: r, plan: pl, goals: input.goals,
                                        profile: prof, halfEquivMin: halfEquiv,
                                        heat: heat, raceTempC: MR_REF_TEMP)
                    guard let g = c.goalMin, let gap = c.gapMin else { continue }
                    log += String(format: "%@ [%@]\n  계획후 %@ · 목표 %@ · 차이 %+.1f분 (%+.1f%%)\n  %@\n",
                                  r.name, r.label,
                                  mrFormatDisplay(pl.projectedFinal), mrFormatDisplay(g),
                                  gap, gap / g * 100, c.verdict)
                    for lv in c.levers { log += "    · \(lv)\n" }
                }

                log += "\n── 조언 큐 \(advice.count)건\n"
                for (i, a) in advice.prefix(6).enumerated() {
                    log += String(format: "%d. [%@ %.1f] %@\n   %@\n", i+1, a.grade, a.score, a.text, a.rationale)
                }

                if let c = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                       raceDayCardVisible: false,
                                       advice: advice, asOf: Date()) {
                    log += """

                    ── 오늘의 러닝 카드
                    \(c.streakLine)
                    \(c.cumulativeLine)

                    \(c.sessionLine ?? "(쉬는 날 — 이번 주 러닝 없음)")
                    \(c.linkLine ?? "")
                    """
                }
            } catch {
                log = "실패: \(error.localizedDescription)"
            }
        }
    }
}
