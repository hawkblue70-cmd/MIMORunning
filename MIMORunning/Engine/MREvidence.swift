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
    /// MSSE 48(7):1347–1354, PubMed 색인 "Randomized controlled trial"(2026-11-11 확인)
    static let vesterinen2016 = MRCitation(name: "Vesterinen 2016", kind: .rct, detail: "n=40")
    static let rosenblat2025 = MRCitation(name: "Rosenblat 2025", kind: .meta)
    static let blagrove2018 = MRCitation(name: "Blagrove 2018", kind: .meta)
    static let vanHooren2024 = MRCitation(name: "Van Hooren 2024", kind: .meta, detail: "r=−0.20")
    static let heiderscheit2011 = MRCitation(name: "Heiderscheit 2011", kind: .experiment)
    static let maunder2021 = MRCitation(name: "Maunder 2021", kind: .review)
    static let acsm2016 = MRCitation(name: "ACSM/AND/DC 2016", kind: .review)
    /// Schimpchen 외 2023, Int J Sports Med 44(2):95–107 — 표준화된 최대하 속도 심박 ↔ 유산소 체력 변화 체계적 문헌고찰(2026-11-11 저자 확인)
    static let schimpchen2023 = MRCitation(name: "Schimpchen 2023", kind: .review, detail: "r 0.51–0.88")

    // 앱 핵심 판정 문헌(코드 주석에 있던 것, 2026-11-11 목록에 추가 · 분류표 사용자 확인)
    static let riegel1981 = MRCitation(name: "Riegel 1981", kind: .observational)
    static let vickers2016 = MRCitation(name: "Vickers & Vertosick 2016", kind: .observational, detail: "n=2,303")
    static let bosquet2007 = MRCitation(name: "Bosquet 2007", kind: .meta)
    static let fokkema2020 = MRCitation(name: "Fokkema 2020", kind: .observational)
    static let buist2008 = MRCitation(name: "Buist 2008", kind: .rct, detail: "n=532")
    static let foster2001 = MRCitation(name: "Foster 2001", kind: .experiment)
    static let stoggl2014 = MRCitation(name: "Stöggl & Sperlich 2014", kind: .rct)
    static let tanaka2001 = MRCitation(name: "Tanaka 2001", kind: .meta)
    static let nuuttila2025 = MRCitation(name: "Nuuttila 2025", kind: .observational, detail: "n=165")
    static let daanen2012 = MRCitation(name: "Daanen 2012", kind: .review)
    static let ely2007 = MRCitation(name: "Ely 2007", kind: .observational)
    static let elHelou2012 = MRCitation(name: "El Helou 2012", kind: .observational)
    static var daniels: MRCitation {
        MRCitation(name: AppLanguage.shared.s("Daniels' Running Formula", "Daniels' Running Formula", ja: "Daniels' Running Formula"),
                   kind: .practice)
    }
    static var frielDecoupling: MRCitation {
        MRCitation(name: AppLanguage.shared.s("Friel 유산소 디커플링 5%", "Friel 5% aerobic decoupling", ja: "Friel 有酸素デカップリング5%"),
                   kind: .practice)
    }
    static var lateRacePace: MRCitation {
        // 기능 이름과 같은 말을 되풀이하지 않게 — "통제 연구 없음(코칭 관행)"(2026-11-11)
        MRCitation(name: AppLanguage.shared.s("통제 연구 없음", "No controlled studies", ja: "対照研究なし"),
                   kind: .practice)
    }
}

/// 기능 하나와 그 기능이 기대는 문헌
struct MREvidenceEntry: Equatable, Identifiable {
    let feature: String
    let cites: [MRCitation]
    var id: String { feature }
}

enum MREvidence {
    /// 나 탭 '근거 문헌' 목록 — 계획 → 대회 → 강도·심박 → 폼 순서. 새 기능은 여기에 한 줄 더한다.
    static var catalog: [MREvidenceEntry] {
        let L = AppLanguage.shared
        func e(_ ko: String, _ en: String, _ ja: String, _ cites: [MRCitation]) -> MREvidenceEntry {
            MREvidenceEntry(feature: L.s(ko, en, ja: ja), cites: cites)
        }
        return [
            // 훈련 계획
            e("롱런 거리 상한 · 한 번 러닝 급증 조언", "Long-run cap · single-run spike", "ロング走の上限 · 1回の急増の助言", [.frandsen2025]),
            e("롱런 목표 거리", "Long-run target distance", "ロング走の目標距離", [.fokkema2020]),
            e("주간 거리 상한 없음", "No weekly-volume cap", "週間距離の上限なし", [.buist2008]),
            e("테이퍼", "Taper", "テーパー", [.bosquet2007]),
            e("강도 훈련 분리(이지·강도)", "Separating easy and hard training", "強度練習の分離(イージー・強度)", [.stoggl2014]),
            e("역치 페이스 · 훈련 페이스", "Threshold & training paces", "閾値ペース・練習ペース", [.daniels]),
            e("롱런 후반 대회 페이스", "Race pace late in long runs", "ロング走後半のレースペース", [.lateRacePace]),
            // 대회
            e("대회 기록 예측", "Race-time prediction", "大会記録の予測", [.riegel1981, .vickers2016]),
            e("레이스 위장 훈련", "Race gut training", "レースの胃腸トレーニング", [.jeukendrup2017, .pugh2018]),
            e("레이스 수분", "Race hydration", "レースの水分補給", [.hewButler2015]),
            e("롱런 후반 보급", "Fueling on long runs", "ロング走の補給",
              [.acsm2016.with(L.s("1~2.5시간 30~60 g/h", "30–60 g/h for 1–2.5 h", ja: "1~2.5時間で30~60 g/h"))]),
            // 강도·심박·컨디션
            e("운동 강도 부하(AU)", "Session load (AU)", "運動強度の負荷(AU)", [.foster2001]),
            e("최대 심박 추정", "Max heart-rate estimate", "最大心拍の推定", [.tanaka2001]),
            e("이지 상한(LT1 심박)", "Easy ceiling (LT1 heart rate)", "イージーの上限(LT1心拍)", [.nuuttila2025]),
            e("이지 비율", "Easy-run share", "イージーの割合", [.rosenblat2025]),
            e("HRV로 강도 세션 시점", "Hard-session timing from HRV", "HRVで強度練習の時期", [.vesterinen2016]),
            e("운동 후 심박 회복", "Post-run heart-rate recovery", "運動後の心拍回復", [.daanen2012]),
            e("더위 보정", "Heat adjustment", "暑さの補正", [.ely2007, .elHelou2012]),
            e("같은 페이스 심박", "HR at your usual pace", "同じペースの心拍", [.schimpchen2023]),
            // 폼·후반
            e("케이던스", "Cadence", "ケイデンス", [.vanHooren2024, .heiderscheit2011]),
            e("후반 내구성 — 근력·플라이오", "Late-run durability — strength & plyometrics", "後半の耐久力 — 筋力・プライオ", [.blagrove2018]),
            e("후반 심박 효율", "Late-run HR efficiency", "後半の心拍効率", [.frielDecoupling, .maunder2021]),
        ]
    }
}
