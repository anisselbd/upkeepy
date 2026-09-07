# Distribuer UpKeepy via Homebrew

C'est le canal le plus naturel pour ce produit : quelqu'un qui a besoin
d'UpKeepy a forcément déjà Homebrew installé.

## Le dépôt officiel n'est pas accessible tout de suite

`homebrew/cask` impose un seuil de notoriété aux projets open source hébergés
sur GitHub : **75 étoiles, 30 forks ou 30 watchers**. En deçà, la pull request
est refusée, quelle que soit la qualité du logiciel.

La stratégie est donc en deux temps : un tap personnel maintenant, le dépôt
officiel une fois le seuil franchi. Un tap personnel n'a aucune limite et
s'installe en une commande, il change juste le nom à taper.

## Étape 1 : le tap personnel

Le dépôt doit s'appeler `homebrew-tap`, la convention étant que Homebrew retire
le préfixe `homebrew-`.

```bash
gh repo create anisselbd/homebrew-tap --public \
  --description "Casks Homebrew d'anisselbd"
git clone https://github.com/anisselbd/homebrew-tap
mkdir -p homebrew-tap/Casks
```

Copier ensuite le cask généré par `release.sh` (dans `dist/upkeepy.rb`) vers
`homebrew-tap/Casks/upkeepy.rb`, puis pousser.

L'installation devient :

```bash
brew install --cask anisselbd/tap/upkeepy
```

## Étape 2 : vérifier le cask avant de pousser

```bash
brew audit --new --cask anisselbd/tap/upkeepy
brew install --cask anisselbd/tap/upkeepy
brew uninstall --cask upkeepy
```

`brew audit` refuse notamment les descriptions qui commencent par un article ou
qui répètent le nom de l'app : `desc` doit tenir en une ligne factuelle.

## Étape 3 : à chaque version

`release.sh` régénère `dist/upkeepy.rb` avec la version et le sha256 corrects.
Il suffit de le recopier dans le tap et de pousser. Le bloc `livecheck` permet
à Homebrew de détecter automatiquement les versions suivantes.

## Étape 4 : basculer vers le dépôt officiel

Une fois le seuil de notoriété atteint :

```bash
brew bump-cask-pr --version 1.2.0 upkeepy
```

Le cask officiel rend l'installation universelle :

```bash
brew install --cask upkeepy
```

Penser alors à déprécier le cask du tap personnel pour ne pas maintenir deux
recettes en parallèle.
