#!/usr/bin/env bash
# Einheitentest für das Notfall-Passwort (BAUAUFTRAG.md, Bauauftrag 2): /usr/lib/zenos/notfall-gemeinsam (Prüfen der
# Anfragen von zen notfall, Wiederherstellungsschlüssel, Container anlegen und lesen, nullen) und die Passwortabfrage
# beim Start (/usr/lib/zenos/entsperren) mit allen Fällen: falsches Passwort, echtes Passwort, Wiederherstellungsschlüssel
# in jeder Schreibweise, Notfall-Passwort (Schlüssel gelöscht, Notfall-Partition genullt, Attrappe im Arbeitsspeicher)
# und danach jedes Passwort «stimmt nicht».
#
# Läuft in der Bauumgebung mit echtem cryptsetup auf Loop-Geräten (privilegierter Container). systemd-ask-password ist
# eine Attrappe, die vorbereitete Eingaben liefert. Die Passwörter hier gelten nur für diese Wegwerf-Dateien.
#
#   mkosi/test/notfall-einheiten.sh          (auf dem Mac: startet sich selbst in der Bauumgebung)
#
# «pruefe $?» nach einer Bedingung ist hier gewollt: Der Exit-Code der Bedingung ist das Ergebnis.
# shellcheck disable=SC2319
set -uo pipefail

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	hier=$(cd "$(dirname "$0")/.." && pwd)
	kontext=${ZENOS_DOCKER_KONTEXT:-colima-zenos}
	docker --context "$kontext" build -q -t zenos-bau:1 "$hier/umgebung" >/dev/null
	exec docker --context "$kontext" run --rm --privileged -v "$hier:/zenos/mkosi:ro" \
		-v "$hier/mkosi.extra/usr/lib/zenos:/usr/lib/zenos:ro" \
		-e ZENOS_IM_CONTAINER=1 zenos-bau:1 bash /zenos/mkosi/test/notfall-einheiten.sh
fi

fehler=0
pruefe() { # BEDINGUNG-EXIT TEXT
	if [[ "$1" == 0 ]]; then
		printf '  ok      %s\n' "$2"
	else
		printf '  FEHLER  %s\n' "$2"
		fehler=$((fehler + 1))
	fi
}

ECHT=echtes-passwort-nur-fuer-den-test
NOTFALL=notfall-passwort-nur-fuer-den-test
KONTO=pruefer
# Ein Wiederherstellungsschlüssel in der Form von systemd-cryptenroll (8 × 8 Zeichen modhex)
WIEDER=cbdefghi-jklnrtuv-cbdefghi-jklnrtuv-vutrnlkj-ihgfedbc-vutrnlkj-ihgfedbc

arbeit=$(mktemp -d)
attrappen=$arbeit/bin
mkdir -p "$attrappen"
# systemd-ask-password: liefert Zeile für Zeile aus $ANTWORTEN, danach Exit 1 (wie eine abgebrochene Frage)
cat >"$attrappen/systemd-ask-password" <<'EOF'
#!/bin/bash
n=$(cat "$ANTWORTEN.n" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$ANTWORTEN.n"
zeile=$(sed -n "${n}p" "$ANTWORTEN")
[[ -n "$zeile" ]] || { sleep 0.2; exit 1; }
printf '%s\n' "$zeile"
EOF
printf '#!/bin/sh\nexit 0\n' >"$attrappen/udevadm"
chmod +x "$attrappen"/*
export PATH="$attrappen:$PATH"
# Wie KeyringMode=shared der Dienste: Docker gibt dem Container einen eigenen Sitzungs-Schlüsselbund ohne den von root
keyctl link @u @s >/dev/null

aufraeumen() {
	cryptsetup close daten >/dev/null 2>&1
	cryptsetup close zenos-notfall-neu >/dev/null 2>&1
	cryptsetup close zenos-notfall-lesen >/dev/null 2>&1
	umount /run/zenos-speicher >/dev/null 2>&1
	for l in $(losetup -j "$arbeit/daten.img" -O NAME -n) $(losetup -j "$arbeit/notfall.img" -O NAME -n) \
		$(losetup -j /run/zenos-speicher/daten -O NAME -n 2>/dev/null); do
		losetup -d "$l" >/dev/null 2>&1
	done
	keyctl purge user zenos-attrappe >/dev/null 2>&1
	rm -rf "$arbeit"
}
trap aufraeumen EXIT

# Datenpartition (LUKS2 mit Passwort und Wiederherstellungsschlüssel) und Notfall-Partition (32 MB Nullen)
truncate -s 64M "$arbeit/daten.img"
truncate -s 32M "$arbeit/notfall.img"
daten_geraet=$(losetup --find --show "$arbeit/daten.img")
notfall_geraet=$(losetup --find --show "$arbeit/notfall.img")
printf '%s' "$ECHT" | cryptsetup luksFormat --batch-mode --type luks2 --pbkdf argon2id --key-file=- "$daten_geraet"
cryptsetup luksAddKey --batch-mode --key-file=<(printf '%s' "$ECHT") "$daten_geraet" <(printf '%s' "$WIEDER") ||
	{ echo "Wiederherstellungsschlüssel liess sich nicht eintragen" >&2; exit 1; }
export ZENOS_TEST_DATEN=$daten_geraet ZENOS_TEST_NOTFALL=$notfall_geraet
# shellcheck source=../mkosi.extra/usr/lib/zenos/notfall-gemeinsam
. /usr/lib/zenos/notfall-gemeinsam

echo "--- Namen, Wiederherstellungsschlüssel, Anfragen"
name_gueltig pruefer && name_gueltig _a-1 && ! name_gueltig "" && ! name_gueltig 1abc && ! name_gueltig 'a b' &&
	! name_gueltig 'a"b' && ! name_gueltig "$(printf 'a%.0s' {1..33})"
pruefe $? "Kontonamen: nur der sichere Kern dessen, was homed annimmt"
[[ "$(als_wiederherstellungsschluessel "${WIEDER^^}")" == "$WIEDER" &&
	"$(als_wiederherstellungsschluessel "${WIEDER//-/}")" == "$WIEDER" &&
	"$(als_wiederherstellungsschluessel "${WIEDER//-/ }")" == "$WIEDER" ]]
pruefe $? "Wiederherstellungsschlüssel gross, ohne oder mit Leerzeichen statt Bindestrichen wird normalisiert"
! als_wiederherstellungsschluessel "$ECHT" >/dev/null && ! als_wiederherstellungsschluessel "${WIEDER:0:60}" >/dev/null
pruefe $? "ein Passwort gilt nicht als Wiederherstellungsschlüssel"
[[ "$(hex_zu_text 4142c3a4)" == "ABä" ]] && ! hex_zu_text 4142C3 >/dev/null && ! hex_zu_text 414 >/dev/null &&
	! hex_zu_text 410042 >/dev/null && ! hex_zu_text 00 >/dev/null && ! hex_zu_text "$(printf '41%.0s' {1..257})" >/dev/null
pruefe $? "Hex: klein, gerade Länge, keine Nullbytes, höchstens 256 Bytes"
[[ "$(hex_zu_text 3030)" == "00" && "$(hex_zu_text 2522275c)" == "%\"'\\" ]]
pruefe $? "Hex: Ziffern und Sonderzeichen kommen genau an"
h() { printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'; }
anfrage_lesen '{"method":"io.zenos.Notfall.Status","parameters":{}}' && [[ "$methode" == Status ]]
pruefe $? "Anfrage Status"
anfrage_lesen "{\"method\":\"io.zenos.Notfall.Setzen\",\"parameters\":{\"daten\":\"$(h "$ECHT")\",\"neu\":\"$(h "$NOTFALL")\"}}" &&
	[[ "$methode" == Setzen && "$daten" == "$ECHT" && "$neu" == "$NOTFALL" ]]
pruefe $? "Anfrage Setzen: beide Passwörter genau"
anfrage_lesen "{\"method\":\"io.zenos.Notfall.Entfernen\",\"parameters\":{\"daten\":\"$(h "$ECHT")\"}}" &&
	[[ "$methode" == Entfernen && "$daten" == "$ECHT" ]]
pruefe $? "Anfrage Entfernen"
ungueltig=0
for a in '{"method":"io.zenos.Notfall.Status","parameters":{"x":"1"}}' \
	'{"method":"io.zenos.Notfall.Loeschen","parameters":{}}' \
	'{"method":"io.zenos.Notfall.Status","parameters":{}} ' \
	'{"parameters":{},"method":"io.zenos.Notfall.Status"}' \
	'{"method":"io.zenos.Notfall.Entfernen","parameters":{"daten":"41","neu":"42"}}' \
	'{"method":"io.zenos.Notfall.Setzen","parameters":{"neu":"42","daten":"41"}}' \
	'{"method":"io.zenos.Notfall.Setzen","parameters":{"daten":"41"}}' \
	'{"method":"io.zenos.Notfall.Entfernen","parameters":{"daten":"4A"}}' \
	'{"method":"io.zenos.Notfall.Entfernen","parameters":{"daten":"4100"}}' \
	'{"method":"io.zenos.Notfall.Entfernen","parameters":{"daten":"41\"}}'; do
	if anfrage_lesen "$a"; then ungueltig=1; echo "    angenommen: $a"; fi
done
pruefe $ungueltig "ungültige Anfragen werden abgelehnt (fremde Felder, Reihenfolge, Methode, Hex, Nullbyte)"
unset daten neu

echo "--- Container"
! notfall_gesetzt
pruefe $? "Nullen: kein Notfall-Passwort gesetzt"
passwort_oeffnet_daten "$ECHT" && passwort_oeffnet_daten "$WIEDER" && ! passwort_oeffnet_daten "$NOTFALL"
pruefe $? "Passwort und Wiederherstellungsschlüssel öffnen die Daten, das Notfall-Passwort nicht"
notfall_anlegen "$NOTFALL" zenos-notfall-neu && notfall_name_schreiben zenos-notfall-neu "$KONTO"
pruefe $? "Notfall-Container anlegen und den Kontonamen hineinschreiben"
[[ ! -e /dev/mapper/zenos-notfall-neu ]]
pruefe $? "danach ist der Container wieder zu"
notfall_gesetzt && passwort_ist_notfall "$NOTFALL" && ! passwort_ist_notfall "$ECHT"
pruefe $? "das Notfall-Passwort passt, das echte nicht"
[[ "$(cryptsetup luksDump "$notfall_geraet" | awk '/^Keyslots:/{d=1;next} /^[A-Za-z]/{d=0} d && /^  [0-9]+: /{n++} END{print n+0}')" == 1 ]]
pruefe $? "der Container hat genau einen Schlüsselplatz"
[[ "$(notfall_name_lesen "$NOTFALL")" == "$KONTO" ]]
pruefe $? "Kontoname wieder lesbar ($(notfall_name_lesen "$NOTFALL"))"
! notfall_name_lesen "$ECHT" >/dev/null
pruefe $? "mit dem falschen Passwort kein Name"

echo "--- Passwortabfrage beim Start (entsperren)"
starten() { # EINGABE … (eine Zeile pro Frage); Ausgabe von entsperren in $arbeit/ausgabe
	printf '%s\n' "$@" >"$arbeit/antworten"
	rm -f "$arbeit/antworten.n"
	ANTWORTEN=$arbeit/antworten timeout "${ZEIT:-60}" /usr/lib/zenos/entsperren >"$arbeit/ausgabe" 2>&1
}
starten "falsch" "$ECHT"
rc=$?
[[ $rc == 0 && "$(cryptsetup status daten 2>/dev/null | awk '/type:/ {print $2}')" == LUKS2 &&
	"$(grep -c 'stimmt nicht' "$arbeit/ausgabe")" == 1 ]]
pruefe $? "falsches Passwort: «stimmt nicht», dann öffnet das echte die Daten (rc $rc)"
cryptsetup close daten
notfall_gesetzt
pruefe $? "ein falsches Passwort löscht nichts"
for schreibweise in "${WIEDER^^}" "${WIEDER//-/}"; do
	starten "$schreibweise"
	rc=$?
	[[ $rc == 0 && -e /dev/mapper/daten ]]
	pruefe $? "Wiederherstellungsschlüssel öffnet die Daten (${schreibweise:0:12}…)"
	cryptsetup close daten 2>/dev/null
done

starten "$NOTFALL"
rc=$?
[[ $rc == 0 ]]
pruefe $? "Notfall-Passwort: der Start geht weiter (rc $rc)"
[[ "$(daten_schluesselplaetze)" == 0 ]]
pruefe $? "alle Schlüssel der Daten sind gelöscht, auch der Wiederherstellungsschlüssel"
cmp -s -n $((32 * 1048576)) "$notfall_geraet" /dev/zero
pruefe $? "die Notfall-Partition ist ganz genullt"
[[ "$(cryptsetup status daten 2>/dev/null | awk '/type:/ {print $2}')" == PLAIN ]] &&
	[[ "$(blkid -o value -s LABEL /dev/mapper/daten)" == zenos-daten ]] &&
	debugfs -R 'ls -l /' /dev/mapper/daten 2>/dev/null | grep -qw home
pruefe $? "Attrappe: /dev/mapper/daten im Arbeitsspeicher, ext4 «zenos-daten» mit home"
[[ "$(cat /run/zenos/attrappe 2>/dev/null)" == "$KONTO" ]]
pruefe $? "Marker der Attrappe mit dem Kontonamen"
schluessel=$(keyctl search @u user zenos-attrappe 2>/dev/null)
[[ -n "$schluessel" && "$(keyctl pipe "$schluessel" 2>/dev/null)" == "$NOTFALL" ]]
pruefe $? "das Notfall-Passwort liegt für die Attrappe im Schlüsselbund von root"
! grep -q -e "$NOTFALL" -e "$ECHT" "$arbeit/ausgabe"
pruefe $? "kein Passwort in der Ausgabe"
[[ "$(sed 's/ *$//' "$arbeit/ausgabe" | grep -v '^$' | sort -u)" == "  Einen Moment …" ]]
pruefe $? "die Ausgabe sieht beim Notfall-Passwort aus wie beim echten"
keyctl purge user zenos-attrappe >/dev/null 2>&1
cryptsetup close daten
umount /run/zenos-speicher 2>/dev/null
rm -f /run/zenos/attrappe

ZEIT=40 starten "$ECHT" "$NOTFALL" "$WIEDER"
rc=$?
[[ $rc == 124 && ! -e /dev/mapper/daten && "$(grep -c 'stimmt nicht' "$arbeit/ausgabe")" == 3 ]]
pruefe $? "danach stimmt kein Passwort mehr: echtes, Notfall-Passwort, Wiederherstellungsschlüssel (rc $rc)"

echo "--- zen notfall: Aufrufer"
antwort=$(/usr/lib/zenos/notfall-dienst "0-$$-0" </dev/null | tr -d '\0')
[[ "$antwort" == '{"error":"io.zenos.Notfall.Abgelehnt","parameters":{}}' ]]
pruefe $? "root und Aufrufer ohne Sitzung am Gerät werden abgelehnt"
antwort=$(/usr/lib/zenos/notfall-dienst "kaputt" </dev/null | tr -d '\0')
[[ "$antwort" == *Abgelehnt* ]]
pruefe $? "ohne Angaben von systemd abgelehnt"

if ((fehler == 0)); then
	echo "Alle Prüfungen bestanden"
else
	echo "$fehler Prüfungen gescheitert"
	exit 1
fi
