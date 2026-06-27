import Foundation
import CoreLocation

// MARK: - Models

struct HillSpot: Decodable {
    let name: String
    let lat: Double
    let lng: Double
    let radiusM: Double
    let minElevationGainM: Double
}

struct HillMatch {
    let spot: HillSpot
    let minDistanceM: Double
    let elevationGain: Double
    let matched: Bool
}

// MARK: - Detector

struct HillSpotDetector {

    static let shared = HillSpotDetector()

    private(set) var spots: [HillSpot]

    private init() {
        guard let data = Self.embeddedHillsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([HillSpot].self, from: data)
        else { spots = []; return }
        spots = decoded
    }

    /// Returns one HillMatch per spot — matched and unmatched both included so callers
    /// can inspect minDistanceM / elevationGain even when matched == false.
    func assess(routeCoords: [CLLocationCoordinate2D], elevationGain: Double?) -> [HillMatch] {
        let gain = elevationGain ?? 0
        return spots.map { spot in
            let minDist = minDistance(routeCoords: routeCoords, spotLat: spot.lat, spotLng: spot.lng)
            let matched = minDist <= spot.radiusM && gain >= spot.minElevationGainM
            return HillMatch(spot: spot, minDistanceM: minDist, elevationGain: gain, matched: matched)
        }
    }

    // Samples up to 100 evenly-spaced route points (same approach as RaceDetector.minDistance).
    private func minDistance(routeCoords: [CLLocationCoordinate2D],
                             spotLat: Double, spotLng: Double) -> Double {
        guard !routeCoords.isEmpty else { return .greatestFiniteMagnitude }
        let spotLoc = CLLocation(latitude: spotLat, longitude: spotLng)
        var minDist = CLLocation(latitude: routeCoords[0].latitude,
                                 longitude: routeCoords[0].longitude).distance(from: spotLoc)
        let step = max(1, routeCoords.count / 100)
        for i in Swift.stride(from: 1, to: routeCoords.count, by: step) {
            let d = CLLocation(latitude: routeCoords[i].latitude,
                               longitude: routeCoords[i].longitude).distance(from: spotLoc)
            if d < minDist { minDist = d }
        }
        return minDist
    }

    // MARK: - Embedded hill spot data
    // 좌표는 각 스팟의 정상/대표 지점. 추가는 배열에 항목을 append.

    private static let embeddedHillsJSON = """
    [
      {
        "name": "남산",
        "lat": 37.5512,
        "lng": 126.9882,
        "radiusM": 900,
        "minElevationGainM": 80
      }
    ]
    """
}
