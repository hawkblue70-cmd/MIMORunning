import Foundation
import SwiftData

/// SwiftData-persisted race match; replaces UserDefaults JSON so matches
/// are included in the CloudKit automatic sync path.
@Model
final class PersistedRaceMatchRecord {
    var activityID:  String = ""
    var raceName:    String = ""
    var distanceKm:  Double = 0
    var raceDate:    Date   = Date()
    var isConfirmed: Bool   = false
    var isDismissed: Bool   = false
    var isManual:    Bool   = false
    /// 이 매칭을 만든 게이트 기준 버전. 0 = 버전 도입 전(재검증 대상).
    var gateVersion: Int    = 0

    init(from match: PersistedRaceMatch) {
        self.activityID  = match.activityID.uuidString
        self.raceName    = match.raceName
        self.distanceKm  = match.distanceKm
        self.raceDate    = match.raceDate
        self.isConfirmed = match.isConfirmed
        self.isDismissed = match.isDismissed
        self.isManual    = match.isManual
        self.gateVersion = match.gateVersion ?? 0
    }

    var asPersistedRaceMatch: PersistedRaceMatch? {
        guard let id = UUID(uuidString: activityID) else { return nil }
        return PersistedRaceMatch(
            activityID: id,       raceName:    raceName,
            distanceKm: distanceKm, raceDate:  raceDate,
            isConfirmed: isConfirmed, isDismissed: isDismissed, isManual: isManual,
            gateVersion: gateVersion
        )
    }
}
