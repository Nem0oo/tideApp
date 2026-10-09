# Tide

Application iOS (SwiftUI) qui affiche les horaires et hauteurs de marée pour votre position actuelle.

## Fonctionnalités

- Géolocalisation automatique via `CoreLocation`
- Récupération des données de marée (heures et hauteurs des pleines/basses mers) via l'API [WorldWeatherOnline](https://www.worldweatheronline.com/)
- Graphique de la courbe de marée (interpolation cosinus entre les extrêmes), avec repère de l'heure actuelle
- Liste détaillée des prochaines pleines et basses mers
- Configuration de la clé API directement dans l'application (écran Réglages)

## Aperçu technique

Cible minimale : iOS 17. Sources dans `Sources/Tide/` (app) et `Sources/TideWidgetExtension/` (widget).

| Fichier | Rôle |
|---|---|
| `TideApp.swift` | Point d'entrée de l'application |
| `ContentView.swift` | Écran principal : affichage du graphique et de la liste des marées |
| `TideChartView.swift` | Graphique de marée (Swift Charts, défilable) |
| `LocationPickerView.swift` | Choix d'une zone sur la carte et points mémorisés |
| `SavedLocation.swift` | Points mémorisés (persistés dans `UserDefaults`) |
| `TideService.swift` | Appel réseau à l'API de marée et modèles de décodage JSON |
| `LocationManager.swift` | Gestion de la localisation de l'utilisateur |
| `SettingsView.swift` | Écran de saisie/suppression de la clé API |
| `TideSnapshot.swift` | Instantané des marées partagé entre l'app et le widget (stocké dans l'App Group `group.fr.gcourtot.tide`) |
| `TideWidgetBundle.swift` | Extension widget (WidgetKit) : courbe de marée, prochains extrêmes et lever/coucher du soleil |

## Prérequis

- Une clé API [WorldWeatherOnline](https://www.worldweatheronline.com/) (offre gratuite disponible)
- Docker et l'image locale `xtool-image` (Swift + xtool + SDK iOS dans les volumes Docker `xtool-swiftpm` et `xtool-sdkcache`). Le SDK Apple ne peut pas être hébergé publiquement : le build se fait donc en local, il n'y a pas de CI GitHub.
- Pour publier une release : [`gh`](https://cli.github.com/) authentifié (`gh auth status`)

## Compilation

L'identifiant du bundle est `fr.gcourtot.tide`, le build passe par [xtool](https://xtool.sh).

Fichiers de configuration : `Package.swift`, `xtool.yml`, `Info.plist`, `TideWidgetExtension-Info.plist` et les `.entitlements`.

Build de l'arbre de travail tel quel (modifications non commitées comprises) : `scripts/build-local.sh` (IPA dans `xtool/Tide.ipa`), ou `scripts/build-local.sh --quick` pour une simple compilation.

Équivalent manuel dans l'image (produit `xtool/Tide.ipa`) :

```bash
docker run --rm --memory=4g \
  -v xtool-swiftpm:/home/builder/.swiftpm -v xtool-sdkcache:/home/builder/.cache/xtool \
  -e XCODE_VERSION=26.5 -e XCODE_BUILD=<build> -v "$PWD":/work xtool-image \
  bash -c 'ulimit -n 65536 && /home/builder/omarchy-apple-dev/ship.sh'
```

#### Release via le hook Git `pre-push`

Le hook `.githooks/pre-push` construit l'IPA et publie la release GitHub quand vous poussez un tag `vX.Y.Z`.

1. Activer le hook (une fois par clone) : `git config core.hooksPath .githooks`
2. Créer et pousser le tag : `git tag vX.Y.Z && git push origin vX.Y.Z`

Déroulé :
- Pendant le push, le hook construit l'IPA du tag (environ 2 minutes, sortie visible dans le terminal). Si le build échoue, le push est annulé.
- Une fois le tag arrivé sur GitHub, la release est créée en arrière-plan avec `gh release create`. Suivi : `tail -f /tmp/tideapp-release-vX.Y.Z.log` ou `gh release list`.
- L'IPA est aussi conservé dans `~/.cache/tideapp-releases/vX.Y.Z/`.
- Pour passer outre le hook : `git push --no-verify`.

Sans hook, ou pour rattraper un tag déjà poussé : `scripts/release.sh vX.Y.Z` (build puis publication). Le mode `--build-only` ne construit que l'IPA.

Points d'attention :
- L'IPA est signé avec une **identité de test** : il faut le re-signer pour l'installer. Le groupe d'applications `group.fr.gcourtot.tide` (partage de données avec le widget) n'est pas inclus dans cette signature ; `Tide.entitlements` (app) et `TideWidgetExtension.entitlements` (widget) doivent être réappliqués à la re-signature, sinon le widget reste vide (il affiche alors « App Group indisponible »).
- `XCODE_BUILD` (dans `scripts/release.sh`) est provisoire ; mettre le vrai build d'Xcode avant un envoi TestFlight.
- Un nouveau fichier Swift se place dans `Sources/Tide/`. S'il sert aussi au widget, ajouter un lien symbolique dans `Sources/TideWidgetExtension/` (c'est le cas de `TideSnapshot.swift`).

## Configuration de la clé API

Au premier lancement, ouvrez l'écran **Réglages** (icône engrenage) et saisissez votre clé API WorldWeatherOnline. Elle est stockée localement via `UserDefaults` et n'est jamais partagée.

## Licence

Projet personnel, non destiné à une distribution publique.
