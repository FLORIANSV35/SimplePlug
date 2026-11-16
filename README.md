# SimplePlug

Hôte minimal pour **un seul plugin AU** (effet) en **2 entrées / 2 sorties**, pour macOS.
Seuls réglages : interface audio, taille de buffer et fréquence d'échantillonnage.

## Compiler et lancer

Nécessite les Command Line Tools (`xcode-select --install`).

```
./build.sh
open build/SimplePlug.app
```

Au premier lancement, macOS demande l'accès au micro (entrées de l'interface).

## Notes

- Interfaces listées : au moins 2 entrées et 2 sorties ; canaux 1-2 utilisés.
- Effets AU uniquement (pas d'instruments).
- Compilé pour l'architecture de la machine (arm64 ou x86_64).
