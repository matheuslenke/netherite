import AppKit
import SwiftUI

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class AppThemeTests: XCTestCase {
    func testPreferredColorSchemeMatchesTheme() {
        XCTAssertNil(AppTheme.system.preferredColorScheme)
        XCTAssertEqual(AppTheme.light.preferredColorScheme, .light)
        XCTAssertEqual(AppTheme.dark.preferredColorScheme, .dark)
    }

    func testAppKitAppearanceNameMatchesTheme() {
        XCTAssertNil(AppTheme.system.appKitAppearanceName)
        XCTAssertEqual(AppTheme.light.appKitAppearanceName, .aqua)
        XCTAssertEqual(AppTheme.dark.appKitAppearanceName, .darkAqua)
    }
}
#endif
