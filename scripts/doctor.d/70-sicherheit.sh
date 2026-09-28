#!/usr/bin/env bash
# 70-sicherheit: automatische Updates, Chrome- und VS Code-Richtlinie, Ubuntu-Nachrichten, gitleaks und Hook, Firewall
# shellcheck shell=bash
#
# Die sudo-Regel aus dem Bau prüft schon 00-basis. Die Firewall-Regeln sind nur für root lesbar; ohne
# sudo ohne Passwort bleibt es bei einem Hinweis. Ausgegeben werden nur Anzahlen, keine Adressen.

pruefe_sicherheit() {
  abschnitt "Sicherheit"
  _sicherheit_updates
  _sicherheit_chrome
  _sicherheit_vscode
  _sicherheit_nachrichten
  _sicherheit_gitleaks
  _sicherheit_firewall
}

_sicherheit_apt_wert() {
  apt-config shell WERT "$1" 2>/dev/null | sed -n "s/^WERT='\(.*\)'\$/\1/p"
}

_sicherheit_updates() {
  local datei wert zeit ergebnis anzahl
  if ! paket_installiert unattended-upgrades; then
    fehler "unattended-upgrades fehlt – keine automatischen Sicherheitsupdates (install.sh ausführen)"
    return 0
  fi
  if [[ "$(_sicherheit_apt_wert APT::Periodic::Update-Package-Lists)" == 1 &&
    "$(_sicherheit_apt_wert APT::Periodic::Unattended-Upgrade)" == 1 ]]; then
    ok "Automatische Sicherheitsupdates eingeschaltet (unattended-upgrades)"
  else
    fehler "Automatische Sicherheitsupdates sind aus (APT::Periodic, install.sh stellt es wieder her)"
  fi
  if [[ "$(_sicherheit_apt_wert APT::Periodic::Enable)" == 0 ]]; then
    datei=$(grep -l 'APT::Periodic::Enable' /etc/apt/apt.conf.d/* 2>/dev/null | head -n 1)
    warnung "APT::Periodic::Enable ist 0${datei:+ ($datei)} – die automatischen Updates laufen nicht"
  fi

  datei=/etc/apt/apt.conf.d/52zenos-unattended
  if [[ ! -f "$datei" ]]; then
    warnung "$datei fehlt – Updates für Chrome und VS Code nur von Hand (install.sh)"
  elif [[ -r /opt/zenos/system/apt/52zenos-unattended ]] && ! cmp -s "$datei" /opt/zenos/system/apt/52zenos-unattended; then
    warnung "$datei weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  else
    ok "Updates auch aus den Paketquellen von Chrome, VS Code und 1Password-CLI"
  fi
  wert=$(_sicherheit_apt_wert Unattended-Upgrade::Automatic-Reboot)
  if [[ "$wert" == true ]]; then
    hinweis "Automatische Neustarts nach Updates sind eingeschaltet"
  else
    ok "Keine automatischen Neustarts"
  fi

  if [[ "$(systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null)" != enabled ]]; then
    fehler "apt-daily-upgrade.timer ist nicht aktiviert – unattended-upgrades läuft nie (install.sh)"
  else
    zeit=$(systemctl show -p LastTriggerUSec --value --timestamp=unix apt-daily-upgrade.timer 2>/dev/null)
    ergebnis=$(systemctl show -p Result --value apt-daily-upgrade.service 2>/dev/null)
    if [[ ! "$zeit" =~ ^@[1-9][0-9]*$ ]]; then
      hinweis "unattended-upgrades ist noch nie gelaufen (läuft täglich über apt-daily-upgrade.timer)"
    elif [[ "$ergebnis" != success ]]; then
      warnung "Letzter Lauf von unattended-upgrades ist gescheitert (${ergebnis:-unbekannt}; journalctl -u apt-daily-upgrade)"
    else
      ok "Letzter Lauf von unattended-upgrades: $(date -d "$zeit" '+%d.%m.%Y %H:%M' 2>/dev/null || printf '%s' "$zeit")"
    fi
  fi

  if [[ -e /run/reboot-required ]]; then
    anzahl=""
    if [[ -r /run/reboot-required.pkgs ]]; then anzahl=$(sort -u /run/reboot-required.pkgs | grep -c .); fi
    hinweis "Nach Updates steht ein Neustart an${anzahl:+ (Pakete: $anzahl)} – automatische Neustarts sind aus"
  fi
}

_sicherheit_chrome() {
  local datei=/etc/opt/chrome/policies/managed/zenos.json quelle=/opt/zenos/system/chrome/policies/zenos.json
  local ordner rechte anzahl
  for ordner in /etc/opt/chrome/policies /etc/opt/chrome/policies/managed; do
    [[ -d "$ordner" ]] || continue
    rechte=$(stat -c '%U %a' -- "$ordner" 2>/dev/null)
    if [[ "${rechte%% *}" != root ]] || (( (8#${rechte##* } & 8#022) != 0 )); then
      fehler "$ordner ist nicht nur für root schreibbar ($rechte) – Richtlinien liessen sich aushebeln (install.sh)"
    fi
  done
  if [[ ! -f "$datei" ]]; then
    fehler "Chrome-Richtlinie fehlt: $datei (install.sh ausführen)"
    return 0
  fi
  if ! anzahl=$(python3 - "$datei" 2>/dev/null <<'PY'
import json
import sys

ID = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
with open(sys.argv[1], encoding="utf-8") as f:
    daten = json.load(f)
if not isinstance(daten, dict):
    sys.exit(1)
if daten.get("ExtensionInstallBlocklist") != ["*"] or ID not in daten.get("ExtensionInstallAllowlist", []):
    sys.exit(1)
if not any(e.split(";", 1)[0] == ID for e in daten.get("ExtensionInstallForcelist", [])):
    sys.exit(1)
print(len(daten))
PY
  ); then
    fehler "Chrome-Richtlinie $datei ist ungültig oder unvollständig – Chrome ignoriert sie (install.sh)"
    return 0
  fi
  if [[ -r "$quelle" ]] && ! cmp -s "$datei" "$quelle"; then
    warnung "Chrome-Richtlinie weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  else
    ok "Chrome-Richtlinie vorhanden und gültig ($anzahl Richtlinien, 1Password als einzige Erweiterung)"
  fi
  if [[ -x /opt/google/chrome/chrome ]] || command -v google-chrome-stable >/dev/null 2>&1; then
    ok "Chrome installiert – chrome://policy zeigt die Richtlinien"
  else
    hinweis "Chrome ist noch nicht installiert; die Richtlinie greift, sobald es da ist"
  fi
}

# Richtlinie für VS Code: Telemetrie aus. VS Code liest /etc/vscode/policy.json ab 1.106.
_sicherheit_vscode() {
  local datei=/etc/vscode/policy.json quelle=/opt/zenos/system/vscode/policy.json
  local version rechte pfad schwere=warnung
  version=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' code 2>/dev/null)
  if [[ "$version" == ii* ]]; then version=${version##* }; else version=""; fi
  # Ohne VS Code schadet eine fehlende Richtlinie noch nicht, mit VS Code geht Telemetrie hinaus.
  [[ -z "$version" ]] || schwere=fehler

  for pfad in /etc/vscode "$datei"; do
    [[ -e "$pfad" ]] || continue
    rechte=$(stat -c '%U %a' -- "$pfad" 2>/dev/null)
    if [[ "${rechte%% *}" != root ]] || (( (8#${rechte##* } & 8#022) != 0 )); then
      fehler "$pfad ist nicht nur für root schreibbar ($rechte) – die Richtlinie liesse sich aushebeln (install.sh)"
    fi
  done
  if [[ ! -f "$datei" ]]; then
    "$schwere" "VS Code-Richtlinie fehlt: $datei – VS Code sendet ab Werk Telemetrie (install.sh ausführen)"
    return 0
  fi
  if ! python3 - "$datei" 2>/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    daten = json.load(f)
sys.exit(not (isinstance(daten, dict) and daten.get("TelemetryLevel") == "off"))
PY
  then
    "$schwere" "VS Code-Richtlinie $datei ist ungültig oder schaltet die Telemetrie nicht ab (install.sh)"
    return 0
  fi
  if [[ -r "$quelle" ]] && ! cmp -s "$datei" "$quelle"; then
    warnung "VS Code-Richtlinie weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  elif [[ -z "$version" ]]; then
    ok "VS Code-Richtlinie vorhanden (Telemetrie aus); greift, sobald VS Code installiert ist"
  elif dpkg --compare-versions "$version" lt 1.106; then
    warnung "VS Code ${version%%-*} liest $datei noch nicht (erst ab 1.106) – Telemetrie nicht abgeschaltet (sudo apt upgrade)"
  else
    ok "VS Code ${version%%-*}: Telemetrie per Richtlinie aus"
  fi
}

# Ubuntu-Nachrichten, die ohne Aktion des Benutzers motd.ubuntu.com abrufen
_sicherheit_nachrichten() {
  local datei=/etc/default/motd-news wert
  if [[ -f "$datei" ]]; then
    wert=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}ENABLED=//p' "$datei" 2>/dev/null |
      tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '"'"'"'[:space:]')
    if [[ "$wert" == 1 ]]; then
      warnung "motd-news ist eingeschaltet und ruft zweimal täglich motd.ubuntu.com auf (install.sh schaltet es ab)"
    else
      ok "motd-news aus"
    fi
  fi
  if command -v pro >/dev/null 2>&1; then
    wert=$(pro config show apt_news 2>/dev/null | awk '$1 == "apt_news" { print $2 }')
    case "$wert" in
      False) ok "apt-news aus (ubuntu-pro-client)" ;;
      True) warnung "apt-news ist eingeschaltet und ruft bei apt update motd.ubuntu.com auf (install.sh schaltet es ab)" ;;
      *) hinweis "apt-news: Einstellung nicht lesbar (pro config show apt_news)" ;;
    esac
  fi
}

_sicherheit_gitleaks() {
  local version repo=$HOME/zenOS ist
  if command -v gitleaks >/dev/null 2>&1; then
    version=$(dpkg-query -W -f='${Version}' gitleaks 2>/dev/null)
    version=${version%%-*}
    ok "gitleaks installiert${version:+ ($version)}"
  else
    fehler "gitleaks fehlt – der Pre-Commit-Hook lässt keinen Commit zu (sudo apt install gitleaks)"
  fi

  if [[ ! -d "$repo" ]] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    hinweis "Kein Quell-Repo unter $repo, gitleaks-Hook nicht geprüft"
    return 0
  fi
  ist=$(git -C "$repo" config --local --get core.hooksPath 2>/dev/null)
  if [[ -n "$ist" && "$ist" != /* ]]; then ist="$repo/$ist"; fi
  if [[ -z "$ist" ]] || [[ "$(readlink -m -- "$ist")" != "$(readlink -m -- "$repo/.githooks")" ]]; then
    warnung "gitleaks-Hook in $repo nicht aktiv (install.sh aus $repo ausführen oder git -C $repo config core.hooksPath .githooks)"
  elif [[ ! -x "$repo/.githooks/pre-commit" ]]; then
    warnung "$repo/.githooks/pre-commit fehlt oder ist nicht ausführbar"
  else
    ok "gitleaks-Hook aktiv in $repo"
  fi
}

_sicherheit_firewall() {
  local eingehend ausgehend tupel ausgabe
  local -a fehlend=() netze=()
  # Gemeinsame Hilfsfunktionen und die Liste der lokalen Netze
  # shellcheck source=../zen.d/firewall.sh
  source "$ZEN_SKRIPTE/zen.d/firewall.sh" || { fehler "zen.d/firewall.sh nicht ladbar"; return 0; }

  if ! _firewall_installiert; then
    fehler "ufw fehlt – keine Firewall (install.sh ausführen)"
    return 0
  fi
  if _firewall_aktiv; then
    ok "Firewall aktiv"
  else
    hinweis "Firewall vorbereitet, aber nicht aktiv (einschalten: zen firewall aktivieren)"
  fi
  eingehend=$(_firewall_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  ausgehend=$(_firewall_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  if [[ "$eingehend" == DROP && "$ausgehend" == ACCEPT ]]; then
    ok "Firewall-Standard: eingehend verweigern, ausgehend erlauben"
  else
    warnung "Firewall-Standard: eingehend $(_firewall_politik "$eingehend"), ausgehend $(_firewall_politik "$ausgehend") (erwartet: verweigern, erlauben)"
  fi

  if ! tupel=$(_firewall_tupel --still); then
    hinweis "SSH-Regeln der Firewall nur mit Root-Rechten prüfbar (sudo zen firewall status)"
    return 0
  fi
  mapfile -t netze < <(_firewall_netze)
  if ! ausgabe=$(_firewall_auswerten fehlend "${netze[@]}" <<< "$tupel"); then
    warnung "SSH-Regeln der Firewall liessen sich nicht auswerten (python3)"
    return 0
  fi
  mapfile -t fehlend < <(printf '%s' "$ausgabe" | sed '/^$/d')
  if (( ${#fehlend[@]} == 0 )); then
    ok "SSH (22/tcp) aus den lokalen Netzen erlaubt (${#netze[@]} Regeln)"
  elif _firewall_aktiv; then
    fehler "Firewall aktiv, aber ${#fehlend[@]} von ${#netze[@]} SSH-Regeln fehlen – SSH aus dem lokalen Netz kann gesperrt sein"
  else
    warnung "${#fehlend[@]} von ${#netze[@]} SSH-Regeln fehlen (install.sh bereitet sie vor)"
  fi
  if [[ "$(_firewall_wert IPV6 /etc/default/ufw)" != yes ]]; then
    warnung "IPv6 ist in ufw ausgeschaltet (IPV6 in /etc/default/ufw) – IPv6-Verkehr bliebe ungefiltert"
  fi
}
