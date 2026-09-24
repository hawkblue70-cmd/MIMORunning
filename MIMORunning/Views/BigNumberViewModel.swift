import SwiftUI

// MARK: - BigNumberViewModel
//
// BigNumber 카드(ShareCard.bigNumber)의 전용 상태 클래스.
// 영상 클립(athleticClipRecipes)은 AthleticViewModel과 공유 → athleticVM 참조.
//
// ShareCardView에서 @State var bigNumberVM = BigNumberViewModel() 로 보유.
//
// ⚠️ 이 파일은 BigNumber 카드 전용.
//    Athletic · OneLiner · Placeable · Sky · ECG · Ticket 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class BigNumberViewModel {

    var bigNumberShowMemo: Bool       = true
    var bigNumberAccent:   CardAccent = .violet
}
