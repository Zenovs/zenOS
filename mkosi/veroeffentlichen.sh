#!/usr/bin/env bash
# Bereitet einen gebauten Stand von zenOS 1.0 als Update vor (auf dem Mac, Arbeit in der Bauumgebung).
#
#   mkosi/veroeffentlichen.sh [argon|qemu]
#
# Liest mkosi/ausgabe/<profil>/zenos_<version>.raw und legt unter mkosi/ausgabe/veroeffentlichung/<profil>/<version>/ ab:
#   zenos_<version>_<uuid>.root.raw.xz          System (erofs), UUID = erste Hälfte des Wurzel-Hashs
#   zenos_<version>_<uuid>.root-verity.raw.xz   Prüfsummen (dm-verity), UUID = zweite Hälfte
#   zenos_<version>.start.raw.xz                Startpartition (nur argon): Kernel, initrd, Gerätebäume, cmdline.txt
#   zenos_<version>.raw.xz                      ganzes Image zum Schreiben auf eine leere SSD oder einen Stick
#   SHA256SUMS                                  Prüfsummen aller Dateien, wie sie systemd-sysupdate erwartet
#
# ZENOS_AUSGABE und ZENOS_VERSION wählen ein anderes Image (wie bei bauen.sh), etwa den zweiten Stand im Update-Test.
#
# Danach signiert Zeno SHA256SUMS auf seinem Signierrechner (docs/signieren.md) und legt SHA256SUMS.gpg daneben.
# Hochgeladen wird erst nach Zenos Ja. Claude erzeugt, sieht und benutzt nie einen Signaturschlüssel.
set -euo pipefail

profil=${1:-argon}
case "$profil" in argon | qemu) ;; *) echo "Aufruf: mkosi/veroeffentlichen.sh [argon|qemu]" >&2; exit 2 ;; esac
kontext=${ZENOS_DOCKER_KONTEXT:-colima-zenos}
hier=$(cd "$(dirname "$0")" && pwd)

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	version=${ZENOS_VERSION:-$(cat "$hier/mkosi.version")}
	eingabe=${ZENOS_AUSGABE:-$profil}
	[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ && "$eingabe" =~ ^[a-z0-9-]+$ ]] || { echo "Version oder Ordner ungültig" >&2; exit 2; }
	[[ -f "$hier/ausgabe/$eingabe/zenos_$version.raw" ]] || {
		echo "Kein Image unter mkosi/ausgabe/$eingabe/zenos_$version.raw. Zuerst: mkosi/bauen.sh $profil" >&2
		exit 1
	}
	mkdir -p "$hier/ausgabe/veroeffentlichung/$profil"
	exec docker --context "$kontext" run --rm \
		-v "$hier:/zenos/mkosi:ro" \
		-v "$hier/ausgabe/$eingabe:/eingabe:ro" \
		-v "$hier/ausgabe/veroeffentlichung/$profil:/ausgabe" \
		-e ZENOS_IM_CONTAINER=1 -e ZENOS_VERSION="$version" \
		zenos-bau:1 /zenos/mkosi/veroeffentlichen.sh "$profil"
fi

# --- in der Bauumgebung ---------------------------------------------------------------------------------------
version=${ZENOS_VERSION:?}
image=/eingabe/zenos_$version.raw
ziel=/ausgabe/$version
rm -rf "$ziel"
mkdir -p "$ziel"

tabelle=$(sfdisk --json "$image")
sektor=$(jq -r '.partitiontable.sectorsize // 512' <<<"$tabelle")

# partition NAME → «start größe uuid» (Sektoren, UUID klein)
partition() {
	jq -r --arg n "$1" '.partitiontable.partitions[] | select(.name == $n) | "\(.start) \(.size) \(.uuid | ascii_downcase)"' <<<"$tabelle"
}

herausschreiben() { # NAME DATEI
	local start groesse uuid
	read -r start groesse uuid < <(partition "$1")
	[[ -n "${start:-}" ]] || { echo "Partition $1 fehlt im Image" >&2; exit 1; }
	dd if="$image" of="$2" bs="$sektor" skip="$start" count="$groesse" status=none
	printf '%s' "$uuid"
}

root_uuid=$(herausschreiben "zenos_$version" "$ziel/root.raw")
verity_uuid=$(herausschreiben "zenos_${version}_verity" "$ziel/verity.raw")
roothash=$(tr -d '-' <<<"$root_uuid$verity_uuid")
[[ "$roothash" =~ ^[0-9a-f]{64}$ ]] || { echo "Wurzel-Hash unplausibel: $roothash" >&2; exit 1; }
mv "$ziel/root.raw" "$ziel/zenos_${version}_${root_uuid}.root.raw"
mv "$ziel/verity.raw" "$ziel/zenos_${version}_${verity_uuid}.root-verity.raw"
if [[ "$profil" == argon ]]; then
	herausschreiben "zenos-start_$version" "$ziel/zenos_$version.start.raw" >/dev/null
fi
cp "$image" "$ziel/zenos_$version.raw"

xz -T0 -6 "$ziel"/*.raw
(cd "$ziel" && sha256sum -- *.xz >SHA256SUMS)

echo "Stand $version ($profil), Wurzel-Hash $roothash"
echo "Dateien in mkosi/ausgabe/veroeffentlichung/$profil/$version/:"
(cd "$ziel" && ls -l)
echo
echo "SHA256SUMS (diese Datei signiert Zeno):"
cat "$ziel/SHA256SUMS"
echo
echo "Prüfsumme von SHA256SUMS selbst (beim Signieren vergleichen): $(sha256sum "$ziel/SHA256SUMS" | cut -d' ' -f1)"
