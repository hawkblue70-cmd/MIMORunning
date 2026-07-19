import SwiftUI

// MARK: - SkyViewModel
//
// Sky 카드(cardIndex == 4)의 전용 상태 클래스.
// ShareCardView에서 @State var skyVM = SkyViewModel() 로 보유.
//
// ⚠️ 이 파일은 Sky 카드 전용.
//    Athletic · OneLiner · Placeable · BigNumber · ECG · Ticket 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class SkyViewModel {

    var skyAccent: CardAccent = .none
}
