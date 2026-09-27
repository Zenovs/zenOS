#!/usr/bin/env bash
# holen.sh <container> <ziel-ordner> – holt die Bilder aus /srv/bilder des Testcontainers (läuft auf dem Mac).

set -euo pipefail

if (( $# != 2 )); then
  echo "Aufruf: test/container/holen.sh <container> <ziel-ordner>" >&2
  exit 2
fi
container=$1
ziel=$2
mkdir -p -- "$ziel"
docker cp "$container:/srv/bilder/." "$ziel/"
echo "Bilder in $ziel:"
find "$ziel" -maxdepth 1 -name '*.png' -print | LC_ALL=C sort
