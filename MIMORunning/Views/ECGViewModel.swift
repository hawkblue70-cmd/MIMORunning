import SwiftUI

// MARK: - ECGViewModel
//
// ECG 카드(cardIndex == 5)의 전용 상태 클래스.
// ShareCardView에서 @State var ecgVM = ECGViewModel() 로 보유.
//
// ⚠️ 이 파일은 ECG 카드 전용.
//    Athletic · OneLiner · Placeable · BigNumber · Sky · Ticket 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class ECGViewModel {

    var paceWaveform:    ECGWaveform? = nil
    var hrWaveform:      ECGWaveform? = nil
    var ecgShowPace:     Bool         = true
    var ecgDataAvailable: Bool?       = nil
    var ecgAccent:       CardAccent   = .violet
}
