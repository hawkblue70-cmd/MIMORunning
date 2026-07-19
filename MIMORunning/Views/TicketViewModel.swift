import SwiftUI

// MARK: - TicketViewModel
//
// Ticket 카드(cardIndex == 6)의 전용 상태 클래스.
// ShareCardView에서 @State var ticketVM = TicketViewModel() 로 보유.
//
// ⚠️ 이 파일은 Ticket 카드 전용.
//    Athletic · OneLiner · Placeable · BigNumber · Sky · ECG 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class TicketViewModel {

    var ticketDepartureName: String     = "RUN"
    /// 레이스 티켓은 gold 고정 — 이 값은 일반 티켓에만 적용.
    var ticketAccent:        CardAccent = .none
}
