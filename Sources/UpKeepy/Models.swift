import Foundation

/// Les gestionnaires de paquets pris en charge par UpKeepy.
enum PackageManager: String, CaseIterable, Identifiable, Sendable {
    case homebrew
    case homebrewCask
    case npm
    case gem
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homebrew:     return "Homebrew"
        case .homebrewCask: return "Applications"
        case .npm:          return "npm (global)"
        case .gem:          return "RubyGems"
        case .system:       return "macOS"
        }
    }

    /// Symbole SF affiché à côté du groupe.
    var symbol: String {
        switch self {
        case .homebrew:     return "cup.and.saucer.fill"
        case .homebrewCask: return "macwindow"
        case .npm:          return "shippingbox.fill"
        case .gem:          return "diamond.fill"
        case .system:       return "apple.logo"
        }
    }
}

/// Un paquet pour lequel une mise à jour est disponible.
struct UpdatePackage: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let manager: PackageManager
    let currentVersion: String
    let newVersion: String
}

/// Un cask « fantôme » : Homebrew le croit installé, mais son application
/// n'existe plus sur le disque (supprimée à la main par l'utilisateur).
struct GhostCask: Identifiable, Hashable, Sendable {
    let id = UUID()
    let token: String     // nom du cask côté Homebrew (ex. "bruno")
    let version: String   // version que Homebrew croit installée
    let appName: String   // nom de l'app attendue (ex. "Bruno.app")
}

/// Récapitulatif affiché à la fin d'une opération (succès ou échec).
struct OperationResult: Identifiable, Sendable {
    let id = UUID()
    let success: Bool
    let title: String
    let detail: String
    let duration: TimeInterval

    var durationText: String {
        duration < 1 ? "moins d'une seconde"
                     : String(format: "%.1f s", duration)
    }
}

/// État global affiché dans la barre de menu.
enum OverallStatus: Sendable, Equatable {
    case idle
    case checking
    case upToDate
    case updatesAvailable(Int)
    case updating
    case error(String)

    /// Vrai dès qu'une vérification a abouti (succès ou MAJ dispo).
    var isResolved: Bool {
        switch self {
        case .upToDate, .updatesAvailable: return true
        default: return false
        }
    }

    /// Symbole de la barre de menu selon l'état.
    var menuBarSymbol: String {
        switch self {
        case .idle, .checking, .updating: return "arrow.triangle.2.circlepath"
        case .upToDate:                   return "checkmark.seal.fill"
        case .updatesAvailable:           return "arrow.down.circle.fill"
        case .error:                      return "exclamationmark.triangle.fill"
        }
    }
}
