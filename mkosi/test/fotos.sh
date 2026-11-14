#!/usr/bin/env bash
# Bildschirmfotos von zenOS 1.0 für die Website, aus dem Test-Image in QEMU (mkosi/test/fotos.py).
# Vorher: mkosi/bauen.sh qemu. Die Bilder landen unter mkosi/ausgabe/fotos/ (nicht im Repo).
#
#   mkosi/test/fotos.sh
#   ZENOS_FOTO_MOTIVE="sperre-hell raster" mkosi/test/fotos.sh     (nur diese Motive, Liste in fotos.py)
set -euo pipefail

kontext=${ZENOS_DOCKER_KONTEXT:-colima-zenos}
hier=$(cd "$(dirname "$0")" && pwd)
mkosi=$(cd "$hier/.." && pwd)
image="$mkosi/ausgabe/qemu/zenos_$(cat "$mkosi/mkosi.version").raw"
[[ -f "$image" ]] || { echo "Kein Image unter $image. Zuerst: mkosi/bauen.sh qemu" >&2; exit 1; }

docker --context "$kontext" build -q -t zenos-bau:1 "$mkosi/umgebung" >/dev/null
mkdir -p "$mkosi/ausgabe/fotos"
exec docker --context "$kontext" run --rm -i \
	-v "$mkosi:/zenos/mkosi:ro" \
	-v "$mkosi/ausgabe/fotos:/fotos" \
	-e ZENOS_TEST_BILDER=/fotos \
	-e ZENOS_FOTO_MOTIVE="${ZENOS_FOTO_MOTIVE:-}" \
	zenos-bau:1 \
	python3 /zenos/mkosi/test/fotos.py "/zenos/mkosi/ausgabe/qemu/$(basename "$image")"
