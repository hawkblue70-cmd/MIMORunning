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
    // 기본 9종
    case hud
    case receipt
    case scoreboard
    case passportStamp
    case circleBadge
    case labeledRows
    case verticalLabel
    case distanceHero
    case mixedAlign
    // 지표 특화 7종
    case hrWave
    case hrZone
    case elevProfile
    case cadenceEq
    case vitals
    case hrBadge
    case watchHud
    // 지명 3종
    case placeHeadline
    case pinInline
    case mapBackground

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hud:           return "HUD 계기판"
        case .receipt:       return "영수증"
        case .scoreboard:    return "전광판"
        case .passportStamp: return "여권 스탬프"
        case .circleBadge:   return "서클 배지"
        case .labeledRows:   return "행마다 라벨"
        case .verticalLabel: return "세로 라벨"
        case .distanceHero:  return "거리 몰아주기"
        case .mixedAlign:    return "혼합 정렬"
        case .hrWave:        return "심박 파형"
        case .hrZone:        return "심박 존"
        case .elevProfile:   return "고도 프로파일"
        case .cadenceEq:     return "케이던스"
        case .vitals:        return "바이탈 패널"
        case .hrBadge:       return "심박 서클"
        case .watchHud:      return "워치 HUD"
        case .placeHeadline: return "지명 헤드라인"
        case .pinInline:     return "핀 인라인"
        case .mapBackground: return "지도 배경"
        }
    }

    var positionMode: StampPositionMode {
        switch self {
        case .hud, .watchHud, .mapBackground:
            return .fixed
        default:
            return .free9
        }
    }

    var occupancy: StampOccupancy {
        switch self {
        case .receipt, .scoreboard: return .row
        default:                    return .single
        }
    }

    var isColorFixed: Bool {
        switch self {
        case .scoreboard, .receipt, .passportStamp: return true
        default:                                    return false
        }
    }

    var isVideoOnly: Bool {
        self == .hud || self == .watchHud
    }

    var requires: [StampRequirement] {
        switch self {
        case .hrWave, .hrBadge:          return [.heartRate]
        case .hrZone:                    return [.hrZone]
        case .elevProfile:               return [.elevation]
        case .cadenceEq:                 return [.cadence]
        case .vitals:                    return [.heartRate]
        case .watchHud:                  return [.heartRate]
        case .placeHeadline, .pinInline: return [.location]
        case .mapBackground:             return [.route]
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
    var showCalories:   Bool              = false
    var showTextOutline: Bool             = true
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
        templates: [.passportStamp, .receipt, .circleBadge, .distanceHero]
    )

    static let sporty = StampSet(
        id: "sporty",
        name: "스포티",
        templates: [.hud, .scoreboard, .labeledRows, .mixedAlign]
    )

    static let all: [StampSet] = [.classic, .sporty]
}
