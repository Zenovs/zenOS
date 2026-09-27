#!/usr/bin/env bash
# 65-oberflaeche: Sperrbildschirm (automatische Sperre, Notfall-Sperre) und Hilfsprogramme der Oberfläche
# shellcheck shell=bash
#
# Der PAM-Dienst des Sperrbildschirms (system/pam/zenos-sperre) wird nicht kopiert: Quickshell liest ihn
# direkt aus /opt/zenos/system/pam (PamContext.configDirectory, im Container geprüft). Die Pakete aus
# scripts/pakete/sperre.txt installiert 20-pakete; hier wird nur nachgesehen.

modul_system() {
  local paket zeile
  local -a fehlend=()
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    paket=${zeile//[[:space:]]/}
    [[ -n "$paket" ]] || continue
    paket_installiert "$paket" || fehlend+=("$paket")
  done < "$ZENOS_CODE/scripts/pakete/sperre.txt"
  if (( ${#fehlend[@]} > 0 )); then
    log_warnung "Für den Sperrbildschirm fehlt: ${fehlend[*]} (automatische Sperre bzw. Notfall-Sperre eingeschränkt)"
  fi

  local datei
  for datei in /etc/pam.d/common-auth /etc/pam.d/common-account; do
    [[ -f "$datei" ]] || log_warnung "$datei fehlt: Der PAM-Dienst zenos-sperre bindet sie ein"
  done

  # systemd-Benutzerdienst. Direkt nach /etc/systemd/user: /etc/xdg/systemd/user ist unter Ubuntu nur ein
  # Symlink dorthin, und «install -D» aus uutils (Ubuntu 26.04) ersetzt einen solchen Symlink durch einen
  # leeren Ordner, den systemd nicht durchsucht.
  datei_installieren "$ZENOS_CODE/system/systemd/user/zenos-idle.service" \
    /etc/systemd/user/zenos-idle.service 0644 root:root
}

modul_benutzer() {
  # Läuft die Sitzung schon (Installation per SSH), startet die automatische Sperre sofort statt erst
  # bei der nächsten Anmeldung.
  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$EUID}
  [[ "$ZENOS_SYSTEMD" == 1 && -S "$laufzeit/bus" ]] || return 0
  XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-sitzung.target 2>/dev/null || return 0
  XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-idle.service 2>/dev/null && return 0
  if XDG_RUNTIME_DIR=$laufzeit systemctl --user start zenos-idle.service 2>/dev/null; then
    aenderung "Automatische Sperre gestartet (zenos-idle.service)"
  else
    log_warnung "zenos-idle.service liess sich nicht starten (systemctl --user status zenos-idle)"
  fi
}
