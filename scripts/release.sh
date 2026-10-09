#!/usr/bin/env bash
# Build local de l'IPA avec l'image xtool, puis publication de la release GitHub.
#
#   scripts/release.sh vX.Y.Z --build-only   construit l'IPA du tag (ou de RELEASE_REF) et s'arrête
#   scripts/release.sh vX.Y.Z --publish      attend que le tag soit sur le remote, puis crée la release
#   scripts/release.sh vX.Y.Z                les deux (le tag doit déjà être poussé pour la 2e étape)
#
# Le build part d'un `git archive` du tag : seul le contenu commité est compilé, jamais l'arbre
# de travail. L'IPA est signé avec une identité de test (à re-signer pour l'installer).
set -euo pipefail

tag=${1:?usage: release.sh vX.Y.Z [--build-only|--publish]}
mode=${2:-all}
[[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*([-.][0-9A-Za-z.]+)?$ ]] || { echo "tag invalide: $tag" >&2; exit 2; }

repo=$(git rev-parse --show-toplevel)
ref=${RELEASE_REF:-$tag}
image=${XTOOL_IMAGE:-xtool-image}
remote=${RELEASE_REMOTE:-origin}
out=${RELEASE_OUT:-$HOME/.cache/tideapp-releases}/$tag
ipa=$out/TideApp-$tag.ipa
# Version/build de l'Xcode dont vient le SDK (requis par ship.sh).
# TODO: remplacer XCODE_BUILD par le vrai build d'Xcode 26.5 avant un envoi TestFlight.
export XCODE_VERSION=${XCODE_VERSION:-26.5}
export XCODE_BUILD=${XCODE_BUILD:-23F73}

build() {
  mkdir -p "$out"
  local work; work=$(mktemp -d "${TMPDIR:-/tmp}/tide-release.XXXXXX")
  trap 'rm -rf -- "$work"' RETURN
  git -C "$repo" archive --format=tar "$ref" | tar -x -C "$work"
  local version=${tag#v}
  for f in Info.plist TideWidgetExtension-Info.plist; do
    sed -i "/CFBundleShortVersionString/{n;s|<string>.*</string>|<string>${version}</string>|}" "$work/$f"
  done
  echo "== build $tag ($(git -C "$repo" rev-parse --short "$ref")) avec $image =="
  docker run --rm --memory=4g --memory-swap=4g \
    -v xtool-swiftpm:/home/builder/.swiftpm \
    -v xtool-sdkcache:/home/builder/.cache/xtool \
    -v "$work":/work \
    -e XCODE_VERSION -e XCODE_BUILD -e BUILD_NUMBER="$(date -u +%Y%m%d%H%M)" \
    "$image" bash -c 'ulimit -n 65536 && /home/builder/omarchy-apple-dev/ship.sh'
  cp "$work/xtool/Tide.ipa" "$ipa"
  echo "IPA: $ipa"
}

publish() {
  [ -f "$ipa" ] || { echo "IPA introuvable: $ipa (lancer --build-only d'abord)" >&2; exit 1; }
  echo "== attente du tag $tag sur $remote =="
  for _ in $(seq 1 120); do
    if git -C "$repo" ls-remote --exit-code --tags "$remote" "refs/tags/$tag" >/dev/null 2>&1; then
      (cd "$repo" && gh release create "$tag" "$ipa" --title "TideApp $tag" --generate-notes)
      echo "release $tag publiée"
      return
    fi
    sleep 5
  done
  echo "tag $tag jamais apparu sur $remote (push annulé ?) : release non créée" >&2
  exit 1
}

case "$mode" in
  --build-only) build ;;
  --publish) publish ;;
  all) build; publish ;;
  *) echo "mode inconnu: $mode" >&2; exit 2 ;;
esac
