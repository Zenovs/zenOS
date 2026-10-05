#!/usr/bin/env bash
# hilfe: update – neuen Stand über den Kanal holen, prüfen und installieren
# Folgt dem Kanal aus /etc/xdg/zenos/kanal (stabil, vorschau oder dev; main gilt als stabil). Die Arbeit machen die
# Units von zenos-kanal: holen (ohne Rechte), prüfen und bereitstellen (ohne Netz), installieren (als Dienst mit
# Inhibitor; bricht die SSH-Verbindung ab, läuft er zu Ende). /opt/zenos wird nie mehr direkt umgestellt.
#   stabil, vorschau  nur gültig signierte Tags, die höchste Version des Kanals (nie unter «hoechste»)
#   dev               origin/dev. Ohne Frage nur, wenn jeder neue Commit gültig signiert ist; sonst (auch solange der
#                     Anker fehlt) zeigt zen update die Commits und installiert nur nach «ja» für genau diesen Commit
# Ein «ja» braucht es ausserdem für Firewall, Netz und Boot (Rückfrage-Pfade) und für einen Rückschritt. Gesperrte
# Versionen (scheiterten schon einmal) lässt zen update aus; noch einmal versuchen: zen rollback mit «ja». Danach
# Gesundheitsprüfung; scheitert sie, geht es automatisch zurück auf den Stand davor. Eine unterbrochene Installation setzt zen update zuerst fort. Zum Schluss die Benutzerteile.
# Notweg, falls zen update selbst nicht mehr geht: ANLEITUNG.md, Abschnitt F.
# shellcheck shell=bash

_UPDATE_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal

befehl_update() {
  if (( $# > 0 )); then
    zen_fehler "zen update kennt keine Argumente"
    return 2
  fi
  if [[ ! -f "$_UPDATE_PROGRAMM" ]]; then
    zen_fehler "$_UPDATE_PROGRAMM fehlt, ohne ihn geht zen update nicht. Notweg: ANLEITUNG.md, Abschnitt F («zen update bricht ab»)."
    return 1
  fi
  local rc=0
  $SUDO /usr/bin/python3 -I "$_UPDATE_PROGRAMM" update || rc=$?
  _update_benutzerteile "$rc"
}

# Nach einer Installation (0) oder einem Rückweg (4): die Benutzerteile des Stands, der jetzt läuft, als Benutzer
# (ohne sudo; startet die Oberfläche neu, wenn sich QML geändert hat). Rückgabe: Exit von zenos-kanal.
_update_benutzerteile() {
  local rc=$1
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
