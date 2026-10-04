#!/usr/bin/env bash
# 00-vorbereitung: System prüfen und die Werkzeuge des Installers sicherstellen
# shellcheck shell=bash

modul_system() {
  befehl_vorhanden apt-get || abbruch "apt-get fehlt: zenOS braucht Ubuntu (getestet: 26.04 LTS)"

  # Gültig ist Ubuntu 26.04 als Kennung oder, mit der Kennung zenOS (72-kennung), als Basis: ID=zenos mit «ubuntu» in
  # ID_LIKE, Version und Name aus der umgelenkten Ubuntu-Fassung /usr/lib/os-release.ubuntu.
  local name basis arch
  name=$(os_release_wert PRETTY_NAME)
  basis=$(os_release_wert PRETTY_NAME "$(basis_os_release)")
  [[ "$basis" != "$name" ]] || basis=""
  arch=$(dpkg --print-architecture)

  if system_unterstuetzt; then
    log_info "${name:-Ubuntu 26.04}${basis:+ · Basis $basis} · $arch"
  else
    log_warnung "zenOS ist für Ubuntu 26.04 gebaut, gefunden: ${name:-unbekannt}${basis:+ (Basis $basis)}. Die Installation läuft trotzdem weiter."
  fi
  case "$arch" in
    arm64 | amd64) ;;
    *) log_warnung "Architektur $arch ist nicht vorgesehen (arm64 oder amd64). Die Installation läuft trotzdem weiter." ;;
  esac

  # Quickshell wird in /var/tmp gebaut: der Build-Ordner hat vor dem Strip rund 2,5 GB, 25-quickshell bricht
  # unter 3,5 GB frei ab. Hier nur eine frühe Warnung, solange Quickshell noch nicht gebaut ist.
  local frei
  if [[ ! -x /usr/local/bin/quickshell || ! -f /usr/local/share/zenos/quickshell.version ]]; then
    frei=$(df -P -k /var/tmp 2>/dev/null | awk 'NR == 2 { print $4 }')
    if [[ "$frei" =~ ^[0-9]+$ ]] && (( frei < 3670016 )); then
      log_warnung "Nur $(( frei / 1024 )) MB frei in /var/tmp – der Quickshell-Bau braucht etwa 3,5 GB."
    fi
  fi
  frei=$(df -P -k / | awk 'NR == 2 { print $4 }')
  if [[ "$frei" =~ ^[0-9]+$ ]] && (( frei < 1048576 )); then
    log_warnung "Weniger als 1 GB frei auf / – für die Pakete wird es knapp."
  fi

  # Werkzeuge, die install.sh selbst braucht (10-code, json_pruefen)
  pakete_sicherstellen git python3 python3-jsonschema
}
