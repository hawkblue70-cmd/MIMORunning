import SwiftUI
import Combine

// MARK: - RestDayTemplate

enum RestDayTemplate: String, CaseIterable {
    case story = "스토리"
    case video = "영상"
    case slide = "슬라이드"
}

// MARK: - RestDayLoadGuard
// @StateObject: 뷰 생존 기간 동안 유지, re-render에 재설정 안 됨.
// @State보다 확실하게 loadEntry 1회 보장 (배칭 타이밍 이슈 없음).
final class RestDayLoadGuard: ObservableObject {
    @Published var hasLoaded = false
}

// MARK: - RestDayExportError

enum RestDayExportError: Error {
    case clipNotFound   // 임시 파일 삭제됨 + assetIdentifier/storedPhotoRef 없음
}

// MARK: - PerModeRecipeStore

struct PerModeRecipeStore: Codable {
    var story:      SavedRecipeSet?
    var video:      SavedRecipeSet?
    var slide:      SavedRecipeSet?
    var activeMode: String   // RestDayTemplate.rawValue: "스토리" | "영상" | "슬라이드"
}
