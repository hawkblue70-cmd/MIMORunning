import Testing
import Foundation
@testable import MIMORunning

/// 걸음 수 → 케이던스 정리 — 200spm 초과를 모두 반으로 나눠 빠른 구간(5'04"/km · 205spm)이
/// 103spm이 되던 결함(2026-10-14) 회귀 방지. 두 배 겹침(300↑)만 반으로.
@Suite("구간 케이던스 반감 기준")
struct StepCadenceTests {
    @Test func fastRealCadenceKept() {
        #expect(HealthKitManager.normalizedStepCadence(205) == 205)
        #expect(HealthKitManager.normalizedStepCadence(248) == 248)
    }
    @Test func doubleCountedHalved() {
        #expect(HealthKitManager.normalizedStepCadence(380) == 190)
    }
    @Test func walkingTooLowDropped() {
        #expect(HealthKitManager.normalizedStepCadence(40) == nil)
    }
}
