import SwiftUI
import AppKit

public struct FoldyDockSettingsView: View {
    @ObservedObject var viewModel: DockViewModel
    public var onClose: (() -> Void)?

    @State private var showingResetConfirmation: Bool = false

    public init(viewModel: DockViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Window Header
            HStack(spacing: 14) {
                Image(nsImage: LogoProvider.shared.logoImage(size: 48))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FoldyDock")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Paramètres & Personnalisation")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("v1.1.0")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Section 1: Démarrage & Masquage automatique
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Lancer FoldyDock au démarrage du Mac", isOn: Binding(
                                get: { viewModel.config.launchAtLogin },
                                set: { newValue in
                                    viewModel.setLaunchAtLogin(newValue)
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .medium))

                            Text("Démarre automatiquement FoldyDock lors de l'ouverture de votre session macOS.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)

                            Divider()

                            Toggle("Masquage automatique (Autohide)", isOn: Binding(
                                get: { viewModel.config.autohideEnabled },
                                set: { _ in viewModel.toggleAutohide() }
                            ))
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .medium))

                            Text("Rétracte automatiquement le dock vers le bas de l'écran lorsque le curseur quitte la zone.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)

                            if viewModel.config.autohideEnabled {
                                Divider()

                                // Show delay
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Délai d'apparition (Show delay)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(String(format: "%.1f", viewModel.config.showDelay)) s")
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.12))
                                            .cornerRadius(4)
                                    }

                                    Slider(
                                        value: Binding(
                                            get: { viewModel.config.showDelay },
                                            set: { newValue in
                                                viewModel.config.showDelay = newValue
                                                viewModel.saveConfig()
                                            }
                                        ),
                                        in: 0.0...1.5,
                                        step: 0.1
                                    )
                                }

                                Divider()

                                // Hide delay
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Délai de masquage (Hide delay)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(String(format: "%.1f", viewModel.config.autohideDelay)) s")
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.12))
                                            .cornerRadius(4)
                                    }

                                    Slider(
                                        value: Binding(
                                            get: { viewModel.config.autohideDelay },
                                            set: { newValue in
                                                viewModel.config.autohideDelay = newValue
                                                viewModel.saveConfig()
                                            }
                                        ),
                                        in: 0.1...1.5,
                                        step: 0.1
                                    )
                                }
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("Comportement", systemImage: "eye")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    // Section 2: Dimensions & Marges
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            // Icon size
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Taille des icônes")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(viewModel.config.iconSize)) pt")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.config.iconSize },
                                        set: { newValue in
                                            viewModel.config.iconSize = newValue
                                            viewModel.saveConfig()
                                        }
                                    ),
                                    in: 32...96,
                                    step: 2
                                )

                                HStack(spacing: 8) {
                                    ForEach([40, 56, 72, 88], id: \.self) { size in
                                        Button("\(size) pt") {
                                            viewModel.config.iconSize = Double(size)
                                            viewModel.saveConfig()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .tint(Int(viewModel.config.iconSize) == size ? Color.accentColor : Color.secondary)
                                    }
                                }
                            }

                            Divider()

                            // Espacement entre les icônes (marge horizontale entre éléments)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Espacement entre les icônes (marge)")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(viewModel.config.itemSpacing)) pt")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.config.itemSpacing },
                                        set: { newValue in
                                            viewModel.config.itemSpacing = newValue
                                            viewModel.saveConfig()
                                        }
                                    ),
                                    in: 4...28,
                                    step: 1
                                )

                                HStack(spacing: 8) {
                                    ForEach([8, 10, 12, 16, 20], id: \.self) { spacing in
                                        Button("\(spacing) pt") {
                                            viewModel.config.itemSpacing = Double(spacing)
                                            viewModel.saveConfig()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .tint(Int(viewModel.config.itemSpacing) == spacing ? Color.accentColor : Color.secondary)
                                    }
                                }
                            }

                            Divider()

                            // Marge des extrémités du dock (horizontal padding)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Marge des extrémités du dock (padding)")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(viewModel.config.horizontalPadding)) pt")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.config.horizontalPadding },
                                        set: { newValue in
                                            viewModel.config.horizontalPadding = newValue
                                            viewModel.saveConfig()
                                        }
                                    ),
                                    in: 0...40,
                                    step: 1
                                )

                                HStack(spacing: 8) {
                                    ForEach([8, 12, 16, 24], id: \.self) { pad in
                                        Button("\(pad) pt") {
                                            viewModel.config.horizontalPadding = Double(pad)
                                            viewModel.saveConfig()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .tint(Int(viewModel.config.horizontalPadding) == pad ? Color.accentColor : Color.secondary)
                                    }
                                }
                            }

                            Divider()

                            // Vertical padding
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Marge verticale (padding)")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(viewModel.config.verticalPadding)) pt")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.config.verticalPadding },
                                        set: { newValue in
                                            viewModel.config.verticalPadding = newValue
                                            viewModel.saveConfig()
                                        }
                                    ),
                                    in: 4...48,
                                    step: 1
                                )
                            }

                            Divider()

                            // Distance titres & pastilles
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Distance titres & pastilles")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(viewModel.config.labelDistance)) px")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.config.labelDistance },
                                        set: { newValue in
                                            viewModel.config.labelDistance = newValue
                                            viewModel.saveConfig()
                                        }
                                    ),
                                    in: 2...24,
                                    step: 1
                                )
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("Dimensions & Marges", systemImage: "aspectratio")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    // Section 3: Affichage & Titres
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Afficher les titres des applications", isOn: Binding(
                                get: { viewModel.config.showAppTitles },
                                set: { newValue in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.config.showAppTitles = newValue
                                    }
                                    viewModel.saveConfig()
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .medium))

                            Divider()

                            Toggle("Afficher les titres des dossiers", isOn: Binding(
                                get: { viewModel.config.showFolderTitles },
                                set: { newValue in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.config.showFolderTitles = newValue
                                    }
                                    viewModel.saveConfig()
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .medium))



                            Divider()

                            Toggle("Lanceur d'applications (logo FoldyDock)", isOn: Binding(
                                get: { viewModel.config.showAppLauncher },
                                set: { newValue in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.config.showAppLauncher = newValue
                                    }
                                    viewModel.saveConfig()
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .medium))

                            Divider()

                            // Opacité des applications cachées / réduites
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Opacité des applications cachées")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(viewModel.config.hiddenAppOpacity * 100)) %")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.config.hiddenAppOpacity },
                                        set: { newValue in
                                            viewModel.config.hiddenAppOpacity = newValue
                                            viewModel.saveConfig()
                                        }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )

                                Text("Réduit l'opacité des applications masquées (⌘H) ou dont les fenêtres sont réduites (bouton jaune).")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("Affichage & Titres", systemImage: "textformat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    // Section 4: Organisation du Dock
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Personnalisez l'agencement du dock avec des séparateurs et des dossiers.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        viewModel.insertSeparator(at: viewModel.items.count)
                                    }
                                } label: {
                                    Label("Ajouter un séparateur", systemImage: "line.diagonal")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        viewModel.createEmptyFolder(at: viewModel.items.count)
                                    }
                                } label: {
                                    Label("Nouveau dossier", systemImage: "folder.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            Divider()

                            Toggle("Afficher la corbeille", isOn: Binding(
                                get: { viewModel.config.showTrash },
                                set: { _ in
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        viewModel.toggleTrash()
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.system(size: 13, weight: .medium))

                            Text("Affiche la corbeille macOS à l'extrémité droite du dock.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    } label: {
                        Label("Organisation", systemImage: "square.grid.2x2")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    // Section 5: Maintenance & Quitter
                    VStack(spacing: 10) {
                        Button(action: {
                            showingResetConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restaurer les applications par défaut")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .alert(isPresented: $showingResetConfirmation) {
                            Alert(
                                title: Text("Réinitialiser le Dock"),
                                message: Text("Voulez-vous restaurer la configuration et les applications par défaut de FoldyDock ?"),
                                primaryButton: .destructive(Text("Réinitialiser")) {
                                    viewModel.resetToDefaults()
                                },
                                secondaryButton: .cancel(Text("Annuler"))
                            )
                        }

                        Button(action: {
                            NSApp.terminate(nil)
                        }) {
                            HStack {
                                Image(systemName: "power")
                                Text("Quitter FoldyDock")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 580)
    }
}
