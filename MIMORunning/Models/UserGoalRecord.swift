import SwiftData

/// 목표 기록 (10K·하프·풀) — CloudKit 동기화로 기기 간 공유
@Model final class UserGoalRecord {
    var tenKGoal:  String = ""
    var halfGoal:  String = ""
    var fullGoal:  String = ""

    init() {}
}
