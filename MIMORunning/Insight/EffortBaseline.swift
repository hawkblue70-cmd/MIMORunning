import Foundation

/// 개인 기준선 — 최근 8주, 같은 워크아웃 유형의 강도 중앙값. 절대 임계를 쓰지 않는 이유는
/// Apple 추정이 이지런에도 5~6을 주는 경향이 있기 때문(스펙 "결정" 참조).
enum EffortBaseline {
    struct Sample: Equatable {
        let type: WorkoutType
        let effort: Int
    }

    static let minSamples = 3
    static let windowDays = 56

    /// 같은 유형 3건 이상 → 그 중앙값. 미달 → 전체 러닝 3건 이상이면 전체 중앙값. 그것도 미달 → nil.
    static func median(for type: WorkoutType, samples: [Sample]) -> Int? {
        let same = samples.filter { $0.type == type }.map { Double($0.effort) }
        if same.count >= minSamples { return Int(WorkoutTypeClassifier.median(same).rounded()) }
        let all = samples.map { Double($0.effort) }
        if all.count >= minSamples { return Int(WorkoutTypeClassifier.median(all).rounded()) }
        return nil
    }

    /// 현재 런 제외 · 러닝만 · 현재 런 기준 56일 이내 · 강도 있는 것만.
    static func samples(current: Activity,
                        history: [Activity],
                        index: EffortIndex,
                        typeOf: (UUID) -> WorkoutType?) -> [Sample] {
        let cutoff = current.date.addingTimeInterval(-Double(windowDays) * 86_400)
        return history.compactMap { a in
            guard a.id != current.id, a.type == .running,
                  a.date >= cutoff, a.date <= current.date,
                  let e = index.resolve(a.id) else { return nil }
            return Sample(type: typeOf(a.id) ?? .general, effort: e.value)
        }
    }
}
