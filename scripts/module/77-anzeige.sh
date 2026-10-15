#!/usr/bin/env bash
# 77-anzeige: Geräteprofil «Öffentlicher Bildschirm» nachziehen – nur, wenn es aktiv ist (zen anzeige einrichten)
# shellcheck shell=bash
#
# Ohne aktives Profil tut das Modul nichts: Auf Geräten ohne Anzeige ändert sich nichts. Mit Profil zieht
# «zenos-anzeige anwenden» die Dateien nach (polkit-Regel, Einheiten der Anzeige-Sitzung, Drop-in für die App;
# greetd schreibt 40-sitzung aus derselben Quelle) und meldet ein unpassend gewordenes Anzeige-Konto. Danach gleicht
# «zenos-firewall anzeige» die Regeln für die Ports an (nur aus den lokalen Netzen, wie SSH; schaltet nie ein).
# Konto anlegen und löschen tut nur «zen anzeige einrichten» bzw. «entfernen», nie install.sh. Im Image-Modus gibt es
# kein Profil. Doku: docs/module/anzeige.md.

modul_system() {
  local programm=$ZENOS_CODE/scripts/bin/zenos-anzeige zeile ausgabe rc=0
  [[ -f "$programm" ]] || return 0
  python3 -I "$programm" aktiv > /dev/null 2>&1 || return 0
  ausgabe=$($SUDO /usr/bin/python3 -I "$programm" anwenden --melden 2>&1) || rc=$?
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] || continue
    case "$zeile" in
      "geändert: "*) aenderung "${zeile#geändert: }" ;;
      *) log_warnung "${zeile#zenos-anzeige: }" ;;
    esac
  done <<< "$ausgabe"
  (( rc == 0 )) || log_warnung "zenos-anzeige anwenden ist gescheitert (Exit $rc; sudo zen anzeige status)"

  [[ "$ZENOS_IMAGE" == 1 ]] && return 0
  rc=0
  ausgabe=$($SUDO "$ZENOS_CODE/scripts/bin/zenos-firewall" anzeige 2>&1) || rc=$?
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] || continue
    case "$zeile" in
      "Anzeige: "*) aenderung "Firewall ${zeile#Anzeige: }" ;;
      *) log_info "$zeile" ;;
    esac
  done <<< "$ausgabe"
  case "$rc" in
    0) ;;
    4) log_warnung "ufw fehlt: keine Firewall-Regeln für die Ports der Anzeige" ;;
    *) log_warnung "Firewall-Regeln der Anzeige nicht angeglichen (zenos-firewall anzeige, Exit $rc)" ;;
  esac
}
