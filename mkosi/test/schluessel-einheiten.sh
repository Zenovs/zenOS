#!/usr/bin/env bash
# Einheitentest für den Hardware-Schlüssel (BAUAUFTRAG.md, Bauauftrag 4): schluessel-gemeinsam (Ableitung der
# Passphrase aus Passwort und Schlüssel, Eintragen, Öffnen, Entfernen), die Passwortabfrage beim Start mit Schlüssel
# (mit, ohne, später eingesteckt, falsches Passwort, Wiederherstellungsschlüssel mit Notweg, Notfall-Passwort ohne
# Schlüssel) und die Anfragen von zen schluessel.
#
# Läuft in der Bauumgebung mit echtem cryptsetup auf Loop-Geräten (privilegierter Container). Die FIDO2-Werkzeuge
# (fido2-token, fido2-cred, fido2-assert, pamu2fcfg) sind Attrappen, die nur deren Ausgabeformat nachbilden
# (schluessel-attrappe.py); ein echter Schlüssel wird am Argon geprüft. Die Passwörter gelten nur für diese Dateien.
#
#   mkosi/test/schluessel-einheiten.sh          (auf dem Mac: startet sich selbst in der Bauumgebung)
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
		-e ZENOS_IM_CONTAINER=1 zenos-bau:1 bash /zenos/mkosi/test/schluessel-einheiten.sh
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

PASSWORT=passwort-nur-fuer-den-test
FALSCH=falsches-passwort-nur-fuer-den-test
NEU=neues-passwort-nur-fuer-den-test
NOTFALL=notfall-passwort-nur-fuer-den-test
WIEDER=cbdefghi-jklnrtuv-cbdefghi-jklnrtuv-vutrnlkj-ihgfedbc-vutrnlkj-ihgfedbc

arbeit=$(mktemp -d)
attrappen=$arbeit/bin
mkdir -p "$attrappen" "$arbeit/zustand"
for befehl in fido2-token fido2-cred fido2-assert pamu2fcfg; do
	ln -s /zenos/mkosi/test/schluessel-attrappe.py "$attrappen/$befehl"
done
# systemd-ask-password: liefert Zeile für Zeile aus $ANTWORTEN, danach Exit 1 (wie eine abgebrochene Frage)
cat >"$attrappen/systemd-ask-password" <<'EOF'
#!/bin/bash
n=$(cat "$ANTWORTEN.n" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$ANTWORTEN.n"
if [[ "$(wc -l <"$ANTWORTEN")" -lt "$n" ]]; then
	sleep 0.2
	exit 1
fi
sed -n "${n}p" "$ANTWORTEN"
EOF
printf '#!/bin/sh\nexit 0\n' >"$attrappen/udevadm"
chmod +x "$attrappen/systemd-ask-password" "$attrappen/udevadm"
export PATH="$attrappen:$PATH" SCHLUESSEL_ZUSTAND=$arbeit/zustand
# Wie KeyringMode=shared der Dienste: Docker gibt dem Container einen eigenen Sitzungs-Schlüsselbund ohne den von root
keyctl link @u @s >/dev/null

stecken() { printf '%s' "$*" >"$SCHLUESSEL_ZUSTAND/steckt"; }
beruehrungen() { if [[ -e "$SCHLUESSEL_ZUSTAND/beruehrt" ]]; then wc -l <"$SCHLUESSEL_ZUSTAND/beruehrt"; else echo 0; fi; }

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

# Datenpartition wie beim ersten Start: Einmal-Schlüssel in Platz 0, Wiederherstellungsschlüssel mit seinem Token
truncate -s 64M "$arbeit/daten.img"
truncate -s 32M "$arbeit/notfall.img"
daten_geraet=$(losetup --find --show "$arbeit/daten.img")
notfall_geraet=$(losetup --find --show "$arbeit/notfall.img")
head -c 64 /dev/urandom >"$arbeit/einmal"
cryptsetup luksFormat --batch-mode --type luks2 --pbkdf argon2id --key-file="$arbeit/einmal" "$daten_geraet"
cryptsetup luksAddKey --batch-mode --key-slot 1 --key-file="$arbeit/einmal" "$daten_geraet" <(printf '%s' "$WIEDER")
printf '{"type":"systemd-recovery","keyslots":[]}' |
	cryptsetup token import --json-file=- --key-slot 1 "$daten_geraet"
export ZENOS_TEST_DATEN=$daten_geraet ZENOS_TEST_NOTFALL=$notfall_geraet
export ZENOS_TEST_OHNE_SCHLUESSEL=$arbeit/gibt-es-nicht
# shellcheck source=../mkosi.extra/usr/lib/zenos/notfall-gemeinsam
. /usr/lib/zenos/notfall-gemeinsam
# shellcheck source=../mkosi.extra/usr/lib/zenos/schluessel-gemeinsam
. /usr/lib/zenos/schluessel-gemeinsam

echo "--- Ableitung"
s1=$(ableitungssalz "$PASSWORT" AAAA) s2=$(ableitungssalz "$PASSWORT" AAAA)
s3=$(ableitungssalz "$FALSCH" AAAA) s4=$(ableitungssalz "$PASSWORT" BBBB)
[[ "$s1" == "$s2" && "$s1" != "$s3" && "$s1" != "$s4" && "$(printf '%s' "$s1" | base64 -d | wc -c)" == 32 ]]
pruefe $? "Salz aus Passwort und Zufallssalz: gleich bei gleicher Eingabe, anders bei anderem Passwort oder Salz, 32 Bytes"
! test_ohne_schluessel
pruefe $? "ohne die Datei des Test-Images ist ein Schlüssel Pflicht"
[[ "$(wiederherstellung_platz)" == 1 ]]
pruefe $? "Platz des Wiederherstellungsschlüssels aus seinem Token"

echo "--- Eintragen"
stecken a
schluessel_eintragen /dev/hidraw-a "$PASSWORT" "$arbeit/einmal" && [[ -n "$schluessel_neues_credential" ]]
pruefe $? "Schlüssel a eintragen"
stecken b
! schluessel_schon_eingetragen /dev/hidraw-b && schluessel_eintragen /dev/hidraw-b "$PASSWORT" "$arbeit/einmal"
pruefe $? "Schlüssel b ist neu und lässt sich eintragen"
stecken a
schluessel_schon_eingetragen /dev/hidraw-a
pruefe $? "Schlüssel a gilt als eingetragen (ohne Berührung erkannt)"
[[ "$(schluessel_plaetze | wc -l)" == 2 ]]
pruefe $? "zwei Plätze mit Token zenos-fido2 ($(schluessel_plaetze | tr '\n' ' '))"
plaetze() { cryptsetup luksDump "$daten_geraet" | grep -cE '^  [0-9]+: luks2'; }
cryptsetup luksKillSlot --batch-mode "$daten_geraet" 0 </dev/null 2>/dev/null
[[ "$(plaetze)" == 3 ]] && ! passwort_oeffnet_daten "$PASSWORT" && passwort_oeffnet_daten "$WIEDER"
pruefe $? "drei Plätze (Wiederherstellung, a, b), keiner mit dem Passwort allein; der Wiederherstellungsschlüssel öffnet"

echo "--- Öffnen mit Passwort und Schlüssel"
stecken a
vorher=$(beruehrungen)
schluessel_oeffnen "$PASSWORT" && platz_a=$schluessel_platz
pruefe $? "Passwort und Schlüssel a öffnen (Platz $schluessel_platz)"
[[ "$(($(beruehrungen) - vorher))" == 1 ]]
pruefe $? "dafür genau eine Berührung"
stecken b
schluessel_oeffnen "$PASSWORT" && [[ "$schluessel_platz" != "$platz_a" ]]
pruefe $? "Passwort und Schlüssel b öffnen seinen eigenen Platz ($schluessel_platz)"
stecken a
! schluessel_oeffnen "$FALSCH"
pruefe $? "falsches Passwort mit Schlüssel öffnet nicht"
stecken
! schluessel_oeffnen "$PASSWORT"
pruefe $? "Passwort ohne Schlüssel öffnet nicht"
stecken c
! schluessel_oeffnen "$PASSWORT"
pruefe $? "Passwort mit einem fremden Schlüssel öffnet nicht"
unset schluessel_passphrase

echo "--- Notfall-Passwort neben den Schlüsseln"
notfall_anlegen "$NOTFALL" zenos-notfall-neu && notfall_name_schreiben zenos-notfall-neu pruefer
pruefe $? "Notfall-Passwort anlegen"

echo "--- Passwortabfrage beim Start (entsperren)"
starten() { # EINGABE … (eine Zeile pro Frage); Ausgabe von entsperren in $arbeit/ausgabe
	printf '%s\n' "$@" >"$arbeit/antworten"
	rm -f "$arbeit/antworten.n"
	ANTWORTEN=$arbeit/antworten timeout "${ZEIT:-90}" /usr/lib/zenos/entsperren >"$arbeit/ausgabe" 2>&1
}
offen_luks() { [[ "$(cryptsetup status daten 2>/dev/null | awk '/type:/ {print $2}')" == LUKS2 ]]; }

stecken a
starten "$PASSWORT"
rc=$?
offen_luks && [[ $rc == 0 ]] && grep -q "Schlüssel berühren" "$arbeit/ausgabe"
pruefe $? "Passwort und Schlüssel öffnen die Daten beim Start (rc $rc)"
cryptsetup close daten 2>/dev/null
stecken b
starten "$FALSCH" "$PASSWORT"
rc=$?
offen_luks && [[ $rc == 0 && "$(grep -c 'stimmt nicht' "$arbeit/ausgabe")" == 1 ]]
pruefe $? "falsches Passwort: «stimmt nicht», dann öffnet das richtige mit Schlüssel b"
cryptsetup close daten 2>/dev/null
notfall_gesetzt
pruefe $? "ein falsches Passwort löscht nichts"
stecken
(sleep 4 && stecken a) &
starten "$PASSWORT"
rc=$?
wait
offen_luks && [[ $rc == 0 ]] && grep -q "Schlüssel einstecken" "$arbeit/ausgabe"
pruefe $? "ohne Schlüssel: «Schlüssel einstecken», dann öffnet der eingesteckte"
cryptsetup close daten 2>/dev/null
stecken
starten "${WIEDER^^}" ""
rc=$?
offen_luks && [[ $rc == 0 ]] && grep -q "Mit dem Wiederherstellungsschlüssel" "$arbeit/ausgabe"
pruefe $? "Wiederherstellungsschlüssel öffnet ohne Schlüssel; Notweg abgelehnt (Enter)"
cryptsetup close daten 2>/dev/null
[[ "$(schluessel_plaetze | wc -l)" == 2 ]]
pruefe $? "ohne Notweg bleiben die Schlüsselplätze"

stecken c
rm -f /run/zenos/schluessel-konto
starten "$WIEDER" "ja" "$NOTFALL" "$NOTFALL" "$NEU" "$NEU" ""
rc=$?
offen_luks && [[ $rc == 0 && "$(schluessel_plaetze | wc -l)" == 1 && "$(plaetze)" == 2 && -e /run/zenos/schluessel-konto ]]
pruefe $? "Notweg: neues Passwort und neuer Schlüssel c, die alten Plätze wirklich gelöscht, Anmeldung folgt"
grep -q "Das ist dein Notfall-Passwort" "$arbeit/ausgabe" && notfall_gesetzt
pruefe $? "Notweg: das Notfall-Passwort als neues Passwort wird abgelehnt, nichts gelöscht"
cryptsetup close daten 2>/dev/null
schluessel_oeffnen "$NEU"
pruefe $? "danach öffnen das neue Passwort und Schlüssel c"
stecken a
! schluessel_oeffnen "$PASSWORT"
pruefe $? "der alte Schlüssel a mit dem alten Passwort öffnet nicht mehr"
unset schluessel_passphrase

echo "--- Entfernen mit belegtem stdin (wie im Dienst hinter dem Socket)"
stecken d
schluessel_eintragen /dev/hidraw-d "$NEU" <(printf '%s' "$WIEDER")
pruefe $? "Schlüssel d eintragen (freigegeben mit dem Wiederherstellungsschlüssel)"
platz_d=$(schluessel_plaetze | tail -n 1 | awk '{ print $2 }')
vorher=$(plaetze)
echo "etwas auf stdin" | schluessel_platz_entfernen "$platz_d"
[[ "$(plaetze)" == "$((vorher - 1))" && "$(schluessel_plaetze | wc -l)" == 1 ]]
pruefe $? "der Platz ist wirklich weg, auch wenn auf stdin etwas steht"

stecken
starten "$NOTFALL"
rc=$?
[[ $rc == 0 && "$(daten_schluesselplaetze)" == 0 ]] && cmp -s -n $((32 * 1048576)) "$notfall_geraet" /dev/zero &&
	[[ "$(cat /run/zenos/attrappe 2>/dev/null)" == pruefer ]]
pruefe $? "Notfall-Passwort ohne eingesteckten Schlüssel: Schlüssel gelöscht, Partition genullt, Attrappe"
cryptsetup close daten 2>/dev/null
umount /run/zenos-speicher 2>/dev/null

echo "--- Attrappe: Berührung eines beliebigen Schlüssels"
stecken z
vorher=$(beruehrungen)
/usr/lib/zenos/schluessel-beruehren
pruefe $? "ein Schlüssel, der nirgends eingetragen ist, genügt nach dem Notfall (Exit 0)"
[[ "$(($(beruehrungen) - vorher))" == 1 ]]
pruefe $? "dafür eine Berührung"
touch "$arbeit/ohne"
stecken
ZENOS_TEST_OHNE_SCHLUESSEL=$arbeit/ohne /usr/lib/zenos/schluessel-beruehren
pruefe $? "im Test-Image ohne Schlüssel gilt es als erfüllt"
rm -f /run/zenos/attrappe /run/zenos/schluessel-konto

echo "--- Anfragen von zen schluessel"
h() { printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'; }
anfrage_lesen '{"method":"io.zenos.Schluessel.Status","parameters":{}}' && [[ "$schnittstelle.$methode" == Schluessel.Status ]]
pruefe $? "Status"
anfrage_lesen "{\"method\":\"io.zenos.Schluessel.Hinzufuegen\",\"parameters\":{\"daten\":\"$(h "$PASSWORT")\"}}" &&
	[[ "$methode" == Hinzufuegen && "$daten" == "$PASSWORT" ]]
pruefe $? "Hinzufuegen mit dem Passwort der Daten"
anfrage_lesen "{\"method\":\"io.zenos.Schluessel.Entfernen\",\"parameters\":{\"daten\":\"$(h "$PASSWORT")\",\"nummer\":\"2\"}}" &&
	[[ "$methode" == Entfernen && "$nummer" == 2 && "$daten" == "$PASSWORT" ]]
pruefe $? "Entfernen mit Nummer"
ungueltig=0
for a in '{"method":"io.zenos.Schluessel.Entfernen","parameters":{"daten":"41","nummer":"0"}}' \
	'{"method":"io.zenos.Schluessel.Entfernen","parameters":{"daten":"41","nummer":"12"}}' \
	'{"method":"io.zenos.Schluessel.Entfernen","parameters":{"daten":"41"}}' \
	'{"method":"io.zenos.Schluessel.Setzen","parameters":{"daten":"41","neu":"42"}}' \
	'{"method":"io.zenos.Notfall.Hinzufuegen","parameters":{"daten":"41"}}' \
	'{"method":"io.zenos.Fremd.Status","parameters":{}}'; do
	if anfrage_lesen "$a"; then ungueltig=1; echo "    angenommen: $a"; fi
done
pruefe $ungueltig "ungültige Anfragen werden abgelehnt (Nummer, fehlende Felder, falsche Schnittstelle)"
unset daten neu

if ((fehler == 0)); then
	echo "Alle Prüfungen bestanden"
else
	echo "$fehler Prüfungen gescheitert"
	exit 1
fi
