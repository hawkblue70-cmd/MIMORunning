// Placeable 카드 — UserDefaults 영속화
//
// 스토리·슬라이드 오버레이 설정(텍스트·스타일·클립별 스타일)의 저장·복원 전담.
// PlaceableStoryTemplate.swift에서 추출. extension ShareCardScreen 으로 타입 상태에 직접 접근.

import SwiftUI

extension ShareCardScreen {

    // MARK: - Placeable 오버레이 저장·복원

    var psoPrefix: String { "pso_\(activity.id.uuidString)_" }

    func loadPlaceableStoryOverlay() {
        let ud = UserDefaults.standard
        let p  = psoPrefix
        if let data = ud.data(forKey: p + "textsArr"),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            placeableVM.placeableStoryTexts = Dictionary(uniqueKeysWithValues:
                arr.enumerated().compactMap { i, t in t.isEmpty ? nil : (i, t) })
        } else if let t = ud.string(forKey: p + "text"), !t.isEmpty {
            placeableVM.placeableStoryTexts = [0: t]
        }
        if let f = ud.string(forKey: p + "font"),  let fv = OneLinerFont(rawValue: f)         { placeableVM.placeableStoryFont        = fv }
        if let c = ud.string(forKey: p + "color"), let cv = OneLinerTextColor(rawValue: c)    { placeableVM.placeableStoryColor       = cv }
        if let s = ud.string(forKey: p + "size"),  let sv = TextSizeLevel(rawValue: s)        { placeableVM.placeableStorySize        = sv }
        let posIdx = ud.integer(forKey: p + "pos")
        let posAll = Array(CardPosition.allCases)
        if posIdx >= 0, posIdx < posAll.count { placeableVM.placeableStoryPosition = posAll[posIdx] }
        if let bv = ud.object(forKey: p + "border") as? Bool { placeableVM.placeableStoryHasBorder = bv }
        // 슬라이드 클립별 스타일 복원
        if let data = ud.data(forKey: p + "slideClipStyles"),
           let styles = try? JSONDecoder().decode([String: PlaceableSlideClipStyle].self, from: data) {
            placeableVM.placeableSlideClipStyles = Dictionary(uniqueKeysWithValues:
                styles.compactMap { k, v in Int(k).map { ($0, v) } })
        }
        // 사진별 크롭 오프셋 복원
        if let data = ud.data(forKey: p + "cropOffsetsX"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            placeableVM.placeableStoryCropOffsets = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in Int(k).map { ($0, CGFloat(v)) } })
        }
        if let data = ud.data(forKey: p + "cropOffsetsY"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            placeableVM.placeableStoryCropOffsetsY = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in Int(k).map { ($0, CGFloat(v)) } })
        }
    }

    func savePlaceableStoryOverlay() {
        let ud = UserDefaults.standard
        let p  = psoPrefix
        let maxIdx = placeableVM.placeableStoryTexts.keys.max() ?? 0
        var arr = Array(repeating: "", count: maxIdx + 1)
        for (idx, text) in placeableVM.placeableStoryTexts where idx <= maxIdx { arr[idx] = text }
        if let data = try? JSONEncoder().encode(arr) { ud.set(data, forKey: p + "textsArr") }
        ud.set(placeableVM.placeableStoryFont.rawValue,               forKey: p + "font")
        ud.set(placeableVM.placeableStoryColor.rawValue,              forKey: p + "color")
        ud.set(placeableVM.placeableStorySize.rawValue,               forKey: p + "size")
        let posAll = Array(CardPosition.allCases)
        ud.set(posAll.firstIndex(of: placeableVM.placeableStoryPosition) ?? 0, forKey: p + "pos")
        ud.set(placeableVM.placeableStoryHasBorder,                   forKey: p + "border")
        // 슬라이드 클립별 스타일 저장
        let stylesDict = Dictionary(uniqueKeysWithValues: placeableVM.placeableSlideClipStyles.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stylesDict) { ud.set(data, forKey: p + "slideClipStyles") }
        // 사진별 크롭 오프셋 저장
        let cxDict = Dictionary(uniqueKeysWithValues: placeableVM.placeableStoryCropOffsets.map  { (String($0.key), Double($0.value)) })
        let cyDict = Dictionary(uniqueKeysWithValues: placeableVM.placeableStoryCropOffsetsY.map { (String($0.key), Double($0.value)) })
        if let data = try? JSONEncoder().encode(cxDict) { ud.set(data, forKey: p + "cropOffsetsX") }
        if let data = try? JSONEncoder().encode(cyDict) { ud.set(data, forKey: p + "cropOffsetsY") }
    }

    // MARK: - Athletic 크롭 저장·복원

    var athleticCropPrefix: String { "athletic_\(activity.id.uuidString)_" }

    func saveAthleticCropOffsets() {
        let ud = UserDefaults.standard
        let p  = athleticCropPrefix
        ud.set(Double(athleticCropOffsetX), forKey: p + "cropX")
        let dict = Dictionary(uniqueKeysWithValues: athleticSlideCropOffsets.map { (String($0.key), Double($0.value)) })
        if let data = try? JSONEncoder().encode(dict) { ud.set(data, forKey: p + "slideCropOffsets") }
    }

    func loadAthleticCropOffsets() {
        let ud = UserDefaults.standard
        let p  = athleticCropPrefix
        if ud.object(forKey: p + "cropX") != nil {
            athleticCropOffsetX = CGFloat(ud.double(forKey: p + "cropX"))
        }
        if let data = ud.data(forKey: p + "slideCropOffsets"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            athleticSlideCropOffsets = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in Int(k).map { ($0, CGFloat(v)) } })
        }
    }
}
