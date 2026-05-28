import Foundation
import AppKit

/// Cœur métier : interroge chaque gestionnaire de paquets, détecte les casks
/// fantômes et applique les mises à jour. Tout est `nonisolated` afin de
/// pouvoir être appelé en parallèle depuis l'`AppState` (MainActor).
enum MaintenanceEngine {

    /// Chemin absolu de `brew` selon l'architecture.
    static let brewPath: String = {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "brew"
    }()

    static var isHomebrewInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: brewPath)
    }

    // MARK: - Vérifications

    /// Met à jour l'index Homebrew puis liste les paquets périmés (formules + apps).
    /// Renvoie aussi les casks fantômes, en les retirant de la liste des MAJ
    /// (ils ne peuvent pas être mis à jour normalement).
    static func checkHomebrew() async -> (packages: [UpdatePackage], ghosts: [GhostCask]) {
        guard isHomebrewInstalled else { return ([], []) }

        _ = await Shell.run("\(brewPath) update")

        async let formulaTask = Shell.run("\(brewPath) outdated --formula --verbose")
        async let caskTask = Shell.run("\(brewPath) outdated --cask --verbose --greedy")
        let (formula, cask) = await (formulaTask, caskTask)

        var packages = parseBrewOutdated(formula.stdout, manager: .homebrew)
        packages += parseBrewOutdated(cask.stdout, manager: .homebrewCask)

        let ghosts = await detectGhostCasks()
        let ghostTokens = Set(ghosts.map(\.token))
        packages.removeAll { $0.manager == .homebrewCask && ghostTokens.contains($0.name) }

        return (packages, ghosts)
    }

    /// Détecte les casks dont l'application n'existe plus sur le disque.
    static func detectGhostCasks() async -> [GhostCask] {
        guard isHomebrewInstalled else { return [] }

        let list = await Shell.run("\(brewPath) list --cask")
        guard list.ok else { return [] }
        let casks = list.stdout
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !casks.isEmpty else { return [] }

        let info = await Shell.run("\(brewPath) info --cask --json=v2 \(casks.joined(separator: " "))")
        guard info.ok, let data = info.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let caskArray = root["casks"] as? [[String: Any]] else { return [] }

        let fm = FileManager.default
        let home = NSHomeDirectory()
        var ghosts: [GhostCask] = []

        for cask in caskArray {
            guard let token = cask["token"] as? String else { continue }
            let version = (cask["installed"] as? String)
                ?? (cask["version"] as? String) ?? "?"

            // Récupère les noms d'apps déclarés dans les artefacts du cask.
            var appNames: [String] = []
            if let artifacts = cask["artifacts"] as? [Any] {
                for artifact in artifacts {
                    if let dict = artifact as? [String: Any],
                       let apps = dict["app"] as? [Any] {
                        for app in apps where app is String {
                            appNames.append(app as! String)
                        }
                    }
                }
            }
            // Pas une app (ex. font, pilote…) : hors périmètre de détection.
            guard !appNames.isEmpty else { continue }

            let anyExists = appNames.contains { name in
                fm.fileExists(atPath: "/Applications/\(name)")
                    || fm.fileExists(atPath: "\(home)/Applications/\(name)")
            }
            if !anyExists {
                ghosts.append(GhostCask(token: token, version: version, appName: appNames.first ?? token))
            }
        }
        return ghosts
    }

    /// Paquets npm globaux périmés (`npm outdated -g --json`).
    static func checkNpm() async -> [UpdatePackage] {
        guard let npm = Shell.which("npm") else { return [] }
        let result = await Shell.run("\(npm) outdated -g --json")
        guard let data = result.stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var packages: [UpdatePackage] = []
        for (name, value) in obj {
            guard let info = value as? [String: Any] else { continue }
            let current = info["current"] as? String ?? "?"
            let latest = info["latest"] as? String ?? "?"
            guard current != latest else { continue }
            packages.append(UpdatePackage(name: name, manager: .npm,
                                          currentVersion: current, newVersion: latest))
        }
        return packages.sorted { $0.name < $1.name }
    }

    /// Gems périmés (`gem outdated`).
    ///
    /// On ignore complètement le **Ruby système Apple** (`/usr/bin/gem`) : ses
    /// gems sont livrés avec macOS, les mettre à jour nécessite `sudo` et
    /// peut casser des composants système (CFPropertyList, bigdecimal, etc.).
    static func checkGems() async -> [UpdatePackage] {
        guard let gem = Shell.which("gem") else { return [] }
        if gem == "/usr/bin/gem" || gem.hasPrefix("/System/") { return [] }
        let result = await Shell.run("\(gem) outdated")
        var packages: [UpdatePackage] = []
        for raw in result.stdout.split(separator: "\n") {
            // Format : "name (1.0 < 2.0)"
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let open = line.firstIndex(of: "("),
                  let close = line.firstIndex(of: ")") else { continue }
            let name = line[line.startIndex..<open].trimmingCharacters(in: .whitespaces)
            let inside = String(line[line.index(after: open)..<close])
            let parts = inside.components(separatedBy: "<")
            guard parts.count == 2 else { continue }
            packages.append(UpdatePackage(
                name: name, manager: .gem,
                currentVersion: parts[0].trimmingCharacters(in: .whitespaces),
                newVersion: parts[1].trimmingCharacters(in: .whitespaces)))
        }
        return packages
    }

    /// Mises à jour système macOS (`softwareupdate -l`). Lecture seule : on ne
    /// les applique pas ici (sudo requis) — on ouvre les Réglages Système.
    static func checkSystem() async -> [String] {
        let result = await Shell.run("softwareupdate -l 2>&1")
        var items: [String] = []
        for raw in result.stdout.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("* Label:") {
                items.append(line
                    .replacingOccurrences(of: "* Label:", with: "")
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        return items
    }

    // MARK: - Actions

    /// Met à jour un seul paquet, selon son gestionnaire.
    /// `onOutput` reçoit la sortie en direct (pour l'affichage de progression).
    static func update(_ package: UpdatePackage,
                       onOutput: ((String) -> Void)? = nil) async -> ShellResult {
        switch package.manager {
        case .homebrew:
            return await Shell.run("\(brewPath) upgrade '\(package.name)'", onOutput: onOutput)
        case .homebrewCask:
            return await Shell.run("\(brewPath) upgrade --cask '\(package.name)'", onOutput: onOutput)
        case .npm:
            guard let npm = Shell.which("npm") else {
                return ShellResult(stdout: "", stderr: "npm introuvable", exitCode: -1)
            }
            // On vise la version exacte plutôt que `@latest` : c'est
            // déterministe et permet une vérification a posteriori.
            let result = await Shell.run(
                "\(npm) install -g '\(package.name)@\(package.newVersion)'",
                onOutput: onOutput)
            return await decorateNpmResult(result, package: package, npm: npm)
        case .gem:
            guard let gem = Shell.which("gem") else {
                return ShellResult(stdout: "", stderr: "gem introuvable", exitCode: -1)
            }
            return await Shell.run("\(gem) update '\(package.name)'", onOutput: onOutput)
        case .system:
            // macOS : pas d'install ciblée ici (sudo) — on passe par les Réglages.
            return ShellResult(stdout: "Mise à jour macOS via les Réglages Système.",
                               stderr: "", exitCode: 0)
        }
    }

    /// Désinstalle complètement un paquet (action destructive — l'UI doit
    /// demander confirmation avant d'appeler cette méthode).
    static func uninstall(_ package: UpdatePackage,
                          onOutput: ((String) -> Void)? = nil) async -> ShellResult {
        switch package.manager {
        case .homebrew:
            return await Shell.run("\(brewPath) uninstall '\(package.name)'",
                                   onOutput: onOutput)
        case .homebrewCask:
            return await Shell.run("\(brewPath) uninstall --cask '\(package.name)'",
                                   onOutput: onOutput)
        case .npm:
            guard let npm = Shell.which("npm") else {
                return ShellResult(stdout: "", stderr: "npm introuvable", exitCode: -1)
            }
            return await Shell.run("\(npm) uninstall -g '\(package.name)'",
                                   onOutput: onOutput)
        case .gem:
            guard let gem = Shell.which("gem") else {
                return ShellResult(stdout: "", stderr: "gem introuvable", exitCode: -1)
            }
            // `--force` car gem demande sinon confirmation interactive.
            return await Shell.run("\(gem) uninstall '\(package.name)' --force",
                                   onOutput: onOutput)
        case .system:
            return ShellResult(stdout: "",
                               stderr: "Non applicable aux mises à jour macOS.",
                               exitCode: -1)
        }
    }

    /// Nettoie les anciennes versions Homebrew (lancé en fin de « Tout mettre à jour »).
    static func cleanup() async -> ShellResult {
        guard isHomebrewInstalled else { return ShellResult(stdout: "", stderr: "", exitCode: 0) }
        return await Shell.run("\(brewPath) cleanup")
    }

    /// Réinstalle proprement un cask fantôme (récupère l'app manquante).
    static func reinstallGhost(_ ghost: GhostCask) async -> ShellResult {
        await Shell.run("\(brewPath) reinstall --cask \(ghost.token)")
    }

    /// Supprime la référence fantôme côté Homebrew.
    static func removeGhost(_ ghost: GhostCask) async -> ShellResult {
        await Shell.run("\(brewPath) uninstall --cask --force \(ghost.token)")
    }

    /// Ouvre le volet « Mise à jour de logiciels » des Réglages Système.
    @MainActor
    static func openSoftwareUpdateSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    /// Enrichit un résultat d'install npm avec :
    ///   • la version réellement installée vs la version visée,
    ///   • un conseil actionnable pour les erreurs connues (node-gyp/distutils).
    /// Le diagnostic est placé en TÊTE du log pour être visible sans scroller.
    private static func decorateNpmResult(_ result: ShellResult,
                                          package: UpdatePackage,
                                          npm: String) async -> ShellResult {
        let actual = await currentNpmVersion(package.name, npm: npm) ?? "absent"
        let versionMismatch = actual != package.newVersion
        let combinedLog = result.combined

        // Détection de patterns d'erreur connus → conseil concret.
        var hint: String?
        if combinedLog.contains("No module named 'distutils'") {
            hint = """
            Cause : node-gyp ne trouve pas le module Python `distutils`
            (supprimé en Python 3.12). Solution :
              npm install -g node-gyp@latest
              # puis réessaie la mise à jour ici
            """
        } else if combinedLog.contains("EACCES") {
            hint = "Cause : permission refusée. Vérifie que tu n'as pas besoin de `sudo`."
        }

        // Si tout va bien (exit 0 + version cible atteinte + pas de hint) → on
        // ne touche pas au résultat : succès propre.
        if result.ok && !versionMismatch && hint == nil { return result }

        var header = ""
        header += "Paquet : \(package.name)\n"
        header += "Version visée    : \(package.newVersion)\n"
        header += "Version installée : \(actual)"
        if versionMismatch { header += "   ⚠️ écart" }
        header += "\n"
        if let hint { header += "\n" + hint + "\n" }
        header += "\n── Log npm ──────────────────────────────\n"

        return ShellResult(
            stdout: header + "\n" + result.stdout,
            stderr: result.stderr,
            // Si la version installée correspond à la cible, on respecte le code
            // de sortie d'origine. Sinon on force un échec.
            exitCode: versionMismatch ? max(result.exitCode, 1) : result.exitCode
        )
    }

    /// Lit la version réellement installée d'un paquet npm global.
    /// Renvoie `nil` si npm ne parvient pas à parser l'état (paquet absent ou cassé).
    private static func currentNpmVersion(_ name: String, npm: String) async -> String? {
        let result = await Shell.run("\(npm) list -g '\(name)' --depth=0 --json")
        guard let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deps = root["dependencies"] as? [String: Any],
              let info = deps[name] as? [String: Any],
              let version = info["version"] as? String,
              !version.isEmpty else { return nil }
        return version
    }

    // MARK: - Parsing

    /// Analyse la sortie de `brew outdated --verbose`.
    /// Formats : "deno (2.8.0) < 2.8.1" ou "bruno (2.13.2) != 3.4.2".
    private static func parseBrewOutdated(_ output: String, manager: PackageManager) -> [UpdatePackage] {
        var result: [UpdatePackage] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let open = line.firstIndex(of: "(") else { continue }
            let name = line[line.startIndex..<open].trimmingCharacters(in: .whitespaces)
            guard let close = line[open...].firstIndex(of: ")") else { continue }

            let current = String(line[line.index(after: open)..<close])
            // En cas de versions multiples ("1.0, 1.1"), on garde la dernière.
            let cleanCurrent = current.split(separator: ",").last
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? current

            let rest = line[line.index(after: close)...]
            let newVersion: String
            if let range = rest.range(of: "!= ") {
                newVersion = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let range = rest.range(of: "< ") {
                newVersion = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                newVersion = "—"
            }

            result.append(UpdatePackage(name: name, manager: manager,
                                        currentVersion: cleanCurrent, newVersion: newVersion))
        }
        return result
    }
}
