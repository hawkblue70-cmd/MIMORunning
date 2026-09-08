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
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: current.date)
            ?? current.date.addingTimeInterval(-Double(windowDays) * 86_400)
        return history.compactMap { a in
            guard a.id != current.id, a.type == .running,
                  a.date >= cutoff, a.date <= current.date,
                  let e = index.resolve(a.id) else { return nil }
            return Sample(type: typeOf(a.id), effort: e.value, source: e.source)
        }
    }
}
