#!/usr/bin/env bash
# Baut zenOS 1.0 in der Bauumgebung auf dem Mac.
#
#   mkosi/bauen.sh argon [mkosi-Optionen]   Image für das Argon ONE UP (Compute Module 5) und den Raspberry Pi 5
#   mkosi/bauen.sh qemu  [mkosi-Optionen]   Image für die Angriffstests in QEMU
#
# Die Bauumgebung läuft in der Colima-VM «zenos» (Docker-Kontext colima-zenos), nie im Kontext anderer Projekte.
# Das Repo ist darin nur lesbar eingehängt. Pakete liegen im Docker-Volume zenos-bau-pakete, das fertige Image unter
# mkosi/ausgabe/<profil>/ (nicht im Repo).
set -euo pipefail

profil=${1:?Aufruf: mkosi/bauen.sh argon|qemu [mkosi-Optionen]}
shift
case "$profil" in
	argon | qemu) ;;
	*) echo "Unbekanntes Profil: $profil (argon oder qemu)" >&2; exit 2 ;;
esac

kontext=${ZENOS_DOCKER_KONTEXT:-colima-zenos}
hier=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$hier/.." && pwd)
mkdir -p "$hier/ausgabe/$profil"

docker --context "$kontext" build -q -t zenos-bau:1 "$hier/umgebung" >/dev/null

# Zeitstempel aus dem letzten Commit: Derselbe Stand soll dasselbe Image ergeben.
epoch=$(git -C "$repo" log -1 --format=%ct)

exec docker --context "$kontext" run --rm --privileged \
	-v "$repo:/zenos:ro" \
	-v "$hier/ausgabe/$profil:/ausgabe" \
	-v zenos-bau-pakete:/var/cache/zenos \
	-e SOURCE_DATE_EPOCH="$epoch" \
	-w /zenos/mkosi \
	zenos-bau:1 \
	mkosi --profile="$profil" --force \
	--cache-directory=/var/cache/zenos/pakete \
	--output-directory=/ausgabe \
	"$@" build
