#!/usr/bin/env bash
# hilfe: anzeige [status|einrichten|entfernen|neustart] – Gerät als öffentlichen Bildschirm betreiben (Geräteprofil)
# Ein technisches Anzeige-Konto meldet sich beim Start von selbst an und zeigt genau eine App im Vollbild, ohne Sperre
# (MANIFEST, «Ausnahme Anzeigegerät»). Konfiguration: /etc/zenos/anzeige.json (Vorlage
# config/beispiele/anzeige.beispiel.json). «einrichten» und «entfernen» zeigen vorher den Plan und brauchen die
# Eingabe des Worts; sie laufen als root (sudo). Dein Konto sperrt auf so einem Gerät wie immer und meldet sich nie
# automatisch an. Ausweg vor Ort: Strg + Alt + Shift + Rücktaste beendet die Anzeige, danach erscheint dein Login.
# «neustart» startet greetd neu, damit die Anzeige wieder läuft (nicht, solange du selbst am Gerät angemeldet bist).
# Doku: docs/module/anzeige.md.
# shellcheck shell=bash

_ANZEIGE_PROGRAMM=$ZENOS_CODE/scripts/bin/zenos-anzeige

befehl_anzeige() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen anzeige [status|einrichten|entfernen|neustart])"
    return 2
  fi
  if [[ ! -f "$_ANZEIGE_PROGRAMM" ]]; then
    zen_fehler "$_ANZEIGE_PROGRAMM fehlt (zen update)"
    return 1
  fi
  case "${1:-status}" in
    status) python3 -I "$_ANZEIGE_PROGRAMM" status ;;
    einrichten) _anzeige_einrichten ;;
    entfernen) _anzeige_entfernen ;;
    neustart) $SUDO /usr/bin/python3 -I "$_ANZEIGE_PROGRAMM" neustart ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, einrichten, entfernen, neustart)"
      return 2
      ;;
  esac
}

_anzeige_einrichten() {
  if [[ ! -t 0 ]]; then
    zen_fehler "zen anzeige einrichten braucht eine Bestätigung im Terminal (Eingabe «einrichten»)"
    return 2
  fi
  # Der Plan prüft die Konfiguration und ein schon vorhandenes Konto; scheitert er, ändert sich nichts
  $SUDO /usr/bin/python3 -I "$_ANZEIGE_PROGRAMM" plan einrichten || return 1
  printf '\n'
  local antwort=""
  read -r -p 'Zum Einrichten «einrichten» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != einrichten ]]; then
    printf 'Abgebrochen. Nichts geändert.\n'
    return 1
  fi
  $SUDO /usr/bin/python3 -I "$_ANZEIGE_PROGRAMM" einrichten --ja
}

_anzeige_entfernen() {
  if [[ ! -t 0 ]]; then
    zen_fehler "zen anzeige entfernen braucht eine Bestätigung im Terminal (Eingabe «entfernen»)"
    return 2
  fi
  if ! python3 -I "$_ANZEIGE_PROGRAMM" aktiv; then
    printf 'Das Profil ist nicht aktiv; nichts zu entfernen.\n'
    return 0
  fi
  $SUDO /usr/bin/python3 -I "$_ANZEIGE_PROGRAMM" plan entfernen || return 1
  printf '\n'
  local antwort="" daten=""
  read -r -p 'Zum Entfernen «entfernen» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != entfernen ]]; then
    printf 'Abgebrochen. Nichts geändert.\n'
    return 1
  fi
  # Daten des Kontos nur auf ausdrückliche Rückfrage (etwa der Checkout der App)
  read -r -p 'Auch das Home des Anzeige-Kontos löschen? Dafür «löschen» eintippen, sonst bleibt es: ' daten || daten=""
  if [[ "$daten" == löschen ]]; then
    $SUDO /usr/bin/python3 -I "$_ANZEIGE_PROGRAMM" entfernen --ja --daten-loeschen
  else
    $SUDO /usr/bin/python3 -I "$_ANZEIGE_PROGRAMM" entfernen --ja
  fi
}
