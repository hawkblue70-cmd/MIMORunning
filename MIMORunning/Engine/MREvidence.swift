import Foundation

// MARK: - 근거 문헌 — 문헌 이름 + 연구 종류, 나 탭 '근거 문헌'(접힘) 한곳에 모은다 (2026-11-03)
//
// 조언 카드 펼침마다 문헌 줄을 붙이면 매번 같은 내용을 보게 된다(2026-11-03 사용자) →
// 카드에는 본인 기록만, 문헌은 기능별 목록(`MREvidence.catalog`)으로 나 탭에서 한 번에.
// 연구 종류는 6가지로 고정 — 같은 문헌은 어디서나 같은 종류(아래 `MRCitation` 상수, 분류표 2026-11-03 사용자 확인).

enum MREvidenceKind: Equatable {
    case meta, rct, experiment, observational, review, practice

    var label: String {
        let L = AppLanguage.shared
        switch self {
        case .meta:          return L.s("메타분석", "meta-analysis", ja: "メタ分析")
        case .rct:           return L.s("무작위 연구", "randomized trial", ja: "無作為化試験")
        case .experiment:    return L.s("실험 연구", "experimental study", ja: "実験研究")
        case .observational: return L.s("관찰 연구", "observational study", ja: "観察研究")
        case .review:        return L.s("리뷰·합의", "review/consensus", ja: "レビュー・合意")
        case .practice:      return L.s("코칭 관행", "coaching practice", ja: "コーチングの慣行")
        }
    }
}

struct MRCitation: Equatable {
    /// "Frandsen 2025" — 저자 연도(또는 관행 이름)
    let name: String
    let kind: MREvidenceKind
    /// 괄호 안에 종류 뒤로 붙는 세부 — "n=96", "r=−0.20" 등. 없으면 nil.
    var detail: String? = nil

    /// "Pugh 2018(관찰 연구, n=96)"
    var text: String {
        name + "(" + kind.label + (detail.map { ", " + $0 } ?? "") + ")"
    }

    func with(_ detail: String) -> MRCitation { MRCitation(name: name, kind: kind, detail: detail) }

    // 분류표(2026-11-03 사용자 확인) — 이름이 같으면 화면마다 같은 종류로
    static let jeukendrup2017 = MRCitation(name: "Jeukendrup 2017", kind: .review)
    static let pugh2018 = MRCitation(name: "Pugh 2018", kind: .observational, detail: "n=96")
    static let hewButler2015 = MRCitation(name: "Hew-Butler 2015", kind: .review)
    static let frandsen2025 = MRCitation(name: "Frandsen 2025", kind: .observational, detail: "n=5,205")
    /// ⚠ 무작위 배정 여부 원문 확인 필요(분류표 표시)
    static let vesterinen2016 = MRCitation(name: "Vesterinen 2016", kind: .rct)
    static let rosenblat2025 = MRCitation(name: "Rosenblat 2025", kind: .meta)
    static let blagrove2018 = MRCitation(name: "Blagrove 2018", kind: .meta)
    static let vanHooren2024 = MRCitation(name: "Van Hooren 2024", kind: .meta, detail: "r=−0.20")
    static let heiderscheit2011 = MRCitation(name: "Heiderscheit 2011", kind: .experiment)
    static let maunder2021 = MRCitation(name: "Maunder 2021", kind: .review)
    static let acsm2016 = MRCitation(name: "ACSM/AND/DC 2016", kind: .review)
    /// 표준화된 최대하 속도 심박 ↔ 유산소 체력 변화 체계적 문헌고찰(Int J Sports Med 44(2):95–107) — 저자명 미확인이라 학술지로 적는다
    static let ijsm2023 = MRCitation(name: "Int J Sports Med 2023", kind: .review, detail: "r 0.51–0.88")
    static var frielDecoupling: MRCitation {
        MRCitation(name: AppLanguage.shared.s("Friel 유산소 디커플링 5%", "Friel 5% aerobic decoupling", ja: "Friel 有酸素デカップリング5%"),
                   kind: .practice)
    }
    static var lateRacePace: MRCitation {
        MRCitation(name: AppLanguage.shared.s("롱런 후반 대회 페이스", "race pace late in long runs", ja: "ロング走後半のレースペース"),
                   kind: .practice, detail: AppLanguage.shared.s("통제 연구 없음", "no controlled studies", ja: "対照研究なし"))
    }
}

/// 기능 하나와 그 기능이 기대는 문헌
struct MREvidenceEntry: Equatable, Identifiable {
    let feature: String
    let cites: [MRCitation]
    var id: String { feature }
}

enum MREvidence {
    /// 나 탭 '근거 문헌' 목록 — 조언 카드(성장 탭) + 2026-11-03 문헌 보강 기능. 새 기능은 여기에 한 줄 더한다.
    static var catalog: [MREvidenceEntry] {
        let L = AppLanguage.shared
        return [
            MREvidenceEntry(feature: L.s("롱런 거리 상한 · 한 번 러닝 급증 조언", "Long-run cap · single-run spike", ja: "ロング走の上限 · 1回の急増の助言"),
                            cites: [.frandsen2025]),
            MREvidenceEntry(feature: L.s("레이스 위장 훈련", "Race gut training", ja: "レースの胃腸トレーニング"),
                            cites: [.jeukendrup2017, .pugh2018]),
            MREvidenceEntry(feature: L.s("레이스 수분", "Race hydration", ja: "レースの水分補給"),
                            cites: [.hewButler2015]),
            MREvidenceEntry(feature: L.s("HRV로 강도 세션 시점", "Hard-session timing from HRV", ja: "HRVで強度練習の時期"),
                            cites: [.vesterinen2016]),
            MREvidenceEntry(feature: L.s("이지 비율", "Easy-run share", ja: "イージーの割合"),
                            cites: [.rosenblat2025]),
            MREvidenceEntry(feature: L.s("후반 내구성 — 근력·플라이오", "Late-run durability — strength & plyometrics", ja: "後半の耐久力 — 筋力・プライオ"),
                            cites: [.blagrove2018]),
            MREvidenceEntry(feature: L.s("케이던스", "Cadence", ja: "ケイデンス"),
                            cites: [.vanHooren2024, .heiderscheit2011]),
            MREvidenceEntry(feature: L.s("후반 심박 효율", "Late-run HR efficiency", ja: "後半の心拍効率"),
                            cites: [.frielDecoupling, .maunder2021]),
            MREvidenceEntry(feature: L.s("롱런 후반 대회 페이스", "Race pace late in long runs", ja: "ロング走後半のレースペース"),
                            cites: [.lateRacePace]),
            MREvidenceEntry(feature: L.s("롱런 후반 보급", "Fueling on long runs", ja: "ロング走の補給"),
                            cites: [.acsm2016.with(L.s("1~2.5시간 30~60 g/h", "30–60 g/h for 1–2.5 h", ja: "1~2.5時間で30~60 g/h"))]),
            MREvidenceEntry(feature: L.s("같은 페이스 심박", "HR at your usual pace", ja: "同じペースの心拍"),
                            cites: [.ijsm2023]),
        ]
    }
}
