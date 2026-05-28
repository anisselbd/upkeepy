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

    init() {
        // Vérification au lancement pour refléter l'état dans la barre de menu.
        Task { await checkAll() }
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
        busyMessage = "Vérification…"
        defer { busyMessage = nil }

        async let brew = MaintenanceEngine.checkHomebrew()
        async let npm = MaintenanceEngine.checkNpm()
        async let gem = MaintenanceEngine.checkGems()
        async let sys = MaintenanceEngine.checkSystem()
        let (brewRes, npmRes, gemRes, sysRes) = await (brew, npm, gem, sys)

        packages = brewRes.packages + npmRes + gemRes
        ghosts = brewRes.ghosts
        systemUpdates = sysRes
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

        for (index, package) in targets.enumerated() {
            progress = ProgressInfo(done: index, total: total)
            busyMessage = "Mise à jour de \(package.name)…"
            liveOutput = ""
            let result = await MaintenanceEngine.update(package, onOutput: liveSink())
            if !result.ok { failures.append(package.name) }
        }

        progress = ProgressInfo(done: total, total: total)
        busyMessage = "Nettoyage…"
        liveOutput = ""
        _ = await MaintenanceEngine.cleanup()

        progress = nil
        busyMessage = nil
        liveOutput = ""
        let done = total - failures.count
        lastResult = OperationResult(
            success: failures.isEmpty,
            title: failures.isEmpty ? "\(total) paquet\(total > 1 ? "s" : "") à jour"
                                    : "\(done)/\(total) mis à jour",
            detail: failures.isEmpty ? "Tout est à jour ✨"
                                     : "Échec(s) : \(failures.joined(separator: ", "))",
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func update(_ package: UpdatePackage) async {
        guard !isBusy else { return }
        lastResult = nil
        status = .updating
        progress = nil            // un seul paquet : barre indéterminée
        liveOutput = ""
        busyMessage = "Mise à jour de \(package.name)…"
        let start = Date()
        let result = await MaintenanceEngine.update(package, onOutput: liveSink())
        busyMessage = nil
        liveOutput = ""
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(package.name) mis à jour" : "Échec : \(package.name)",
            detail: result.combined.isEmpty
                ? (result.ok ? "Terminé." : "Erreur inconnue")
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
        busyMessage = "Désinstallation de \(package.name)…"
        let start = Date()
        let result = await MaintenanceEngine.uninstall(package, onOutput: liveSink())
        busyMessage = nil
        liveOutput = ""
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(package.name) désinstallé" : "Échec : \(package.name)",
            detail: result.combined.isEmpty
                ? (result.ok ? "Paquet retiré." : "Erreur inconnue")
                : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func reinstall(_ ghost: GhostCask) async {
        guard !isBusy else { return }
        lastResult = nil
        liveOutput = ""
        busyMessage = "Réinstallation de \(ghost.token)…"
        let start = Date()
        let result = await MaintenanceEngine.reinstallGhost(ghost)
        busyMessage = nil
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(ghost.token) réinstallé" : "Échec : \(ghost.token)",
            detail: result.combined.isEmpty ? "Terminé." : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }

    func remove(_ ghost: GhostCask) async {
        guard !isBusy else { return }
        lastResult = nil
        busyMessage = "Suppression de \(ghost.token)…"
        let start = Date()
        let result = await MaintenanceEngine.removeGhost(ghost)
        busyMessage = nil
        lastResult = OperationResult(
            success: result.ok,
            title: result.ok ? "\(ghost.token) supprimé" : "Échec : \(ghost.token)",
            detail: result.combined.isEmpty ? "Terminé." : result.combined,
            duration: Date().timeIntervalSince(start))
        await checkAll()
    }
}
