#!/usr/bin/env bash
# hilfe: hilfe [befehl] – Übersicht aller Befehle oder Hilfe zu einem Befehl
# shellcheck shell=bash

befehl_hilfe() {
  if (( $# == 0 )); then
    _zen_hilfe_kurz
    return 0
  fi
  local name=$1 datei
  datei="$ZEN_SKRIPTE/zen.d/$name.sh"
  if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ || ! -f "$datei" ]]; then
    printf 'zen: unbekannter Befehl «%s»\n\n' "$name" >&2
    _zen_hilfe_kurz >&2
    return 2
  fi
  # Die «# hilfe:»-Zeile und die direkt folgenden Kommentarzeilen (ohne shellcheck-Anweisungen)
  awk '
    /^# hilfe: / { drin = 1; sub(/^# hilfe: /, "zen "); print; next }
    drin && /^# shellcheck/ { next }
    drin && /^#( |$)/ { sub(/^# ?/, "  "); print; next }
    drin { exit }
  ' "$datei"
}
