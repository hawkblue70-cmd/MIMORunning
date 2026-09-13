import Testing
import Foundation
@testable import MIMORunning

/// `RunSummaryBuilder` 배선 검증 — 리듬 카드가 하던 ~15개 입력 조립을 이 빌더 하나로 옮긴 뒤에도
/// 같은 러닝이 같은 총평 5줄을 내는지 확인한다. 세부 문구는 `RunSummaryTests`가 이미 촘촘히 검사하므로
/// 여기서는 축 순서·핵심 근거 한둘만 재확인한다.
@Suite("RunSummaryBuilder 조립", .serialized)
@MainActor
struct RunSummaryBuilderTests {

    private func split(_ id: Int) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: 375,
                  avgHeartRate: 150, avgCadence: 175, avgPower: nil,
                  avgGroundContactTime: 255, avgStrideLength: 0.92, avgVerticalOscillation: 8.4)
    }

    private func makeEasyDetail(cadence: Int, stride: Double, gct: Double, vo: Double) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 20,
                       avgPower: nil, avgCadence: cadence, splits: [], hrZones: [],
                       intervalSegments: [], workoutType: .easy,
                       avgGroundContactTime: gct, avgStrideLength: stride,
                       avgVerticalOscillation: vo, vo2Max: nil,
                       altitudeProfile: [], altitudeTimeProfile: [])
    }

    /// 오늘 러닝(16km 375초/km 페이스)이 속할 밴드를 담은 기준선 — `FormReferenceBandTests.easyOnlyBaseline()`과
    /// 같은 방식(`FormBaselineEngine.compute(from:)`)으로 만들되, 페이스 대역을 오늘 러닝(375초/km) 쪽으로 맞춘다.
    private func baseline(asOf today: Date) -> RunningFormBaseline {
        let cal = Calendar.current
        var inputs: [FormInput] = []
        for i in 1...30 {
            let d = cal.date(byAdding: .day, value: -(4 + i * 3), to: today)!
            let paceSec = 360.0 + Double((i * 7) % 31)   // 360~390초/km — 오늘 러닝(375초/km)을 감싼다
            let act = Activity(id: UUID(), type: .running, date: d,
                                duration: paceSec * 7.5, distance: 7500,
                                calories: 550, avgHeartRate: 146, temperatureC: 15)
            let det = makeEasyDetail(cadence: 172 + ((i * 3) % 7),
                                     stride: 0.89 + Double((i * 5) % 9) * 0.01,
                                     gct: 250 + Double((i * 11) % 13),
                                     vo: 8.1 + Double((i * 4) % 7) * 0.06)
            if let fi = FormInput(activity: act, detail: det) { inputs.append(fi) }
        }
        return FormBaselineEngine.compute(from: inputs)
    }

    /// 과거 30회 이지런(15°C·146bpm, 90일에 걸쳐) + 직전 3일 연속 러닝 — 오늘까지 "4일 연속"을 만든다.
    private func history(activity: Activity, today: Date) -> [Activity] {
        let cal = Calendar.current
        var runs: [Activity] = [activity]
        for i in 1...30 {
            let d = cal.date(byAdding: .day, value: -(4 + i * 3), to: today)!
            runs.append(Activity(id: UUID(), type: .running, date: d, duration: 375.0 * 7.5,
                                  distance: 7500, calories: 550, avgHeartRate: 146, temperatureC: 15))
        }
        for dayOffset in 1...3 {
            let d = cal.date(byAdding: .day, value: -dayOffset, to: today)!
            runs.append(Activity(id: UUID(), type: .running, date: d, duration: 375.0 * 7.5,
                                  distance: 7500, calories: 550, avgHeartRate: 146, temperatureC: 15))
        }
        return runs
    }

    private func makeContext() -> RunSummaryBuilder.Context {
        AppLanguage.shared.isEnglish = false
        let today = Date()
        let activity = Activity(id: UUID(), type: .running, date: today,
                                 duration: 6041, distance: 16_000, calories: 900,
                                 avgHeartRate: 149, temperatureC: 25)
        let detail = ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 40,
                                    avgPower: nil, avgCadence: 175, splits: (1...16).map(split),
                                    hrZones: [], intervalSegments: [], workoutType: .distanceRun,
                                    avgGroundContactTime: 255, avgStrideLength: 0.92,
                                    avgVerticalOscillation: 8.4, vo2Max: 45.4,
                                    altitudeProfile: [], altitudeTimeProfile: [])
        let hrZones: [HRZoneData] = [
            HRZoneData(id: 2, name: "Zone 2", minBPM: 120, maxBPM: 139, seconds: 604, fraction: 0.10),
            HRZoneData(id: 3, name: "Zone 3", minBPM: 140, maxBPM: 154, seconds: 1208, fraction: 0.20),
            HRZoneData(id: 4, name: "Zone 4", minBPM: 155, maxBPM: 169, seconds: 3745, fraction: 0.62),
            HRZoneData(id: 5, name: "Zone 5", minBPM: 170, maxBPM: 200, seconds: 484, fraction: 0.08),
        ]
        let hrSamples: [(offset: TimeInterval, bpm: Int)] = (0..<600).map { i in
            let t = Double(i) / 599.0
            let bpm = Int((140.0 + t * (157.0 - 140.0)).rounded())
            return (offset: Double(i) * (6041.0 / 599.0), bpm: bpm)
        }
        var heatModel = MRHeatHRModel()
        heatModel.ok = true
        heatModel.bpmPerC = 0.8
        heatModel.tempMaxC = 25

        return RunSummaryBuilder.Context(
            activity: activity, detail: detail, history: history(activity: activity, today: today),
            hrZones: hrZones, hrSamples: hrSamples,
            formBaseline: baseline(asOf: today), formShifts: [],
            workoutType: .distanceRun, workoutTypeFn: nil,
            effortIndex: nil, heatHRModel: heatModel,
            age: 55, isMale: true, easyPaceLookup: nil,
            planPhase: nil, raceDetailFn: nil, hrZonesFn: nil
        )
    }

    @Test func fiveAxesInOrderWithHeatAndStreakEvidence() {
        let lines = RunSummaryBuilder.lines(makeContext())
        #expect(lines.map(\.axis) == ["러닝폼", "거리 적응", "심박", "훈련부하", "유산소"])
        let hr = lines[2]
        #expect(hr.evidence?.contains("25°C(더위 +8)") == true)
        let load = lines[3]
        #expect(load.state.contains("4일 연속"))
    }
}
