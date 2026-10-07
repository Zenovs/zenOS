#!/usr/bin/env bash
# hilfe: update [--ja] [--nur-zenos|--nur-basis] – zenOS über den Kanal, dann die Pakete der Ubuntu-Basis aktualisieren
# Zwei Schritte, jeder meldet für sich, ob er gelungen ist; danach die Benutzerteile.
#
# Schritt 1, zenOS-Kanal: folgt dem Kanal aus /etc/xdg/zenos/kanal (stabil, vorschau oder dev; main gilt als stabil).
# Die Arbeit machen die Units von zenos-kanal: holen (ohne Rechte), prüfen und bereitstellen (ohne Netz), installieren
# (als Dienst mit Inhibitor; bricht die SSH-Verbindung ab, läuft er zu Ende). /opt/zenos wird nie direkt umgestellt.
#   stabil, vorschau  nur gültig signierte Tags, die höchste Version des Kanals (nie unter «hoechste»)
#   dev               origin/dev. Ohne Frage nur, wenn jeder neue Commit gültig signiert ist; sonst (auch solange der
#                     Anker fehlt) zeigt zen update die Commits und installiert nur nach «ja» für genau diesen Commit
# Ein «ja» braucht es ausserdem für Firewall, Netz und Boot (Rückfrage-Pfade) und für einen Rückschritt. Gesperrte
# Versionen (scheiterten schon einmal) lässt zen update aus; noch einmal versuchen: zen rollback mit «ja». Danach
# Gesundheitsprüfung; scheitert sie, geht es automatisch zurück auf den Stand davor. Eine unterbrochene Installation
# setzt zen update zuerst fort.
#
# Schritt 2, Ubuntu-Basis (zenos-basis): apt-get update, dann zeigt zen update, was «apt full-upgrade» brächte (Anzahl,
# davon Sicherheit, Kernel/Firmware/Bootloader, Entfernungen, Neustart voraussichtlich), und installiert genau diese
# Liste nach einem getippten «ja» (als Dienst, läuft auch ohne Terminal zu Ende; danach install.sh und
# Gesundheitsprüfung, zurückgerollt wird nichts). Er läuft auch, wenn der Kanal nichts Neues hatte, ein «ja» dort
# fehlte oder gerade etwas lief, aber nicht, wenn der Kanal einen kaputten oder unterbrochenen Stand hinterlässt.
#   --ja          ohne Rückfrage, nur für den Basis-Schritt (auch Kernel, Firmware, Bootloader und Entfernungen). Das
#                 «ja» des Kanals ersetzt es nie: Das gibt es nur getippt im Terminal, für genau einen Stand
#   --nur-zenos   nur Schritt 1 (so deployt Claude; Paketänderungen der Basis bleiben bei Zeno)
#   --nur-basis   nur Schritt 2
# Exit: 0, wenn jeder gelaufene Schritt gelang (aktuell oder installiert); sonst der Exit des Schritts mit dem
# schwereren Ergebnis: 5 kaputt, 4 gescheitert und zurück (Kanal), 1 Fehler, 3 abgelehnt oder gesperrt, 10 wartet
# (auch «nein», übersprungen), 75 läuft schon. 2 falscher Aufruf, 130 abgebrochen.
# Automatisch (zum Zeitpunkt aus Einstellungen › System › Updates, zen kanal zeitpunkt): signierte Versionen auf
# stabil und vorschau, Basis-Updates ohne Kernel, Firmware, Bootloader und Entfernungen (auch auf dev, nie während
# einer SSH-Sitzung, nie ein Neustart). Gemeinsamer Notschalter: sudo zen kanal automatik aus. Sicherheitsupdates
# bringt weiter unattended-upgrades. Stand ohne Netz: zen version (Zeile «Pakete»), zen kanal status.
# Eine neue Ubuntu-Version kommt nie als Update (Basiswechsel: docs/image-und-releases.md).
# Notweg, falls zen update selbst nicht mehr geht: ANLEITUNG.md, Abschnitt F.
# shellcheck shell=bash

_UPDATE_PROGRAMM=/usr/local/libexec/zenos/zenos-kanal
_UPDATE_BASIS=/usr/local/libexec/zenos/zenos-basis
_UPDATE_PYTHON=/usr/bin/python3

befehl_update() {
  local ja=0 kanal=1 basis=1 rc_kanal="" rc_basis="" argument
  for argument in "$@"; do
    case "$argument" in
      --ja) ja=1 ;;
      --nur-zenos) basis=0 ;;
      --nur-basis) kanal=0 ;;
      *)
        zen_fehler "zen update kennt nur --ja, --nur-zenos und --nur-basis (nicht «$argument»)"
        return 2
        ;;
    esac
  done
  if (( kanal == 0 && basis == 0 )); then
    zen_fehler "zen update: --nur-zenos und --nur-basis schliessen sich aus"
    return 2
  fi
  if (( ja && ! basis )); then
    zen_fehler "zen update: --ja gilt nur für den Basis-Schritt, nie für das «ja» des Kanals (ohne --nur-zenos)"
    return 2
  fi

  if (( kanal )); then
    (( ! basis )) || zen_hinweis "== Schritt 1 von 2: zenOS-Kanal"
    rc_kanal=0
    _update_kanal || rc_kanal=$?
    _update_ergebnis "zenOS-Kanal" "$rc_kanal"
    if (( rc_kanal == 130 )); then
      (( ! basis )) || zen_hinweis "Ubuntu-Basis: nicht begonnen (abgebrochen)."
      return 130
    fi
  fi

  if (( basis )); then
    if (( kanal )); then
      zen_hinweis ""
      zen_hinweis "== Schritt 2 von 2: Ubuntu-Basis"
    fi
    if [[ "$rc_kanal" == 5 ]]; then
      # Auch zenos-basis prüft das selbst (laeuft.json, letzte.json «kaputt»)
      zen_hinweis "Ubuntu-Basis: übersprungen – der zenOS-Kanal ist kaputt; zuerst ihn reparieren (ANLEITUNG.md, Abschnitt F)."
      rc_basis=10
    else
      rc_basis=0
      _update_basis "$ja" || rc_basis=$?
      _update_ergebnis "Ubuntu-Basis" "$rc_basis"
    fi
  fi

  _update_benutzerteile "$rc_kanal" "$rc_basis"
  if [[ "$rc_basis" == 130 ]]; then
    return 130
  fi
  _update_exit "${rc_kanal:-0}" "${rc_basis:-0}"
}

_update_kanal() {
  if [[ ! -f "$_UPDATE_PROGRAMM" ]]; then
    zen_fehler "$_UPDATE_PROGRAMM fehlt, ohne ihn geht zen update nicht. Notweg: ANLEITUNG.md, Abschnitt F («zen update bricht ab»)."
    return 1
  fi
  $SUDO "$_UPDATE_PYTHON" -I "$_UPDATE_PROGRAMM" update
}

_update_basis() { # JA
  if [[ ! -f "$_UPDATE_BASIS" ]]; then
    zen_fehler "$_UPDATE_BASIS fehlt: Die Basis-Updates richtet install.sh ein (Modul 71-basis)."
    return 1
  fi
  if (( $1 )); then
    $SUDO "$_UPDATE_PYTHON" -I "$_UPDATE_BASIS" update --ja
  else
    $SUDO "$_UPDATE_PYTHON" -I "$_UPDATE_BASIS" update
  fi
}

# «zenOS-Kanal: gelungen.» bzw. «… nicht gelungen – wartet (Exit 10).»
_update_ergebnis() { # SCHRITT EXIT
  local text
  case "$2" in
    0) zen_hinweis "$1: gelungen."; return 0 ;;
    1) text="Fehler" ;;
    3) text="abgelehnt" ;;
    4) text="gescheitert, zurück auf dem Stand davor" ;;
    5) text="kaputt" ;;
    10) text="wartet" ;;
    75) text="läuft schon" ;;
    130) text="abgebrochen" ;;
    *) text="Fehler" ;;
  esac
  zen_hinweis "$1: nicht gelungen – $text (Exit $2)."
}

# Rang eines Exits: je höher, desto schwerer (unbekannte zählen wie 1)
_update_rang() {
  case "$1" in
    0) printf 0 ;;
    75) printf 1 ;;
    10) printf 2 ;;
    3) printf 3 ;;
    4) printf 5 ;;
    5) printf 6 ;;
    *) printf 4 ;;
  esac
}

# Exit von zen update: 0 nur, wenn jeder gelaufene Schritt gelang, sonst der schwerere der beiden
_update_exit() { # EXIT_KANAL EXIT_BASIS
  if (( $(_update_rang "$2") > $(_update_rang "$1") )); then
    return "$2"
  fi
  return "$1"
}

# Nach einer Installation oder einem Rückweg des Kanals (0, 4) oder einem gelungenen Basis-Schritt (0; install.sh lief
# dort als root und hat womöglich Quickshell neu gebaut): die Benutzerteile des Stands, der jetzt läuft, als Benutzer
# (ohne sudo; startet die Oberfläche neu, wenn sich QML geändert hat).
_update_benutzerteile() { # EXIT_KANAL EXIT_BASIS (leer: Schritt lief nicht)
  case "$1:$2" in
    0:* | 4:* | *:0) ;;
    *) return 0 ;;
  esac
  if (( EUID != 0 )) && [[ -x "$ZENOS_CODE/scripts/install.sh" ]]; then
    zen_hinweis ""
    "$ZENOS_CODE/scripts/install.sh" --nur-benutzer ||
      zen_warnung "Die Benutzerteile sind nicht vollständig eingerichtet (zen benutzer)"
  fi
  return 0
}
