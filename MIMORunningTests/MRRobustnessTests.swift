import XCTest
@testable import MIMORunning

final class MRRobustnessTests: XCTestCase {

    /// 합성 워크아웃 생성기
    func makeRuns(count: Int, km: Double, paceSecPerKm: Double,
                  hr: Double?, temp: Double?, endingDaysAgo: Int = 0,
                  everyNDays: Int = 2) -> [MRWorkout] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: -endingDaysAgo, to: Date())!
        return (0..<count).map { i in
            let d = cal.date(byAdding: .day, value: -i * everyNDays, to: end)!
            return MRWorkout(start: d, durationMin: km * paceSecPerKm / 60,
                             distanceKm: km, hrAvg: hr, hrMax: hr.map { $0 + 25 },
                             tempC: temp, humidity: nil, indoor: false,
                             isInterval: false)
        }.reversed()
    }

    // MARK: ① 데이터가 아예 없는 사람

    func testEmpty() {
        let phys = mrPhysiology(runs: [], restingHRSamples: [],
                                dateOfBirth: nil, sex: .unknown, asOf: Date())
        XCTAssertNil(phys.hrMax)
        XCTAssertNil(phys.lt1HR)

        let efforts = mrDetectEfforts(runs: [], phys: phys)
        XCTAssertTrue(efforts.isEmpty)

        let fit = mrFitExponent(efforts)
        XCTAssertFalse(fit.ok)

        let prof = mrProfile(runs: [], efforts: [], asOf: Date())
        let preds = mrPredict(efforts: [], fit: fit, profile: prof,
                              heat: MRHeatModel(), asOf: Date())
        // ★ 0:00을 만들어내면 안 된다. 아예 비어 있어야 한다.
        XCTAssertTrue(preds.isEmpty, "데이터가 없으면 예측을 만들지 않아야 한다")
    }

    // MARK: ② 진짜 초보 — 파이프라인 생존 확인 + 레벨 판정

    func testBeginner() {
        // ⚠ 임계값에 딱 걸리지 않게 만든다.
        //   30회 × 4km / 3일 간격은 km12=10.0 (임계 10), ta=0.246 (임계 0.25)로
        //   양쪽 다 경계에 붙어 있어 부동소수점에 흔들린다.
        //   진짜 초보(주 5km 미만, 6주차)로 명확히 잡는다.
        let runs = makeRuns(count: 12, km: 3, paceSecPerKm: 450,
                            hr: 155, temp: 18, everyNDays: 4)   // 6주 · 주 6km
        let phys = mrPhysiology(runs: runs, restingHRSamples: [],
                                dateOfBirth: Calendar.current.date(byAdding: .year, value: -35, to: Date()),
                                sex: .male, asOf: Date())
        // HRmax 관측이 10건 미만이거나 공식 폴백이어도 죽지 않아야 한다
        XCTAssertNotNil(phys.hrMax)
        XCTAssertNotNil(phys.lt1HR)

        let prof = mrProfileFull(runs: runs, efforts: [], firstDataDate: runs.first?.date,
                                 dateOfBirth: nil, hasGoalTime: false,
                                 hasGoalRace: false, asOf: Date())
        XCTAssertEqual(prof.level, "초보")
        // ★ 대회도 목표도 없으면 건강 모드여야 한다
        XCTAssertEqual(prof.mode, "health")
    }

    /// 3개월 · 주 10km — 초보와 하수의 경계.
    /// 여기가 흔들리면 레벨 판정 임계값을 손봤다는 뜻이다.
    func testBeginnerToNoviceBoundary() {
        let runs = makeRuns(count: 30, km: 4, paceSecPerKm: 420,
                            hr: 155, temp: 18, everyNDays: 3)
        let prof = mrProfileFull(runs: runs, efforts: [], firstDataDate: runs.first?.date,
                                 dateOfBirth: nil, hasGoalTime: false,
                                 hasGoalRace: false, asOf: Date())
        XCTAssertEqual(prof.level, "하수", "km12=10.0·ses12=2.5로 2/3 충족")
    }

    // MARK: ③ 심박 데이터가 전혀 없는 사람 (구형 기기 / 시계 미착용)

    func testNoHeartRate() {
        let runs = makeRuns(count: 100, km: 8, paceSecPerKm: 330,
                            hr: nil, temp: 15)
        let phys = mrPhysiology(runs: runs, restingHRSamples: [],
                                dateOfBirth: Calendar.current.date(byAdding: .year, value: -45, to: Date()),
                                sex: .male, asOf: Date())
        // 공식 폴백으로 HRmax는 나오되 신뢰도가 낮아야 한다
        XCTAssertEqual(phys.hrMax?.confidence, .low)

        // ★ 심박이 없어도 노력 감지와 예측이 돌아가야 한다
        let efforts = mrDetectEfforts(runs: runs, phys: phys)
        XCTAssertFalse(efforts.isEmpty, "심박이 없어도 거리 기반으로는 감지되어야 한다")

        let hrp = mrFitHRPaceModel(runs: runs, asOf: Date())
        XCTAssertFalse(hrp.ok, "심박이 없으면 회귀는 실패해야 한다 (억지로 값을 만들지 말 것)")
        XCTAssertNil(hrp.paceAtHR(140))
    }

    // MARK: ④ 기온 데이터가 없는 사람

    func testNoTemperature() {
        let runs = makeRuns(count: 100, km: 8, paceSecPerKm: 330, hr: 150, temp: nil)
        let heat = mrFitHeatModel(runs: runs)
        XCTAssertFalse(heat.ok)
        // ★ 실패해도 환산은 항등이어야 한다 (값을 왜곡하면 안 된다)
        XCTAssertEqual(heat.toRef(timeMin: 50, tempC: 30.0), 50, accuracy: 0.001)
        XCTAssertEqual(heat.fromRef(timeRefMin: 50, tempC: 30.0), 50, accuracy: 0.001)
    }

    // MARK: ⑤ 여성 사용자

    func testFemale() {
        let runs = makeRuns(count: 60, km: 6, paceSecPerKm: 360, hr: 158, temp: 15)
        let phys = mrPhysiology(runs: runs, restingHRSamples: [],
                                dateOfBirth: Calendar.current.date(byAdding: .year, value: -40, to: Date()),
                                sex: .female, asOf: Date())
        guard let hm = phys.hrMax?.value, let lt1 = phys.lt1HR?.value else {
            return XCTFail("추정 실패")
        }
        // Nuuttila 2025: 여성 LT1 = 80.0 %HRmax
        XCTAssertEqual(lt1 / hm, 0.800, accuracy: 0.001)
    }

    // MARK: ⑥ 대회 하나뿐인 사람 — 지수 적합 불가

    func testSingleEffort() {
        var runs = makeRuns(count: 40, km: 6, paceSecPerKm: 400, hr: 140, temp: 15)
        // 한 번 빠르게 10K
        runs.append(MRWorkout(start: Date().addingTimeInterval(-86400 * 10),
                              durationMin: 50, distanceKm: 10, hrAvg: 175, hrMax: 185,
                              tempC: 15, humidity: nil, indoor: false, isInterval: false))
        let phys = mrPhysiology(runs: runs, restingHRSamples: [],
                                dateOfBirth: nil, sex: .male, asOf: Date())
        let efforts = mrDetectEfforts(runs: runs, phys: phys)
        let fit = mrFitExponent(efforts)
        // ★ 거리 범위가 좁으면 개인 지수를 만들지 말고 1.06을 써야 한다
        if fit.ok {
            let (b, w) = fit.bFor(distanceM: MRDistance.dF, prior: 1.06)
            XCTAssertLessThan(w, 0.5, "관측 범위 밖으로 개인 지수를 외삽하면 안 된다")
            XCTAssertGreaterThan(b, 1.0)
        }
    }

    // MARK: ⑦ 극단값 — 엘리트와 초저마일리지

    func testExtremes() {
        // 주 120km 엘리트
        let e = bMarathonModel(weeklyKm: 120, longestKm: 35, finishes: 5)
        XCTAssertGreaterThanOrEqual(e.b, 1.03)
        XCTAssertLessThanOrEqual(e.b, 1.10)

        // 주 5km, 롱런 3km — Tanda 적합 범위 한참 밖
        let low = bMarathonModel(weeklyKm: 5, longestKm: 3, finishes: 0)
        XCTAssertLessThanOrEqual(low.b, 1.32, "상한을 넘으면 안 된다")
        XCTAssertGreaterThan(low.extraSD, 0.02, "범위 밖이면 불확실도가 커져야 한다")
    }

    // MARK: ⑧ 미래 날짜 누출 (백테스트 안전장치)

    func testNoFutureLeak() {
        let runs = makeRuns(count: 100, km: 8, paceSecPerKm: 330, hr: 150, temp: 15)
        // 기준일을 50일 전으로 잡으면 그 뒤 러닝은 절대 안 들어가야 한다
        let past = Calendar.current.date(byAdding: .day, value: -50, to: Date())!
        let prof = mrProfile(runs: runs, efforts: [], asOf: past)
        let futureKm = runs.filter { $0.date > past }.compactMap(\.distanceKm).reduce(0, +)
        XCTAssertGreaterThan(futureKm, 0, "테스트 전제: 미래 러닝이 존재해야 함")
        // ★ 주간 거리가 4주치를 넘으면 미래가 샌 것이다
        XCTAssertLessThan(prof.weeklyKm4w, 8 * 4, "미래 데이터가 새어 들어왔다")
    }
}
