# Publier une version d'UpKeepy

De la compilation au cask Homebrew. Les étapes 1 à 3 ne sont à faire qu'une
seule fois ; ensuite, publier une version tient en une commande.

## Pourquoi tout ce protocole

Une app macOS téléchargée hors du Mac App Store est inspectée par Gatekeeper.
Sans certificat Developer ID **et** sans notarisation, l'utilisateur voit
« UpKeepy est endommagé et ne peut pas être ouvert », et abandonne. Une
signature ad-hoc (`codesign --sign -`) fonctionne uniquement sur la machine qui
l'a produite : elle ne sert qu'au développement local.

## 1. Certificat Developer ID Application *(une fois)*

Un certificat « Apple Development » ne convient pas : il ne signe que pour le
test local. Il faut un **Developer ID Application**, réservé aux comptes Apple
Developer payants.

    Xcode → Settings → Accounts → sélectionner le compte
        → Manage Certificates… → bouton + → « Developer ID Application »

Vérifier ensuite qu'il est bien dans le trousseau :

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## 2. Mot de passe dédié à la notarisation *(une fois)*

L'Apple ID principal ne peut pas servir directement, il faut un mot de passe
d'application :

1. aller sur https://account.apple.com → « Connexion et sécurité » ;
2. « Mots de passe pour applications » → en générer un, nommé par exemple
   `notarytool` ;
3. le copier, il ne sera plus jamais affiché.

Le Team ID se lit sur https://developer.apple.com/account sous « Membership
details ». En local, il se lit de façon fiable dans le champ `OU` du
certificat :

```bash
security find-certificate -c "Developer ID Application" -p \
  | openssl x509 -noout -subject
```

Attention : pour un certificat « Apple Development », la valeur entre
parenthèses du nom **n'est pas** le Team ID mais l'identifiant du certificat.
S'en servir donne un `HTTP 403 Invalid or inaccessible developer team ID`.

## 3. Enregistrer le profil notarytool *(une fois)*

Le profil est stocké dans le trousseau, ce qui évite de laisser traîner un mot
de passe dans un script ou une variable d'environnement.

```bash
xcrun notarytool store-credentials "upkeepy" \
  --apple-id "<ton Apple ID>" \
  --team-id "<TEAM_ID>" \
  --password "<le mot de passe de l'étape 2>"
```

## 4. Publier une version

```bash
VERSION=1.0.0 ./release.sh
```

Le script enchaîne : compilation release, signature avec hardened runtime et
horodatage, fabrication du DMG (avec l'alias vers `/Applications`), signature du
DMG, envoi à Apple, agrafage du ticket, contrôle Gatekeeper. Il affiche à la fin
la taille et le **sha256**, nécessaire au cask Homebrew.

Compter quelques minutes, l'essentiel étant l'attente côté Apple. Pour répéter
le pipeline sans solliciter Apple :

```bash
SKIP_NOTARIZE=1 ./release.sh    # le DMG produit n'est PAS distribuable
```

## 5. Vérifier avant de diffuser

Le test qui compte est celui d'une machine qui n'a jamais vu l'app. À défaut, on
s'en approche en simulant un téléchargement (l'attribut de quarantaine est ce
qui déclenche le contrôle Gatekeeper) :

```bash
xattr -w com.apple.quarantine "0081;00000000;Safari;" dist/UpKeepy-1.0.0.dmg
open dist/UpKeepy-1.0.0.dmg
```

L'app doit s'ouvrir sans avertissement autre que le « téléchargé depuis
internet » habituel. Si macOS parle d'un développeur non identifié, la
notarisation ou l'agrafage a échoué.

## 6. GitHub Release

```bash
gh release create v1.0.0 dist/UpKeepy-1.0.0.dmg \
  --title "UpKeepy 1.0.0" \
  --notes-file docs/release-notes.md
```

## 7. Cask Homebrew

Le canal de distribution principal : les utilisateurs d'UpKeepy sont, par
définition, des utilisateurs de Homebrew.

Voir `docs/HOMEBREW.md`.
