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
#   SHA256SUMS                                  Prüfsummen aller Dateien; diese Liste wird signiert
#   SHA256SUMS.sig                              nur qemu: Signatur mit dem Wegwerf-Schlüssel des Tests
#
# ZENOS_AUSGABE und ZENOS_VERSION wählen ein anderes Image (wie bei bauen.sh), etwa den zweiten Stand im Update-Test.
#
# argon: Danach signiert Zeno SHA256SUMS selbst, in seinem Terminal, mit PIN und Berührung seines FIDO2-Schlüssels
# (docs/signieren.md). Das legt SHA256SUMS.sig daneben; mkosi/signatur-pruefen.sh prüft sie wie der Argon.
# Hochgeladen wird erst nach Zenos Ja. Claude erzeugt, sieht und benutzt nie einen Signaturschlüssel und startet nie
# einen Signaturbefehl; der Wegwerf-Schlüssel des QEMU-Tests gilt auf keinem Gerät.
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
	test=()
	if [[ "$profil" == qemu ]]; then
		[[ -f "$hier/ausgabe/test-schluessel/zenos-test" ]] || {
			echo "Kein Wegwerf-Schlüssel unter mkosi/ausgabe/test-schluessel/. Zuerst: mkosi/bauen.sh qemu" >&2
			exit 1
		}
		test=(-v "$hier/ausgabe/test-schluessel:/test-schluessel:ro")
	fi
	exec docker --context "$kontext" run --rm \
		-v "$hier:/zenos/mkosi:ro" \
		-v "$hier/ausgabe/$eingabe:/eingabe:ro" \
		-v "$hier/ausgabe/veroeffentlichung/$profil:/ausgabe" \
		${test[@]+"${test[@]}"} \
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

if [[ "$profil" == qemu ]]; then
	# Nur für QEMU: Der Wegwerf-Schlüssel gilt allein im Test-Image (mkosi.finalize, ZENOS_TEST_SIGNIERER).
	install -m 0600 /test-schluessel/zenos-test /tmp/zenos-test
	ssh-keygen -q -Y sign -f /tmp/zenos-test -n argon-update "$ziel/SHA256SUMS"
	rm -f /tmp/zenos-test
fi

echo "Stand $version ($profil), Wurzel-Hash $roothash"
echo "Dateien in mkosi/ausgabe/veroeffentlichung/$profil/$version/:"
(cd "$ziel" && ls -l)
echo
echo "SHA256SUMS:"
cat "$ziel/SHA256SUMS"
echo
echo "Prüfsumme von SHA256SUMS selbst: $(sha256sum "$ziel/SHA256SUMS" | cut -d' ' -f1)"
if [[ "$profil" == argon ]]; then
	echo
	echo "Zeno signiert in seinem Terminal (PIN, dann den Schlüssel berühren), aus dem Ordner des Repos:"
	echo "  /opt/homebrew/bin/ssh-keygen -Y sign -f ~/.ssh/argon_update_a -n argon-update mkosi/ausgabe/veroeffentlichung/argon/$version/SHA256SUMS"
	echo "Danach prüft mkosi/signatur-pruefen.sh $version die Signatur wie der Argon."
fi
