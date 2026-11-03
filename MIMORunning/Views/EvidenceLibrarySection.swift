import SwiftUI

/// 나 탭 '근거 문헌' — 앱 판단이 기대는 문헌을 기능별로 한곳에(2026-11-03 사용자 제안: 카드마다 같은 문헌 줄을 보지 않게).
/// 기본 접힘, 펼침 상태는 저장하지 않는다. 목록은 `MREvidence.catalog` 하나 — 새 기능은 거기에 한 줄 더한다.
struct EvidenceLibrarySection: View {
    @State private var expanded = false

    var body: some View {
        let L = AppLanguage.shared
        let entries = MREvidence.catalog
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mrInk3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("근거 문헌", "Evidence", ja: "根拠となる文献"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(L.s("제안·판정이 기대는 연구 · \(entries.count)개 기능",
                                 "Research behind the suggestions · \(entries.count) features",
                                 ja: "提案・判定の根拠となる研究 · \(entries.count)機能"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mrInk3)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(L.s("연구 종류: 메타분석 · 무작위 연구 · 실험 연구 · 관찰 연구 · 리뷰·합의 · 코칭 관행. 값(페이스·거리·횟수)은 본인 기록에서 정합니다.",
                         "Study types: meta-analysis · randomized trial · experimental study · observational study · review/consensus · coaching practice. Values (pace, distance, frequency) come from your own records.",
                         ja: "研究の種類: メタ分析 · 無作為化試験 · 実験研究 · 観察研究 · レビュー・合意 · コーチングの慣行。値(ペース・距離・回数)はあなたの記録から決めます。"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mrInk3)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.feature)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        ForEach(e.cites, id: \.name) { c in
                            Text("· " + c.text)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mrInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}
