import Foundation

// MARK: - 공백

struct MRGap: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let days: Int
    let cause: String        // 부상 의심 / 질병·여행 의심 / 동기 저하
    let preSpike: Bool
    let stepsDropped: Bool
}

/// 21일 이상 공백을 찾고 **원인을 분류**한다.
///
/// 원인 판별의 핵심은 **걸음 수**다:
///   · 공백 직전 4주에 단일 세션 급증(직전 30일 최장의 1.2배 초과)이 있었다 → 부상 의심
///   · 공백 동안 일상 걸음 수가 평소의 75% 아래로 떨어졌다 → 질병·여행 의심
///   · 둘 다 아니다 → 동기 저하
///
/// 부상이면 걷는 것도 줄어들 것 같지만, 러닝 부상은 걷기까지 막지는 않는
/// 경우가 많다. 반대로 감기나 여행은 걸음 수가 확실히 떨어진다.
/// 그래서 **걸음 수 유지 여부가 두 원인을 가르는 신호**가 된다.
///
/// ⚠ 사용자에게 "왜 쉬었냐"고 묻지 않는다. 이 앱의 원칙이다.
func mrDetectGaps(runs: [MRWorkout],
                  stepsDaily: [Date: Double],
                  minDays: Int = 21) -> [MRGap] {
    guard runs.count >= 2 else { return [] }
    let cal = Calendar.current
    func days(_ a: Date, _ b: Date) -> Int {
        cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    var out: [MRGap] = []
    for i in 0..<(runs.count - 1) {
        let a = runs[i], b = runs[i + 1]
        let gap = days(a.date, b.date)
        guard gap >= minDays else { continue }

        // 공백 직전 4주에 단일 세션 스파이크가 있었나
        let window = runs.filter {
            let d = days($0.date, a.date); return d >= 0 && d < 28 && $0.distanceKm != nil
        }
        let longestBefore = runs.filter {
            let d = days($0.date, a.date); return d >= 28 && d < 58
        }.compactMap(\.distanceKm).max() ?? 0
        let preSpike = longestBefore > 0 &&
            window.contains { ($0.distanceKm ?? 0) > 1.2 * longestBefore }

        // 공백 동안 일상 걸음 수가 떨어졌나
        let base = stepsDaily.filter { let d = days($0.key, a.date); return d > 0 && d <= 60 }
                             .map(\.value)
        let during = stepsDaily.filter { $0.key > a.date && $0.key < b.date }.map(\.value)
        var dropped = false
        if base.count >= 15 && during.count >= 7 {
            dropped = mrMedian(during) < 0.75 * mrMedian(base)
        }

        let cause = preSpike ? "부상 의심" : (dropped ? "질병·여행 의심" : "동기 저하")
        out.append(MRGap(start: a.date, end: b.date, days: gap, cause: cause,
                         preSpike: preSpike, stepsDropped: dropped))
    }
    return out
}

// MARK: - 경력 · 레벨 · 모드

struct MRProfileFull {
    var weeklyKm4w = 0.0
    var sessionsPerWeek4w = 0.0
    var longestRun30d = 0.0
    var longestRun16wKm = 0.0
    var marathonFinishes = 0
    var runsPerWeek = 0.0

    var trainingAgeYears: MRInference?
    var level = "초보"           // 초보 / 하수 / 중수 / 고수 / 신
    var mode = "hybrid"          // performance / hybrid / health
    var modeScore = 0
    var modeReasons: [String] = []
}

func mrProfileFull(runs: [MRWorkout],
                   efforts: [MRRaceEffort],
                   firstDataDate: Date?,
                   dateOfBirth: Date?,
                   hasGoalTime: Bool,
                   hasGoalRace: Bool,
                   asOf: Date) -> MRProfileFull {

    var p = MRProfileFull()
    let cal = Calendar.current
    func ago(_ d: Date) -> Int { cal.dateComponents([.day], from: d, to: cal.startOfDay(for: asOf)).day ?? -1 }

    // ★ 날짜 필터에 하한을 반드시 넣는다
    let last28 = runs.filter { let d = ago($0.date); return d >= 0 && d < 28 }
    p.weeklyKm4w = last28.compactMap(\.distanceKm).reduce(0, +) / 4.0
    p.sessionsPerWeek4w = Double(last28.count) / 4.0
    p.runsPerWeek = p.sessionsPerWeek4w
    p.longestRun30d = runs.filter { let d = ago($0.date); return d >= 0 && d < 30 }
                          .compactMap(\.distanceKm).max() ?? 0
    let w16 = runs.filter { let d = ago($0.date); return d >= 0 && d < 112 }
    p.longestRun16wKm = w16.compactMap(\.distanceKm).max() ?? 0
    p.marathonFinishes = efforts.filter { $0.distanceM >= 40_000 }.count

    // ── 경력 — 러닝이 1회 이상 있는 달의 수 / 12
    //
    // ⚠ "첫 러닝부터 지금까지"로 세면 데니처럼 29개월 공백이 있을 때
    //   실제 경력의 두 배 가까이 나온다.
    //   "공백 N일 이상을 뺀다"는 방식은 N이 근거 없는 임의값이 된다.
    //   달 단위로 세면 문턱 없이 공백을 정확히 제거한다.
    //   기기 구매일 함정도 자연스럽게 피해간다 — 뛴 달만 세니까.
    //   (firstDataDate 파라미터는 하위 호환을 위해 남겨두되 더 이상 쓰지 않는다)
    let mdf = DateFormatter(); mdf.dateFormat = "yyyy-MM"
    let activeMonthSet: Set<String> = Set(runs.compactMap { w -> String? in
        let c = cal.dateComponents([.year, .month], from: w.date)
        guard let y = c.year, let m = c.month else { return nil }
        return "\(y)-\(String(format: "%02d", m))"
    })
    if !activeMonthSet.isEmpty {
        let nActive = activeMonthSet.count
        let years   = Double(nActive) / 12.0
        p.trainingAgeYears = MRInference(
            value: years, confidence: .high,
            basis: ["러닝 기록이 있는 달 \(nActive)개월 기준"])

        #if DEBUG
        // 첫 활성 달 ~ 현재까지 모든 달 생성
        let sortedActive = activeMonthSet.sorted()
        let firstM = sortedActive.first!
        var allMonths: [String] = []
        if let startDate = mdf.date(from: firstM),
           let endComp  = cal.date(from: cal.dateComponents([.year, .month], from: asOf)) {
            var cur = startDate
            while cur <= endComp {
                allMonths.append(mdf.string(from: cur))
                cur = cal.date(byAdding: .month, value: 1, to: cur)!
            }
        }
        let totalMonths = allMonths.count

        // 연속 공백 구간 찾기
        let sortedInactive = allMonths.filter { !activeMonthSet.contains($0) }
        var gapRanges: [(from: String, to: String, count: Int)] = []
        if !sortedInactive.isEmpty {
            var gs = sortedInactive[0], ge = sortedInactive[0], gc = 1
            for i in 1..<sortedInactive.count {
                let prev = sortedInactive[i - 1]
                let expected = mdf.date(from: prev).flatMap {
                    cal.date(byAdding: .month, value: 1, to: $0)
                }.map { mdf.string(from: $0) }
                if expected == sortedInactive[i] { ge = sortedInactive[i]; gc += 1 }
                else { gapRanges.append((gs, ge, gc)); gs = sortedInactive[i]; ge = gs; gc = 1 }
            }
            gapRanges.append((gs, ge, gc))
        }

        print(String(format: "[추론] 경력 — 전체 %d개월 · 러닝 있는 달 %d개월 → %.2f년",
                     totalMonths, nActive, years))
        let sigGaps = gapRanges.filter { $0.count >= 2 }
        if !sigGaps.isEmpty {
            let parts = sigGaps.map { "\($0.from) ~ \($0.to) (\($0.count)개월)" }
            print("[추론] 러닝 없는 달: \(parts.joined(separator: " · "))")
        }
        #endif
    }

    // ── 모드 점수
    //
    // 기록형인지 건강형인지를 **행동으로** 판정한다. 묻지 않는다.
    // 목표 입력은 강한 신호지만(각 +2), 그것만으로 정해지지 않는다.
    var s = 0
    var why: [String] = []
    let recentEff = efforts.filter { let d = ago($0.date); return d >= 0 && d < 365 }
    if !recentEff.isEmpty { s += 2; why.append("최근 1년 대회급 노력 \(recentEff.count)회 (+2)") }
    if hasGoalTime { s += 2; why.append("목표 시간 입력 (+2)") }
    if hasGoalRace { s += 2; why.append("목표 대회 입력 (+2)") }
    if p.weeklyKm4w >= 30 { s += 1; why.append(String(format: "주 %.0fkm (+1)", p.weeklyKm4w)) }
    if p.sessionsPerWeek4w >= 4 { s += 1; why.append(String(format: "주 %.1f회 (+1)", p.sessionsPerWeek4w)) }
    if p.longestRun30d >= 15 { s += 1; why.append(String(format: "최장 롱런 %.0fkm (+1)", p.longestRun30d)) }

    // 세션 간 페이스 변주 — 기록형은 빠른 날과 느린 날을 나눈다
    let paces = runs.filter { let d = ago($0.date); return d >= 0 && d < 84 }
                    .compactMap(\.paceSecPerKm)
    if paces.count >= 6 {
        let m = paces.reduce(0, +) / Double(paces.count)
        let sd = (paces.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(paces.count)).squareRoot()
        let cv = sd / m
        if cv > 0.08 { s += 1; why.append(String(format: "세션 간 페이스 변주 CV %.0f%% (+1)", cv*100)) }
        else if cv < 0.03 { s -= 1; why.append(String(format: "늘 같은 속도 CV %.0f%% (−1)", cv*100)) }
    }

    if let dob = dateOfBirth {
        let age = Double(cal.dateComponents([.day], from: dob, to: asOf).day ?? 0) / 365.25
        if age >= 55 { s -= 1; why.append(String(format: "%.0f세 (−1)", age)) }
    }
    if p.weeklyKm4w < 15 { s -= 1; why.append(String(format: "주 %.0fkm (−1)", p.weeklyKm4w)) }
    if p.sessionsPerWeek4w < 2 { s -= 2; why.append(String(format: "주 %.1f회 (−2)", p.sessionsPerWeek4w)) }

    p.modeScore = s
    p.modeReasons = why
    p.mode = s >= 4 ? "performance" : (s <= 0 ? "health" : "hybrid")

    // ── 레벨 (노출량만. **목표는 절대 반영하지 않는다**)
    //
    // ⚠ AND 조건으로 판정하면 한 축만 걸려도 등급이 떨어져
    //   계절 하나에 레벨이 출렁인다(여름에 거리가 줄면 강등된다).
    //   → 3개 기준 중 **2개 이상** 충족. 창도 4주가 아니라 12주.
    let last84 = runs.filter { let d = ago($0.date); return d >= 0 && d < 84 }
    let km12 = last84.compactMap(\.distanceKm).reduce(0, +) / 12.0
    let ses12 = Double(last84.count) / 12.0
    let ta = p.trainingAgeYears?.value ?? 0

    let tiers: [(String, Double, Double, Double)] = [
        ("신",   70, 5.0, 5.0),
        ("고수", 40, 4.0, 2.0),
        ("중수", 20, 3.0, 1.0),
        ("하수", 10, 2.0, 0.25),
    ]
    p.level = "초보"
    for (name, kmin, smin, tmin) in tiers {
        let met = (km12 >= kmin ? 1 : 0) + (ses12 >= smin ? 1 : 0) + (ta >= tmin ? 1 : 0)
        if met >= 2 { p.level = name; break }
    }
    return p
}

// MARK: - 날짜 포맷 헬퍼

func mrYMD(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

// MARK: - 건강 지표 스냅샷

struct MRHealthMetrics {
    var habitDays: [Int] = []         // 요일(1=일…7=토), 빈도 높은 순 상위 3개
    var typicalHour: Int? = nil       // 주로 달리는 시각 (0–23)
    var days30: Int = 0               // 최근 30일 중 러닝한 날 수
    var minutesPerWeek: Double = 0    // 최근 4주 평균 분/주
    var sessions90: Int = 0           // 최근 90일 세션 수
    var km90: Double = 0              // 최근 90일 거리(km)
    var sessions90LY: Int = 0         // 작년 같은 90일 세션 수
    var km90LY: Double = 0            // 작년 같은 90일 거리(km)
    var restingHR: Double? = nil      // 최근 90일 안정시 심박 중앙값
    var restingHRLY: Double? = nil    // 작년 같은 90일 안정시 심박 중앙값
    var vo2max: Double? = nil         // 가장 최근 VO2max (ml/kg/min)
    var vo2maxLY: Double? = nil       // 작년 같은 기간 마지막 VO2max
}

/// 러닝 습관·심폐 추세를 한 곳에 모은 스냅샷.
///
/// ⚠ "작년 같은 90일"은 `asOf-365 … asOf-275` 창이다.
///   365일 전 같은 날부터 90일치 — 연간 계절 효과를 잡는다.
func mrHealthMetrics(runs: [MRWorkout],
                     restingHRSamples: [(date: Date, value: Double)],
                     vo2Samples: [(date: Date, value: Double)],
                     stepsDaily: [Date: Double],
                     asOf: Date) -> MRHealthMetrics {
    var m = MRHealthMetrics()
    let cal = Calendar.current
    func daysAgo(_ d: Date) -> Int {
        cal.dateComponents([.day], from: d, to: cal.startOfDay(for: asOf)).day ?? -1
    }

    // 창 정의
    let last90  = runs.filter { let d = daysAgo($0.date); return d >= 0 && d < 90 }
    let last28  = runs.filter { let d = daysAgo($0.date); return d >= 0 && d < 28 }
    let last30d = runs.filter { let d = daysAgo($0.date); return d >= 0 && d < 30 }
    let lyLo    = 365, lyHi = 365 + 90
    let ly90    = runs.filter { let d = daysAgo($0.date); return d >= lyLo && d < lyHi }

    // 습관 — 요일 빈도
    //
    // ⚠ 요일이 고른 사람에게 억지로 습관 요일을 뽑으면
    //   없는 패턴을 만들어 보여주게 된다.
    //   → 최다 요일이 평균의 1.4배를 넘을 때만 '습관'으로 인정하고,
    //     아니면 빈 배열을 돌려 "고르게 나가신다"고 말한다.
    if last90.count >= 20 {
        var byDay = [Int: Int]()
        for r in last90 { byDay[cal.component(.weekday, from: r.start), default: 0] += 1 }
        let avg = Double(last90.count) / 7.0
        let top = byDay.values.max() ?? 0
        if Double(top) >= avg * 1.40 {
            m.habitDays = byDay.filter { Double($0.value) >= avg * 1.25 }
                               .sorted { $0.value > $1.value }
                               .map(\.key)
        }
    }

    // 습관 — 주로 달리는 시각
    var hourCount = [Int: Int]()
    for r in last90 {
        let h = cal.component(.hour, from: r.start)
        hourCount[h, default: 0] += 1
    }
    m.typicalHour = hourCount.max(by: { $0.value < $1.value })?.key

    // 습관 — 최근 30일 중 러닝한 날 수
    m.days30 = Set(last30d.map { cal.startOfDay(for: $0.date) }).count

    // 습관 — 주당 분
    m.minutesPerWeek = last28.map(\.durationMin).reduce(0, +) / 4.0

    // 90일 거리·횟수
    m.sessions90 = last90.count
    m.km90       = last90.compactMap(\.distanceKm).reduce(0, +)
    m.sessions90LY = ly90.count
    m.km90LY       = ly90.compactMap(\.distanceKm).reduce(0, +)

    // 안정시 심박
    func rhrMedian(in range: ClosedRange<Int>) -> Double? {
        let vals = restingHRSamples.filter {
            let d = daysAgo($0.date); return d >= range.lowerBound && d < range.upperBound
        }.map(\.value)
        return vals.isEmpty ? nil : mrMedian(vals)
    }
    m.restingHR   = rhrMedian(in: 0...90)
    m.restingHRLY = rhrMedian(in: lyLo...lyHi)

    // VO2max
    let sorted = vo2Samples.sorted { $0.date < $1.date }
    m.vo2max   = sorted.filter { daysAgo($0.date) >= 0 && daysAgo($0.date) < 90 }.last?.value
    m.vo2maxLY = sorted.filter { let d = daysAgo($0.date); return d >= lyLo && d < lyHi }.last?.value
    return m
}

