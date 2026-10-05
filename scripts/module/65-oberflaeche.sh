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
  # Symlink dorthin, und systemd 259 durchsucht /etc/xdg/systemd/user nur über XDG_CONFIG_DIRS, das in der
  # Benutzerinstanz meist nicht gesetzt ist. /etc/systemd/user gilt immer.
  datei_installieren "$ZENOS_CODE/system/systemd/user/zenos-idle.service" \
    /etc/systemd/user/zenos-idle.service 0644 root:root
}

modul_benutzer() {
  # Läuft die Sitzung schon (Installation per SSH), startet die automatische Sperre sofort statt erst
  # bei der nächsten Anmeldung.
  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$EUID}
  [[ "$ZENOS_SYSTEMD" == 1 && -S "$laufzeit/bus" ]] || return 0
  XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-sitzung.target 2>/dev/null || return 0
  if XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-idle.service 2>/dev/null; then
    _oberflaeche_idle_neu_laden "$laufzeit"
    return 0
  fi
  if XDG_RUNTIME_DIR=$laufzeit systemctl --user start zenos-idle.service 2>/dev/null; then
    aenderung "Automatische Sperre gestartet (zenos-idle.service)"
  else
    log_warnung "zenos-idle.service liess sich nicht starten (systemctl --user status zenos-idle)"
  fi
}

# Läuft zenos-idle mit einem älteren Stand (zen update), neu starten, damit die neue Leerlauf-Logik ohne
# neues Anmelden gilt – aber nur, wenn die Sitzung gesperrt ist: Ein Neustart beginnt die Leerlaufzeit von
# vorn und schöbe die automatische Sperre sonst hinaus. Ungesperrt übernimmt zenos-idle den neuen Stand selbst
# bei der nächsten Sperre (ein Stand von vor der Bildschirm-Abschaltung erst nach dem nächsten Anmelden).
# Kein Zähler: Ein Neustart ändert nichts am System (wie 55-zustaende).
_oberflaeche_idle_neu_laden() {
  local laufzeit=$1 einheit=zenos-idle.service start datei code neuer=0
  start=$(XDG_RUNTIME_DIR=$laufzeit systemctl --user show --timestamp=unix -p ExecMainStartTimestamp --value \
    "$einheit" 2>/dev/null) || return 0
  start=${start#@}
  [[ "$start" =~ ^[0-9]+$ ]] || return 0
  for datei in "$ZENOS_CODE/scripts/bin/zenos-idle" "$ZENOS_CODE/scripts/bin/zenos-bildschirm"; do
    code=$(stat -c %Y -- "$datei" 2>/dev/null) || continue
    if [[ "$code" =~ ^[0-9]+$ ]] && (( code > start )); then neuer=1; fi
  done
  (( neuer )) || return 0
  if [[ ! -e "$laufzeit/zenos/gesperrt" ]]; then
    log_info "Automatische Sperre geändert; zenos-idle übernimmt den neuen Stand bei der nächsten Sperre."
    return 0
  fi
  if XDG_RUNTIME_DIR=$laufzeit systemctl --user try-restart "$einheit" 2>/dev/null; then
    log_info "Automatische Sperre neu gestartet (neuer Stand von zenos-idle, gesperrt)"
  else
    log_warnung "$einheit liess sich nicht neu starten (systemctl --user status zenos-idle)"
  fi
}
