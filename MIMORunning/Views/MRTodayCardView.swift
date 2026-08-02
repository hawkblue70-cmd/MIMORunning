import SwiftUI

struct MRTodayCardView: View {
    @EnvironmentObject var engine: MREngineStore
    @State private var showBasis = false

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
                Text(c.cumulativeLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 4)

                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 18)

                // ② 오늘 + 목표 연결
                Text(c.headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let link = c.linkLine {
                    Text(link)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.98))
                        .padding(.top, 8)
                }

                // ③ 짚어보기 — 없으면 아무것도 그리지 않는다.
                //   "특별한 조언 없음" 같은 문구를 넣지 말 것.
                //   빈 자리를 결핍으로 만들지 않기 위해서다.
                if let obs = c.observation {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.vertical, 18)

                    Text(obs)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let basis = c.observationBasis {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { showBasis.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(showBasis ? "근거 접기" : "왜 이렇게 나왔나요")
                                Image(systemName: showBasis ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.top, 10)

                        if showBasis {
                            Text(basis)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.top, 6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
