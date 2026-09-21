import SwiftUI

/// 경로 1 영상 인터벌 회차 보드 — 미리보기·출력이 **이 뷰 하나**를 쓴다(§5.8).
/// 글자는 왼쪽 열 러닝 데이터(9pt medium)보다 한 단계 크고 굵게(줄 10pt bold · 머리글/바닥글 10pt semibold), 음영·배경 없음.
/// 회차 9개부터 두 열(쌍)로 나누고 심박 칸을 뺀다 — 높이는 스크림 안에, 폭은 오른쪽 스탬프 앞에서 멈추게.
/// `revealed`: 보이는 회차 수(0…reps.count). 보이지 않는 줄은 투명(opacity 0)으로 자리를 지킨다 —
/// 줄이 나타나도 레이아웃이 움직이지 않고, 출력에서 "뼈대만"과 "줄만" 두 렌더가 같은 위치를 갖는다.
/// `renderMode`: `.full`(미리보기) / `.chromeOnly`(머리글·배경만, 줄은 투명) / `.rowsOnly`(줄만, 나머지 투명).
struct IntervalRepBoardView: View {
    enum RenderMode { case full, chromeOnly, rowsOnly }

    let board: IntervalRepBoard
    /// 경로 진행 비율(0…1) — 회차·준비·정리 줄이 보일지 이 값으로 정한다
    var progress: CGFloat
    var renderMode: RenderMode = .full
    var scale: CGFloat = 1.0

    private var revealed: Int { board.revealedCount(progress: progress) }

    private var L: AppLanguage { AppLanguage.shared }

    // 열 폭(scale=1): 회차 22 · 거리 40 · 페이스 44 · 심박 30
    // 열 폭(scale=1): 회차 20("준비"·"정리" 두 글자) · 거리 36 · 페이스 38 · 심박 28.
    // 한 열이면 20+38+28 = 86, 두 열(심박 없음)이면 (20+38)×2+6 = 122 — 경로 1 왼쪽 열 옆 스탬프에 닿지 않는 폭.
    private var idxW: CGFloat { 20 * scale }
    private var distW: CGFloat { 36 * scale }
    private var paceW: CGFloat { 38 * scale }
    private var hrW: CGFloat { 28 * scale }
    private var colGap: CGFloat { 6 * scale }
    /// 두 열이면 심박 칸을 뺀다 — 폭이 왼쳌 열을 넘어 스탬프와 겹치기 때문
    private var showsHR: Bool { board.columns == 1 }
    private var rowFont: Font { .system(size: 10 * scale, weight: .bold).monospacedDigit() }

    private var chromeOpacity: Double { renderMode == .rowsOnly ? 0 : 1 }
    private func rowOpacity(_ rep: IntervalRepBoard.Rep) -> Double {
        switch renderMode {
        case .chromeOnly: return 0
        case .rowsOnly:   return 1          // 출력은 마스크로 드러내므로 전부 그린다
        case .full:       return rep.index <= revealed ? 1 : 0
        }
    }
    private func edgeOpacity(_ edge: IntervalRepBoard.Edge?) -> Double {
        switch renderMode {
        case .chromeOnly: return 0
        case .rowsOnly:   return 1
        case .full:       return board.isRevealed(edge, progress: progress) ? 1 : 0
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
                .font(.system(size: 10 * scale, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.bottom, 2 * scale)
                .opacity(chromeOpacity)

            // 준비운동 줄 — 회차 앞
            if let w = board.warmup {
                edgeRow(L.s("준비", "WU"), w).opacity(edgeOpacity(w)).padding(.vertical, 1 * scale)
            }

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
                .padding(.vertical, 1 * scale)
            }

            // 정리운동 줄 — 회차 뒤, 그 구간 끝(대개 마지막 프레임)에
            if let c = board.cooldown {
                edgeRow(L.s("정리", "CD"), c).opacity(edgeOpacity(c)).padding(.vertical, 1 * scale)
            }

            // 바닥글: "평균 4'52"" — 마지막 회차와 함께
            if let footer = board.footerText {
                Text(footer)
                    .font(.system(size: 10 * scale, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.vertical, 1 * scale)
                    .opacity(footerOpacity)
            }
        }
        .fixedSize()
    }

    /// 준비·정리 줄 — 회차 줄과 같은 열 폭, 번호 자리에 "준비"/"정리"
    @ViewBuilder
    private func edgeRow(_ label: String, _ e: IntervalRepBoard.Edge) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: idxW, alignment: .leading)
            if board.showsDistanceColumn {
                Text(e.distanceM.map { IntervalRepBoard.distanceLabel($0) } ?? "–")
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: distW, alignment: .leading)
            }
            Text(e.paceSecPerKm.map { IntervalRepBoard.paceText($0) } ?? "–")
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: paceW, alignment: .leading)
            if showsHR {
                Text(e.avgHeartRate.map { "\($0)" } ?? "–")
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: hrW, alignment: .trailing)
            }
        }
        .font(rowFont)
    }

    @ViewBuilder
    private func row(_ rep: IntervalRepBoard.Rep) -> some View {
        HStack(spacing: 0) {
            Text("\(rep.index)")
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: idxW, alignment: .leading)
            if board.showsDistanceColumn {
                Text(rep.distanceM.map { IntervalRepBoard.distanceLabel($0) } ?? "–")
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: distW, alignment: .leading)
            }
            Text(rep.paceSecPerKm.map { IntervalRepBoard.paceText($0) } ?? "–")
                .foregroundStyle(Color.white)
                .frame(width: paceW, alignment: .leading)
            if showsHR {
                Text(rep.avgHeartRate.map { "\($0)" } ?? "–")
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: hrW, alignment: .trailing)
            }
        }
        .font(rowFont)
    }
}
