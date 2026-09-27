#!/usr/bin/env bash
# oberflaeche.sh – zenOS-Oberfläche ohne Bildschirm im Testcontainer. Läuft im Container als tester.
#
#   start [--shell <pfad/zu/shell.qml>] [--greeter] [--groesse 1440x900] [--labwc-config <ordner>]
#         startet labwc headless (pixman) und darin Quickshell im Software-Backend.
#         Standard: ~/zenOS/shell/shell.qml, mit --greeter ~/zenOS/shell/greeter.qml.
#         Läuft die Shell aus ~/zenOS, ist ZENOS_CODE=~/zenOS gesetzt.
#   start --sitzung [--groesse 1440x900]
#         wie auf dem Pi: labwc startet über autostart zenos-sitzung.target, die Oberfläche läuft als
#         systemd-Benutzerdienst (zenos-shell, zenos-idle, zenos-kanshi) aus /opt/zenos. Vorher install.sh.
#   bild <name> [<x>,<y> <b>x<h>]   Bildschirmfoto nach /srv/bilder/<name>.png (grim)
#   ipc <ziel> <funktion> [arg…]    quickshell ipc call in die laufende Shell
#   thema hell|dunkel               Erscheinungsbild umschalten (IPC thema setzen, sonst einstellungen.json)
#   starte <programm> [arg…]        Programm in der Sitzung starten (z. B. kitty)
#   tippe <text>                    Text eintippen (wtype), z. B. das Passwort «tester» in die Sperre
#   taste <taste> [<taste>…]        Tasten drücken (wtype -k), z. B. Return, Escape, Tab
#   log [zeilen]                    Ende des Quickshell-Protokolls (mit --sitzung aus dem Journal)
#   status                          läuft etwas?
#   stopp                           Quickshell und labwc beenden (mit --sitzung auch die Dienste)
#
# Protokolle liegen in /srv/oberflaeche, Bilder in /srv/bilder (holen: test/container/holen.sh).

set -euo pipefail

ZUSTAND=/srv/oberflaeche
BILDER=/srv/bilder
REPO=${ZENOS_TEST_REPO:-$HOME/zenOS}
SELBST=$(readlink -f -- "${BASH_SOURCE[0]}")
SITZUNG_DIENSTE=(zenos-shell.service zenos-idle.service zenos-kanshi.service)

XDG_RUNTIME_DIR=/run/user/$(id -u)
DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
WLR_BACKENDS=headless
WLR_RENDERER=pixman
WLR_LIBINPUT_NO_DEVICES=1
QT_QUICK_BACKEND=software
QT_QPA_PLATFORM=wayland
XDG_CURRENT_DESKTOP=labwc:wlroots
XDG_SESSION_TYPE=wayland
export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS WLR_BACKENDS WLR_RENDERER WLR_LIBINPUT_NO_DEVICES \
  QT_QUICK_BACKEND QT_QPA_PLATFORM XDG_CURRENT_DESKTOP XDG_SESSION_TYPE

meldung() { printf 'oberflaeche.sh: %s\n' "$*" >&2; }
hilfe() { sed -n '2,21p' "$SELBST" | sed 's/^# \{0,1\}//'; }

ordner_bereit() {
  local o
  for o in "$ZUSTAND" "$BILDER"; do
    if [[ ! -d "$o" || ! -w "$o" ]]; then sudo install -d -o "$(id -un)" -g "$(id -gn)" "$o"; fi
  done
}

laeuft() { # PIDDATEI
  [[ -r "$ZUSTAND/$1" ]] && kill -0 "$(cat "$ZUSTAND/$1")" 2>/dev/null
}

# «sitzung», wenn die laufende Oberfläche mit start --sitzung kam, sonst «direkt»
modus() {
  if [[ -r "$ZUSTAND/modus" && "$(cat "$ZUSTAND/modus")" == sitzung ]]; then echo sitzung; else echo direkt; fi
}

# PID der laufenden Quickshell (mit --sitzung: Hauptprozess von zenos-shell.service, wechselt bei Neustarts)
qs_pid() {
  local pid
  if [[ "$(modus)" == sitzung ]]; then
    pid=$(systemctl --user show -p MainPID --value zenos-shell.service 2>/dev/null) || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )) || return 1
  else
    [[ -r "$ZUSTAND/quickshell.pid" ]] || return 1
    pid=$(cat "$ZUSTAND/quickshell.pid")
  fi
  kill -0 "$pid" 2>/dev/null || return 1
  printf '%s' "$pid"
}

wayland_setzen() {
  [[ -r "$ZUSTAND/wayland" ]] || { meldung "keine laufende Sitzung (erst: start)"; exit 1; }
  WAYLAND_DISPLAY=$(cat "$ZUSTAND/wayland")
  export WAYLAND_DISPLAY
}

schriften() {
  local fehlt=0 familie
  for familie in "Geist" "Geist Mono" "Instrument Serif"; do
    fc-list : family | grep -qxF -- "$familie" || fehlt=1
  done
  (( fehlt )) || return 0
  if ! compgen -G "$REPO/assets/fonts/*.ttf" >/dev/null; then
    meldung "Schriften fehlen und $REPO/assets/fonts hat keine TTF-Dateien"
    return 0
  fi
  mkdir -p -- "$HOME/.local/share/fonts/zenos-test"
  cp -- "$REPO"/assets/fonts/*.ttf "$HOME/.local/share/fonts/zenos-test/"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null
  echo "Schriften aus $REPO/assets/fonts nach ~/.local/share/fonts/zenos-test kopiert."
}

befehl_start() {
  local shell="" greeter=0 groesse=1440x900 config="" sitzung=0
  while (( $# > 0 )); do
    case "$1" in
      --shell) shell=${2:?--shell braucht einen Pfad}; shift 2 ;;
      --greeter) greeter=1; shift ;;
      --groesse) groesse=${2:?--groesse braucht BxH}; shift 2 ;;
      --labwc-config) config=${2:?--labwc-config braucht einen Ordner}; shift 2 ;;
      --sitzung) sitzung=1; shift ;;
      *) meldung "unbekannte Option «$1»"; exit 2 ;;
    esac
  done
  [[ "$groesse" =~ ^[0-9]+x[0-9]+$ ]] || { meldung "Grösse als BxH, z. B. 1440x900"; exit 2; }
  if (( sitzung )) && [[ -n "$shell$config" || "$greeter" == 1 ]]; then
    meldung "--sitzung startet die installierte Oberfläche (/opt/zenos); --shell, --greeter und --labwc-config gehen damit nicht"
    exit 2
  fi
  ordner_bereit
  if laeuft labwc.pid; then meldung "läuft schon (erst: stopp)"; exit 1; fi
  if (( sitzung )); then
    start_sitzung "$groesse"
    return
  fi

  if [[ -z "$shell" ]]; then
    if (( greeter )); then shell=$REPO/shell/greeter.qml; else shell=$REPO/shell/shell.qml; fi
  fi
  shell=$(readlink -f -- "$shell")
  [[ -f "$shell" ]] || { meldung "Shell-Datei fehlt: $shell"; exit 1; }
  local repo_echt
  repo_echt=$(readlink -f -- "$REPO")
  if [[ "$shell" == "$repo_echt"/* ]]; then
    export ZENOS_CODE=$repo_echt
  else
    unset ZENOS_CODE
  fi

  if [[ -z "$config" ]]; then
    if (( greeter )) && [[ -d "$REPO/system/greeter/labwc" ]]; then
      config=$REPO/system/greeter/labwc
    else
      config=$ZUSTAND/labwc-leer
      mkdir -p -- "$config"
    fi
  fi
  schriften

  rm -f -- "$ZUSTAND"/{wayland,quickshell.pid,labwc.pid,quickshell.log,labwc.log,modus}
  echo direkt > "$ZUSTAND/modus"
  export ZENOS_TEST_SHELL=$shell ZENOS_TEST_GROESSE=$groesse ZENOS_TEST_ZUSTAND=$ZUSTAND
  setsid labwc -C "$config" -s "$SELBST _innen" > "$ZUSTAND/labwc.log" 2>&1 < /dev/null &
  echo "$!" > "$ZUSTAND/labwc.pid"

  local i
  for i in $(seq 1 60); do
    if grep -q 'Configuration Loaded' "$ZUSTAND/quickshell.log" 2>/dev/null; then break; fi
    if (( i > 4 )) && ! laeuft quickshell.pid; then
      meldung "Quickshell läuft nicht. Protokoll:"
      tail -n 40 "$ZUSTAND/quickshell.log" 2>/dev/null >&2 || tail -n 20 "$ZUSTAND/labwc.log" >&2
      exit 1
    fi
    sleep 0.5
  done
  if ! grep -q 'Configuration Loaded' "$ZUSTAND/quickshell.log" 2>/dev/null; then
    meldung "Quickshell hat nach 30 s nicht geladen. Protokoll:"
    tail -n 40 "$ZUSTAND/quickshell.log" >&2 || true
    exit 1
  fi
  sleep 1
  printf 'Läuft: %s · %s · WAYLAND_DISPLAY=%s%s\n' "${shell/#"$HOME"/\~}" "$groesse" \
    "$(cat "$ZUSTAND/wayland")" "${ZENOS_CODE:+ · ZENOS_CODE=${ZENOS_CODE/#"$HOME"/\~}}"
}

# Läuft als Startbefehl in labwc
befehl__innen() {
  local ausgang
  ausgang=$(wlr-randr 2>/dev/null | awk 'NR == 1 { print $1 }')
  wlr-randr --output "${ausgang:-HEADLESS-1}" --custom-mode "$ZENOS_TEST_GROESSE" || true
  printf '%s\n' "$WAYLAND_DISPLAY" > "$ZENOS_TEST_ZUSTAND/wayland"
  echo "$$" > "$ZENOS_TEST_ZUSTAND/quickshell.pid"
  exec quickshell --no-color -p "$ZENOS_TEST_SHELL" > "$ZENOS_TEST_ZUSTAND/quickshell.log" 2>&1
}

# --- Sitzung wie auf dem Pi ------------------------------------------------
#
# labwc läuft mit einem eigenen Konfigurationsordner: Verweise auf alles aus ~/.config/labwc (rc.xml,
# environment, shutdown, menu.xml, themerc-override …) ausser autostart. Das eigene autostart setzt die
# Auflösung und Software-Rendering für die Dienste (kein GPU im Container) und ruft dann das echte
# autostart (system/labwc/autostart), das zenos-sitzung.target startet.

start_sitzung() {
  local groesse=$1 konfig=$ZUSTAND/labwc-sitzung eintrag dienst i
  if ! systemctl --user cat zenos-sitzung.target > /dev/null 2>&1; then
    meldung "zenos-sitzung.target fehlt: erst ./scripts/install.sh (die Sitzung nimmt die Oberfläche aus /opt/zenos)"
    exit 1
  fi
  [[ -e "$HOME/.config/labwc/autostart" ]] ||
    meldung "autostart fehlt in ~/.config/labwc (install.sh), starte zenos-sitzung.target direkt"
  [[ -e "$HOME/.config/quickshell/shell.qml" ]] ||
    meldung "shell.qml fehlt in ~/.config/quickshell (install.sh), zenos-shell.service wird scheitern"

  # Reste eines früheren Laufs
  if systemctl --user --quiet is-active zenos-sitzung.target 2> /dev/null; then
    systemctl --user stop zenos-sitzung.target graphical-session.target 2> /dev/null || true
  fi
  systemctl --user reset-failed "${SITZUNG_DIENSTE[@]}" 2> /dev/null || true
  # Wie zenos-sitzung: wer sich gerade anmeldet, ist nicht gesperrt
  rm -f -- "$XDG_RUNTIME_DIR/zenos/gesperrt"
  schriften

  rm -rf -- "$konfig"
  mkdir -p -- "$konfig"
  for eintrag in "$HOME"/.config/labwc/*; do
    [[ -e "$eintrag" && "$(basename -- "$eintrag")" != autostart ]] || continue
    ln -s -- "$eintrag" "$konfig/"
  done
  printf '#!/bin/sh\n# oberflaeche.sh start --sitzung\nexec %q _autostart\n' "$SELBST" > "$konfig/autostart"

  rm -f -- "$ZUSTAND"/{wayland,quickshell.pid,labwc.pid,quickshell.log,labwc.log,modus,sitzung.beginn}
  echo sitzung > "$ZUSTAND/modus"
  date +%s > "$ZUSTAND/sitzung.beginn"
  unset ZENOS_CODE
  export ZENOS_TEST_GROESSE=$groesse ZENOS_TEST_ZUSTAND=$ZUSTAND
  setsid labwc -C "$konfig" > "$ZUSTAND/labwc.log" 2>&1 < /dev/null &
  echo "$!" > "$ZUSTAND/labwc.pid"

  # Warten, bis die Oberfläche als Dienst läuft und geladen hat
  local geladen=0
  for i in $(seq 1 90); do
    if ! laeuft labwc.pid; then
      meldung "labwc hat sich beendet. Protokoll:"
      tail -n 20 "$ZUSTAND/labwc.log" >&2
      exit 1
    fi
    # grep ohne -q: liest alles, sonst bricht journalctl mit SIGPIPE ab und pipefail meldet einen Fehler
    if sitzung_journal 400 | grep 'Configuration Loaded' > /dev/null; then geladen=1; break; fi
    sleep 0.5
  done
  if (( ! geladen )); then
    meldung "zenos-shell.service hat nach 45 s nicht geladen:"
    systemctl --user --no-pager status zenos-shell.service 2>&1 | head -n 12 >&2 || true
    sitzung_journal 30 >&2
    exit 1
  fi
  sleep 1
  printf 'Sitzung läuft · %s · WAYLAND_DISPLAY=%s\n' "$groesse" "$(cat "$ZUSTAND/wayland" 2>/dev/null)"
  for dienst in zenos-sitzung.target "${SITZUNG_DIENSTE[@]}"; do
    printf '  %-22s %s\n' "$dienst" "$(systemctl --user is-active "$dienst" 2> /dev/null || true)"
  done
}

# Protokoll von zenos-shell.service seit dem Start der Sitzung (alle Neustarts)
sitzung_journal() { # ZEILEN
  local beginn
  beginn=$(cat "$ZUSTAND/sitzung.beginn" 2> /dev/null || echo 0)
  journalctl --user --unit zenos-shell.service --since "@$beginn" --lines "$1" --no-pager --output cat 2> /dev/null
}

# Läuft als autostart in labwc (start --sitzung)
befehl__autostart() {
  local ausgang
  ausgang=$(wlr-randr 2>/dev/null | awk 'NR == 1 { print $1 }')
  wlr-randr --output "${ausgang:-HEADLESS-1}" --custom-mode "$ZENOS_TEST_GROESSE" || true
  printf '%s\n' "$WAYLAND_DISPLAY" > "$ZENOS_TEST_ZUSTAND/wayland"
  # Nur im Container: Quickshell ohne GPU (pixman)
  systemctl --user set-environment QT_QUICK_BACKEND=software || true
  if [[ -r "$HOME/.config/labwc/autostart" ]]; then
    exec sh "$HOME/.config/labwc/autostart"
  fi
  dbus-update-activation-environment --systemd WAYLAND_DISPLAY LABWC_PID XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
  exec systemctl --user start --no-block zenos-sitzung.target
}

sitzung_stoppen() {
  local pid
  systemctl --user stop zenos-sitzung.target graphical-session.target 2> /dev/null || true
  if laeuft labwc.pid; then
    pid=$(cat "$ZUSTAND/labwc.pid")
    kill "$pid" 2> /dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2> /dev/null || break
      sleep 0.25
    done
    if kill -0 "$pid" 2> /dev/null; then kill -9 "$pid" 2> /dev/null || true; fi
  fi
  systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY LABWC_PID XDG_SESSION_ID QT_QUICK_BACKEND 2> /dev/null || true
  # Notfall-Sperre (zen lock ohne Shell) läuft ausserhalb der Dienste
  pkill -u "$(id -u)" -x swaylock 2> /dev/null || true
}

# --- Befehle in die laufende Sitzung ---------------------------------------

befehl_bild() {
  local name=${1:-}
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { meldung "Aufruf: bild <name> [<x>,<y> <b>x<h>]"; exit 2; }
  ordner_bereit
  wayland_setzen
  local ziel="$BILDER/${name%.png}.png"
  if (( $# >= 2 )); then
    grim -g "$2" -- "$ziel"
  else
    grim -- "$ziel"
  fi
  echo "$ziel"
}

# quickshell ipc call mit Fehlererkennung: Quickshell v0.3.1 beendet sich auch bei «Target not found.»
# oder falschen Argumenten mit Exit 0, deshalb zählt zusätzlich die Fehlerausgabe.
ipc_aufruf() {
  local pid rc=0
  pid=$(qs_pid) || { meldung "Quickshell läuft nicht"; return 1; }
  # Quickshell schreibt seine Fehlermeldungen auf stdout
  quickshell ipc --pid "$pid" call "$@" > "$ZUSTAND/ipc.ausgabe" 2>&1 || rc=$?
  if (( rc != 0 )) ||
    grep -qE '^(Target|Function) not found\.|arguments provided|Unable to parse argument|Not ready to accept|Socket Error' \
      "$ZUSTAND/ipc.ausgabe"; then
    sed 's/\x1b\[[0-9;]*m//g' "$ZUSTAND/ipc.ausgabe" >&2
    return 1
  fi
  cat -- "$ZUSTAND/ipc.ausgabe"
}

befehl_ipc() {
  (( $# >= 2 )) || { meldung "Aufruf: ipc <ziel> <funktion> [arg…]"; exit 2; }
  ipc_aufruf "$@"
}

befehl_thema() {
  local modus=${1:-}
  [[ "$modus" == hell || "$modus" == dunkel ]] || { meldung "Aufruf: thema hell|dunkel"; exit 2; }
  if ipc_aufruf thema setzen "$modus" >/dev/null 2>&1; then
    echo "Thema $modus (über IPC)"
  else
    local datei="$HOME/.config/zenos/einstellungen.json"
    mkdir -p -- "$(dirname -- "$datei")"
    python3 - "$datei" "$modus" <<'PY'
import json
import os
import sys

datei, modus = sys.argv[1], sys.argv[2]
try:
    with open(datei, encoding="utf-8") as f:
        daten = json.load(f)
except (OSError, ValueError):
    daten = {}
daten["erscheinungsbild"] = modus
neu = datei + ".neu"
with open(neu, "w", encoding="utf-8") as f:
    json.dump(daten, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(neu, datei)
PY
    echo "Thema $modus (über ~/.config/zenos/einstellungen.json)"
  fi
  sleep 0.6
}

befehl_starte() {
  (( $# >= 1 )) || { meldung "Aufruf: starte <programm> [arg…]"; exit 2; }
  wayland_setzen
  local name
  name=$(basename -- "$1")
  setsid "$@" > "$ZUSTAND/$name.log" 2>&1 < /dev/null &
  echo "$1 gestartet (Protokoll $ZUSTAND/$name.log)"
}

# wtype kennt kein «--»: Text, der mit - beginnt, wäre eine Option
befehl_tippe() {
  (( $# == 1 )) && [[ -n "$1" && "$1" != -* ]] || { meldung "Aufruf: tippe <text> (nicht mit - am Anfang)"; exit 2; }
  wayland_setzen
  wtype "$1"
}

befehl_taste() {
  (( $# >= 1 )) || { meldung "Aufruf: taste <taste> [<taste>…] (z. B. Return, Escape, Tab)"; exit 2; }
  wayland_setzen
  local taste
  for taste in "$@"; do
    [[ "$taste" =~ ^[A-Za-z0-9_]+$ ]] || { meldung "unbekannte Taste «$taste»"; exit 2; }
    wtype -k "$taste"
  done
}

befehl_log() {
  local zeilen=${1:-60}
  [[ "$zeilen" =~ ^[0-9]+$ ]] || { meldung "Aufruf: log [zeilen]"; exit 2; }
  if [[ "$(modus)" == sitzung ]]; then
    sitzung_journal "$zeilen"
  else
    tail -n "$zeilen" "$ZUSTAND/quickshell.log"
  fi
}

befehl_status() {
  local pid dienst art=""
  [[ "$(modus)" != sitzung ]] || art=" · Sitzung (systemd-Benutzerdienste)"
  if laeuft labwc.pid; then
    printf 'labwc läuft (PID %s), WAYLAND_DISPLAY=%s%s\n' "$(cat "$ZUSTAND/labwc.pid")" \
      "$(cat "$ZUSTAND/wayland" 2>/dev/null)" "$art"
  else
    echo "labwc läuft nicht"
  fi
  if pid=$(qs_pid); then
    printf 'Quickshell läuft (PID %s)\n' "$pid"
  else
    echo "Quickshell läuft nicht"
  fi
  if [[ "$(modus)" == sitzung ]]; then
    for dienst in zenos-sitzung.target "${SITZUNG_DIENSTE[@]}"; do
      printf '  %-22s %s\n' "$dienst" "$(systemctl --user is-active "$dienst" 2> /dev/null || true)"
    done
  fi
}

befehl_stopp() {
  local datei pid
  if [[ "$(modus)" == sitzung ]]; then
    sitzung_stoppen
  else
    for datei in quickshell.pid labwc.pid; do
      laeuft "$datei" || continue
      pid=$(cat "$ZUSTAND/$datei")
      kill "$pid" 2>/dev/null || true
      for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
      done
      if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
    done
  fi
  rm -f -- "$ZUSTAND"/{wayland,quickshell.pid,labwc.pid,modus,sitzung.beginn}
  echo "Gestoppt."
}

befehl=${1:-}
(( $# == 0 )) || shift
case "$befehl" in
  start | bild | ipc | thema | starte | tippe | taste | log | status | stopp | _innen | _autostart) "befehl_${befehl}" "$@" ;;
  "" | -h | --hilfe | hilfe) hilfe ;;
  *) meldung "unbekannter Befehl «$befehl»"; hilfe >&2; exit 2 ;;
esac
