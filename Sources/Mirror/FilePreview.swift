import ImageIO
import Quartz
import SwiftUI

struct ExternalFilePreview: View {
    @EnvironmentObject private var document: DocumentStore
    let url: URL

    private var detail: String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Unknown size"
        let type = values?.contentType?.localizedDescription ?? (url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased())
        return "\(type) · \(size)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { document.closeFilePreview() } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.borderless).help("Back to document")

                Image(systemName: document.isImageFile(url) ? "photo" : "doc.viewfinder")
                    .font(.system(size: 17)).foregroundStyle(document.theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show in Finder") { document.revealInFinder(url) }
                    .buttonStyle(.borderless)
                Button("Open in Default App") { document.openInDefaultApp(url) }
                    .buttonStyle(NativeActionStyle(theme: document.theme))
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(document.theme.workspaceCanvas.opacity(0.4))

            Divider().opacity(0.5)
            if document.isImageFile(url) {
                NativeImagePreview(url: url)
            } else {
                QuickLookPreview(url: url)
            }
        }
    }
}

private struct NativeImagePreview: View {
    let url: URL
    @StateObject private var loader = ImagePreviewLoader()
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color(nsColor: .windowBackgroundColor).opacity(0.18)
                if let image = loader.image {
                    let availableWidth = max(1, geometry.size.width - 40)
                    let availableHeight = max(1, geometry.size.height - 40)
                    let fit = min(1, availableWidth / max(1, image.size.width), availableHeight / max(1, image.size.height))
                    let width = max(1, image.size.width * fit * zoom)
                    let height = max(1, image.size.height * fit * zoom)
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: width, height: height)
                            .frame(
                                minWidth: geometry.size.width,
                                minHeight: geometry.size.height,
                                alignment: .center
                            )
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in zoom = min(8, max(0.2, zoomBase * value)) }
                            .onEnded { _ in zoomBase = zoom }
                    )

                    HStack(spacing: 6) {
                        Button { zoom = max(0.2, zoom / 1.25); zoomBase = zoom } label: { Image(systemName: "minus") }
                        Text("\(Int(zoom * 100))%")
                            .font(.system(size: 9.5, weight: .medium)).frame(width: 42)
                        Button { zoom = min(8, zoom * 1.25); zoomBase = zoom } label: { Image(systemName: "plus") }
                        Button { zoom = 1; zoomBase = 1 } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                            .help("Fit image")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                } else if loader.isLoading {
                    ProgressView("Loading image…")
                        .controlSize(.small)
                } else {
                    ContentUnavailableView(
                        "Image unavailable",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(loader.errorMessage ?? "Mirror couldn’t decode this image.")
                    )
                }
            }
        }
        .task(id: url) {
            zoom = 1
            zoomBase = 1
            await loader.load(url)
        }
    }
}

@MainActor
private final class ImagePreviewLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(_ url: URL) async {
        image = nil
        errorMessage = nil
        isLoading = true
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsampledImage(at: url, maximumPixelSize: 4_096)
        }.value
        guard !Task.isCancelled else { return }
        image = decoded
        isLoading = false
        if decoded == nil { errorMessage = "The file may be damaged or use an unsupported image codec." }
    }

    private nonisolated static func downsampledImage(at url: URL, maximumPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                return NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
            }
        }
        return NSImage(contentsOf: url)
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.previewItem = url as NSURL
        return view!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }
}
