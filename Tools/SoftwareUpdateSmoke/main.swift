import AppKit
import Foundation
import CryptoKit

final class ReleaseProtocol: URLProtocol {
    static var payload = Data()
    static var responseCode = 200
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func release(_ version: String, draft: Bool = false, prerelease: Bool = false, mac: Bool = true) -> [String: Any] {
    let name = "Mirror-\(version.dropFirst()).dmg"
    return ["tag_name": version, "draft": draft, "prerelease": prerelease,
            "assets": mac ? [["name": name, "state": "uploaded", "size": 12, "browser_download_url": "https://github.com/BoneInk/Mirror/releases/download/\(version)/\(name)"]] : []]
}
func rejects(_ operation: () throws -> Void) {
    do { try operation(); preconditionFailure("Expected rejection") } catch {}
}

Task { @MainActor in
    do {
        precondition(ReleaseVersion("v1.3.10")! > ReleaseVersion("1.3.9")!)
        precondition(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.99")!)
        precondition(ReleaseVersion("1.3.5")! == ReleaseVersion("v1.3.5.0")!)
        precondition(ReleaseVersion("v1.3.5-rc.1") == nil)
        precondition(ReleaseVersion("v1.3") == nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        let client = GitHubUpdateClient(session: URLSession(configuration: configuration))
        ReleaseProtocol.payload = try JSONSerialization.data(withJSONObject: [release("v1.3.9"), release("v1.10.0"), release("v2.0.0", draft: true), release("v3.0.0", prerelease: true), release("v4.0.0", mac: false)])
        let selected = try await client.latestMacRelease()
        precondition(selected?.tag_name == "v1.10.0")
        let defaults = UserDefaults(suiteName: "MirrorUpdateSmoke-\(UUID().uuidString)")!
        let updates = SoftwareUpdateStore(defaults: defaults, client: client, version: "1.10.0")
        await updates.check(automatic: true)
        let count = ReleaseProtocol.requests
        await updates.check(automatic: true)
        precondition(ReleaseProtocol.requests == count)
        await updates.check()
        precondition(ReleaseProtocol.requests == count + 1)
        updates.automaticallyUpdates = false
        defaults.removeObject(forKey: "MirrorUpdateLastChecked")
        let optedOut = SoftwareUpdateStore(defaults: defaults, client: client, version: "1.3.4")
        let before = ReleaseProtocol.requests
        await optedOut.check(automatic: true)
        precondition(ReleaseProtocol.requests == before)
        await optedOut.check()
        precondition(optedOut.availableVersion == "v1.10.0" && !optedOut.readyToInstall)
        ReleaseProtocol.responseCode = 403
        await optedOut.check()
        precondition(optedOut.error != nil && !optedOut.busy)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MirrorUpdateSmoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.dmg")
        let data = Data("verified installer bytes".utf8)
        try data.write(to: file)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try GitHubUpdateClient.verify(file: file, size: Int64(data.count), checksum: digest)
        rejects { try GitHubUpdateClient.verify(file: file, size: Int64(data.count) + 1, checksum: digest) }
        rejects { try GitHubUpdateClient.verify(file: file, size: Int64(data.count), checksum: String(repeating: "0", count: 64)) }
        precondition(GitHubUpdateClient.checksum(in: "\(digest)  Mirror-1.3.5.dmg", filename: "Mirror-1.3.5.dmg") == digest)
        precondition(!GitHubUpdateClient.trustedAssetURL(URL(string: "https://github.com.evil/BoneInk/Mirror/releases/download/v1/a.dmg")!))
        precondition(!GitHubUpdateClient.trustedAssetURL(URL(string: "https://github.com/Other/Mirror/releases/download/v1/a.dmg")!))
        try MacUpdateInstaller.helperScript.write(to: root.appendingPathComponent("install.sh"), atomically: true, encoding: .utf8)
        print("Update smoke passed: version ordering, platform filtering, daily checks, opt-out, manual retry, errors, SHA-256, download origin")
        if let helperOutput = ProcessInfo.processInfo.environment["MIRROR_UPDATE_HELPER_OUTPUT"] {
            try MacUpdateInstaller.helperScript.write(toFile: helperOutput, atomically: true, encoding: .utf8)
        }
        exit(0)
    } catch { fputs("Update smoke failed: \(error)\n", stderr); exit(1) }
}
NSApplication.shared.run()
