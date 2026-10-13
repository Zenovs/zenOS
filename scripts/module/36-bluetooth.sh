#!/usr/bin/env bash
# 36-bluetooth: BlueZ für den Bluetooth-Abschnitt im System-Menü – Paket nachziehen, Dienst nach der ersten Installation
# gleich starten
# shellcheck shell=bash
#
# Das Paket kommt mit den übrigen über 20-pakete (scripts/pakete/bluetooth.txt); hier nur nachziehen, falls es fehlt.
# BlueZ aktiviert bluetooth.service selbst. Während apt läuft, verhindert policy-rc.d aber jeden Start (greetd!), also
# liefe der Dienst erst nach dem nächsten Neustart. Deshalb startet das Modul ihn, wenn er aktiviert ist und in diesem
# Start noch nie lief. Hat Zeno ihn bewusst gestoppt, deaktiviert oder maskiert, bleibt er, wie er ist.
# Nicht im Image (dort startet er beim ersten Start), nicht ohne systemd. Ein- und ausgeschaltet wird Bluetooth im
# System-Menü (Adapter an/aus über BlueZ), nicht hier. Keine Konfiguration: Sichtbar für andere ist der Rechner nur,
# wenn jemand es ausdrücklich einschaltet (BlueZ-Standard, docs/sicherheit.md).

_BLUETOOTH_SYS=/sys/class/bluetooth

modul_system() {
  pakete_sicherstellen bluez
  _bluetooth_starten
}

_bluetooth_starten() {
  local aktiviert seit
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  [[ -n "$(ls -A "$_BLUETOOTH_SYS" 2> /dev/null)" ]] || return 0
  systemctl --quiet is-active bluetooth.service 2> /dev/null && return 0
  aktiviert=$(systemctl is-enabled bluetooth.service 2> /dev/null) || aktiviert=""
  [[ "$aktiviert" == enabled ]] || return 0
  seit=$(systemctl show -p ActiveEnterTimestampMonotonic --value bluetooth.service 2> /dev/null) || seit=""
  [[ "$seit" == 0 ]] || return 0
  if $SUDO systemctl start bluetooth.service; then
    aenderung "bluetooth.service gestartet (nach der Installation von BlueZ)"
  else
    log_warnung "bluetooth.service liess sich nicht starten (journalctl -u bluetooth); Bluetooth geht nach dem Neustart"
  fi
}
