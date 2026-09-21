import SwiftUI

/// 경로 영상 인터벌 회차 보드 — 미리보기·출력이 **이 뷰 하나**를 쓴다(§5.8).
/// `revealed`: 보이는 회차 수(0…reps.count). 보이지 않는 줄은 투명(opacity 0)으로 자리를 지킨다 —
/// 줄이 나타나도 레이아웃이 움직이지 않고, 출력에서 "뼈대만"과 "줄만" 두 렌더가 같은 위치를 갖는다.
/// `renderMode`: `.full`(미리보기) / `.chromeOnly`(머리글·배경만, 줄은 투명) / `.rowsOnly`(줄만, 나머지 투명).
struct IntervalRepBoardView: View {
    enum RenderMode { case full, chromeOnly, rowsOnly }

    let board: IntervalRepBoard
    var revealed: Int
    var renderMode: RenderMode = .full
    var scale: CGFloat = 1.0

    private var L: AppLanguage { AppLanguage.shared }

    // 열 폭(scale=1): 회차 22 · 거리 40 · 페이스 44 · 심박 30
    private var idxW: CGFloat { 22 * scale }
    private var distW: CGFloat { 40 * scale }
    private var paceW: CGFloat { 44 * scale }
    private var hrW: CGFloat { 30 * scale }
    private var colGap: CGFloat { 10 * scale }

    private var chromeOpacity: Double { renderMode == .rowsOnly ? 0 : 1 }
    private func rowOpacity(_ rep: IntervalRepBoard.Rep) -> Double {
        switch renderMode {
        case .chromeOnly: return 0
        case .rowsOnly:   return 1          // 출력은 마스크로 드러내므로 전부 그린다
        case .full:       return rep.index <= revealed ? 1 : 0
        }
    }
    private var footerOpacity: Double {
        switch renderMode {
        case .chromeOnly: return 0
        case .rowsOnly:   return 1
        case .full:       return revealed >= board.reps.count ? 1 : 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 머리글: "5 × 1km"
            Text(board.headerText)
                .font(.system(size: 9 * scale, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.bottom, 3 * scale)
                .opacity(chromeOpacity)

            // 회차 줄 — 열 하나 또는 쌍
            let pairs = stride(from: 0, to: board.reps.count, by: board.columns).map { i in
                Array(board.reps[i..<min(i + board.columns, board.reps.count)])
            }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, group in
                HStack(spacing: colGap) {
                    ForEach(group, id: \.index) { rep in
                        row(rep).opacity(rowOpacity(rep))
                    }
                }
                .padding(.vertical, 2 * scale)
            }

            // 바닥글: "평균 4'52"" — 마지막 회차와 함께
            if let footer = board.footerText {
                Text(footer)
                    .font(.system(size: 10 * scale, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.positive)
                    .padding(.vertical, 2 * scale)
                    .opacity(footerOpacity)
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .background(
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .opacity(chromeOpacity)
        )
        .fixedSize()
    }

    @ViewBuilder
    private func row(_ rep: IntervalRepBoard.Rep) -> some View {
        HStack(spacing: 0) {
            Text("\(rep.index)")
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: idxW, alignment: .leading)
            if board.showsDistanceColumn {
                Text(rep.distanceM.map { IntervalRepBoard.distanceLabel($0) } ?? "–")
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(width: distW, alignment: .leading)
            }
            Text(rep.paceSecPerKm.map { IntervalRepBoard.paceText($0) } ?? "–")
                .foregroundStyle(Color.white)
                .frame(width: paceW, alignment: .leading)
            Text(rep.avgHeartRate.map { "\($0)" } ?? "–")
                .foregroundStyle(Theme.heartRate)
                .frame(width: hrW, alignment: .trailing)
        }
        .font(.system(size: 10 * scale, weight: .medium).monospacedDigit())
    }
}
