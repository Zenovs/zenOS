#!/usr/bin/env bash
# hilfe: netzwerk [status|umstellen|zurueck] – Netz auf NetworkManager umstellen (WLAN-Menü oben rechts) und zurück
# «umstellen» zeigt vorher, was passiert (übernommene WLANs, Sicherung, WPA3 im WLAN-Treiber, Rückweg), und stellt
# erst nach der Eingabe «umstellen» um. Jedes bisherige WLAN wird ein eigenes Profil von NetworkManager. Wirksam
# nach dem Neustart; bis dahin bleibt das Netz, wie es ist (kein «netplan apply», SSH bleibt).
# «zurueck» stellt die Sicherung wieder her, auch ohne Netz; danach ebenfalls neu starten.
# Einzelheiten: docs/module/netzwerk.md
# shellcheck shell=bash

befehl_netzwerk() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen netzwerk [status|umstellen|zurueck])"
    return 2
  fi
  _NETZWERK_PROGRAMM="$ZENOS_CODE/scripts/bin/zenos-netzwerk"
  if [[ ! -f "$_NETZWERK_PROGRAMM" ]]; then
    zen_fehler "$_NETZWERK_PROGRAMM fehlt (zen update)"
    return 1
  fi
  case "${1:-status}" in
    status) python3 -I "$_NETZWERK_PROGRAMM" status ;;
    umstellen) _netzwerk_umstellen ;;
    zurueck) _netzwerk_zurueck ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, umstellen, zurueck)"
      return 2
      ;;
  esac
}

_netzwerk_umgestellt() { [[ -e /etc/netplan/90-zenos-netzwerk.yaml ]]; }

_netzwerk_umstellen() {
  if _netzwerk_umgestellt; then
    printf 'Schon umgestellt: NetworkManager verwaltet das Netz.\n\n'
    python3 -I "$_NETZWERK_PROGRAMM" status
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen netzwerk umstellen braucht eine Bestätigung im Terminal (Eingabe «umstellen»)"
    return 2
  fi
  # Der Plan liest die netplan-Dateien (nur für root lesbar) und prüft alles, ändert aber nichts
  $SUDO python3 -I "$_NETZWERK_PROGRAMM" plan || return 1
  printf '\n'
  local antwort=""
  read -r -p 'Zum Umstellen «umstellen» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != umstellen ]]; then
    printf 'Abgebrochen. Nichts geändert.\n'
    return 1
  fi
  $SUDO python3 -I "$_NETZWERK_PROGRAMM" umstellen || return 1
  printf '\nNach dem Neustart: WLAN im Menü oben rechts, Prüfung mit «zen netzwerk status».\n'
  printf 'Beim Neustart am Gerät bleiben: Eine SSH-Verbindung ist dabei weg.\n'
}

_netzwerk_zurueck() {
  if ! _netzwerk_umgestellt; then
    printf 'Nicht umgestellt: Das Netz läuft über netplan mit systemd-networkd. Nichts zu tun.\n'
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen netzwerk zurueck braucht eine Bestätigung im Terminal (Eingabe «zurueck»)"
    return 2
  fi
  printf 'Zurück auf die Sicherung von vor der Umstellung: netplan mit systemd-networkd, wirksam nach dem Neustart.\n'
  printf 'Später im Menü angelegte WLANs wandern in die Sicherung (/var/lib/zenos/netplan-vorher/).\n\n'
  local antwort=""
  read -r -p 'Zum Zurückstellen «zurueck» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != zurueck ]]; then
    printf 'Abgebrochen. Nichts geändert.\n'
    return 1
  fi
  $SUDO python3 -I "$_NETZWERK_PROGRAMM" zurueck
}
