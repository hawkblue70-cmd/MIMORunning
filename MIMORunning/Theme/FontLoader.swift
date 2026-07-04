import CoreText
import Foundation

/// Registers bundled custom fonts programmatically so they are available in
/// both the running app and Xcode SwiftUI previews (UIAppFonts alone is skipped
/// by the preview host process).
enum FontLoader {
    static func registerBundledFonts() {
        let names = [
            "Gaegu-Regular",
            "NanumPenScript-Regular",
            "NanumBrushScript-Regular",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
