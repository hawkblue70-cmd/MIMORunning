import Foundation

// MARK: - '나' 탭 입력
//
// 이 앱이 사용자에게 받는 것은 **이것뿐이다.**
// 나이·성별·경력·부상이력·목표페이스 같은 것은 묻지 않는다.
// 나머지는 전부 HealthKit에서 추론한다.

struct MRTargetRace: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var distanceM: Double        // 사용자가 칩으로 고른 거리 (5K/10K/하프/풀)
    var name: String
    var startTime: String?       // "08:00"
    var place: String?

    var label: String { mrLabelFor(distanceM: distanceM) }
}

struct MRGoals: Codable, Equatable {
    var tenKSec: Int?            // 10K 목표 (초)
    var halfSec: Int?
    var fullSec: Int?

    func minutes(for distanceM: Double) -> Double? {
        let s: Int?
        switch distanceM {
        case MRDistance.d10:  s = tenKSec
        case MRDistance.dH:   s = halfSec
        case MRDistance.dF:   s = fullSec
        default:              s = nil
        }
        return s.map { Double($0) / 60.0 }
    }
}

struct MRUserInput: Codable, Equatable {
    var races: [MRTargetRace] = []
    var goals = MRGoals()

    /// 아직 지나지 않은 대회만, 날짜순
    func upcomingRaces(asOf: Date) -> [MRTargetRace] {
        races.filter { $0.date >= Calendar.current.startOfDay(for: asOf) }
             .sorted { $0.date < $1.date }
    }
}

// MARK: - 저장

enum MRUserInputStore {
    private static let key = "mimo.userInput.v1"

    static func load() -> MRUserInput {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode(MRUserInput.self, from: d)
        else { return MRUserInput() }
        return v
    }

    static func save(_ v: MRUserInput) {
        if let d = try? JSONEncoder().encode(v) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}

// MARK: - '나' 탭 모델(MyPlannedRace) 변환
//
// MyPlannedRace는 SwiftData @Model이라 엔진이 직접 참조하면 안 된다.
// 이 함수 한 곳에서만 변환한다.

func mrTargetRace(from r: MyPlannedRace) -> MRTargetRace? {
    guard let date = r.raceDate, r.selectedDistanceKm > 0 else { return nil }
    return MRTargetRace(date: date,
                        distanceM: r.selectedDistanceKm * 1000,
                        name: r.raceName,
                        startTime: r.startTime,
                        place: r.startPlace.isEmpty ? nil : r.startPlace)
}
