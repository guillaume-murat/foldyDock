import Testing
import Foundation
@testable import FoldyDock

@Suite("AccessibilityPermissionTests")
struct AccessibilityPermissionTests {
    @Test("DockConfig checks Accessibility on launch by default, including configs saved before the option existed")
    func testCheckAccessibilityOnLaunchDefault() throws {
        #expect(DockConfig().checkAccessibilityOnLaunch == true)

        let legacyJSON = Data(#"{"autohideEnabled": true, "items": []}"#.utf8)
        let legacy = try JSONDecoder().decode(DockConfig.self, from: legacyJSON)
        #expect(legacy.checkAccessibilityOnLaunch == true)

        let disabled = DockConfig(checkAccessibilityOnLaunch: false)
        let decoded = try JSONDecoder().decode(DockConfig.self, from: JSONEncoder().encode(disabled))
        #expect(decoded.checkAccessibilityOnLaunch == false)
    }
}
