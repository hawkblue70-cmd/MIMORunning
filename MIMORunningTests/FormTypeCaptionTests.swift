import Testing
import Foundation
@testable import MIMORunning

/// 러닝 유형별 캡션(인사이트 탭·폼 카드 공용) + 두 카드가 공유하는 지표 상태 판정.
/// 문자열 검사는 `AppLanguage.shared`를 건드리므로 직렬 실행.
@Suite("FormNarrative 유형별 캡션·상태 판정", .serialized)
struct FormTypeCaptionTests {

    private func ko<T>(_ body: () -> T) -> T {
        AppLanguage.shared.isEnglish = false
        return body()
    }

    // MARK: - 유형 그룹

    @Test func plannedFastFinishCoversBuildUpTempoRaceOnly() {
        #expect(FormNarrative.isPlannedFastFinish(.buildUp))
        #expect(FormNarrative.isPlannedFastFinish(.tempo))
        #expect(FormNarrative.isPlannedFastFinish(.race))
        for t: WorkoutType in [.easy, .general, .longRun, .lsd, .distanceRun, .interval] {
            #expect(!FormNarrative.isPlannedFastFinish(t), "\(t)")
        }
    }

    @Test func plannedHighIntensityAddsInterval() {
        #expect(FormNarrative.isPlannedHighIntensity(.interval))
        #expect(FormNarrative.isPlannedHighIntensity(.buildUp))
        #expect(FormNarrative.isPlannedHighIntensity(.distanceRun))   // 레이스페이스 장거리 — 고강도가 계획
        #expect(!FormNarrative.isPlannedHighIntensity(.easy))
        #expect(!FormNarrative.isPlannedHighIntensity(.longRun))
    }

    // MARK: - 심박 차트 캡션

    @Test func hrRiseCaptionOnlyBuildUpGetsPrefix() {
        ko {
            #expect(FormNarrative.hrSecondHalfRiseCaption(type: .buildUp) == "빌드업답게 후반에 심박이 올라갔어요")
            for t: WorkoutType in [.tempo, .race, .interval, .easy, .general, .longRun] {
                #expect(FormNarrative.hrSecondHalfRiseCaption(type: t) == "후반에 심박이 올랐어요", "\(t)")
            }
        }
    }

    // MARK: - 심박존 캡션 · 한 줄 요약

    @Test func zoneCaptionPlannedTypesSayAsPlanned() {
        ko {
            for t: WorkoutType in [.buildUp, .tempo, .race, .interval] {
                #expect(FormNarrative.highIntensityZoneCaption(type: t) == "계획대로 고강도 구간이 많았어요", "\(t)")
            }
            #expect(FormNarrative.highIntensityZoneCaption(type: .easy) == "고강도 구간이 많았어요")
            #expect(FormNarrative.highIntensityZoneCaption(type: .general) == "고강도 구간이 많았어요")
        }
    }

    @Test func oneLinerKeepsAdviceAndAddsAsPlanned() {
        ko {
            #expect(FormNarrative.highIntensityOneLiner(type: .buildUp) == "계획대로 고강도 구간이 많았어요. 다음엔 여유롭게 가도 좋아요")
            #expect(FormNarrative.highIntensityOneLiner(type: .easy) == "고강도 구간이 많았어요. 다음엔 여유롭게 가도 좋아요")
        }
    }

    // MARK: - 폼 유지 알약

    @Test func formHeldCaptionFastFinishVsLong() {
        ko {
            for t: WorkoutType in [.buildUp, .tempo, .race] {
                #expect(FormNarrative.formHeldCaption(type: t) == "후반 가속에도 폼이 버텼어요", "\(t)")
            }
            for t: WorkoutType in [.longRun, .lsd, .distanceRun, .general, .easy] {
                #expect(FormNarrative.formHeldCaption(type: t) == "장거리인데 후반까지 폼이 버텼어요", "\(t)")
            }
        }
    }

    // MARK: - km별 차트 주석

    @Test func belowRangeNoteFastTypesExplainPace() {
        ko {
            #expect(FormNarrative.belowRangeNote(type: .buildUp, metric: .groundContact) == "후반 페이스가 빨라 범위 아래에 머물러요")
            #expect(FormNarrative.belowRangeNote(type: .tempo, metric: .cadence) == "후반 페이스가 빨라 범위를 벗어났어요")
            #expect(FormNarrative.belowRangeNote(type: .race, metric: .stride) == "후반 페이스가 빨라 범위를 벗어났어요")
        }
    }

    @Test func belowRangeNoteLongTypesUnchanged() {
        ko {
            for t: WorkoutType in [.longRun, .lsd, .distanceRun, .general, .easy] {
                #expect(FormNarrative.belowRangeNote(type: t, metric: .groundContact) == "장거리라 평소 범위 아래에 머물러요", "\(t)")
                #expect(FormNarrative.belowRangeNote(type: t, metric: .cadence) == "장거리라 평소 범위 아래에 머물러요", "\(t)")
            }
        }
    }

    @Test func captionsHaveEnglish() {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        #expect(FormNarrative.hrSecondHalfRiseCaption(type: .buildUp).contains("build-up"))
        #expect(FormNarrative.highIntensityZoneCaption(type: .tempo).contains("as planned"))
        #expect(FormNarrative.formHeldCaption(type: .race).contains("fast finish"))
        #expect(FormNarrative.belowRangeNote(type: .buildUp, metric: .groundContact).contains("Faster late pace"))
    }

    // MARK: - 상태 판정 (표시 정밀도 반올림)

    private func stat(median: Double, sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }

    @Test func statusRoundsCadenceBoundsToDisplayPrecision() {
        // lower = 176 − 1.2×5 = 170.0 정확히 → 170은 범위 안. lower가 170.4여도 표시상 170 → 범위 안
        let s = stat(median: 176.4, sd: 5)          // lower 170.4, upper 182.4
        #expect(FormNarrative.status(rawValue: 170, stat: s, metric: .cadence) == .inRange)
        #expect(FormNarrative.status(rawValue: 169, stat: s, metric: .cadence) == .below)
        #expect(FormNarrative.status(rawValue: 182, stat: s, metric: .cadence) == .inRange)
        #expect(FormNarrative.status(rawValue: 183, stat: s, metric: .cadence) == .above)
    }

    @Test func statusStrideUsesTwoDecimals() {
        let s = stat(median: 1.10, sd: 0.05)         // lower 1.04, upper 1.16
        #expect(FormNarrative.status(rawValue: 1.044, stat: s, metric: .stride) == .inRange)
        #expect(FormNarrative.status(rawValue: 1.034, stat: s, metric: .stride) == .below)
        #expect(FormNarrative.status(rawValue: 1.164, stat: s, metric: .stride) == .inRange)
        #expect(FormNarrative.status(rawValue: 1.166, stat: s, metric: .stride) == .above)
    }

    @Test func statusUnknownWhenMissing() {
        #expect(FormNarrative.status(rawValue: nil, stat: stat(median: 1, sd: 1), metric: .cadence) == .unknown)
        #expect(FormNarrative.status(rawValue: 1, stat: nil, metric: .cadence) == .unknown)
    }

    @Test func roundedDisplayPerMetric() {
        #expect(FormNarrative.roundedDisplay(176.6, metric: .cadence) == 177)
        #expect(FormNarrative.roundedDisplay(240.4, metric: .groundContact) == 240)
        #expect(FormNarrative.roundedDisplay(1.126, metric: .stride) == 1.13)
        #expect(FormNarrative.roundedDisplay(8.26, metric: .verticalOsc) == 8.3)
    }

    // MARK: - GCT 시점 보정

    private func gctShift(recentMean: Double, r2: Double?) -> MRFormShift {
        let m = mrFormMetrics.first { $0.key == "gct" }!
        return MRFormShift(metric: m, recentMean: recentMean, baseMean: 0, delta: recentMean,
                           mdc: 2, weeksConsistent: 4, r2: r2)
    }

    @Test func gctDriftAppliesWhenConditionsMet() {
        // 열람 시점 잔차 −6, baseline 잔차 +2 → drift −8ms
        let d = FormNarrative.gctDrift(baselineResidualMean: 2, gctShift: gctShift(recentMean: -6, r2: 0.5))
        #expect(d == -8)
        let s = FormNarrative.driftAdjustedGCT(stat(median: 250, sd: 10), baselineResidualMean: 2,
                                               gctShift: gctShift(recentMean: -6, r2: 0.5))
        #expect(s?.median == 242)
        #expect(s?.sd == 10)
    }

    @Test func gctDriftGuards() {
        let st = stat(median: 250, sd: 10)
        // shift 없음
        #expect(FormNarrative.gctDrift(baselineResidualMean: 2, gctShift: nil) == nil)
        // R² < 0.2
        #expect(FormNarrative.gctDrift(baselineResidualMean: 2, gctShift: gctShift(recentMean: -6, r2: 0.1)) == nil)
        // |drift| < 2
        #expect(FormNarrative.gctDrift(baselineResidualMean: 2, gctShift: gctShift(recentMean: 0.5, r2: 0.5)) == nil)
        // 클램프 ±15
        #expect(FormNarrative.gctDrift(baselineResidualMean: 0, gctShift: gctShift(recentMean: -30, r2: 0.5)) == -15)
        // 조건 미충족이면 원본 그대로
        #expect(FormNarrative.driftAdjustedGCT(st, baselineResidualMean: nil, gctShift: nil)?.median == 250)
        #expect(FormNarrative.driftAdjustedGCT(nil, baselineResidualMean: 2, gctShift: gctShift(recentMean: -6, r2: 0.5)) == nil)
    }

    // MARK: - 심폐 효율 비교 게이트 (RunInsightEngine)

    @Test func efficiencyComparisonExcludesBuildUpAndInterval() {
        #expect(!RunInsightEngine.efficiencyComparisonApplies(to: .buildUp))
        #expect(!RunInsightEngine.efficiencyComparisonApplies(to: .interval))
        for t: WorkoutType in [.easy, .general, .tempo, .race, .longRun, .lsd, .distanceRun] {
            #expect(RunInsightEngine.efficiencyComparisonApplies(to: t), "\(t)")
        }
    }

    // MARK: - 러닝별 잔차 조회 (추세 문단 마무리 배선)

    @Test func runResidualMatchesSameDayAndFeedsTail() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let residuals = [
            MRFormResidual(date: cal.date(byAdding: .day, value: -3, to: day)!, value: -4),
            MRFormResidual(date: day, value: 1.5),
            MRFormResidual(date: cal.date(byAdding: .day, value: 2, to: day)!, value: 3),
        ]
        // 같은 날의 다른 시각으로 조회해도 그 날 잔차
        let r = mrFormRunResidual(residuals, on: day.addingTimeInterval(9 * 3600))
        #expect(r == 1.5)
        #expect(mrFormRunResidual(residuals, on: cal.date(byAdding: .day, value: 10, to: day)!) == nil)

        // 잔차를 mrFormObservation에 넘기면 마무리 문장이 붙는다
        let cadM = mrFormMetrics.first { $0.key == "cadence" }!
        let gctM = mrFormMetrics.first { $0.key == "gct" }!
        let cad = MRFormShift(metric: cadM, recentMean: 1.0, baseMean: -2.0, delta: 3.0, mdc: 1.0, weeksConsistent: 4, r2: nil)
        let gct = MRFormShift(metric: gctM, recentMean: -8, baseMean: 0, delta: -8, mdc: 2.0, weeksConsistent: 4, r2: nil)
        let text = ko { mrFormObservation([cad, gct], refCadence: 170, runCadenceResidual: r)?.text ?? "" }
        #expect(text.hasSuffix("이 러닝도 그 흐름 위에 있어요."))
    }
}
