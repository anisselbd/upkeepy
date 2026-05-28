# Feuille de route UpKeepy

État V1 : **fonctionnelle et fiable**. Détecte et applique les MAJ Homebrew
(formules + casks), npm global, macOS, avec récap intelligent post-opération
et détection interactive des casks fantômes.

## Idées V2 — par ordre d'impact perçu

### 🥇 Mode démo (état simulé)
Toggle dans les préférences qui forge une fausse liste de paquets en attente,
indépendamment de l'état réel de la machine. Utile pour présenter le produit
(captures, screencasts, démos clients) sans dépendre de l'instant T.

### ✅ Désinstall par paquet *(livré)*
Bouton 🗑️ à côté du ⬇️ sur chaque ligne, avec dialogue de confirmation
destructif. Couvre brew (formules + casks), npm global et gems.

### ✅ Vérification périodique en arrière-plan *(livré)*
Scheduler interne (Swift `Task` + `Task.sleep`) qui re-vérifie tous les N
minutes (30 / 60 / 360 / 1440 / désactivé, persistant via `UserDefaults`).
Notification système (`UserNotifications`) envoyée uniquement quand de
nouvelles MAJ apparaissent entre deux ticks. Réglage via menu ⏰ dans le
pied de page.

### Bouton « Tout mettre à jour ce groupe »
Sur l'en-tête de chaque gestionnaire (Homebrew, npm, gem…), un bouton qui
itère uniquement sur ce groupe avec sa propre barre `X/N`.

### Vérification post-install Homebrew (parité avec npm)
Aujourd'hui seul npm est protégé contre les faux succès. Ajouter le même
garde-fou pour `brew upgrade` (vérifier `brew list --versions <pkg>`) couvrirait
le cas où brew sort en succès sans avoir réellement migré.

### Détection enrichie d'erreurs connues
On a déjà `distutils` + `EACCES`. À ajouter au fil de l'eau :
`EPEERINVALID`, `ENOTSUP`, `nodeBindingsMissing`, `Could not detect Python`,
`EROFS` (SIP), etc. Chaque pattern → un conseil concret dans la bannière.

### Application directe des MAJ macOS
Aujourd'hui on ouvre les Réglages Système (sudo). Lancer `softwareupdate -ia`
nécessite une élévation propre — possibilités :
- `STPrivilegedTask` / `AuthorizationExecuteWithPrivileges` (déprécié).
- Helper privilégié via SMJobBless (workflow Apple complexe).
- Voie pragmatique : exposer un copier-coller de la commande sudo + lancer
  Terminal sur celle-ci.

### Lancement automatique au démarrage
Aujourd'hui : ajout manuel dans Réglages Système → Général → Ouverture.
Cible : toggle in-app via `SMAppService.mainApp.register()` (macOS 13+).

### Tests unitaires
Le code le plus fragile est le parsing :
- `parseBrewOutdated` (formules `<` vs casks `!=`, versions multiples).
- `detectGhostCasks` (JSON v2 avec/sans artefact app, multi-apps).
- `checkNpm` (paquet en état `current: null` / MISSING).
- `checkGems` (lignes hors-format, sauts de version mineurs).

Suite de tests SwiftPM (`Tests/UpKeepyTests/`) avec des fixtures de sortie
brew/npm/gem capturées en réel.

### Polish UX
- Tail intelligent du log dans la bannière (les 30 dernières lignes par
  défaut, plein log au déclic).
- Bouton « Copier le log » dans la bannière d'échec.
- Animation douce sur l'apparition/disparition de la bannière.
- Raccourci clavier (⌘R = Vérifier, ⌘U = Tout mettre à jour).

### Localisation
Aujourd'hui 100 % français en dur. Étape : tout passer en `String(localized:)`
pour préparer EN/FR/etc.

## Hors V2 (à débattre)

- **Auto-update d'UpKeepy lui-même** (vérifier GitHub releases) — utile si
  l'app est distribuée hors App Store.
- **Notarisation Apple** pour distribution publique (Developer ID requis).
- **Support des autres gestionnaires** : pip, cargo, rustup, asdf, mise…
  À mesurer en demande réelle avant d'ouvrir cette boîte.
