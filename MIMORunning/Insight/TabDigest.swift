import Foundation

/// 오늘의 인사이트 탭 요약 — 신호를 탭별 블록으로 조합한다.
/// 같은 사실을 여러 카드가 말하지 않도록 묶음(family)마다 소유 탭을 하나로 정한다.
enum TabDigest {
    enum Tab: Int, CaseIterable, Comparable {
        case rhythm, form, performance

        static func < (a: Tab, b: Tab) -> Bool { a.rawValue < b.rawValue }
    }

    enum Kind: Equatable { case problem, good, extra }

    enum Tone: Equatable { case caution, good, neutral }

    /// 같은 사실을 여러 카드가 말하는 신호 묶음 — 묶음마다 소유 탭은 하나
    enum Family: Equatable {
        case lateHR, latePace, lateForm, load, distanceRank, efficiency, unique

        /// 앞쪽 탭부터 신호가 있으면 그 탭이 소유
        var ownerOrder: [Tab] {
            switch self {
            case .lateHR:       return [.performance, .rhythm]
            case .latePace:     return [.form, .rhythm, .performance]
            // 후반 폼 변화(다리 먼저 지침·무거워짐·범위 이탈) — 폼 카드가 소유
            case .lateForm:     return [.form, .rhythm]
            case .load:         return [.performance, .rhythm, .form]
            case .distanceRank: return [.rhythm, .performance]
            case .efficiency:   return [.performance]
            case .unique:       return Tab.allCases
            }
        }
    }

    struct Signal: Equatable {
        let tab: Tab
        let kind: Kind
        /// 같은 탭·같은 kind 안에서 작을수록 먼저 (설계 §4 표의 순서 번호)
        let priority: Int
        let family: Family
        let text: String
        var tone: Tone = .neutral
        /// 이 문제/신호의 짝 권고 — 없으면 nil
        var direction: String? = nil
    }

    /// 탭마다 문제 없을 때 쓰는 기본 방향(설계 §4 각 '기본 방향')
    struct Defaults: Equatable { var directions: [Tab: String] = [:] }

    struct Statement: Equatable { let text: String; let tone: Tone }

    struct Block: Equatable { let tab: Tab; let statements: [Statement]; let direction: String? }

    static func make(_ signals: [Signal], defaults: Defaults = .init()) -> [Block] {
        let owned = signals.filter { s in
            guard s.family != .unique else { return true }
            let owner = s.family.ownerOrder.first { t in signals.contains { $0.family == s.family && $0.tab == t } }
            return owner == s.tab
        }
        var used = Set<String>()
        var out: [Block] = []
        for tab in Tab.allCases {
            let mine = owned.filter { $0.tab == tab }
            let problems = Array(mine.filter { $0.kind == .problem }.sorted { $0.priority < $1.priority }.prefix(2))
            let good = problems.isEmpty ? mine.filter { $0.kind == .good }.min { $0.priority < $1.priority } : nil
            let extra = mine.filter { $0.kind == .extra }.min { $0.priority < $1.priority }
            let chosen = problems + [good, extra].compactMap { $0 }
            guard !chosen.isEmpty else { continue }
            var dir = problems.first?.direction ?? good?.direction ?? defaults.directions[tab]
            if let d = dir, used.contains(d) { dir = nil }
            if let d = dir { used.insert(d) }
            out.append(Block(tab: tab, statements: chosen.map { Statement(text: $0.text, tone: $0.tone) }, direction: dir))
        }
        return out
    }

    /// 세 탭 수집기 결과를 한 번에 조합 — `make(rhythm + form + performance)`와 같다.
    static func assemble(rhythm: [Signal], form: [Signal], performance: [Signal], defaults: Defaults = .init()) -> [Block] {
        make(rhythm + form + performance, defaults: defaults)
    }
}
