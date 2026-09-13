import Foundation

/// 총평 한 줄 — 색점(톤) + 축 이름 + 짧은 상태어(관찰 사실, 등급어 아님).
struct RunSummaryLine: Equatable {
    enum Tone: Equatable { case good, neutral }
    let axis: String
    let state: String
    let tone: Tone
}
