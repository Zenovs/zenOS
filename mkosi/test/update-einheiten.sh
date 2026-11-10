#!/usr/bin/env bash
# Einheitentest für /usr/lib/zenos/update: Probestart vorbereiten, festschreiben (autoboot.txt), gescheiterte
# Probestarts. Läuft in der Bauumgebung ohne Gerät: ZENOS_UPDATE_TESTWURZEL legt alle Orte des Programms (Gerätebaum
# des Bootloaders, Partitionen, autoboot.txt, Marker) in einen Testordner.
#
#   mkosi/test/update-einheiten.sh          (auf dem Mac: startet sich selbst in der Bauumgebung)
set -uo pipefail

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	hier=$(cd "$(dirname "$0")/.." && pwd)
	exec docker --context "${ZENOS_DOCKER_KONTEXT:-colima-zenos}" run --rm -v "$hier:/zenos/mkosi:ro" \
		-e ZENOS_IM_CONTAINER=1 zenos-bau:1 bash /zenos/mkosi/test/update-einheiten.sh
fi

programm=/zenos/mkosi/mkosi.extra/usr/lib/zenos/update
fehler=0

pruefe() { # BEDINGUNG-EXIT TEXT
	if [[ "$1" == 0 ]]; then
		printf '  ok      %s\n' "$2"
	else
		printf '  FEHLER  %s\n' "$2"
		fehler=$((fehler + 1))
	fi
}

zahl() { printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' 0 0 0 "$1")"; }

autoboot() { printf '[all]\ntryboot_a_b=1\nboot_partition=%s\n[tryboot]\nboot_partition=%s\n' "$1" "$2"; }

# Gerät nachbilden: läuft VERSION von Startpartition PARTITION, tryboot TRYBOOT, autoboot.txt mit FEST/PROBE
geraet() { # VERSION PARTITION TRYBOOT FEST PROBE
	w=$(mktemp -d)
	mkdir -p "$w/usr/lib" "$w/proc/device-tree/chosen/bootloader" "$w/dev/disk/by-partlabel/zenos-start.inhalt" \
		"$w/run/systemd"
	printf 'ID=debian\nIMAGE_VERSION=%s\n' "$1" >"$w/usr/lib/os-release"
	zahl "$3" >"$w/proc/device-tree/chosen/bootloader/tryboot"
	zahl "$2" >"$w/proc/device-tree/chosen/bootloader/partition"
	autoboot "$4" "$5" >"$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt"
	printf '%s' "$w"
}

partition() { # WURZEL BEZEICHNUNG NUMMER
	printf '%s\n' "$3" >"$1/dev/disk/by-partlabel/$2.nummer"
}

laeuft() { # WURZEL FUNKTION [LOGIN-EXIT]
	(
		export ZENOS_UPDATE_TESTWURZEL=$1 ZENOS_UPDATE_TEST_LOGIN=${3:-0}
		# shellcheck source=/dev/null
		source "$programm"
		sleep() { :; }
		"$2"
	) >/dev/null 2>&1
}

echo "--- Probestart vorbereiten"
w=$(geraet 0.9.1 2 0 2 3)
partition "$w" zenos_0.9.1 5
partition "$w" zenos_0.9.2 7
partition "$w" zenos-start_0.9.1 2
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
(
	export ZENOS_UPDATE_TESTWURZEL=$w
	source "$programm"
	mkdir -p "$laufzeit"
	probe_vorbereiten 0.9.2
) >/dev/null 2>&1
pruefe $? "Probestart für 0.9.2 vorbereitet"
[[ "$(cat "$w/run/systemd/reboot-param" 2>/dev/null)" == "0 tryboot" ]]
pruefe $? "Neustart mit «0 tryboot»"
[[ "$(cat "$w/var/lib/zenos/update/probe" 2>/dev/null)" == "0.9.2 bereit" ]]
pruefe $? "Marker «0.9.2 bereit»"
[[ -e "$w/run/zenos/update/neustart" ]]
pruefe $? "Marker für die Leiste (neustart)"
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 2 3)" ]]
pruefe $? "autoboot.txt bleibt beim Vorbereiten unverändert"

echo "--- Vorbereiten verweigert, wenn autoboot.txt nicht zum laufenden Start passt"
w=$(geraet 0.9.1 2 0 3 2)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
(
	export ZENOS_UPDATE_TESTWURZEL=$w
	source "$programm"
	mkdir -p "$laufzeit"
	probe_vorbereiten 0.9.2
) >/dev/null 2>&1
[[ $? != 0 && ! -e "$w/run/systemd/reboot-param" ]]
pruefe $? "kein Probestart bei unpassender autoboot.txt"

echo "--- Probestart gelingt: festschreiben"
w=$(geraet 0.9.2 3 1 2 3)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
groesse_vorher=$(wc -c <"$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")
laeuft "$w" pruefen
pruefe $? "pruefen meldet Erfolg"
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 3 2)" ]]
pruefe $? "autoboot.txt: 3 fest, 2 zur Probe"
[[ "$(wc -c <"$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$groesse_vorher" ]]
pruefe $? "autoboot.txt behält die Länge (an Ort und Stelle)"
[[ ! -e "$w/var/lib/zenos/update/probe" ]]
pruefe $? "Marker entfernt"
grep -q "ist jetzt fest" "$w/run/zenos/update/hinweis"
pruefe $? "Hinweis «ist jetzt fest»"

echo "--- Probestart, aber der Login läuft nicht: nicht festschreiben"
w=$(geraet 0.9.2 3 1 2 3)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen 1
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 2 3)" ]]
pruefe $? "autoboot.txt unverändert"
[[ "$(cat "$w/var/lib/zenos/update/probe")" == "0.9.2 probiert" ]]
pruefe $? "Marker «probiert»: der nächste normale Start hält den Fehlschlag fest"

echo "--- Probestart von der falschen Partition: nicht festschreiben"
w=$(geraet 0.9.2 2 1 2 3)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 2 3)" ]]
pruefe $? "autoboot.txt unverändert"

echo "--- Normaler Start nach «bereit» (ausgeschaltet statt neu gestartet): noch ein Versuch"
w=$(geraet 0.9.1 2 0 2 3)
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen
[[ "$(cat "$w/var/lib/zenos/update/probe")" == "0.9.2 bereit-2" && "$(cat "$w/run/systemd/reboot-param")" == "0 tryboot" ]]
pruefe $? "Marker «bereit-2», Neustart wieder mit tryboot"

echo "--- Normaler Start nach «bereit-2» oder «probiert»: gescheitert"
for zustand in bereit-2 probiert; do
	w=$(geraet 0.9.1 2 0 2 3)
	mkdir -p "$w/var/lib/zenos/update"
	printf '0.9.2 %s\n' "$zustand" >"$w/var/lib/zenos/update/probe"
	laeuft "$w" pruefen
	[[ "$(cat "$w/var/lib/zenos/update/fehlgeschlagen")" == 0.9.2 && ! -e "$w/var/lib/zenos/update/probe" ]]
	pruefe $? "nach «$zustand»: 0.9.2 gilt als gescheitert und kommt nicht nochmals"
done

echo "--- Ein zweites Festschreiben ändert nichts"
w=$(geraet 0.9.2 3 1 3 2)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 probiert\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 3 2)" ]]
pruefe $? "autoboot.txt bleibt 3 fest, 2 zur Probe"

echo
if ((fehler == 0)); then echo "--- Alle Prüfungen bestanden"; else echo "--- $fehler Befunde"; fi
exit $((fehler > 0))
