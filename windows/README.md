# SimplePlug pour Windows

Hôte minimal pour **un seul plugin VST3** (effet) en **2 entrées / 2 sorties**.
Même principe que la version macOS (qui héberge un plugin AU : les Audio Units n'existent
pas sous Windows, l'équivalent est le **VST3**).

Réglages : interface audio, fréquence d'échantillonnage et taille de buffer. Une jauge
**Charge buffer** montre le temps de calcul par rapport à la durée d'un buffer
(au-delà de 100 %, l'audio craque : augmente le buffer).

> Version **expérimentale** : compilée automatiquement par GitHub Actions, développée et
> testée côté code sur macOS. Les retours sur de vraies interfaces Windows sont bienvenus.

## Installation

1. Télécharge `SimplePlug-X.Y.Z-windows-x64.zip` (page *Releases*, ou artefact du dernier
   build dans l'onglet *Actions*), dézippe-le où tu veux.
2. Lance `SimplePlug.exe`. Comme le programme n'est pas signé, SmartScreen peut afficher
   « Windows a protégé votre PC » : clique sur **Informations complémentaires › Exécuter quand même**.
3. Aucune installation, aucun prérequis (le runtime C++ est inclus).

## Utilisation

- **Type d'interface** : choisis **ASIO** si ton interface a un pilote ASIO (latence la plus faible).
  Sinon *Windows Audio* (WASAPI) ou DirectSound. Le bouton « Panneau de contrôle » ouvre celui du pilote ASIO.
- **Entrée / Sortie**, **Fréquence**, **Taille du buffer** : réglables directement. Seuls 2 canaux
  (une paire stéréo) sont utilisés en entrée et en sortie.
- **Plugin VST3** : la liste vient du scan de `C:\Program Files\Common Files\VST3`
  (et du dossier utilisateur). Bouton **Rescanner** après avoir installé un plugin.
  Si un plugin plante l'analyse, il est ignoré au lancement suivant.
- Les réglages et l'état du plugin sont mémorisés (`%APPDATA%\SimplePlug`).
- **Mises à jour** : l'app vérifie la dernière release GitHub (au plus une fois par jour) et
  propose d'ouvrir le téléchargement. Pas d'installation automatique sous Windows.

## Compiler soi-même

Prérequis : Visual Studio 2022 (charge de travail « Développement Desktop en C++ »), CMake ≥ 3.22, Git.

```powershell
cmake -S windows -B build -A x64
cmake --build build --config Release
# → build\SimplePlug_artefacts\Release\SimplePlug.exe
```

JUCE 9.0.5 est téléchargé automatiquement par CMake.

## Licence

Cette version utilise le framework [JUCE](https://juce.com) sous licence **AGPLv3**
(avec ses en-têtes ASIO fournis) ; son code source est donc distribué sous **GNU AGPL v3**,
voir le fichier `LICENSE`. La version macOS (dossier `Sources/`) est indépendante.
