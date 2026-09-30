import SwiftUI
import TappyCore

/// Parent-facing "About this app" page. The backstory comes first —
/// a dad's gift to his daughter, a prop for parent-child play — which
/// frames the app (for parents and reviewers alike) as an early-learning
/// app rather than a game. The source-code link follows (the project is
/// MIT-licensed open source), then the complete licence texts — the
/// app's own MIT plus the third-party works (Twemoji artwork under
/// CC-BY 4.0 requires attribution regardless of the app's own licence).
struct AcknowledgementsView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                // Smoke observability: the harness asserts these lines.
                .onAppear { SmokeMode.log("about open") }
                .onDisappear { SmokeMode.log("about closed") }

            VStack(spacing: 16) {
                Text(L10n.aboutTitle)
                    .font(.title2.bold())

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.aboutStory)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)

                        Text(L10n.aboutSourceCode)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Verified-but-never-pressed by the smoke
                        // harness: pressing opens a browser.
                        Link("github.com/F2077/Tappy",
                             destination: URL(string: "https://github.com/F2077/Tappy")!)
                            .font(.caption)
                            .accessibilityIdentifier("about.sourceLink")

                        Text(L10n.aboutAckTitle)
                            .font(.headline)
                            .padding(.top, 8)

                        ForEach(LicenseEntry.canonical) { entry in
                            section(entry)
                            if entry.id != LicenseEntry.canonical.last?.id {
                                Divider()
                            }
                        }

                        // Bundled-without-copy notes (see NOTICE.txt).
                        Text(L10n.aboutLegalNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                Button(L10n.settingsDone, action: onClose)
                    .keyboardShortcut(.defaultAction)
                    // Distinct from the settings panel's Done so the
                    // smoke harness can press THIS one while the About
                    // page covers the panel behind it.
                    .accessibilityIdentifier("about.done")
            }
            .padding(28)
            .frame(width: 560)
            // Flexible height: shrinks to fit small windows (the 960×540
            // demo-recording window) instead of overflowing past them.
            .frame(maxHeight: 640)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

    private func section(_ entry: LicenseEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.subheadline.bold())
            Text("\(entry.copyright) · \(entry.licenseName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Legal texts ship verbatim; selectable so a reviewer can
            // copy the notice without leaving the app.
            Text(entry.text)
                .font(.caption2)
                .textSelection(.enabled)
        }
    }
}

/// One bundled licence. Texts live in the Licenses resource directory,
/// copied verbatim from their authoritative sources (creativecommons.org
/// legal codes, the SwiftDraw checkout). Titles localize via
/// "license.<id>"; copyright and licence names stay untranslated on
/// purpose (legal identifiers).
struct LicenseEntry: Identifiable {
    let id: String
    let copyright: String
    let licenseName: String
    /// Resource name (without extension) inside the Licenses directory.
    let resource: String

    var title: String { L10n.licenseTitle(id) }

    var text: String {
        let url = TappyResources.bundle.url(
            forResource: resource, withExtension: "txt", subdirectory: "Licenses")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            // Never crash the parent gate over a missing notice; the
            // one-liner keeps attribution present regardless.
            return "\(licenseName) — \(copyright)"
        }
        return text
    }

    /// The app's own licence first (the source is MIT-licensed open
    /// source), then the third-party works it bundles.
    static let canonical: [LicenseEntry] = [
        LicenseEntry(
            id: "tappy",
            copyright: "© 2026 F2077",
            licenseName: "MIT License", resource: "mit"),
        LicenseEntry(
            id: "twemoji",
            copyright: "© 2019-2024 Twitter, Inc. and other contributors",
            licenseName: "CC-BY 4.0", resource: "cc-by-4.0"),
        LicenseEntry(
            id: "sounds",
            copyright: "OpenGameArt.org contributors",
            licenseName: "CC0 1.0 (public domain)", resource: "cc0-1.0"),
        LicenseEntry(
            id: "swiftdraw",
            copyright: "Copyright (c) 2019 Simon Whitty",
            licenseName: "zlib License", resource: "zlib"),
    ]
}
