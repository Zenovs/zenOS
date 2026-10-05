#!/usr/bin/env bash
# hilfe: kanal [status|pruefen|anker] – signierter Update-Kanal prüfen (installiert nichts)
#   zen kanal [status]           Kanal, Zustand, Anker mit Fingerabdrücken, gültige und abgelehnte Tags
#   sudo zen kanal pruefen       holt Tags und Branches von origin (ohne Rechte), prüft sie ohne Netz, schreibt den
#                                Stand (/var/lib/zenos/kanal/stand.json) und zeigt ihn. Installiert nichts.
#   zen kanal anker              zeigt den Vertrauensanker /etc/zenos/vertrauen
#   sudo zen kanal anker ORDNER  setzt den Anker von Hand aus ORDNER (etwa /opt/zenos/system/vertrauen): Fingerabdruck
#                                der Wurzel aus 1Password eintippen, die Release-Schlüssel mit «ja» bestätigen
# Das Programm ist /usr/local/libexec/zenos/zenos-kanal (kommt mit install.sh). «zen update» bleibt der Weg von Hand.
# shellcheck shell=bash

_KANAL_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal

befehl_kanal() {
  local befehl=${1:-status}
  (( $# == 0 )) || shift
  if [[ ! -f "$_KANAL_PROGRAMM" ]]; then
    zen_fehler "$_KANAL_PROGRAMM fehlt. Zuerst install.sh (oder zen update) ausführen."
    return 1
  fi
  case "$befehl" in
    status)
      /usr/bin/python3 -I "$_KANAL_PROGRAMM" status "$@"
      ;;
    pruefen)
      if (( $# > 0 )); then
        zen_fehler "zen kanal pruefen kennt keine Argumente"
        return 2
      fi
      _kanal_pruefen
      ;;
    anker)
      if (( $# == 0 )); then
        /usr/bin/python3 -I "$_KANAL_PROGRAMM" anker
      elif (( $# == 1 )) && [[ "$1" != -* ]]; then
        $SUDO /usr/bin/python3 -I "$_KANAL_PROGRAMM" anker "$(readlink -f -- "$1")"
      else
        zen_fehler "zen kanal anker [ORDNER]"
        return 2
      fi
      ;;
    *)
      zen_fehler "zen kanal kennt «$befehl» nicht (status, pruefen, anker)"
      return 2
      ;;
  esac
}

# Holen und Prüfen als systemd-Units (Sandbox, ohne Netz beim Prüfen); danach der Stand. Rückgabe: Exit des Prüfens.
_kanal_pruefen() {
  local rc fehler
  if [[ ! -d /run/systemd/system ]]; then
    zen_fehler "zen kanal pruefen braucht systemd"
    return 1
  fi
  zen_hinweis "Hole von origin (ohne Rechte) …"
  if ! $SUDO systemctl start zenos-kanal-holen.service; then
    zen_warnung "Holen ist gescheitert (journalctl -u zenos-kanal-holen.service). Geprüft wird der letzte Stand."
  fi
  zen_hinweis "Prüfe (ohne Netz) …"
  # «Anker fehlt» oder «blockiert» (Exit 3) lässt die Unit scheitern; das zeigt der Status unten ohnehin
  fehler=$($SUDO systemctl start zenos-kanal-pruefen.service 2>&1) || true
  rc=$($SUDO systemctl show --property=ExecMainStatus --value zenos-kanal-pruefen.service 2>/dev/null) || rc=1
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
  case "$rc" in
    0 | 3 | 10 | 75) ;;
    *) [[ -z "$fehler" ]] || printf '%s\n' "$fehler" >&2 ;;
  esac
  zen_hinweis ""
  /usr/bin/python3 -I "$_KANAL_PROGRAMM" status
  if (( rc == 75 )); then
    zen_warnung "Ein Update oder eine Prüfung lief gerade; der Stand oben ist der vorige. Später noch einmal."
  elif (( rc == 1 )); then
    zen_warnung "Die Prüfung ist abgebrochen (journalctl -u zenos-kanal-pruefen.service)"
  fi
  return "$rc"
}
