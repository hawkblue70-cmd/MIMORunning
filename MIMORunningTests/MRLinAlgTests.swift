import XCTest
@testable import MIMORunning

final class MRLinAlgTests: XCTestCase {

    /// y = 3 + 2x 를 정확히 복원하는가
    func testPerfectFit() {
        let X = (0..<10).map { [1.0, Double($0)] }
        let y = (0..<10).map { 3.0 + 2.0 * Double($0) }
        let c = MRLinAlg.lstsq(X: X, y: y)
        XCTAssertNotNil(c)
        XCTAssertEqual(c![0], 3.0, accuracy: 1e-9)
        XCTAssertEqual(c![1], 2.0, accuracy: 1e-9)
    }

    /// 다변량: y = 1 + 2a - 3b
    func testMultivariate() {
        var X: [[Double]] = [], y: [Double] = []
        for a in 0..<5 {
            for b in 0..<5 {
                X.append([1.0, Double(a), Double(b)])
                y.append(1.0 + 2.0 * Double(a) - 3.0 * Double(b))
            }
        }
        let c = MRLinAlg.lstsq(X: X, y: y)!
        XCTAssertEqual(c[0],  1.0, accuracy: 1e-9)
        XCTAssertEqual(c[1],  2.0, accuracy: 1e-9)
        XCTAssertEqual(c[2], -3.0, accuracy: 1e-9)
    }

    /// 완전 공선이면 nil을 돌려줘야 한다 (엔진이 이걸로 "적합 불가"를 판단한다)
    func testSingular() {
        let X = (0..<10).map { [1.0, Double($0), Double($0) * 2.0] }
        let y = (0..<10).map { Double($0) }
        XCTAssertNil(MRLinAlg.lstsq(X: X, y: y))
    }
}
