#!/usr/bin/env bash
# 65-sperre: Sperrbildschirm – PAM-Dienst, automatische Sperre (zenos-idle), Sperrzeit, Notfall-Sperre
# shellcheck shell=bash

pruefe_sperre() {
  abschnitt "Sperrbildschirm"
  _sperre_pam
  _sperre_pakete
  _sperre_dienst
  _sperre_zeit
  _sperre_einspasswort
}

# PAM-Dienst zenos-sperre: liegt im Code-Checkout, gehört root, bindet vorhandene Dateien ein
_sperre_pam() {
  local datei=/opt/zenos/system/pam/zenos-sperre recht besitz ziel fehlend=()
  if [[ ! -f "$datei" ]]; then
    fehler "PAM-Dienst fehlt: $datei (Sperrbildschirm weicht auf /etc/pam.d/login aus; zen update oder install.sh)"
    return 0
  fi
  besitz=$(stat -c '%U' -- "$datei" 2>/dev/null)
  recht=$(stat -c '%a' -- "$datei" 2>/dev/null)
  if [[ "$besitz" != root ]] || (( (8#${recht:-777} & 8#022) != 0 )); then
    fehler "PAM-Dienst $datei gehört $besitz mit Rechten $recht (erwartet: root, für andere nicht schreibbar)"
    return 0
  fi
  while read -r ziel; do
    [[ -f "$ziel" ]] || fehlend+=("$ziel")
  done < <(awk '$2 == "include" && $3 ~ /^\// { print $3 }' "$datei")
  if (( ${#fehlend[@]} > 0 )); then
    fehler "PAM-Dienst zenos-sperre bindet fehlende Dateien ein: ${fehlend[*]}"
  else
    ok "PAM-Dienst zenos-sperre (/opt/zenos/system/pam)"
  fi
}

_sperre_pakete() {
  if command -v swayidle >/dev/null 2>&1; then
    ok "swayidle installiert"
  else
    fehler "swayidle fehlt – keine automatische Sperre (sudo apt install swayidle)"
  fi
  if ! command -v swaylock >/dev/null 2>&1; then
    warnung "swaylock fehlt – keine Notfall-Sperre, falls die Oberfläche nicht antwortet (sudo apt install swaylock)"
  elif [[ ! -f /etc/pam.d/swaylock ]]; then
    warnung "swaylock ohne PAM-Dienst /etc/pam.d/swaylock – die Notfall-Sperre liesse sich nicht entsperren"
  else
    ok "Notfall-Sperre swaylock bereit"
  fi
}

# zenos-idle.service: vorhanden, von der Sitzung gewollt und in einer laufenden Sitzung aktiv
_sperre_dienst() {
  local laufzeit einheit=zenos-idle.service ladung aktiv
  local -a sc
  if [[ ! -f /etc/systemd/user/$einheit ]]; then
    fehler "$einheit fehlt (install.sh ausführen)"
    return 0
  fi
  laufzeit=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  sc=(env "XDG_RUNTIME_DIR=$laufzeit" systemctl --user)
  if [[ ! -S "$laufzeit/bus" ]] || ! "${sc[@]}" show-environment >/dev/null 2>&1; then
    ok "$einheit vorhanden"
    hinweis "systemd-Benutzerinstanz nicht erreichbar, automatische Sperre nicht geprüft"
    return 0
  fi
  ladung=$("${sc[@]}" show -p LoadState --value "$einheit" 2>/dev/null)
  if [[ "$ladung" != loaded ]]; then
    fehler "$einheit ist nicht geladen (${ladung:-unbekannt}; systemctl --user daemon-reload)"
    return 0
  fi
  if ! "${sc[@]}" show -p Wants --value zenos-sitzung.target 2>/dev/null | tr ' ' '\n' | grep -qx "$einheit"; then
    fehler "zenos-sitzung.target startet $einheit nicht (Wants= fehlt)"
  fi
  if ! "${sc[@]}" --quiet is-active zenos-sitzung.target 2>/dev/null; then
    ok "$einheit vorhanden"
    hinweis "Keine laufende zenOS-Sitzung, automatische Sperre erst nach der Anmeldung prüfbar"
    return 0
  fi
  aktiv=$("${sc[@]}" is-active "$einheit" 2>/dev/null)
  if [[ "$aktiv" == active ]]; then
    ok "Automatische Sperre läuft ($einheit)"
  else
    fehler "Automatische Sperre läuft nicht ($einheit: ${aktiv:-unbekannt}; journalctl --user -u $einheit)"
  fi
}

# Sperrzeit aus den Einstellungen (nur die wirksame Zahl, keine weiteren Inhalte)
_sperre_zeit() {
  local idle=/opt/zenos/scripts/bin/zenos-idle ergebnis minuten art
  if [[ ! -x "$idle" ]]; then
    fehler "$idle fehlt"
    return 0
  fi
  ergebnis=$("$idle" pruefen 2>/dev/null)
  read -r minuten art <<< "$ergebnis"
  if [[ ! "$minuten" =~ ^[0-9]+$ ]] || (( minuten < 1 || minuten > 15 )); then
    fehler "Sperrzeit nicht ermittelbar (zenos-idle pruefen)"
    return 0
  fi
  case "$art" in
    standard) ok "Automatische Sperre nach $minuten Min. (Standard)" ;;
    einstellung) ok "Automatische Sperre nach $minuten Min." ;;
    begrenzt) warnung "sperreNachMinuten liegt ausserhalb von 1–15, wirksam sind $minuten Min. (Einstellungen → Allgemein)" ;;
    *) warnung "sperreNachMinuten ist keine Zahl oder einstellungen.json ist ungültig, wirksam sind $minuten Min." ;;
  esac
}

_sperre_einspasswort() {
  if [[ -x /opt/1Password/1password || -x /usr/bin/1password ]]; then
    ok "1Password sperrt sich mit"
  else
    hinweis "1Password nicht installiert (Sperrbildschirm zeigt «zenOS gesperrt»)"
  fi
}
