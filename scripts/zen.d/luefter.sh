#!/usr/bin/env bash
# hilfe: luefter [status|auto|1|2|3|4] – Lüfter anzeigen oder einstellen (automatisch oder Mindeststufe)
# «auto» (Standard): Der Kernel (Argon ONE UP) bzw. die Kurve von zenos-argon (Argon ONE V3) regelt allein.
# «1» bis «4»: Mindeststufe. Der Lüfter läuft mindestens so schnell, bei Wärme schneller, nie langsamer als
# automatisch; ab 80 °C immer auf voller Stufe. Der Wunsch bleibt über Neustarts (/var/lib/zenos/luefter) und wirkt
# nach wenigen Sekunden. Setzen braucht sudo; im System-Menü geht dasselbe ohne Passwort (Zeile «Lüfter»).
# «status» zeigt Wunsch, Stufe und Drehzahl, ohne sudo. Einzelheiten: docs/module/m13.md
# shellcheck shell=bash

# Derselbe Helfer, den das System-Menü über pkexec aufruft (feste Stelle in /opt/zenos)
_LUEFTER_HELFER=$ZENOS_CODE/scripts/bin/zenos-luefter
_LUEFTER_STATUS=/run/zenos/geraet.json

befehl_luefter() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen luefter [status|auto|1|2|3|4])"
    return 2
  fi
  case "${1:-status}" in
    status) _luefter_status ;;
    auto | 1 | 2 | 3 | 4) _luefter_setzen "$1" ;;
    *)
      zen_fehler "unbekannte Wahl «$1» (erlaubt: status, auto, 1, 2, 3, 4)"
      return 2
      ;;
  esac
}

# Lüfter aus /run/zenos/geraet.json (von zenos-argon), eine Zeile; Exit 1 ohne Werte
_luefter_wert() {
  if [[ ! -r "$_LUEFTER_STATUS" ]]; then
    printf 'keine Werte (%s fehlt; läuft zenos-argon?)\n' "$_LUEFTER_STATUS"
    return 1
  fi
  jq -r '.luefter | if .vorhanden != true then "kein Lüfter erkannt"
    else ([ (if .prozent != null then "\(.prozent) %"
             elif .stufe == 0 then "aus"
             elif .stufe != null then "Stufe \(.stufe) von \(.stufen)" else empty end),
            (if .upm != null and .prozent == null then "\(.upm) U/min" else empty end),
            (if .steuerbar != true then empty
             elif .modus == "mindest" then "Mindeststufe \(.mindeststufe)" else "automatisch" end)
          ] | join(" · ")) end' "$_LUEFTER_STATUS" 2> /dev/null || printf '%s ist ungültig\n' "$_LUEFTER_STATUS"
}

# Wunsch, den zenos-argon gerade umsetzt: «auto», «mindest N» oder leer (keine Werte, alter Dienst)
_luefter_umgesetzt() {
  [[ -r "$_LUEFTER_STATUS" ]] || return 0
  jq -r '.luefter | if .modus == "mindest" then "mindest \(.mindeststufe)" elif .modus == "auto" then "auto"
    else empty end' "$_LUEFTER_STATUS" 2> /dev/null || true
}

_luefter_status() {
  local temperatur roh
  printf 'Lüfter: %s\n' "$(_luefter_wert)"
  if [[ -x "$_LUEFTER_HELFER" ]]; then
    printf 'Wunsch: %s\n' "$("$_LUEFTER_HELFER" status | sed 's/^Lüfter: //')"
  fi
  roh=$(cat /sys/class/thermal/thermal_zone0/temp 2> /dev/null) || roh=""
  if [[ "$roh" =~ ^-?[0-9]+$ ]]; then
    temperatur=$(( (roh + 500) / 1000 ))
    printf 'CPU: %s °C\n' "$temperatur"
  fi
  printf 'Einstellen: zen luefter auto|1|2|3|4 (oder im System-Menü die Zeile «Lüfter»)\n'
}

_luefter_setzen() {
  local wahl=$1 ziel umgesetzt="" _n
  if [[ ! -x "$_LUEFTER_HELFER" ]]; then
    zen_fehler "$_LUEFTER_HELFER fehlt (install.sh ausführen)"
    return 1
  fi
  $SUDO "$_LUEFTER_HELFER" "$wahl" || return 1
  # Läuft zenos-argon, übernimmt er den Wunsch nach höchstens 2 s (Argon ONE V3: 5 s)
  systemctl --quiet is-active zenos-argon.service 2> /dev/null || {
    printf 'zenos-argon läuft nicht: Der Wunsch wirkt, sobald der Dienst läuft.\n'
    return 0
  }
  if [[ "$wahl" == auto ]]; then ziel=auto; else ziel="mindest $wahl"; fi
  for _n in $(seq 1 16); do
    umgesetzt=$(_luefter_umgesetzt)
    [[ "$umgesetzt" == "$ziel" ]] && break
    sleep 0.5
  done
  if [[ "$umgesetzt" == "$ziel" ]]; then
    printf 'Lüfter jetzt: %s\n' "$(_luefter_wert)"
  else
    printf 'zenos-argon hat den Wunsch noch nicht übernommen (journalctl -u zenos-argon; zen luefter status).\n'
  fi
}
