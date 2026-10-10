import AppKit
import CryptoKit
import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (3...4).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              fields.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = fields.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }
    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
        let state: String
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [Asset]
    var macInstaller: Asset? {
        assets.first { $0.name == "Mirror-\(tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name).dmg" && $0.state == "uploaded" }
    }
}

enum SoftwareUpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let key): return NSLocalizedString(key, comment: "Software update error") }
    }
}

struct GitHubUpdateClient {
    var session: URLSession = .shared
    static let releasesURL = URL(string: "https://api.github.com/repos/BoneInk/Mirror/releases?per_page=100")!
    static let manifestURL = URL(string: "https://github.com/BoneInk/Mirror/releases/latest/download/Mirror-update.json")!

    func latestMacRelease() async throws -> GitHubRelease? {
        do { return try await apiMacRelease() }
        catch {
            let apiError = error
            do {
                var request = URLRequest(url: Self.manifestURL)
                request.timeoutInterval = 30
                let (data, response) = try await session.data(for: request)
                try Self.validate(response)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !release.draft, !release.prerelease, ReleaseVersion(release.tag_name) != nil,
                      release.macInstaller != nil else { throw apiError }
                return release
            } catch { throw apiError }
        }
    }

    private func apiMacRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: Self.releasesURL)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Mirror-Update", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        return releases.filter { !$0.draft && !$0.prerelease && ReleaseVersion($0.tag_name) != nil && $0.macInstaller != nil }
            .max { ReleaseVersion($0.tag_name)! < ReleaseVersion($1.tag_name)! }
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SoftwareUpdateError.message("GitHub is unavailable. Please try again later.")
        }
        guard http.statusCode == 200 else {
            throw SoftwareUpdateError.message(String(format: NSLocalizedString("GitHub returned HTTP %d. Please try again later.", comment: "Software update"), http.statusCode))
        }
    }

    static func trustedAssetURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
            url.path.hasPrefix("/BoneInk/Mirror/releases/download/") && url.query == nil && url.fragment == nil && (url.port == nil || url.port == 443)
    }

    func download(_ release: GitHubRelease, to directory: URL) async throws -> URL {
        guard let asset = release.macInstaller, Self.trustedAssetURL(asset.browser_download_url),
              asset.size > 0 && asset.size < 2_000_000_000 else {
            throw SoftwareUpdateError.message("The release installer is invalid.")
        }
        var expected: String?
        if let digest = asset.digest, digest.hasPrefix("sha256:") { expected = String(digest.dropFirst(7)) }
        if expected == nil, let sums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }), Self.trustedAssetURL(sums.browser_download_url) {
            let (data, response) = try await session.data(from: sums.browser_download_url)
            try Self.validate(response)
            expected = Self.checksum(in: String(decoding: data, as: UTF8.self), filename: asset.name)
        }
        guard let expected, expected.count == 64, expected.allSatisfy({ $0.isHexDigit }) else {
            throw SoftwareUpdateError.message("The release has no valid SHA-256 checksum.")
        }
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 300
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.validate(response)
        try Self.verify(file: temporary, size: asset.size, checksum: expected)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    static func checksum(in text: String, filename: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if fields.count == 2, fields[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "") == filename {
                return String(fields[0])
            }
        }
        return nil
    }

    static func verify(file: URL, size: Int64, checksum: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard Int64(data.count) == size, digest == checksum.lowercased() else {
            throw SoftwareUpdateError.message("Installer verification failed. Nothing was installed.")
        }
    }
}

@MainActor
final class SoftwareUpdateStore: ObservableObject {
    @Published var automaticallyUpdates: Bool {
        didSet {
            defaults.set(automaticallyUpdates, forKey: "MirrorAutomaticallyUpdates")
            if let marker { if automaticallyUpdates { try? Data().write(to: marker) } else { try? FileManager.default.removeItem(at: marker) } }
            if readyToInstall { status = automaticallyUpdates ? "Update ready. It will install after you quit Mirror." : "Automatic installation paused. Choose Restart to Update to install now." }
        }
    }
    @Published private(set) var status = "Updates are checked automatically once a day."
    @Published private(set) var busy = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var readyToInstall = false
    @Published private(set) var installerURL: URL?
    @Published private(set) var lastChecked: Date?
    @Published var error: String?
    let currentVersion: String
    private let defaults: UserDefaults
    private let client: GitHubUpdateClient
    private var release: GitHubRelease?
    private var marker: URL?
    private var restartMarker: URL?

    init(defaults: UserDefaults = .standard, client: GitHubUpdateClient = GitHubUpdateClient(), version: String? = nil) {
        self.defaults = defaults; self.client = client
        currentVersion = version ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        automaticallyUpdates = defaults.object(forKey: "MirrorAutomaticallyUpdates") as? Bool ?? true
        lastChecked = defaults.object(forKey: "MirrorUpdateLastChecked") as? Date
        let errorFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mirror/Updates/last-install-error.txt")
        if FileManager.default.fileExists(atPath: errorFile.path) {
            error = NSLocalizedString("The previous automatic installation failed. Please retry or open the installer.", comment: "Software update")
        }
    }

    func check(automatic: Bool = false) async {
        guard !busy, !readyToInstall else { return }
        if automatic && (!automaticallyUpdates || Date().timeIntervalSince(lastChecked ?? .distantPast) < 86400) { return }
        busy = true; error = nil; status = "Checking for updates…"
        defer { busy = false }
        do {
            guard let found = try await client.latestMacRelease(), let version = ReleaseVersion(found.tag_name), let current = ReleaseVersion(currentVersion) else {
                throw SoftwareUpdateError.message("No compatible macOS release was found.")
            }
            lastChecked = Date(); defaults.set(lastChecked, forKey: "MirrorUpdateLastChecked")
            if version > current {
                release = found; availableVersion = found.tag_name
                status = "An update is available."
                if automatic && automaticallyUpdates { try await prepare(found) }
            } else { status = "Mirror is up to date." }
        } catch { self.error = error.localizedDescription; status = "Unable to check for updates." }
    }

    func download() async {
        guard !busy, let release else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await prepare(release) }
        catch { self.error = error.localizedDescription; status = "Unable to prepare the update." }
    }

    private func prepare(_ release: GitHubRelease) async throws {
        status = "Downloading and verifying the update…"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mirror/Updates/\(UUID().uuidString)")
        let dmg = try await client.download(release, to: directory)
        installerURL = dmg
        guard Bundle.main.bundleURL.pathExtension == "app",
              !Bundle.main.bundleURL.path.hasPrefix("/Volumes/"),
              FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path),
              FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.path) else {
            status = "Downloaded. Move Mirror to a writable Applications folder to enable automatic installation."
            return
        }
        status = "Preparing installation…"
        let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        // Disk mounting, copying and signature checks must not block the editor.
        let paths = try await Task.detached(priority: .utility) {
            try MacUpdateInstaller.stage(dmg: dmg, directory: directory, destination: destination, version: version)
        }.value
        marker = paths.armed; restartMarker = paths.restart
        // The user may disable automatic updates while a download is running.
        if automaticallyUpdates { try Data().write(to: paths.armed) }
        readyToInstall = true
        status = automaticallyUpdates ? "Update ready. It will install after you quit Mirror." : "Update ready. Choose Restart to Update to install now."
    }

    func restart(document: DocumentStore) {
        guard readyToInstall, let marker, let restartMarker else { return }
        do {
            guard document.persistForApplicationTermination() else {
                throw SoftwareUpdateError.message("Could not preserve drafts. Update restart was cancelled.")
            }
            try Data().write(to: marker); try Data().write(to: restartMarker)
            NSApp.terminate(nil)
        } catch { self.error = error.localizedDescription }
    }
}
