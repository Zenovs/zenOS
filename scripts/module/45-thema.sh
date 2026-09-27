#!/usr/bin/env bash
# 45-thema: Erscheinungsbild aus den Design-Tokens auf GTK, Qt, kitty, labwc und VS Code übertragen
# shellcheck shell=bash

modul_system() {
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  local -a pakete=()
  local zeile
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_QUELLE/scripts/pakete/thema.txt"
  pakete_sicherstellen "${pakete[@]}"
}

modul_benutzer() {
  local thema="$ZENOS_CODE/scripts/bin/zenos-thema" ausgabe zeile
  if [[ ! -x "$thema" ]]; then
    log_warnung "zenos-thema fehlt unter $ZENOS_CODE, Erscheinungsbild nicht übertragen"
    return 0
  fi
  # Erscheinungsbild und Akzent aus den Einstellungen und dem aktiven Modus;
  # zenos-thema meldet jede Änderung als eigene Zeile.
  if ! ausgabe=$("$thema" anwenden --melden); then
    log_warnung "zenos-thema konnte das Erscheinungsbild nicht vollständig übertragen"
  fi
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] && aenderung "Erscheinungsbild: $zeile"
  done <<< "$ausgabe"
  return 0
}
