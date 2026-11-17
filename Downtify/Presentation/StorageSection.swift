import SwiftUI

struct StorageSection: View {
    @ObservedObject var model: StorageSettingsModel
    @State private var confirming = false
    @State private var showingOutcome = false

    var body: some View {
        Section {
            row("Downloads", model.downloadsBytes)
            row("Caches", model.cachesBytes)
            row("Library Data", model.libraryDataBytes)
            row("Total", model.totalBytes)
            Button(role: .destructive) { confirming = true } label: {
                HStack {
                    Text("Clear App Cache and Saved Data")
                    if model.isClearing { Spacer(); ProgressView() }
                }
            }
            .disabled(model.isClearing)
            .accessibilityHint(String(localized: "Removes downloads, caches and library data from this device. You stay signed in."))
        } header: {
            Text("Storage")
        } footer: {
            Text("Removes songs added to this device, caches and local library data. You stay signed in and your library syncs again from the server.")
        }
        .task { await model.load() }
        .confirmationDialog("Clear App Cache and Saved Data?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                Task {
                    await model.clear()
                    showingOutcome = model.lastOutcome != nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.confirmationMessage)
        }
        .alert(outcomeTitle, isPresented: $showingOutcome) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(outcomeMessage)
        }
    }

    private func row(_ title: LocalizedStringKey, _ bytes: Int64?) -> some View {
        LabeledContent(title, value: bytes.map(StorageSettingsModel.formatted) ?? String(localized: "Calculating…"))
    }

    private var outcomeTitle: String {
        if case .partial = model.lastOutcome { return String(localized: "Some Data Could Not Be Cleared") }
        return String(localized: "Storage Cleared")
    }

    private var outcomeMessage: String {
        switch model.lastOutcome {
        case .success(let freed)?:
            let size = StorageSettingsModel.formatted(freed)
            return String(localized: "Freed \(size).")
        case .partial?:
            return String(localized: "Try again. If it keeps happening, restart the app.")
        case nil:
            return ""
        }
    }
}
