import SwiftUI

struct DocumentHistoryView: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    private var selectedEntry: DocumentHistoryEntry? {
        document.documentHistory.first { $0.id == selectedID } ?? document.documentHistory.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18)).foregroundStyle(document.theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Document History").font(.headline)
                    Text(document.fileURL?.lastPathComponent ?? document.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show Files") { document.revealDocumentHistoryFolder() }
                Button("Clear…", role: .destructive) { document.clearDocumentHistory() }
                    .disabled(document.documentHistory.isEmpty)
            }
            .padding(14)

            Divider()

            if document.isLoadingDocumentHistory {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading saved versions…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if document.documentHistory.isEmpty {
                ContentUnavailableView(
                    "No Saved Versions Yet",
                    systemImage: "clock",
                    description: Text("Mirror keeps periodic versions after this document is saved or autosaved.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(document.documentHistory, selection: $selectedID) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 11.5, weight: .semibold))
                            HStack(spacing: 6) {
                                Text(relativeTime(entry.createdAt))
                                Text("·")
                                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                                Text("·")
                                Text(entry.lineEndingRawValue)
                            }
                            .font(.system(size: 9.5)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(entry.id)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(document.theme.workspaceCanvas.opacity(0.5))
                    .frame(minWidth: 245, idealWidth: 270, maxWidth: 320)

                    if let entry = selectedEntry {
                        VStack(spacing: 0) {
                            HStack {
                                Text(entry.createdAt.formatted(date: .complete, time: .standard))
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(WritingStats(text: entry.text).characters) characters")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).frame(height: 38)
                            Divider()
                            ScrollView([.vertical, .horizontal]) {
                                Text(previewText(entry))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(18)
                            }
                        }
                        .frame(minWidth: 470)
                    }
                }
            }

            Divider()
            HStack {
                Text("Up to 30 versions and 64 MB are retained per document.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore Selected Version") {
                    guard let entry = selectedEntry else { return }
                    document.restoreDocumentHistory(entry)
                    dismiss()
                }
                .buttonStyle(NativeActionStyle(theme: document.theme, prominent: true))
                .disabled(selectedEntry == nil)
            }
            .padding(12)
        }
        .frame(width: 900, height: 590)
        .nativeDialog(theme: document.theme)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .onAppear { document.loadDocumentHistory() }
        .onChange(of: document.documentHistory) { _, entries in
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
        }
    }

    private func previewText(_ entry: DocumentHistoryEntry) -> String {
        let limit = 200_000
        guard entry.text.count > limit else { return entry.text }
        return String(entry.text.prefix(limit)) + "\n\n… Preview truncated; restoring still uses the complete version."
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
