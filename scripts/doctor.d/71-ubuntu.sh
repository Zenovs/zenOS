#!/usr/bin/env bash
# 71-ubuntu: Ubuntu-Basis – kein Wechsel der Hauptversion (Prompt=never für den Release-Upgrader)
# shellcheck shell=bash
#
# Ein Wechsel der Ubuntu-Basis ist eine neue zenOS-Hauptversion mit neuem Image, kein Update (scripts/module/71-basis.sh,
# docs/image-und-releases.md, «Basiswechsel»). Ob die Basis selbst Ubuntu 26.04 ist, prüft 00-basis. Ohne root, nur
# lesend.

# Ordner des Release-Upgraders (die Einheitentests setzen einen anderen)
_UBUNTU_ORDNER=/etc/update-manager

pruefe_ubuntu() {
  abschnitt "Ubuntu-Basis"
  _ubuntu_prompt
}

# Wert von Prompt im Abschnitt [DEFAULT] einer Datei des Release-Upgraders, klein geschrieben; leer, wenn er fehlt.
# Wie configparser: Schlüssel am Zeilenanfang, «=» oder «:», Gross- und Kleinschreibung egal.
_ubuntu_prompt_wert() { # DATEI
  awk '
    /^\[/ { abschnitt = $0; sub(/^\[[ \t]*/, "", abschnitt); sub(/[ \t]*\].*$/, "", abschnitt); next }
    abschnitt == "DEFAULT" && tolower($0) ~ /^prompt[ \t]*[=:]/ {
      sub(/^[^=:]*[=:][ \t]*/, ""); sub(/[ \t\r]+$/, ""); wert = tolower($0)
    }
    END { print wert }
  ' "$1" 2>/dev/null
}

# Wie ubuntu-release-upgrader (MetaRelease.py): zuerst release-upgrades, danach jede *.cfg in release-upgrades.d in
# Namensreihenfolge; der letzte Wert zählt. Ohne Wert gilt «normal».
_ubuntu_prompt() {
  local LC_ALL=C datei wert="" quelle="" w text
  local dropin="$_UBUNTU_ORDNER/release-upgrades.d/zenos.cfg"
  for datei in "$_UBUNTU_ORDNER/release-upgrades" "$_UBUNTU_ORDNER"/release-upgrades.d/*.cfg; do
    [[ -f "$datei" && -r "$datei" ]] || continue
    w=$(_ubuntu_prompt_wert "$datei")
    if [[ -n "$w" ]]; then
      wert=$w
      quelle=$datei
    fi
  done
  case "$wert" in
    never | no)
      ok "Kein Wechsel der Ubuntu-Hauptversion: Prompt=never ($quelle)"
      ;;
    *)
      text="Prompt ist «${wert:-normal}», nicht «never»: do-release-upgrade könnte auf eine neue Ubuntu-Version wechseln, das ist eine neue zenOS-Hauptversion mit neuem Image"
      if [[ ! -f "$dropin" ]]; then
        warnung "$text ($dropin fehlt, install.sh legt ihn an)"
      elif [[ ! "$(_ubuntu_prompt_wert "$dropin")" =~ ^(never|no)$ ]]; then
        warnung "$text ($dropin weicht ab, install.sh stellt ihn wieder her)"
      else
        warnung "$text ($quelle gilt nach $dropin)"
      fi
      ;;
  esac
}
