#!/usr/bin/env bash
# Prüft die Startpartitionen eines Images für den Argon, bevor es auf die SSD kommt (liest nur): Partitionstabelle,
# autoboot.txt, Startpartition A (Kernel, initramfs, Gerätebäume, config.txt, cmdline.txt passend zu den Partitionen)
# und die leere Startpartition B.
#
#   mkosi/test/startpartitionen.sh [BILD]     (Vorgabe: mkosi/ausgabe/argon/zenos_<mkosi.version>.raw)
set -uo pipefail

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	hier=$(cd "$(dirname "$0")/.." && pwd)
	bild=${1:-$hier/ausgabe/argon/zenos_$(cat "$hier/mkosi.version").raw}
	[[ -f "$bild" ]] || { echo "Kein Image: $bild" >&2; exit 2; }
	ordner=$(cd "$(dirname "$bild")" && pwd)
	exec docker --context "${ZENOS_DOCKER_KONTEXT:-colima-zenos}" run --rm -v "$ordner:/bild:ro" \
		-v "$hier/test:/test:ro" -e ZENOS_IM_CONTAINER=1 zenos-bau:1 bash /test/startpartitionen.sh \
		"/bild/$(basename "$bild")"
fi

bild=$1
fehler=0
pruefe() { # BEDINGUNG-EXIT TEXT
	if [[ "$1" == 0 ]]; then
		printf '  ok      %s\n' "$2"
	else
		printf '  FEHLER  %s\n' "$2"
		fehler=$((fehler + 1))
	fi
}

# Partitionstabelle (GPT): Nummer, Startsektor, Grösse in MB, Typ, eindeutige UUID, Name
teile=$(python3 - "$bild" <<'PY'
import struct, sys, uuid
with open(sys.argv[1], "rb") as f:
    f.seek(512)
    kopf = f.read(92)
    assert kopf[:8] == b"EFI PART", "keine GPT"
    start, anzahl, groesse = struct.unpack_from("<QII", kopf, 72)
    f.seek(start * 512)
    for i in range(anzahl):
        e = f.read(groesse)
        if e[:16] == b"\0" * 16:
            continue
        typ = uuid.UUID(bytes_le=e[:16])
        eigen = uuid.UUID(bytes_le=e[16:32])
        erster, letzter = struct.unpack_from("<QQ", e, 32)
        name = e[56:128].decode("utf-16-le").rstrip("\0")
        print(i + 1, erster, (letzter - erster + 1) * 512 // 1048576, typ, eigen, name)
PY
)
echo "--- Partitionen (Nr. Startsektor MB Typ UUID Name)"
printf '%s\n' "$teile"
feld() { awk -v n="$1" -v f="$2" '$1 == n { print $f }' <<<"$teile"; }
esp=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
version=$(feld 2 6 | sed -n 's/^zenos-start_//p')

echo "--- Prüfungen"
[[ "$(feld 1 4)" == "$esp" && "$(feld 2 4)" == "$esp" && "$(feld 3 4)" == "$esp" ]]
pruefe $? "die ersten drei Partitionen sind FAT-Startpartitionen (ESP), wie der Bootloader es für tryboot braucht"
[[ "$(feld 1 6)" == zenos-start && -n "$version" && "$(feld 3 6)" == _empty ]]
pruefe $? "Bezeichnungen: zenos-start, zenos-start_$version, _empty"
[[ "$(feld 4 6)" == "zenos_${version}_verity" && "$(feld 5 6)" == "zenos_$version" ]]
pruefe $? "Prüfsummen und System A tragen die Version $version"

p() { printf '%s@@%s' "$bild" $(($(feld "$1" 2) * 512)); }
soll=$(printf '[all]\ntryboot_a_b=1\nboot_partition=2\n[tryboot]\nboot_partition=3\n')
[[ "$(mtype -i "$(p 1)" ::autoboot.txt 2>/dev/null)" == "$soll" ]]
pruefe $? "autoboot.txt: startet Partition 2, Probestart auf 3"

inhalt=$(mdir -b -i "$(p 2)" :: 2>/dev/null)
fehlt=""
for datei in kernel_2712.img initramfs_2712 config.txt cmdline.txt bcm2712-rpi-cm5l-cm5io.dtb bcm2712-rpi-5-b.dtb \
	overlays/; do
	grep -qx -- "::/$datei" <<<"$inhalt" || fehlt+=" $datei"
done
[[ -z "$fehlt" ]]
pruefe $? "Startpartition A hat Kernel, initramfs, Gerätebäume (CM5 Lite, Pi 5), Overlays und Konfiguration${fehlt:+ (fehlt:$fehlt)}"

config=$(mtype -i "$(p 2)" ::config.txt 2>/dev/null)
grep -qx 'enable_uart=0' <<<"$config" && grep -qx 'kernel=kernel_2712.img' <<<"$config" &&
	grep -qx 'dtoverlay=dwc2,dr_mode=host' <<<"$config"
pruefe $? "config.txt: Kernel 2712, keine serielle Konsole, USB für Tastatur und Touchpad"

cmdline=$(mtype -i "$(p 2)" ::cmdline.txt 2>/dev/null)
hash=$(grep -o 'roothash=[0-9a-f]\{64\}' <<<"$cmdline" | cut -d= -f2)
daten=$(grep -o 'systemd.verity_root_data=PARTUUID=[0-9a-f-]*' <<<"$cmdline" | cut -d= -f3)
pruefsummen=$(grep -o 'systemd.verity_root_hash=PARTUUID=[0-9a-f-]*' <<<"$cmdline" | cut -d= -f3)
[[ -n "$hash" && "$daten" == "$(feld 5 5)" && "$pruefsummen" == "$(feld 4 5)" ]]
pruefe $? "cmdline.txt: Wurzel-Hash und PARTUUIDs passen zu System A und seinen Prüfsummen"
[[ -n "$hash" && "${hash:0:32}" == "$(tr -d - <<<"$(feld 5 5)")" && "${hash:32:32}" == "$(tr -d - <<<"$(feld 4 5)")" ]]
pruefe $? "die UUIDs stammen aus dem Wurzel-Hash (so findet systemd-sysupdate die Partitionen)"

# Leer heisst: ein lesbares FAT ohne Einträge (eine Fehlermeldung von mdir zählt nicht als leer)
minfo -i "$(p 3)" :: >/dev/null 2>&1 && [[ -z "$(mdir -b -i "$(p 3)" :: 2>/dev/null)" ]]
pruefe $? "Startpartition B ist ein leeres FAT (frei für das erste Update)"

if ((fehler == 0)); then
	echo "Alle Prüfungen bestanden"
else
	echo "$fehler Prüfungen gescheitert"
	exit 1
fi
