#!/usr/bin/env bash
# hilfe: apps [installieren|aktualisieren|status] [app …] – Chrome, VS Code, 1Password, coremail aus offiziellen Quellen
# Apps: chrome vscode 1password cli coremail nubix (ohne Angabe: alle, die es für diese Architektur gibt).
#   zen apps installieren [--ja] [app …]   zeigt vorher genau, was passiert (Quellen, Schlüssel, Dateien),
#                                          fragt einmal nach und holt sich Root-Rechte mit sudo.
#                                          Bereits Installiertes wird übersprungen. --ja: ohne Rückfrage.
#   zen apps aktualisieren [app …]         neue Version von 1Password, coremail und Nubix
#                                          (Chrome, VS Code und die CLI aktualisiert apt)
#   zen apps status [--netz]               was installiert ist; --netz fragt die GitHub-Releases ab
# Proprietäre Apps kommen nie ins Image und nie ohne deine Zustimmung aufs Gerät.
# shellcheck shell=bash

befehl_apps() {
  local apps="$ZEN_SKRIPTE/bin/zenos-apps"
  if [[ ! -x "$apps" ]]; then
    zen_fehler "$apps fehlt"
    return 1
  fi
  (( $# > 0 )) || set -- status
  case "$1" in
    installieren | aktualisieren | status) "$apps" "$@" ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: installieren, aktualisieren, status)"
      return 2
      ;;
  esac
}
