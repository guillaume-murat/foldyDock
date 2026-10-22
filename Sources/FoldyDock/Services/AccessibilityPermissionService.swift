import AppKit
import ApplicationServices
import Combine

/// Owns the macOS Accessibility (AX) permission state FoldyDock needs for window cycling and the Window Picker.
@MainActor
public final class AccessibilityPermissionService: ObservableObject {
    public static let shared = AccessibilityPermissionService()

    @Published public private(set) var isTrusted: Bool

    private var pollTimer: Timer?
    private let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    public init() {
        isTrusted = AXIsProcessTrusted()
        if !isTrusted { startPolling() }
    }

    /// Re-reads the trust state; polling stops once permission is granted.
    public func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        if trusted {
            stopPolling()
        } else if pollTimer == nil {
            startPolling()
        }
    }

    /// Shows the system Accessibility prompt and opens the matching System Settings pane.
    public func requestPermission() {
        refresh()
        guard !isTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
    }

    /// Removes a stale TCC entry (left by a previous build) then asks again.
    public func resetAndRequestPermission() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.foldydock.FoldyDock"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleId]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[Accessibility] tccutil reset failed: \(error)")
        }
        requestPermission()
    }

    public func openSystemSettings() {
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Launch-time check: alerts the user when permission is missing (typically after a rebuild).
    /// Returns false when the user asked not to be reminded again.
    public func presentLaunchAlertIfNeeded() -> Bool {
        refresh()
        guard !isTrusted else { return true }

        let alert = NSAlert()
        alert.messageText = "Autorisation d'accessibilité requise"
        alert.informativeText = """
        FoldyDock a besoin de l'accès Accessibilité pour le sélecteur de fenêtres et le passage d'une fenêtre à l'autre.

        Si FoldyDock apparaît déjà coché dans Réglages Système, c'est l'autorisation d'une ancienne version : utilisez « Réinitialiser et redemander ».
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Ouvrir les Réglages")
        alert.addButton(withTitle: "Réinitialiser et redemander")
        alert.addButton(withTitle: "Plus tard")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Ne plus vérifier au lancement"

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            requestPermission()
        case .alertSecondButtonReturn:
            resetAndRequestPermission()
        default:
            break
        }
        return alert.suppressionButton?.state != .on
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
