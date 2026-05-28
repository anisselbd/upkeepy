import Foundation

/// Résultat d'une commande shell.
struct ShellResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var ok: Bool { exitCode == 0 }

    /// Sortie combinée (utile pour les journaux affichés à l'utilisateur).
    var combined: String {
        var parts: [String] = []
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { parts.append(out) }
        if !err.isEmpty { parts.append(err) }
        return parts.joined(separator: "\n")
    }
}

/// Exécution de commandes shell pour une app GUI.
///
/// Une app lancée depuis le Finder **n'hérite pas** du `PATH` du shell de
/// l'utilisateur : on reconstruit donc un `PATH` enrichi avec les emplacements
/// usuels (Homebrew, npm global, etc.) pour retrouver `brew`, `npm`, `gem`…
enum Shell {
    static let enrichedPath: String = {
        let home = NSHomeDirectory()
        let extra = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (extra + [current]).joined(separator: ":")
    }()

    /// Cherche un exécutable dans le PATH enrichi. Renvoie son chemin absolu.
    static func which(_ binary: String) -> String? {
        for dir in enrichedPath.split(separator: ":") {
            let path = "\(dir)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Exécute une commande via `/bin/zsh -c` et renvoie son résultat.
    ///
    /// Si `onOutput` est fourni, il est appelé en continu (depuis un thread de
    /// fond) avec chaque morceau de sortie — utile pour afficher la progression
    /// en direct. La sortie complète reste accumulée pour le `ShellResult` final.
    static func run(_ command: String,
                    onOutput: ((String) -> Void)? = nil) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = enrichedPath
                env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
                env["HOMEBREW_NO_ENV_HINTS"] = "1"
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                let lock = NSLock()
                var outData = Data()
                var errData = Data()

                if let onOutput {
                    // Mode streaming : on lit au fil de l'eau via readabilityHandler.
                    let outHandle = outPipe.fileHandleForReading
                    let errHandle = errPipe.fileHandleForReading
                    outHandle.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        lock.lock(); outData.append(chunk); lock.unlock()
                        if let text = String(data: chunk, encoding: .utf8) { onOutput(text) }
                    }
                    errHandle.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        lock.lock(); errData.append(chunk); lock.unlock()
                        if let text = String(data: chunk, encoding: .utf8) { onOutput(text) }
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: ShellResult(
                            stdout: "", stderr: error.localizedDescription, exitCode: -1))
                        return
                    }
                    process.waitUntilExit()
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    // Vide les éventuelles données restantes.
                    let remOut = outHandle.readDataToEndOfFile()
                    let remErr = errHandle.readDataToEndOfFile()
                    lock.lock(); outData.append(remOut); errData.append(remErr); lock.unlock()
                } else {
                    // Mode simple : lecture concurrente pour éviter tout blocage.
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: ShellResult(
                            stdout: "", stderr: error.localizedDescription, exitCode: -1))
                        return
                    }
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        let d = outPipe.fileHandleForReading.readDataToEndOfFile()
                        lock.lock(); outData = d; lock.unlock(); group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        let d = errPipe.fileHandleForReading.readDataToEndOfFile()
                        lock.lock(); errData = d; lock.unlock(); group.leave()
                    }
                    process.waitUntilExit()
                    group.wait()
                }

                continuation.resume(returning: ShellResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                ))
            }
        }
    }
}
