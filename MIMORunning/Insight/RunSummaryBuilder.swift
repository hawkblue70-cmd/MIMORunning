import Foundation

/// 총평 5줄의 입력 조립 — 리듬 카드와 공유 카드가 **이 함수 하나만** 쓴다(§5.8: 같은 러닝은 어디서나 같은 문장).
enum RunSummaryBuilder {
    struct Context {
        let activity: Activity
        let detail: ActivityDetail?
        let history: [Activity]
        let hrZones: [HRZoneData]
        let hrSamples: [(offset: TimeInterval, bpm: Int)]
        let formBaseline: RunningFormBaseline?
        let formShifts: [MRFormShift]
        let workoutType: WorkoutType
        let workoutTypeFn: ((UUID) -> WorkoutType?)?
        let effortIndex: EffortIndex?
        let heatHRModel: MRHeatHRModel?
        let age: Int?
        let isMale: Bool?
        let easyPaceLookup: MRHRPaceLookup?
        let planPhase: String?
        let raceDetailFn: ((UUID) -> ActivityDetail?)?
        let hrZonesFn: ((UUID) -> [HRZoneData]?)?
        /// 수면 HRV 밤별 중앙값(엔진 스토어 `hrvNights`). 비어 있으면 HRV 문장·근거 모두 빠진다.
        var hrvNights: [(date: Date, value: Double)] = []
    }

    /// 총평 줄 — 각 축의 결론은 해당 엔진에서 그대로 받는다. 2줄 미만일 때의 한 줄 칩 폴백은 호출부(카드) 몫.
    static func lines(_ c: Context) -> [RunSummaryLine] {
        RunSummary.lines(input(c))
    }

    /// 직전 4주간 러닝 1회 평균 거리(km). 거리 문맥 판단(장거리 여부·거리 적응 근거)에 쓴다.
    /// 리듬 카드 body·oneLiner도 이 헬퍼 하나만 쓴다.
    static func typicalRunDistanceKm(activity: Activity, history: [Activity]) -> Double? {
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: activity.date) ?? .distantPast
        let recent = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= fourWeeksAgo && $0.date < activity.date
        }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0.0) { $0 + $1.distance } / Double(recent.count) / 1000.0
    }

    /// 최근 N회 중 이 거리의 순위 — 거리 문맥 원라이너·총평 거리 적응 근거가 공유.
    static func distanceRankInfo(activity: Activity, history: [Activity]) -> (rank: Int, sampleCount: Int)? {
        let recent = history
            .filter { $0.type == .running && $0.id != activity.id && $0.date < activity.date }
            .sorted { $0.date > $1.date }
        let sample = (Array(recent.prefix(9)) + [activity]).sorted { $0.distance > $1.distance }
        guard sample.count >= 5 else { return nil }
        guard let rank = sample.firstIndex(where: { $0.id == activity.id }).map({ $0 + 1 }) else { return nil }
        return (rank, sample.count)
    }

    private static func vo2Info(detail: ActivityDetail?, age: Int?, isMale: Bool?) -> RunInsightEngine.VO2FitnessInfo? {
        guard let vo2 = detail?.vo2Max, let a = age else { return nil }
        return RunInsightEngine.vo2FitnessInfo(vo2: vo2, age: a, isMale: isMale)
    }

    /// 고강도 러닝인가 — 체감 강도 7 이상 · 계획된 고강도 유형 · 존 4+5 비율 50% 이상 중 하나.
    /// 싼 검사부터: 체감 강도(딕셔너리) → 계획 유형(UserDefaults) → 존 분포(디스크 조회 가능) 순으로 단락평가.
    static func isHardRun(_ run: Activity, effortIndex: EffortIndex?,
                          workoutTypeFn: ((UUID) -> WorkoutType?)?,
                          hrZonesFn: ((UUID) -> [HRZoneData]?)?) -> Bool {
        if (effortIndex?.resolve(run.id)?.value ?? 0) >= 7 { return true }
        if workoutTypeFn?(run.id).map(FormNarrative.isPlannedHighIntensity) == true { return true }
        guard let zones = hrZonesFn?(run.id) else { return false }
        let total = zones.map(\.fraction).reduce(0, +)
        guard total > 0 else { return false }
        let highFrac = zones.filter { $0.id >= 4 }.map(\.fraction).reduce(0, +) / total
        return highFrac >= 0.5
    }

    /// 마지막 고강도 러닝까지의 일수. 28일 안에 없으면 nil — 총평 훈련부하 줄이 그 근거를 생략한다.
    private static func daysSinceHardRun(activity: Activity, history: [Activity],
                                        effortIndex: EffortIndex?,
                                        workoutTypeFn: ((UUID) -> WorkoutType?)?,
                                        hrZonesFn: ((UUID) -> [HRZoneData]?)?) -> Int? {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -28, to: activity.date) ?? .distantPast
        let priorRuns = history
            .filter { $0.type == .running && $0.date < activity.date && $0.date >= since }
            .sorted { $0.date > $1.date }
        for run in priorRuns where isHardRun(run, effortIndex: effortIndex, workoutTypeFn: workoutTypeFn, hrZonesFn: hrZonesFn) {
            return cal.dateComponents([.day], from: cal.startOfDay(for: run.date), to: cal.startOfDay(for: activity.date)).day
        }
        return nil
    }

    /// 이 러닝 직전 14일(이 러닝 제외) 고강도 러닝 수 / 러닝 수 — 총평 HRV 결합 문장의 이지 블록 판정.
    static func hardRunsLast14(activity: Activity, history: [Activity],
                               effortIndex: EffortIndex?,
                               workoutTypeFn: ((UUID) -> WorkoutType?)?,
                               hrZonesFn: ((UUID) -> [HRZoneData]?)?) -> (hard: Int, total: Int) {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: activity.date)) ?? .distantPast
        let runs = history.filter { $0.type == .running && $0.id != activity.id && $0.date < activity.date && $0.date >= since }
        let hard = runs.filter { isHardRun($0, effortIndex: effortIndex, workoutTypeFn: workoutTypeFn, hrZonesFn: hrZonesFn) }.count
        return (hard, runs.count)
    }

    /// 8주 전(±1주) 러닝들의 VO2max 중앙값 — 총평 유산소 줄의 "8주 전 대비" 근거.
    private static func vo2EightWeeksAgo(activity: Activity, history: [Activity],
                                         raceDetailFn: ((UUID) -> ActivityDetail?)?) -> Double? {
        guard let raceDetailFn else { return nil }
        let cal = Calendar.current
        guard let lower = cal.date(byAdding: .day, value: -63, to: activity.date),
              let upper = cal.date(byAdding: .day, value: -49, to: activity.date) else { return nil }
        let values = history
            .filter { $0.type == .running && $0.date >= lower && $0.date <= upper }
            .compactMap { raceDetailFn($0.id)?.vo2Max }
            .sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        if values.count % 2 == 0 { return (values[mid - 1] + values[mid]) / 2 }
        return values[mid]
    }

    /// 총평 입력 조립 — 테스트·디버그용으로도 공개.
    static func input(_ c: Context) -> RunSummaryInput {
        var input = RunSummaryInput()
        input.form = {
            guard let det = c.detail else { return nil }
            return FormPhase.result(splits: det.splits, altitudeProfile: det.altitudeProfile,
                                    baseline: c.formBaseline, formShifts: c.formShifts, workoutType: c.workoutType)
        }()
        input.distKm = c.activity.distance / 1000
        let typicalKm = typicalRunDistanceKm(activity: c.activity, history: c.history)
        input.typicalKm = typicalKm
        input.workoutType = c.workoutType
        input.isLongDistanceContext = isLongDistanceRunContext(activity: c.activity, workoutType: c.workoutType,
                                                                recentAvgDistanceKm: typicalKm)
        input.zoneFractions = Dictionary(c.hrZones.map { ($0.id, $0.fraction) }, uniquingKeysWith: { a, _ in a })
        let hrTotalFrac = c.hrZones.map(\.fraction).reduce(0, +)
        let highZoneFrac = hrTotalFrac > 0 ? c.hrZones.filter { $0.id >= 4 }.map(\.fraction).reduce(0, +) / hrTotalFrac : 0
        input.todayIsHard = FormNarrative.isPlannedHighIntensity(c.workoutType)
            || highZoneFrac >= 0.5
            || (c.effortIndex?.resolve(c.activity.id)?.value ?? 0) >= 7
        if let idx = c.effortIndex {
            let runs = effortLoadRuns(activity: c.activity, history: c.history, index: idx).runs
            input.weekOverWeek = EffortLoad.rollingWeekOverWeek(runs: runs, asOf: c.activity.date)
            input.acuteChronic = EffortLoad.rollingAcuteChronic(runs: runs, asOf: c.activity.date)?.label
            // 같은 러닝 목록으로 하루 전 창의 라벨 — 36일 창이 어제 기준 7+28일을 덮는다
            input.acuteChronicYesterday = EffortLoad.rollingAcuteChronicYesterday(runs: runs, asOf: c.activity.date)?.label
            input.loadSentence = EffortLoad.rollingSentenceKind(runs: runs, asOf: c.activity.date)
            if let au = sevenDayAU(runs: runs, asOf: c.activity.date) {
                input.sevenDayAU = au.current
                input.previousSevenAU = au.previous
            }
            // 이 러닝의 강도가 아직 없으면 위 합계에 오늘이 0으로 들어가 있다 — 상태어가 그 사실을 말하게 한다
            input.todayEffortMissing = idx.resolve(c.activity.id) == nil
        }
        input.streakDays = computeRunningStreak(activity: c.activity, history: c.history)
        if let fi = vo2Info(detail: c.detail, age: c.age, isMale: c.isMale), let v = c.detail?.vo2Max {
            input.vo2 = v
            input.vo2AgeDecade = fi.ageDecade
            input.vo2GenderLabel = fi.genderLabel
            input.vo2EightWeeksAgo = vo2EightWeeksAgo(activity: c.activity, history: c.history, raceDetailFn: c.raceDetailFn)
        }
        input.heatDeltaBpm = c.heatHRModel?.delta(c.activity.temperatureC)

        if let info = distanceRankInfo(activity: c.activity, history: c.history) {
            input.distanceRank = info.rank
            input.distanceSampleCount = info.sampleCount
        }
        input.avgHeartRate = c.activity.avgHeartRate
        // 차트 축 라벨(평활화 최고)과 같은 값 — 원본 최고를 쓰면 카드 안에서 157 vs 159처럼 어긋난다
        input.peakHeartRate = c.hrSamples.count >= 5 ? hrChartSmoothed(c.hrSamples.map(\.bpm)).max().map { Int($0.rounded()) } : nil
        input.temperatureC = c.activity.temperatureC
        input.planPhase = c.planPhase
        input.easyPace = c.easyPaceLookup
        // daysSinceHardRun 계산(과거 최대 28일 스캔)은 loadNext가 실제로 쓸 수 있을 때만 —
        // 회복/테이퍼 주거나 이미 4주 평균 대비 높음·단조·4일+ 연속으로 다음 행동이 정해지면 "충분히 회복" 분기에 도달하지 않는다.
        // (급증 판정은 RunSummary.loadLine과 같이 acuteChronic만 본다 — 최근 7일 증감은 근거 숫자일 뿐)
        let jumped = input.acuteChronic == .high || input.acuteChronic == .veryHigh
        if (input.acuteChronic != nil || input.sevenDayAU != nil),
           input.planPhase != "회복", input.planPhase != "테이퍼",
           !jumped, input.loadSentence != .monotony, input.streakDays < 4 {
            input.daysSinceHardRun = daysSinceHardRun(activity: c.activity, history: c.history,
                                                       effortIndex: c.effortIndex,
                                                       workoutTypeFn: c.workoutTypeFn,
                                                       hrZonesFn: c.hrZonesFn)
        }
        // 수면 HRV 추세는 러닝 날짜 기준(오래된 러닝을 열어도 당시 상태). 추세가 있을 때만 14일 고강도를 센다(존 분포 조회 비용).
        if !c.hrvNights.isEmpty, let t = mrHRVTrend(nights: c.hrvNights, asOf: c.activity.date) {
            input.hrvTrend = t
            // 아침 제안과 같은 밤 — 러닝 날짜 키(전날 15시~당일 12시 창)
            input.lastNightHRV = c.hrvNights.last(where: { Calendar.current.isDate($0.date, inSameDayAs: c.activity.date) })?.value
            let h = hardRunsLast14(activity: c.activity, history: c.history,
                                   effortIndex: c.effortIndex, workoutTypeFn: c.workoutTypeFn, hrZonesFn: c.hrZonesFn)
            input.hardRunsLast14 = h.hard
            input.runsLast14 = h.total
        }
        return input
    }
}

/// 부하 계산용 러닝 목록 — 이 러닝 날짜로 끝나는 36일 창(이 러닝 포함). 리듬·퍼포먼스 카드가 **이 함수 하나만** 쓴다.
func effortLoadRuns(activity: Activity, history: [Activity], index: EffortIndex)
    -> (runs: [EffortLoad.Run], acts: [Activity], dayEnd: Date) {
    let cal = Calendar.current
    let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: activity.date)) ?? activity.date
    let since = cal.date(byAdding: .day, value: -36, to: activity.date) ?? .distantPast
    var acts = history.filter { $0.date >= since && $0.date < dayEnd }
    // history가 이 러닝을 포함하지 않는 호출부에서도 이 러닝이 창에 들어가야 한다.
    if !acts.contains(where: { $0.id == activity.id }) { acts.append(activity) }
    return (EffortLoad.runs(from: acts, index: index), acts, dayEnd)
}

/// 최근 7일 AU 합계와 그 직전 7일 합계 — 리듬 카드 총평·퍼포먼스 카드 강도 부하가 공유.
/// 강도 기록이 없으면(이 창에 커버된 러닝이 하나도 없으면) nil.
/// `runs`를 이미 만든 호출부는 이 오버로드로 재계산을 피한다.
func sevenDayAU(runs: [EffortLoad.Run], asOf: Date) -> (current: Double, previous: Double)? {
    let w = EffortLoad.lastSevenDays(runs: runs, asOf: asOf)
    guard w.coveredCount > 0 else { return nil }
    let previous = EffortLoad.previousSevenDays(runs: runs, asOf: asOf).total
    return (w.total, previous)
}

func sevenDayAU(activity: Activity, history: [Activity], index: EffortIndex) -> (current: Double, previous: Double)? {
    let runs = effortLoadRuns(activity: activity, history: history, index: index).runs
    return sevenDayAU(runs: runs, asOf: activity.date)
}
