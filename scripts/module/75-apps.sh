#!/usr/bin/env bash
# 75-apps: Werkzeuge für «zen apps» sowie Starter für Chrome und Web-Apps (keine proprietären Apps)
# shellcheck shell=bash
#
# install.sh installiert nie proprietäre Apps, auch nicht im Image. Chrome, VS Code, 1Password und
# coremail kommen erst mit deiner Zustimmung über «zen apps installieren» (erster Start oder
# Einstellungen → Apps). Hier nur die freien Werkzeuge dafür (curl, gpg, Zertifikate, Keyring-Ordner)
# und, ausserhalb des Images, die Benutzerteile: Chrome-Starter über zenos-chrome, Web-App-Starter
# aus webapps.json und – wenn 1Password installiert ist – SSH_AUTH_SOCK für den SSH-Agent.

modul_system() {
  pakete_sicherstellen ca-certificates curl gpg
  ordner_sicherstellen /etc/apt/keyrings 0755 root:root
}

modul_benutzer() {
  local apps="$ZENOS_CODE/scripts/bin/zenos-apps" ausgabe zeile
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
