// 스탬프 카드 전용 공용 타입. 러닝 데이터(거리·페이스·시간 필수, 심박·칼로리 선택)를
// 사진 위에 텍스트만(투명 배경) 표시하는 템플릿 정의.

import Foundation

// MARK: - Data Requirement

enum StampRequirement {
    case none, heartRate, hrZone, cadence, elevation, location, route
}

// MARK: - Position / Occupancy

enum StampPositionMode {
    case free9, band3, fixed
}

enum StampOccupancy {
    case single, row
}

// MARK: - Template

enum StampTemplate: String, CaseIterable, Identifiable {
    // 경로 결합 2종
    case routeHero
    case routeSide
    // 기본 8종
    case hud
    case scoreboard
    case passportStamp
    case circleBadge
    case labeledRows
    case inlineTriple
    case distanceHero
    case summaryGrid
    // 지표 특화 4종
    case hrWave
    case hrZone
    case elevProfile
    case cadenceEq
    // 지명 1종
    case placeHeadline

    var id: String { rawValue }

    /// 삭제·병합된 템플릿의 저장값(rawValue)을 가장 가까운 현행 템플릿으로 매핑 (2026-09 정리).
    /// 저장된 설정을 불러올 때만 사용. 병합된 심박 변형은 `legacyImpliesHeartRate`로 심박 토글을 켠다.
    static func resolvingLegacy(_ raw: String) -> StampTemplate? {
        if let t = StampTemplate(rawValue: raw) { return t }
        switch raw {
        case "verticalLabel", "mixedAlign": return .labeledRows
        case "vitals":                      return .hrWave
        case "pinInline":                   return .placeHeadline
        case "routeRows", "routeVertical":  return .routeSide
        case "receipt":                     return .scoreboard   // 영수증 → 전광판 (같은 행 점유 타입)
        case "hrBadge":                     return .circleBadge   // 심박 서클 → 서클 배지 + 심박 토글
        case "watchHud":                    return .hud           // 워치 HUD → HUD + 심박 토글
        default:                            return nil
        }
    }
    /// 병합 전 템플릿 값이 심박 표시를 전제로 했던 경우 true.
    static func legacyImpliesHeartRate(_ raw: String) -> Bool {
        raw == "hrBadge" || raw == "watchHud"
    }

    var displayName: String {
        let L = AppLanguage.shared
        switch self {
        case .hud:           return L.s("HUD 계기판",      "HUD Gauge")
        case .scoreboard:    return L.s("전광판",          "Scoreboard")
        case .passportStamp: return L.s("여권 스탬프",     "Passport Stamp")
        case .circleBadge:   return L.s("서클 배지",       "Circle Badge")
        case .labeledRows:   return L.s("행마다 라벨",     "Row Labels")
        case .inlineTriple:  return L.s("가로 3열",        "Inline Triple")
        case .distanceHero:  return L.s("거리 몰아주기",   "Distance Hero")
        case .summaryGrid:   return L.s("요약 그리드",     "Summary Grid")
        case .hrWave:        return L.s("심박 파형",       "HR Wave")
        case .hrZone:        return L.s("심박 존",         "HR Zones")
        case .elevProfile:   return L.s("고도 프로파일",   "Elevation Profile")
        case .cadenceEq:     return L.s("케이던스",        "Cadence")
        case .placeHeadline: return L.s("지명 헤드라인",   "Place Headline")
        case .routeHero:     return L.s("루트 히어로",     "Route Hero")
        case .routeSide:     return L.s("루트 사이드",     "Route Side")
        }
    }

    var positionMode: StampPositionMode {
        switch self {
        case .hud:
            return .fixed
        default:
            return .free9
        }
    }

    var occupancy: StampOccupancy {
        switch self {
        case .scoreboard:           return .row
        default:                    return .single
        }
    }

    var isColorFixed: Bool {
        switch self {
        case .scoreboard, .passportStamp: return true
        default:                                    return false
        }
    }

    var isVideoOnly: Bool {
        self == .hud
    }

    /// 심박 토글이 그림을 바꾸는 스탬프인가.
    ///
    /// 여기 없는 스탬프는 `showHeartRate`를 아예 받지 않아 토글을 눌러도 아무 일이 없다.
    /// 심박 파형·심박 존은 심박이 본체이고, 전광판·서클 배지·루트 히어로·요약 그리드는
    /// 심박을 토글 없이 항상 그린다. 여권 스탬프·고도·케이던스·지명은 심박을 그리지 않는다.
    /// `StampHeartRateToggleTests`가 실제 렌더로 이 목록과 코드가 맞는지 검사한다.
    var supportsHeartRateToggle: Bool {
        switch self {
        case .labeledRows, .inlineTriple, .distanceHero, .hud, .routeSide:
            return true
        default:
            return false
        }
    }

    // MARK: 크기 규칙 (절대 배율표)
    //
    // 기준 폭 211pt(영상·슬라이드 논리 폭, 가장 좁음)에서 소 40% · 중 55% · 대 72% · 특대 90%를
    // 차지하도록 스탬프별로 고정한 배율. 높이는 특대 기준 폭의 75%(158pt)를 넘지 않게 상한.
    // 자연 폭·높이(scale 1)는 StampMeasureTests로 측정 → 아래 상수는 그 결과에서 산출한 값.
    // 값을 손으로 조정해도 되며, 스탬프를 추가하면 측정 후 한 줄을 추가한다. HUD는 고정형이라 예외.
    var sizeScales: (small: CGFloat, medium: CGFloat, large: CGFloat, xlarge: CGFloat) {
        switch self {
        case .passportStamp: return (small: 0.61, medium: 0.85, large: 1.11, xlarge: 1.39)
        case .circleBadge:  return (small: 0.67, medium: 0.93, large: 1.22, xlarge: 1.52)
        case .scoreboard:   return (small: 0.27, medium: 0.37, large: 0.49, xlarge: 0.58)   // 심박까지 한 줄, 폭 311. 특대는 좌우 여백에 걸려 0.61 → 0.58
        case .labeledRows:  return (small: 0.60, medium: 0.82, large: 1.08, xlarge: 1.35)
        case .inlineTriple: return (small: 0.28, medium: 0.38, large: 0.50, xlarge: 0.62)
        case .distanceHero: return (small: 0.56, medium: 0.78, large: 1.02, xlarge: 1.28)
        case .summaryGrid:  return (small: 0.38, medium: 0.52, large: 0.68, xlarge: 0.84)   // 특대는 높이 상한(158pt)에 걸려 0.85 → 0.84
        case .hud:          return (small: 0.50, medium: 0.65, large: 0.80, xlarge: 1.00)
        case .hrWave:       return (small: 0.56, medium: 0.77, large: 1.01, xlarge: 1.27)
        case .hrZone:       return (small: 0.55, medium: 0.76, large: 1.00, xlarge: 1.25)
        case .elevProfile:  return (small: 0.51, medium: 0.71, large: 0.93, xlarge: 1.16)
        case .cadenceEq:    return (small: 0.64, medium: 0.88, large: 1.15, xlarge: 1.44)
        case .placeHeadline: return (small: 0.64, medium: 0.88, large: 1.16, xlarge: 1.45)
        case .routeHero:    return (small: 0.34, medium: 0.46, large: 0.60, xlarge: 0.74)   // 심박 열이 붙어 폭 164 → 238. 특대는 좌우 여백에 걸려 0.76 → 0.74
        case .routeSide:    return (small: 0.38, medium: 0.53, large: 0.69, xlarge: 0.87)
        }
    }

    func stampScale(for level: TextSizeLevel) -> CGFloat {
        let t = sizeScales
        switch level {
        case .small:  return t.small
        case .medium: return t.medium
        case .large:  return t.large
        case .xlarge: return t.xlarge
        }
    }

    /// 기울어진 스탬프가 레이아웃 프레임보다 왼쪽으로 삐져나오는 양(scale 1 기준).
    /// 왼쪽 정렬 시 이만큼 더 들여 실제 잉크의 왼쪽 끝을 로고에 맞춘다.
    /// 여권 스탬프: 137×69 프레임을 -7° 회전 → 세로 반높이 × sin7° ≈ 4.2 + 가로 성분 0.5.
    var leadingOverhang: CGFloat {
        switch self {
        case .passportStamp: return 4.7
        default:             return 0
        }
    }

    var requires: [StampRequirement] {
        switch self {
        case .hrWave:                    return [.heartRate]
        case .hrZone:                    return [.hrZone]
        case .elevProfile:               return [.elevation]
        case .cadenceEq:                 return [.cadence]
        case .placeHeadline:             return [.location]
        case .routeHero, .routeSide:     return [.route]
        default:                         return [.none]
        }
    }
}

// MARK: - Color Mode

enum StampColorMode: String, CaseIterable {
    case auto
    case brand
    case ink
    case lime
    case red

    var displayName: String {
        switch self {
        case .auto:  return "자동"
        case .brand: return "기본"
        case .ink:   return "잉크"
        case .lime:  return "라임"
        case .red:   return "레드"
        }
    }
}

// MARK: - Entrance Animation Mode

enum StampEntranceMode: String, CaseIterable {
    case stamp  = "stamp"   // 도장 찍히는 스프링 등장 (기본)
    case fade   = "fade"    // 페이드인
    case flyIn  = "flyIn"   // 방향에서 슬라이드 인
    case none   = "none"    // 애니메이션 없음

    var chipLabel: String {
        switch self {
        case .stamp: return AppLanguage.shared.s("도장", "Stamp")
        case .fade:  return AppLanguage.shared.s("페이드", "Fade")
        case .flyIn: return AppLanguage.shared.s("날아오기", "Fly In")
        case .none:  return AppLanguage.shared.s("없음", "None")
        }
    }
}

// MARK: - Controls Tab

enum StampControlTab { case stamp, text }

// MARK: - Per-photo Config

/// 사진 한 장(또는 클립 하나)의 스탬프·문구·애니메이션 속성 전체.
/// story / slide / video 모두 클립·사진마다 독립 저장.
struct StampPhotoConfig: Equatable {
    var template:       StampTemplate     = .passportStamp
    var colorMode:      StampColorMode    = .auto
    var position:       CardPosition      = .bottom
    var sizeLevel:      TextSizeLevel     = .medium
    var showHeartRate:  Bool              = false
    var showTextOutline: Bool             = true
    /// 워드마크 줄 오른쪽에 날짜·시간 표시 (스토리·영상·슬라이드·경로 영상 공통). 기본 ON — 로고 칩과 같은 원칙
    var showDate:       Bool              = true
    var text:           String            = ""
    var textPosition:   CardPosition      = .top
    var textFont:       OneLinerFont      = .gothic
    var textSize:       TextSizeLevel     = .medium
    var textColor:      OneLinerTextColor = .white
    var textHasBorder:  Bool              = false
    // 애니메이션 (영상·슬라이드 클립별 독립)
    var entranceMode:     StampEntranceMode = .stamp
    var flyDirection:     FlyInDirection    = .trailing
    var textEntranceMode: StampEntranceMode = .fade
    var textFlyDirection: FlyInDirection    = .bottom
}

// MARK: - Stamp Set (슬라이드용)

struct StampSet: Identifiable {
    let id: String
    let name: String
    let templates: [StampTemplate]

    static let classic = StampSet(
        id: "classic",
        name: "클래식",
        templates: [.passportStamp, .scoreboard, .circleBadge, .distanceHero]
    )

    static let sporty = StampSet(
        id: "sporty",
        name: "스포티",
        templates: [.hud, .scoreboard, .labeledRows, .routeSide]
    )

    static let all: [StampSet] = [.classic, .sporty]
}
