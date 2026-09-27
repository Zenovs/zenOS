#!/usr/bin/env bash
# arbeitsstand.sh [quelle] [ziel] – läuft im Testcontainer als tester. Bringt ~/zenOS auf den Stand von
# /repo (nur lesbar eingehängt): gleicher Commit und Branch, alle Tags, origin wie in /repo, dazu nicht
# committete und neue (nicht ignorierte) Dateien; in /repo gelöschte Dateien fehlen auch hier.
# Unversionierte Dateien, die nur in ~/zenOS liegen, werden entfernt (git clean).

set -euo pipefail

quelle=${1:-/repo}
ziel=${2:-$HOME/zenOS}

# /repo gehört im Container je nach Einhängung einem anderen Benutzer
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qxF -- "$quelle"; then
  git config --global --add safe.directory "$quelle"
fi

commit=$(git -C "$quelle" rev-parse --verify 'HEAD^{commit}')
zweig=$(git -C "$quelle" symbolic-ref --quiet --short HEAD || true)

if [[ ! -d "$ziel/.git" ]]; then
  git init --quiet "$ziel"
fi
git -C "$ziel" fetch --quiet --force --tags "$quelle" "+HEAD:refs/zenos/quelle"
if [[ -n "$zweig" ]]; then
  git -C "$ziel" checkout --quiet --force -B "$zweig" "$commit"
else
  git -C "$ziel" -c advice.detachedHead=false checkout --quiet --force --detach "$commit"
fi
git -C "$ziel" clean --quiet -fd

url=$(git -C "$quelle" remote get-url origin 2>/dev/null || true)
if [[ -n "$url" ]]; then
  if git -C "$ziel" remote get-url origin >/dev/null 2>&1; then
    git -C "$ziel" remote set-url origin "$url"
  else
    git -C "$ziel" remote add origin "$url"
  fi
fi

# Arbeitsstand übertragen: vorhandene, nicht ignorierte Dateien kopieren, gelöschte entfernen
liste=$(mktemp)
trap 'rm -f -- "$liste"' EXIT
while IFS= read -r -d '' pfad; do
  if [[ -e "$quelle/$pfad" || -L "$quelle/$pfad" ]]; then printf '%s\0' "$pfad" >> "$liste"; fi
done < <(git -C "$quelle" ls-files -z --cached --others --exclude-standard)
tar -c -f - -C "$quelle" --null --no-recursion --files-from="$liste" | tar -x -f - -C "$ziel" --no-same-owner
git -C "$quelle" ls-files -z --deleted | (cd -- "$ziel" && xargs -0 -r rm -f --)

geaendert=$(git -C "$ziel" status --porcelain | wc -l | tr -d ' ')
printf '%s: %s (%s), %s Dateien abweichend vom Commit\n' "${ziel/#"$HOME"/\~}" "${commit:0:7}" "${zweig:-losgelöst}" "$geaendert"
