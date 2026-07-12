import CoreText
import Foundation

/// Registers bundled custom fonts programmatically so they are available in
/// both the running app and Xcode SwiftUI previews (UIAppFonts alone is skipped
/// by the preview host process).
enum FontLoader {
    static func registerBundledFonts() {
        // NanumPen만 번들 등록. Apple SD Gothic Neo는 iOS 시스템 폰트라 등록 불필요.
        let names = ["NanumPenScript-Regular"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
