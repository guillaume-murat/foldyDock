import Testing
import Foundation
import CoreGraphics
@testable import FoldyDock

/// Fixture adapter: describes each application as raw CGWindowList rows, AX windows and Window menu entries.
final class FixtureWindowSource: AppWindowSource, @unchecked Sendable {
    var cgRows: [CGWindowRow] = []
    var axWindowsByPid: [pid_t: [AXWindowReading]] = [:]
    var menuEntriesByPid: [pid_t: [WindowMenuEntry]] = [:]

    func cgWindowRows() -> [CGWindowRow] { cgRows }
    func axWindows(pid: pid_t) -> [AXWindowReading] { axWindowsByPid[pid] ?? [] }
    func windowMenuEntries(pid: pid_t) -> [WindowMenuEntry] { menuEntriesByPid[pid] ?? [] }
}

private func window(_ id: CGWindowID, _ title: String, minimized: Bool = false, main: Bool = false,
                    role: String = "AXWindow", subrole: String = "AXStandardWindow") -> AXWindowReading {
    AXWindowReading(windowID: id, role: role, subrole: subrole, title: title, isMinimized: minimized, isMain: main)
}

private func menu(_ titles: [String], marked: String? = nil) -> [WindowMenuEntry] {
    let header = [
        WindowMenuEntry(index: 0, title: "Tout ramener au premier plan", isSeparator: false, isMarked: false),
        WindowMenuEntry(index: 1, title: "", isSeparator: true, isMarked: false)
    ]
    return header + titles.enumerated().map { offset, title in
        WindowMenuEntry(index: offset + 2, title: title, isSeparator: false, isMarked: title == marked)
    }
}

private let chrome = RunningAppRef(pid: 42, bundleIdentifier: "com.google.Chrome")

@Suite("AppWindowInventoryTests")
struct AppWindowInventoryTests {
    @Test("Snapshot pairs Chrome's suffixed AX title with its Window menu entry and lists the other-Space window once")
    func testSnapshotPairsSuffixedTitles() {
        let source = FixtureWindowSource()
        source.axWindowsByPid[42] = [window(201, "Nouvel onglet - Google Chrome", main: true)]
        source.menuEntriesByPid[42] = menu(["Claude in Chrome", "Nouvel onglet"], marked: "Nouvel onglet")

        let snapshot = AppWindowInventory(source: source).snapshot(for: chrome)

        #expect(snapshot.windows.map(\.title) == ["Nouvel onglet", "Claude in Chrome"])
        #expect(snapshot.windows[0].windowID == 201)
        #expect(snapshot.windows[0].isMain == true)
        #expect(snapshot.windows[1].windowID == nil)
    }

    @Test("Dock dot counts use the inventory, ignoring Chrome's helper rows, and fall back to raw rows when the inventory is empty")
    func testWindowCountsPreferInventoryOverRawRows() async {
        let source = FixtureWindowSource()
        let noMenuApp = RunningAppRef(pid: 7, bundleIdentifier: "org.example.NoMenu")
        source.cgRows = [
            CGWindowRow(ownerPID: 42, width: 1710, height: 952),
            CGWindowRow(ownerPID: 42, width: 1710, height: 952),
            CGWindowRow(ownerPID: 42, width: 1710, height: 158),   // full-screen toolbar helper
            CGWindowRow(ownerPID: 42, width: 1710, height: 38),    // too small
            CGWindowRow(ownerPID: 7, width: 800, height: 600),
            CGWindowRow(ownerPID: 7, width: 800, height: 600, alpha: 0),  // invisible
            CGWindowRow(ownerPID: 7, width: 500, height: 500),     // untitled offscreen helper
            CGWindowRow(ownerPID: 7, layer: 25, width: 900, height: 900) // not a document layer
        ]
        source.axWindowsByPid[42] = [window(201, "Nouvel onglet - Google Chrome", main: true)]
        source.menuEntriesByPid[42] = menu(["Claude in Chrome", "Nouvel onglet"])

        let summary = await AppWindowInventory(source: source).refresh(apps: [chrome, noMenuApp])

        #expect(summary.windowCounts["com.google.Chrome"] == 2)
        #expect(summary.windowCounts["org.example.NoMenu"] == 1)
    }

    @Test("Cached counts are re-read only when the raw row count changes or after 10 seconds")
    func testWindowCountFreshness() async {
        let source = FixtureWindowSource()
        let clock = TestClock()
        source.cgRows = [CGWindowRow(ownerPID: 42, width: 1200, height: 800), CGWindowRow(ownerPID: 42, width: 1200, height: 800)]
        source.axWindowsByPid[42] = [window(201, "A"), window(202, "B")]
        let inventory = AppWindowInventory(source: source, now: { clock.now })

        #expect(await inventory.refresh(apps: [chrome]).windowCounts["com.google.Chrome"] == 2)

        // A window titled "C" appears in AX only: raw rows unchanged, cache still fresh
        source.axWindowsByPid[42] = [window(201, "A"), window(202, "B"), window(203, "C")]
        clock.now += 5
        #expect(await inventory.refresh(apps: [chrome]).windowCounts["com.google.Chrome"] == 2)

        // Cache expires after 10 s
        clock.now += 6
        #expect(await inventory.refresh(apps: [chrome]).windowCounts["com.google.Chrome"] == 3)

        // A raw row change invalidates immediately
        source.axWindowsByPid[42] = [window(201, "A")]
        source.cgRows.removeLast()
        clock.now += 1
        #expect(await inventory.refresh(apps: [chrome]).windowCounts["com.google.Chrome"] == 1)
    }

    @Test("An app is all-minimized when every User Window is minimized, ignoring panels; an app without AX windows is not")
    func testAllMinimizedIgnoresPanels() async {
        let source = FixtureWindowSource()
        let preview = RunningAppRef(pid: 8, bundleIdentifier: "com.apple.Preview")
        let otherSpace = RunningAppRef(pid: 9, bundleIdentifier: "org.example.OtherSpace")
        source.axWindowsByPid[8] = [
            window(301, "Document.pdf", minimized: true),
            window(302, "Inspecteur", subrole: "AXFloatingWindow")
        ]
        source.axWindowsByPid[42] = [window(201, "A", minimized: true), window(202, "B")]

        let summary = await AppWindowInventory(source: source).refresh(apps: [preview, chrome, otherSpace])

        #expect(summary.allMinimizedBundleIds == ["com.apple.Preview"])
    }

    @Test("Window menu commands after the last separator are not windows (Gemini lists none, Antigravity ends with Toggle Full Screen)")
    func testWindowMenuCommandsAreNotWindows() {
        let source = FixtureWindowSource()
        let gemini = RunningAppRef(pid: 12, bundleIdentifier: "com.google.GeminiMacOS")
        let antigravity = RunningAppRef(pid: 13, bundleIdentifier: "com.google.antigravity")
        source.axWindowsByPid[12] = [window(401, "Gemini", main: true)]
        source.menuEntriesByPid[12] = [
            WindowMenuEntry(index: 0, title: "Minimiser", isSeparator: false, isMarked: false, identifier: "performMiniaturize:"),
            WindowMenuEntry(index: 1, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 2, title: "Tout ramener au premier plan", isSeparator: false, isMarked: false, identifier: "arrangeInFront:"),
            WindowMenuEntry(index: 3, title: "Organiser au premier plan", isSeparator: false, isMarked: false, identifier: "alternateArrangeInFront:"),
            WindowMenuEntry(index: 4, title: "Supprimer la fenêtre du groupe", isSeparator: false, isMarked: false, identifier: "_removeWindowFromStageManagerSet:")
        ]
        source.axWindowsByPid[13] = [window(501, "main.swift — foldyDock")]
        source.menuEntriesByPid[13] = [
            WindowMenuEntry(index: 0, title: "Minimize", isSeparator: false, isMarked: false, identifier: "performMiniaturize:"),
            WindowMenuEntry(index: 1, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 2, title: "Toggle Full Screen", isSeparator: false, isMarked: false, identifier: "toggleFullScreenMode:")
        ]
        let inventory = AppWindowInventory(source: source)

        #expect(inventory.snapshot(for: gemini).windows.map(\.title) == ["Gemini"])
        #expect(inventory.snapshot(for: antigravity).windows.map(\.title) == ["main.swift — foldyDock"])
    }

    @Test("Window entries are recognised by their makeKeyAndOrderFront: action even when commands follow them")
    func testWindowEntriesRecognisedByAction() {
        let source = FixtureWindowSource()
        let app = RunningAppRef(pid: 14, bundleIdentifier: "com.example.Editor")
        source.menuEntriesByPid[14] = [
            WindowMenuEntry(index: 0, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 1, title: "Rapport.md", isSeparator: false, isMarked: true, identifier: "makeKeyAndOrderFront:"),
            WindowMenuEntry(index: 2, title: "Notes.md", isSeparator: false, isMarked: false, identifier: "makeKeyAndOrderFront:"),
            WindowMenuEntry(index: 3, title: "", isSeparator: true, isMarked: false),
            WindowMenuEntry(index: 4, title: "Show All Tabs", isSeparator: false, isMarked: false, identifier: "toggleTabOverview:")
        ]

        let windows = AppWindowInventory(source: source).snapshot(for: app).windows

        #expect(windows.map(\.title) == ["Rapport.md", "Notes.md"])
        #expect(windows.map(\.menuIndex) == [1, 2])
    }

    @Test("Window cycling raises the window paired by the inventory, not one whose title merely contains the target")
    func testCyclingUsesInventoryPairing() {
        let source = FixtureWindowSource()
        let notes = RunningAppRef(pid: 11, bundleIdentifier: "com.example.Notes")
        source.axWindowsByPid[11] = [window(301, "Notes de réunion", main: true), window(302, "Notes")]
        source.menuEntriesByPid[11] = menu(["Notes", "Notes de réunion"], marked: "Notes de réunion")
        let snapshot = AppWindowInventory(source: source).snapshot(for: notes)

        var engine = AppWindowCyclingEngine()
        let decision = engine.decideActivation(pid: 11, isFrontmost: true, isHidden: false, snapshot: snapshot)

        #expect(decision == .pressMenuIndex(menuIndex: 2, matchingWindowID: 302))
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}
