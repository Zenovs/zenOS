#!/usr/bin/env bash
# 15-kanal: signierter Kanal – Prüfprogramm, Units, Vertrauensanker und der letzte Stand (zen kanal status)
# shellcheck shell=bash
#
# Ausgegeben werden nur Zustände und Fingerabdrücke öffentlicher Prüfschlüssel, keine Adressen.

pruefe_kanal() {
  abschnitt "Signierter Kanal"
  local programm=/usr/local/libexec/zenos/zenos-kanal quelle=/opt/zenos/scripts/bin/zenos-kanal einheit
  if [[ ! -f "$programm" ]]; then
    hinweis "Noch nicht eingerichtet ($programm fehlt; install.sh richtet es ein)"
    return 0
  fi
  if ! _kanal_nur_root "$programm"; then
    fehler "$programm oder ein Ordner darüber ist nicht nur für root schreibbar – root führt es aus (install.sh)"
  elif [[ -r "$quelle" ]] && ! cmp -s "$programm" "$quelle"; then
    warnung "$programm weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  fi
  for einheit in zenos-kanal-holen.service zenos-kanal-pruefen.service; do
    [[ -f "/etc/systemd/system/$einheit" ]] || warnung "$einheit fehlt (install.sh)"
  done
  _kanal_anker
  _kanal_stand "$programm"
}

# Gehört PFAD und jeder Ordner darüber root, und ist nichts davon für andere schreibbar?
_kanal_nur_root() {
  local pfad=$1 rechte
  while [[ -n "$pfad" && "$pfad" != / ]]; do
    rechte=$(stat -c '%u %a' -- "$pfad" 2>/dev/null) || return 1
    [[ "${rechte%% *}" == 0 ]] || return 1
    (( (8#${rechte##* } & 8#022) == 0 )) || return 1
    pfad=$(dirname -- "$pfad")
  done
}

_kanal_anker() {
  local ordner=/etc/zenos/vertrauen ausgabe name
  if [[ ! -d "$ordner" ]]; then
    warnung "Vertrauensanker $ordner fehlt: Der Kanal installiert nichts (install.sh legt ihn an)"
    return 0
  fi
  for name in "$ordner" "$ordner/release" "$ordner/wurzel" "$ordner/widerrufen" "$ordner/serie"; do
    [[ -e "$name" ]] || continue
    if [[ -L "$name" ]] || ! _kanal_nur_root "$name"; then
      fehler "$name gehört nicht root, ist ein Verweis oder für andere schreibbar: Der Kanal gilt als «Anker fehlt»"
      return 0
    fi
  done
  ausgabe=$(/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal anker --pruefen "$ordner" 2>&1) || true
  case "$ausgabe" in
    vollständig*) ok "Vertrauensanker ${ausgabe#vollständig: }" ;;
    leer*) hinweis "Vertrauensanker noch ohne Schlüssel: Der signierte Kanal installiert nichts, zen update über dev geht weiter" ;;
    *) fehler "Vertrauensanker ${ausgabe:-nicht prüfbar} (sudo zen kanal anker ORDNER)" ;;
  esac
}

_kanal_stand() {
  local programm=$1 zeile zustand grund
  zeile=$(/usr/bin/python3 -I "$programm" status --kurz 2>/dev/null | head -n 1) || zeile=""
  zustand=${zeile%% *}
  grund=${zeile#* }
  case "$zustand" in
    ungeprueft | "") hinweis "Kanal noch nie geprüft (sudo zen kanal pruefen)" ;;
    veraltet) hinweis "Kanal: $grund" ;;
    aktuell | bereit | dev) ok "Kanal: $grund" ;;
    kein_kontakt) warnung "Kanal: $grund" ;;
    anker_fehlt) hinweis "Kanal: Anker fehlt, es gilt nichts als gültig (zen kanal status)" ;;
    blockiert | fehler) fehler "Kanal $zustand: $grund" ;;
    *) warnung "Kanal: unbekannter Zustand «$zustand»" ;;
  esac
}
