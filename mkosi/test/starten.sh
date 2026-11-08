#!/usr/bin/env bash
# Startet die Angriffs- und Starttests für zenOS 1.0 in QEMU, in der Bauumgebung (Docker-Kontext colima-zenos).
# Vorher: mkosi/bauen.sh qemu. Das Image bleibt unverändert; die Tests schreiben auf eine Kopie (qcow2-Überlagerung).
#
#   mkosi/test/starten.sh
set -euo pipefail

kontext=${ZENOS_DOCKER_KONTEXT:-colima-zenos}
hier=$(cd "$(dirname "$0")" && pwd)
mkosi=$(cd "$hier/.." && pwd)
image="$mkosi/ausgabe/qemu/zenos_$(cat "$mkosi/mkosi.version").raw"
[[ -f "$image" ]] || { echo "Kein Image unter $image. Zuerst: mkosi/bauen.sh qemu" >&2; exit 1; }

docker --context "$kontext" build -q -t zenos-bau:1 "$mkosi/umgebung" >/dev/null
exec docker --context "$kontext" run --rm -i \
	-v "$mkosi:/zenos/mkosi:ro" \
	zenos-bau:1 \
	python3 /zenos/mkosi/test/erster-start.py "/zenos/mkosi/ausgabe/qemu/$(basename "$image")"
