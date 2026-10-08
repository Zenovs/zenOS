#!/usr/bin/env bash
# hilfe: install [--text] DATEI.deb | --liste | --status – heruntergeladene Software (.deb) mit dem zen Installer
# In zenOS (Terminal in der Sitzung) öffnet «zen install DATEI.deb» das Fenster «zen Installer», wie ein Doppelklick
# auf die Datei. Ohne Sitzung (etwa über SSH) oder mit --text zeigt es hier, was das Paket mitbringt (Herausgeber,
# zusätzliche Pakete, Systemdienste, Paketquellen, eigene Skripte als root …), und installiert erst nach der Eingabe
# «ja» mit sudo: genau die angezeigte Datei (SHA-256) und genau das, was apt dazu angezeigt hat. Ein fremdes Paket
# läuft bei der Installation mit allen Rechten.
#   zen install --liste     was über den zen Installer kam und ob es noch installiert ist
#   zen install --status    läuft gerade eine Installation, letztes Ergebnis
# Entfernen: sudo apt remove PAKET (die Konfiguration bleibt).
# shellcheck shell=bash

befehl_install() {
  local programm="$ZEN_SKRIPTE/bin/zenos-installer" helfer="$ZEN_SKRIPTE/bin/zenos-installer-bedienen"
  local text=0 datei="" arg
  if [[ ! -x "$programm" || ! -x "$helfer" ]]; then
    zen_fehler "zen Installer fehlt ($programm)"
    return 1
  fi
  if (( $# == 1 )) && [[ "$1" == --liste || "$1" == --status ]]; then
    case "$1" in
      --liste) "$programm" liste ;;
      --status) "$programm" status ;;
    esac
    return
  fi
  for arg in "$@"; do
    case "$arg" in
      --text) text=1 ;;
      --liste | --status)
        zen_fehler "$arg steht allein (zen install --liste, zen install --status)"
        return 2
        ;;
      -*)
        zen_fehler "unbekannte Option «$arg» (zen install [--text] DATEI.deb | --liste | --status)"
        return 2
        ;;
      *)
        if [[ -n "$datei" ]]; then
          zen_fehler "nur eine Datei auf einmal"
          return 2
        fi
        datei=$arg
        ;;
    esac
  done
  if [[ -z "$datei" ]]; then
    zen_fehler "welche Datei? (zen install [--text] DATEI.deb | --liste | --status)"
    return 2
  fi
  if [[ "$datei" != *.deb ]]; then
    zen_fehler "der zen Installer nimmt nur Pakete mit der Endung .deb"
    return 2
  fi
  local pfad
  if ! pfad=$(realpath -e -- "$datei" 2> /dev/null) || [[ ! -f "$pfad" ]]; then
    zen_fehler "$datei gibt es nicht"
    return 2
  fi

  # In der Sitzung: das Fenster (wie ein Doppelklick)
  if (( ! text )) && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    local rc=0
    "$programm" oeffnen "$pfad" || rc=$?
    if (( rc == 0 )); then
      zen_hinweis "Der zen Installer ist offen."
    elif (( rc == 1 )); then
      zen_hinweis "Ohne Fenster, hier im Terminal: zen install --text $(printf '%q' "$datei")"
    fi
    return "$rc"
  fi
  _install_text "$programm" "$helfer" "$pfad"
}

# Ansicht als Text, «ja», dann sudo zenos-installer-bedienen installieren PFAD SHA256 PLAN
_install_text() {
  local programm=$1 helfer=$2 pfad=$3 ausgabe="" rc=0 zeile sha="" plan="" antwort="" beginn grund=""
  ausgabe=$("$programm" ansehen "$pfad" --auftrag) || rc=$?
  if [[ -n "$ausgabe" ]]; then
    while IFS= read -r zeile; do
      if [[ "$zeile" =~ ^auftrag\ ([0-9a-f]{64})\ ([0-9a-f]{40})$ ]]; then
        sha=${BASH_REMATCH[1]}
        plan=${BASH_REMATCH[2]}
      else
        printf '%s\n' "$zeile"
      fi
    done <<< "$ausgabe"
  fi
  if (( rc != 0 )); then
    return "$rc"
  fi
  # Schon installiert: nichts zu tun
  [[ -n "$sha" ]] || return 0

  printf '\nDas Paket läuft bei der Installation mit allen Rechten; sudo fragt nach deinem Passwort.\n'
  if [[ ! -t 0 ]]; then
    zen_fehler "keine Bestätigung möglich (kein Terminal)"
    return 1
  fi
  read -r -p 'Zum Installieren «ja» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != ja ]]; then
    printf 'Abgebrochen. Nichts installiert.\n'
    return 1
  fi
  rc=0
  beginn=$EPOCHSECONDS
  $SUDO "$helfer" installieren "$pfad" "$sha" "$plan" || rc=$?
  # Die Unit schreibt ins Journal; ihr Ergebnis steht in letzte.json (nur wenn es zu dieser Datei und diesem Lauf
  # gehört: Lehnt schon der Helfer ab, hat er es selbst gesagt)
  grund=$(_install_grund "$programm" "$sha" "$beginn" || true)
  if (( rc == 0 )); then
    zen_hinweis "${grund:-Installiert.}"
  elif [[ -n "$grund" ]]; then
    zen_fehler "$grund"
  elif (( rc == 75 )); then
    zen_fehler "gerade läuft ein Update oder ein anderer Paketvorgang; später noch einmal"
  fi
  return "$rc"
}

# Grund aus letzte.json, wenn sie zu SHA256 gehört und nicht vor BEGINN (Sekunden) endete; sonst Exit 1
_install_grund() {
  local programm=$1 sha=$2 beginn=$3
  "$programm" status --json 2> /dev/null | python3 -I -c '
import datetime, json, sys
try:
    letzte = json.load(sys.stdin).get("letzte") or {}
    ende = datetime.datetime.strptime(str(letzte.get("ende")), "%Y-%m-%dT%H:%M:%SZ")
except (ValueError, AttributeError):
    sys.exit(1)
ende = ende.replace(tzinfo=datetime.timezone.utc).timestamp()
if letzte.get("art") != "installieren" or letzte.get("sha256") != sys.argv[1] or ende < int(sys.argv[2]) - 2:
    sys.exit(1)
print(" ".join(str(letzte.get("grund") or "").split())[:400])
' "$sha" "$beginn"
}
