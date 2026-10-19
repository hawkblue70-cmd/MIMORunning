import SwiftUI

/// 크루 만들기·참여 버튼 바로 위 안내 — 버튼을 누르는 순간 닉네임·기간 거리가 공개 CloudKit에 올라간다.
/// 동의 버튼이 아니라 알림(사용자가 요청한 기능이라 별도 동의 불요) + 방침 11장 링크(2026-10-19).
struct CrewPrivacyNote: View {
    private var text: AttributedString {
        let L = AppLanguage.shared
        let url = L.s("https://mimoplanner.kr/privacy.html#running",
                      "https://mimoplanner.kr/en/privacy.html#running",
                      ja: "https://mimoplanner.kr/ja/privacy.html#running")
        let md = L.s("닉네임과 기간 러닝 거리는 같은 크루 멤버에게 보입니다. 경로·페이스·심박은 올라가지 않습니다. [개인정보처리방침](\(url))",
                     "Your nickname and running distance for the period are visible to members of the same crew. Routes, pace and heart rate are not uploaded. [Privacy Policy](\(url))",
                     ja: "ニックネームと期間のランニング距離は同じクルーのメンバーに表示されます。ルート・ペース・心拍数はアップロードされません。[プライバシーポリシー](\(url))")
        return (try? AttributedString(markdown: md)) ?? AttributedString(md)
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .tint(Theme.violetText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
    }
}
