#!/usr/bin/env bash
# 00-vorbereitung: System prüfen und die Werkzeuge des Installers sicherstellen
# shellcheck shell=bash

modul_system() {
  befehl_vorhanden apt-get || abbruch "apt-get fehlt: zenOS braucht Ubuntu (getestet: 26.04 LTS)"

  local id="" version="" name="" arch
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    id=$(. /etc/os-release && printf '%s' "${ID:-}")
    # shellcheck disable=SC1091
    version=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")
    # shellcheck disable=SC1091
    name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-}")
  fi
  arch=$(dpkg --print-architecture)

  if [[ "$id" == ubuntu && "$version" == 26.04 ]]; then
    log_info "${name:-Ubuntu 26.04} · $arch"
  else
    log_warnung "zenOS ist für Ubuntu 26.04 gebaut, gefunden: ${name:-unbekannt}. Die Installation läuft trotzdem weiter."
  fi
  case "$arch" in
    arm64 | amd64) ;;
    *) log_warnung "Architektur $arch ist nicht vorgesehen (arm64 oder amd64). Die Installation läuft trotzdem weiter." ;;
  esac

  local frei
  frei=$(df -P -k / | awk 'NR == 2 { print $4 }')
  if [[ "$frei" =~ ^[0-9]+$ ]] && (( frei < 1048576 )); then
    log_warnung "Weniger als 1 GB frei auf / – der Quickshell-Bau braucht mehr Platz."
  fi

  # Werkzeuge, die install.sh selbst braucht (10-code, json_pruefen)
  pakete_sicherstellen git python3 python3-jsonschema
}
