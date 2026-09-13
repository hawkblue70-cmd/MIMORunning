import Foundation
@testable import MIMORunning

/// `FormPhase.Result`가 `phases`/`signals`를 갖게 된 뒤, 문장·표시 테스트가 직접 초기화를 쓰지 않고
/// 이 스텁으로 결과를 만든다. 값 자체는 관계 문장 테스트가 아니라면 대개 의미가 없어 0/nil로 채운다.
extension FormPhase.Result {
    static func stub(early: FormPhase.Early? = nil, mid: FormPhase.Mid? = nil, late: FormPhase.Late,
                     earlyEnd: Double = 4, lateStart: Double = 12, total: Double = 16,
                     easyFrame: Bool = false) -> FormPhase.Result {
        func zeroed(startKm: Double, endKm: Double) -> FormPhase.PhaseStats {
            FormPhase.PhaseStats(splitCount: 0, startKm: startKm, endKm: endKm, paceSecPerKm: 0,
                                 cadence: nil, stride: nil, groundContact: nil, verticalOsc: nil, avgHR: nil)
        }
        let earlyStats = zeroed(startKm: 0, endKm: earlyEnd)
        let midStats = zeroed(startKm: earlyEnd, endKm: lateStart)
        let lateStats = zeroed(startKm: lateStart, endKm: total)
        let unknown = FormPhase.Signals(cadence: .unknown, stride: .unknown, groundContact: .unknown)
        return FormPhase.Result(early: early, mid: mid, late: late,
                                earlyEndKm: earlyEnd, lateStartKm: lateStart, totalKm: total,
                                phases: FormPhase.Phases(early: earlyStats, mid: midStats, late: lateStats),
                                signals: FormPhase.PhaseSignals(early: unknown, mid: unknown, late: unknown),
                                isEasyFrame: easyFrame)
    }
}
