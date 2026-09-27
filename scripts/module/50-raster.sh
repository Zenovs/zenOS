#!/usr/bin/env bash
# 50-raster: Raster (labwc-Regionen, Tastenkürzel) und Bildschirm-Profile (kanshi)
# shellcheck shell=bash
#
# System: Pakete nachziehen, zenos-kanshi.service nach /etc/systemd/user (wie 40-sitzung; gestartet von
# zenos-sitzung.target). Benutzer: Raster-Vorlagen und bildschirme.json nach ~/.config/zenos (nur, was
# fehlt), menu.xml verknüpfen, dann ~/.config/labwc/rc.xml (zenos-labwc) und ~/.config/kanshi/config
# (zenos-kanshi) erzeugen. Beide schreiben nur bei Änderungen und laden labwc bzw. kanshi dann neu.

modul_system() {
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  local -a pakete=()
  local zeile
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_QUELLE/scripts/pakete/raster.txt"
  pakete_sicherstellen "${pakete[@]}"

  datei_installieren "$ZENOS_CODE/system/systemd/user/zenos-kanshi.service" \
    /etc/systemd/user/zenos-kanshi.service 0644 root:root
}

modul_benutzer() {
  local konfig="$ZENOS_HOME/.config/zenos" zustand="$ZENOS_HOME/.local/state/zenos"
  local merker="$zustand/vorlagen-raster" vorlage id ziel ausgabe zeile neu=0 rc
  local -a kopiert=()

  benutzer_ordner_sicherstellen "$konfig" 0700
  benutzer_ordner_sicherstellen "$konfig/raster"
  benutzer_ordner_sicherstellen "$zustand" 0700

  # Vorlagen genau einmal kopieren: Ein Raster, das du geändert oder bewusst gelöscht hast, bleibt so.
  # Der Merker hält fest, welche Vorlagen schon da waren; neue Vorlagen späterer Versionen kommen dazu.
  if [[ -f "$merker" ]]; then mapfile -t kopiert < "$merker"; fi
  for vorlage in "$ZENOS_CODE"/config/vorlagen/raster/*.json; do
    [[ -f "$vorlage" ]] || continue
    id=$(basename -- "$vorlage" .json)
    _raster_enthaelt "$id" "${kopiert[@]}" && continue
    ziel="$konfig/raster/$id.json"
    if [[ ! -e "$ziel" ]]; then
      benutzer_datei_schreiben "$ziel" 0600 < "$vorlage"
    fi
    kopiert+=("$id")
    neu=1
  done
  if (( neu )); then
    printf '%s\n' "${kopiert[@]}" | benutzer_datei_schreiben "$merker" 0600
  fi

  if [[ ! -e "$konfig/bildschirme.json" ]]; then
    benutzer_datei_schreiben "$konfig/bildschirme.json" 0600 < "$ZENOS_CODE/config/vorlagen/bildschirme.json"
  fi

  benutzer_ordner_sicherstellen "$ZENOS_HOME/.config/labwc"
  verknuepfen "$ZENOS_CODE/system/labwc/menu.xml" "$ZENOS_HOME/.config/labwc/menu.xml"

  # labwc-Konfiguration aus dem aktiven Raster; jede Änderung meldet zenos-labwc als eigene Zeile
  rc=0
  ausgabe=$("$ZENOS_CODE/scripts/bin/zenos-labwc" --melden) || rc=$?
  (( rc == 0 )) || log_warnung "zenos-labwc konnte ~/.config/labwc/rc.xml nicht erzeugen (Exit $rc)"
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] && aenderung "Raster: $zeile"
  done <<< "$ausgabe"

  # kanshi-Konfiguration aus den Bildschirm-Profilen (Exit 1: bildschirme.json ungültig, Vorlage gilt)
  rc=0
  ausgabe=$("$ZENOS_CODE/scripts/bin/zenos-kanshi" --melden) || rc=$?
  case "$rc" in
    0) ;;
    1) log_warnung "bildschirme.json ist ungültig, kanshi nutzt die Vorlage (Details: zenos-kanshi --pruefen)" ;;
    *) log_warnung "zenos-kanshi konnte ~/.config/kanshi/config nicht erzeugen (Exit $rc)" ;;
  esac
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] && aenderung "Bildschirme: $zeile"
  done <<< "$ausgabe"
  return 0
}

_raster_enthaelt() {
  local suche=$1 eintrag
  shift
  for eintrag in "$@"; do [[ "$eintrag" == "$suche" ]] && return 0; done
  return 1
}
