import SwiftUI

/// État observable partagé par toute l'interface.
@MainActor
final class AppState: ObservableObject {
    @Published var status: OverallStatus = .idle
    @Published var packages: [UpdatePackage] = []
    @Published var ghosts: [GhostCask] = []
    @Published var systemUpdates: [String] = []
    @Published var lastCheck: Date?
    @Published var log: String = ""
    @Published var busyMessage: String?
    @Published var liveOutput: String = ""          // dernière ligne de sortie en direct
    @Published var progress: ProgressInfo?          // barre déterminée pour « Tout »
    @Published var lastResult: OperationResult?      // récap de fin d'opération

    struct ProgressInfo { let done: Int; let total: Int }

    /// Dernière ligne non vide d'un morceau de sortie.
    private static func lastLine(_ chunk: String) -> String? {
        chunk.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
    }

    /// Intervalle (en minutes) entre deux vérifications automatiques.
    /// `0` désactive la vérif périodique. Persisté dans `UserDefaults`.
    @Published var checkIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(checkIntervalMinutes, forKey: Self.intervalKey)
            startScheduler()
        }
    }

    /// Mode démo : état forgé, aucune commande réelle exécutée.
    /// Sert à présenter l'app quand la machine n'a rien à montrer.
    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: Self.demoKey)
            DemoMode.reset()
            lastResult = nil
            Task { await checkAll() }
        }
    }

    private static let intervalKey = "checkIntervalMinutes"
    private static let demoKey = "demoMode"
    private var schedulerTask: Task<Void, Never>?

    init() {
        // Valeur par défaut : vérif toutes les 6 heures.
        UserDefaults.standard.register(defaults: [Self.intervalKey: 360])
        self.checkIntervalMinutes = UserDefaults.standard.integer(forKey: Self.intervalKey)
        // Absent des defaults enregistrés : false tant que rien n'a été choisi.
        self.demoMode = UserDefaults.standard.bool(forKey: Self.demoKey)

        Task { @MainActor in
            await Notifications.requestPermissionIfNeeded()
            await checkAll()
            startScheduler()
        }
    }

    /// Relance la boucle de vérification périodique selon l'intervalle courant.
    func startScheduler() {
        schedulerTask?.cancel()
        guard checkIntervalMinutes > 0 else { return }
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = await MainActor.run { self?.checkIntervalMinutes ?? 0 }
                guard minutes > 0 else { return }
                try? await Task.sleep(for: .seconds(minutes * 60))
                if Task.isCancelled { return }
                await self?.scheduledCheck()
            }
        }
    }

    /// Check automatique : silencieux mais envoie une notif si de NOUVELLES
    /// mises à jour apparaissent (pas à chaque tour quand rien ne change).
    private func scheduledCheck() async {
        guard !isBusy else { return }
        let before = totalUpdates
        await checkAll()
        let delta = totalUpdates - before
        if delta > 0 {
            let s = delta > 1 ? "s" : ""
            Notifications.send(
                title: "UpKeepy",
                body: "\(delta) new update\(s) available")
        }
    }

    var totalUpdates: Int { packages.count + systemUpdates.count }

    var isBusy: Bool { busyMessage != nil }

    func packages(for manager: PackageManager) -> [UpdatePackage] {
        packages.filter { $0.manager == manager }
    }

    /// Liste ordonnée des gestionnaires ayant au moins une MAJ.
    var managersWithUpdates: [PackageManager] {
        PackageManager.allCases.filter { !packages(for: $0).isEmpty }
    }

    // MARK: - Actions

    func checkAll() async {
        guard !isBusy else { return }
        status = .checking
        busyMessage = "Checking…"
        defer { busyMessage = nil }

        if demoMode {
            // Bref délai : sans lui, l'état « Checking » n'est jamais visible,
            // ce qui rend la démonstration moins fidèle qu'un vrai passage.
            try? await Task.sleep(for: .milliseconds(450))
            packages = DemoMode.packages
            ghosts = DemoMode.ghosts
            systemUpdates = DemoMode.systemUpdates
        } else {
            async let brew = MaintenanceEngine.checkHomebrew()
            async let npm = MaintenanceEngine.checkNpm()
            async let gem = MaintenanceEngine.checkGems()
            async let sys = MaintenanceEngine.checkSystem()
            let (brewRes, npmRes, gemRes, sysRes) = await (brew, npm, gem, sys)

            packages = brewRes.packages + npmRes + gemRes
            ghosts = brewRes.ghosts
            systemUpdates = sysRes
        }
        lastCheck = Date()
        status = totalUpdates == 0 ? .upToDate : .updatesAvailable(totalUpdates)
    }

    /// Capte la sortie en direct vers `liveOutput` (marshalé sur le main thread).
    private func liveSink() -> (String) -> Void {
        { chunk in
            DispatchQueue.main.async { [weak self] in
                if let line = AppState.lastLine(chunk) { self?.liveOutput = line }
            }
        }
    }

    // MARK: - Routage réel / démo
    //
    // Toutes les opérations passent par ces quatre méthodes. Le reste de la
    // classe ignore le mode démo, et le récapitulatif de fin est identique
    // dans les deux cas puisqu'il part du même ShellResult.

    private func runUpdate(_ package: UpdatePackage) async -> ShellResult {
        demoMode
            ? await DemoMode.update(package, onOutput: liveSink())
            : await MaintenanceEngine.update(package, onOutput: liveSink())
    }

    private func runUninstall(_ package: UpdatePackage) async -> ShellResult {
        demoMode
            ? await DemoMode.uninstall(package, onOutput: liveSink())
            : await MaintenanceEngine.uninstall(package, onOutput: liveSink())
    }

    private func runReinstallGhost(_ ghost: GhostCask) async -> ShellResult {
        demoMode ? await DemoMode.reinstallGhost(ghost)
                 : await MaintenanceEngine.reinstallGhost(ghost)
    }

    private func runRemoveGhost(_ ghost: GhostCask) async -> ShellResult {
        demoMode ? await DemoMode.removeGhost(ghost)
                 : await MaintenanceEngine.removeGhost(ghost)
    }

    private func runCleanup() async -> ShellResult {
        demoMode ? await DemoMode.cleanup() : await MaintenanceEngine.cleanup()
    }

    func updateAll() async {
        guard !isBusy else { return }
        let targets = packages   // instantané de la liste à traiter
        guard !targets.isEmpty else { return }

        lastResult = nil
        status = .updating
        liveOutput = ""
        let total = targets.count
        let start = Date()
        var failures: [String] = []
        // Les journaux des échecs sont conservés : sans eux, le récapitulatif
        // se réduit aux noms des paquets, et le diagnostic (version visée
        // contre version installée, cause probable, commande à lancer) serait
        // perdu précisément sur le chemin le plus emprunté.
        var failureLogs: [String] = []

        for (index, package) in targets.enumerated() {
            progress = ProgressInfo(done: index, total: total)
            busyMessage = "Updating \(package.name)…"
            liveOutput = ""
            let result = await runUpdate(package)
            if !result.ok {
                failures.append(package.name)
                let log = result.combined.isEmpty ? "Unknown error" : result.combined
                failureLogs.append("── \(package.name) " + String(repeating: "─", count: max(1, 30 - package.name.count)) + "\n" + log)
            }
        }

        progress = ProgressInfo(done: total, total: total)
        busyMessage = "Cleaning up…"
        liveOutput = ""
        _ = await runCleanup()

        progress = nil
        busyMessage = nil
        liveOutput = ""
        let done = total - failures.count
        lastResult = OperationResult(
            success: failures.isEmpty,
            title: failures.isEmpty ? "\(total) package\(total > 1 ? "s" : "") updated"
                                    : "\(done)/\(total) updated",
            detail: failures.isEmpty
                ? "Everything is up to date ✨"
                : "Failed: \(failures.joined(separator: ", "))\n\n"
                  + failureLogs.joined(separator: "\n\n"),
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func update(_ package: UpdatePackage) async {
        guard !isBusy else { return }
        lastResult = nil
        status = .updating
        progress = nil            // un seul paquet : barre indéterminée
        liveOutput = ""
        busyMessage = "Updating \(package.name)…"
        let start = Date()
        let result = await runUpdate(package)
        busyMessage = nil
        liveOutput = ""
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(package.name) updated" : "Failed: \(package.name)",
            detail: result.combined.isEmpty
                ? (result.ok ? "Done." : "Unknown error")
                : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func uninstall(_ package: UpdatePackage) async {
        guard !isBusy else { return }
        lastResult = nil
        status = .updating
        progress = nil
        liveOutput = ""
        busyMessage = "Uninstalling \(package.name)…"
        let start = Date()
        let result = await runUninstall(package)
        busyMessage = nil
        liveOutput = ""
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(package.name) uninstalled" : "Failed: \(package.name)",
            detail: result.combined.isEmpty
                ? (result.ok ? "Package removed." : "Unknown error")
                : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func reinstall(_ ghost: GhostCask) async {
        guard !isBusy else { return }
        lastResult = nil
        liveOutput = ""
        busyMessage = "Reinstalling \(ghost.token)…"
        let start = Date()
        let result = await runReinstallGhost(ghost)
        busyMessage = nil
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(ghost.token) reinstalled" : "Failed: \(ghost.token)",
            detail: result.combined.isEmpty ? "Done." : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func remove(_ ghost: GhostCask) async {
        guard !isBusy else { return }
        lastResult = nil
        busyMessage = "Removing \(ghost.token)…"
        let start = Date()
        let result = await runRemoveGhost(ghost)
        busyMessage = nil
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(ghost.token) removed" : "Failed: \(ghost.token)",
            detail: result.combined.isEmpty ? "Done." : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }
}
