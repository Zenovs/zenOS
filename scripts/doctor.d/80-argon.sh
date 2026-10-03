#!/usr/bin/env bash
# 80-argon: Argon ONE – Dienst, Abschaltsignal, Gerät (Pi 5 mit V3 oder Compute Module 5 mit ONE UP), I2C-Bus,
# Argon an 0x1a bzw. Akku-Messchip an 0x64 (nur lesend), Werte für die Leiste (Akku, Lüfter), Kurve
# shellcheck shell=bash

pruefe_argon() {
  abschnitt "Argon ONE"
  local modell geraet i2c=0
  _argon_einheit
  modell=$(_argon_modell)
  case "$modell" in
    "Raspberry Pi 5"*) geraet=v3 ;;
    "Raspberry Pi Compute Module 5"*) geraet=up ;;
    *) geraet="" ;;
  esac
  # Das Abschaltsignal gibt es nur beim V3; der Hook liegt aber überall (install.sh legt ihn immer ab)
  [[ "$geraet" == up ]] || _argon_abschaltsignal
  if [[ -z "$geraet" ]]; then
    hinweis "Weder Raspberry Pi 5 noch Compute Module 5 (${modell:-kein Gerätebaum}), der Argon-Dienst hat nichts zu tun"
    return 0
  fi
  _argon_temperatur
  if _argon_i2c; then
    i2c=1
    if [[ "$geraet" == up ]]; then _argon_messchip; else _argon_antwort; fi
  fi
  _argon_dienst "$i2c"
  [[ "$geraet" == up ]] || _argon_kurve
  _argon_originalskript
}

_argon_modell() {
  local datei
  for datei in /sys/firmware/devicetree/base/model /proc/device-tree/model; do
    if [[ -r "$datei" ]]; then
      tr -d '\0' < "$datei"
      return 0
    fi
  done
}

_argon_einheit() {
  local einheit=zenos-argon.service zustand
  if [[ ! -f /etc/systemd/system/$einheit ]]; then
    fehler "$einheit fehlt (install.sh ausführen)"
    return 0
  fi
  zustand=$(systemctl is-enabled "$einheit" 2> /dev/null)
  if [[ "$zustand" == enabled ]]; then
    ok "$einheit installiert und aktiviert"
  else
    warnung "$einheit ist nicht aktiviert (${zustand:-unbekannt}; install.sh ausführen)"
  fi
}

# Hook für systemd-shutdown: sendet beim Ausschalten das Abschaltsignal an die Platine (nur lesend geprüft)
_argon_abschaltsignal() {
  local hook=/usr/lib/systemd/system-shutdown/zenos-argon quelle=/opt/zenos/system/systemd/system-shutdown/zenos-argon
  if [[ ! -f "$hook" ]]; then
    fehler "Abschaltsignal beim Ausschalten fehlt: $hook (install.sh ausführen)"
  elif [[ ! -x "$hook" ]]; then
    fehler "$hook ist nicht ausführbar (install.sh ausführen)"
  elif [[ -r "$quelle" ]] && ! cmp -s -- "$quelle" "$hook"; then
    warnung "$hook ist veraltet (install.sh ausführen)"
  elif ! command -v i2cset > /dev/null 2>&1; then
    warnung "i2cset fehlt (Paket i2c-tools): kein Abschaltsignal an die Argon-Platine beim Ausschalten"
  else
    ok "Abschaltsignal an die Argon-Platine beim Ausschalten eingerichtet (${hook%/*}/)"
  fi
}

_argon_temperatur() {
  local roh grad
  roh=$(cat /sys/class/thermal/thermal_zone0/temp 2> /dev/null)
  if [[ ! "$roh" =~ ^-?[0-9]+$ ]]; then
    warnung "CPU-Temperatur nicht lesbar (/sys/class/thermal/thermal_zone0/temp)"
    return 0
  fi
  grad=$(( (roh + 500) / 1000 ))
  if (( grad >= 80 )); then
    warnung "CPU $grad °C – der Pi drosselt ab 80–85 °C (Lüfter prüfen)"
  else
    ok "CPU $grad °C"
  fi
}

# Steht dtparam=i2c_arm=on (oder i2c=on) in einer der Firmware-Dateien? Nur lesen.
_argon_i2c_eingetragen() {
  local -a dateien=()
  local datei
  for datei in /boot/firmware/*.txt; do
    [[ -f "$datei" ]] && dateien+=("$datei")
  done
  (( ${#dateien[@]} > 0 )) || return 1
  grep -Eqs '^[[:space:]]*dtparam=([^#]*,)?i2c(_arm)?(=on)?[[:space:]]*(,|#|$)' -- "${dateien[@]}"
}

_argon_i2c() {
  if [[ -e /dev/i2c-1 ]]; then
    ok "I2C-Bus 1 (/dev/i2c-1)"
    return 0
  fi
  if _argon_i2c_eingetragen; then
    warnung "I2C-Bus 1 fehlt, obwohl dtparam=i2c_arm=on eingetragen ist (wirkt nach einem Neustart)"
  else
    warnung "I2C-Bus 1 fehlt: Der Argon ONE (Lüfter bzw. Akku) braucht dtparam=i2c_arm=on in /boot/firmware/config.txt und einen Neustart (Firmware-Einstellung, zenOS ändert sie nicht selbst)"
  fi
  return 1
}

# Nur lesen (i2cget ohne Register = «receive byte»), nie an den Argon schreiben
_argon_antwort() {
  if ! command -v i2cget > /dev/null 2>&1; then
    hinweis "i2cget fehlt (Paket i2c-tools), Argon an 0x1a nicht direkt geprüft"
    return 0
  fi
  if [[ ! -r /dev/i2c-1 || ! -w /dev/i2c-1 ]]; then
    hinweis "Argon an 0x1a nur mit Zugriff auf /dev/i2c-1 direkt prüfbar (sudo /opt/zenos/scripts/bin/zenos-argon --pruefen)"
    return 0
  fi
  if i2cget -y 1 0x1a > /dev/null 2>&1; then
    ok "Argon ONE antwortet an I2C-Adresse 0x1a"
  else
    warnung "Keine Antwort an I2C-Adresse 0x1a (Argon-Platine nicht erkannt)"
  fi
}

# Argon ONE UP: Akku-Messchip CW2217 an 0x64, nur Chip-ID lesen (Register 0x00 = 0xa0), nie schreiben
_argon_messchip() {
  local id
  if ! command -v i2cget > /dev/null 2>&1; then
    hinweis "i2cget fehlt (Paket i2c-tools), Akku-Messchip an 0x64 nicht direkt geprüft"
    return 0
  fi
  if [[ ! -r /dev/i2c-1 || ! -w /dev/i2c-1 ]]; then
    hinweis "Akku-Messchip an 0x64 nur mit Zugriff auf /dev/i2c-1 direkt prüfbar (sudo /opt/zenos/scripts/bin/zenos-argon --pruefen)"
    return 0
  fi
  id=$(i2cget -y 1 0x64 0x00 2> /dev/null) || id=""
  case "$id" in
    0xa0) ok "Akku-Messchip CW2217 antwortet an I2C-Adresse 0x64 (Argon ONE UP)" ;;
    "") warnung "Keine Antwort an I2C-Adresse 0x64 (Akku-Messchip des Argon ONE UP nicht erkannt)" ;;
    *) warnung "An I2C-Adresse 0x64 antwortet kein CW2217 (Chip-ID $id statt 0xa0)" ;;
  esac
}

# Letzte Meldung von zenos-argon selbst (Gerätemeldungen, keine persönlichen Daten), falls lesbar
_argon_letzte_meldung() {
  journalctl -q -n 1 -o cat --no-pager SYSLOG_IDENTIFIER=zenos-argon 2> /dev/null | tail -n 1 | cut -c 1-200
}

_argon_dienst() {
  local i2c=$1 einheit=zenos-argon.service aktiv ergebnis meldung
  aktiv=$(systemctl is-active "$einheit" 2> /dev/null)
  case "$aktiv" in
    active)
      ok "Dienst $einheit läuft"
      _argon_werte
      return 0
      ;;
    activating) hinweis "$einheit startet gerade neu (journalctl -u $einheit)"; return 0 ;;
    failed) fehler "$einheit ist fehlgeschlagen (journalctl -u $einheit)"; return 0 ;;
  esac
  ergebnis=$(systemctl show -p Result --value "$einheit" 2> /dev/null)
  meldung=$(_argon_letzte_meldung)
  if (( ! i2c )); then
    hinweis "$einheit ruht ohne I2C-Bus${meldung:+ · $meldung}"
  elif [[ "$ergebnis" == success ]]; then
    warnung "$einheit läuft nicht, der Argon-Lüfter wird nicht geregelt${meldung:+ · $meldung}"
  else
    fehler "$einheit läuft nicht (${ergebnis:-unbekannt}; journalctl -u $einheit)"
  fi
}

# /run/zenos/geraet.json (Version 1): Alter, Akku, Lüfter. Nur Gerätewerte, nichts Persönliches.
_argon_werte() {
  local datei=/run/zenos/geraet.json jetzt zeit alter zeile geraet temperatur luefter akku zustand
  if [[ ! -r "$datei" ]]; then
    fehler "$datei fehlt, obwohl zenos-argon läuft"
    return 0
  fi
  jetzt=$(date +%s)
  zeit=$(stat -c %Y -- "$datei" 2> /dev/null)
  alter=$(( jetzt - ${zeit:-0} ))
  # eine Zeile, Felder mit «|» getrennt: Gerät|Temperatur|Lüfter|Akku|Akku-Zustand
  zeile=$(jq -r 'select(.version == 1) | [
      .geraet,
      (.temperatur.cpu // "?" | if type == "number" then round else . end),
      (.luefter | if .vorhanden != true then "kein Lüfter"
                  elif .prozent != null then "Lüfter \(.prozent) %"
                  elif .stufe == 0 then "Lüfter aus"
                  elif .stufe != null then "Lüfter Stufe \(.stufe) von \(.stufen)"
                    + (if .upm != null then " · \(.upm) U/min" else "" end)
                  elif .upm != null then "Lüfter \(.upm) U/min"
                  else "Lüfter ohne Werte" end),
      (.akku | if .vorhanden != true then "" elif .prozent != null
               then "Akku \(.prozent) %" + (if .laedt == true then ", lädt" elif .laedt == false then ", Akkubetrieb"
                                              else "" end)
               else "Akku ohne Wert" end),
      (.akku.zustand // "")
    ] | map(tostring) | join("|")' "$datei" 2> /dev/null) || zeile=""
  if [[ -z "$zeile" ]]; then
    fehler "$datei ist ungültig"
    return 0
  fi
  IFS='|' read -r geraet temperatur luefter akku zustand <<< "$zeile"
  if (( alter > 60 )); then
    warnung "Werte in $datei sind $alter s alt (hängt zenos-argon? sudo systemctl restart zenos-argon)"
    return 0
  fi
  case "$luefter" in
    "Lüfter ohne Werte") warnung "Leiste bekommt $temperatur °C, der Lüfter antwortet aber nicht (journalctl -u zenos-argon)" ;;
    *) ok "Leiste bekommt $temperatur °C · $luefter (${geraet:-?}, vor $alter s)" ;;
  esac
  [[ "$geraet" == argon-one-up ]] || return 0
  case "$zustand" in
    ok) ok "$akku" ;;
    unbekannt) hinweis "Akku: noch kein Messwert (der Messchip startet gerade; journalctl -u zenos-argon)" ;;
    freigabe) hinweis "Akku: Der Messchip misst nicht, und das Akkuprofil schreiben ist nicht freigegeben (zen akku freigeben)" ;;
    *) warnung "Akku nicht lesbar (${zustand:-unbekannt}; journalctl -u zenos-argon)" ;;
  esac
}

_argon_kurve() {
  local programm=/opt/zenos/scripts/bin/zenos-argon ausgabe
  [[ -x "$programm" ]] || { fehler "$programm fehlt"; return 0; }
  if ausgabe=$("$programm" --konfig-pruefen 2>&1); then
    ok "$(tail -n 1 <<< "$ausgabe")"
  else
    warnung "/etc/xdg/zenos/argon.json ist ungültig, es gilt die Standardkurve ($(grep -m 1 '^Ungültig:' <<< "$ausgabe" | cut -d ' ' -f 2-))"
  fi
}

_argon_originalskript() {
  local zustand
  zustand=$(systemctl is-enabled argononeupd.service 2> /dev/null)
  case "$zustand" in
    enabled | enabled-runtime | static | alias | generated | indirect)
      warnung "argononeupd.service (Argon-Software für den ONE UP) ist eingerichtet: zenos-argon liest den Akku nur (argon-uninstall)"
      ;;
  esac
  zustand=$(systemctl is-enabled argononed.service 2> /dev/null)
  case "$zustand" in
    enabled | enabled-runtime | static | alias | generated | indirect)
      warnung "argononed.service (Argon-Originalskript) ist eingerichtet und stört zenos-argon (argonone-uninstall)"
      ;;
  esac
  if [[ -e /usr/lib/systemd/system-shutdown/argon-shutdown.sh ]]; then
    hinweis "argon-shutdown.sh (Argon-Originalskript) sendet das Abschaltsignal, zenos-argon hält sich heraus (argonone-uninstall)"
  fi
}
