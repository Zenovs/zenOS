#!/usr/bin/env bash
# hilfe: kanal [status|pruefen|anker|zeitpunkt|automatik] – signierter Update-Kanal: Stand zeigen und prüfen (installieren: zen update)
#   zen kanal [status]           Kanal, Zustand, Anker mit Fingerabdrücken, gültige und abgelehnte Tags, letzte
#                                Installation, guter Stand, gesperrte Stände
#   sudo zen kanal pruefen       holt Tags und Branches von origin (ohne Rechte), prüft sie ohne Netz, schreibt den
#                                Stand (/var/lib/zenos/kanal/stand.json) und zeigt ihn. Installiert nichts.
#   zen kanal anker              zeigt den Vertrauensanker /etc/zenos/vertrauen
#   sudo zen kanal anker ORDNER  setzt den Anker von Hand aus ORDNER (etwa /opt/zenos/system/vertrauen): den ganzen
#                                Fingerabdruck der Wurzel und von jedem Release-Schlüssel die ersten 8 Zeichen nach
#                                «SHA256:» aus 1Password eintippen
#   zen kanal zeitpunkt          zeigt, wann automatische Updates installiert werden (ohne Datei: «sperre»)
#   sudo zen kanal zeitpunkt sperre|jederzeit|hand
#   sudo zen kanal zeitpunkt fenster VON BIS
#                                setzt ihn (/etc/xdg/zenos/kanal-zeitpunkt; VON und BIS als HH:MM, mindestens eine
#                                Stunde). Dasselbe in Einstellungen › System › Updates
#   zen kanal automatik          zeigt, ob die Automatik an ist (alle 6 h holen und prüfen, installiert wird nach dem
#                                Zeitpunkt; nie auf dev), wann sie zuletzt lief und was wartet
#   sudo zen kanal automatik an|aus
#                                Notschalter: Timer ein bzw. aus (/etc/xdg/zenos/kanal-automatik-aus; install.sh
#                                hält sich daran). zen update geht immer
# Das Programm ist /usr/local/libexec/zenos/zenos-kanal (kommt mit install.sh). Installiert wird mit «zen update» und
# «zen rollback <tag>» über dieselben Units.
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
    zeitpunkt)
      if (( $# == 0 )); then
        /usr/bin/python3 -I "$_KANAL_PROGRAMM" zeitpunkt
      else
        $SUDO /usr/bin/python3 -I "$_KANAL_PROGRAMM" zeitpunkt "$@"
      fi
      ;;
    automatik)
      if (( $# == 0 )); then
        /usr/bin/python3 -I "$_KANAL_PROGRAMM" automatik
      elif (( $# == 1 )) && [[ "$1" == an || "$1" == aus ]]; then
        $SUDO /usr/bin/python3 -I "$_KANAL_PROGRAMM" automatik "$1"
      else
        zen_fehler "zen kanal automatik [an|aus]"
        return 2
      fi
      ;;
    *)
      zen_fehler "zen kanal kennt «$befehl» nicht (status, pruefen, anker, zeitpunkt, automatik)"
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
