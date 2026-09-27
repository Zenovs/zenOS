#!/usr/bin/env bash
# 60-mitteilungen: Quickshell ist der einzige Mitteilungsdienst (org.freedesktop.Notifications)
# shellcheck shell=bash

pruefe_mitteilungen() {
  abschnitt "Mitteilungen"
  _mitteilungen_fremde_pakete
  _mitteilungen_dbus_dateien
  _mitteilungen_sitzung
  _mitteilungen_standard
}

# Andere Mitteilungsdienste als Paket
_mitteilungen_fremde_pakete() {
  local paket gefunden=()
  for paket in mako-notifier dunst notification-daemon xfce4-notifyd swaync fnott notify-osd \
    lxqt-notificationd; do
    if dpkg-query -W -f='${Status}' "$paket" 2>/dev/null | grep -q '^install ok installed$'; then
      gefunden+=("$paket")
    fi
  done
  if (( ${#gefunden[@]} == 0 )); then
    ok "Kein anderer Mitteilungsdienst installiert"
  else
    warnung "Anderer Mitteilungsdienst installiert: ${gefunden[*]} (kann Quickshell den Dienst wegnehmen; entfernen mit: sudo apt remove ${gefunden[*]})"
  fi
}

# D-Bus-Aktivierung: Startet ein anderer Dienst automatisch, sobald eine App vor der
# Shell eine Mitteilung schickt, belegt er den Namen und Quickshell kommt nicht mehr dran.
_mitteilungen_dbus_dateien() {
  local datei treffer=()
  for datei in /usr/share/dbus-1/services/*.service /usr/local/share/dbus-1/services/*.service \
    "$HOME"/.local/share/dbus-1/services/*.service; do
    [[ -f "$datei" ]] || continue
    if grep -qx 'Name=org.freedesktop.Notifications' "$datei" 2>/dev/null; then
      treffer+=("$datei")
    fi
  done
  if (( ${#treffer[@]} == 0 )); then
    ok "Kein anderer Dienst startet automatisch für org.freedesktop.Notifications"
  else
    warnung "Automatischer Start eines anderen Mitteilungsdienstes möglich: ${treffer[*]}"
  fi
}

# In einer laufenden Sitzung: gehört der Name Quickshell?
_mitteilungen_sitzung() {
  local laufzeit bus antwort pid exe name
  laufzeit=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  bus=$laufzeit/bus
  if ! command -v busctl >/dev/null 2>&1; then
    hinweis "busctl fehlt, Mitteilungsdienst der Sitzung nicht prüfbar"
    return 0
  fi
  if [[ ! -S "$bus" ]]; then
    hinweis "Keine Sitzung erreichbar, Mitteilungsdienst nicht geprüft"
    return 0
  fi
  # GetConnectionUnixProcessID startet keinen Dienst (anders als ein Aufruf an den Namen selbst)
  if ! antwort=$(DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" timeout 5 busctl --user call \
    org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
    GetConnectionUnixProcessID s org.freedesktop.Notifications 2>/dev/null); then
    if pgrep -u "$(id -u)" -x quickshell >/dev/null 2>&1 || pgrep -u "$(id -u)" -x qs >/dev/null 2>&1; then
      fehler "Quickshell läuft, stellt aber keinen Mitteilungsdienst bereit (Protokoll: journalctl --user -u zenos-shell)"
    else
      hinweis "Keine laufende zenOS-Oberfläche, Mitteilungsdienst nicht geprüft"
    fi
    return 0
  fi
  pid=${antwort##* }
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    hinweis "Besitzer von org.freedesktop.Notifications nicht ermittelbar"
    return 0
  fi
  exe=$(readlink -f -- "/proc/$pid/exe" 2>/dev/null || true)
  name=$(cat "/proc/$pid/comm" 2>/dev/null || true)
  case "${exe##*/}:$name" in
    quickshell:* | qs:* | *:quickshell | *:qs)
      ok "Mitteilungsdienst der Sitzung: Quickshell"
      _mitteilungen_faehigkeiten "$bus"
      ;;
    *)
      fehler "org.freedesktop.Notifications gehört nicht Quickshell, sondern «${name:-unbekannt}»"
      ;;
  esac
}

# Fähigkeiten, die zenOS anbietet: Text und Aktionen, kein Markup
_mitteilungen_faehigkeiten() {
  local bus=$1 antwort
  antwort=$(DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" timeout 5 busctl --user call \
    org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications \
    GetCapabilities 2>/dev/null) || { hinweis "Fähigkeiten des Mitteilungsdienstes nicht abfragbar"; return 0; }
  if [[ "$antwort" == *'"actions"'* && "$antwort" == *'"body"'* && "$antwort" != *'"body-markup"'* ]]; then
    ok "Mitteilungen mit Text und Aktionen, ohne Markup"
  else
    warnung "Unerwartete Fähigkeiten des Mitteilungsdienstes: ${antwort#* }"
  fi
}

# Standardregel in einstellungen.json: nur die Gültigkeit, nie den Inhalt
_mitteilungen_standard() {
  local datei=$HOME/.config/zenos/einstellungen.json ergebnis
  if [[ ! -f "$datei" ]]; then
    ok "Mitteilungen: Standardregel (gebündelt, stündlich)"
    return 0
  fi
  ergebnis=$(python3 - "$datei" <<'PY' 2>/dev/null
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        daten = json.load(f)
except (OSError, ValueError):
    print("unlesbar")
    sys.exit(0)
wert = daten.get("mitteilungenStandard") if isinstance(daten, dict) else None
if wert is None:
    print("fehlt")
elif isinstance(wert, str) and (wert in ("alle", "nur-dringend", "keine") or (
        re.fullmatch(r"gebuendelt-(\d{1,4})", wert) and 1 <= int(wert.split("-")[1]) <= 1440)):
    print("gueltig")
else:
    print("ungueltig")
PY
)
  case "$ergebnis" in
    gueltig) ok "Mitteilungen: Standardregel in den Einstellungen gültig" ;;
    fehlt) ok "Mitteilungen: Standardregel (gebündelt, stündlich)" ;;
    ungueltig) warnung "Mitteilungen: mitteilungenStandard in ~/.config/zenos/einstellungen.json ist ungültig – es gilt gebuendelt-60" ;;
    unlesbar) hinweis "Mitteilungen: einstellungen.json nicht lesbar, Standardregel nicht geprüft" ;;
    *) hinweis "Mitteilungen: Standardregel nicht prüfbar" ;;
  esac
}
