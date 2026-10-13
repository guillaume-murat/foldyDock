import Foundation

public enum NowPlayingScriptParser {
    public static func parse(output: String) -> NowPlayingState {
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let status = lines.first, !status.isEmpty, status.caseInsensitiveCompare("IDLE") != .orderedSame else {
            return .idle
        }

        let title = lines.count > 1 ? lines[1] : ""
        let artist = lines.count > 2 ? lines[2] : ""
        let album = lines.count > 3 ? lines[3] : ""
        let bundleId = lines.count > 4 ? lines[4] : ""
        let appName = lines.count > 5 ? lines[5] : ""
        let pidString = lines.count > 6 ? lines[6] : ""
        let pid = pid_t(pidString)

        guard !title.isEmpty else {
            return .idle
        }

        let resolvedArtist: String
        if !artist.isEmpty {
            resolvedArtist = artist
        } else if !appName.isEmpty {
            resolvedArtist = appName
        } else {
            resolvedArtist = "Unknown Artist"
        }

        let track = MediaTrack(
            title: title,
            artist: resolvedArtist,
            album: album.isEmpty ? nil : album,
            artworkData: nil,
            pid: (pid != nil && pid! > 0) ? pid : nil,
            bundleIdentifier: bundleId.isEmpty ? nil : bundleId
        )

        if status.caseInsensitiveCompare("Playing") == .orderedSame {
            return .playing(track)
        } else if status.caseInsensitiveCompare("Paused") == .orderedSame {
            return .paused(track)
        } else {
            return .idle
        }
    }
}
