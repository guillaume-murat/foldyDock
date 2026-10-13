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
        iconSize * 0.82
    }

    private var artworkSize: CGFloat {
        iconSize * 0.62
    }

    private var titleFontSize: CGFloat {
        max(9.5, min(12.0, iconSize * 0.19))
    }

    private var artistFontSize: CGFloat {
        max(8.0, min(10.5, iconSize * 0.16))
    }

    private var buttonIconSize: CGFloat {
        max(9.0, min(13.0, iconSize * 0.20))
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
            RoundedRectangle(cornerRadius: capsuleHeight * 0.35, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: capsuleHeight * 0.35, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.20 : 0.10), lineWidth: 0.8)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .onChange(of: viewModel.nowPlayingState.artworkData) { _, newData in
            updateCachedArtwork(newData)
        }
        .onAppear {
            updateCachedArtwork(viewModel.nowPlayingState.artworkData)
        }
    }

    private func updateCachedArtwork(_ data: Data?) {
        guard data != lastArtworkData else { return }
        lastArtworkData = data
        if let data {
            cachedArtwork = NSImage(data: data)
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
                        RoundedRectangle(cornerRadius: artworkSize * 0.28, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                Text("No Music")
                    .font(.system(size: titleFontSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .lineLimit(1)
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 6)
            .frame(minWidth: iconSize * 1.9)
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
                        .clipShape(RoundedRectangle(cornerRadius: artworkSize * 0.28, style: .continuous))
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
