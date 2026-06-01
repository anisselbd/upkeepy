# UpKeepy

Petite app **barre de menu** macOS qui garde ton Mac à jour, façon `topgrade`
mais graphique, en un clic, avec une fonctionnalité que `brew` ne sait pas
faire : **la détection des casks fantômes**.

`macOS 14+` · `Swift / SwiftUI` · Code ouvert (MIT)

![Le popover UpKeepy listant les mises à jour disponibles, regroupées par gestionnaire](docs/hero.png)

## Ce qu'elle fait

- **Homebrew** : formules + applications (casks), avec `cleanup` automatique.
- **npm** : paquets globaux périmés, installés à la **version exacte** (pas
  `@latest`) avec **vérification post-install** qui démasque les faux succès où
  npm sort en exit 0 alors que le module natif a échoué à compiler.
- **RubyGems** : gems périmés (le **Ruby système macOS** est ignoré, ses gems
  sont gérés par Apple et les toucher casserait des choses).
- **macOS** : liste les mises à jour système et ouvre les Réglages Système.
- **Casks fantômes** : détecte les apps que Homebrew croit installées mais qui
  ont été supprimées à la main, et propose pour chacune de **réinstaller** ou de
  **supprimer** la référence. C'est la fonctionnalité signature.
- **Diagnostic intelligent** : quand une MAJ échoue, la bannière affiche la
  cause probable et la commande à lancer (ex. `distutils` manquant en Python
  3.13 → `npm install -g node-gyp@latest`).
- **Vérification périodique en arrière-plan** (30 min / 1 h / 6 h / 24 h,
  réglable via le menu ⏰ du pied de page) + **notification système** quand de
  nouvelles MAJ apparaissent entre deux contrôles.

## Granularité

- **Un paquet** : bouton ⬇️ sur la ligne, spinner + sortie live + récap.
- **Tout** : bouton « Tout mettre à jour », barre de progression `X/N` qui
  avance paquet par paquet, avec le nom courant et sa sortie en direct.
- **Désinstall ciblée** : bouton 🗑️ avec dialogue de confirmation (brew, npm
  global, gems).
- **Récap de fin** systématique : ✅/❌ + durée mesurée + détail dépliable et
  sélectionnable (pour copier-coller un log).

![Le récapitulatif de fin d'opération : durée mesurée et journal dépliable](docs/recap.png)

L'icône de la barre de menu reflète l'état en direct :

| Icône | État |
|-------|------|
| ✅ `checkmark.seal` | tout est à jour |
| ⬇️ `arrow.down.circle` | mises à jour disponibles |
| 🔄 `arrow.triangle.2.circlepath` | vérification / mise à jour en cours |
| ⚠️ `exclamationmark.triangle` | erreur |

## Installation

Pas besoin d'Xcode complet, uniquement les Command Line Tools.

```bash
git clone https://github.com/anisselbd/upkeepy.git
cd upkeepy
./build.sh        # compile + empaquette UpKeepy.app
open UpKeepy.app  # lance l'app (icône dans la barre de menu)
```

Pour qu'elle se lance à chaque démarrage : Réglages Système → Général →
Ouverture → ajouter `UpKeepy.app`.

> Une version packagée prête à l'emploi (signée Developer ID et notarisée)
> arrivera. Une liste d'attente sera ouverte sur **upkeepy.fr**.

## Architecture

| Fichier | Rôle |
|---------|------|
| `Models.swift` | types de données (`UpdatePackage`, `GhostCask`, états) |
| `Shell.swift` | exécution de commandes avec `PATH` enrichi (une app GUI n'hérite pas du PATH du shell) |
| `MaintenanceEngine.swift` | logique métier : vérifications, parsing, mises à jour, détection fantômes |
| `AppState.swift` | état observable (`@MainActor`) partagé par l'UI |
| `MenuContentView.swift` | interface SwiftUI du popover |
| `UpKeepyApp.swift` | point d'entrée `MenuBarExtra` |
| `Tools/make-icon.swift` | génère l'icône d'app par code (Core Graphics) |

### Régénérer l'icône

```bash
swift Tools/make-icon.swift
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
./build.sh
```

## Limites connues

- Les MAJ macOS sont listées mais pas appliquées dans l'app (élévation `sudo`
  non gérée) : UpKeepy ouvre les Réglages Système pour les terminer.
- Pas de lancement automatique au démarrage intégré (à ajouter à la main pour
  l'instant, voir ci-dessus).

La suite (mode démo, lancement auto, MAJ groupées) est dans [`ROADMAP.md`](ROADMAP.md).

## Licence

[MIT](LICENSE). Fais-en ce que tu veux.
