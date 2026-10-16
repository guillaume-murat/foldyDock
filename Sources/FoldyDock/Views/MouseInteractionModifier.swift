import SwiftUI

public struct ItemFramesPreferenceKey: PreferenceKey {
    public static var defaultValue: [UUID: CGRect] = [:]

    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public struct FolderItemFramesPreferenceKey: PreferenceKey {
    public static var defaultValue: [UUID: CGRect] = [:]

    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public struct FolderAnchorFramesPreferenceKey: PreferenceKey {
    public static var defaultValue: [UUID: CGRect] = [:]

    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}


