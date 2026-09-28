#!/usr/bin/env bash
# 75-apps: Werkzeuge für «zen apps» sowie Starter für Chrome und Web-Apps (keine proprietären Apps)
# shellcheck shell=bash
#
# install.sh installiert nie proprietäre Apps, auch nicht im Image. Chrome, VS Code, 1Password und
# coremail kommen erst mit deiner Zustimmung über «zen apps installieren» (erster Start oder
# Einstellungen → Apps). Hier nur die freien Werkzeuge dafür (scripts/pakete/apps.txt: curl, gpg,
# Zertifikate), der Keyring-Ordner und, ausserhalb des Images, die Benutzerteile: Chrome-Starter über
# zenos-chrome, Web-App-Starter aus webapps.json und – wenn 1Password installiert ist – SSH_AUTH_SOCK
# für den SSH-Agent.

modul_system() {
  local keyrings=/etc/apt/keyrings zeile
  local -a pakete=()
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_QUELLE/scripts/pakete/apps.txt"
  pakete_sicherstellen "${pakete[@]}"
  # Ein Symlink auf einen Ordner bleibt, wie er ist (ordner_sicherstellen nimmt nur echte Ordner)
  if [[ ! -L "$keyrings" ]]; then
    ordner_sicherstellen "$keyrings" 0755 root:root
  elif [[ ! -d "$keyrings" ]]; then
    log_warnung "$keyrings zeigt auf keinen Ordner, zen apps kann dort keine Schlüssel ablegen"
  fi
}

modul_benutzer() {
  local apps="$ZENOS_CODE/scripts/bin/zenos-apps" ausgabe zeile
  local starter="$ZENOS_HOME/.local/share/applications"
  # Quickshell beobachtet nur Ordner, die beim Start der Oberfläche schon da sind. Ohne diesen Ordner
  # erschiene die erste Web-App erst nach dem nächsten Anmelden im Befehlsfeld.
  if [[ ! -d "$starter" ]]; then
    if [[ -e "$starter" || -L "$starter" ]]; then
      log_warnung "$starter ist kein Ordner, neue Starter erscheinen erst nach dem nächsten Anmelden"
    else
      benutzer_ordner_sicherstellen "$starter"
    fi
  fi
  if [[ ! -x "$apps" ]]; then
    log_warnung "zenos-apps fehlt unter $ZENOS_CODE, Starter für Chrome und Web-Apps nicht abgeglichen"
    return 0
  fi
  # zenos-apps meldet jede Änderung als eigene Zeile
  if ! ausgabe=$("$apps" benutzer --melden); then
    log_warnung "Starter für Chrome und Web-Apps nicht vollständig abgeglichen (zenos-apps benutzer)"
  fi
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] && aenderung "Apps: $zeile"
  done <<< "$ausgabe"
  return 0
}
