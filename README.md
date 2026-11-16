# SimplePlug

Hôte minimal pour **un seul plugin AU** (effet) en **2 entrées / 2 sorties**, pour macOS.
Seuls réglages : interface audio, taille de buffer et fréquence d'échantillonnage.

## Installation

### 1. Prérequis

Les Command Line Tools d'Apple (inutile d'installer Xcode) :

```bash
xcode-select --install
```

### 2. Récupérer le projet

```bash
git clone https://github.com/FLORIANSV35/SimplePlug.git
cd SimplePlug
```

### 3. Compiler

```bash
chmod +x build.sh   # rend le script exécutable (une seule fois)
./build.sh
```

Le script compile l'app et la signe en ad-hoc. Résultat : `build/SimplePlug.app`.

### 4. Lancer

```bash
open build/SimplePlug.app
```

Au premier lancement, macOS demande l'accès au **micro** : accepte, c'est ce qui donne
accès aux entrées de l'interface audio. Si tu as refusé par erreur :
Réglages Système › Confidentialité et sécurité › Microphone.

Pour l'avoir dans tes applications :

```bash
cp -R build/SimplePlug.app /Applications/
```

> Si macOS bloque l'app (« développeur non identifié ») après l'avoir copiée ou téléchargée :
> `xattr -dr com.apple.quarantine /Applications/SimplePlug.app`

## Utilisation

1. Choisis ton **interface audio** (au moins 2 in / 2 out ; canaux 1-2 utilisés).
2. Règle le **buffer** et la **fréquence** (la latence aller-retour approximative s'affiche).
3. Choisis le **plugin AU** : son interface s'affiche dans la fenêtre.

Tous les réglages, y compris l'état du plugin, sont mémorisés.

## Mises à jour

SimplePlug vérifie les nouvelles releases GitHub au lancement (au plus une fois par jour) et propose de
les installer : téléchargement, vérification de l'app, remplacement et relance automatiques.
Tu peux aussi le faire à la main : menu **SimplePlug › Rechercher des mises à jour…**

- La vérification contacte `api.github.com` (une requête, sans donnée personnelle).
- L'app doit être dans un dossier où tu as le droit d'écrire (ex. `/Applications`).
- L'app n'étant pas notarisée, macOS peut redemander l'accès au micro après une mise à jour.
- Les versions antérieures à 1.0.1 n'ont pas d'updater : installe la 1.0.1 à la main une fois.

## Limites

- Effets AU uniquement (pas d'instruments).
- Une seule interface pour l'entrée et la sortie.
- Compilé pour l'architecture de la machine (arm64 ou x86_64) : un plugin d'une autre
  architecture ne se chargera pas.
