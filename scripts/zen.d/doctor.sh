#!/usr/bin/env bash
# hilfe: doctor [--kurz] – Prüfbericht ohne Geheimnisse (Exit 1 bei Fehlern)
# Führt die Prüfungen aus scripts/doctor.d/*.sh in Namensreihenfolge aus. --kurz zeigt nur die
# Zusammenfassung. Der Bericht enthält keine Geheimnisse, keine Adressen und keine Inhalte aus
# ~/.config/zenos; das Home erscheint als «~».
# shellcheck shell=bash
#
# Vertrag für scripts/doctor.d/NN-name.sh: eine Funktion pruefe_<name> (Bindestriche → Unterstriche),
# die mit abschnitt, ok, hinweis, warnung und fehler berichtet. Jede Datei läuft in einer eigenen
# Subshell ohne «set -e» und ohne «set -u»; ein Absturz dort erscheint als Fehler im Bericht und
# stoppt die übrigen Prüfungen nicht. Nichts ausgeben, was Geheimnisse, Tokens, IP-/MAC-Adressen,
# Hostnamen, SSIDs, Benutzernamen oder Inhalte persönlicher Dateien enthält.

_DOCTOR_ZAEHLER=""

_doctor_text() {
  local text="$*"
  if [[ -n "${HOME:-}" && "$HOME" != / ]]; then text=${text//"$HOME"/"~"}; fi
  printf '%s' "$text"
}

_doctor_zeile() { # ART SYMBOL TEXT
  printf '%s\n' "$1" >> "$_DOCTOR_ZAEHLER"
  printf '  %s %s\n' "$2" "$(_doctor_text "${*:3}")"
}

abschnitt() { printf '\n%s\n' "$(_doctor_text "$*")"; }
ok() { _doctor_zeile ok '✓' "$*"; }
hinweis() { _doctor_zeile hinweis '·' "$*"; }
warnung() { _doctor_zeile warnung '!' "$*"; }
fehler() { _doctor_zeile fehler '✗' "$*"; }

_doctor_anzahl() { # ZAHL EINZAHL MEHRZAHL
  if (( $1 == 1 )); then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi
}

_doctor_pruefungen() {
  local datei name funktion rc
  printf 'zenOS doctor · %s\n' "$(date '+%Y-%m-%d %H:%M')"
  while IFS= read -r -d '' datei; do
    name=$(basename -- "$datei" .sh)
    funktion="pruefe_${name#[0-9][0-9]-}"
    funktion=${funktion//-/_}
    rc=0
    (
      set +eu
      # shellcheck source=/dev/null
      source "$datei"
      if declare -F "$funktion" >/dev/null; then
        "$funktion"
      else
        fehler "doctor.d/$name.sh: Funktion $funktion fehlt"
      fi
    ) < /dev/null || rc=$?
    if (( rc != 0 )); then fehler "doctor.d/$name.sh ist abgebrochen (Exit $rc)"; fi
  done < <(find "$ZEN_SKRIPTE/doctor.d" -maxdepth 1 -type f -name '*.sh' -print0 | LC_ALL=C sort -z)
}

befehl_doctor() {
  local kurz=0 arg tmp n_fehler n_warnungen n_hinweise
  for arg in "$@"; do
    case "$arg" in
      --kurz) kurz=1 ;;
      *) zen_fehler "unbekannte Option «$arg» (erlaubt: --kurz)"; return 2 ;;
    esac
  done

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/zen-doctor.XXXXXX")
  _DOCTOR_ZAEHLER="$tmp/zaehler"
  : > "$_DOCTOR_ZAEHLER"
  if (( kurz )); then
    _doctor_pruefungen > /dev/null
  else
    _doctor_pruefungen
    printf '\n'
  fi

  n_fehler=$(grep -cx fehler "$_DOCTOR_ZAEHLER" || true)
  n_warnungen=$(grep -cx warnung "$_DOCTOR_ZAEHLER" || true)
  n_hinweise=$(grep -cx hinweis "$_DOCTOR_ZAEHLER" || true)
  rm -rf -- "$tmp"
  printf '%s · %s · %s\n' "$(_doctor_anzahl "$n_fehler" Fehler Fehler)" \
    "$(_doctor_anzahl "$n_warnungen" Warnung Warnungen)" "$(_doctor_anzahl "$n_hinweise" Hinweis Hinweise)"
  (( n_fehler == 0 )) || return 1
}
