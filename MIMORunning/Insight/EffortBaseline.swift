import Foundation

/// 개인 기준선 — 최근 8주, 같은 워크아웃 유형의 강도 중앙값. 절대 임계를 쓰지 않는 이유는
/// Apple 추정이 이지런에도 5~6을 주는 경향이 있기 때문(스펙 "결정" 참조).
///
/// 수동 입력 우선: 사용자가 직접 넣은 값은 본인 척도이고 Apple 추정은 부풀려져 있어 같은 잣대가 아니다.
/// 각 단계에서 수동 입력이 3건 이상이면 수동 입력만으로 중앙값을 내고, 부족할 때만 Apple 값을 섞는다.
enum EffortBaseline {
    struct Sample: Equatable {
        /// nil = 유형 미분류. 같은 유형 집계에는 절대 포함되지 않고 전체 폴백에만 쓰인다.
        let type: WorkoutType?
        let effort: Int
        let source: EffortSource

        init(type: WorkoutType?, effort: Int, source: EffortSource = .appleEstimated) {
            self.type = type
            self.effort = effort
            self.source = source
        }
    }

    static let minSamples = 3
    static let windowDays = 56

    /// 유형별 "평소 강도" 요약. 8주 창에서 같은 유형 3건 미만이면 12주로 넓혀 다시 센다.
    struct TypeSummary: Equatable {
        let type: WorkoutType
        let median: Int?          // 같은 유형 3건 이상일 때만(전체 폴백 없음)
        let count: Int            // 같은 유형 표본 수(창 안)
        let isUserBased: Bool     // 수동 입력만으로 계산됐는가
        let windowWeeks: Int      // 8 또는 12
    }

    static let widenedWindowDays = 84

    /// 성장 탭 표의 고정 순서 — 쉬운 유형부터.
    static let tableOrder: [WorkoutType] = [.easy, .lsd, .longRun, .tempo, .interval, .distanceRun, .buildUp, .race, .general]

    /// 우선순위: 같은 유형·수동 → 같은 유형·전체 → 전체 러닝·수동 → 전체 러닝·전체. 각 단계 3건 이상. 모두 미달 → nil.
    static func median(for type: WorkoutType, samples: [Sample]) -> Int? {
        let same = samples.filter { $0.type == type }
        if let m = medianIfEnough(same.filter { $0.source == .user }) { return m }
        if let m = medianIfEnough(same) { return m }
        if let m = medianIfEnough(samples.filter { $0.source == .user }) { return m }
        return medianIfEnough(samples)
    }

    /// 기준선이 수동 입력만으로 계산됐는가(문구용). `median`과 같은 단계 규칙.
    static func isUserBased(for type: WorkoutType, samples: [Sample]) -> Bool {
        let same = samples.filter { $0.type == type }
        if medianIfEnough(same.filter { $0.source == .user }) != nil { return true }
        if medianIfEnough(same) != nil { return false }
        return medianIfEnough(samples.filter { $0.source == .user }) != nil
    }

    private static func medianIfEnough(_ s: [Sample]) -> Int? {
        guard s.count >= minSamples else { return nil }
        return Int(WorkoutTypeClassifier.median(s.map { Double($0.effort) }).rounded())
    }

    /// 현재 런 제외 · 러닝만 · 현재 런 기준 56일 이내 · 강도 있는 것만.
    static func samples(current: Activity,
                        history: [Activity],
                        index: EffortIndex,
                        typeOf: (UUID) -> WorkoutType?) -> [Sample] {
        samples(asOf: current.date, windowDays: windowDays, history: history,
                index: index, typeOf: typeOf, excluding: current.id)
    }

    /// `asOf` 기준(그 날짜 포함) 과거 창. `excluding`은 현재 런 제외용.
    static func samples(asOf: Date,
                        windowDays: Int,
                        history: [Activity],
                        index: EffortIndex,
                        typeOf: (UUID) -> WorkoutType?,
                        excluding: UUID? = nil) -> [Sample] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: asOf)
            ?? asOf.addingTimeInterval(-Double(windowDays) * 86_400)
        return history.compactMap { a in
            guard a.id != excluding, a.type == .running,
                  a.date >= cutoff, a.date <= asOf,
                  let e = index.resolve(a.id) else { return nil }
            return Sample(type: typeOf(a.id), effort: e.value, source: e.source)
        }
    }

    /// 같은 유형만 세는 요약(전체 러닝 폴백 없음). 8주에 3건 미만이면 12주.
    static func typeSummary(for type: WorkoutType,
                            asOf: Date,
                            history: [Activity],
                            index: EffortIndex,
                            typeOf: (UUID) -> WorkoutType?,
                            excluding: UUID? = nil) -> TypeSummary {
        func same(_ days: Int) -> [Sample] {
            samples(asOf: asOf, windowDays: days, history: history, index: index,
                    typeOf: typeOf, excluding: excluding).filter { $0.type == type }
        }
        var used = same(windowDays)
        var weeks = windowDays / 7
        if used.count < minSamples {
            used = same(widenedWindowDays)
            weeks = widenedWindowDays / 7
        }
        guard used.count >= minSamples else {
            return TypeSummary(type: type, median: nil, count: used.count, isUserBased: false, windowWeeks: weeks)
        }
        if let m = medianIfEnough(used.filter { $0.source == .user }) {
            return TypeSummary(type: type, median: m, count: used.count, isUserBased: true, windowWeeks: weeks)
        }
        return TypeSummary(type: type, median: medianIfEnough(used), count: used.count,
                           isUserBased: false, windowWeeks: weeks)
    }

    /// 성장 탭 표: 표본이 1건 이상인 유형만, 고정 순서(easy, lsd, longRun, tempo, interval, distanceRun, buildUp, race, general).
    static func typeTable(asOf: Date,
                          history: [Activity],
                          index: EffortIndex,
                          typeOf: (UUID) -> WorkoutType?) -> [TypeSummary] {
        tableOrder
            .map { typeSummary(for: $0, asOf: asOf, history: history, index: index, typeOf: typeOf) }
            .filter { $0.count > 0 }
    }
}
