import UIKit
import MapKit
import SwiftUI

/// 경로 지도 스냅샷 그리기 — 활동 상세 지도와 경로 공유 카드가 **이 타입 하나만** 쓴다.
///
/// 예전에는 같은 경로선을 세 곳에서 따로 그렸다. 그 결과 화면 지도에만 km 마커가 있고
/// 공유 카드에는 없는 식으로 갈라졌다. 선·마커·심박 색을 여기 모아 둔다.
enum RouteSnapshotRenderer {

    static let violet = UIColor(red: 0x7C / 255.0, green: 0x5C / 255.0, blue: 0xFC / 255.0, alpha: 1.0)

    /// 스냅샷 옵션 — 경로 전체가 들어오도록 영역을 잡는다.
    /// `routeBottomLimit`(0~1)을 주면 경로가 지도 높이의 그 비율 **위쪽**에만 놓이도록 영역을 아래로
    /// 늘린다 — 경로 카드처럼 지도 아래쪽에 글자를 얹을 때 경로와 글자가 겹치지 않게. nil이면 가운데.
    static func options(coordinates: [CLLocationCoordinate2D], size: CGSize, scale: CGFloat,
                        routeBottomLimit: Double? = nil)
        -> MKMapSnapshotter.Options? {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let opts = MKMapSnapshotter.Options()
        if let limit = routeBottomLimit {
            opts.region = topAnchoredRegion(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon,
                                            size: size, bottomLimit: limit)
        } else {
            opts.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                               longitude: (minLon + maxLon) / 2),
                span: MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
                                       longitudeDelta: max(0.004, (maxLon - minLon) * 1.4))
            )
        }
        opts.size = size
        opts.scale = scale
        opts.mapType = .mutedStandard
        opts.showsBuildings = false
        return opts
    }

    /// 경로를 위쪽에 앉히는 영역 — 위 여백 12%, 경로는 `bottomLimit`까지, 그 아래는 빈 지도.
    /// 영역의 가로세로 비를 스냅샷 크기와 맞춰 두어야 스냅샷터가 영역을 다시 잡으며 경로를 가운데로 되돌리지 않는다.
    static func topAnchoredRegion(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
                                  size: CGSize, bottomLimit: Double) -> MKCoordinateRegion {
        let topMargin = 0.12
        let usable = max(0.2, min(bottomLimit, 0.95) - topMargin)
        let routeLat = max(maxLat - minLat, 0.002)
        let routeLon = max(maxLon - minLon, 0.002)
        let cosLat = max(0.2, cos((minLat + maxLat) / 2 * .pi / 180))
        let aspect = size.width / max(size.height, 1)
        var latSpan = max(0.004, routeLat / usable)
        var lonSpan = max(0.004, routeLon * 1.3)
        let lonForLat = latSpan * aspect / cosLat
        if lonSpan < lonForLat { lonSpan = lonForLat } else { latSpan = lonSpan * cosLat / aspect }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: maxLat + latSpan * topMargin - latSpan / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
    }

    /// 쓸 수 있는 좌표인가 — (0,0) 근처 콜드스타트 튐은 영역을 통째로 늘린다.
    /// 시간 오프셋 같은 평행 배열을 같이 걸러야 할 때 이 판정을 직접 쓴다(판정이 갈라지면 인덱스가 어긋난다).
    static func isValid(_ c: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(c) && abs(c.latitude) > 1 && abs(c.longitude) > 1
    }

    /// GPS 오류 좌표 제거 — (0,0) 근처 콜드스타트 튐이 영역을 통째로 늘린다.
    static func validCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        coordinates.filter(isValid)
    }

    /// 경로선 + 시작·km·도착 마커를 스냅샷 위에 그린다.
    /// `segmentColors`가 있으면 구간별 색(심박 존 그라데이션), 없으면 단색 바이올렛.
    /// `lineScale`은 선 굵기 배율(작은 카드는 굵게), `showKmMarkers`가 false면 시작·도착 점만 남긴다 —
    /// 300pt 폭 카드에서 km 알약이 경로보다 커 보여서.
    /// `progress`(0~1)를 1보다 작게 주면 그 지점까지만 그리고 끝에 현재 위치 점을 찍는다 — 경로 영상의 한 프레임.
    /// 정지 카드와 영상이 **같은 선 그리기**를 쓰도록 여기 한 곳에만 둔다.
    static func draw(on snap: MKMapSnapshotter.Snapshot,
                     coordinates: [CLLocationCoordinate2D],
                     segmentColors: [UIColor]? = nil,
                     lineScale: CGFloat = 1,
                     showKmMarkers: Bool = true,
                     progress: Double = 1) -> UIImage {
        let step = max(1, coordinates.count / 300)
        let indices = Array(stride(from: 0, to: coordinates.count, by: step))
        let allPts = indices.map { snap.point(for: coordinates[$0]) }
        let pts = trimmed(allPts, to: progress)

        // 스냅샷이 가진 배율 그대로 다시 그린다 — 기본값(화면 배율)을 쓰면 3.6배로 찍은 영상용 지도가 3배로 줄어 흐려진다
        let format = UIGraphicsImageRendererFormat()
        format.scale = snap.image.scale
        return UIGraphicsImageRenderer(size: snap.image.size, format: format).image { _ in
            snap.image.draw(at: .zero)
            guard pts.count > 1 else {
                if let p = pts.first { RouteMarkers.drawStartMarker(at: p) }
                return
            }

            if let segmentColors, segmentColors.count >= coordinates.count {
                // 구간마다 색이 다르다 — 글로우를 전부 깐 뒤 코어를 올려야 이음매가 깔끔하다
                let colors = indices.map { segmentColors[$0] }
                for pass in 0..<2 {
                    for i in 0..<(pts.count - 1) {
                        let seg = UIBezierPath()
                        seg.move(to: pts[i])
                        seg.addLine(to: pts[i + 1])
                        seg.lineCapStyle = .round
                        seg.lineWidth = (pass == 0 ? 3.5 : 1.5) * lineScale
                        let c = colors[i]
                        (pass == 0 ? c.withAlphaComponent(0.35) : c).setStroke()
                        seg.stroke()
                    }
                }
            } else {
                let path = UIBezierPath()
                path.move(to: pts[0])
                for pt in pts.dropFirst() { path.addLine(to: pt) }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = 3 * lineScale
                violet.withAlphaComponent(0.4).setStroke()
                path.stroke()
                path.lineWidth = 1.5 * lineScale
                violet.setStroke()
                path.stroke()
            }

            if showKmMarkers, progress >= 1 {
                RouteMarkers.drawAll(on: snap, coords: coordinates,
                                     endPoint: pts.last, startPoint: pts.first)
            } else {
                if let p = pts.first { RouteMarkers.drawStartMarker(at: p) }
                if let p = pts.last { RouteMarkers.drawFinishMarker(at: p) }
            }
        }
    }

    /// 꺾은선을 전체 길이의 `progress` 지점에서 자른다 — 마지막 구간은 그 안에서 비례해 끊어 선이 매끄럽게 자란다.
    private static func trimmed(_ pts: [CGPoint], to progress: Double) -> [CGPoint] {
        guard progress < 1 else { return pts }
        guard pts.count > 1, progress > 0 else { return Array(pts.prefix(1)) }
        let lengths = (0..<(pts.count - 1)).map { hypot(pts[$0 + 1].x - pts[$0].x, pts[$0 + 1].y - pts[$0].y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return Array(pts.prefix(1)) }
        let target = total * CGFloat(progress)
        var acc: CGFloat = 0
        var out: [CGPoint] = [pts[0]]
        for i in lengths.indices {
            if acc + lengths[i] >= target {
                let t = lengths[i] > 0 ? (target - acc) / lengths[i] : 0
                out.append(CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
                                   y: pts[i].y + (pts[i + 1].y - pts[i].y) * t))
                return out
            }
            acc += lengths[i]
            out.append(pts[i + 1])
        }
        return out
    }

    // MARK: - 심박 존 색

    /// 각 좌표의 심박을 존 색으로 바꾼 배열. 심박 표본이 모자라면 nil.
    /// 시간 오프셋이 없으면 전체 시간에 균등 분포로 가정한다.
    static func zoneColors(coordinates: [CLLocationCoordinate2D],
                           routeTimeOffsets: [TimeInterval],
                           workoutDuration: TimeInterval,
                           hrSamples: [(offset: TimeInterval, bpm: Int)],
                           zoneBounds: [(id: Int, minBPM: Int)]) -> [UIColor]? {
        guard hrSamples.count >= 10, coordinates.count > 1, !zoneBounds.isEmpty else { return nil }
        let sorted = zoneBounds.sorted { $0.minBPM < $1.minBPM }
        var matched = 0
        var colors: [UIColor] = []
        colors.reserveCapacity(coordinates.count)

        for i in coordinates.indices {
            let offset = i < routeTimeOffsets.count
                ? routeTimeOffsets[i]
                : Double(i) * workoutDuration / max(Double(coordinates.count - 1), 1)
            let (bpm, ok) = smoothedBPM(at: offset, samples: hrSamples)
            if ok { matched += 1 }
            colors.append(color(bpm: bpm, bounds: sorted))
        }
        // 좌표 시간대와 심박 표본이 어긋나면(브리지 앱 기록 등) 색이 의미 없어진다
        guard matched > 0 else { return nil }
        return colors
    }

    /// 5초 이동평균 심박. matched=false면 윈도우에 표본이 없어 최근접값을 쓴 것.
    static func smoothedBPM(at offset: TimeInterval,
                            samples: [(offset: TimeInterval, bpm: Int)]) -> (bpm: Int, matched: Bool) {
        let window = samples.filter { abs($0.offset - offset) <= 2.5 }
        if window.isEmpty {
            guard let nearest = samples.min(by: { abs($0.offset - offset) < abs($1.offset - offset) })
            else { return (60, false) }
            return (nearest.bpm, false)
        }
        return (window.reduce(0) { $0 + $1.bpm } / window.count, true)
    }

    /// 존 경계 사이를 선형 보간한 색
    static func color(bpm: Int, bounds: [(id: Int, minBPM: Int)]) -> UIColor {
        let sorted = bounds.sorted { $0.minBPM < $1.minBPM }
        let colors = Theme.hrZoneColors.map { UIColor($0) }
        guard sorted.count >= 2, !colors.isEmpty else { return violet }
        if bpm <= sorted[0].minBPM { return colors[0] }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i].minBPM, hi = sorted[i + 1].minBPM
            guard hi > lo, bpm < hi else { continue }
            return lerp(colors[min(i, colors.count - 1)],
                        colors[min(i + 1, colors.count - 1)],
                        CGFloat(bpm - lo) / CGFloat(hi - lo))
        }
        return colors[min(sorted.count - 1, colors.count - 1)]
    }

    private static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tc = max(0, min(1, t))
        return UIColor(red: r1 + (r2 - r1) * tc, green: g1 + (g2 - g1) * tc,
                       blue: b1 + (b2 - b1) * tc, alpha: 1)
    }
}
