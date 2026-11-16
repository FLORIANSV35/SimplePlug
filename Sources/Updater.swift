import AppKit

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Updates through GitHub releases: checks the latest release, downloads the .zip,
/// verifies the app, replaces the old one, then relaunches. No external dependency.
@MainActor
final class Updater {
    static let repo = "FLORIANSV35/SimplePlug"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 3600

    struct Release: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: String }
    }

    var currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var busy = false

    #if arch(arm64)
    static let arch = "arm64"
    #else
    static let arch = "x86_64"
    #endif

    // MARK: Checking

    /// Automatic check at launch, at most once a day, silent when there's nothing new.
    func checkAtLaunch(status: @escaping (String) -> Void) async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > Self.checkInterval else { return }
        await check(interactive: false, status: status)
    }

    func check(interactive: Bool, status: @escaping (String) -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let release = try await fetchLatest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            guard Self.isNewer(release.tag_name, than: currentVersion) else {
                if interactive { alert("You're up to date", "SimplePlug \(currentVersion) is the latest version.") }
                return
            }
            await offer(release, status: status)
        } catch {
            if interactive { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SimplePlug-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("GitHub didn't respond correctly (no release published?).")
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Proposition

    private func offer(_ release: Release, status: @escaping (String) -> Void) async {
        let asset = release.assets.first { $0.name.hasSuffix("-macOS-\(Self.arch).zip") }
        let notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let a = NSAlert()
        a.messageText = "SimplePlug \(release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))) is available"
        a.informativeText = "You're using version \(currentVersion)."
            + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(600)))
        a.addButton(withTitle: asset == nil ? "Open page" : "Install and relaunch")
        a.addButton(withTitle: "Later")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        guard let asset, let url = URL(string: asset.browser_download_url) else {
            NSWorkspace.shared.open(URL(string: release.html_url)!)
            return
        }
        do {
            try await install(from: url, version: release.tag_name, status: status)
        } catch {
            status("")
            let e = NSAlert()
            e.messageText = "The update failed"
            e.informativeText = error.localizedDescription
            e.addButton(withTitle: "Open download page")
            e.addButton(withTitle: "Close")
            if e.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string: release.html_url)!) }
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    // MARK: Installation

    /// Downloads, verifies, then replaces `destination` with the new app and relaunches.
    func install(from zipURL: URL, version: String,
                 destination: URL = Bundle.main.bundleURL,
                 terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
                 status: @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        if destination.path.contains("/AppTranslocation/") {
            throw UpdateError("The app is running from a temporary folder protected by macOS. Move SimplePlug.app to Applications, relaunch it, then try again.")
        }
        guard fm.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw UpdateError("No permission to write to “\(destination.deletingLastPathComponent().path)”.")
        }

        let work = fm.temporaryDirectory.appendingPathComponent("SimplePlugUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        var handedOff = false
        defer { if !handedOff { try? fm.removeItem(at: work) } }

        status("Downloading the update…")
        let (tmp, response) = try await URLSession.shared.download(from: zipURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError("Download failed (HTTP \(http.statusCode)).")
        }
        let zip = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: tmp, to: zip)

        status("Verifying the update…")
        let extracted = work.appendingPathComponent("extracted")
        guard await run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path]) == 0 else {
            throw UpdateError("Unreadable archive.")
        }
        let newApp = extracted.appendingPathComponent(destination.lastPathComponent)
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == (Bundle(url: destination)?.bundleIdentifier ?? bundle.bundleIdentifier),
              let newVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              Self.isNewer(newVersion, than: currentVersion) else {
            throw UpdateError("The archive doesn't contain a newer version of SimplePlug.")
        }
        guard await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0 else {
            throw UpdateError("The new version's signature is invalid.")
        }

        // The replacement happens after the app quits, via a small detached script.
        let script = work.appendingPathComponent("replace.sh")
        try """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        BACKUP="$DEST.old-$$"
        if mv "$DEST" "$BACKUP"; then
            if ditto "$NEW" "$DEST"; then
                xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
                rm -rf "$BACKUP"
            else
                rm -rf "$DEST"; mv "$BACKUP" "$DEST"
            fi
        fi
        open "$DEST"
        rm -rf "$WORK"
        """.write(to: script, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination.path, work.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        handedOff = true

        status("Installing version \(newVersion)… the app will relaunch.")
        terminate()
    }

    private func run(_ path: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { continuation.resume(returning: -1) }
        }
    }
}
