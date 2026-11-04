import SwiftUI

public struct NowPlayingWidget: View {
    @ObservedObject var viewModel: DockViewModel
    public let iconSize: CGFloat
    public let dockHeight: CGFloat

    @State private var isHovered: Bool = false

    public init(viewModel: DockViewModel, iconSize: CGFloat, dockHeight: CGFloat) {
        self.viewModel = viewModel
        self.iconSize = iconSize
        self.dockHeight = dockHeight
    }

    private var capsuleHeight: CGFloat {
        iconSize
    }

    /// Below this icon size, title and artist share a line so the controls still fit underneath.
    private var usesTwoTextLines: Bool {
        iconSize >= 48
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

    private var labelFontSize: CGFloat {
        max(9.0, min(11.5, iconSize * 0.17))
    }

    private var theme: DockTheme {
        viewModel.theme
    }

    public var body: some View {
        ZStack(alignment: .center) {
            // 1. Main Capsule - centered vertically
            activeView
            .frame(height: capsuleHeight)
            .background(
                RoundedRectangle(cornerRadius: capsuleHeight * 0.22, style: .continuous)
                    .fill(theme.widgetBackground(isHovered: isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: capsuleHeight * 0.22, style: .continuous)
                    .stroke(theme.widgetStroke(isHovered: isHovered), lineWidth: 0.8)
            )

            // 2. Title "Music" positioned above the capsule at fixed distance
            if viewModel.config.showAppTitles {
                Text("Music")
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(theme.labelColor(isHovered: isHovered))
                    .shadow(color: theme.labelShadowColor, radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .offset(y: -(iconSize / 2 + viewModel.config.labelDistance))
            }

            // 3. Indicator dot positioned below the capsule when music is currently playing
            if viewModel.nowPlayingState.isPlaying {
                Circle()
                    .fill(theme.indicatorDotColor)
                    .frame(width: 4, height: 4)
                    .shadow(color: theme.indicatorDotShadowColor, radius: 2)
                    .offset(y: iconSize / 2 + viewModel.config.labelDistance)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // The dock takes its width from its content: without this the widget would shrink into
        // whatever width the dock already has instead of making it grow.
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: dockHeight, alignment: .center)
        .zIndex(isHovered ? 10 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.nowPlayingState.isPlaying)
    }

    // MARK: - Active View (Playing or Paused)
    private var activeView: some View {
        VStack(spacing: 1) {
            // Interactive source opener: clicking the metadata activates the app
            Button(action: {
                viewModel.activateNowPlayingSource()
            }) {
                metadataView
                    .frame(minWidth: iconSize * 1.9, maxWidth: iconSize * 2.6)
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
                        .foregroundColor(theme.widgetTransportSecondaryColor)
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
                        .foregroundColor(theme.widgetPlayIconColor)
                        .frame(width: buttonIconSize * 2.0, height: buttonIconSize * 2.0)
                        .background(
                            Circle()
                                .fill(theme.widgetPlayCircleBackground)
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
                        .foregroundColor(theme.widgetTransportSecondaryColor)
                        .frame(width: buttonIconSize * 1.8, height: buttonIconSize * 1.8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var metadataView: some View {
        let title = viewModel.nowPlayingState.title ?? "Unknown Title"
        let artist = viewModel.nowPlayingState.artist ?? "Unknown Artist"

        if usesTwoTextLines {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundColor(theme.widgetTitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(artist)
                    .font(.system(size: artistFontSize, weight: .medium))
                    .foregroundColor(theme.widgetArtistColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text("\(title) · \(artist)")
                .font(.system(size: artistFontSize, weight: .semibold))
                .foregroundColor(theme.widgetTitleColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
