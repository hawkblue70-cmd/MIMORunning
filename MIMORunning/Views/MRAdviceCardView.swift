import SwiftUI

/// 조언 카드 — 큐 상위 2건. 탭하면 운동 목록과 근거가 펼쳐진다.
///
/// ⚠ 조언이 0건이면 카드를 그리지 않는다. "제안 없음" 문구 금지.
/// ⚠ record()는 여기 .onAppear에서만 호출한다. 판정 시점에 기록하면
///   화면에 뜬 적 없는 항목이 "보여줬다"로 기록돼 영영 노출되지 않는다.
struct MRAdviceCardView: View {
    @EnvironmentObject private var engine: MREngineStore
    @State private var expanded: Set<String> = []

    // 형제 카드(MRBacktestView 등)와 동일한 컨테이너 스타일
    private let cardColor = Theme.cardBackground

    private var items: [MRAdvice] { Array(engine.advice.prefix(2)) }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLanguage.shared.s("제안", "Suggestions"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                ForEach(items, id: \.key) { a in
                    row(a)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                engine.adviceLog.record(items.map(\.key), asOf: Date())
                MRAdviceLogStore.save(engine.adviceLog)
            }
            .onChange(of: items.map(\.key)) { _, keys in
                engine.adviceLog.record(keys, asOf: Date())
                MRAdviceLogStore.save(engine.adviceLog)
            }
        }
    }

    @ViewBuilder
    private func row(_ a: MRAdvice) -> some View {
        let open = expanded.contains(a.key)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Theme.violet).frame(width: 6, height: 6).padding(.top, 6)
                Text(a.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            }
            if open {
                if !a.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(a.exercises, id: \.self) { e in
                            Text("· " + e)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 14)
                }
                Text(a.rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) {
                if open { expanded.remove(a.key) } else { expanded.insert(a.key) }
            }
        }
    }
}
