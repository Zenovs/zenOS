#!/usr/bin/env bash
# 45-thema: Erscheinungsbild aus den Design-Tokens auf GTK, Qt, kitty, labwc und VS Code übertragen
# shellcheck shell=bash

modul_system() {
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  local -a pakete=()
  local zeile
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_QUELLE/scripts/pakete/thema.txt"
  pakete_sicherstellen "${pakete[@]}"
}

modul_benutzer() {
  _thema_app_icon

  local thema="$ZENOS_CODE/scripts/bin/zenos-thema" ausgabe zeile
  if [[ ! -x "$thema" ]]; then
    log_warnung "zenos-thema fehlt unter $ZENOS_CODE, Erscheinungsbild nicht übertragen"
    return 0
  fi
  # Erscheinungsbild und Akzent aus den Einstellungen und dem aktiven Modus;
  # zenos-thema meldet jede Änderung als eigene Zeile.
  if ! ausgabe=$("$thema" anwenden --melden); then
    log_warnung "zenos-thema konnte das Erscheinungsbild nicht vollständig übertragen"
  fi
  while IFS= read -r zeile; do
    [[ -n "$zeile" ]] && aenderung "Erscheinungsbild: $zeile"
  done <<< "$ausgabe"
  return 0
}

# App-Icon der Bildmarke (docs/bildmarke.md) als «zenos» ins hicolor-Thema des Benutzers, eine Datei je Grösse
# aus assets/zeichen/png/zenos-app-icon-<n>.png. Grössen, die im Repo fehlen, kommen weg. Den Icon-Cache
# erneuert es nur, wenn es dort schon einen gibt (sonst sucht GTK ohne Cache).
_thema_app_icon() {
  local quelle="$ZENOS_CODE/assets/zeichen/png" ordner="$ZENOS_HOME/.local/share/icons/hicolor"
  local datei n vorher
  local -A soll=()
  vorher=$(zenos_anzahl aenderung)

  for datei in "$quelle"/zenos-app-icon-*.png; do
    [[ -f "$datei" ]] || continue
    n=${datei##*/zenos-app-icon-}
    n=${n%.png}
    [[ "$n" =~ ^[1-9][0-9]*$ ]] || continue
    soll[$n]=1
    benutzer_datei_schreiben "$ordner/${n}x${n}/apps/zenos.png" < "$datei"
  done
  if (( ${#soll[@]} == 0 )); then
    log_warnung "Kein App-Icon unter $quelle gefunden"
    return 0
  fi

  for datei in "$ordner"/*x*/apps/zenos.png; do
    [[ -e "$datei" || -L "$datei" ]] || continue
    n=${datei#"$ordner"/}
    n=${n%%x*}
    [[ -n "${soll[$n]:-}" ]] || benutzer_datei_entfernen "$datei"
  done

  if (( $(zenos_anzahl aenderung) > vorher )) && [[ -f "$ordner/icon-theme.cache" ]] &&
    befehl_vorhanden gtk-update-icon-cache; then
    gtk-update-icon-cache --force --ignore-theme-index --quiet -- "$ordner" > /dev/null 2>&1 ||
      log_warnung "gtk-update-icon-cache ist fehlgeschlagen ($ordner)"
  fi
}
