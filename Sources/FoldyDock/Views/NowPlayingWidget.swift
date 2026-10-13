import SwiftUI
import AppKit

public struct NowPlayingWidget: View {
    @ObservedObject var viewModel: DockViewModel
    public let iconSize: CGFloat
    public let dockHeight: CGFloat

    @State private var isHovered: Bool = false
    @State private var cachedArtwork: NSImage?
    @State private var lastArtworkData: Data?

    public init(viewModel: DockViewModel, iconSize: CGFloat, dockHeight: CGFloat) {
        self.viewModel = viewModel
        self.iconSize = iconSize
        self.dockHeight = dockHeight
    }

    private var capsuleHeight: CGFloat {
        iconSize
    }

    private var artworkSize: CGFloat {
        iconSize * 0.70
    }

    private var titleFontSize: CGFloat {
        max(10.0, min(12.5, iconSize * 0.21))
    }

    private var artistFontSize: CGFloat {
        max(8.5, min(11.0, iconSize * 0.17))
    }

    private var buttonIconSize: CGFloat {
        max(10.0, min(14.0, iconSize * 0.22))
    }

    public var body: some View {
        Group {
            switch viewModel.nowPlayingState {
            case .idle:
                idleView
            case .playing, .paused:
                activeView
            }
        }
        .frame(height: capsuleHeight)
        .background(
            RoundedRectangle(cornerRadius: capsuleHeight * 0.22, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: capsuleHeight * 0.22, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.20 : 0.10), lineWidth: 0.8)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .onChange(of: viewModel.nowPlayingState) { _, _ in
            updateCachedArtwork()
        }
        .onAppear {
            updateCachedArtwork()
        }
    }

    private func updateCachedArtwork() {
        if let data = viewModel.nowPlayingState.artworkData, let img = NSImage(data: data) {
            cachedArtwork = img
        } else if let bundleId = viewModel.nowPlayingState.bundleIdentifier,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            cachedArtwork = NSWorkspace.shared.icon(forFile: appURL.path)
        } else if let pid = viewModel.nowPlayingState.pid,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let appURL = app.bundleURL {
            cachedArtwork = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            cachedArtwork = nil
        }
    }

    // MARK: - Idle View (No media playing)
    private var idleView: some View {
        Button(action: {
            viewModel.activateNowPlayingSource()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: buttonIconSize * 1.15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: artworkSize, height: artworkSize)
                    .background(
                        RoundedRectangle(cornerRadius: artworkSize * 0.24, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                Text("No Music")
                    .font(.system(size: titleFontSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 7)
            .frame(minWidth: iconSize * 2.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active View (Playing or Paused)
    private var activeView: some View {
        HStack(spacing: 8) {
            // Interactive source opener: clicking artwork + metadata activates the app
            Button(action: {
                viewModel.activateNowPlayingSource()
            }) {
                HStack(spacing: 8) {
                    artworkView
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: artworkSize * 0.24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1.5)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.nowPlayingState.title ?? "Unknown Title")
                            .font(.system(size: titleFontSize, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(viewModel.nowPlayingState.artist ?? "Unknown Artist")
                            .font(.system(size: artistFontSize, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(minWidth: iconSize * 1.1, maxWidth: iconSize * 2.2, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Transport Controls: Isolated from the app opener
            HStack(spacing: 4) {
                // Previous Track
                Button(action: {
                    viewModel.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: buttonIconSize * 0.85, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                        .frame(width: buttonIconSize * 1.8, height: buttonIconSize * 1.8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Play / Pause
                Button(action: {
                    viewModel.togglePlayPause()
                }) {
                    Image(systemName: viewModel.nowPlayingState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: buttonIconSize * 1.05, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: buttonIconSize * 2.0, height: buttonIconSize * 2.0)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                // Next Track
                Button(action: {
                    viewModel.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: buttonIconSize * 0.85, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                        .frame(width: buttonIconSize * 1.8, height: buttonIconSize * 1.8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Artwork View
    @ViewBuilder
    private var artworkView: some View {
        if let cachedArtwork {
            Image(nsImage: cachedArtwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: artworkSize * 0.45, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}
