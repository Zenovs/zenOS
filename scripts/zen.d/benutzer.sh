#!/usr/bin/env bash
# hilfe: benutzer [--ruhig] – nur die Benutzerteile einrichten (install.sh --nur-benutzer)
# shellcheck shell=bash

befehl_benutzer() {
  local arg
  for arg in "$@"; do
    [[ "$arg" == --ruhig ]] || { zen_fehler "unbekannte Option «$arg» (erlaubt: --ruhig)"; return 2; }
  done
  if (( EUID == 0 )); then
    zen_fehler "zen benutzer läuft als normaler Benutzer, nicht als root"
    return 2
  fi
  [[ -x "$ZENOS_CODE/scripts/install.sh" ]] || { zen_fehler "$ZENOS_CODE ist nicht installiert"; return 1; }
  "$ZENOS_CODE/scripts/install.sh" --nur-benutzer "$@"
}
