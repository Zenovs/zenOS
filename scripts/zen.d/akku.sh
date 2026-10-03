#!/usr/bin/env bash
# hilfe: akku [status|freigeben|sperren] – Akku des Argon ONE UP: Messwerte und Freigabe für das Akkuprofil
# Der Akku-Messchip (CW2217 an I2C 0x64) schläft ab Werk und hat kein Akkuprofil; dann misst er nichts.
# «freigeben» zeigt, was zenos-argon in den Chip schreibt, und legt die Freigabe erst nach der Eingabe
# «freigeben» an (/etc/xdg/zenos/argon-akkuprofil). Danach lädt zenos-argon Argons Akkuprofil im nächsten Takt.
# «sperren» nimmt die Freigabe zurück; zenos-argon liest den Chip dann nur noch.
# Einzelheiten: docs/module/m13.md
# shellcheck shell=bash

_AKKU_FREIGABE=/etc/xdg/zenos/argon-akkuprofil

befehl_akku() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen akku [status|freigeben|sperren])"
    return 2
  fi
  case "${1:-status}" in
    status) _akku_status ;;
    freigeben) _akku_freigeben ;;
    sperren) _akku_sperren ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, freigeben, sperren)"
      return 2
      ;;
  esac
}

_akku_freigegeben() { [[ -f "$_AKKU_FREIGABE" ]]; }

# Akku aus /run/zenos/geraet.json (von zenos-argon), eine Zeile
_akku_wert() {
  local datei=/run/zenos/geraet.json
  if [[ ! -r "$datei" ]]; then
    printf 'keine Werte (%s fehlt; läuft zenos-argon?)\n' "$datei"
    return 0
  fi
  jq -r '.akku | if .vorhanden != true then "kein Akku erkannt"
    elif .prozent != null then "\(.prozent) %" + (if .laedt == true then ", lädt oder Netzteil"
                                                   elif .laedt == false then ", Akkubetrieb" else "" end)
    elif .zustand == "freigabe" then "kein Messwert, der Messchip misst erst nach der Freigabe"
    elif .zustand == "fehler" then "nicht lesbar (journalctl -u zenos-argon)"
    else "noch kein Messwert" end' "$datei" 2> /dev/null || printf '%s ist ungültig\n' "$datei"
}

_akku_status() {
  printf 'Akku: %s\n' "$(_akku_wert)"
  if _akku_freigegeben; then
    printf 'Akkuprofil schreiben: freigegeben (%s)\n' "$_AKKU_FREIGABE"
  else
    printf 'Akkuprofil schreiben: nicht freigegeben (zen akku freigeben)\n'
  fi
  printf 'Messchip im Einzelnen, nur lesend: sudo /opt/zenos/scripts/bin/zenos-argon --pruefen\n'
}

_akku_freigeben() {
  if _akku_freigegeben; then
    printf 'Schon freigegeben (%s).\n' "$_AKKU_FREIGABE"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen akku freigeben braucht eine Bestätigung im Terminal (Eingabe «freigeben»)"
    return 2
  fi
  cat <<'TEXT'
Akkuprofil für den Argon ONE UP freigeben:

  zenos-argon weckt den Akku-Messchip (Cellwise CW2217, I2C-Bus 1, Adresse 0x64) und schreibt Argons Akkuprofil
  hinein, genau wie Argons eigene Software (argononeupd.py, Version 2608001). Erst dann misst der Chip.
  - Nur diese Register: 0x08 (wecken, schlafen legen, aktivieren), 0x0A (Interrupts aus), 0x0B (Profil geladen)
    und 0x10–0x5F (Argons Profil, 80 Byte, fest im Code).
  - Nur wenn nötig: Ist der Chip aktiv und hat er Argons Profil, schreibt zenos-argon nichts. Höchstens dreimal
    pro Stunde, nach Fehlern mit wachsender Pause.
  - Kein Absuchen des Busses, keine anderen Adressen. Nichts, solange Argons eigener Dienst aktiviert ist.
  Risiko: gering. Der Chip misst nur, er steuert weder Laden noch Strom noch das Abschalten. Ein falsches Profil
  ergäbe höchstens falsche Prozentwerte.
  Zurück: zen akku sperren (der Chip behält das Profil, bis er ohne Strom ist).

TEXT
  local antwort=""
  read -r -p 'Zum Freigeben «freigeben» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != freigeben ]]; then
    printf 'Abgebrochen. Nichts geändert.\n'
    return 1
  fi
  $SUDO install -d -m 0755 -o root -g root "${_AKKU_FREIGABE%/*}"
  printf '# zenOS: zenos-argon darf Argons Akkuprofil in den Akku-Messchip schreiben (zen akku freigeben)\n' |
    $SUDO install -m 0644 -o root -g root /dev/stdin "$_AKKU_FREIGABE"
  printf 'Freigegeben. zenos-argon lädt das Profil im nächsten Takt (höchstens 15 s), Prüfen: zen akku status\n'
}

_akku_sperren() {
  if ! _akku_freigegeben; then
    printf 'Nicht freigegeben. Nichts zu tun.\n'
    return 0
  fi
  $SUDO rm -f -- "$_AKKU_FREIGABE"
  printf 'Freigabe entfernt. zenos-argon liest den Messchip ab jetzt nur noch.\n'
}
