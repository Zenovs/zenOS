#!/usr/bin/env bash
# 66-energie: Energie – wlopm und zenos-bildschirm, Bildschirm aus nach der Sperre (wirksame Zeit), Bildschirm
# in der laufenden Sitzung erreichbar, Stand von zenos-idle, Bereitschaft des Kernels (nur Anzeige)
# shellcheck shell=bash
#
# Liest nur: zenos-idle energie (wirksame Minuten, keine Inhalte aus einstellungen.json), zenos-bildschirm
# status und /sys/power/state.

pruefe_energie() {
  abschnitt "Energie"
  _energie_werkzeuge
  _energie_zeit
  _energie_sitzung
  _energie_bereitschaft
}

_energie_werkzeuge() {
  local helfer=/opt/zenos/scripts/bin/zenos-bildschirm
  if [[ ! -x "$helfer" ]]; then
    fehler "$helfer fehlt (zen update oder install.sh)"
  fi
  if command -v wlopm >/dev/null 2>&1; then
    ok "wlopm installiert (Bildschirm aus nach der Sperre)"
  else
    warnung "wlopm fehlt – gesperrt wird weiter, aber der Bildschirm bleibt an (sudo apt install wlopm)"
  fi
}

# Wirksame Zeiten aus zenos-idle: Bildschirm aus B Min. nach der Sperre, also nach S+B Min. ohne Eingabe
_energie_zeit() {
  local idle=/opt/zenos/scripts/bin/zenos-idle name wert art sperre="" bildschirm="" bildschirm_art=""
  if [[ ! -x "$idle" ]]; then
    fehler "$idle fehlt"
    return 0
  fi
  while read -r name wert art; do
    case "$name" in
      sperre) sperre=$wert ;;
      bildschirm) bildschirm=$wert bildschirm_art=$art ;;
    esac
  done < <("$idle" energie 2>/dev/null)
  if [[ ! "$bildschirm" =~ ^[0-9]+$ ]] || (( bildschirm < 1 || bildschirm > 10 )) || [[ ! "$sperre" =~ ^[0-9]+$ ]]; then
    fehler "Zeit für «Bildschirm aus» nicht ermittelbar (zenos-idle energie)"
    return 0
  fi
  local text="Bildschirm aus $bildschirm Min. nach der Sperre, also nach $((sperre + bildschirm)) Min. ohne Eingabe"
  case "$bildschirm_art" in
    standard) ok "$text (Standard)" ;;
    einstellung) ok "$text" ;;
    begrenzt) warnung "bildschirmAusNachSperre liegt ausserhalb von 1–10, wirksam: $text" ;;
    *) warnung "bildschirmAusNachSperre ist keine Zahl oder einstellungen.json ist ungültig, wirksam: $text" ;;
  esac
}

# In einer laufenden Sitzung: Erreicht wlopm die Bildschirme, und läuft zenos-idle mit dem aktuellen Stand?
_energie_sitzung() {
  local laufzeit einheit=zenos-idle.service start code datei status
  local -a sc
  laufzeit=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  sc=(env "XDG_RUNTIME_DIR=$laufzeit" systemctl --user)
  if [[ ! -S "$laufzeit/bus" ]] || ! "${sc[@]}" --quiet is-active zenos-sitzung.target 2>/dev/null; then
    hinweis "Keine laufende zenOS-Sitzung, Bildschirm-Steuerung erst nach der Anmeldung prüfbar"
    return 0
  fi
  if command -v wlopm >/dev/null 2>&1 && [[ -x /opt/zenos/scripts/bin/zenos-bildschirm ]]; then
    if status=$(XDG_RUNTIME_DIR=$laufzeit timeout 10 /opt/zenos/scripts/bin/zenos-bildschirm status 2>/dev/null); then
      ok "Bildschirm-Steuerung in der Sitzung erreichbar (Bildschirm ${status})"
    else
      warnung "wlopm erreicht die Bildschirme der Sitzung nicht – der Bildschirm bliebe an (zenos-bildschirm status)"
    fi
  fi
  "${sc[@]}" --quiet is-active "$einheit" 2>/dev/null || return 0
  start=$("${sc[@]}" show --timestamp=unix -p ExecMainStartTimestamp --value "$einheit" 2>/dev/null)
  start=${start#@}
  [[ "$start" =~ ^[0-9]+$ ]] || return 0
  for datei in /opt/zenos/scripts/bin/zenos-idle /opt/zenos/scripts/bin/zenos-bildschirm; do
    code=$(stat -c %Y -- "$datei" 2>/dev/null) || continue
    if [[ "$code" =~ ^[0-9]+$ ]] && (( code > start )); then
      hinweis "zenos-idle läuft mit einem älteren Stand und übernimmt den neuen bei der nächsten Sperre"
      return 0
    fi
  done
}

# Bereitschaft (Suspend) gibt es nur, wenn der Kernel einen Schlafzustand anbietet. zenOS nutzt sie nicht.
_energie_bereitschaft() {
  local zustaende
  zustaende=$(cat /sys/power/state 2>/dev/null) || zustaende=""
  if [[ " $zustaende " == *" mem "* || " $zustaende " == *" freeze "* ]]; then
    hinweis "Der Kernel bietet Bereitschaft an ($zustaende), zenOS nutzt sie nicht und schaltet den Bildschirm aus"
  else
    hinweis "Bereitschaft auf diesem Gerät nicht verfügbar (Kernel ohne Schlafzustand), zenOS schaltet den Bildschirm aus"
  fi
}
