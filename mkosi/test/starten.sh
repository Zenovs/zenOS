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
mkdir -p "$mkosi/ausgabe/test"
# Update-Test: ZENOS_TEST_NEU=<version> bietet den zweiten Stand aus mkosi/ausgabe/veroeffentlichung/qemu/<version>/ an.
# Fehlt er noch, wartet der Test vor dem Update-Teil bis zu einer Stunde darauf (er darf parallel entstehen).
update=()
if [[ -n "${ZENOS_TEST_NEU:-}" ]]; then
	[[ "$ZENOS_TEST_NEU" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "ZENOS_TEST_NEU: eine Version wie 0.9.2" >&2; exit 2; }
	mkdir -p "$mkosi/ausgabe/veroeffentlichung/qemu"
	update=(-v "$mkosi/ausgabe/veroeffentlichung/qemu:/update-quellen:ro" -e "ZENOS_TEST_UPDATE=/update-quellen/$ZENOS_TEST_NEU")
fi
exec docker --context "$kontext" run --rm -i \
	-v "$mkosi:/zenos/mkosi:ro" \
	-v "$mkosi/ausgabe/test:/ausgabe-test" \
	-e ZENOS_TEST_BILDER=/ausgabe-test \
	${update[@]+"${update[@]}"} \
	zenos-bau:1 \
	python3 /zenos/mkosi/test/erster-start.py "/zenos/mkosi/ausgabe/qemu/$(basename "$image")"
