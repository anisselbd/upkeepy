import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showResultDetail = false
    @State private var packageToUninstall: UpdatePackage?
    // Hauteur réelle du contenu de la liste : indispensable car dans une
    // MenuBarExtra(.window), un ScrollView sans hauteur explicite se replie
    // à sa taille idéale (quasi nulle) depuis le SDK macOS 26.
    @State private var listContentHeight: CGFloat = 0

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
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    listContentHeight = newValue
                }
            }
            .frame(height: min(max(listContentHeight, 56), 420))

            Divider()
            footer
        }
        .frame(width: 380)
        .overlay { if state.isBusy { busyOverlay } }
        .task {
            if state.lastCheck == nil { await state.checkAll() }
        }
        .confirmationDialog(
            packageToUninstall.map { "Uninstall \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { packageToUninstall != nil },
                set: { if !$0 { packageToUninstall = nil } }
            ),
            presenting: packageToUninstall
        ) { pkg in
            Button("Uninstall", role: .destructive) {
                let target = pkg
                packageToUninstall = nil
                Task { await state.uninstall(target) }
            }
            Button("Cancel", role: .cancel) { packageToUninstall = nil }
        } message: { pkg in
            Text("This can't be undone. \(pkg.name) will be removed via \(pkg.manager.displayName).")
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
        case .idle:       return "Idle…"
        case .checking:   return "Checking…"
        case .upToDate:   return "Everything is up to date ✨"
        case .updating:   return "Updating…"
        case .error(let m): return m
        case .updatesAvailable(let n):
            return "\(n) update\(n > 1 ? "s" : "") available"
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
                    Text("Done in \(result.durationText)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { showResultDetail.toggle() }
                } label: {
                    Image(systemName: showResultDetail ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Show details")
                Button {
                    state.lastResult = nil
                    showResultDetail = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
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
            Label("Ghost apps", systemImage: "questionmark.app.dashed")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text("Homebrew thinks they're installed, but their app is gone from disk.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(state.ghosts) { ghost in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ghost.token).font(.callout.weight(.medium))
                        Text(ghost.appName).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reinstall") { Task { await state.reinstall(ghost) } }
                        .controlSize(.small)
                    Button("Remove") { Task { await state.remove(ghost) } }
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
                        .help("Update \(pkg.name)")
                        .disabled(state.isBusy)

                        Button {
                            packageToUninstall = pkg
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Uninstall \(pkg.name)")
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
                Label("Open System Settings", systemImage: "gearshape")
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
            Text("Your Mac is up to date")
                .font(.headline)
            if let date = state.lastCheck {
                Text("Checked at \(date.formatted(date: .omitted, time: .shortened))")
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
                Label("Check", systemImage: "arrow.clockwise")
            }
            .disabled(state.isBusy)

            if state.totalUpdates > 0 {
                Button {
                    Task { await state.updateAll() }
                } label: {
                    Label("Update all", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            }

            Spacer()

            Menu {
                Picker("Automatic checks", selection: $state.checkIntervalMinutes) {
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Every 6 hours").tag(360)
                    Text("Every 24 hours").tag(1440)
                    Divider()
                    Text("Off").tag(0)
                }
            } label: {
                Image(systemName: state.checkIntervalMinutes == 0
                      ? "clock.badge.xmark"
                      : "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(scheduleHelp)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit UpKeepy")
        }
        .padding(12)
    }

    private var scheduleHelp: String {
        switch state.checkIntervalMinutes {
        case 0:    return "Automatic checks off"
        case 30:   return "Checking every 30 minutes"
        case 60:   return "Checking every hour"
        case 360:  return "Checking every 6 hours"
        case 1440: return "Checking every 24 hours"
        default:   return "Scheduled checks"
        }
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
