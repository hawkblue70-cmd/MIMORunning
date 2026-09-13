import SwiftUI

/// 초반·중반·후반 표 — 페이스·심박·케이던스·보폭·접지. 폼 카드가 **이 컴포넌트 하나만** 쓴다(§5.8). scale=1 기준: 글자 9pt · 행 간격 5pt.
/// 판정: 케이던스·보폭·접지가 그 구간의 평소 범위에서 피로 방향(케이던스↓·보폭↓·접지↑)으로 벗어나면 `Theme.caution`, 아니면 지표 고유색. 페이스·심박은 판정 없음. 결측은 "–".
struct FormPhaseTableView: View {
    let result: FormPhase.Result
    var scale: CGFloat = 1.0
    /// 내보내기(촘촘 모드)면 행 간격 5→3
    @Environment(\.insightCompact) private var compact

    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 5 * scale, verticalSpacing: (compact ? 3 : 5) * scale) {
            GridRow {
                headerCell(L.s("구간", "Phase"))
                headerCell(L.s("페이스", "Pace")).gridColumnAlignment(.trailing)
                headerCell(L.s("심박", "HR")).gridColumnAlignment(.trailing)
                headerCell(L.s("케이던스", "Cadence")).gridColumnAlignment(.trailing)
                headerCell(L.s("보폭", "Stride")).gridColumnAlignment(.trailing)
                headerCell(L.s("지면접촉", "GCT")).gridColumnAlignment(.trailing)
            }
            row(ko: "초반", en: "Early", stats: result.phases.early, signals: result.signals.early)
            row(ko: "중반", en: "Mid", stats: result.phases.mid, signals: result.signals.mid)
            row(ko: "후반", en: "Late", stats: result.phases.late, signals: result.signals.late, isLate: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(ko: String, en: String, stats: FormPhase.PhaseStats, signals: FormPhase.Signals, isLate: Bool = false) -> some View {
        // 페이스 무너짐(§Insight/FormPhase.faded)도 후반 케이던스·보폭·접지 셀에 캐셔닝 — 기존 평소범위 이탈 신호와 OR.
        let fadedWorse: (FormPhase.Metric) -> Bool = { isLate && result.isFaded && result.lateWorsened($0) }
        GridRow {
            Text(phaseLabel(stats, ko: ko, en: en))
                .font(.system(size: 9 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 3 * scale)
                .padding(.vertical, 1 * scale)
            valueCell(paceText(stats.paceSecPerKm), color: Color.white.opacity(0.9), caution: false)
            valueCell(stats.avgHR.map { String(Int($0.rounded())) }, color: Theme.heartRate, caution: false)
            valueCell(stats.cadence.map { String(Int($0.rounded())) }, color: Theme.cadence, caution: signals.cadence == .below || fadedWorse(.cadence))
            valueCell(stats.stride.map { String(format: "%.2f", $0) }, color: Theme.strideLength, caution: signals.stride == .below || fadedWorse(.stride))
            valueCell(stats.groundContact.map { String(Int($0.rounded())) }, color: Theme.groundContact, caution: signals.groundContact == .above || fadedWorse(.groundContact))
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8 * scale))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, 3 * scale)
    }

    @ViewBuilder
    private func valueCell(_ text: String?, color: Color, caution: Bool) -> some View {
        Text(text ?? "–")
            .font(.system(size: 9 * scale))
            .foregroundStyle(text == nil ? Color.white.opacity(0.35) : (caution ? Theme.caution : color))
            .padding(.horizontal, 3 * scale)
            .padding(.vertical, 1 * scale)
            .background {
                if caution {
                    RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                        .fill(Theme.caution.opacity(0.18))
                }
            }
    }

    // MARK: - Formatting

    private func phaseLabel(_ p: FormPhase.PhaseStats, ko: String, en: String) -> String {
        let s = Int(p.startKm.rounded()), e = Int(p.endKm.rounded())
        return L.s("\(ko) \(s)~\(e)km", "\(en) \(s)–\(e) km")
    }

    private func paceText(_ sec: Double) -> String {
        let i = Int(sec.rounded())
        return String(format: "%d'%02d\"", i / 60, i % 60)
    }
}
