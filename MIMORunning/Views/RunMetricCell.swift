import SwiftUI

/// 러닝 지표 한 칸 — 앱 상세 격자와 공유 카드들이 **함께 쓰는** 단 하나의 셀.
///
/// ⚠ §5.8. 예전에는 같은 데이터를 네 곳에서 네 가지로 그렸다. 박스가 있는 곳과 없는 곳이
///   갈리고, 값 글꼴이 라운드 볼드·블랙 콘덴스드·세미볼드로 제각각이었다.
///   형태가 달라져도 **데이터 표시 속성은 같아야 한다** — 크기만 `scale`로 조정한다.
struct RunMetricCellStyle {
    /// 밝은 배경인가 — 셀 테두리를 그릴지 정한다(흰 셀은 밝은 배경에 묻힌다).
    let isLight: Bool
    let textPrimary: Color
    /// 셀 표면색
    let cellBackground: Color
    /// 셀 테두리 — 라이트에서만 옅게. 다크는 `.clear`.
    let cellBorder: Color

    static let appDark = RunMetricCellStyle(
        isLight: false, textPrimary: .white,
        cellBackground: Theme.cardBackground, cellBorder: .clear)

    static func light(textPrimary: Color, surface: Color = .white) -> RunMetricCellStyle {
        RunMetricCellStyle(isLight: true, textPrimary: textPrimary,
                           cellBackground: surface, cellBorder: .black.opacity(0.10))
    }

    static func dark(textPrimary: Color, surface: Color) -> RunMetricCellStyle {
        RunMetricCellStyle(isLight: false, textPrimary: textPrimary,
                           cellBackground: surface, cellBorder: .clear)
    }
}

/// scale = 1.0 기준값. 앱 상세 격자가 기준이고, 공유 카드는 이 값을 줄여 쓴다.
enum RunMetricCellMetrics {
    static let icon:    CGFloat = 11
    static let label:   CGFloat = 12
    static let value:   CGFloat = 20
    static let note:    CGFloat = 9
    static let padH:    CGFloat = 10
    static let padV:    CGFloat = 8
    static let corner:  CGFloat = 12
    /// 격자 열·행 간격 — 셀과 같은 비율로 줄어들어야 칸이 붙어 보이지 않는다.
    static let spacing: CGFloat = 8
}

struct RunMetricCell: View {
    let item: RunMetricItem
    let style: RunMetricCellStyle
    var scale: CGFloat = 1.0
    /// 값 아래 부연(유산소의 "현재 추정 · 높음") — 작은 카드에서는 자리가 없어 끈다.
    var showsNote: Bool = true

    private func s(_ v: CGFloat) -> CGFloat { v * scale }

    var body: some View {
        let m = RunMetricCellMetrics.self
        VStack(alignment: .leading, spacing: s(1)) {
            HStack(spacing: s(3)) {
                Image(systemName: item.icon)
                    .font(.system(size: s(m.icon), weight: .semibold))
                Text(item.label)
                    .font(.system(size: s(m.label), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(item.color)

            Text(item.value)
                .font(.system(size: s(item.compactValue ? m.value * 0.82 : m.value), weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(style.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if showsNote, let note = item.note {
                Text(note)
                    .font(.system(size: s(m.note)))
                    .foregroundStyle(style.textPrimary.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, s(m.padH))
        .padding(.vertical, s(m.padV))
        .background {
            let r = RoundedRectangle(cornerRadius: s(m.corner))
            r.fill(style.cellBackground)
                .overlay(r.stroke(style.cellBorder, lineWidth: style.isLight ? 0.5 : 0))
        }
    }
}

/// 지표 3열 격자 — 셀과 같은 비율로 간격이 줄어든다.
struct RunMetricGrid: View {
    let items: [RunMetricItem]
    let style: RunMetricCellStyle
    var scale: CGFloat = 1.0
    var showsNote: Bool = true

    var body: some View {
        let gap = RunMetricCellMetrics.spacing * scale
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 3),
                  alignment: .leading, spacing: gap) {
            ForEach(items) { item in
                RunMetricCell(item: item, style: style, scale: scale, showsNote: showsNote)
            }
        }
    }
}
