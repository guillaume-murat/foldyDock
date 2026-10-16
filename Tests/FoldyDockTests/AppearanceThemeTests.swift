import Testing
import Foundation
@testable import FoldyDock

@Suite("AppearanceThemeTests")
struct AppearanceThemeTests {
    @Test("DockConfig defaults to system appearance mode and persists light and dark modes")
    func testAppearanceModePersistence() throws {
        let defaultConfig = DockConfig()
        #expect(defaultConfig.appearanceMode == .system)

        var lightConfig = DockConfig(appearanceMode: .light)
        let encodedLight = try JSONEncoder().encode(lightConfig)
        let decodedLight = try JSONDecoder().decode(DockConfig.self, from: encodedLight)
        #expect(decodedLight.appearanceMode == .light)

        lightConfig.appearanceMode = .dark
        let encodedDark = try JSONEncoder().encode(lightConfig)
        let decodedDark = try JSONDecoder().decode(DockConfig.self, from: encodedDark)
        #expect(decodedDark.appearanceMode == .dark)
    }

    @Test("DockTheme resolves effective light/dark state from AppearanceMode and system dark flag")
    func testThemeResolution() {
        #expect(DockTheme.resolve(mode: .system, isSystemDark: true).isDark == true)
        #expect(DockTheme.resolve(mode: .system, isSystemDark: false).isDark == false)
        #expect(DockTheme.resolve(mode: .light, isSystemDark: true).isDark == false)
        #expect(DockTheme.resolve(mode: .dark, isSystemDark: false).isDark == true)
    }

    @Test("DockViewModel updates effective theme when appearanceMode or system appearance changes")
    @MainActor
    func testDockViewModelThemeUpdates() {
        let vm = DockViewModel()
        vm.isSystemDark = false

        vm.setAppearanceMode(.system)
        #expect(vm.theme.isDark == false)

        vm.isSystemDark = true
        #expect(vm.theme.isDark == true)

        vm.setAppearanceMode(.light)
        #expect(vm.theme.isDark == false)

        vm.setAppearanceMode(.dark)
        #expect(vm.theme.isDark == true)
    }
}
