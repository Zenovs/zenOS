#!/usr/bin/env bash
# gesten-e2e.sh [schritt …] – Ende-zu-Ende-Test des Gestendienstes zenos-gesten im Testcontainer (als root).
#
# Ohne echtes Touchpad: virtuelle Geräte über uinput (test/container/gesten/touchpad_uinput.py, python3-libevdev). Neue
# Knoten erscheinen im /dev des Containers nicht von selbst (tmpfs); das Skript legt sie mit mknod an. udev ist im
# Testbild maskiert; das Skript startet systemd-udevd von Hand und stösst nur die eigenen Geräte an (die Geräte der VM
# bleiben unberührt).
# labwc läuft wie auf dem Pi in einer Sitzung auf seat0 (über PAM gestellt) und öffnet die Geräte über logind
# (LIBSEAT_BACKEND=logind, WLR_BACKENDS=headless,libinput). Damit logind seat0 ohne VT führt und keine Konsole der VM
# umstellt, liegt /dev/tty0 während des Tests beiseite (logind neu gestartet); «aufraeumen» stellt es zurück.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, ~/zenOS auf dem Stand dieses Codes):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-gesten-e2e
#   docker exec zenos-gesten-e2e bash -c 'apt-get update -qq && apt-get install -y -qq python3-libevdev'
# Dann: docker exec zenos-gesten-e2e bash /home/tester/zenOS/test/container/gesten-e2e.sh [schritt …]
# Die Schritte bauen aufeinander auf; ohne Angabe laufen alle (rund 10 Minuten, vor allem install.sh).
#
#   geraete      udev von Hand, virtuelles Touchpad, Tastatur und Touchpad mit Tasten (noch ohne Regel: root:input)
#   install      install.sh zweimal als tester (der zweite Lauf ohne Änderung): Benutzer, Regel, Dienst. Danach gehört
#                das Touchpad root:zenos-gesten 0640, Tastatur und Touchpad mit Tasten bleiben root:input; tester liest
#                keins davon; der Dienst läuft (gestartet vom Modul bzw. von udev)
#   dienst       läuft als zenos-gesten ohne Capabilities, nur das reine Touchpad offen, systemd-analyze höchstens 0.8,
#                Socket 0666 mit «bereit», ein Klient kann nichts schicken, je Benutzer höchstens 2 Verbindungen,
#                nobody wird sofort getrennt und kann die Oberfläche nicht verdrängen. Tastatur und Touchpad mit Tasten
#                in der Gruppe zenos-gesten: trotzdem abgelehnt (Prüfung im Dienst); ein Touchpad ohne Gesten (1 Slot)
#                bleibt nicht offen. 3 Finger hoch und runter → «oben» und «unten»; 2 Finger, seitlich, schräg, kurz,
#                4 Finger, Tippen → nichts; keine Geste im Journal; ein zweites Touchpad kommt und geht
#   labwc        labwc über logind öffnet das Touchpad trotz 0640, Zeiger und swipe.begin mit 3 Fingern kommen beim
#                Client an, zugleich meldet der Dienst «oben»
#   oberflaeche  zenOS-Oberfläche in dieser Sitzung: verbunden, 3 Finger hoch → Übersicht offen, runter → zu, die
#                anderen Bewegungen → nichts; polkit fragt → Übersicht zu und öffnet weder per Wischen noch per IPC;
#                Menü der Leiste geht zu, wenn die Übersicht öffnet; nach einem Neustart des Dienstes wieder verbunden;
#                gesperrt → nichts
#   rueckweg     Notschalter /etc/xdg/zenos/gesten-aus: install.sh nimmt alles zurück (Touchpad wieder root:input 0660),
#                auch wenn der Messmodus gerade läuft; ohne Schalter richtet es alles wieder ein
#   aufraeumen   Sitzung, Geräte und udev beenden, Knoten weg, /dev/tty0 zurück, logind neu

set -euo pipefail

E2E=/srv/gesten-e2e
TESTER=tester
REPO=/home/$TESTER/zenOS
HILFE=$REPO/test/container/gesten
SOCKET=/run/zenos-gesten/gesten.sock
TTY_BEISEITE=/dev/tty0.zenos-gesten-e2e
ALLE=(geraete install dienst labwc oberflaeche rueckweg aufraeumen)

ok() { printf '  ok  %s\n' "$*"; }
fehler() { printf '  FEHLER  %s\n' "$*" >&2; exit 1; }
schritt() { printf '\n== %s\n' "$*"; }

[[ $EUID == 0 ]] || { echo "gesten-e2e.sh läuft als root im Testcontainer" >&2; exit 2; }
[[ -f /.dockerenv || -n "${container:-}" ]] || { echo "gesten-e2e.sh nur im Testcontainer" >&2; exit 2; }
TESTER_UID=$(id -u "$TESTER")
LAUFZEIT=/run/user/$TESTER_UID
mkdir -p "$E2E"
install -d -o "$TESTER" -g "$TESTER" "$E2E/tester"

als_tester() {
  runuser -u "$TESTER" -- env HOME=/home/$TESTER XDG_RUNTIME_DIR="$LAUFZEIT" LANG=C.UTF-8 "$@"
}

als_nobody() {
  setpriv --reuid=nobody --regid=nogroup --clear-groups -- env -i PATH=/usr/bin:/bin LANG=C.UTF-8 "$@"
}

ipc() { als_tester "$REPO/scripts/bin/zenos-ipc" "$@" 2> /dev/null | tail -n 1; }

# warte_bis SEKUNDEN BEFEHL… – bis BEFEHL gelingt (Takt 0,2 s)
warte_bis() {
  local ende=$((SECONDS + $1))
  shift
  until "$@" > /dev/null 2>&1; do
    (( SECONDS < ende )) || return 1
    sleep 0.2
  done
}

gleich() { [[ "$("${@:2}")" == "$1" ]]; }

zeilen() { # DATEI – Zahl der Zeilen (0, wenn es sie nicht gibt)
  if [[ -f "$1" ]]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}

# --- Geräte -----------------------------------------------------------------

udev_starten() {
  if ! udevadm control --ping > /dev/null 2>&1; then
    /usr/lib/systemd/systemd-udevd --daemon
    warte_bis 10 udevadm control --ping || fehler "systemd-udevd startet nicht"
  fi
}

knoten() { cat "$E2E/$1.knoten"; }
rechte() { stat -c '%U:%G %a' -- "/dev/input/$(knoten "$1")"; }
eigenschaft() { udevadm info --query=property --property="$2" --value "/sys/class/input/$(knoten "$1")"; }

# geraet_anlegen NAME ART [OPTION…] – virtuelles Gerät im Hintergrund, Knoten anlegen, udev «add»
geraet_anlegen() {
  local name=$1 art=$2 knoten="" nummer i
  rm -f "$E2E/$name.fifo" "$E2E/$name.log"
  mkfifo -m 0600 "$E2E/$name.fifo"
  setsid python3 "$HILFE/touchpad_uinput.py" "$E2E/$name.fifo" --art "$art" "${@:3}" > "$E2E/$name.log" 2>&1 \
    < /dev/null &
  echo "$!" > "$E2E/$name.pid"
  for i in $(seq 1 50); do
    knoten=$(sed -n 's|^geraet /dev/input/\(event[0-9]*\) .*|\1|p' "$E2E/$name.log")
    [[ -n "$knoten" ]] && break
    sleep 0.1
  done
  [[ -n "$knoten" ]] || { cat "$E2E/$name.log" >&2; fehler "Gerät $name nicht angelegt"; }
  nummer=$(cat "/sys/class/input/$knoten/dev")
  rm -f "/dev/input/$knoten"
  mknod -m 0600 "/dev/input/$knoten" c "${nummer%%:*}" "${nummer##*:}"
  udevadm trigger --action=add --settle "/sys/class/input/$knoten"
  echo "$knoten" > "$E2E/$name.knoten"
}

# geraet NAME BEFEHL… – Befehl an das Gerät, warten, bis es ihn ausgeführt hat
geraet() {
  local name=$1 vorher
  shift
  vorher=$(grep -c '^fertig ' "$E2E/$name.log" || true)
  printf '%s\n' "$*" > "$E2E/$name.fifo"
  local ende=$((SECONDS + 15))
  until (( $(grep -c '^fertig ' "$E2E/$name.log" || true) > vorher )); do
    (( SECONDS < ende )) || fehler "Gerät $name: «$*» nicht fertig"
    sleep 0.1
  done
  sleep 0.3
}

geraet_entfernen() {
  local name=$1 pid
  [[ -f "$E2E/$name.pid" ]] || return 0
  pid=$(cat "$E2E/$name.pid")
  if kill -0 "$pid" 2> /dev/null; then
    printf 'ende\n' > "$E2E/$name.fifo" &
    warte_bis 5 bash -c "! kill -0 $pid" || kill "$pid" 2> /dev/null || true
  fi
  [[ -f "$E2E/$name.knoten" ]] && rm -f "/dev/input/$(knoten "$name")"
  rm -f "$E2E/$name".{pid,fifo,knoten}
}

schritt_geraete() {
  schritt "geraete: udev von Hand, Touchpad, Tastatur, Touchpad mit Tasten"
  [[ -c /dev/uinput ]] || fehler "/dev/uinput fehlt (privilegierter Container?)"
  python3 -c 'import libevdev' 2> /dev/null || fehler "python3-libevdev fehlt (apt-get install python3-libevdev)"
  udev_starten
  geraet_anlegen tp touchpad
  geraet_anlegen kb tastatur
  geraet_anlegen tk touchpad-tasten
  [[ "$(eigenschaft tp ID_INPUT_TOUCHPAD)" == 1 && -z "$(eigenschaft tp ID_INPUT_KEY)" ]] ||
    fehler "Touchpad: udev sieht kein reines Touchpad"
  [[ "$(eigenschaft kb ID_INPUT_KEYBOARD)" == 1 ]] || fehler "Tastatur: ID_INPUT_KEYBOARD fehlt"
  [[ "$(eigenschaft tk ID_INPUT_TOUCHPAD)" == 1 && "$(eigenschaft tk ID_INPUT_KEY)" == 1 ]] ||
    fehler "Touchpad mit Tasten: ID_INPUT_TOUCHPAD und ID_INPUT_KEY erwartet"
  ok "Touchpad $(knoten tp) ($(rechte tp)), Tastatur $(knoten kb), Touchpad mit Tasten $(knoten tk)"
}

# --- install.sh ---------------------------------------------------------------

install_lauf() { # NAME – install.sh als tester, Ausgabe in $E2E/NAME.log; gibt die Schlusszeile aus
  local rc=0
  als_tester "$REPO/scripts/install.sh" > "$E2E/$1.log" 2>&1 < /dev/null || rc=$?
  (( rc == 0 )) || { tail -n 30 "$E2E/$1.log" >&2; fehler "install.sh ($1) Exit $rc"; }
  grep -E '^zenOS .* installiert' "$E2E/$1.log" | tail -n 1 || true
}

schritt_install() {
  schritt "install: install.sh zweimal, Benutzer, Regel, Dienst"
  loginctl enable-linger "$TESTER"
  udev_starten
  local zeile
  zeile=$(install_lauf install-1)
  ok "erster Lauf: $zeile"
  grep -q '82-gesten' "$E2E/install-1.log" || fehler "Modul 82-gesten lief nicht"
  zeile=$(install_lauf install-2)
  if [[ "$zeile" != *"· 0 Änderungen"* ]]; then
    grep 'geändert:' "$E2E/install-2.log" >&2 || true
    fehler "zweiter Lauf: $zeile"
  fi
  ok "zweiter Lauf: $zeile"

  getent passwd zenos-gesten > /dev/null || fehler "Benutzer zenos-gesten fehlt"
  [[ "$(getent passwd zenos-gesten | cut -d: -f7)" == */nologin ]] || fehler "zenos-gesten hat eine Shell"
  [[ -z "$(getent group zenos-gesten | cut -d: -f4)" ]] || fehler "Gruppe zenos-gesten hat Mitglieder"
  local gruppen
  gruppen=" $(id -nG "$TESTER") "
  if [[ "$gruppen" == *" input "* || "$gruppen" == *" zenos-gesten "* ]]; then
    fehler "$TESTER ist in input oder zenos-gesten"
  fi
  ok "Dienstbenutzer ohne Shell, Gruppe ohne Mitglieder, $TESTER weder in input noch in zenos-gesten"

  [[ "$(rechte tp)" == "root:zenos-gesten 640" ]] || fehler "Touchpad: $(rechte tp) statt root:zenos-gesten 640"
  [[ "$(rechte kb)" == "root:input 660" ]] || fehler "Tastatur: $(rechte kb) statt root:input 660"
  [[ "$(rechte tk)" == "root:input 660" ]] || fehler "Touchpad mit Tasten: $(rechte tk) statt root:input 660"
  ok "Touchpad root:zenos-gesten 640, Tastatur und Touchpad mit Tasten bleiben root:input 660"
  local name
  for name in tp kb tk; do
    if als_tester test -r "/dev/input/$(knoten "$name")"; then fehler "$TESTER kann $(knoten "$name") lesen"; fi
    if als_tester python3 -c 'import os, sys; os.open(sys.argv[1], os.O_RDONLY)' "/dev/input/$(knoten "$name")" \
      2> /dev/null; then fehler "$TESTER öffnet $(knoten "$name")"; fi
  done
  ok "$TESTER kann keinen der drei Knoten öffnen (EACCES)"
  warte_bis 10 systemctl --quiet is-active zenos-gesten.service || fehler "zenos-gesten.service läuft nicht"
  ok "zenos-gesten.service läuft"
}

# --- Dienst -------------------------------------------------------------------

# Klient, der alles vom Socket in DATEI schreibt (eigene Sitzung, kein Job dieser Shell)
leser_starten() { # DATEI
  rm -f "$1"
  setsid runuser -u "$TESTER" -- python3 "$HILFE/klient.py" lesen "$1" > /dev/null 2>&1 < /dev/null &
  warte_bis 5 grep -qx verbunden "$1" || fehler "Klient verbindet nicht"
}
leser_stoppen() {
  pkill -u "$TESTER" -f "gesten/klient.py lesen" 2> /dev/null || true
}

# geste_erwartet DATEI WORT GERAET BEFEHL… – nach dem Befehl genau WORT (oder «nichts») neu in DATEI
geste_erwartet() {
  local datei=$1 wort=$2 name=$3 vorher neu wer
  shift 3
  vorher=$(zeilen "$datei")
  geraet "$name" "$@"
  sleep 0.3
  neu=$(tail -n +"$((vorher + 1))" "$datei" | tr '\n' ' ' | sed 's/ $//')
  case "$name" in
    kb) wer="Tastatur" ;;
    tk) wer="Touchpad mit Tasten" ;;
    *) wer="Touchpad $(knoten "$name")" ;;
  esac
  [[ "${neu:-nichts}" == "$wort" ]] || fehler "$wer «$*»: erwartet «$wort», kam «${neu:-nichts}»"
  ok "$wer «$*» → $wort"
}

schritt_dienst() {
  schritt "dienst: Rechte, Socket, Erkennung, Hotplug"
  local pid status uid gid exposure
  pid=$(systemctl show -p MainPID --value zenos-gesten.service)
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || fehler "kein Hauptprozess"
  status=/proc/$pid/status
  uid=$(id -u zenos-gesten)
  gid=$(getent group zenos-gesten | cut -d: -f3)
  [[ "$(awk '/^Uid:/ { print $2 $3 $4 $5 }' "$status")" == "$uid$uid$uid$uid" ]] ||
    fehler "läuft nicht als zenos-gesten"
  [[ "$(awk '/^Groups:/ { $1 = ""; print }' "$status" | xargs)" == "$gid" ]] ||
    fehler "Zusatzgruppen: $(grep '^Groups:' "$status")"
  [[ "$(awk '/^CapEff:/ { print $2 }' "$status")" == 0000000000000000 &&
    "$(awk '/^CapBnd:/ { print $2 }' "$status")" == 0000000000000000 ]] || fehler "hat Capabilities"
  [[ "$(awk '/^NoNewPrivs:/ { print $2 }' "$status")" == 1 ]] || fehler "NoNewPrivs fehlt"
  ok "läuft als zenos-gesten, nur Gruppe zenos-gesten, ohne Capabilities, NoNewPrivs"
  [[ "$(offene_knoten)" == "/dev/input/$(knoten tp) " ]] || fehler "offene Knoten: «$(offene_knoten)» statt nur dem Touchpad"
  ok "offen ist nur /dev/input/$(knoten tp)"
  exposure=$(systemd-analyze security --no-pager zenos-gesten.service 2> /dev/null |
    sed -n 's/.*Overall exposure level for zenos-gesten.service: \([0-9.]*\).*/\1/p')
  [[ -n "$exposure" ]] || fehler "systemd-analyze security ohne Ergebnis"
  awk -v e="$exposure" 'BEGIN { exit !(e <= 0.8) }' || fehler "systemd-analyze security: $exposure (höchstens 0.8)"
  ok "systemd-analyze security: $exposure"
  [[ "$(cat "/proc/$pid/uid_map" | xargs)" == "0 0 65536" ]] || fehler "PrivateUsers=identity greift nicht"
  ok "eigener Benutzer-Namensraum, uids 0 bis 65535 unverändert (für SO_PEERCRED)"

  [[ "$(stat -c '%U:%G %a' /run/zenos-gesten)" == "zenos-gesten:zenos-gesten 755" ]] ||
    fehler "Ordner /run/zenos-gesten"
  [[ -S "$SOCKET" && "$(stat -c '%U %a' "$SOCKET")" == "zenos-gesten 666" ]] || fehler "Socket $SOCKET"
  [[ "$(stat -c '%U %a' /run/zenos-gesten/bereit)" == "zenos-gesten 644" &&
    "$(cat /run/zenos-gesten/bereit)" == "$pid" ]] || fehler "/run/zenos-gesten/bereit"
  ok "Socket 0666 und «bereit» (PID) in /run/zenos-gesten (zenos-gesten, 0755)"
  [[ "$(als_tester python3 "$HILFE/klient.py" schreiben)" == EPIPE ]] || fehler "ein Klient kann dem Dienst schreiben"
  ok "ein Klient kann nichts schicken (EPIPE)"
  [[ "$(als_tester python3 "$HILFE/klient.py" viele 3)" == "zu offen offen" ]] ||
    fehler "dritte Verbindung desselben Benutzers verdrängt nicht genau seine älteste"
  ok "je Benutzer höchstens 2 Verbindungen: die dritte verdrängt seine älteste"
  install -m 0644 "$HILFE/klient.py" "$E2E/klient.py"
  [[ "$(als_nobody python3 "$E2E/klient.py" viele 1)" == zu ]] || fehler "nobody bleibt verbunden"
  ok "nobody wird sofort getrennt"

  local lesen=$E2E/tester/lesen-dienst
  leser_starten "$lesen"
  # Wie im Befund: nobody verbindet immer wieder, je 8 zugleich; die Oberfläche (hier der Leser) bleibt
  als_nobody python3 "$E2E/klient.py" flut 6 > "$E2E/flut.log" 2>&1 < /dev/null &
  local flut=$!
  sleep 1
  geste_erwartet "$lesen" oben tp swipe3 hoch
  geste_erwartet "$lesen" unten tp swipe3 runter
  wait "$flut" || true
  (( $(cat "$E2E/flut.log" 2> /dev/null || echo 0) > 100 )) || fehler "Flut lief nicht ($(cat "$E2E/flut.log"))"
  if grep -qx getrennt "$lesen"; then fehler "Leser wurde während der Flut getrennt"; fi
  ok "Flut von nobody ($(cat "$E2E/flut.log") Verbindungen): Der Leser bleibt verbunden und bekommt jede Geste"
  geste_erwartet "$lesen" oben tp swipe3 hoch
  geste_erwartet "$lesen" unten tp swipe3 runter
  geste_erwartet "$lesen" oben tp pfad 3 0 -12 0.08
  geste_erwartet "$lesen" nichts tp scroll2 hoch 30
  geste_erwartet "$lesen" nichts tp swipe3 links
  geste_erwartet "$lesen" nichts tp swipe3 rechts
  geste_erwartet "$lesen" nichts tp pfad 3 15 -15 0.3
  geste_erwartet "$lesen" nichts tp swipe3 hoch 4
  geste_erwartet "$lesen" nichts tp swipe4 hoch
  geste_erwartet "$lesen" nichts tp tippen3
  geste_erwartet "$lesen" nichts tp zeiger1 30
  geste_erwartet "$lesen" nichts kb swipe3 hoch
  geste_erwartet "$lesen" nichts tk swipe3 hoch

  # Ein Touchpad mit nur einem Slot: libinput führt es ohne Gesten, der Dienst hält es nicht offen
  geraet_anlegen t1 touchpad --slots 1
  warte_bis 5 enthaelt "$(knoten t1) dazu, ohne Gesten (geschlossen)" journalctl -u zenos-gesten.service -o cat \
    --no-pager || fehler "Touchpad mit einem Slot nicht gemeldet"
  pid=$(systemctl show -p MainPID --value zenos-gesten.service)
  [[ "$(offene_knoten)" == "/dev/input/$(knoten tp) " ]] || fehler "offene Knoten mit Touchpad ohne Gesten: $(offene_knoten)"
  ok "Touchpad ohne Gesten ($(knoten t1), 1 Slot) bleibt nicht offen"
  geraet_entfernen t1

  geraet_anlegen tp2 touchpad
  warte_bis 5 enthaelt "Touchpad $(knoten tp2) dazu" journalctl -u zenos-gesten.service -o cat --no-pager ||
    fehler "zweites Touchpad nicht übernommen"
  ok "zweites Touchpad $(knoten tp2) im laufenden Betrieb übernommen"
  geste_erwartet "$lesen" oben tp2 swipe3 hoch
  local zweites
  zweites=$(knoten tp2)
  geraet_entfernen tp2
  warte_bis 5 enthaelt "$zweites weg" journalctl -u zenos-gesten.service -o cat --no-pager ||
    fehler "zweites Touchpad nicht abgemeldet"
  ok "zweites Touchpad abgemeldet"
  geste_erwartet "$lesen" unten tp swipe3 runter
  leser_stoppen
  local journal
  journal=$(journalctl -u zenos-gesten.service -o cat --no-pager)
  if grep -qwE 'oben|unten' <<< "$journal"; then fehler "Gesten stehen im Journal"; fi
  ok "Journal ohne einzelne Gesten ($(grep -c . <<< "$journal") Zeilen)"
  riegel_pruefen
}

# Befund: Tastaturen hingen nur an der Gruppe des Knotens. Jetzt Tastatur und Touchpad mit Tasten von Hand in die Gruppe
# zenos-gesten (wie durch eine fremde Regel): Der Dienst prüft selbst und lehnt beide ab.
riegel_pruefen() {
  local name lesen=$E2E/tester/lesen-riegel seit
  for name in kb tk; do
    chgrp zenos-gesten "/dev/input/$(knoten "$name")"
    chmod 0640 "/dev/input/$(knoten "$name")"
  done
  seit=$(date '+%Y-%m-%d %H:%M:%S')
  systemctl restart zenos-gesten.service
  warte_bis 10 test -f /run/zenos-gesten/bereit || fehler "Dienst nach Neustart nicht bereit"
  pid=$(systemctl show -p MainPID --value zenos-gesten.service)
  [[ "$(offene_knoten)" == "/dev/input/$(knoten tp) " ]] ||
    fehler "falsche Gruppe: offen sind «$(offene_knoten)» statt nur dem Touchpad"
  for name in kb tk; do
    enthaelt "$(knoten "$name") abgelehnt: kein reines Touchpad" journalctl -u zenos-gesten.service -o cat \
      --no-pager --since "$seit" || fehler "$(knoten "$name") nicht als abgelehnt gemeldet"
  done
  ok "Tastatur und Touchpad mit Tasten in der Gruppe zenos-gesten: abgelehnt (EACCES), nur das Touchpad offen"
  leser_starten "$lesen"
  geste_erwartet "$lesen" nichts tk swipe3 hoch
  geste_erwartet "$lesen" oben tp swipe3 hoch
  leser_stoppen
  for name in kb tk; do
    chgrp input "/dev/input/$(knoten "$name")"
    chmod 0660 "/dev/input/$(knoten "$name")"
  done
  systemctl restart zenos-gesten.service
  warte_bis 10 test -f /run/zenos-gesten/bereit || fehler "Dienst nach Neustart nicht bereit"
}

# Offene Eingabeknoten des Dienstes (PID in $pid), durch Leerzeichen getrennt
offene_knoten() {
  local fd ziel liste=""
  for fd in "/proc/$pid/fd"/*; do
    ziel=$(readlink -- "$fd" 2> /dev/null) || continue
    [[ "$ziel" == /dev/input/* ]] && liste+="$ziel "
  done
  printf '%s' "$liste"
}

enthaelt() { # MUSTER BEFEHL… – kommt MUSTER in der Ausgabe vor (ohne Pipe, wegen pipefail)
  local muster=$1 text
  shift
  text=$("$@" 2> /dev/null) || true
  grep -qF -- "$muster" <<< "$text"
}

# --- Sitzung auf seat0 mit labwc über logind ------------------------------------

seat_ohne_vt() {
  if [[ -e /dev/tty0 ]]; then
    mv /dev/tty0 "$TTY_BEISEITE"
    systemctl restart systemd-logind
  fi
  loginctl enable-linger "$TESTER"
  warte_bis 10 test -S "$LAUFZEIT/bus" || fehler "Sitzungsbus von $TESTER fehlt"
}

# sitzung_starten UNIT STARTBEFEHL – labwc in einer über PAM gestellten Sitzung auf seat0, Protokoll $E2E/UNIT.log
sitzung_starten() {
  local unit=$1 start=$2 i
  install -d -o "$TESTER" -g "$TESTER" "$E2E/labwc"
  [[ -f "$E2E/labwc/rc.xml" ]] || printf '<?xml version="1.0"?>\n<labwc_config />\n' > "$E2E/labwc/rc.xml"
  systemctl stop "$unit.service" 2> /dev/null || true
  systemctl reset-failed "$unit.service" 2> /dev/null || true
  systemd-run --quiet --unit="$unit" -p PAMName=login -p User="$TESTER" -p WorkingDirectory=/home/$TESTER \
    -p Environment=XDG_SEAT=seat0 -p Environment=XDG_SESSION_CLASS=user -p Environment=XDG_SESSION_TYPE=wayland \
    -p Environment=WLR_BACKENDS=headless,libinput -p Environment=LIBSEAT_BACKEND=logind \
    -p Environment=WLR_RENDERER=pixman -p Environment=WLR_LIBINPUT_NO_DEVICES=1 \
    -p Environment=QT_QUICK_BACKEND=software -p Environment=QT_QPA_PLATFORM=wayland \
    -p Environment=XDG_CURRENT_DESKTOP=labwc:wlroots -p Environment=ZENOS_CODE="$REPO" \
    -p Environment=DBUS_SESSION_BUS_ADDRESS=unix:path="$LAUFZEIT/bus" \
    -p StandardOutput=file:"$E2E/$unit.log" -p StandardError=inherit \
    /usr/bin/labwc -d -C "$E2E/labwc" -s "$start"
  for i in $(seq 1 50); do
    loginctl list-sessions --json=short | jq -e --arg u "$TESTER" \
      '.[] | select(.seat == "seat0" and .user == $u and .class == "user")' > /dev/null && break
    sleep 0.2
  done
  (( i < 50 )) || fehler "keine Sitzung auf seat0"
}

sitzung_aktiv() {
  local id
  id=$(loginctl list-sessions --json=short | jq -r --arg u "$TESTER" \
    '.[] | select(.seat == "seat0" and .user == $u and .class == "user") | .session' | head -n 1)
  [[ "$(loginctl show-session "$id" -p Active --value)" == yes ]]
}

schritt_labwc() {
  schritt "labwc: über logind trotz 0640, Zeiger und Geste beim Client, Dienst liest mit"
  seat_ohne_vt
  local log=$E2E/e2e-gesten-labwc.log pid lesen=$E2E/tester/lesen-labwc vorher_zeiger vorher_geste
  install -m 0644 "$HILFE/beobachter.qml" "$E2E/beobachter.qml"
  printf '#!/bin/sh\nexport WAYLAND_DEBUG=client\nexec quickshell --no-color -p %s/beobachter.qml\n' "$E2E" \
    > "$E2E/beobachter.sh"
  chmod 0755 "$E2E/beobachter.sh"
  sitzung_starten e2e-gesten-labwc "$E2E/beobachter.sh"
  sitzung_aktiv || fehler "Sitzung auf seat0 ist nicht aktiv"
  warte_bis 15 grep -q "Seat opened with backend 'logind'" "$log" || fehler "labwc ohne logind ($log)"
  warte_bis 15 grep -q "configuring input device zenOS Test Touchpad ($(knoten tp))" "$log" ||
    fehler "labwc hat das Touchpad nicht geöffnet"
  warte_bis 15 grep -q 'get_swipe_gesture' "$log" || fehler "Client bindet keine Wischgesten"
  pid=$(systemctl show -p MainPID --value e2e-gesten-labwc.service)
  enthaelt "/dev/input/$(knoten tp)" ls -l "/proc/$pid/fd" || fehler "labwc hält das Touchpad nicht offen"
  ok "labwc öffnet das Touchpad über logind ($(rechte tp)), obwohl $TESTER es nicht lesen darf"
  sleep 1
  vorher_zeiger=$(grep -c 'wl_pointer#[0-9]*\.motion' "$log" || true)
  geraet tp zeiger1 30
  (( $(grep -c 'wl_pointer#[0-9]*\.motion' "$log" || true) > vorher_zeiger )) || fehler "kein Zeiger beim Client"
  ok "Zeiger bewegt sich ($(( $(grep -c 'wl_pointer#[0-9]*\.motion' "$log" || true) - vorher_zeiger )) Ereignisse)"
  leser_starten "$lesen"
  vorher_geste=$(grep -c 'swipe_v1#[0-9]*\.begin(.*, 3)' "$log" || true)
  geste_erwartet "$lesen" oben tp swipe3 hoch
  (( $(grep -c 'swipe_v1#[0-9]*\.begin(.*, 3)' "$log" || true) > vorher_geste )) ||
    fehler "labwc reicht die Geste nicht mehr weiter"
  ok "labwc schickt dem Client weiter swipe.begin mit 3 Fingern (kein Grab)"
  leser_stoppen
  systemctl stop e2e-gesten-labwc.service
}

# --- Oberfläche ------------------------------------------------------------------

uebersicht_ist() { [[ "$(ipc uebersicht status)" == "$1" ]]; }

# oberflaeche_geste WORT|nichts ERWARTET BEFEHL… – nach der Bewegung ist die Übersicht ERWARTET (offen/zu)
oberflaeche_geste() {
  local erwartet=$1
  shift
  geraet tp "$@"
  if [[ "$erwartet" == offen ]]; then
    warte_bis 3 uebersicht_ist offen || fehler "«$*»: Übersicht nicht offen"
  else
    sleep 0.6
    warte_bis 3 uebersicht_ist zu || fehler "«$*»: Übersicht nicht zu"
  fi
  ok "«$*» → Übersicht $erwartet"
}

schritt_oberflaeche() {
  schritt "oberflaeche: Übersicht mit drei Fingern, Neustart des Dienstes, Sperre"
  seat_ohne_vt
  local log=$E2E/tester/quickshell.log
  printf '#!/bin/sh\nexec quickshell --no-color -p %s/shell/shell.qml > %s 2>&1\n' "$REPO" "$log" > "$E2E/innen.sh"
  chmod 0755 "$E2E/innen.sh"
  rm -f "$log"
  # Wie zenos-sitzung: Wer sich gerade anmeldet, ist nicht gesperrt (ein früherer Lauf endete gesperrt)
  rm -f "$LAUFZEIT/zenos/gesperrt"
  sitzung_starten e2e-gesten-oberflaeche "$E2E/innen.sh"
  warte_bis 90 grep -q 'Configuration Loaded' "$log" || { tail -n 30 "$log" >&2; fehler "Oberfläche lädt nicht"; }
  warte_bis 30 ipc einrichtung status || fehler "Oberfläche antwortet nicht auf zenos-ipc"
  ipc einrichtung schliessen > /dev/null || true
  warte_bis 10 gleich zu ipc einrichtung status || fehler "Einrichtung geht nicht zu"
  warte_bis 10 gleich verbunden ipc gesten status || fehler "Oberfläche nicht mit zenos-gesten verbunden"
  ok "Oberfläche läuft und ist mit zenos-gesten verbunden"
  # Ist an seat0 jemand aktiv, nur er (sd_seat_get_active im Sandkasten): ein anderer gewöhnlicher Benutzer fliegt
  [[ "$(setpriv --reuid=1500 --regid=1500 --clear-groups -- python3 "$E2E/klient.py" viele 1)" == zu ]] ||
    fehler "uid 1500 bleibt verbunden, obwohl $TESTER an seat0 aktiv ist"
  ok "$TESTER ist an seat0 aktiv: ein anderer Benutzer (uid 1500) wird sofort getrennt"
  uebersicht_ist zu || fehler "Übersicht ist schon offen"
  oberflaeche_geste offen swipe3 hoch
  oberflaeche_geste zu swipe3 runter
  oberflaeche_geste zu swipe3 runter
  oberflaeche_geste zu scroll2 hoch 30
  oberflaeche_geste zu swipe3 links
  oberflaeche_geste zu pfad 3 15 -15 0.3
  oberflaeche_geste zu swipe3 hoch 4
  oberflaeche_geste zu swipe4 hoch
  oberflaeche_geste zu tippen3
  ipc uebersicht oeffnen > /dev/null
  warte_bis 3 uebersicht_ist offen || fehler "Übersicht über IPC nicht offen"
  oberflaeche_geste offen swipe3 hoch
  oberflaeche_geste zu swipe3 runter
  polkit_pruefen
  leiste_pruefen

  systemctl restart zenos-gesten.service
  warte_bis 5 gleich getrennt ipc gesten status || true
  warte_bis 40 gleich verbunden ipc gesten status || fehler "nach dem Neustart des Dienstes nicht wieder verbunden"
  ok "nach dem Neustart des Dienstes wieder verbunden"
  oberflaeche_geste offen swipe3 hoch
  ipc uebersicht schliessen > /dev/null
  warte_bis 3 uebersicht_ist zu || fehler "Übersicht geht nicht zu"

  ipc sperre sperren > /dev/null
  warte_bis 10 gleich gesperrt ipc sperre status || fehler "Sperre greift nicht"
  geraet tp swipe3 hoch
  sleep 0.8
  uebersicht_ist zu || fehler "gesperrt: Übersicht geht auf"
  ok "gesperrt: 3 Finger hoch → nichts"

  local warnungen
  warnungen=$(grep -c 'quickshell.io.socket' "$log" || true)
  (( warnungen <= 2 )) || fehler "$warnungen Socket-Meldungen im Protokoll der Oberfläche"
  if grep -E 'qs/dienste/Gesten.qml|dienste/Gesten.qml' "$log" | grep -qiE 'warn|error'; then
    fehler "Warnungen aus Gesten.qml"
  fi
  ok "Protokoll der Oberfläche ruhig ($warnungen Socket-Meldungen, nur vom Neustart)"
  systemctl stop e2e-gesten-oberflaeche.service
  rm -f "$LAUFZEIT/zenos/gesperrt"
}

# Befund: Die Übersicht verdrängte den polkit-Dialog und zeigte Getipptes im Filter. Jetzt: Fragt polkit, geht die
# Übersicht zu und öffnet weder per Wischen noch per IPC; nach dem Dialog wieder wie gewohnt.
polkit_pruefen() {
  command -v pkexec > /dev/null || fehler "pkexec fehlt (kommt mit install.sh, scripts/pakete/sicherheit.txt)"
  warte_bis 10 gleich angemeldet ipc polkit agent || fehler "Oberfläche ist nicht als polkit-Agent angemeldet"
  oberflaeche_geste offen swipe3 hoch
  # pkexec aus der Benutzerinstanz: polkit fragt den Agenten der Sitzung auf seat0
  als_tester systemd-run --user --quiet --collect --unit=e2e-gesten-pkexec pkexec /bin/true
  warte_bis 10 gleich offen ipc polkit status || fehler "polkit fragt nicht"
  warte_bis 3 uebersicht_ist zu || fehler "polkit fragt, die Übersicht bleibt offen"
  ok "polkit fragt → Übersicht zu"
  oberflaeche_geste zu swipe3 hoch
  ipc uebersicht oeffnen > /dev/null
  ipc uebersicht umschalten > /dev/null
  sleep 0.6
  uebersicht_ist zu || fehler "polkit offen: Übersicht öffnet über IPC"
  [[ "$(ipc polkit status)" == offen ]] || fehler "polkit-Dialog ging zu"
  ok "solange polkit fragt: weder Wischen noch IPC öffnet die Übersicht, der Dialog bleibt"
  ipc polkit abbrechen > /dev/null
  warte_bis 10 gleich zu ipc polkit status || fehler "polkit-Anfrage geht nicht zu"
  oberflaeche_geste offen swipe3 hoch
  oberflaeche_geste zu swipe3 runter
}

# Befund: Ein Menü der Leiste (mit WLAN-Passwortfeld) blieb unter der Übersicht offen. Jetzt schliesst es.
leiste_pruefen() {
  ipc leiste menue wlan > /dev/null
  warte_bis 3 gleich system ipc leiste status || fehler "System-Menü geht nicht auf"
  oberflaeche_geste offen swipe3 hoch
  [[ "$(ipc leiste status)" == zu ]] || fehler "Menü der Leiste bleibt unter der Übersicht offen"
  ok "Übersicht öffnet → Menü der Leiste zu"
  oberflaeche_geste zu swipe3 runter
}

# --- Rückweg ------------------------------------------------------------------------

schritt_rueckweg() {
  schritt "rueckweg: Notschalter nimmt alles zurück, ohne Schalter wieder da"
  local zeile uid_dienst
  install -d /etc/xdg/zenos
  uid_dienst=$(id -u zenos-gesten)
  # Befund: Lief der Messmodus noch, scheiterte userdel und install.sh brach ab
  setsid setpriv --reuid=zenos-gesten --regid=zenos-gesten --clear-groups -- \
    python3 -I /opt/zenos/scripts/bin/zenos-gesten --messen > "$E2E/messen.log" 2>&1 < /dev/null &
  warte_bis 10 grep -q Messmodus "$E2E/messen.log" || { cat "$E2E/messen.log" >&2; fehler "Messmodus startet nicht"; }
  ok "Messmodus läuft als zenos-gesten"
  touch /etc/xdg/zenos/gesten-aus
  zeile=$(install_lauf rueckweg-1)
  ok "mit Notschalter: $zeile"
  grep -q 'Prozesse von zenos-gesten beendet' "$E2E/rueckweg-1.log" || fehler "Messmodus nicht beendet"
  if pgrep -u "$uid_dienst" > /dev/null 2>&1; then fehler "es läuft noch ein Prozess als zenos-gesten"; fi
  ok "Messmodus beendet, install.sh lief durch"
  if systemctl --quiet is-active zenos-gesten.service; then fehler "Dienst läuft noch"; fi
  local datei
  for datei in /etc/udev/rules.d/72-zenos-gesten.rules /etc/systemd/system/zenos-gesten.service \
    /etc/sysusers.d/zenos-gesten.conf; do
    [[ ! -e "$datei" ]] || fehler "$datei liegt noch da"
  done
  if getent passwd zenos-gesten > /dev/null || getent group zenos-gesten > /dev/null; then
    fehler "Benutzer oder Gruppe zenos-gesten gibt es noch"
  fi
  [[ "$(rechte tp)" == "root:input 660" ]] || fehler "Touchpad: $(rechte tp) statt root:input 660"
  ok "Dienst, Regel, Einheit, Benutzer und Gruppe weg, Touchpad wieder root:input 660"
  zeile=$(install_lauf rueckweg-2)
  [[ "$zeile" == *"· 0 Änderungen"* ]] || fehler "zweiter Lauf mit Notschalter: $zeile"
  ok "zweiter Lauf mit Notschalter: $zeile"
  rm -f /etc/xdg/zenos/gesten-aus
  zeile=$(install_lauf rueckweg-3)
  ok "ohne Notschalter: $zeile"
  [[ "$(rechte tp)" == "root:zenos-gesten 640" ]] || fehler "Touchpad: $(rechte tp)"
  warte_bis 10 systemctl --quiet is-active zenos-gesten.service || fehler "Dienst läuft nicht wieder"
  ok "wieder eingerichtet: Touchpad root:zenos-gesten 640, Dienst läuft"
}

# --- Aufräumen ------------------------------------------------------------------------

schritt_aufraeumen() {
  schritt "aufraeumen"
  leser_stoppen
  systemctl stop e2e-gesten-labwc.service e2e-gesten-oberflaeche.service 2> /dev/null || true
  local name
  for name in tp tp2 kb tk; do geraet_entfernen "$name"; done
  if udevadm control --ping > /dev/null 2>&1; then udevadm control --exit || true; fi
  rm -f "$LAUFZEIT/zenos/gesperrt"
  if [[ -e "$TTY_BEISEITE" ]]; then
    mv "$TTY_BEISEITE" /dev/tty0
    systemctl restart systemd-logind
  fi
  loginctl enable-linger "$TESTER"
  ok "Sitzungen, Geräte und udev beendet, /dev/tty0 zurück"
}

schritte=("$@")
(( ${#schritte[@]} > 0 )) || schritte=("${ALLE[@]}")
for s in "${schritte[@]}"; do
  case "$s" in
    geraete | install | dienst | labwc | oberflaeche | rueckweg | aufraeumen) "schritt_$s" ;;
    *) echo "gesten-e2e.sh: unbekannter Schritt «$s» (${ALLE[*]})" >&2; exit 2 ;;
  esac
done
printf '\nAlles gut: %s\n' "${schritte[*]}"
