import SwiftUI

struct MRTodayCardView: View {
    @EnvironmentObject var engine: MREngineStore
    @AppStorage("distanceUnitMiles") private var useMiles = false

    /// 숫자와 단위를 따로 — 단위는 작고 흐리게 붙여 숫자가 또렷하게.
    /// 100 미만은 소수 1자리(주간에서 의미 있음), 그 이상은 정수 + 천 단위 콤마.
    private func distanceParts(km: Double) -> (number: String, unit: String) {
        let v = useMiles ? km * 0.621371 : km
        let unit = useMiles ? "mi" : "km"
        if v < 100 { return (String(format: "%.1f", v), unit) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: v)) ?? String(Int(v)), unit)
    }

    /// 아침 제안 색 — 초록(강도 OK)·노랑(이지런)·주황(휴식).
    private func readinessColor(_ level: MRReadiness.Level) -> Color {
        switch level {
        case .go:   return Theme.positive
        case .easy: return Theme.time
        case .rest: return Color(hex: "FF9A3C")
        }
    }

    var body: some View {
        if let c = engine.todayCard {
            VStack(alignment: .leading, spacing: 0) {

                // ① 쌓인 것 — 맨 위. 결과가 아니라 행동이 먼저다.
                //   Harkin 2016 (138 RCT, N=19,951):
                //   행동 모니터링 → 행동 변화 d+ = 0.79
                //   결과 모니터링 → 행동 변화 d+ = 0.17
                Text(c.streakLine)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                // 아침 제안 — 연속 줄 바로 아래 한 줄. 색은 판정별(초록/노랑/주황). 오늘 뛴 날엔 없다.
                if let line = c.readinessLine, let level = c.readinessLevel {
                    Text(line)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(readinessColor(level))
                        .padding(.top, 6)
                    // 둘째 줄 — 왜 그 판정인지 + 데이터. 판정 줄보다 작고 흐리게(12pt · 0.72).
                    if let detail = c.readinessDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                }
                // 거리 행 — 이번 주 · 이번 달 · 올해 · 누적. 0km 칸은 엔진에서 이미 빠져 있고
                // 남은 칸이 폭을 나눠 갖는다.
                //   라벨 mrInk2(0.72) / 값 mrInk1(흰) / 누적 값만 노랑 — 색 규칙 "노랑 = 실제로 한 것",
                //   한 자리에만. 누적은 레벨의 숫자다(NRC 블랙 = 5,000km).
                //   라벨·값을 한 단계 밝힘(0.45→0.72, 0.72→흰) — 연속 줄(흰 22pt) 바로 아래라 묻혔다.
                //   단위(km·mi)는 11pt·0.45로 낮춰 숫자가 또렷하게.
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(c.distanceCells.enumerated()), id: \.offset) { idx, cell in
                        let parts = distanceParts(km: cell.km)
                        DistanceCellView(label: cell.label, number: parts.number, unit: parts.unit,
                                         isTotal: idx == c.distanceCells.count - 1)
                    }
                }
                .padding(.top, 10)

                // ⚠ 구분선은 아래에 내용이 있을 때만 그린다.
                //   sessionLine과 linkLine이 둘 다 nil이면(안 뛴 날 + 등록 대회 없음)
                //   빈 구분선이 남아 카드 아래쪽이 텅 빈다.
                if c.sessionLine != nil || c.linkLine != nil {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.vertical, 18)

                    // ② 오늘 기록 — 오늘 뛴 날에만.
                    //   어제 러닝을 매일 보는 건 아래 목록과 중복이다.
                    if let session = c.sessionLine {
                        // 한 줄 고정 — "6.07km · 39:41 · 6'32"/km"이 26pt로는 카드 폭을 넘어
                        // 페이스만 둘째 줄로 떨어졌다. 줄을 바꾸는 대신 줄여서 맞춘다(최소 70%).
                        Text(session)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if let link = c.linkLine {
                        Text(link)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.98))
                            .padding(.top, c.sessionLine != nil ? 8 : 0)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onChange(of: AppLanguage.shared.isEnglish) { _, _ in
                engine.recomputeTodayCard()
            }
        }
    }
}

/// 거리 행의 칸 하나 — 라벨 / 숫자 + 작은 단위. 본문에서 빼낸 이유는 타입체크 시간(한 식에 넣으면 컴파일 실패).
private struct DistanceCellView: View {
    let label: String
    let number: String
    let unit: String
    let isTotal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.mrInk2)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(number)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isTotal ? Theme.time : Color.mrInk1)
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.mrInk3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
