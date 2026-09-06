import Foundation

// MARK: - 내구성 판단 — 롱런 후반 케이던스 붕괴(S1)
//
// "다리가 지치면 발걸음이 느려진다"를 본인 데이터로 잰다.
// 같은 롱런 안에서 첫 25% 구간과 마지막 25% 구간의 케이던스를 비교한다.
//
// ⚠ 페이스 게이트(±5%)가 핵심이다. 후반에 느려졌으면 케이던스 하락이
//   속도 변화로 설명되므로 판정하지 않는다(nil). false가 아니다.
// ⚠ 초반 과속·초반 역치는 근력 문제가 아니다 → RunInsightEngine.analyzeFade와
//   같은 규칙으로 제외한다(중앙 페이스 ×0.95 / maxHR ×0.85).
// ⚠ 수직 진동은 쓰지 않는다. 폼 카드가 Apple Watch MAPE 19%를 이유로
//   추세 판정에서 제외한 것과 일관되게 케이던스만 쓴다.
// ⚠ 3% 임계는 임의로 정함. 170spm 기준 5spm — 페도미터 정수 반올림(1spm)보다 충분히 크다.
// ⚠ 근력·플라이오가 이 패턴을 늦춘다는 직접 근거는 없다. 있는 것은
//   Blagrove 2018 (Sports Med 48(5):1117–1149) "근력 추가 → 경제성·기록 개선"이다.
//   그래서 이 조언은 B등급이다.

/// 롱런 한 건의 피로 요약. HealthKit 상세 캐시의 km 스플릿에서 만든다.
struct MRLongRunFatigue: Codable, Sendable, Identifiable {
    let id: UUID
    let start: Date                // 워크아웃 시작 시각 (원본)
    var date: Date { Calendar.current.startOfDay(for: start) }   // 일 단위 비교용
    let distanceKm: Double
    let durationMin: Double
    let q1PaceSecPerKm: Double     // 첫 25% 구간 (km1 제외)
    let q4PaceSecPerKm: Double     // 마지막 25% 구간 (마지막 부분 스플릿 제외)
    let q1Cadence: Double
    let q4Cadence: Double
    let firstHalfAvgHR: Double?    // 스플릿 avgHeartRate 전반 평균
    let cadenceCoverage: Double    // 케이던스 있는 스플릿 비율 (0~1)

    var cadenceDropPct: Double {
        guard q1Cadence > 0 else { return 0 }
        return (1 - q4Cadence / q1Cadence) * 100
    }
}

enum MRDurabilityCheck {

    static let cadenceDropFrac  = 0.03    // 임의로 정함 — 170spm 기준 5spm, 페도미터 정수 반올림(1spm)보다 충분히 큼
    static let paceGateFrac     = 0.05    // 임의로 정함 — 페이스 5% 안이면 케이던스 차이를 속도 탓으로 돌릴 수 없다
    static let minSplits        = 8       // 임의로 정함 — km1·부분 스플릿 제거 후 분기당 ≥2개 확보
    static let minCoverage      = 0.8     // 임의로 정함 — 워치 케이던스 누락 20% 초과면 분기 평균 신뢰 불가
    static let windowDays       = 56      // 8주
    static let maxRunsConsidered = 3      // 임의로 정함 — 한 번의 나쁜 날을 패턴으로 굳히지 않기 위해 3회 중 2회

    // MARK: 자격

    /// 롱런 자격: 러닝·야외·비인터벌은 호출 쪽에서 거른다. 여기서는 거리·시간·유형.
    static func isEligibleLongRun(distanceKm: Double, durationMin: Double,
                                  longest16wKm: Double, workoutType: WorkoutType) -> Bool {
        if workoutType == .interval || workoutType == .buildUp || workoutType == .tempo { return false }
        let minKm = max(10.0, longest16wKm * 0.7)   // 임의로 정함 — 본인 16주 최장의 70% (본인이 실제로 해낸 값 기준) · 최소 10km/60분
        return distanceKm >= minKm && durationMin >= 60
    }

    // MARK: 요약

    /// km 스플릿 → 피로 요약. 스플릿 8개 미만 · 케이던스 커버리지 80% 미만이면 nil.
    static func summarize(id: UUID, start: Date, distanceKm: Double, durationMin: Double,
                          splits: [SplitData]) -> MRLongRunFatigue? {
        guard splits.count >= minSplits else { return nil }
        var body = splits.sorted { $0.id < $1.id }
        // km1 제외 (워밍업), 마지막 부분 스플릿 제외
        body.removeFirst()
        if let last = body.last, last.distanceM < 1000 { body.removeLast() }
        guard body.count >= 4 else { return nil }   // minSplits 방어선 (8 − km1 − 부분 = 6 ≥ 4)

        let withCad = body.filter { $0.avgCadence != nil }.count
        let coverage = Double(withCad) / Double(body.count)
        guard coverage >= minCoverage else { return nil }

        let q = max(2, body.count / 4)
        let q1 = Array(body.prefix(q))
        let q4 = Array(body.suffix(q))

        func pace(_ s: [SplitData]) -> Double {
            let dist = s.map(\.distanceM).reduce(0, +)
            let dur  = s.map(\.duration).reduce(0, +)
            return dist > 0 ? dur / (dist / 1000) : 0
        }
        func cad(_ s: [SplitData]) -> Double? {
            let v = s.compactMap(\.avgCadence).map(Double.init)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        guard let c1 = cad(q1), let c4 = cad(q4), c1 > 0 else { return nil }

        let half = Array(body.prefix(max(1, body.count / 2)))
        let hrs = half.compactMap(\.avgHeartRate).map(Double.init)
        let hr: Double? = hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)

        return MRLongRunFatigue(id: id, start: start,
                                distanceKm: distanceKm, durationMin: durationMin,
                                q1PaceSecPerKm: pace(q1), q4PaceSecPerKm: pace(q4),
                                q1Cadence: c1, q4Cadence: c4,
                                firstHalfAvgHR: hr, cadenceCoverage: coverage)
    }

    // MARK: 판정

    /// S1 판정. nil = 평가 불가 (페이스 게이트 밖 · 초반 과속 · 초반 역치).
    static func evaluate(_ f: MRLongRunFatigue, recentMedianPace: Double?, maxHR: Double?) -> Bool? {
        guard f.q1PaceSecPerKm > 0, f.q1Cadence > 0 else { return nil }
        let paceDiff = abs(f.q4PaceSecPerKm - f.q1PaceSecPerKm) / f.q1PaceSecPerKm
        guard paceDiff <= paceGateFrac else { return nil }
        if let med = recentMedianPace, med > 0, f.q1PaceSecPerKm < med * 0.95 { return nil }
        if let mhr = maxHR, mhr > 0, let hr = f.firstHalfAvgHR, hr >= mhr * 0.85 { return nil }
        return f.q4Cadence < f.q1Cadence * (1 - cadenceDropFrac)
    }

    // MARK: 집계

    struct Verdict: Sendable {
        let evaluated: Int
        let positive: Int
        let latestDropPct: Double?        // 가장 최근 평가된 롱런의 케이던스 하락률 (양수 = 하락)
        let latestDate: Date?
        let latestPositiveIsToday: Bool
        var triggered: Bool { evaluated >= 2 && positive >= 2 }   // 임의로 정함 — 한 번의 나쁜 날을 패턴으로 굳히지 않기 위해 3회 중 2회
    }

    /// 최근 8주 자격 롱런 중 평가 가능한 것 최신순 최대 3개. 2개 이상 true → 발동.
    static func aggregate(fatigue: [MRLongRunFatigue], runs: [MRWorkout],
                          maxHR: Double?, asOf: Date) -> Verdict {
        let cal = Calendar.current
        let today = cal.startOfDay(for: asOf)
        let cutoff = cal.date(byAdding: .day, value: -windowDays, to: today) ?? today
        let recent = fatigue.filter { $0.date >= cutoff && $0.date <= today }
                            .sorted { $0.start > $1.start }

        var results: [(f: MRLongRunFatigue, s1: Bool)] = []
        for f in recent {
            let med = medianPace(runs: runs, before: f.date)
            if let s1 = evaluate(f, recentMedianPace: med, maxHR: maxHR) {
                results.append((f, s1))
            }
            if results.count >= maxRunsConsidered { break }
        }
        let latest = results.first
        return Verdict(evaluated: results.count,
                       positive: results.filter(\.s1).count,
                       latestDropPct: latest.map { $0.f.cadenceDropPct },
                       latestDate: latest?.f.date,
                       latestPositiveIsToday: latest.map { $0.s1 && cal.isDate($0.f.date, inSameDayAs: today) } ?? false)
    }

    /// 해당 날짜 직전 8주 러닝 페이스 중앙값. RunInsightEngine.analyzeFade와 같은 창.
    static func medianPace(runs: [MRWorkout], before date: Date) -> Double? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -windowDays, to: date) ?? date
        // 당일 러닝(본인 포함)은 제외 — analyzeFade의 id != activity.id 와 같은 효과
        let paces = runs.filter { $0.date >= start && $0.date < date }
                        .compactMap(\.paceSecPerKm).sorted()
        guard !paces.isEmpty else { return nil }
        return paces[paces.count / 2]
    }
}
