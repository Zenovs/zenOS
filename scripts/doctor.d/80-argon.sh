#!/usr/bin/env bash
# 80-argon: Argon ONE – Dienst, Abschaltsignal, Pi-Modell, I2C-Bus, Argon an 0x1a (nur lesend), Werte für die
# Leiste, Kurve
# shellcheck shell=bash

pruefe_argon() {
  abschnitt "Argon ONE"
  local modell i2c=0
  _argon_einheit
  _argon_abschaltsignal
  modell=$(_argon_modell)
  if [[ "$modell" != "Raspberry Pi 5"* ]]; then
    hinweis "Kein Raspberry Pi 5 (${modell:-kein Gerätebaum}), der Argon-Dienst hat nichts zu tun"
    return 0
  fi
  _argon_temperatur
  if _argon_i2c; then
    i2c=1
    _argon_antwort
  fi
  _argon_dienst "$i2c"
  _argon_kurve
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
    warnung "I2C-Bus 1 fehlt: Der Argon-Lüfter braucht dtparam=i2c_arm=on in /boot/firmware/config.txt und einen Neustart (Firmware-Einstellung, zenOS ändert sie nicht selbst)"
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

_argon_werte() {
  local datei=/run/zenos/argon.json jetzt zeit alter temperatur luefter
  if [[ ! -r "$datei" ]]; then
    fehler "$datei fehlt, obwohl zenos-argon läuft"
    return 0
  fi
  jetzt=$(date +%s)
  zeit=$(stat -c %Y -- "$datei" 2> /dev/null)
  alter=$(( jetzt - ${zeit:-0} ))
  temperatur=$(jq -r '.temperatur' "$datei" 2> /dev/null)
  luefter=$(jq -r '.luefter' "$datei" 2> /dev/null)
  if [[ ! "$temperatur" =~ ^-?[0-9]+$ || ! "$luefter" =~ ^-?[0-9]+$ ]]; then
    fehler "$datei ist ungültig"
    return 0
  fi
  if (( alter > 30 )); then
    warnung "Werte in $datei sind $alter s alt (hängt zenos-argon? sudo systemctl restart zenos-argon)"
    return 0
  fi
  (( temperatur >= 0 )) || temperatur="?"
  if (( luefter < 0 )); then
    warnung "Leiste bekommt $temperatur °C, der Lüfter antwortet aber nicht (journalctl -u zenos-argon)"
  else
    ok "Leiste bekommt $temperatur °C · Lüfter $luefter % (vor $alter s)"
  fi
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
