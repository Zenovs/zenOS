#!/usr/bin/env bash
# sperre-e2e.sh [schritt …] – Ende-zu-Ende-Test: Wecktaste der Sperre (shell/sperre/Sperre.qml). Ist der Bildschirm
# gesperrt und dunkel, weckt ihn die erste Taste und wird verworfen; hält man sie fest, auch ihre Wiederholungen, bis
# sie losgelassen wird. Läuft im Testcontainer als tester: labwc ohne Bildschirm mit der Oberfläche aus ~/zenOS
# (oberflaeche.sh start), die echte Sperre (ext-session-lock) und PAM (Dienst zenos-sperre, Passwort «tester»).
# Dunkel wird es über scripts/bin/zenos-bildschirm aus (Quittung der Sperre, dann wlopm; so macht es gesperrt auch
# `zen energie aus` per SSH, Super+Shift+L wirkt in der Sperre nicht), Eingaben kommen über wtype, der Bildschirm wird
# mit wlopm abgefragt. Jeder Fehlversuch steht im Journal (pam_unix, «authentication failure»): So zeigt sich, dass
# PAM nur das vollständige Passwort bekommt.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, ~/zenOS auf dem Stand dieses Codes):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-sperre-e2e
#   docker exec zenos-sperre-e2e bash -c 'apt-get update -qq && apt-get install -y -qq wlopm wtype'
#   docker exec zenos-sperre-e2e loginctl enable-linger tester
# Dann: docker exec -u tester -w /home/tester/zenOS zenos-sperre-e2e test/container/sperre-e2e.sh [schritt …]
# Ohne Angabe laufen alle (rund 3 Minuten). Exit 0 nur, wenn alles stimmt.
#
#   taste    gesperrt, «tes» getippt, dunkel; «q» weckt und ist verworfen; «ter» und Return entsperren beim ersten
#            Versuch (kein Fehlversuch bei PAM)
#   halten   die Wecktaste gehalten (1,5 s, der Client wiederholt sie nach 600 ms): gesperrt, «tes», dunkel, «q»
#            gehalten, «ter» und Return entsperren beim ersten Versuch. Dann gesperrt, «tes», dunkel, Return gehalten:
#            weiter gesperrt, PAM hat nichts geprüft (kein halbes Passwort); «ter» und Return entsperren.
#   andere   nie eine andere Taste: gesperrt, «tes», dunkel, «q» gehalten und währenddessen «t» gedrückt: «t» kommt
#            an, «er» und Return entsperren beim ersten Versuch
#   modifikator  Shift, Alt, AltGr oder Super während des Haltens: Sie wiederholen sich nicht (xkb) und übernehmen
#            die Wiederholung im Client nicht, die gehaltene Taste wiederholt sich weiter. Gesperrt, «tes», dunkel,
#            Return gehalten und nach 900 ms Shift dazu: weiter gesperrt, PAM hat nichts geprüft; «ter» und Return
#            entsperren. Dann «q» gehalten, nacheinander Alt, AltGr und Super dazu: «ter» und Return entsperren beim
#            ersten Versuch. (Ctrl wiederholt sich in der Keymap von wtype, anders als in den Belegungen ch und us,
#            und übernimmt dort die Wiederholung: Ihn prüfen nur die Einheitentests.)
#   hell     ohne Wecken wird nichts verworfen: gesperrt und hell, «x» 1,5 s gehalten und Return: PAM lehnt «xx…» ab
#            (genau ein Fehlversuch, die Wiederholungen kamen an); «tester» und Return entsperren
#
# Die Logik im Einzelnen prüfen die Einheitentests (test/einheiten/energie.test.mjs, «Sperre: gehaltene Wecktaste»).

set -uo pipefail

SELBST=$(readlink -f -- "${BASH_SOURCE[0]}")
REPO=$(cd -- "$(dirname -- "$SELBST")/../.." && pwd -P)
O=$REPO/test/container/oberflaeche.sh
ZUSTAND=/srv/oberflaeche
XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_RUNTIME_DIR

BEFUND=0
# Beginn des laufenden Schritts (Unix-Sekunden, für das Journal)
BEGINN=0

meldung() { printf 'sperre-e2e: %s\n' "$*" >&2; }
gut() { printf '  ✓ %s\n' "$*"; }
schlecht() { printf '  ✗ %s\n' "$*"; BEFUND=1; }
# pruefe GUT SCHLECHT BEFEHL…: ✓ GUT, wenn BEFEHL gelingt, sonst ✗ SCHLECHT
pruefe() {
  local ja=$1 nein=$2
  shift 2
  if "$@"; then gut "$ja"; else schlecht "$nein"; fi
}

anzeige() { cat "$ZUSTAND/wayland" 2> /dev/null; }

# «an», «aus» oder «?» (wlopm --json)
bildschirm() {
  WAYLAND_DISPLAY=$(anzeige) wlopm --json 2> /dev/null | python3 -c '
import json, sys
try:
    modi = {e.get("power-mode") for e in json.load(sys.stdin)}
except (ValueError, AttributeError, TypeError):
    modi = set()
print("an" if modi == {"on"} else "aus" if modi == {"off"} else "?")'
}

# Wartet höchstens SEKUNDEN, bis der Bildschirm ZIEL ist. 0, wenn ja.
warte_bildschirm() { # ZIEL SEKUNDEN
  local ende=$((SECONDS + $2))
  while (( SECONDS < ende )); do
    [[ "$(bildschirm)" == "$1" ]] && return 0
    sleep 0.25
  done
  [[ "$(bildschirm)" == "$1" ]]
}

# «gesperrt» oder «offen», wie die Sperre selbst es sieht (labwc hat die Sperre bestätigt). Die Antwort ist die letzte
# Zeile (Qt warnt davor womöglich über die Locale).
sperre() { "$O" ipc sperre status 2> /dev/null | tail -n 1 | tr -d '[:space:]'; }
ist_sperre() { [[ "$(sperre)" == "$1" ]]; }

# Wartet höchstens SEKUNDEN, bis die Sperre ZIEL meldet. 0, wenn ja.
warte_sperre() { # ZIEL SEKUNDEN
  local ende=$((SECONDS + $2))
  while (( SECONDS < ende )); do
    ist_sperre "$1" && return 0
    sleep 0.25
  done
  ist_sperre "$1"
}

# Fehlversuche bei PAM seit dem Beginn des Schritts (pam_unix schreibt je Fehlversuch eine Zeile)
fehlversuche() {
  journalctl --since "@$BEGINN" --no-pager -o cat 2> /dev/null |
    grep -c 'pam_unix(zenos-sperre:auth): authentication failure'
}
keine_fehlversuche() { [[ "$(fehlversuche)" == 0 ]]; }
ein_fehlversuch() { [[ "$(fehlversuche)" == 1 ]]; }
gesperrt_ohne_fehlversuch() { ist_sperre gesperrt && keine_fehlversuche; }

tippe() { "$O" tippe "$1"; }
taste() { "$O" taste "$@"; }
# Hält TASTE MS Millisekunden gedrückt (wtype drückt und lässt los; wiederholt wird sie im Client, wie bei einer
# echten Tastatur unter Wayland)
halte() { # TASTE MS
  WAYLAND_DISPLAY=$(anzeige) wtype -P "$1" -s "$2" -p "$1"
}

oberflaeche_starten() {
  "$O" stopp > /dev/null 2>&1 || true
  rm -f -- "$XDG_RUNTIME_DIR/zenos/gesperrt"
  "$O" start > /dev/null || return 1
  # Der erste virtuelle Tastendruck nach dem Start von labwc geht verloren (oberflaeche.sh): jetzt, harmlos
  taste Shift_L
}

oberflaeche_stoppen() {
  "$O" stopp > /dev/null 2>&1 || true
  rm -f -- "$XDG_RUNTIME_DIR/zenos/gesperrt"
}

# Sperrt (wie Super+L über IPC), Beginn des Schritts fürs Journal
sperren() {
  BEGINN=$(date +%s)
  sleep 1
  "$O" ipc sperre sperren > /dev/null || return 1
  warte_sperre gesperrt 10 || return 1
  # Die Sperrfläche hat den Fokus (Component.onCompleted), dann erst tippen
  sleep 1
}

# Dunkel wie gesperrt mit `zen energie aus`: zenos-bildschirm fragt die Sperre («sperre bildschirm aus»), dann
# wlopm --off. Was im Feld steht, bleibt (die Sperre besteht schon, sperren ändert nichts).
dunkel() {
  WAYLAND_DISPLAY=$(anzeige) "$REPO/scripts/bin/zenos-bildschirm" aus > /dev/null 2>&1 || return 1
  warte_bildschirm aus 10 || return 1
  # Die Sperre hat «aus» quittiert: Die Wecktaste steht aus. Nach 1 s Ruhe ist auch der Wecker der Sperre scharf.
  sleep 1.5
}

# Gesperrt, «tes» im Feld, dunkel
vorbereiten() {
  sperren || { schlecht "Sperre greift nicht ($(sperre))"; return 1; }
  tippe tes
  dunkel || { schlecht "nicht dunkel ($(bildschirm))"; return 1; }
  gut "gesperrt, «tes» im Feld, dunkel"
}

# Return und warten, bis entsperrt ist; prüft, dass PAM keinen Fehlversuch sah
entsperrt_beim_ersten() { # TEXT
  taste Return
  if warte_sperre offen 10; then
    if keine_fehlversuche; then
      gut "$1 entsperrt beim ersten Versuch (PAM bekam genau «tester», kein Fehlversuch)"
    else
      schlecht "$1 entsperrt, aber PAM sah $(fehlversuche) Fehlversuch(e)"
    fi
  else
    schlecht "$1 entsperrt nicht ($(sperre), Fehlversuche: $(fehlversuche))"
  fi
}

schritt_taste() {
  echo "Schritt taste: die erste Taste weckt nur, die übrigen landen im Feld"
  vorbereiten || return
  tippe q
  pruefe "«q» weckt" "«q» weckt nicht" warte_bildschirm an 5
  pruefe "weiter gesperrt" "nicht mehr gesperrt" ist_sperre gesperrt
  tippe ter
  entsperrt_beim_ersten "«ter» und Return:"
}

schritt_halten() {
  echo "Schritt halten: die gehaltene Wecktaste wiederholt sich nicht ins Feld"
  vorbereiten || return
  halte q 1500
  pruefe "«q» (1,5 s gehalten) weckt" "«q» weckt nicht" warte_bildschirm an 5
  sleep 1
  pruefe "weiter gesperrt, PAM hat nichts geprüft" "gesperrt: $(sperre), Fehlversuche: $(fehlversuche)" \
    gesperrt_ohne_fehlversuch
  tippe ter
  entsperrt_beim_ersten "«ter» und Return:"

  vorbereiten || return
  halte Return 1500
  pruefe "Return (1,5 s gehalten) weckt" "Return weckt nicht" warte_bildschirm an 5
  # pam_unix antwortet auf ein falsches Passwort erst nach rund 2 s: abwarten, was ein halbes Passwort ergäbe
  sleep 3
  pruefe "weiter gesperrt" "gehaltenes Return hat entsperrt" ist_sperre gesperrt
  pruefe "PAM hat nichts geprüft (kein halbes Passwort)" "PAM sah $(fehlversuche) Fehlversuch(e): das halbe Passwort" \
    keine_fehlversuche
  tippe ter
  entsperrt_beim_ersten "danach «ter» und Return:"
}

schritt_andere() {
  echo "Schritt andere: eine andere Taste während des Haltens kommt an"
  vorbereiten || return
  # «q» gedrückt, nach 800 ms (schon wiederholt) «t» gedrückt und losgelassen, nach weiteren 700 ms «q» los
  WAYLAND_DISPLAY=$(anzeige) wtype -P q -s 800 -k t -s 700 -p q
  pruefe "«q» weckt" "«q» weckt nicht" warte_bildschirm an 5
  sleep 0.5
  tippe er
  entsperrt_beim_ersten "«t» kam an, «er» und Return:"
}

schritt_modifikator() {
  echo "Schritt modifikator: Shift, Alt, AltGr oder Super während des Haltens beenden das Verwerfen nicht"
  vorbereiten || return
  # Return gedrückt, nach 900 ms (schon wiederholt) Shift dazu, 600 ms später Shift los, Return 100 ms danach
  WAYLAND_DISPLAY=$(anzeige) wtype -P Return -s 900 -P Shift_L -s 600 -p Shift_L -s 100 -p Return
  pruefe "Return (mit Shift dazu gehalten) weckt" "Return weckt nicht" warte_bildschirm an 5
  # pam_unix antwortet auf ein falsches Passwort erst nach rund 2 s: abwarten, was ein halbes Passwort ergäbe
  sleep 3
  pruefe "weiter gesperrt" "gehaltenes Return hat entsperrt" ist_sperre gesperrt
  pruefe "PAM hat nichts geprüft (kein halbes Passwort nach dem Shift)" \
    "PAM sah $(fehlversuche) Fehlversuch(e): Return wiederholte sich nach dem Shift ins Feld" keine_fehlversuche
  tippe ter
  entsperrt_beim_ersten "danach «ter» und Return:"

  vorbereiten || return
  # «q» gedrückt, nach 900 ms nacheinander Alt, AltGr und Super je 300 ms, dazwischen 200 ms nur «q»
  WAYLAND_DISPLAY=$(anzeige) wtype -P q -s 900 -P Alt_L -s 300 -p Alt_L -s 200 \
    -P ISO_Level3_Shift -s 300 -p ISO_Level3_Shift -s 200 -P Super_L -s 300 -p Super_L -s 200 -p q
  pruefe "«q» (mit Alt, AltGr und Super dazu gehalten) weckt" "«q» weckt nicht" warte_bildschirm an 5
  sleep 1
  pruefe "weiter gesperrt, PAM hat nichts geprüft" "gesperrt: $(sperre), Fehlversuche: $(fehlversuche)" \
    gesperrt_ohne_fehlversuch
  tippe ter
  entsperrt_beim_ersten "keine Wiederholung von «q» im Feld, «ter» und Return:"
}

schritt_hell() {
  echo "Schritt hell: ohne Wecken wird nichts verworfen"
  sperren || { schlecht "Sperre greift nicht ($(sperre))"; return; }
  pruefe "gesperrt und hell" "nicht hell ($(bildschirm))" warte_bildschirm an 3
  # «x» gehalten, dann Return: Kamen die Wiederholungen an, prüft PAM «xxx…» und lehnt ab (ein Fehlversuch)
  halte x 1500
  taste Return
  sleep 3
  pruefe "die Wiederholungen von «x» kamen an (PAM lehnte «xx…» ab)" "PAM sah $(fehlversuche) Fehlversuche statt 1" \
    ein_fehlversuch
  pruefe "weiter gesperrt" "nicht mehr gesperrt" ist_sperre gesperrt
  BEGINN=$(date +%s)
  sleep 1
  tippe tester
  entsperrt_beim_ersten "«tester» und Return:"
}

if (( EUID == 0 )); then
  meldung "als tester starten, nicht als root"
  exit 2
fi
for programm in wlopm wtype python3 labwc quickshell journalctl; do
  command -v "$programm" > /dev/null || { meldung "$programm fehlt (siehe Kopf der Datei)"; exit 2; }
done
[[ -d "$XDG_RUNTIME_DIR" ]] || { meldung "$XDG_RUNTIME_DIR fehlt (loginctl enable-linger tester)"; exit 2; }

schritte=("$@")
(( ${#schritte[@]} > 0 )) || schritte=(taste halten andere modifikator hell)
for s in "${schritte[@]}"; do
  case "$s" in
    taste | halten | andere | modifikator | hell) ;;
    *) meldung "unbekannter Schritt «$s» (taste, halten, andere, modifikator, hell)"; exit 2 ;;
  esac
done
trap oberflaeche_stoppen EXIT
oberflaeche_starten || { meldung "Oberfläche startet nicht"; exit 1; }
# Sieht dieser Benutzer, was seine Prozesse ins Syslog schreiben (pam_unix in Quickshell)? Sonst wäre «kein
# Fehlversuch» nichts wert. Ob pam_unix Fehlversuche wirklich meldet, zeigt der Schritt «hell».
BEGINN=$(date +%s)
probe="sperre-e2e Probe $$-$RANDOM"
logger -p authpriv.notice -t sperre-e2e -- "$probe"
sleep 1
if ! journalctl --since "@$BEGINN" --no-pager -o cat 2> /dev/null | grep -qF -- "$probe"; then
  meldung "das Journal zeigt diesem Benutzer seine eigenen Syslog-Zeilen nicht"
  exit 2
fi
for s in "${schritte[@]}"; do
  "schritt_$s"
done
oberflaeche_stoppen
if (( BEFUND )); then echo "Befunde, siehe oben."; exit 1; fi
echo "Alles wie erwartet."
