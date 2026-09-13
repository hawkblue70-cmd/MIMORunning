import SwiftUI

/// 인사이트 카드(리듬·폼·퍼포먼스)의 촘촘한 세로 간격 — 내보내기(미리보기 = 출력) 경로에서만 켠다.
/// 글자 크기·차트 크기는 그대로 두고 섹션 간격·여백·줄 간격만 줄인다(§5.8: 같은 컴포넌트, 값만 분기).
private struct InsightCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var insightCompact: Bool {
        get { self[InsightCompactKey.self] }
        set { self[InsightCompactKey.self] = newValue }
    }
}
