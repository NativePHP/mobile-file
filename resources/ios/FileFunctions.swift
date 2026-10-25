import Foundation

// MARK: - File Function Namespace

/// Functions related to file operations
/// Namespace: "File.*"
enum FileFunctions {

    // MARK: - Path confinement
    //
    // File.Move/File.Copy are exported in the JS bridge, so a web view page can
    // call them through `/_native/api/call` with `from`/`to` of its choosing
    // (the `api` routes carry no middleware). Left open that is two primitives
    // against the app sandbox: copy a secret (`.env`, the SQLite database) into
    // `public/` and read it back over the app origin at `/_assets/…`, and
    // truncate or clobber any file the app relies on.
    //
    // So the paths are confined, not just the method gated. The plugin's own
    // documented destinations are broader than a bare `storage/app` — the
    // README/Boost examples move a captured file into `storage_path('recordings')`
    // and into the sandbox `Documents/…` tree — so both of those are allowed,
    // and the sensitive sinks inside them are denied:
    //
    //   allowed destination: the real `storage_path()` tree, or the sandbox
    //                        Documents directory;
    //   allowed source:      a scratch area (temp or caches) or either allowed
    //                        destination tree;
    //   denied everywhere:   the extracted Laravel app tree (`Documents/app` —
    //                        `public/`, `.env`, the DB, `bootstrap/cache` all
    //                        live here) and `storage/framework` + `storage/logs`.
    //
    // `public/` is the exfil read-back root and sits inside `Documents/app`, so
    // denying the whole extract closes the exfil chain and the clobber of app
    // internals in one prefix. The storage root is derived from where
    // `storage_path()` actually points — `LARAVEL_STORAGE_PATH` (Application
    // Support), set by the device shell — not the extracted app tree, which the
    // updater swaps on every update and which is not where `storage_path()`
    // resolves.
    //
    // Every path is canonicalised first (symlinks and `..` resolved) and only
    // then prefix-checked, so neither `..` nor a symlink can walk out of a root.

    /// A path with every symlink and `..`/`.` resolved. For a target that does
    /// not exist yet (a move/copy destination), the existing parent is resolved
    /// and the final component re-appended, so the check sees where the write
    /// would actually land.
    private static func canonical(_ path: String) -> String {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        if fileManager.fileExists(atPath: url.path) {
            return url.resolvingSymlinksInPath().standardizedFileURL.path
        }

        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        return parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL.path
    }

    /// True when `path` is `root` itself or sits beneath it. Both must already
    /// be canonical, so a prefix match is a real containment.
    private static func isInside(_ path: String, _ root: String) -> Bool {
        !root.isEmpty && (path == root || path.hasPrefix(root + "/"))
    }

    /// Where `storage_path()` actually resolves on device. The device shell
    /// points Laravel at Application Support via `LARAVEL_STORAGE_PATH`, which
    /// is persistent — the updater swaps the whole `Documents/app` extract on
    /// every update, so a root under it would be both wrong (a legitimate
    /// `storage_path()` destination would be rejected) and ephemeral. Read the
    /// same env the shell sets; fall back to Application Support/storage if it
    /// is somehow unset (no dependency on a core Swift symbol, so this compiles
    /// against both `nativephp/mobile` 3.x and 4.x).
    private static var storageRoot: String {
        if let raw = getenv("LARAVEL_STORAGE_PATH") {
            let storage = String(cString: raw)
            if !storage.isEmpty {
                return canonical(storage)
            }
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return canonical(appSupport.appendingPathComponent("storage").path)
        }

        return ""
    }

    /// The sandbox Documents directory — the app's user files area, which the
    /// plugin's docs point at for a captured photo.
    private static var documentsRoot: String {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return ""
        }
        return canonical(docs.path)
    }

    /// The extracted Laravel app tree (`Documents/app`). `public/`, `.env`, the
    /// SQLite database and `bootstrap/cache` all live here, so it is denied as
    /// both a source and a destination even though it sits inside Documents.
    private static var extractRoot: String {
        let docs = documentsRoot
        return docs.isEmpty ? "" : canonical(docs + "/app")
    }

    /// Roots that are never a valid source or destination, even when they fall
    /// inside an allowed tree: the app extract, and the framework/log areas of
    /// the storage tree.
    private static var deniedRoots: [String] {
        let storage = storageRoot
        var roots = [extractRoot]
        if !storage.isEmpty {
            roots.append(canonical(storage + "/framework"))
            roots.append(canonical(storage + "/logs"))
        }
        return roots.filter { !$0.isEmpty }
    }

    /// Trees a destination may land in: the real storage tree, or Documents.
    private static var destinationRoots: [String] {
        [storageRoot, documentsRoot].filter { !$0.isEmpty }
    }

    /// Trees a source may come from: a scratch area, plus the destination trees.
    private static var sourceRoots: [String] {
        var roots = [canonical(NSTemporaryDirectory())]
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots.append(canonical(caches.path))
        }
        roots.append(contentsOf: destinationRoots)
        return roots.filter { !$0.isEmpty }
    }

    /// Refuse a move/copy whose source or destination falls outside the allowed
    /// roots, or inside a denied one. Returns an error payload to hand straight
    /// back, or nil to proceed.
    private static func confinementError(from: String, to: String) -> [String: Any]? {
        let fromReal = canonical(from)
        let toReal = canonical(to)
        let denied = deniedRoots

        guard sourceRoots.contains(where: { isInside(fromReal, $0) }),
              !denied.contains(where: { isInside(fromReal, $0) }) else {
            print("File op refused: source outside the allowed roots")
            return ["success": false, "error": "Source path is not allowed"]
        }

        guard destinationRoots.contains(where: { isInside(toReal, $0) }),
              !denied.contains(where: { isInside(toReal, $0) }) else {
            print("File op refused: destination outside the allowed roots")
            return ["success": false, "error": "Destination path is not allowed"]
        }

        return nil
    }

    // MARK: - File.Move

    /// Move a file from one location to another
    class Move: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            guard let from = parameters["from"] as? String, !from.isEmpty else {
                return ["success": false, "error": "'from' parameter is required"]
            }

            guard let to = parameters["to"] as? String, !to.isEmpty else {
                return ["success": false, "error": "'to' parameter is required"]
            }

            if let refusal = FileFunctions.confinementError(from: from, to: to) {
                return refusal
            }

            print("Move requested - from: '\(from)', to: '\(to)'")

            let fileManager = FileManager.default
            let sourceURL = URL(fileURLWithPath: from)
            let destURL = URL(fileURLWithPath: to)

            do {
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    return ["success": false, "error": "Source file does not exist"]
                }

                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    return ["success": false, "error": "Source is not a file"]
                }

                let destParent = destURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: destParent.path) {
                    try fileManager.createDirectory(at: destParent, withIntermediateDirectories: true)
                }

                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }

                try fileManager.moveItem(at: sourceURL, to: destURL)

                print("File moved successfully")
                return ["success": true]

            } catch {
                print("Error moving file: \(error.localizedDescription)")
                return ["success": false, "error": error.localizedDescription]
            }
        }
    }

    // MARK: - File.Copy

    /// Copy a file from one location to another
    class Copy: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            guard let from = parameters["from"] as? String, !from.isEmpty else {
                return ["success": false, "error": "'from' parameter is required"]
            }

            guard let to = parameters["to"] as? String, !to.isEmpty else {
                return ["success": false, "error": "'to' parameter is required"]
            }

            if let refusal = FileFunctions.confinementError(from: from, to: to) {
                return refusal
            }

            print("Copy requested - from: '\(from)', to: '\(to)'")

            let fileManager = FileManager.default
            let sourceURL = URL(fileURLWithPath: from)
            let destURL = URL(fileURLWithPath: to)

            do {
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    return ["success": false, "error": "Source file does not exist"]
                }

                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    return ["success": false, "error": "Source is not a file"]
                }

                let destParent = destURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: destParent.path) {
                    try fileManager.createDirectory(at: destParent, withIntermediateDirectories: true)
                }

                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }

                try fileManager.copyItem(at: sourceURL, to: destURL)

                print("File copied successfully")
                return ["success": true]

            } catch {
                print("Error copying file: \(error.localizedDescription)")
                return ["success": false, "error": error.localizedDescription]
            }
        }
    }
}
