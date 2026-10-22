import Foundation
import CoreGraphics

/// Represents an open standard user window of an application.
public struct AppWindowInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let isMinimized: Bool
    public let isMain: Bool
    public let windowID: CGWindowID?
    public let menuTitle: String?
    /// Index of the paired entry in the application's Window menu, if any.
    public let menuIndex: Int?

    public init(
        id: String,
        title: String,
        isMinimized: Bool,
        isMain: Bool,
        windowID: CGWindowID? = nil,
        menuTitle: String? = nil,
        menuIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.isMinimized = isMinimized
        self.isMain = isMain
        self.windowID = windowID
        self.menuTitle = menuTitle
        self.menuIndex = menuIndex
    }
}
