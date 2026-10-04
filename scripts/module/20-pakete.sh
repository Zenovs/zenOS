#!/usr/bin/env bash
# 20-pakete: alle apt-Pakete der Module in einem Durchgang (ohne Build-Abhängigkeiten von Quickshell)
# shellcheck shell=bash
#
# Liest scripts/pakete/*.txt (ein Paket pro Zeile, «#» Kommentar) ausser quickshell-bau.txt und installiert
# nur, was fehlt. Pakete starten ihre Dienste dabei nicht (policy-rc.d in pakete_sicherstellen), greetd
# läuft also erst nach dem Neustart. Fehlt ein Paket in
# den Paketquellen (z. B. nicht für diese Architektur), wird es mit einer Warnung übersprungen, statt die
# ganze Installation aufzuhalten.
# Danach sind alle Pakete dieser Listen als manuell installiert markiert (pakete_manuell_markieren): Was schon als
# Abhängigkeit eines Ubuntu-Metapakets da war (ufw, unattended-upgrades, jq …), entfernte «apt autoremove» sonst,
# sobald das Metapaket wegfällt. Die Build-Abhängigkeiten von Quickshell (quickshell-bau.txt) bleiben, wie sie sind.

modul_system() {
  local -a pakete=()
  mapfile -t pakete < <(_pakete_liste "$ZENOS_CODE/scripts/pakete")
  (( ${#pakete[@]} > 0 )) || { log_warnung "Keine Paketlisten unter $ZENOS_CODE/scripts/pakete gefunden"; return 0; }

  _pakete_installieren "${pakete[@]}"
  pakete_manuell_markieren "${pakete[@]}"
}

_pakete_installieren() {
  local paket
  local -a pakete=("$@") fehlend=() verfuegbar=() unbekannt=()
  for paket in "${pakete[@]}"; do
    paket_installiert "$paket" || fehlend+=("$paket")
  done
  if (( ${#fehlend[@]} == 0 )); then
    log_info "${#pakete[@]} Pakete vorhanden"
    return 0
  fi

  # Erster Versuch mit allem, was fehlt. In einer Subshell, damit ein unbekanntes Paket nicht sofort
  # abbricht (die Zähler sind subshell-fest).
  if (pakete_sicherstellen "${fehlend[@]}"); then
    _pakete_dbus_neu_laden
    return 0
  fi

  # Pakete ohne Installationskandidat aussortieren und den Rest noch einmal versuchen
  for paket in "${fehlend[@]}"; do
    if _pakete_kandidat "$paket"; then verfuegbar+=("$paket"); else unbekannt+=("$paket"); fi
  done
  (( ${#unbekannt[@]} > 0 )) || abbruch "Paketinstallation fehlgeschlagen (Details oben und in /var/log/apt/term.log)"
  log_warnung "Nicht in den Paketquellen, übersprungen: ${unbekannt[*]}"
  (( ${#verfuegbar[@]} == 0 )) || pakete_sicherstellen "${verfuegbar[@]}"
  _pakete_dbus_neu_laden
}

# Sicherheitsnetz: Neue Pakete bringen D-Bus-Richtlinien für eben angelegte Systembenutzer mit (z. B. polkitd).
# Deren postinst lädt den System-Bus selbst neu – die policy-rc.d aus pakete_sicherstellen erlaubt «dbus
# reload». Pakete, die das nicht tun, bekämen ihre Richtlinie sonst erst nach dem Neustart (bei polkit:
# Neustart/Ausschalten im Login, Sperre vor dem Standby). Neu laden trennt keine Verbindungen.
_pakete_dbus_neu_laden() {
  [[ "$ZENOS_SYSTEMD" == 1 ]] || return 0
  modul_geaendert || return 0
  systemctl is-active --quiet dbus.service 2> /dev/null || return 0
  $SUDO systemctl reload dbus.service > /dev/null 2>&1 ||
    log_warnung "System-Bus (dbus) liess sich nicht neu laden; nach dem nächsten Neustart ist es erledigt"
}

# Vereinigung aller Listen, sortiert und ohne Doppelte
_pakete_liste() {
  local ordner=$1 datei name zeile wort
  local -a woerter
  local -A gesehen=()
  for datei in "$ordner"/*.txt; do
    [[ -f "$datei" ]] || continue
    name=$(basename -- "$datei")
    [[ "$name" != quickshell-bau.txt ]] || continue
    while IFS= read -r zeile || [[ -n "$zeile" ]]; do
      read -ra woerter <<< "${zeile%%#*}"
      for wort in "${woerter[@]}"; do
        if [[ ! "$wort" =~ ^[a-z0-9][a-z0-9+.-]+(:[a-z0-9]+)?$ ]]; then
          log_warnung "Ungültiger Paketname «$wort» in $name, übersprungen"
          continue
        fi
        gesehen[$wort]=1
      done
    done < "$datei"
  done
  (( ${#gesehen[@]} > 0 )) || return 0
  printf '%s\n' "${!gesehen[@]}" | LC_ALL=C sort
}

# 0, wenn apt für das Paket eine installierbare Version kennt
_pakete_kandidat() {
  local kandidat
  kandidat=$(apt-cache policy -- "$1" 2>/dev/null | awk '$1 == "Candidate:" { print $2; exit }')
  [[ -n "$kandidat" && "$kandidat" != "(none)" ]]
}
