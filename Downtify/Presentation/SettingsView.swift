import SwiftUI

/// Who is signed in and where, shown at the top of Settings.
struct SettingsAccount {
    let name: String
    let server: String
    let role: String?
    let signOut: () -> Void
}

struct SettingsView: View {
    @Binding var appearance: DowntifyAppearance
    @Binding var language: String
    @Binding var networkOperationLimit: Int
    @ObservedObject var playback: PlaybackController
    var showsDoneButton = true
    var account: SettingsAccount? = nil
    var storage: StorageSettingsModel? = nil
    @AppStorage("debug.networkOverlay.enabled") private var networkOverlayEnabled = false
    @State private var showingAbout = false

    private let languages: [(String, String)] = [
        ("system", "System default"), ("bg", "Български"), ("en", "English"),
        ("fr", "Français"), ("el", "Ελληνικά"), ("hu", "Magyar"),
        ("pt-BR", "Português (Brasil)"), ("es", "Español"), ("tr", "Türkçe")
    ]

    var body: some View {
        Form {
            if let account {
                Section {
                    HStack(spacing: 14) {
                        ProfileAvatar(name: account.name, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: account.name).font(.headline)
                            Label { Text(verbatim: account.server) } icon: { Image(systemName: "server.rack") }
                                .font(.subheadline).foregroundStyle(.secondary)
                            if account.role?.lowercased() == "admin" {
                                Text("Administrator").font(.caption.weight(.semibold)).foregroundStyle(DowntifyStyle.accent)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    Button("Sign out", role: .destructive, action: account.signOut)
                } header: {
                    Text("Account")
                }
            }
            Section {
                Toggle("Autoplay", isOn: Binding(get: { playback.autoplay }, set: { playback.setAutoplay($0) }))
                    .tint(DowntifyStyle.brand)
                Text("When your music ends, keep playing similar songs.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Crossfade")
                        Spacer()
                        Group {
                            if playback.crossfade == 0 { Text("Off") } else { Text("\(Int(playback.crossfade)) s") }
                        }
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { playback.crossfade }, set: { playback.setCrossfade($0) }),
                           in: 0...PlaybackCrossfade.maximum, step: 1)
                        .tint(DowntifyStyle.brand)
                        .accessibilityLabel("Crossfade")
                        .accessibilityValue(playback.crossfade == 0 ? String(localized: "Off")
                                            : String(localized: "\(Int(playback.crossfade)) seconds"))
                }
                Text("Blends the end of each song into the next. Songs that follow each other on an album stay gapless.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    EqualizerView(playback: playback)
                } label: {
                    LabeledContent("Equalizer") {
                        Text(LocalizedStringKey(!playback.equalizer.enabled ? "Off" : playback.equalizer.preset?.name ?? "Custom"))
                    }
                }
                .accessibilityIdentifier("settings.equalizer")
                Toggle("Switch quality immediately", isOn: Binding(
                    get: { playback.immediateQualitySwitch },
                    set: { playback.setImmediateQualitySwitch($0) }
                ))
                Text("When off, the current song keeps its quality when possible. The next song uses the new network’s quality.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Playback")
            }
            Section("Diagnostics") {
                Toggle("Network debug overlay", isOn: $networkOverlayEnabled)
                Text("Shows active and waiting network work, playback queue depth, and offline transfer state.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Advanced") {
                Stepper("Concurrent network requests: \(networkOperationLimit)", value: $networkOperationLimit,
                        in: NetworkOperationCoordinator.allowedLimits)
                Text("Limits simultaneous network activity, including offline downloads. Changes apply immediately.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(DowntifyAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .accessibilityHint("Choose the app color appearance")
            }
            Section("Language") {
                Picker("App language", selection: $language) {
                    ForEach(languages, id: \.0) { code, title in
                        Text(code == "system" ? String(localized: "System default") : title).tag(code)
                    }
                }
                .accessibilityHint("Choose the language used in the app")
                Text("Some server supplied content, including music titles and descriptions, stays in its original language.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let storage {
                StorageSection(model: storage)
            }
            Section("About") {
                Button("About Downtify") { showingAbout = true }
                LabeledContent("Version", value: versionText)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack { AboutView(version: versionText) }
        }
    }

    @Environment(\.dismiss) private var dismiss
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

struct AboutView: View {
    let version: String
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Text("Downtify").font(.title.bold())
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }
            Section {
                Text("Michael Moskie")
                    .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                aboutSectionHeader("Author")
            }
            Section {
                Text("Version \(version)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                ForEach(Array(releaseNotes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                aboutSectionHeader("What's new in this build")
            }
            Section {
                Link("iOS client repository", destination: URL(string: "https://github.com/michaelmoskie/Downtify-IOS-Client")!)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Link("Server source code", destination: URL(string: "https://github.com/henriquesebastiao/downtify")!)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Link("Report a bug", destination: URL(string: "https://github.com/michaelmoskie/Downtify-IOS-Client/issues")!)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } header: {
                aboutSectionHeader("Project")
            }
            Section {
                Text("Downtify for iOS is an independent client for the Downtify server. Artwork, names, and media are supplied by your server and their respective rights holders.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("The iOS and Android clients are licensed under GNU GPL v3. The Downtify server is licensed under GNU AGPL v3.")
                    .fixedSize(horizontal: false, vertical: true)
                Link("iOS client license (GPL-3.0)", destination: URL(string: "https://github.com/michaelmoskie/Downtify-IOS-Client/blob/main/LICENSE")!)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Link("Server license (AGPL-3.0)", destination: URL(string: "https://github.com/henriquesebastiao/downtify/blob/main/LICENSE")!)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Link("Android reference app license (GPL-3.0)", destination: URL(string: "https://github.com/henriquesebastiao/downtify-android/blob/100be83e49c3250424e6326670a73bff69325b73/LICENSE")!)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } header: {
                aboutSectionHeader("Acknowledgments and licenses")
            }
            Section {
                Text("Downtify is provided as-is. Availability and playback depend on your server and its media sources.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                aboutSectionHeader("Disclaimer")
            }
        }
        .navigationTitle("About")
        .downtifyScrollEndClearance()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func aboutSectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var releaseNotes: [String] {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return notes
    }
}
