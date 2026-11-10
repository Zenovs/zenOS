#!/usr/bin/env bash
# Einheitentest für /usr/lib/zenos/erinnerung: Mitteilung ab 14 Tagen, höchstens eine am Tag, nur mit gestellter Uhr,
# Neustart statt Update, wenn ein Stand wartet; die Zeile für zen status. Läuft in der Bauumgebung; busctl und
# timedatectl sind Attrappen.
#
#   mkosi/test/erinnerung-einheiten.sh          (auf dem Mac: startet sich selbst in der Bauumgebung)
set -uo pipefail

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	hier=$(cd "$(dirname "$0")/.." && pwd)
	exec docker --context "${ZENOS_DOCKER_KONTEXT:-colima-zenos}" run --rm -v "$hier:/zenos/mkosi:ro" \
		-e ZENOS_IM_CONTAINER=1 -e TZ=Europe/Zurich zenos-bau:1 bash /zenos/mkosi/test/erinnerung-einheiten.sh
fi

programm=/zenos/mkosi/mkosi.extra/usr/lib/zenos/erinnerung
fehler=0
tag=86400

pruefe() { # BEDINGUNG-EXIT TEXT
	if [[ "$1" == 0 ]]; then
		printf '  ok      %s\n' "$2"
	else
		printf '  FEHLER  %s\n' "$2"
		fehler=$((fehler + 1))
	fi
}

# Testordner mit Paketstand und Attrappen: busctl schreibt seine Argumente mit (eine Zeile je Argument, «--» danach) und
# antwortet «u 7» (Exit BUSCTL_EXIT), timedatectl antwortet UHR (yes|no)
umgebung() { # PAKETSTAND UHR [BUSCTL_EXIT]
	local w
	w=$(mktemp -d)
	mkdir -p "$w/usr/lib/zenos" "$w/bin" "$w/zustand" "$w/laufzeit"
	printf '%s\n' "$1" >"$w/usr/lib/zenos/paketstand"
	cat >"$w/bin/busctl" <<EOF
#!/bin/bash
printf '%s\n' "\$@" -- >>"$w/busctl.log"
echo 'u 7'
exit ${3:-0}
EOF
	printf '#!/bin/bash\necho %s\n' "$2" >"$w/bin/timedatectl"
	chmod +x "$w/bin/busctl" "$w/bin/timedatectl"
	printf '%s' "$w"
}

lauf() { # W JETZT(leer: Uhr der Attrappe) [ARGUMENT …]
	local w=$1 jetzt=$2
	shift 2
	local umgebung=(PATH="$w/bin:$PATH" ZENOS_ERINNERUNG_TESTWURZEL="$w" XDG_STATE_HOME="$w/zustand"
		XDG_RUNTIME_DIR="$w/laufzeit")
	[[ -z "$jetzt" ]] || umgebung+=(ZENOS_ERINNERUNG_JETZT="$jetzt")
	env "${umgebung[@]}" bash "$programm" "$@"
}

# Anzahl Aufrufe von busctl (ohne Protokoll: keiner)
aufrufe() {
	if [[ -f "$1/busctl.log" ]]; then grep -cx -- '--' "$1/busctl.log"; else echo 0; fi
}

stand=2026-11-08T00:00:00Z
s=$(date -u -d "$stand" +%s)

echo "--- Erinnerung ab 14 Tagen"
w=$(umgebung "$stand" yes)
lauf "$w" $((s + 13 * tag + 23 * 3600)) 2>/dev/null
pruefe $? "13 Tage alt: Exit 0"
[[ "$(aufrufe "$w")" == 0 ]]
pruefe $? "13 Tage alt: keine Mitteilung"
lauf "$w" $((s + 14 * tag)) 2>"$w/fehler"
pruefe $? "14 Tage alt: Exit 0"
[[ "$(aufrufe "$w")" == 1 ]]
pruefe $? "14 Tage alt: eine Mitteilung"
grep -qx 'Zeit für ein Update' "$w/busctl.log" && grep -q '14 Tage alt (Stand 08.11.2026)' "$w/busctl.log" &&
	grep -q 'zen update' "$w/busctl.log"
pruefe $? "Text nennt Alter, Stand und zen update"
# Argumente: --user call DIENST PFAD SCHNITTSTELLE Notify SIGNATUR app ersetzt symbol titel text aktionen hinweise dauer
mapfile -t argumente <"$w/busctl.log"
[[ "${argumente[0]}" == --user && "${argumente[2]}" == org.freedesktop.Notifications &&
	"${argumente[5]}" == Notify && "${argumente[6]}" == 'susssasa{sv}i' && "${argumente[7]}" == zenOS &&
	"${argumente[8]}" == 0 && "${argumente[12]}" == 0 && "${argumente[13]}" == 0 && "${argumente[14]}" == -1 &&
	"${argumente[15]}" == -- ]]
pruefe $? "Notify an org.freedesktop.Notifications mit der richtigen Signatur (erste ohne Ersatz)"
grep -q 'erinnert: Pakete 14 Tage alt' "$w/fehler"
pruefe $? "Meldung im Journal"
[[ "$(cat "$w/laufzeit/zenos/erinnerung-id")" == 7 ]]
pruefe $? "Nummer der Mitteilung gemerkt"

echo "--- Höchstens eine am Tag"
lauf "$w" $((s + 14 * tag + 3 * 3600)) 2>/dev/null
[[ "$(aufrufe "$w")" == 1 ]]
pruefe $? "am selben Tag keine zweite Mitteilung"
lauf "$w" $((s + 15 * tag + 3600)) 2>/dev/null
[[ "$(aufrufe "$w")" == 2 ]]
pruefe $? "am nächsten Tag wieder"
mapfile -t argumente <"$w/busctl.log"
[[ "${argumente[16 + 8]}" == 7 ]]
pruefe $? "die neue ersetzt die alte Mitteilung (Nummer 7)"
grep -q '15 Tage alt' "$w/busctl.log"
pruefe $? "Alter zählt weiter (15 Tage)"

echo "--- Wartender Neustart"
w=$(umgebung "$stand" yes)
mkdir -p "$w/run/zenos/update" && : >"$w/run/zenos/update/neustart"
lauf "$w" $((s + 20 * tag)) 2>/dev/null
grep -qx 'Neuer Stand wartet auf den Neustart' "$w/busctl.log" && grep -q 'zen neustart' "$w/busctl.log" &&
	! grep -q 'zen update' "$w/busctl.log"
pruefe $? "wartet ein Stand, erinnert sie an den Neustart"

echo "--- Uhr"
w=$(umgebung "$stand" no)
lauf "$w" "" 2>"$w/fehler"
pruefe $? "Uhr nicht über NTS gestellt: Exit 0"
[[ "$(aufrufe "$w")" == 0 ]] && grep -q 'nicht über NTS gestellt' "$w/fehler"
pruefe $? "Uhr nicht über NTS gestellt: keine Mitteilung"
w=$(umgebung 2020-01-01T00:00:00Z yes)
lauf "$w" "" 2>/dev/null
[[ "$(aufrufe "$w")" == 1 ]]
pruefe $? "gestellte Uhr (timedatectl): Mitteilung bei alten Paketen"
w=$(umgebung "$stand" yes)
lauf "$w" "1234x" 2>/dev/null
[[ "$(aufrufe "$w")" == 0 ]]
pruefe $? "unlesbare Testzeit: keine Mitteilung"

echo "--- Fehlerfälle"
w=$(umgebung kaputt yes)
lauf "$w" $((s + 30 * tag)) 2>/dev/null
pruefe $? "unlesbarer Paketstand: Exit 0"
[[ "$(aufrufe "$w")" == 0 ]]
pruefe $? "unlesbarer Paketstand: keine Mitteilung"
w=$(umgebung "$stand" yes 1)
lauf "$w" $((s + 30 * tag)) 2>/dev/null
[[ $? == 1 ]]
pruefe $? "Oberfläche nicht erreichbar: Exit 1"
[[ ! -e "$w/zustand/zenos/erinnerung" ]]
pruefe $? "Oberfläche nicht erreichbar: nicht als erinnert vermerkt (nächste Stunde nochmals)"
lauf "$w" $((s + 30 * tag)) etwas 2>/dev/null
[[ $? == 64 ]]
pruefe $? "unbekannter Aufruf: Exit 64"

echo "--- Zeile für zen status"
w=$(umgebung "$stand" yes)
[[ "$(lauf "$w" $((s + 3 * tag)) stand)" == "Pakete vom 08.11.2026 (3 Tage alt)" ]]
pruefe $? "stand: «Pakete vom 08.11.2026 (3 Tage alt)»"
[[ "$(lauf "$w" $((s + tag)) stand)" == "Pakete vom 08.11.2026 (1 Tag alt)" ]]
pruefe $? "stand: «1 Tag alt»"
w=$(umgebung "$stand" no)
[[ "$(lauf "$w" "" stand)" == "Pakete vom 08.11.2026 (Uhr noch nicht über NTS gestellt)" ]]
pruefe $? "stand ohne gestellte Uhr: nur das Datum"
[[ "$(aufrufe "$w")" == 0 ]]
pruefe $? "stand schickt nie eine Mitteilung"
w=$(umgebung kaputt yes)
[[ -z "$(lauf "$w" "" stand)" ]]
pruefe $? "stand ohne Paketstand: keine Zeile"

if ((fehler == 0)); then
	echo "Alle Prüfungen bestanden"
else
	echo "$fehler Prüfungen gescheitert"
	exit 1
fi
