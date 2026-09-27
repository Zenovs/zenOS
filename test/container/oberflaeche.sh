#!/usr/bin/env bash
# oberflaeche.sh – zenOS-Oberfläche ohne Bildschirm im Testcontainer. Läuft im Container als tester.
#
#   start [--shell <pfad/zu/shell.qml>] [--greeter] [--groesse 1440x900] [--labwc-config <ordner>]
#         startet labwc headless (pixman) und darin Quickshell im Software-Backend.
#         Standard: ~/zenOS/shell/shell.qml, mit --greeter ~/zenOS/shell/greeter.qml.
#         Läuft die Shell aus ~/zenOS, ist ZENOS_CODE=~/zenOS gesetzt.
#   bild <name> [<x>,<y> <b>x<h>]   Bildschirmfoto nach /srv/bilder/<name>.png (grim)
#   ipc <ziel> <funktion> [arg…]    quickshell ipc call in die laufende Shell
#   thema hell|dunkel               Erscheinungsbild umschalten (IPC thema setzen, sonst einstellungen.json)
#   starte <programm> [arg…]        Programm in der Sitzung starten (z. B. kitty)
#   log [zeilen]                    Ende des Quickshell-Protokolls
#   status                          läuft etwas?
#   stopp                           Quickshell und labwc beenden
#
# Protokolle liegen in /srv/oberflaeche, Bilder in /srv/bilder (holen: test/container/holen.sh).

set -euo pipefail

ZUSTAND=/srv/oberflaeche
BILDER=/srv/bilder
REPO=${ZENOS_TEST_REPO:-$HOME/zenOS}
SELBST=$(readlink -f -- "${BASH_SOURCE[0]}")

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
hilfe() { sed -n '2,17p' "$SELBST" | sed 's/^# \{0,1\}//'; }

ordner_bereit() {
  local o
  for o in "$ZUSTAND" "$BILDER"; do
    if [[ ! -d "$o" || ! -w "$o" ]]; then sudo install -d -o "$(id -un)" -g "$(id -gn)" "$o"; fi
  done
}

laeuft() { # PIDDATEI
  [[ -r "$ZUSTAND/$1" ]] && kill -0 "$(cat "$ZUSTAND/$1")" 2>/dev/null
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
  local shell="" greeter=0 groesse=1440x900 config=""
  while (( $# > 0 )); do
    case "$1" in
      --shell) shell=${2:?--shell braucht einen Pfad}; shift 2 ;;
      --greeter) greeter=1; shift ;;
      --groesse) groesse=${2:?--groesse braucht BxH}; shift 2 ;;
      --labwc-config) config=${2:?--labwc-config braucht einen Ordner}; shift 2 ;;
      *) meldung "unbekannte Option «$1»"; exit 2 ;;
    esac
  done
  [[ "$groesse" =~ ^[0-9]+x[0-9]+$ ]] || { meldung "Grösse als BxH, z. B. 1440x900"; exit 2; }
  ordner_bereit
  if laeuft labwc.pid; then meldung "läuft schon (erst: stopp)"; exit 1; fi

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

  rm -f -- "$ZUSTAND"/{wayland,quickshell.pid,labwc.pid,quickshell.log,labwc.log}
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
  exec quickshell -p "$ZENOS_TEST_SHELL" > "$ZENOS_TEST_ZUSTAND/quickshell.log" 2>&1
}

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
  laeuft quickshell.pid || { meldung "Quickshell läuft nicht"; return 1; }
  local rc=0
  # Quickshell schreibt seine Fehlermeldungen auf stdout
  quickshell ipc --pid "$(cat "$ZUSTAND/quickshell.pid")" call "$@" > "$ZUSTAND/ipc.ausgabe" 2>&1 || rc=$?
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

befehl_log() {
  local zeilen=${1:-60}
  [[ "$zeilen" =~ ^[0-9]+$ ]] || { meldung "Aufruf: log [zeilen]"; exit 2; }
  tail -n "$zeilen" "$ZUSTAND/quickshell.log"
}

befehl_status() {
  if laeuft labwc.pid; then
    printf 'labwc läuft (PID %s), WAYLAND_DISPLAY=%s\n' "$(cat "$ZUSTAND/labwc.pid")" "$(cat "$ZUSTAND/wayland" 2>/dev/null)"
  else
    echo "labwc läuft nicht"
  fi
  if laeuft quickshell.pid; then
    printf 'Quickshell läuft (PID %s)\n' "$(cat "$ZUSTAND/quickshell.pid")"
  else
    echo "Quickshell läuft nicht"
  fi
}

befehl_stopp() {
  local datei pid
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
  rm -f -- "$ZUSTAND"/{wayland,quickshell.pid,labwc.pid}
  echo "Gestoppt."
}

befehl=${1:-}
(( $# == 0 )) || shift
case "$befehl" in
  start | bild | ipc | thema | starte | log | status | stopp | _innen) "befehl_${befehl}" "$@" ;;
  "" | -h | --hilfe | hilfe) hilfe ;;
  *) meldung "unbekannter Befehl «$befehl»"; hilfe >&2; exit 2 ;;
esac
