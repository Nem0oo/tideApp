#!/usr/bin/env bash
# Build xtool de l'arbre de travail tel quel (modifications non commitées comprises), sans tag,
# sans commit et sans rien publier.
#
#   scripts/build-local.sh           IPA complet (ship.sh) -> xtool/Tide.ipa
#   scripts/build-local.sh --quick   compilation seule (xtool dev build) -> xtool/Tide.app
#
# Le dossier .build/ du projet est réutilisé : les builds suivants sont incrémentaux.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
image=${XTOOL_IMAGE:-xtool-image}
# Version/build de l'Xcode dont vient le SDK (requis par ship.sh) ; voir scripts/release.sh.
export XCODE_VERSION=${XCODE_VERSION:-26.5}
export XCODE_BUILD=${XCODE_BUILD:-23F73}

case "${1:-}" in
  "")      cmd='/home/builder/omarchy-apple-dev/ship.sh'; result=xtool/Tide.ipa ;;
  --quick) cmd='xtool dev build'; result=xtool/Tide.app ;;
  *) echo "usage: build-local.sh [--quick]" >&2; exit 2 ;;
esac

echo "== build de l'arbre de travail ($repo) avec $image =="
docker run --rm --memory=4g --memory-swap=4g \
  -v xtool-swiftpm:/home/builder/.swiftpm \
  -v xtool-sdkcache:/home/builder/.cache/xtool \
  -v "$repo":/work \
  -e XCODE_VERSION -e XCODE_BUILD -e BUILD_NUMBER="$(date -u +%Y%m%d%H%M)" \
  "$image" bash -c "ulimit -n 65536 && $cmd"
echo "Résultat : $repo/$result"
