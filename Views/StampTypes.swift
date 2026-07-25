// 스탬프 카드 전용 공용 타입. 러닝 데이터(거리·페이스·시간 필수, 심박·칼로리 선택)를
// 사진 위에 텍스트만(투명 배경) 표시하는 템플릿 정의.

import Foundation

// MARK: - Position / Occupancy

enum StampPositionMode {
    case free9, band3, fixed
}

enum StampOccupancy {
    case single, row
}

// MARK: - Template

enum StampTemplate: String, CaseIterable, Identifiable {
    case hud
    case receipt
    case scoreboard
    case passportStamp
    case circleBadge
    case labeledRows
    case verticalLabel
    case distanceHero
    case mixedAlign

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
        }
    }

    var positionMode: StampPositionMode {
        switch self {
        case .hud:                         return .fixed
        case .receipt, .scoreboard:        return .band3
        default:                           return .free9
        }
    }

    var occupancy: StampOccupancy {
        switch self {
        case .receipt, .scoreboard:        return .row
        default:                           return .single
        }
    }

    var isColorFixed: Bool {
        switch self {
        case .scoreboard, .receipt, .passportStamp: return true
        default:                                    return false
        }
    }

    var isVideoOnly: Bool {
        self == .hud
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
