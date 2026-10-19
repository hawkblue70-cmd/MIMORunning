import SwiftUI
import WeatherKit

/// WeatherKit 사용 조건인 출처 표기 — Apple 날씨 표장(다크 화면용 마크)과 법적 고지 페이지 링크.
/// 표장·링크는 Apple이 내려주는 값을 그대로 쓴다(주소를 박아 두지 않음). 받기 전·실패 시엔 글자로 대신한다.
struct WeatherAttributionView: View {
    @State private var attribution: WeatherAttribution?

    var body: some View {
        Group {
            if let a = attribution {
                Link(destination: a.legalPageURL) {
                    AsyncImage(url: a.combinedMarkDarkURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(a.serviceName).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(height: 12)
                }
                .accessibilityLabel(a.serviceName)
            } else {
                Text("Apple Weather").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            attribution = try? await WeatherService.shared.attribution
        }
    }
}
