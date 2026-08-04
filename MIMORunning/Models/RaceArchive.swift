import Foundation
import SwiftData

/// 대회 후 생성되는 아카이브.
/// markdown 하나만 읽어서 그대로 렌더한다. 파싱 금지.
@Model final class RaceArchive {
    var raceDate: Date = Date()
    var raceName: String = ""
    var distanceM: Double = 0
    var createdAt: Date = Date()
    var markdown: String = ""
    var hasResult: Bool = true
    var actualMin: Double = 0                  // 실제 기록 (분). hasResult=false면 0
    var snapshotProjectedFinalMin: Double = 0  // 계획 시작 시점 예측 — 백테스트 행에 표시
    var reconstructed: Bool = false            // true = 소급 재구성 (당시 앱 예측 아님)

    init(raceDate: Date, raceName: String, distanceM: Double,
         markdown: String, hasResult: Bool, actualMin: Double,
         snapshotProjectedFinalMin: Double, reconstructed: Bool = false) {
        self.raceDate = raceDate
        self.raceName = raceName
        self.distanceM = distanceM
        self.createdAt = Date()
        self.markdown = markdown
        self.hasResult = hasResult
        self.actualMin = actualMin
        self.snapshotProjectedFinalMin = snapshotProjectedFinalMin
        self.reconstructed = reconstructed
    }
}
