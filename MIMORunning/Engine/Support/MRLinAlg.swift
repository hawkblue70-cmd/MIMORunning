import Foundation

// ⚠ 회귀를 적합 범위 밖으로 외삽하지 말 것.
//   이 코드베이스에서 네 번 같은 실수가 있었다 —
//   더위 모델 심박 공변량, T3 세그먼트, 드리프트 pooled, HRPace 저심박.
//   데이터가 없는 구간의 값이 필요하면 회귀 대신
//   실측 구간의 중앙값을 쓰고, 그 표본 수를 화면에 밝힌다.
enum MRLinAlg {

    /// 최소자승 다중회귀. X는 행 단위(각 행이 관측 하나, 절편항 포함).
    /// 반환: 계수 배열. 특이행렬이면 nil.
    ///
    /// 정규방정식 (XᵀX)β = Xᵀy 를 부분 피벗 가우스 소거로 푼다.
    static func lstsq(X: [[Double]], y: [Double]) -> [Double]? {
        guard let p = X.first?.count, X.count == y.count, X.count > p else { return nil }
        let n = X.count

        // XᵀX (p×p) 와 Xᵀy (p)
        var A = [[Double]](repeating: [Double](repeating: 0, count: p + 1), count: p)
        for i in 0..<p {
            for j in 0..<p {
                var s = 0.0
                for k in 0..<n { s += X[k][i] * X[k][j] }
                A[i][j] = s
            }
            var s = 0.0
            for k in 0..<n { s += X[k][i] * y[k] }
            A[i][p] = s
        }

        // 부분 피벗 가우스 소거
        for c in 0..<p {
            var piv = c
            for r in (c + 1)..<p where abs(A[r][c]) > abs(A[piv][c]) { piv = r }
            if abs(A[piv][c]) < 1e-12 { return nil }          // 특이
            if piv != c { A.swapAt(piv, c) }
            let d = A[c][c]
            for j in c...p { A[c][j] /= d }
            for r in 0..<p where r != c {
                let f = A[r][c]
                if f == 0 { continue }
                for j in c...p { A[r][j] -= f * A[c][j] }
            }
        }
        return (0..<p).map { A[$0][p] }
    }

    /// 잔차 표준편차. ddof는 자유도 차감.
    static func residualSD(X: [[Double]], y: [Double],
                           coef: [Double], ddof: Int) -> Double {
        var ss = 0.0
        for k in 0..<y.count {
            var pred = 0.0
            for j in 0..<coef.count { pred += X[k][j] * coef[j] }
            let r = y[k] - pred
            ss += r * r
        }
        let df = max(y.count - ddof, 1)
        return (ss / Double(df)).squareRoot()
    }
}
