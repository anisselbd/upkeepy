import Foundation

/// Mode démo : un état forgé, pour présenter l'app sans dépendre de la machine.
///
/// Une machine bien tenue n'a rien à montrer, et surtout pas de cask fantôme,
/// alors que c'est la fonction la plus caractéristique d'UpKeepy. Ce mode fournit
/// un état représentatif et reproductible pour les captures et les démonstrations.
///
/// Garantie centrale : **aucune commande n'est exécutée ici**. Ce fichier
/// n'appelle jamais `Shell`, ce qui rend le mode démo sûr sur une machine
/// inconnue, celle d'une salle de conférence par exemple.
@MainActor
enum DemoMode {

    // MARK: - État consommé

    /// Éléments déjà traités pendant la session de démonstration, pour qu'une
    /// mise à jour simulée disparaisse de la liste comme une vraie le ferait.
    private static var consumedPackages: Set<String> = []
    private static var consumedGhosts: Set<String> = []
    private static var systemConsumed = false

    /// Remet la démonstration à son état initial. Appelé à chaque activation,
    /// pour qu'une seconde démonstration reparte d'une liste pleine.
    static func reset() {
        consumedPackages = []
        consumedGhosts = []
        systemConsumed = false
    }

    // MARK: - Jeu de données

    /// Versions choisies pour rester plausibles sans imiter un instant précis.
    private static let catalog: [(String, PackageManager, String, String)] = [
        ("ffmpeg",              .homebrew,     "7.1",      "7.1.1"),
        ("ripgrep",             .homebrew,     "14.1.0",   "14.1.1"),
        ("node",                .homebrew,     "22.11.0",  "23.3.0"),
        ("visual-studio-code",  .homebrewCask, "1.95.3",   "1.96.0"),
        ("rectangle",           .homebrewCask, "0.84",     "0.85"),
        ("typescript",          .npm,          "5.6.3",    "5.7.2"),
        ("node-sass",           .npm,          "9.0.0",    "9.1.0"),
        ("rubocop",             .gem,          "1.68.0",   "1.69.1"),
    ]

    static var packages: [UpdatePackage] {
        catalog
            .filter { !consumedPackages.contains($0.0) }
            .map { UpdatePackage(name: $0.0, manager: $0.1,
                                 currentVersion: $0.2, newVersion: $0.3) }
    }

    /// Deux casks fantômes : le cas typique d'apps glissées à la corbeille.
    static var ghosts: [GhostCask] {
        [
            GhostCask(token: "bruno", version: "1.34.2", appName: "Bruno.app"),
            GhostCask(token: "postman", version: "11.20.0", appName: "Postman.app"),
        ].filter { !consumedGhosts.contains($0.token) }
    }

    static var systemUpdates: [String] {
        systemConsumed ? [] : ["macOS Sequoia 15.2"]
    }

    // MARK: - Opérations simulées

    /// Rejoue une sortie ligne par ligne, comme le ferait un vrai processus.
    private static func stream(_ lines: [String],
                               onOutput: ((String) -> Void)?,
                               perLine: Duration = .milliseconds(220)) async -> String {
        var full = ""
        for line in lines {
            try? await Task.sleep(for: perLine)
            full += line + "\n"
            onOutput?(line + "\n")
        }
        return full
    }

    static func update(_ package: UpdatePackage,
                       onOutput: ((String) -> Void)? = nil) async -> ShellResult {
        // node-sass échoue volontairement : c'est la démonstration du faux succès
        // npm, où la commande sort en 0 alors que le module natif n'a pas compilé.
        if package.manager == .npm && package.name == "node-sass" {
            return await failingNpmUpdate(package, onOutput: onOutput)
        }

        let output: String
        switch package.manager {
        case .homebrew:
            output = await stream([
                "==> Fetching \(package.name)",
                "==> Downloading https://ghcr.io/v2/homebrew/core/\(package.name)/blobs/sha256:9f3c1a",
                "==> Upgrading \(package.name)",
                "  \(package.currentVersion) -> \(package.newVersion)",
                "==> Pouring \(package.name)--\(package.newVersion).arm64_sequoia.bottle.tar.gz",
                "🍺  /opt/homebrew/Cellar/\(package.name)/\(package.newVersion): 287 files, 52.4MB",
            ], onOutput: onOutput)

        case .homebrewCask:
            output = await stream([
                "==> Downloading https://update.example.com/\(package.name)/\(package.newVersion)",
                "==> Verifying checksum for cask '\(package.name)'",
                "==> Backing up App '\(package.name).app'",
                "==> Moving App '\(package.name).app' to '/Applications'",
                "🍺  \(package.name) was successfully upgraded!",
            ], onOutput: onOutput)

        case .npm:
            output = await stream([
                "npm install -g \(package.name)@\(package.newVersion)",
                "added 1 package in 3s",
                "changed 1 package, and audited 74 packages in 3s",
                "found 0 vulnerabilities",
            ], onOutput: onOutput)

        case .gem:
            output = await stream([
                "Updating installed gems",
                "Fetching \(package.name)-\(package.newVersion).gem",
                "Successfully installed \(package.name)-\(package.newVersion)",
                "Parsing documentation for \(package.name)-\(package.newVersion)",
                "Done installing documentation for \(package.name)",
            ], onOutput: onOutput)

        case .system:
            return ShellResult(stdout: "macOS updates are handled in System Settings.",
                               stderr: "", exitCode: 0)
        }

        consumedPackages.insert(package.name)
        return ShellResult(stdout: output, stderr: "", exitCode: 0)
    }

    /// Le faux succès npm, démasqué.
    ///
    /// Reproduit la mise en forme de `MaintenanceEngine.decorateNpmResult` :
    /// version visée, version réellement installée, cause probable et commande
    /// à lancer. Le paquet n'est pas consommé, puisque la mise à jour a échoué.
    private static func failingNpmUpdate(_ package: UpdatePackage,
                                         onOutput: ((String) -> Void)?) async -> ShellResult {
        let log = await stream([
            "npm install -g \(package.name)@\(package.newVersion)",
            "npm warn deprecated \(package.name)@\(package.newVersion): please migrate to sass",
            "> \(package.name)@\(package.newVersion) install",
            "> node scripts/build.js",
            "gyp ERR! configure error",
            "gyp ERR! stack ModuleNotFoundError: No module named 'distutils'",
            "gyp ERR! System Darwin 24.1.0",
            "gyp ERR! not ok",
            "added 1 package in 4s",
        ], onOutput: onOutput)

        var header = ""
        header += "Package: \(package.name)\n"
        header += "Target version    : \(package.newVersion)\n"
        header += "Installed version : \(package.currentVersion)   ⚠️ mismatch\n"
        header += """

        Cause: node-gyp can't find the Python `distutils` module
        (removed in Python 3.12). Fix:
          npm install -g node-gyp@latest
          # then retry the update here

        """
        header += "\n== npm log ==============================\n"

        return ShellResult(stdout: header + "\n" + log, stderr: "", exitCode: 1)
    }

    static func uninstall(_ package: UpdatePackage,
                          onOutput: ((String) -> Void)? = nil) async -> ShellResult {
        let output = await stream([
            "==> Uninstalling \(package.name)",
            "==> Removing files for \(package.name) \(package.currentVersion)",
            "Uninstalling /opt/homebrew/Cellar/\(package.name)/\(package.currentVersion)... (287 files, 52.4MB)",
        ], onOutput: onOutput)
        consumedPackages.insert(package.name)
        return ShellResult(stdout: output, stderr: "", exitCode: 0)
    }

    static func reinstallGhost(_ ghost: GhostCask) async -> ShellResult {
        let output = await stream([
            "==> Downloading \(ghost.token) \(ghost.version)",
            "==> Installing Cask \(ghost.token)",
            "==> Moving App '\(ghost.appName)' to '/Applications/\(ghost.appName)'",
            "🍺  \(ghost.token) was successfully installed!",
        ], onOutput: nil)
        consumedGhosts.insert(ghost.token)
        return ShellResult(stdout: output, stderr: "", exitCode: 0)
    }

    static func removeGhost(_ ghost: GhostCask) async -> ShellResult {
        let output = await stream([
            "==> Removing the stale reference to \(ghost.token)",
            "==> Purging files for version \(ghost.version) of Cask \(ghost.token)",
        ], onOutput: nil)
        consumedGhosts.insert(ghost.token)
        return ShellResult(stdout: output, stderr: "", exitCode: 0)
    }

    static func cleanup() async -> ShellResult {
        let output = await stream([
            "==> Removing outdated downloads",
            "Freed 412.7MB",
        ], onOutput: nil, perLine: .milliseconds(160))
        return ShellResult(stdout: output, stderr: "", exitCode: 0)
    }

    /// Marque la mise à jour système comme traitée, sans ouvrir les Réglages.
    static func consumeSystemUpdate() {
        systemConsumed = true
    }
}
