import SwiftUI
import TappyCore

/// Parent-facing settings overlay: theme and scene pickers plus the
/// audio toggles. Shown over the playfield; while it is open the input
/// catcher is deactivated so buttons receive clicks normally.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var onClose: () -> Void
    var onQuit: () -> Void

    @State private var showAbout = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Info button rides in the title row: the About page adds
                // zero height to this panel.
                Text(L10n.settingsTitle)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Button {
                            showAbout = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(L10n.settingsAboutButton))
                        // Smoke harness presses this via AX; a stable
                        // identifier avoids any localized-label lookup.
                        .accessibilityIdentifier("settings.about")
                    }

                // Positioning statement, parent-facing: says what the
                // app is (an early-learning app) and what it is not
                // (no ads / offline / no IAP) in one breath.
                Text(L10n.settingsAbout)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // Theme picker: one theme at a time. Menu style scales to
                // any number of packs (a segmented row would overflow).
                if PackCatalog.shared.packIDs.count > 1 {
                    Picker(L10n.settingsTheme, selection: $settings.activePackID) {
                        ForEach(PackCatalog.shared.packIDs, id: \.self) { packID in
                            Text(PackCatalog.shared.displayName(forPack: packID))
                                .tag(packID)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    // Demo-recording harness presses this via AX; a
                    // stable identifier avoids localized-label lookup.
                    .accessibilityIdentifier("settings.theme")
                }

                // Scene picker (active theme only).
                HStack(spacing: 12) {
                    ForEach(settings.activeScenes) { scene in
                        Button {
                            settings.scene = scene
                        } label: {
                            Text(scene.displayName(for: .current))
                                .font(.title3)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(
                                    settings.scene == scene
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.15),
                                    in: .rect(cornerRadius: 10)
                                )
                                .foregroundStyle(settings.scene == scene ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Audio toggles.
                Toggle(L10n.settingsSound, isOn: $settings.soundEnabled)
                Toggle(L10n.settingsSpeech, isOn: $settings.speechEnabled)
                Toggle(L10n.settingsShowNames, isOn: $settings.showNames)

                // Toddler lock: kiosk on/off, applied live. Naming the
                // fullscreen mode as a child-safety feature (rather than
                // leaving it unexplained) is what makes it read as a
                // kids-app safety setting instead of game behavior.
                Toggle(L10n.settingsLock, isOn: $settings.toddlerLock)
                    .onChange(of: settings.toddlerLock) { _, on in
                        KioskController.sync(enabled: on)
                    }
                    .accessibilityIdentifier("settings.lock")

                HStack(spacing: 16) {
                    Button(L10n.settingsQuit, role: .destructive, action: onQuit)
                    Spacer()
                    Button(L10n.settingsDone, action: onClose)
                        .keyboardShortcut(.defaultAction)
                }

                // CC-BY 4.0 attribution must be "reasonable to the medium" —
                // the parent-facing settings panel is where we show it.
                // License names stay untranslated on purpose (legal names).
                Text(L10n.settingsCredits)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(width: 520)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))

            // Sits ABOVE the whole panel (a sibling in the ZStack, never
            // a VStack child — it must not take part in this layout).
            if showAbout {
                AcknowledgementsView(onClose: { showAbout = false })
            }
        }
    }
}
