import SwiftUI

struct MarkdownTableBuilderView: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var columns = 3
    @State private var bodyRows = 3
    @State private var alignments: [MarkdownTableAlignment] = Array(repeating: .leading, count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "tablecells")
                    .font(.system(size: 21)).foregroundStyle(document.theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Insert Markdown Table").font(.title3.bold())
                    Text("Create a GFM-compatible table and choose each column’s alignment.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 12) {
                LabeledContent("Columns") {
                    Stepper("\(columns)", value: $columns, in: 2...10)
                        .fixedSize()
                }
                Divider()
                LabeledContent("Body rows") {
                    Stepper("\(bodyRows)", value: $bodyRows, in: 1...20)
                        .fixedSize()
                }
            }
            .padding(16)
            .background { ContentSurface(theme: document.theme) }

            VStack(alignment: .leading, spacing: 8) {
                Text("COLUMN ALIGNMENT")
                    .font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(0..<columns, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Column \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                                Picker("Column \(index + 1)", selection: alignmentBinding(index)) {
                                    ForEach(MarkdownTableAlignment.allCases) { alignment in
                                        Text(alignment.rawValue).tag(alignment)
                                    }
                                }
                                .labelsHidden().pickerStyle(.menu).frame(width: 105)
                            }
                            .padding(9)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("PREVIEW").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(previewText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                        .background(Color(hex: document.theme.codeHex), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color(hex: document.theme.lineHex)) }
                }
                if bodyRows > 4 {
                    Text("Preview shows 4 of \(bodyRows) body rows.").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()
            HStack {
                Text("The header placeholders stay selected-ready in the source editor.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Insert Table") {
                    document.insertMarkdownTable(columns: columns, bodyRows: bodyRows, alignments: alignments)
                    dismiss()
                }
                .buttonStyle(NativeActionStyle(theme: document.theme, prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 540)
        .nativeDialog(theme: document.theme)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .onChange(of: columns) { _, value in
            if alignments.count < value {
                alignments.append(contentsOf: Array(repeating: .leading, count: value - alignments.count))
            } else if alignments.count > value {
                alignments.removeLast(alignments.count - value)
            }
        }
    }

    private func alignmentBinding(_ index: Int) -> Binding<MarkdownTableAlignment> {
        Binding {
            index < alignments.count ? alignments[index] : .leading
        } set: { value in
            guard index < alignments.count else { return }
            alignments[index] = value
        }
    }

    private var previewText: String {
        let header = "| " + (1...columns).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let delimiter = "| " + alignments.prefix(columns).map(\.marker).joined(separator: " | ") + " |"
        let row = "| " + Array(repeating: "   ", count: columns).joined(separator: " | ") + " |"
        return ([header, delimiter] + Array(repeating: row, count: min(bodyRows, 4))).joined(separator: "\n")
    }
}
