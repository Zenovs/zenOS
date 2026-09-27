#!/usr/bin/env bash
# 80-argon: Argon ONE V3 am Raspberry Pi 5 – Dienst für Lüfterkurve und Power-Button
# shellcheck shell=bash
#
# Installiert zenos-argon.service nach /etc/systemd/system und aktiviert ihn. Ausser im Image-Modus startet
# das Modul ihn auch (nach einer Änderung an der Einheit oder wenn zenos-argon neuer ist als der laufende
# Dienst). Ob es etwas zu tun gibt (Pi 5, I2C-Bus 1, Argon an 0x1a), entscheidet der Dienst selbst; sonst
# endet er mit einer Meldung. Dazu der Hook /usr/lib/systemd/system-shutdown/zenos-argon, der beim
# Ausschalten das Abschaltsignal an die Platine sendet. Firmware und /boot/firmware/config.txt fasst zenOS
# nie an: Fehlt auf einem Pi 5 der I2C-Bus, gibt es nur einen Hinweis (Rückfrage-Thema).

modul_system() {
  local einheit=zenos-argon.service zeile
  local -a pakete=()
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_CODE/scripts/pakete/argon.txt"
  pakete_sicherstellen "${pakete[@]}"

  datei_installieren "$ZENOS_CODE/system/systemd/system/$einheit" "/etc/systemd/system/$einheit" 0644 root:root
  dienst_aktivieren "$einheit"
  if modul_geaendert; then
    _argon_starten "$einheit" "neu eingerichtet"
  elif _argon_code_neuer "$einheit"; then
    _argon_starten "$einheit" "zenos-argon ist neuer als der laufende Dienst"
  fi

  # Abschaltsignal an die Platine ganz am Ende des Ausschaltens (wie argon-shutdown.sh im Original). Eine
  # Kopie, kein Verweis nach /opt/zenos: systemd-shutdown ruft den Hook, wenn die Dateisysteme schon
  # ausgehängt oder nur lesbar sind. Nach dem Start-Entscheid, damit eine Änderung nur am Hook den Dienst
  # nicht neu startet.
  datei_installieren "$ZENOS_CODE/system/systemd/system-shutdown/zenos-argon" \
    /usr/lib/systemd/system-shutdown/zenos-argon 0755 root:root

  _argon_i2c_hinweis
  _argon_originalskript
}

# Startet den Dienst neu (nicht im Image, nur mit laufendem systemd). Ein Fehler hält die Installation nicht
# auf: Der Dienst regelt nur den Lüfter, und systemd versucht es beim nächsten Start wieder.
_argon_starten() {
  local einheit=$1 grund=$2
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  systemd_neu_laden
  $SUDO systemctl reset-failed "$einheit" 2> /dev/null || true
  if $SUDO systemctl restart "$einheit"; then
    log_info "Dienst gestartet: $einheit ($grund)"
  else
    log_warnung "$einheit liess sich nicht starten (journalctl -u $einheit)"
  fi
}

# 0, wenn der Dienst läuft und zenos-argon seit seinem Start geändert wurde (z. B. nach zen update).
# Kein Zähler: Ein Neustart ändert nichts am System.
_argon_code_neuer() {
  local einheit=$1 start code
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 1
  systemctl --quiet is-active "$einheit" 2> /dev/null || return 1
  start=$(systemctl show --timestamp=unix -p ExecMainStartTimestamp --value "$einheit" 2> /dev/null) || return 1
  start=${start#@}
  code=$(stat -c %Y -- "$ZENOS_CODE/scripts/bin/zenos-argon" 2> /dev/null) || return 1
  [[ "$start" =~ ^[0-9]+$ && "$code" =~ ^[0-9]+$ ]] || return 1
  (( code > start ))
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

# Hinweis (keine Warnung), wenn der Argon-Lüfter mangels I2C nicht geregelt werden kann
_argon_i2c_hinweis() {
  local modell
  if [[ "$ZENOS_IMAGE" == 1 ]]; then
    # Im Image gibt es kein /dev/i2c-1; nur die Firmware-Konfiguration des Images ansehen
    [[ -f /boot/firmware/config.txt ]] || return 0
    _argon_i2c_eingetragen && return 0
    log_info "Hinweis: In /boot/firmware/config.txt des Images fehlt dtparam=i2c_arm=on (Argon-Lüfter über I2C)."
    log_info "zenOS ändert Firmware-Einstellungen nicht selbst."
    return 0
  fi
  modell=$(_argon_modell)
  [[ "$modell" == "Raspberry Pi 5"* ]] || return 0
  [[ -e /dev/i2c-1 ]] && return 0
  if _argon_i2c_eingetragen; then
    log_info "Hinweis: dtparam=i2c_arm=on steht in /boot/firmware, /dev/i2c-1 fehlt aber noch (wirkt nach einem Neustart)."
  else
    log_info "Hinweis: Für den Argon ONE braucht es I2C: dtparam=i2c_arm=on in /boot/firmware/config.txt, danach Neustart."
    log_info "zenOS ändert Firmware-Einstellungen nicht selbst. Ohne I2C regelt zenos-argon den Lüfter nicht."
  fi
}

# Das Installationsskript von Argon richtet argononed.service und argon-shutdown.sh ein; zwei Dienste am
# selben Lüfter und Knopf stören sich gegenseitig.
_argon_originalskript() {
  local zustand
  zustand=$(systemctl is-enabled argononed.service 2> /dev/null) || true
  case "$zustand" in
    enabled | enabled-runtime | static | alias | generated | indirect)
      log_warnung "argononed.service (Argon-Originalskript) ist eingerichtet und stört zenos-argon an Lüfter und Knopf. Entfernen: argonone-uninstall oder sudo systemctl disable --now argononed.service"
      return 0
      ;;
  esac
  if [[ -e /usr/lib/systemd/system-shutdown/argon-shutdown.sh ]]; then
    log_info "Hinweis: argon-shutdown.sh (Argon-Originalskript) liegt noch in /usr/lib/systemd/system-shutdown; zenos-argon überlässt ihm das Abschaltsignal (entfernen: argonone-uninstall)."
  fi
}
