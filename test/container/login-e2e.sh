#!/usr/bin/env bash
# login-e2e.sh [schritt …] – Ende-zu-Ende-Test: Bildschirm am Login-Bildschirm (nach 1 Min. ohne Eingabe aus, die
# Eingabe, die weckt, wird verworfen; shell/greeter/Bildschirm.qml). Läuft im Testcontainer als tester: labwc ohne
# Bildschirm mit dem Login (oberflaeche.sh start --greeter, Konfiguration system/greeter/labwc), dazu eine Attrappe
# von greetd (test/container/login/greetd_attrappe.py), die protokolliert, was das Formular weitergibt. Eingaben über
# wtype (Tastatur) und wlrctl (Zeiger), der Bildschirm wird mit wlopm abgefragt.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, ~/zenOS auf dem Stand dieses Codes):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-login-e2e
#   docker exec zenos-login-e2e bash -c 'apt-get update -qq && apt-get install -y -qq wlopm wtype wlrctl'
#   docker exec zenos-login-e2e loginctl enable-linger tester
# Dann: docker exec -u tester -w /home/tester/zenOS zenos-login-e2e test/container/login-e2e.sh [schritt …]
# Ohne Angabe laufen alle (rund 15 Minuten: Jede Minute ohne Eingabe wird abgewartet). Exit 0 nur, wenn alles stimmt.
#
#   minute   nach dem Start an; ein Zeichen im Passwortfeld nach 40 s beginnt die Minute neu (nach 80 s noch an),
#            danach aus, frühestens 55 s nach dieser Eingabe. Die Maus weckt.
#   taste    «tes» getippt, dunkel; «q» weckt und ist verworfen; «ter» und Return: greetd bekommt genau «tester»
#            (was im Feld stand, blieb, die Wecktaste kam nicht dazu). Nach der Anmeldung ist der Bildschirm an.
#   halten   die Wecktaste gehalten (1,5 s, der Client wiederholt sie nach 600 ms): «tes», dunkel, «q» gehalten,
#            «ter» und Return: greetd bekommt genau «tester». Dann «tes», dunkel, Return gehalten: greetd hört nichts
#            (kein halbes Passwort an PAM), «ter» und Return melden mit «tester» an.
#   modifikator  Shift, Alt, AltGr oder Super während des Haltens (sie wiederholen sich nicht und übernehmen die
#            Wiederholung im Client nicht): «tes», dunkel, Return gehalten und nach 900 ms Shift dazu: greetd hört
#            nichts, «ter» und Return melden mit «tester» an. Dann «tes», dunkel, «q» gehalten, nacheinander Alt,
#            AltGr und Super dazu: greetd bekommt genau «tester». (Ctrl wiederholt sich in der Keymap von wtype und
#            übernimmt dort die Wiederholung: Ihn prüfen nur die Einheitentests.)
#   klick    «tester» getippt, Zeiger auf «Anmelden», dunkel: Der erste Klick weckt nur (greetd hört nichts), der
#            zweite meldet an
#   fehler   wlopm (Attrappe vorn im PATH) schaltet ab, meldet aber einen Fehler: Der Login schaltet sofort wieder an
#            und versucht es ohne neue Eingabe nicht nochmals; der Grund steht im Protokoll
#   neustart der echte Start über scripts/bin/zenos-greeter (labwc -S wie unter greetd), wlopm schaltet ab, aber nicht
#            mehr an (Attrappe): Nach der Wecktaste und drei Versuchen beendet sich der Login, labwc endet mit ihm
#            (greetd startet dann beides neu, alle Bildschirme an), ohne Notfall-Login; der Grund steht im Journal
#
# Die Logik im Einzelnen prüfen die Einheitentests (test/einheiten/login-bildschirm.test.mjs).

set -uo pipefail

SELBST=$(readlink -f -- "${BASH_SOURCE[0]}")
REPO=$(cd -- "$(dirname -- "$SELBST")/../.." && pwd -P)
O=$REPO/test/container/oberflaeche.sh
ZUSTAND=/srv/oberflaeche
E2E=$ZUSTAND/login-e2e
XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_RUNTIME_DIR
# Lage von «Anmelden» bei 1440×900 (oberflaeche.sh, Standard), gemessen am Bildschirmfoto
KNOPF_X=856
KNOPF_Y=604

BEFUND=0
ATTRAPPE=""

meldung() { printf 'login-e2e: %s\n' "$*" >&2; }
gut() { printf '  ✓ %s\n' "$*"; }
schlecht() { printf '  ✗ %s\n' "$*"; BEFUND=1; }
# pruefe GUT SCHLECHT BEFEHL…: ✓ GUT, wenn BEFEHL gelingt, sonst ✗ SCHLECHT
pruefe() {
  local ja=$1 nein=$2
  shift 2
  if "$@"; then gut "$ja"; else schlecht "$nein"; fi
}
ist_bildschirm() { [[ "$(bildschirm)" == "$1" ]]; }
keine_anfragen() { [[ -z "$(anfragen)" ]]; }
in_anfragen() { anfragen | grep -qF -- "$1"; }
im_protokoll() { protokoll | grep -qF -- "$1"; }

# «an», «aus» oder «?» (wlopm --json, das echte aus /usr/bin, auch wenn eine Attrappe im PATH steht). Abgefragt wird
# das labwc von oberflaeche.sh, mit ANZEIGE=wayland-N ein anderes.
ANZEIGE=""
bildschirm() {
  local anzeige=$ANZEIGE
  [[ -n "$anzeige" ]] || anzeige=$(cat "$ZUSTAND/wayland" 2> /dev/null) || { echo "?"; return; }
  WAYLAND_DISPLAY=$anzeige /usr/bin/wlopm --json 2> /dev/null | python3 -c '
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
    sleep 0.5
  done
  [[ "$(bildschirm)" == "$1" ]]
}

# Anfragen an greetd (Attrappe), eine JSON-Zeile je Anfrage
anfragen() { cat -- "$E2E/greetd.log" 2> /dev/null || true; }

# Wartet höchstens SEKUNDEN auf eine Antwort an PAM und gibt sie aus
warte_antwort() { # SEKUNDEN
  local ende=$((SECONDS + $1)) antwort
  while (( SECONDS < ende )); do
    antwort=$(anfragen | python3 -c '
import json, sys
for zeile in sys.stdin:
    a = json.loads(zeile)
    if a.get("type") == "post_auth_message_response":
        print(a.get("response", ""))
        break')
    [[ -n "$antwort" ]] && { printf '%s\n' "$antwort"; return 0; }
    sleep 0.5
  done
  return 1
}

zeiger() { WAYLAND_DISPLAY=$(cat "$ZUSTAND/wayland") wlrctl pointer "$@"; }

# Hält TASTE MS Millisekunden gedrückt (wtype drückt und lässt los; wiederholt wird sie im Client, wie bei einer
# echten Tastatur unter Wayland)
halte() { # TASTE MS
  WAYLAND_DISPLAY=$(cat "$ZUSTAND/wayland") wtype -P "$1" -s "$2" -p "$1"
}

login_stoppen() {
  "$O" stopp > /dev/null 2>&1 || true
  if [[ -n "$ATTRAPPE" ]]; then
    kill "$ATTRAPPE" 2> /dev/null || true
    wait "$ATTRAPPE" 2> /dev/null || true
    ATTRAPPE=""
  fi
}

# Startet die Attrappe von greetd und den Login. Optional: Ordner, der vorn in den PATH des Logins kommt.
login_starten() { # [PFAD]
  login_stoppen
  rm -rf -- "$E2E/greetd.log" "$E2E/greetd.sock"
  python3 "$REPO/test/container/login/greetd_attrappe.py" "$E2E/greetd.sock" "$E2E/greetd.log" &
  ATTRAPPE=$!
  for _ in $(seq 1 20); do
    [[ -S "$E2E/greetd.sock" ]] && break
    sleep 0.25
  done
  if [[ ! -S "$E2E/greetd.sock" ]]; then
    meldung "Attrappe von greetd startet nicht"
    return 1
  fi
  if [[ -n "${1:-}" ]]; then
    GREETD_SOCK=$E2E/greetd.sock PATH="$1:$PATH" "$O" start --greeter > /dev/null || return 1
  else
    GREETD_SOCK=$E2E/greetd.sock "$O" start --greeter > /dev/null || return 1
  fi
  # Der erste virtuelle Tastendruck nach dem Start von labwc geht verloren (oberflaeche.sh): jetzt, harmlos
  "$O" taste Shift_L
  START=$SECONDS
}

protokoll() { "$O" log 400 2> /dev/null; }

schritt_minute() {
  echo "Schritt minute: eine Minute ohne Eingabe, Tippen beginnt sie neu"
  login_starten || { schlecht "Login startet nicht"; return; }
  sleep 40
  pruefe "nach 40 s an" "nach 40 s nicht an" ist_bildschirm an
  "$O" tippe x
  local eingabe=$SECONDS
  sleep 40
  if [[ "$(bildschirm)" == an ]]; then
    gut "ein Zeichen im Passwortfeld nach 40 s beginnt die Minute neu: nach $((SECONDS - START)) s noch an"
  else
    schlecht "nach $((SECONDS - START)) s schon $(bildschirm), obwohl nach 40 s getippt wurde"
  fi
  if warte_bildschirm aus 40; then
    local nach=$((SECONDS - eingabe))
    if (( nach >= 55 )); then gut "aus, $nach s nach der letzten Eingabe"; else schlecht "aus schon $nach s nach der letzten Eingabe"; fi
  else
    schlecht "nach $((SECONDS - eingabe)) s ohne Eingabe nicht aus ($(bildschirm))"
  fi
  zeiger move 20 20
  pruefe "die Maus weckt" "die Maus weckt nicht" warte_bildschirm an 5
  pruefe "Protokoll: «… Min. ohne Eingabe, Bildschirm aus»" "keine Zeile «Bildschirm aus» im Protokoll" \
    im_protokoll "Min. ohne Eingabe, Bildschirm aus"
}

schritt_taste() {
  echo "Schritt taste: die erste Taste weckt nur, die zweite landet im Feld"
  login_starten || { schlecht "Login startet nicht"; return; }
  "$O" tippe tes
  if warte_bildschirm aus 75; then gut "mit «tes» im Feld nach $((SECONDS - START)) s aus"; else schlecht "nicht aus ($(bildschirm))"; return; fi
  "$O" tippe q
  pruefe "«q» weckt" "«q» weckt nicht" warte_bildschirm an 5
  sleep 1
  pruefe "greetd hat nichts bekommen" "greetd hat schon etwas bekommen" keine_anfragen
  "$O" tippe ter
  "$O" taste Return
  local antwort
  if antwort=$(warte_antwort 10); then
    if [[ "$antwort" == tester ]]; then
      gut "greetd bekommt genau «tester»: «tes» blieb, die Wecktaste «q» ist verworfen"
    else
      schlecht "greetd bekommt «$antwort» statt «tester»"
    fi
  else
    schlecht "keine Antwort an greetd nach Return"
  fi
  sleep 1
  pruefe "angemeldet (start_session)" "kein start_session" in_anfragen '"start_session"'
  pruefe "nach der Anmeldung ist der Bildschirm an" "nach der Anmeldung nicht an" ist_bildschirm an
  pruefe "Protokoll: «Wecktaste verworfen (Taste)»" "keine Zeile «Wecktaste verworfen (Taste)» im Protokoll" \
    im_protokoll "Wecktaste verworfen (Taste)"
}

schritt_halten() {
  echo "Schritt halten: die gehaltene Wecktaste wiederholt sich nicht ins Feld"
  login_starten || { schlecht "Login startet nicht"; return; }
  "$O" tippe tes
  if warte_bildschirm aus 75; then gut "mit «tes» im Feld nach $((SECONDS - START)) s aus"; else schlecht "nicht aus ($(bildschirm))"; return; fi
  halte q 1500
  pruefe "«q» (1,5 s gehalten) weckt" "«q» weckt nicht" warte_bildschirm an 5
  sleep 1
  pruefe "greetd hat nichts bekommen" "greetd hat schon etwas bekommen" keine_anfragen
  "$O" tippe ter
  "$O" taste Return
  local antwort
  if antwort=$(warte_antwort 10); then
    if [[ "$antwort" == tester ]]; then
      gut "greetd bekommt genau «tester»: keine Wiederholung von «q» im Feld"
    else
      schlecht "greetd bekommt «$antwort» statt «tester»"
    fi
  else
    schlecht "keine Antwort an greetd nach Return"
  fi

  login_starten || { schlecht "Login startet nicht"; return; }
  "$O" tippe tes
  if warte_bildschirm aus 75; then gut "mit «tes» im Feld nach $((SECONDS - START)) s aus"; else schlecht "nicht aus ($(bildschirm))"; return; fi
  halte Return 1500
  pruefe "Return (1,5 s gehalten) weckt" "Return weckt nicht" warte_bildschirm an 5
  sleep 1.5
  pruefe "greetd hat nichts bekommen (kein halbes Passwort an PAM)" "gehaltenes Return hat angemeldet: $(anfragen | tr '\n' ' ')" keine_anfragen
  "$O" tippe ter
  "$O" taste Return
  if antwort=$(warte_antwort 10) && [[ "$antwort" == tester ]]; then
    gut "danach meldet Return an, greetd bekommt genau «tester»"
  else
    schlecht "greetd bekommt «${antwort:-nichts}» statt «tester»"
  fi
}

# Erwartet nach Return eine Antwort an PAM, genau «tester»
meldet_mit_tester_an() { # TEXT
  local antwort
  if antwort=$(warte_antwort 10) && [[ "$antwort" == tester ]]; then
    gut "$1 greetd bekommt genau «tester»"
  else
    schlecht "$1 greetd bekommt «${antwort:-nichts}» statt «tester»"
  fi
}

schritt_modifikator() {
  echo "Schritt modifikator: Shift, Alt, AltGr oder Super während des Haltens beenden das Verwerfen nicht"
  login_starten || { schlecht "Login startet nicht"; return; }
  "$O" tippe tes
  if warte_bildschirm aus 75; then gut "mit «tes» im Feld nach $((SECONDS - START)) s aus"; else schlecht "nicht aus ($(bildschirm))"; return; fi
  # Return gedrückt, nach 900 ms (schon wiederholt) Shift dazu, 600 ms später Shift los, Return 100 ms danach
  WAYLAND_DISPLAY=$(cat "$ZUSTAND/wayland") wtype -P Return -s 900 -P Shift_L -s 600 -p Shift_L -s 100 -p Return
  pruefe "Return (mit Shift dazu gehalten) weckt" "Return weckt nicht" warte_bildschirm an 5
  sleep 1.5
  pruefe "greetd hat nichts bekommen (kein halbes Passwort nach dem Shift)" \
    "Return wiederholte sich nach dem Shift ins Feld: $(anfragen | tr '\n' ' ')" keine_anfragen
  "$O" tippe ter
  "$O" taste Return
  meldet_mit_tester_an "danach «ter» und Return:"

  login_starten || { schlecht "Login startet nicht"; return; }
  "$O" tippe tes
  if warte_bildschirm aus 75; then gut "mit «tes» im Feld nach $((SECONDS - START)) s aus"; else schlecht "nicht aus ($(bildschirm))"; return; fi
  # «q» gedrückt, nach 900 ms nacheinander Alt, AltGr und Super je 300 ms, dazwischen 200 ms nur «q»
  WAYLAND_DISPLAY=$(cat "$ZUSTAND/wayland") wtype -P q -s 900 -P Alt_L -s 300 -p Alt_L -s 200 \
    -P ISO_Level3_Shift -s 300 -p ISO_Level3_Shift -s 200 -P Super_L -s 300 -p Super_L -s 200 -p q
  pruefe "«q» (mit Alt, AltGr und Super dazu gehalten) weckt" "«q» weckt nicht" warte_bildschirm an 5
  sleep 1
  pruefe "greetd hat nichts bekommen" "greetd hat schon etwas bekommen" keine_anfragen
  "$O" tippe ter
  "$O" taste Return
  meldet_mit_tester_an "keine Wiederholung von «q» im Feld:"
}

schritt_klick() {
  echo "Schritt klick: der erste Klick weckt nur, der zweite meldet an"
  login_starten || { schlecht "Login startet nicht"; return; }
  "$O" tippe tester
  zeiger move -3000 -3000
  zeiger move "$KNOPF_X" "$KNOPF_Y"
  if warte_bildschirm aus 75; then gut "Zeiger auf «Anmelden», nach $((SECONDS - START)) s aus"; else schlecht "nicht aus ($(bildschirm))"; return; fi
  zeiger click left
  pruefe "der Klick weckt" "der Klick weckt nicht" warte_bildschirm an 5
  sleep 1.5
  pruefe "der erste Klick löst nichts aus (greetd hat nichts bekommen)" "der erste Klick hat angemeldet" keine_anfragen
  zeiger click left
  local antwort
  if antwort=$(warte_antwort 10) && [[ "$antwort" == tester ]]; then
    gut "der zweite Klick meldet an, greetd bekommt «tester»"
  else
    schlecht "der zweite Klick meldet nicht an (Antwort «${antwort:-keine}»; Lage von «Anmelden» geändert?)"
  fi
}

schritt_fehler() {
  echo "Schritt fehler: wlopm meldet beim Ausschalten einen Fehler, der Bildschirm bleibt an"
  mkdir -p -- "$E2E/bin"
  : > "$E2E/wlopm.log"
  # Attrappe: schaltet wirklich ab, meldet aber einen Fehler (wie ein Bildschirm von zweien, der sich weigert)
  cat > "$E2E/bin/wlopm" << SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$E2E/wlopm.log'
if [[ " \$* " == *" --off "* ]]; then
  /usr/bin/wlopm "\$@" > /dev/null 2>&1
  printf '{\n  "errors": [ { "output": "HEADLESS-1", "error": "Attrappe" } ]\n}\n'
  exit 0
fi
exec /usr/bin/wlopm "\$@"
SH
  chmod 0755 -- "$E2E/bin/wlopm"
  login_starten "$E2E/bin" || { schlecht "Login startet nicht"; return; }
  local ende=$((SECONDS + 75))
  while (( SECONDS < ende )) && ! grep -q -- '--off' "$E2E/wlopm.log"; do sleep 0.5; done
  if grep -q -- '--off' "$E2E/wlopm.log"; then gut "nach $((SECONDS - START)) s versucht auszuschalten"; else schlecht "kein Versuch auszuschalten"; return; fi
  pruefe "der Fehler lässt den Bildschirm an (gleich wieder eingeschaltet)" "nach dem Fehler nicht an" \
    warte_bildschirm an 5
  sleep 20
  pruefe "20 s später weiter an" "20 s später nicht an" ist_bildschirm an
  local aus
  aus=$(grep -c -- '--off' "$E2E/wlopm.log")
  if (( aus == 1 )); then gut "ohne neue Eingabe kein zweiter Versuch"; else schlecht "$aus Versuche auszuschalten"; fi
  pruefe "Protokoll: «wlopm --off gescheitert … bleibt an»" "kein Grund im Protokoll" im_protokoll "gescheitert"
}

schritt_neustart() {
  echo "Schritt neustart: sicher dunkel und geht nicht mehr an, dann beendet sich der Login"
  login_stoppen
  mkdir -p -- "$E2E/bin-an"
  # Attrappe: schaltet ab, aber nicht mehr an (meldet einen Fehler)
  cat > "$E2E/bin-an/wlopm" << SH
#!/usr/bin/env bash
if [[ " \$* " == *" --on "* ]]; then
  printf '{\n  "errors": [ { "output": "HEADLESS-1", "error": "Attrappe" } ]\n}\n'
  exit 0
fi
exec /usr/bin/wlopm "\$@"
SH
  chmod 0755 -- "$E2E/bin-an/wlopm"
  rm -f -- "$E2E/greetd.log"
  python3 "$REPO/test/container/login/greetd_attrappe.py" "$E2E/greetd.sock" "$E2E/greetd.log" &
  ATTRAPPE=$!
  local vorher neu="" beginn greeter
  vorher=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' | sort)
  beginn=$(date +%s)
  # Wie unter greetd: zenos-greeter startet labwc -S mit der Oberfläche (hier ohne Bildschirm)
  (
    unset WAYLAND_DISPLAY DISPLAY
    export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 QT_QUICK_BACKEND=software \
      ZENOS_CODE=$REPO GREETD_SOCK=$E2E/greetd.sock PATH="$E2E/bin-an:$PATH"
    exec setsid "$REPO/scripts/bin/zenos-greeter"
  ) > "$E2E/zenos-greeter.log" 2>&1 < /dev/null &
  greeter=$!
  for _ in $(seq 1 40); do
    neu=$(comm -13 <(printf '%s\n' "$vorher") \
      <(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' | sort) | head -n 1)
    [[ -n "$neu" ]] && break
    sleep 0.5
  done
  if [[ -z "$neu" ]]; then
    schlecht "zenos-greeter startet kein labwc"
    kill -- "-$greeter" 2> /dev/null || kill "$greeter" 2> /dev/null || true
    return
  fi
  ANZEIGE=$neu
  sleep 3
  WAYLAND_DISPLAY=$neu wtype -k Shift_L
  if warte_bildschirm aus 75; then gut "zenos-greeter: nach $(($(date +%s) - beginn)) s aus"; else schlecht "nicht aus"; fi
  WAYLAND_DISPLAY=$neu wtype q
  local ende=$((SECONDS + 15))
  while (( SECONDS < ende )) && kill -0 "$greeter" 2> /dev/null; do sleep 0.5; done
  if kill -0 "$greeter" 2> /dev/null; then
    schlecht "der Login läuft nach 15 s noch (dunkel)"
    kill -- "-$greeter" 2> /dev/null || kill "$greeter" 2> /dev/null || true
  else
    gut "der Login hat sich beendet, labwc mit ihm (unter greetd: neuer Login, alle Bildschirme an)"
  fi
  wait "$greeter" 2> /dev/null || true
  ANZEIGE=""
  local journal
  journal=$(journalctl -t zenos-greeter --since "@$beginn" --no-pager -o cat 2> /dev/null; cat -- "$E2E/zenos-greeter.log")
  if grep -qF 'starte den Login neu' <<< "$journal"; then
    gut "Journal: «Bildschirm geht nicht mehr an, starte den Login neu»"
  else
    schlecht "kein Grund im Journal (journalctl -t zenos-greeter)"
  fi
  if grep -qF 'Notfall-Login' <<< "$journal"; then schlecht "der Notfall-Login wurde gestartet"; else gut "kein Notfall-Login"; fi
  kill "$ATTRAPPE" 2> /dev/null || true
  wait "$ATTRAPPE" 2> /dev/null || true
  ATTRAPPE=""
}

if (( EUID == 0 )); then
  meldung "als tester starten, nicht als root"
  exit 2
fi
for programm in wlopm wtype wlrctl python3 labwc quickshell; do
  command -v "$programm" > /dev/null || { meldung "$programm fehlt (siehe Kopf der Datei)"; exit 2; }
done
[[ -d "$XDG_RUNTIME_DIR" ]] || { meldung "$XDG_RUNTIME_DIR fehlt (loginctl enable-linger tester)"; exit 2; }
mkdir -p -- "$E2E" || exit 1
trap login_stoppen EXIT

schritte=("$@")
(( ${#schritte[@]} > 0 )) || schritte=(minute taste halten modifikator klick fehler neustart)
for s in "${schritte[@]}"; do
  case "$s" in
    minute | taste | halten | modifikator | klick | fehler | neustart) "schritt_$s" ;;
    *) meldung "unbekannter Schritt «$s» (minute, taste, halten, modifikator, klick, fehler, neustart)"; exit 2 ;;
  esac
done
login_stoppen
if (( BEFUND )); then echo "Befunde, siehe oben."; exit 1; fi
echo "Alles wie erwartet."
