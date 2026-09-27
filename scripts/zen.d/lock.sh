#!/usr/bin/env bash
# hilfe: lock – Sitzung sperren (auch per SSH)
# Setzt den Marker $XDG_RUNTIME_DIR/zenos/gesperrt und bittet die Oberfläche zu sperren
# (zenos-ipc sperre sperren). Antwortet sie nicht, startet zen lock sie neu (zenos-shell.service);
# sie sperrt dann über den Marker. Hilft auch das nicht, sperrt swaylock als Notfall-Sperre
# (Farben aus den Tokens, ohne Inhalte). Funktioniert auch ohne Sitzungsumgebung, z. B. per SSH.
# Exit 0 gesperrt · 1 Sperren fehlgeschlagen · 2 falscher Aufruf · 3 keine grafische Sitzung
# shellcheck shell=bash

befehl_lock() {
  if (( $# > 0 )); then
    zen_fehler "zen lock kennt keine Argumente"
    return 2
  fi
  if (( EUID == 0 )); then
    zen_fehler "zen lock läuft als normaler Benutzer, nicht als root"
    return 2
  fi

  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$EUID} anzeige
  if [[ ! -d "$laufzeit" ]]; then
    zen_fehler "Keine laufende Sitzung für diesen Benutzer – nichts zu sperren."
    return 3
  fi
  export XDG_RUNTIME_DIR=$laufzeit
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$laufzeit/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$laufzeit/bus"
  fi

  if ! anzeige=$(_lock_anzeige); then
    zen_fehler "Keine grafische Sitzung gefunden – nichts zu sperren."
    return 3
  fi

  # Der Marker zuerst: Startet die Oberfläche neu, sperrt sie damit sofort.
  _lock_marker_setzen

  if _lock_notfall_aktiv; then
    echo "Bereits gesperrt (Notfall-Sperre)."
    return 0
  fi
  if _lock_ipc sperre sperren >/dev/null && _lock_warten 3; then
    echo "Gesperrt."
    return 0
  fi
  if _lock_shell_neu_starten && _lock_warten 12; then
    echo "Gesperrt (Oberfläche neu gestartet)."
    return 0
  fi
  _lock_notfall "$anzeige"
}

# Name des Wayland-Sockets der Sitzung: aus der Umgebung, aus der systemd-Benutzerinstanz (per SSH)
# oder der erste Socket im Laufzeitordner.
_lock_anzeige() {
  local name pfad
  local -a kandidaten=()
  [[ -z "${WAYLAND_DISPLAY:-}" ]] || kandidaten+=("$WAYLAND_DISPLAY")
  name=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' | head -n 1) || name=""
  [[ -z "$name" ]] || kandidaten+=("$name")
  for pfad in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
    [[ "$pfad" == *.lock ]] || kandidaten+=("${pfad##*/}")
  done
  for name in "${kandidaten[@]}"; do
    pfad=$name
    [[ "$pfad" == /* ]] || pfad=$XDG_RUNTIME_DIR/$name
    if [[ -S "$pfad" ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  return 1
}

# Ein vorhandener Marker bleibt unverändert: Sein Zeitpunkt ist der Beginn der Sperre (die Oberfläche
# lädt nach dem Entsperren neu, wenn sich ihre Dateien seither geändert haben).
_lock_marker_setzen() {
  local ordner=$XDG_RUNTIME_DIR/zenos
  [[ ! -e "$ordner/gesperrt" ]] || return 0
  [[ -d "$ordner" ]] || mkdir -m 0700 -- "$ordner" 2>/dev/null || true
  if ! date -Iseconds 2>/dev/null > "$ordner/gesperrt"; then
    zen_hinweis "Hinweis: Marker $ordner/gesperrt liess sich nicht setzen."
  fi
}

_lock_ipc() {
  local ipc=$ZEN_SKRIPTE/bin/zenos-ipc
  [[ -x "$ipc" ]] || return 1
  timeout 5 "$ipc" "$@" 2>/dev/null
}

# Wartet bis zu N Sekunden, bis die Oberfläche «gesperrt» meldet (labwc hat die Sperre bestätigt).
_lock_warten() {
  local ende=$((SECONDS + $1)) status
  while true; do
    status=$(_lock_ipc sperre status) || status=""
    if [[ "${status//[[:space:]]/}" == gesperrt ]]; then return 0; fi
    (( SECONDS < ende )) || return 1
    sleep 0.25
  done
}

_lock_shell_neu_starten() {
  local zustand
  zustand=$(systemctl --user show -p LoadState --value zenos-shell.service 2>/dev/null) || return 1
  [[ "$zustand" == loaded ]] || return 1
  echo "Die Oberfläche antwortet nicht, starte sie neu …" >&2
  # Nach vielen Abstürzen hält systemd den Dienst an (StartLimit); zen lock hebt das auf
  systemctl --user reset-failed zenos-shell.service 2>/dev/null || true
  timeout 30 systemctl --user restart zenos-shell.service 2>/dev/null
}

_lock_notfall_aktiv() { pgrep -u "$EUID" -x swaylock >/dev/null 2>&1; }

# Letzte Stufe: swaylock sperrt, damit die Sperre nie ausfällt. Es läuft als eigene Einheit der
# systemd-Benutzerinstanz, damit es weder mit der SSH-Verbindung noch mit zenos-idle endet.
_lock_notfall() {
  local anzeige=$1 programm rc=0
  local -a argumente=()
  if ! programm=$(command -v swaylock); then
    zen_fehler "Sperren fehlgeschlagen: Die Oberfläche antwortet nicht, und swaylock fehlt."
    return 1
  fi
  echo "Die Oberfläche antwortet nicht, sperre mit swaylock (Notfall-Sperre) …" >&2
  mapfile -t argumente < <(_lock_swaylock_argumente)

  if systemctl --user show-environment >/dev/null 2>&1; then
    # Type=forking: systemd-run kehrt zurück, sobald swaylock gesperrt hat und sich ablöst
    timeout 20 systemd-run --user --quiet --collect --unit=zenos-notfallsperre \
      --property=Type=forking --setenv=WAYLAND_DISPLAY="$anzeige" \
      -- "$programm" --daemonize "${argumente[@]}" || rc=$?
  else
    WAYLAND_DISPLAY=$anzeige timeout 20 setsid "$programm" --daemonize "${argumente[@]}" \
      < /dev/null > /dev/null 2>&1 || rc=$?
  fi
  if (( rc != 0 )); then
    zen_fehler "Sperren fehlgeschlagen: swaylock konnte nicht sperren (Exit $rc)."
    return 1
  fi
  WAYLAND_DISPLAY=$anzeige "$ZEN_SKRIPTE/bin/zenos-1password-sperren" > /dev/null 2>&1 || true
  echo "Gesperrt (Notfall-Sperre mit swaylock; die Oberfläche hat nicht geantwortet)."
}

# Argumente für swaylock: Farben des dunklen Erscheinungsbilds aus tokens.json, Akzent wie zuletzt
# von zenos-thema übertragen. Eine Benutzerkonfiguration von swaylock gilt nicht, Bilder gibt es keine.
# Fehlt ein Token, bleibt die Farbe von swaylock.
_lock_swaylock_argumente() {
  printf '%s\n' --config /dev/null --ignore-empty-password --show-failed-attempts \
    --indicator-idle-visible --indicator-caps-lock --hide-keyboard-layout \
    --indicator-radius 64 --indicator-thickness 6 --line-uses-inside --separator-color 00000000
  python3 - "$ZEN_WURZEL/shell/theme/tokens.json" "$HOME/.local/state/zenos/thema.json" <<'PY' || true
import json
import re
import sys


def lesen(pfad):
    try:
        with open(pfad, encoding="utf-8") as f:
            daten = json.load(f)
    except (OSError, ValueError):
        return {}
    return daten if isinstance(daten, dict) else {}


tokens = lesen(sys.argv[1])
farben = tokens.get("farben") or {}
dunkel = farben.get("dunkel") or {}
akzente = farben.get("akzente") or {}
signal = farben.get("signal") or {}
name = lesen(sys.argv[2]).get("akzent")
if name not in akzente:
    name = farben.get("standardAkzent")

werte = {
    "grund": dunkel.get("grund"),
    "flaeche": dunkel.get("flaeche"),
    "rand": dunkel.get("eingabeRand"),
    "text": dunkel.get("text"),
    "gedaempft": dunkel.get("gedaempft"),
    "akzent": (akzente.get(name) or {}).get("dunkel"),
    "fehler": (signal.get("fehler") or {}).get("dunkel"),
    "warnung": (signal.get("warnung") or {}).get("dunkel"),
}
werte = {k: str(v)[1:].upper() for k, v in werte.items() if re.fullmatch(r"#[0-9A-Fa-f]{6}", str(v or ""))}

zuordnung = [
    ("--color", "grund"),
    ("--inside-color", "flaeche"), ("--inside-clear-color", "flaeche"), ("--inside-ver-color", "flaeche"),
    ("--inside-wrong-color", "flaeche"), ("--inside-caps-lock-color", "flaeche"),
    ("--ring-color", "rand"), ("--ring-clear-color", "gedaempft"), ("--ring-ver-color", "akzent"),
    ("--ring-wrong-color", "fehler"), ("--ring-caps-lock-color", "warnung"),
    ("--key-hl-color", "akzent"), ("--bs-hl-color", "gedaempft"),
    ("--caps-lock-key-hl-color", "akzent"), ("--caps-lock-bs-hl-color", "gedaempft"),
    ("--text-color", "text"), ("--text-clear-color", "gedaempft"), ("--text-ver-color", "text"),
    ("--text-wrong-color", "fehler"), ("--text-caps-lock-color", "warnung"),
]
ausgabe = []
for option, schluessel in zuordnung:
    if schluessel in werte:
        ausgabe += [option, werte[schluessel]]
schrift = (tokens.get("schrift") or {}).get("text")
if isinstance(schrift, str) and schrift:
    ausgabe += ["--font", schrift, "--font-size", "16"]
print("\n".join(ausgabe))
PY
}
