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
# Der Bootloader von Raspberry Pi liest FAT nur mit 512 Byte pro Sektor; systemd-repart legt 4096 an (mkosi.postoutput
# formatiert neu). Am Argon gesehen am 13.11.2026: Er fand config.txt nicht und probierte eine Partition nach der anderen.
sektoren=$(for n in 1 2 3; do od -An -tu2 --endian=little -j $(($(feld "$n" 2) * 512 + 11)) -N 2 "$bild" | tr -d ' '; done | paste -sd ' ' -)
[[ "$sektoren" == "512 512 512" ]]
pruefe $? "die drei Startpartitionen haben 512 Byte pro Sektor, wie der Bootloader sie lesen kann ($sektoren)"
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

# Deckel: Das eigene Overlay liegt bei den Overlays, config.txt lädt es nur auf dem CM5, und auf den Gerätebaum des
# CM5 Lite angewendet ergibt es einen Schalter SW_LID an GPIO27 des RP1 mit Pull-up.
[[ "$(awk '/^\[/ { abschnitt = $0 } $0 == "dtoverlay=zenos-deckel" { print abschnitt }' <<<"$config")" == "[cm5]" ]]
pruefe $? "config.txt: Overlay des Deckels nur im Abschnitt [cm5]"
probe=$(mktemp -d)
mcopy -n -i "$(p 2)" ::bcm2712-rpi-cm5l-cm5io.dtb ::overlays/zenos-deckel.dtbo "$probe/" 2>/dev/null &&
	fdtoverlay -i "$probe/bcm2712-rpi-cm5l-cm5io.dtb" -o "$probe/mit-deckel.dtb" "$probe/zenos-deckel.dtbo" 2>/dev/null &&
	[[ "$(fdtget "$probe/mit-deckel.dtb" /zenos_deckel compatible)" == gpio-keys &&
		"$(fdtget "$probe/mit-deckel.dtb" /zenos_deckel/deckel linux,input-type)" == 5 &&
		"$(fdtget "$probe/mit-deckel.dtb" /zenos_deckel/deckel linux,code)" == 0 ]] &&
	gpio=$(fdtget "$probe/mit-deckel.dtb" /__symbols__ rp1_gpio) &&
	[[ "$(fdtget -t s "$probe/mit-deckel.dtb" "$gpio/zenos_deckel_pins" pins)" == gpio27 ]] &&
	fdtget "$probe/mit-deckel.dtb" "$gpio/zenos_deckel_pins" bias-pull-up >/dev/null 2>&1
pruefe $? "Overlay des Deckels passt auf den CM5 Lite: Schalter SW_LID an GPIO27 mit Pull-up"
rm -rf "$probe"

cmdline=$(mtype -i "$(p 2)" ::cmdline.txt 2>/dev/null)
hash=$(grep -o 'roothash=[0-9a-f]\{64\}' <<<"$cmdline" | cut -d= -f2)
daten=$(grep -o 'systemd.verity_root_data=PARTUUID=[0-9a-f-]*' <<<"$cmdline" | cut -d= -f3)
pruefsummen=$(grep -o 'systemd.verity_root_hash=PARTUUID=[0-9a-f-]*' <<<"$cmdline" | cut -d= -f3)
[[ -n "$hash" && "$daten" == "$(feld 5 5)" && "$pruefsummen" == "$(feld 4 5)" ]]
pruefe $? "cmdline.txt: Wurzel-Hash und PARTUUIDs passen zu System A und seinen Prüfsummen"
[[ -n "$hash" && "${hash:0:32}" == "$(tr -d - <<<"$(feld 5 5)")" && "${hash:32:32}" == "$(tr -d - <<<"$(feld 4 5)")" ]]
pruefe $? "die UUIDs stammen aus dem Wurzel-Hash (so findet systemd-sysupdate die Partitionen)"

# initrd: Kein Funk-Treiber darf darin sein (mkosi.profiles/argon/mkosi.conf, KernelModulesInitrdExclude=). Lädt
# brcmfmac schon im initrd, findet es dort seine Firmware nicht und gibt den WLAN-Chip für immer auf. Ohne greifenden
# Filter kämen alle Module hinein (mkosi 25.3), am 14.11.2026 waren es 1916, davon 124 für Funk; «0 für Funk» zeigt also
# auch, dass der Filter greift. Alles andere bleibt absichtlich drin (1792). Was zum Start nötig ist, muss drin sein.
# Das initrd besteht aus zstd-Teilen, in denen cpio-Archive stecken.
probe=$(mktemp -d)
module=""
if mcopy -n -i "$(p 2)" ::initramfs_2712 "$probe/initrd" 2>/dev/null; then
	for teil in $(python3 -c '
import re, sys
d = open(sys.argv[1], "rb").read()
print(" ".join(str(m.start()) for m in re.finditer(re.escape(b"\x28\xb5\x2f\xfd"), d)))' "$probe/initrd"); do
		tail -c +$((teil + 1)) "$probe/initrd" | zstd -dc 2>/dev/null
	done >"$probe/entpackt"
	module=$(python3 -c '
import re, sys
d = open(sys.argv[1], "rb").read()
namen, i = set(), 0
while True:
    j = d.find(b"070701", i)
    if j < 0:
        break
    try:
        nlen = int(d[j + 94:j + 102], 16)
    except ValueError:
        i = j + 6
        continue
    n = d[j + 110:j + 110 + nlen - 1].decode(errors="replace")
    if re.search(r"\.ko(\.xz|\.zst|\.gz)?$", n):
        namen.add(re.sub(r"^usr/lib/modules/[^/]+/kernel/", "", n))
    i = j + 110 + nlen
print("\n".join(sorted(namen)))' "$probe/entpackt")
fi
rm -rf "$probe"
anzahl=$(grep -c . <<<"$module")
funk=$(grep -cE '^drivers/net/wireless/|^drivers/bluetooth/|^net/bluetooth/' <<<"$module")
noetig=$(for m in drivers/md/dm-verity fs/erofs/erofs; do grep -q "^$m\.ko" <<<"$module" || echo "$m"; done | paste -sd ' ' -)
[[ "$anzahl" -gt 0 && "$funk" == 0 && -z "$noetig" ]]
pruefe $? "initrd ohne Funk-Treiber (WLAN lädt erst im System, mit Firmware): $anzahl Module, $funk für Funk${noetig:+, fehlt: $noetig}"

# Leer heisst: ein lesbares FAT ohne Einträge (eine Fehlermeldung von mdir zählt nicht als leer)
minfo -i "$(p 3)" :: >/dev/null 2>&1 && [[ -z "$(mdir -b -i "$(p 3)" :: 2>/dev/null)" ]]
pruefe $? "Startpartition B ist ein leeres FAT (frei für das erste Update)"

if ((fehler == 0)); then
	echo "Alle Prüfungen bestanden"
else
	echo "$fehler Prüfungen gescheitert"
	exit 1
fi
