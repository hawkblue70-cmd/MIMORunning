import XCTest
@testable import MIMORunning

/// 상세 화면이 부르는 조립(`TabDigest.assemble`) — 세 수집기 결과를 합쳐 블록 3개를 만드는 시나리오.
final class TabDigestAssemblyTests: XCTestCase {
    typealias S = TabDigest.Signal

    /// 이지런 심박 높음(리듬 R1) + 다리 무거움(폼 F2) + 7일 부하 크게 증가(퍼포먼스 P2·P5)
    func testEasyHighHRHeavyLegsVeryHighLoadMakesThreeBlocks() {
        let loadNext = "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋습니다."
        let heartNext = "다음 이지런은 Zone 2 상단(6'40\" 안팎)으로 가 보세요."
        let formNext = "다음 러닝은 같은 거리에서 후반 지면접촉만 지켜보세요."
        let rhythm = [
            S(tab: .rhythm, kind: .problem, priority: 1, family: .unique,
              text: "이지런인데 심박이 높았습니다 — Zone 3 이상 52%", tone: .caution, direction: heartNext),
            S(tab: .rhythm, kind: .problem, priority: 5, family: .unique,
              text: "템포 구간에 오래 머물렀습니다", tone: .caution, direction: loadNext),
        ]
        let form = [
            S(tab: .form, kind: .problem, priority: 2, family: .unique,
              text: "같은 페이스 평소보다 지면접촉이 273ms로 길고 케이던스가 169spm으로 낮았습니다. 다리가 무거운 날의 패턴입니다 — 5일 연속 · 최근 7일 부하 +134%.",
              tone: .caution, direction: formNext),
        ]
        let performance = [
            S(tab: .performance, kind: .problem, priority: 2, family: .load,
              text: "4주 평균 대비 7일 부하가 크게 높습니다(+34%)", tone: .caution, direction: loadNext),
            S(tab: .performance, kind: .problem, priority: 5, family: .unique,
              text: "최근 이지 비율이 낮습니다", tone: .caution, direction: loadNext),
        ]
        let blocks = TabDigest.assemble(rhythm: rhythm, form: form, performance: performance,
                                        defaults: .init(directions: [.rhythm: "d-r", .form: "d-f", .performance: loadNext]))

        XCTAssertEqual(blocks.map(\.tab), [.rhythm, .form, .performance])
        XCTAssertTrue(blocks.allSatisfy { $0.direction != nil })
        XCTAssertEqual(blocks.compactMap(\.direction).filter { $0 == loadNext }.count, 1)
        XCTAssertEqual(blocks[0].direction, heartNext)
        XCTAssertEqual(blocks[1].direction, formNext)
        XCTAssertEqual(blocks[2].direction, loadNext)
        XCTAssertEqual(blocks[2].statements.count, 2)
    }

    func testAssembleEqualsMake() {
        let r = [S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "r", tone: .good)]
        let f = [S(tab: .form, kind: .good, priority: 1, family: .unique, text: "f", tone: .good)]
        let p = [S(tab: .performance, kind: .problem, priority: 2, family: .load, text: "p", tone: .caution)]
        let d = TabDigest.Defaults(directions: [.form: "df"])
        XCTAssertEqual(TabDigest.assemble(rhythm: r, form: f, performance: p, defaults: d),
                       TabDigest.make(r + f + p, defaults: d))
    }
}
