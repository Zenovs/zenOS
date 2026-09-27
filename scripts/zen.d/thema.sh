#!/usr/bin/env bash
# hilfe: thema [hell|dunkel|tageszeit|wechseln] – Erscheinungsbild setzen oder anzeigen
# Schreibt das Erscheinungsbild in ~/.config/zenos/einstellungen.json. Läuft die Oberfläche,
# übernimmt sie es sofort; sonst überträgt zenos-thema es direkt auf GTK, Qt, kitty, labwc
# und VS Code. Ohne Argument: aktuelles Erscheinungsbild anzeigen.
# shellcheck shell=bash

befehl_thema() {
  if (( EUID == 0 )); then
    zen_fehler "zen thema läuft als normaler Benutzer, nicht als root"
    return 2
  fi
  local thema="$ZENOS_CODE/scripts/bin/zenos-thema"
  [[ -x "$thema" ]] || { zen_fehler "$thema fehlt"; return 1; }
  case "${1:-}" in
    "")
      "$thema" status
      ;;
    hell | dunkel | tageszeit | wechseln)
      (( $# == 1 )) || { zen_fehler "zu viele Argumente"; return 2; }
      "$thema" setzen "$1" || return
      "$thema" status
      ;;
    *)
      zen_fehler "unbekanntes Erscheinungsbild «$1» (erlaubt: hell, dunkel, tageszeit, wechseln)"
      return 2
      ;;
  esac
}
