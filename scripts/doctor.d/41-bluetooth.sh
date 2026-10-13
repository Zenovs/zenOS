#!/usr/bin/env bash
# 41-bluetooth: Bluetooth – BlueZ installiert, Dienst, rfkill, Adapter an, nicht sichtbar für andere, gekoppelte Geräte
# shellcheck shell=bash
#
# Liest nur: /sys/class/bluetooth und /sys/class/rfkill, den Paketstand, den Zustand von bluetooth.service und
# «bluetoothctl show» bzw. «bluetoothctl devices». Nennt nur Anzahlen, nie Namen oder Adressen von Geräten.

_bluetooth_sys=/sys/class/bluetooth
_bluetooth_rfkill_sys=/sys/class/rfkill

pruefe_bluetooth() {
  local zustand
  abschnitt "Bluetooth"
  if [[ -z "$(ls -A "$_bluetooth_sys" 2> /dev/null)" ]]; then
    hinweis "Kein Bluetooth im Gerät"
    return 0
  fi
  # ${Status} setzt dpkg-query ein, nicht die Shell
  # shellcheck disable=SC2016
  if ! dpkg-query -W -f='${Status}' bluez 2> /dev/null | grep -q 'install ok installed'; then
    fehler "bluez fehlt: Das System-Menü kann Bluetooth nicht bedienen (install.sh)"
    return 0
  fi
  zustand=$(systemctl is-active bluetooth.service 2> /dev/null) || true
  if [[ "$zustand" != active ]]; then
    warnung "bluetooth.service ist «${zustand:-unbekannt}» (sudo systemctl start bluetooth)"
    _bluetooth_rfkill
    return 0
  fi
  ok "bluetooth.service läuft"
  _bluetooth_rfkill
  _bluetooth_adapter
}

# rfkill: hart gesperrt (Schalter, Firmware) oder weich (rfkill block); dann geht der Schalter im Menü nicht
_bluetooth_rfkill() {
  local r
  for r in "$_bluetooth_rfkill_sys"/rfkill*; do
    [[ "$(cat "$r/type" 2> /dev/null)" == bluetooth ]] || continue
    if [[ "$(cat "$r/hard" 2> /dev/null)" == 1 ]]; then
      warnung "Bluetooth ist hart gesperrt (rfkill, Schalter oder Firmware)"
    elif [[ "$(cat "$r/soft" 2> /dev/null)" == 1 ]]; then
      warnung "Bluetooth ist per rfkill gesperrt (rfkill unblock bluetooth)"
    fi
  done
}

_bluetooth_adapter() {
  local show gekoppelt verbunden
  if ! show=$(timeout 5 bluetoothctl show 2> /dev/null) || [[ -z "$show" ]]; then
    warnung "BlueZ antwortet nicht (bluetoothctl show)"
    return 0
  fi
  if grep -q 'Powered: yes' <<< "$show"; then
    ok "Adapter an (aus- und einschalten im System-Menü)"
  else
    hinweis "Adapter aus (einschalten im System-Menü › Bluetooth)"
  fi
  if grep -q 'Discoverable: yes' <<< "$show"; then
    warnung "Der Rechner ist für andere sichtbar (bluetoothctl discoverable off)"
  else
    ok "Für andere nicht sichtbar"
  fi
  gekoppelt=$(timeout 5 bluetoothctl devices Paired 2> /dev/null | grep -c '^Device ') || gekoppelt=0
  verbunden=$(timeout 5 bluetoothctl devices Connected 2> /dev/null | grep -c '^Device ') || verbunden=0
  hinweis "Gekoppelt: ${gekoppelt}, verbunden: ${verbunden}"
}
