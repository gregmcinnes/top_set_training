import XCTest
import UIKit
@testable import SBSApp

/// Guards the bundled design-system fonts: a missing UIAppFonts entry or a
/// font file dropped by xcodegen would silently fall back to the system font.
final class ThemeFontsTests: XCTestCase {
    func testEveryBundledFontRegisters() {
        for name in SBSFontName.all {
            XCTAssertNotNil(UIFont(name: name, size: 17), "\(name) is not registered; check Resources/Fonts and UIAppFonts in project.yml")
        }
    }
}
