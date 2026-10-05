#!/usr/bin/env bash
# hilfe: rollback <tag> – über den Kanal zu einem getaggten Stand zurück und installieren
# Der Tag kommt vom zuletzt geholten Stand von origin. Gültig signiert geht es ohne Frage; sonst (unsigniert, etwa
# v0.1.0-rc3, oder solange der Anker fehlt) nur nach «ja», gebunden an genau dieses Tag-Objekt. Firewall, Netz und
# Boot und ein gesperrter Stand fragen ebenfalls. «hoechste» bleibt: Das nächste «zen update» kehrt auf den Kanal
# zurück. Installiert wird wie bei zen update (Dienst, Gesundheitsprüfung, Rückweg), danach die Benutzerteile.
# shellcheck shell=bash

_ROLLBACK_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal

befehl_rollback() {
  if (( $# != 1 )); then
    zen_fehler "Aufruf: zen rollback <tag>"
    return 2
  fi
  local tag=$1 rc=0
  if [[ ! "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]]; then
    zen_fehler "Ungültiger Tag-Name «$tag»"
    return 2
  fi
  if [[ ! -f "$_ROLLBACK_PROGRAMM" ]]; then
    zen_fehler "$_ROLLBACK_PROGRAMM fehlt, ohne ihn geht zen rollback nicht. Notweg: ANLEITUNG.md, Abschnitt F."
    return 1
  fi
  $SUDO /usr/bin/python3 -I "$_ROLLBACK_PROGRAMM" rollback "$tag" || rc=$?
  case "$rc" in
    0 | 4) ;;
    *) return "$rc" ;;
  esac
  if (( EUID != 0 )) && [[ -x "$ZENOS_CODE/scripts/install.sh" ]]; then
    zen_hinweis ""
    "$ZENOS_CODE/scripts/install.sh" --nur-benutzer ||
      zen_warnung "Die Benutzerteile sind nicht vollständig eingerichtet (zen benutzer)"
  fi
  return "$rc"
}
