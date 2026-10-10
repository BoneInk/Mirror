import SwiftUI
import AppKit

struct SoftwareUpdateView: View {
    @ObservedObject var updates: SoftwareUpdateStore
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Software Update").font(.title2.bold())
            Text("Mirror \(updates.currentVersion)").font(.headline)
            Toggle("Automatically download and install updates", isOn: $updates.automaticallyUpdates)
            Text("Check daily. Updates download from GitHub Releases and install after you quit, without interrupting your writing.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                if updates.busy { ProgressView().controlSize(.small) }
                Text(LocalizedStringKey(updates.status))
            }
            if let version = updates.availableVersion { Text("New version: \(version)").font(.headline) }
            if let error = updates.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let checked = updates.lastChecked {
                HStack { Text("Last checked:"); Text(checked, style: .date); Text(checked, style: .time) }
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Check for Updates…") { Task { await updates.check() } }
                    .disabled(updates.busy || updates.readyToInstall)
                if updates.readyToInstall {
                    Button("Restart to Update") { updates.restart(document: document) }
                } else if updates.availableVersion != nil {
                    Button("Download Update") { Task { await updates.download() } }.disabled(updates.busy)
                }
                if let installer = updates.installerURL, !updates.readyToInstall {
                    Button("Open Installer") { NSWorkspace.shared.open(installer) }
                }
            }
            Link("Release Notes", destination: URL(string: "https://github.com/BoneInk/Mirror/releases")!)
            Spacer()
        }
        .padding(8)
    }
}
