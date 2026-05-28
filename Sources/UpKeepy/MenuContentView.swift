import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showResultDetail = false
    @State private var packageToUninstall: UpdatePackage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let result = state.lastResult, !state.isBusy {
                resultBanner(result)
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !state.ghosts.isEmpty {
                        ghostSection
                    }

                    if state.totalUpdates == 0 && state.ghosts.isEmpty && state.status.isResolved {
                        upToDateView
                    } else {
                        ForEach(state.managersWithUpdates) { manager in
                            updateGroup(manager)
                        }
                        if !state.systemUpdates.isEmpty {
                            systemSection
                        }
                    }
                }
                .padding(14)
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .frame(maxHeight: 560)
        .overlay { if state.isBusy { busyOverlay } }
        .task {
            if state.lastCheck == nil { await state.checkAll() }
        }
        .confirmationDialog(
            packageToUninstall.map { "Désinstaller \($0.name) ?" } ?? "",
            isPresented: Binding(
                get: { packageToUninstall != nil },
                set: { if !$0 { packageToUninstall = nil } }
            ),
            presenting: packageToUninstall
        ) { pkg in
            Button("Désinstaller", role: .destructive) {
                let target = pkg
                packageToUninstall = nil
                Task { await state.uninstall(target) }
            }
            Button("Annuler", role: .cancel) { packageToUninstall = nil }
        } message: { pkg in
            Text("Cette action est irréversible. \(pkg.name) sera retiré via \(pkg.manager.displayName).")
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.status.menuBarSymbol)
                .font(.title2)
                .foregroundStyle(headerColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("UpKeepy")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    private var headerColor: Color {
        switch state.status {
        case .upToDate:         return .green
        case .updatesAvailable: return .blue
        case .error:            return .red
        default:                return .secondary
        }
    }

    private var statusText: String {
        switch state.status {
        case .idle:       return "En attente…"
        case .checking:   return "Vérification en cours…"
        case .upToDate:   return "Tout est à jour ✨"
        case .updating:   return "Mise à jour en cours…"
        case .error(let m): return m
        case .updatesAvailable(let n):
            return "\(n) mise\(n > 1 ? "s" : "") à jour disponible\(n > 1 ? "s" : "")"
        }
    }

    // MARK: - Bannière de récap

    private func resultBanner(_ result: OperationResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(result.success ? .green : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title).font(.subheadline.weight(.semibold))
                    Text("Terminé en \(result.durationText)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { showResultDetail.toggle() }
                } label: {
                    Image(systemName: showResultDetail ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Voir le détail")
                Button {
                    state.lastResult = nil
                    showResultDetail = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Fermer")
            }
            if showResultDetail {
                ScrollView {
                    Text(result.detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .background((result.success ? Color.green : Color.red).opacity(0.08))
    }

    // MARK: - Casks fantômes

    private var ghostSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Applications fantômes", systemImage: "questionmark.app.dashed")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text("Homebrew les croit installées, mais leur app a disparu du disque.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(state.ghosts) { ghost in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ghost.token).font(.callout.weight(.medium))
                        Text(ghost.appName).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Réinstaller") { Task { await state.reinstall(ghost) } }
                        .controlSize(.small)
                    Button("Supprimer") { Task { await state.remove(ghost) } }
                        .controlSize(.small)
                        .tint(.red)
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Groupes de mises à jour

    private func updateGroup(_ manager: PackageManager) -> some View {
        let items = state.packages(for: manager)
        return VStack(alignment: .leading, spacing: 6) {
            Label("\(manager.displayName) (\(items.count))", systemImage: manager.symbol)
                .font(.subheadline.bold())
            ForEach(items) { pkg in
                HStack(spacing: 6) {
                    Text(pkg.name).font(.callout)
                    Spacer()
                    Text(pkg.currentVersion)
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(pkg.newVersion)
                        .font(.caption.weight(.medium)).foregroundStyle(.blue)
                    if pkg.manager != .system {
                        Button {
                            Task { await state.update(pkg) }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Mettre à jour \(pkg.name)")
                        .disabled(state.isBusy)

                        Button {
                            packageToUninstall = pkg
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Désinstaller \(pkg.name)")
                        .foregroundStyle(.secondary)
                        .disabled(state.isBusy)
                    }
                }
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("macOS (\(state.systemUpdates.count))", systemImage: "apple.logo")
                .font(.subheadline.bold())
            ForEach(state.systemUpdates, id: \.self) { item in
                Text(item).font(.callout)
            }
            Button {
                MaintenanceEngine.openSoftwareUpdateSettings()
            } label: {
                Label("Ouvrir les Réglages Système", systemImage: "gearshape")
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
    }

    private var upToDateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Ton Mac est à jour")
                .font(.headline)
            if let date = state.lastCheck {
                Text("Vérifié à \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Pied de page

    private var footer: some View {
        HStack {
            Button {
                Task { await state.checkAll() }
            } label: {
                Label("Vérifier", systemImage: "arrow.clockwise")
            }
            .disabled(state.isBusy)

            if state.totalUpdates > 0 {
                Button {
                    Task { await state.updateAll() }
                } label: {
                    Label("Tout mettre à jour", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quitter UpKeepy")
        }
        .padding(12)
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(spacing: 10) {
                if let p = state.progress, p.total > 0 {
                    ProgressView(value: Double(p.done), total: Double(p.total))
                        .frame(width: 200)
                    Text("\(p.done) / \(p.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                Text(state.busyMessage ?? "…")
                    .font(.callout.weight(.medium))
                if !state.liveOutput.isEmpty {
                    Text(state.liveOutput)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 240)
                }
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
