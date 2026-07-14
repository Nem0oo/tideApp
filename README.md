# Tide

Application iOS (SwiftUI) qui affiche les horaires et hauteurs de marée pour votre position actuelle.

## Fonctionnalités

- Géolocalisation automatique via `CoreLocation`
- Récupération des données de marée (heures et hauteurs des pleines/basses mers) via l'API [WorldWeatherOnline](https://www.worldweatheronline.com/)
- Graphique de la courbe de marée (interpolation cosinus entre les extrêmes), avec repère de l'heure actuelle
- Liste détaillée des prochaines pleines et basses mers
- Configuration de la clé API directement dans l'application (écran Réglages)

## Aperçu technique

| Fichier | Rôle |
|---|---|
| `TideApp.swift` | Point d'entrée de l'application |
| `ContentView.swift` | Écran principal : affichage du graphique et de la liste des marées |
| `TideChartView.swift` | Vue du graphique de marée (dessin de la courbe) |
| `TideService.swift` | Appel réseau à l'API de marée et modèles de décodage JSON |
| `LocationManager.swift` | Gestion de la localisation de l'utilisateur |
| `SettingsView.swift` | Écran de saisie/suppression de la clé API |

## Prérequis

- Une clé API [WorldWeatherOnline](https://www.worldweatheronline.com/) (offre gratuite disponible)
- [Theos](https://theos.dev/) installé et configuré (variable d'environnement `THEOS`)
- Un SDK iOS/toolchain compatible avec la cible définie dans le `Makefile`

## Compilation

```bash
make package   # compile l'app et génère le .ipa/.deb dans packages/
make install   # compile, package et installe sur un appareil connecté (SSH ou USB)
```

L'identifiant du bundle est `fr.gcourtot.tide`.

## Configuration de la clé API

Au premier lancement, ouvrez l'écran **Réglages** (icône engrenage) et saisissez votre clé API WorldWeatherOnline. Elle est stockée localement via `UserDefaults` et n'est jamais partagée.

## Licence

Projet personnel, non destiné à une distribution publique.
