#!/usr/bin/env bash
# 55-zustaende: Bildschirmfreigabe (xdg-desktop-portal-wlr) und Vorlagen für Zustände
# shellcheck shell=bash

modul_system() {
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  local -a pakete=()
  local zeile
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_QUELLE/scripts/pakete/zustaende.txt"
  pakete_sicherstellen "${pakete[@]}"

  # exec_before/exec_after melden jede Freigabe an zenos-freigabe (Pfade unter /opt/zenos)
  datei_installieren "$ZENOS_CODE/system/portal/xdpw.conf" /etc/xdg/xdg-desktop-portal-wlr/config

  # Endet das Portal ohne exec_after (Absturz), setzt zenos-freigabe die Freigabe zurück, beim Ende und
  # beim nächsten Start des Portals. Ein laufendes Portal übernimmt das nach daemon-reload ohne Neustart.
  datei_installieren "$ZENOS_CODE/system/systemd/user/xdg-desktop-portal-wlr.service.d/zenos.conf" \
    /etc/systemd/user/xdg-desktop-portal-wlr.service.d/zenos.conf
  systemd_neu_laden
}

modul_benutzer() {
  local konfig="$ZENOS_HOME/.config/zenos" zustand="$ZENOS_HOME/.local/state/zenos"
  local merker="$zustand/vorlagen-zustaende" vorlage id ziel
  local -a kopiert=()

  benutzer_ordner_sicherstellen "$konfig" 0700
  benutzer_ordner_sicherstellen "$konfig/zustaende"
  benutzer_ordner_sicherstellen "$zustand" 0700

  # Vorlagen (Fokus, Sitzung) genau einmal kopieren: Eine Datei, die du geändert oder bewusst
  # gelöscht hast, bleibt so, wie sie ist. Der Merker hält fest, welche Vorlagen schon da waren.
  if [[ -f "$merker" ]]; then mapfile -t kopiert < "$merker"; fi
  local neu=0
  for vorlage in "$ZENOS_CODE"/config/vorlagen/zustaende/*.json; do
    [[ -f "$vorlage" ]] || continue
    id=$(basename -- "$vorlage" .json)
    _zustaende_enthaelt "$id" "${kopiert[@]}" && continue
    ziel="$konfig/zustaende/$id.json"
    if [[ ! -e "$ziel" ]]; then
      benutzer_datei_schreiben "$ziel" 0600 < "$vorlage"
    fi
    kopiert+=("$id")
    neu=1
  done
  if (( neu )); then
    printf '%s\n' "${kopiert[@]}" | benutzer_datei_schreiben "$merker" 0600
  fi

  _zustaende_portal_neu_laden
}

_zustaende_enthaelt() {
  local suche=$1 eintrag
  shift
  for eintrag in "$@"; do [[ "$eintrag" == "$suche" ]] && return 0; done
  return 1
}

# Läuft das Portal schon (Sitzung aktiv) und ist die Konfiguration neuer, neu starten – aber nie
# während einer laufenden Freigabe (auch nicht im Nachlauf nach ihrem Ende: der Marker steht dann
# noch). Kein Zähler: Das ist keine Änderung am System.
_zustaende_portal_neu_laden() {
  local einheit=xdg-desktop-portal-wlr.service conf=/etc/xdg/xdg-desktop-portal-wlr/config
  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$EUID} seit_text seit geaendert
  [[ "$ZENOS_SYSTEMD" == 1 && -S "$laufzeit/bus" && -f "$conf" ]] || return 0
  XDG_RUNTIME_DIR=$laufzeit systemctl --user is-active --quiet "$einheit" 2>/dev/null || return 0
  [[ -s "$laufzeit/zenos/freigabe" ]] && return 0
  seit_text=$(XDG_RUNTIME_DIR=$laufzeit systemctl --user show -p ActiveEnterTimestamp --value "$einheit" 2>/dev/null) || return 0
  seit=$(date -d "$seit_text" +%s 2>/dev/null) || return 0
  geaendert=$(stat -c %Y -- "$conf" 2>/dev/null) || return 0
  if (( geaendert > seit )); then
    if XDG_RUNTIME_DIR=$laufzeit systemctl --user try-restart "$einheit" 2>/dev/null; then
      log_info "Portal für die Bildschirmfreigabe neu gestartet (neue Konfiguration)"
    fi
  fi
}
