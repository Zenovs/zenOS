#!/usr/bin/env bash
# einaus-e2e.sh [schritt …] – Ende-zu-Ende-Beleg: Ein/Aus-Taste am Login-Bildschirm (Zenos Entscheid vom 08.10.2026,
# shell/greeter/EinAusTaste.qml und «zenos-energie hemmer-login»). Läuft im Testcontainer als root.
#
# Der Login läuft wie unter greetd: als _greetd in einer über PAM gestellten Sitzung der Klasse «greeter» auf seat0
# (PAM-Dienst greetd-greeter, wie greetd ihn für den Login nimmt), gestartet über scripts/bin/zenos-greeter (labwc ohne
# Bildschirm mit -S, darin shell/greeter.qml), dazu die Attrappe von greetd (test/container/login/greetd_attrappe.py).
# Damit logind seat0 ohne VT führt und keine Konsole der VM umstellt, liegt /dev/tty0 während des Tests beiseite (wie
# in gesten-e2e.sh). Vorsorglich steht für logind HandlePowerKey=lock in einem Drop-in (nur in diesem Container).
#
# Bewusst ohne Gerät mit KEY_POWER über uinput: Der Kernel gehört der colima-VM, die alle Container trägt. Deren udev
# markiert jedes Gerät mit KEY_POWER als «power-switch», und logind der VM schaltete bei einem Druck womöglich die VM
# samt allen Containern aus. Die Taste kommt deshalb als XF86PowerOff über wtype (virtuelle Tastatur, in labwc derselbe
# Weg wie eine echte Tastatur); dass KEY_POWER (116) in xkb XF86PowerOff ist, prüft «hemmer» in den xkb-Daten. Dass
# logind dann nicht ausschaltet, folgt aus dem Hemmer in einer aktiven Sitzung (BlockInhibited), am Gerät zu prüfen.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, /opt/zenos auf dem Stand dieses Codes):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-einaus-e2e
#   docker exec zenos-einaus-e2e bash -c 'apt-get update -qq && apt-get install -y -qq wlopm wtype'
#   docker exec -u tester -w /home/tester/zenOS zenos-einaus-e2e ./scripts/install.sh
# Dann: docker exec zenos-einaus-e2e bash /home/tester/zenOS/test/container/einaus-e2e.sh [schritt …]
# Ohne Angabe laufen alle (rund 3 Minuten). Exit 0 nur, wenn alles stimmt.
#
#   hemmer      Sitzung des Logins: Klasse greeter, seat0, lokal, aktiv. Logind führt den Hemmer «zenOS» mit
#               handle-power-key im Modus block für _greetd, gehalten von systemd-inhibit mit tail --pid=<Quickshell des
#               Logins>; BlockInhibited nennt handle-power-key; zenOS hat keine eigene polkit-Regel. Gegenprobe: tester
#               ohne Sitzung bekommt denselben Hemmer nicht (polkit lehnt ab). KEY_POWER ist in xkb XF86PowerOff.
#   wecken      am hellen Login XF86PowerOff: bleibt hell, kein Wecken, kein Zeichen; «tes» getippt, nach einer Minute
#               dunkel; XF86PowerOff weckt (Wecktaste verworfen); «ter» und Return: greetd bekommt genau «tester». Nach
#               der Anmeldung (Quickshell endet) ist der Hemmer weg.
#   absturz     kill -9 auf Quickshell des Logins (nach mehr als 30 s): Der Hemmer ist nach höchstens 3 s weg, der Login
#               endet (unter greetd folgt ein neuer).
#   notfall     Quickshell des Logins endet in den ersten 30 s (wie wenn greeter.qml nicht lädt): Der Notfall-Login läuft
#               ohne Hemmer (dort schaltet ein kurzer Druck aus, logind).
#   aufraeumen  Sitzungen und Attrappe beenden, /dev/tty0 zurück, Drop-in weg, logind neu

set -uo pipefail

E2E=/srv/einaus-e2e
CODE=${ZENOS_E2E_CODE:-/opt/zenos}
REPO=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/../.." && pwd -P)
UNIT=e2e-einaus-login
TTY_BEISEITE=/dev/tty0.zenos-einaus-e2e
DROPIN=/run/systemd/logind.conf.d/zenos-einaus-e2e.conf
ALLE=(hemmer wecken absturz notfall aufraeumen)

BEFUND=0
gut() { printf '  ✓ %s\n' "$*"; }
schlecht() { printf '  ✗ %s\n' "$*"; BEFUND=1; }
pruefe() { # GUT SCHLECHT BEFEHL…
  local ja=$1 nein=$2
  shift 2
  if "$@"; then gut "$ja"; else schlecht "$nein"; fi
}
schritt() { printf '\n== %s\n' "$*"; }

[[ $EUID == 0 ]] || { echo "einaus-e2e.sh läuft als root im Testcontainer" >&2; exit 2; }
[[ -f /.dockerenv || -n "${container:-}" ]] || { echo "einaus-e2e.sh nur im Testcontainer" >&2; exit 2; }
GREETD_UID=$(id -u _greetd) || { echo "Benutzer _greetd fehlt (greetd installiert?)" >&2; exit 2; }
LAUFZEIT=/run/user/$GREETD_UID
install -d -o _greetd -g _greetd -m 0755 "$E2E"
for werkzeug in wlopm wtype jq busctl; do
  command -v "$werkzeug" > /dev/null || { echo "$werkzeug fehlt (Vorbereitung im Kopf der Datei)" >&2; exit 2; }
done

als_greetd() { setpriv --reuid=_greetd --regid=_greetd --init-groups -- env -i PATH=/usr/bin:/bin LANG=C.UTF-8 \
  XDG_RUNTIME_DIR="$LAUFZEIT" "$@"; }

# warte_bis SEKUNDEN BEFEHL… – bis BEFEHL gelingt (Takt 0,25 s)
warte_bis() {
  local ende=$((SECONDS + $1))
  shift
  until "$@" > /dev/null 2>&1; do
    (( SECONDS < ende )) || return 1
    sleep 0.25
  done
}

# --- logind, Sitzung des Logins ---------------------------------------------------

vorbereiten() {
  local neu=0
  if [[ -e /dev/tty0 ]]; then mv /dev/tty0 "$TTY_BEISEITE"; neu=1; fi
  if [[ ! -f "$DROPIN" ]]; then
    mkdir -p -- "${DROPIN%/*}"
    printf '# Nur im Testcontainer (einaus-e2e.sh): eine Ein/Aus-Taste schaltet hier nie aus\n[Login]\nHandlePowerKey=lock\n' \
      > "$DROPIN"
    neu=1
  fi
  if (( neu )); then
    systemctl restart systemd-logind
    warte_bis 10 busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager HandlePowerKey
  fi
  [[ "$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
    HandlePowerKey)" == 's "lock"' ]] || { schlecht "HandlePowerKey ist nicht «lock»"; exit 1; }
}

sitzung_ist() { # ID – «Class=… Seat=… Remote=… Active=…»
  local name
  for name in Class Seat Remote Active; do printf '%s=%s ' "$name" "$(loginctl show-session "$1" -p "$name" --value)"; done |
    sed 's/ $//'
}

in_sitzung() { # PID ID – der Prozess liegt im Scope der Sitzung (Pfad von der Wurzel des cgroup-Baums aus)
  [[ "$(grep -o '^0::.*' "/proc/$1/cgroup" 2> /dev/null)" == *"/user.slice/user-$GREETD_UID.slice/session-$2.scope" ]]
}

inhibit_in_sitzung() { # PID ID – systemd-inhibit im Scope der Sitzung
  [[ "$(cat "/proc/$1/comm" 2> /dev/null)" == systemd-inhibit ]] && in_sitzung "$1" "$2"
}

sitzung() { # gibt die ID der Sitzung des Logins aus (Klasse greeter, _greetd, seat0)
  loginctl list-sessions --json=short | jq -r '.[] | select(.user == "_greetd" and .seat == "seat0") | .session' |
    head -n 1
}

hat_sitzung() { [[ -n "$(sitzung)" ]]; }
hat_anzeige() { [[ -n "$(anzeige)" ]]; }
laeuft_qml() { [[ -n "$(quickshell_pid "$1")" ]]; }
laeuft_nicht() { [[ -z "$(quickshell_pid "$1")" ]]; }

anzeige() { # WAYLAND_DISPLAY des labwc im Login
  find "$LAUFZEIT" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' 2> /dev/null | sort | head -n 1
}

quickshell_pid() { # Quickshell mit QML-Datei $1 (greeter.qml oder notfall.qml) von _greetd
  pgrep -u _greetd -f "quickshell .*-p .*/$1\$" | head -n 1
}

hemmer_von_greetd() { # Zeilen «what|who|why|mode|pid» der Hemmer von _greetd
  busctl --system --json=short call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
    ListInhibitors | jq -r --argjson uid "$GREETD_UID" \
    '.data[0][] | select(.[4] == $uid) | "\(.[0])|\(.[1])|\(.[2])|\(.[3])|\(.[5])"'
}
kein_hemmer() { [[ -z "$(hemmer_von_greetd)" ]]; }
ein_hemmer() { [[ -n "$(hemmer_von_greetd)" ]]; }

attrappe_starten() {
  attrappe_stoppen
  install -m 0644 "$REPO/test/container/login/greetd_attrappe.py" "$E2E/greetd_attrappe.py"
  rm -f -- "$E2E/greetd.sock" "$E2E/greetd.log"
  als_greetd python3 "$E2E/greetd_attrappe.py" "$E2E/greetd.sock" "$E2E/greetd.log" > /dev/null 2>&1 &
  echo "$!" > "$E2E/attrappe.pid"
  warte_bis 5 test -S "$E2E/greetd.sock" || { schlecht "Attrappe von greetd startet nicht"; exit 1; }
}

attrappe_stoppen() {
  if [[ -f "$E2E/attrappe.pid" ]]; then
    kill "$(cat "$E2E/attrappe.pid")" 2> /dev/null || true
    rm -f -- "$E2E/attrappe.pid"
  fi
}

# login_starten – zenos-greeter wie unter greetd, als _greetd in einer Sitzung der Klasse greeter auf seat0
login_starten() {
  login_stoppen
  attrappe_starten
  START=$(date +%s)
  systemd-run --quiet --unit="$UNIT" -p PAMName=greetd-greeter -p User=_greetd -p WorkingDirectory=/ \
    -p Environment=XDG_SEAT=seat0 -p Environment=XDG_SESSION_CLASS=greeter -p Environment=XDG_SESSION_TYPE=wayland \
    -p Environment=WLR_BACKENDS=headless -p Environment=WLR_RENDERER=pixman -p Environment=WLR_HEADLESS_OUTPUTS=1 \
    -p Environment=WLR_LIBINPUT_NO_DEVICES=1 -p Environment=QT_QUICK_BACKEND=software \
    -p Environment=GREETD_SOCK="$E2E/greetd.sock" -p Environment=ZENOS_CODE="$CODE" \
    "$CODE/scripts/bin/zenos-greeter"
  warte_bis 15 hat_sitzung || { schlecht "keine Sitzung des Logins auf seat0"; return 1; }
  warte_bis 30 hat_anzeige || { schlecht "labwc des Logins startet nicht"; return 1; }
  ANZEIGE=$(anzeige)
}

login_stoppen() {
  systemctl stop "$UNIT.service" 2> /dev/null || true
  systemctl reset-failed "$UNIT.service" 2> /dev/null || true
  warte_bis 10 bash -c "! loginctl list-sessions --json=short | jq -e '.[] | select(.user == \"_greetd\" and .seat == \"seat0\")' > /dev/null" || true
  attrappe_stoppen
}

journal() { journalctl -t zenos-greeter --since "@$START" --no-pager -o cat 2> /dev/null; }
im_journal() { journal | grep -qF -- "$1"; }

taste() { als_greetd env WAYLAND_DISPLAY="$ANZEIGE" wtype "$@"; }
bildschirm() { # «an», «aus» oder «?»
  als_greetd env WAYLAND_DISPLAY="$ANZEIGE" wlopm --json 2> /dev/null | python3 -c '
import json, sys
try:
    modi = {e.get("power-mode") for e in json.load(sys.stdin)}
except (ValueError, AttributeError, TypeError):
    modi = set()
print("an" if modi == {"on"} else "aus" if modi == {"off"} else "?")'
}
ist_bildschirm() { [[ "$(bildschirm)" == "$1" ]]; }
anfragen() { cat -- "$E2E/greetd.log" 2> /dev/null || true; }
antwort_ist() { [[ "$(antwort)" == "$1" ]]; }
antwort() { # Antwort an PAM aus der Attrappe (leer: keine)
  anfragen | jq -r 'select(.type == "post_auth_message_response") | .response' | head -n 1
}

# --- Schritte ---------------------------------------------------------------------------

schritt_hemmer() {
  schritt "hemmer: Sitzung der Klasse greeter, Hemmer von _greetd, polkit ohne eigene Regel"
  vorbereiten
  login_starten || return
  local id qs inhibit zeile kind
  id=$(sitzung)
  pruefe "Sitzung $id: Klasse greeter, seat0, lokal, aktiv" "Sitzung $id: $(sitzung_ist "$id")" \
    test "$(sitzung_ist "$id")" == "Class=greeter Seat=seat0 Remote=no Active=yes"
  warte_bis 20 laeuft_qml greeter.qml || { schlecht "Quickshell mit greeter.qml läuft nicht"; return; }
  qs=$(quickshell_pid greeter.qml)
  warte_bis 20 ein_hemmer || { schlecht "kein Hemmer von _greetd ($(journal | tail -n 5 | tr '\n' ' '))"; return; }
  zeile=$(hemmer_von_greetd)
  pruefe "genau ein Hemmer: ${zeile%|*}" "Hemmer: $zeile" \
    test "${zeile%|*}" == "handle-power-key|zenOS|Ein/Aus-Taste am Login-Bildschirm: kurzer Druck weckt nur|block"
  inhibit=${zeile##*|}
  pruefe "gehalten von systemd-inhibit (PID $inhibit) in der Sitzung $id" "PID $inhibit: $(cat "/proc/$inhibit/comm" 2> /dev/null) $(grep -o '^0::.*' "/proc/$inhibit/cgroup" 2> /dev/null)" \
    inhibit_in_sitzung "$inhibit" "$id"
  kind=$(pgrep -P "$inhibit" -x tail | head -n 1)
  pruefe "systemd-inhibit wartet auf tail --pid=$qs (Quickshell des Logins)" "Kind von systemd-inhibit: $(tr '\0' ' ' < "/proc/${kind:-0}/cmdline" 2> /dev/null)" \
    test "$(tr '\0' ' ' < "/proc/${kind:-0}/cmdline" 2> /dev/null)" == "tail --pid=$qs -f /dev/null "
  pruefe "logind: BlockInhibited nennt handle-power-key" "BlockInhibited: $(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager BlockInhibited)" \
    grep -q 'handle-power-key' <(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager BlockInhibited)
  pruefe "systemd-inhibit --list nennt zenOS, _greetd, handle-power-key" "systemd-inhibit --list: $(systemd-inhibit --list --no-pager 2> /dev/null | tr '\n' ' ')" \
    grep -qE 'zenOS +[0-9]+ +_greetd .*handle-power-key' <(systemd-inhibit --list --no-pager 2> /dev/null)
  pruefe "Journal: «Ein/Aus-Taste weckt nur (Hemmer handle-power-key)»" "Journal ohne Meldung des Hemmers" \
    warte_bis 10 im_journal "Ein/Aus-Taste weckt nur (Hemmer handle-power-key)"
  pruefe "keine Meldung «Hemmer … beendet»" "Journal: $(journal | grep -F 'Hemmer für die Ein/Aus-Taste beendet')" \
    bash -c "! journalctl -t zenos-greeter --since @$START --no-pager -o cat | grep -qF 'Hemmer für die Ein/Aus-Taste beendet'"
  # polkit: die Vorgabe von systemd, keine Regel von zenOS
  pruefe "polkit: Vorgabe allow_active yes, keine Regel von zenOS" "polkit: Vorgabe geändert oder Regel von zenOS" \
    bash -c 'grep -A8 "id=\"org.freedesktop.login1.inhibit-handle-power-key\"" /usr/share/polkit-1/actions/org.freedesktop.login1.policy | grep -q "<allow_active>yes</allow_active>" && ! grep -rlsE "inhibit-handle-power-key|_greetd" /etc/polkit-1/rules.d /usr/share/polkit-1/rules.d'
  # Gegenprobe: ohne Sitzung (docker exec als tester) lehnt polkit ab
  local gegen rc=0
  gegen=$(setpriv --reuid=tester --regid=tester --init-groups -- timeout 10 systemd-inhibit --what=handle-power-key \
    --mode=block --who=e2e --why=gegenprobe true 2>&1) || rc=$?
  pruefe "Gegenprobe: tester ohne Sitzung bekommt den Hemmer nicht (Exit $rc: ${gegen//$'\n'/ })" "Gegenprobe: tester bekam den Hemmer ohne Sitzung" \
    test "$rc" -ne 0
  # KEY_POWER (evdev 116) ist in xkb <POWR> = 124 und dort XF86PowerOff
  pruefe "xkb: KEY_POWER → <POWR> = 124 → XF86PowerOff" "xkb: KEY_POWER ist nicht XF86PowerOff" \
    bash -c 'grep -qE "^\s*<POWR> = 124;" /usr/share/X11/xkb/keycodes/evdev && grep -qE "key <POWR> +\{ +\[ XF86PowerOff +\] +\};" /usr/share/X11/xkb/symbols/inet'
}

schritt_wecken() {
  schritt "wecken: hell nichts, dunkel weckt nur, nach der Anmeldung kein Hemmer"
  vorbereiten
  if laeuft_qml greeter.qml && hat_anzeige; then ANZEIGE=$(anzeige); else login_starten || return; fi
  warte_bis 20 ein_hemmer || { schlecht "kein Hemmer"; return; }
  sleep 2
  # Der erste virtuelle Tastendruck nach dem Start von labwc geht verloren (oberflaeche.sh): jetzt, harmlos
  taste -k Shift_L
  sleep 1
  local vorher
  vorher=$(journal | grep -cF 'Wecktaste verworfen' || true)
  pruefe "Bildschirm an" "Bildschirm $(bildschirm) statt an" ist_bildschirm an
  taste -k XF86PowerOff
  sleep 2
  pruefe "am hellen Login: XF86PowerOff ändert nichts (hell, kein Wecken)" "am hellen Login: Bildschirm $(bildschirm), Wecktaste verworfen" \
    test "$(bildschirm):$(journal | grep -cF 'Wecktaste verworfen' || true)" == "an:$vorher"
  pruefe "der Login läuft weiter, der Hemmer hält" "Login oder Hemmer weg" bash -c "pgrep -u _greetd -f 'greeter\.qml\$' > /dev/null"
  ein_hemmer || schlecht "Hemmer nach XF86PowerOff weg"
  taste tes
  local beginn=$SECONDS
  if warte_bis 80 ist_bildschirm aus; then
    gut "«tes» getippt, nach $((SECONDS - beginn)) s dunkel"
  else
    schlecht "nach 80 s nicht dunkel"
    return
  fi
  taste -k XF86PowerOff
  pruefe "XF86PowerOff am dunklen Login: hell" "XF86PowerOff weckt nicht" warte_bis 10 ist_bildschirm an
  pruefe "Journal: «Wecktaste verworfen (Taste)»" "keine Wecktaste im Journal" \
    warte_bis 5 im_journal "Wecktaste verworfen (Taste)"
  pruefe "greetd hat nichts bekommen" "greetd bekam: $(anfragen | tr '\n' ' ')" test -z "$(antwort)"
  sleep 1
  taste ter
  taste -k Return
  pruefe "«ter» und Return: greetd bekommt genau «tester»" "greetd bekam «$(antwort)»" \
    warte_bis 10 antwort_ist tester
  pruefe "nach der Anmeldung: Quickshell des Logins beendet" "Quickshell des Logins läuft noch" \
    warte_bis 10 laeuft_nicht greeter.qml
  pruefe "nach der Anmeldung: kein Hemmer von _greetd (höchstens 3 s)" "Hemmer nach der Anmeldung: $(hemmer_von_greetd)" \
    warte_bis 3 kein_hemmer
  login_stoppen
}

schritt_absturz() {
  schritt "absturz: kill -9 auf Quickshell des Logins, der Hemmer geht mit"
  vorbereiten
  login_starten || return
  warte_bis 20 ein_hemmer || { schlecht "kein Hemmer"; return; }
  # Nach 30 s: zenos-greeter startet dann keinen Notfall-Login, der Login endet (unter greetd folgt ein neuer)
  while (( $(date +%s) - START < 40 )); do sleep 1; done
  local qs
  qs=$(quickshell_pid greeter.qml)
  kill -KILL "$qs"
  pruefe "kill -9 auf Quickshell ($qs): kein Hemmer nach höchstens 3 s" "Hemmer nach dem Absturz: $(hemmer_von_greetd)" \
    warte_bis 3 kein_hemmer
  pruefe "der Login endet (labwc -S), kein Notfall-Login" "Login läuft noch oder Notfall-Login" \
    warte_bis 10 bash -c "! systemctl --quiet is-active $UNIT.service && ! pgrep -u _greetd -f 'notfall\.qml\$' > /dev/null"
  login_stoppen
}

schritt_notfall() {
  schritt "notfall: der Notfall-Login nimmt keinen Hemmer"
  vorbereiten
  login_starten || return
  warte_bis 20 ein_hemmer || { schlecht "kein Hemmer"; return; }
  local qs
  qs=$(quickshell_pid greeter.qml)
  # Endet greeter.qml in den ersten 30 s (wie wenn es nicht lädt), startet zenos-greeter den Notfall-Login
  kill -KILL "$qs"
  pruefe "Notfall-Login läuft" "kein Notfall-Login" warte_bis 15 laeuft_qml notfall.qml
  pruefe "Journal: «starte den Notfall-Login»" "Journal ohne Notfall-Login" warte_bis 5 im_journal "starte den Notfall-Login"
  sleep 5
  pruefe "kein Hemmer im Notfall-Login (logind schaltet bei einem kurzen Druck aus)" "Hemmer im Notfall-Login: $(hemmer_von_greetd)" \
    kein_hemmer
  login_stoppen
}

schritt_aufraeumen() {
  schritt "aufraeumen"
  login_stoppen
  rm -f -- "$DROPIN"
  if [[ -e "$TTY_BEISEITE" ]]; then mv "$TTY_BEISEITE" /dev/tty0; fi
  systemctl restart systemd-logind
  gut "Sitzung und Attrappe beendet, Drop-in weg, /dev/tty0 zurück, logind neu"
}

ANZEIGE=""
START=$(date +%s)
schritte=("$@")
(( ${#schritte[@]} > 0 )) || schritte=("${ALLE[@]}")
for s in "${schritte[@]}"; do
  case "$s" in
    hemmer | wecken | absturz | notfall | aufraeumen) "schritt_$s" ;;
    *) echo "einaus-e2e.sh: unbekannter Schritt «$s» (${ALLE[*]})" >&2; exit 2 ;;
  esac
done
if (( BEFUND )); then
  printf '\nBefunde in: %s\n' "${schritte[*]}"
  exit 1
fi
printf '\nAlles gut: %s\n' "${schritte[*]}"
