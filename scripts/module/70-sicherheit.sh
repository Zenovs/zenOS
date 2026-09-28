#!/usr/bin/env bash
# 70-sicherheit: Sicherheitsupdates, Chrome- und VS Code-Richtlinien, Ubuntu-Nachrichten aus, Firewall, gitleaks-Hook
# shellcheck shell=bash
#
# - unattended-upgrades: system/apt/20auto-upgrades (inhaltsgleich mit der Vorlage des Pakets, damit ucf bei
#   Paket-Updates nie nachfragt) und system/apt/52zenos-unattended (Herstellerquellen, keine automatischen
#   Neustarts, keine Mail).
# - Richtlinien für Chrome (/etc/opt/chrome/policies/managed/) und VS Code (/etc/vscode/policy.json, Telemetrie
#   aus), auch ohne die Apps: Sie greifen, sobald sie installiert sind. Läuft auch im Image-Modus (die
#   Richtlinien sind nur Konfiguration, keine proprietäre Software).
# - Ubuntu-Nachrichten: motd-news (ENABLED=0 in /etc/default/motd-news) und apt-news von ubuntu-pro-client
#   (pro config set apt_news=false) abschalten, je nur, wenn vorhanden. Beide holen ohne Aktion des Benutzers
#   Inhalte von motd.ubuntu.com, motd-news schickt dabei Version, Kernel, Architektur und cloud_id mit.
# - ufw: Regeln werden nur vorbereitet, solange die Firewall aus ist. Eingeschaltet wird sie hier nie,
#   nur mit «zen firewall aktivieren». Ist sie schon an, bleibt alles, wie es ist.
# - gitleaks-Hook: core.hooksPath=.githooks im Quell-Repo (z. B. ~/zenOS), wenn es dem Benutzer gehört.
#   /opt/zenos bekommt keinen Hook (dort wird nicht committet).
# Die Pakete aus scripts/pakete/sicherheit.txt installiert 20-pakete; hier wird nur nachgezogen.

modul_system() {
  _sicherheit_pakete
  _sicherheit_updates
  _sicherheit_chrome
  _sicherheit_vscode
  _sicherheit_nachrichten
  _sicherheit_firewall
}

modul_benutzer() {
  _sicherheit_hook
}

_sicherheit_pakete() {
  local zeile
  local -a pakete=()
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_CODE/scripts/pakete/sicherheit.txt"
  pakete_sicherstellen "${pakete[@]}"
}

# Wert eines apt-Konfigurationsschlüssels (leer, wenn nicht gesetzt)
_sicherheit_apt_wert() {
  apt-config shell WERT "$1" 2>/dev/null | sed -n "s/^WERT='\(.*\)'\$/\1/p"
}

_sicherheit_updates() {
  datei_installieren "$ZENOS_CODE/system/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
  datei_installieren "$ZENOS_CODE/system/apt/52zenos-unattended" /etc/apt/apt.conf.d/52zenos-unattended
  # Die Timer bringt apt mit; sie lösen das tägliche Update und unattended-upgrade aus.
  dienst_aktivieren apt-daily.timer
  dienst_aktivieren apt-daily-upgrade.timer

  if [[ "$(_sicherheit_apt_wert APT::Periodic::Enable)" == 0 ]]; then
    log_info "Hinweis: APT::Periodic::Enable ist 0 (eine andere Datei in /etc/apt/apt.conf.d/ schaltet die automatischen Updates ab)"
  fi
}

# Gültiges JSON mit einem Objekt als Wurzel (so erwarten es Chrome und VS Code)
_sicherheit_json_objekt() { # DATEI
  python3 -c 'import json, sys; sys.exit(not isinstance(json.load(open(sys.argv[1], encoding="utf-8")), dict))' \
    "$1" 2>/dev/null
}

_sicherheit_chrome() {
  local quelle="$ZENOS_CODE/system/chrome/policies/zenos.json"
  # Chrome verwirft eine ungültige Datei ganz – dann lieber die alte behalten und warnen.
  if ! _sicherheit_json_objekt "$quelle"; then
    log_warnung "$quelle ist kein gültiges JSON-Objekt, Chrome-Richtlinien nicht aktualisiert"
    return 0
  fi
  # Nur root darf die Richtlinien ändern
  ordner_sicherstellen /etc/opt/chrome/policies 0755 root:root
  ordner_sicherstellen /etc/opt/chrome/policies/managed 0755 root:root
  datei_installieren "$quelle" /etc/opt/chrome/policies/managed/zenos.json 0644 root:root
}

# VS Code liest ab 1.106 unter Linux /etc/vscode/policy.json (streng als JSON; ist die Datei ungültig, gilt
# keine Richtlinie). TelemetryLevel «off» sperrt telemetry.telemetryLevel, der Benutzer kann es nicht ändern.
_sicherheit_vscode() {
  local quelle="$ZENOS_CODE/system/vscode/policy.json"
  if ! _sicherheit_json_objekt "$quelle"; then
    log_warnung "$quelle ist kein gültiges JSON-Objekt, VS Code-Richtlinie nicht aktualisiert"
    return 0
  fi
  ordner_sicherstellen /etc/vscode 0755 root:root
  datei_installieren "$quelle" /etc/vscode/policy.json 0644 root:root
}

# Wert von ENABLED in /etc/default/motd-news, wie ihn 50-motd-news liest (letzte Zuweisung gilt)
_sicherheit_motd_wert() { # DATEI
  sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}ENABLED=//p' "$1" 2>/dev/null |
    tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '"'"'"'[:space:]'
}

# Ubuntu-Nachrichten abschalten, jeweils auf dem Weg, den Ubuntu dafür vorsieht (rückgängig machen: siehe
# docs/sicherheit.md, «Unterbau»).
_sicherheit_nachrichten() {
  local datei=/etc/default/motd-news wert ausgabe

  # motd-news: Der Timer ruft zweimal täglich 50-motd-news --force auf; mit ENABLED≠1 endet das Skript sofort.
  # Die Datei gehört dem Paket motd-news-config (Conffile). Fehlt sie, ist motd-news schon aus – dann nichts
  # anlegen, sonst fragte dpkg bei einer späteren Installation des Pakets nach.
  if [[ -f "$datei" ]]; then
    wert=$(_sicherheit_motd_wert "$datei")
    if [[ "$wert" != 0 ]]; then
      if grep -Eq '^[[:space:]]*(export[[:space:]]+)?ENABLED=' "$datei"; then
        sed -E 's/^[[:space:]]*(export[[:space:]]+)?ENABLED=.*/ENABLED=0/' "$datei" |
          datei_schreiben "$datei" 0644 root:root
      else
        { cat -- "$datei"; printf 'ENABLED=0\n'; } | datei_schreiben "$datei" 0644 root:root
      fi
      if [[ "$(_sicherheit_motd_wert "$datei")" == 0 ]]; then
        log_info "motd-news abgeschaltet (vorher ENABLED=${wert:-leer})"
      else
        log_warnung "motd-news liess sich nicht abschalten ($datei)"
      fi
    fi
  fi

  # apt-news: ubuntu-pro-client holt bei apt update höchstens einmal täglich motd.ubuntu.com/aptnews.json.
  if befehl_vorhanden pro; then
    wert=$($SUDO pro config show apt_news 2>/dev/null | awk '$1 == "apt_news" { print $2 }')
    if [[ "$wert" != False ]]; then
      if ausgabe=$($SUDO pro config set apt_news=false 2>&1); then
        aenderung "apt-news abgeschaltet (pro config set apt_news=false, vorher ${wert:-unbekannt})"
      else
        log_warnung "apt-news liess sich nicht abschalten (${ausgabe##*$'\n'})"
      fi
    fi
  fi
}

# Wert aus einer ufw-Konfigurationsdatei (ohne Anführungszeichen)
_sicherheit_ufw_wert() { # SCHLUESSEL DATEI
  sed -n "s/^$1=//p" "$2" 2>/dev/null | tail -n 1 | tr -d '"'"'"
}

# Druckt die Netze, für die die Regel «allow tcp 22 aus NETZ» noch fehlt (Tupel in user.rules/user6.rules)
_sicherheit_ssh_fehlend() { # NETZ…
  local regeln netz
  regeln=$({
    $SUDO cat -- /etc/ufw/user.rules 2>/dev/null || true
    $SUDO cat -- /etc/ufw/user6.rules 2>/dev/null || true
  } | grep '^### tuple ###') || regeln=""
  for netz in "$@"; do
    awk -v netz="$netz" '
      $4 == "allow" && $5 == "tcp" && $6 == "22" && ($7 == "0.0.0.0/0" || $7 == "::/0") &&
        $8 == "any" && $9 == netz && $10 == "in" { gefunden = 1 }
      END { exit !gefunden }
    ' <<< "$regeln" || printf '%s\n' "$netz"
  done
}

_sicherheit_firewall() {
  # Lokale Netze, aus denen SSH erlaubt ist (dieselbe Liste steht in scripts/zen.d/firewall.sh)
  local -a netze=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fe80::/10 fd00::/8)
  local -a fehlend=() danach=()
  local netz wert ausgabe=""

  if ! paket_installiert ufw; then
    log_warnung "ufw ist nicht installiert, Firewall nicht vorbereitet"
    return 0
  fi

  # Eine laufende Firewall gehört dem Benutzer: nichts ändern, nur nachsehen.
  if [[ "$(_sicherheit_ufw_wert ENABLED /etc/ufw/ufw.conf)" == yes ]]; then
    mapfile -t fehlend < <(_sicherheit_ssh_fehlend "${netze[@]}")
    if (( ${#fehlend[@]} > 0 )); then
      log_warnung "Firewall ist aktiv, aber SSH ist nicht aus allen lokalen Netzen erlaubt (fehlt: ${fehlend[*]}). Regeln bleiben unverändert."
    else
      log_info "Firewall ist aktiv, Regeln bleiben unverändert"
    fi
    return 0
  fi

  # Standard: eingehend verweigern, ausgehend erlauben (ändert bei inaktiver ufw nur /etc/default/ufw)
  wert=$(_sicherheit_ufw_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  if [[ "$wert" != DROP ]]; then
    ausgabe=$($SUDO ufw default deny incoming 2>&1) || true
    if [[ "$(_sicherheit_ufw_wert DEFAULT_INPUT_POLICY /etc/default/ufw)" == DROP ]]; then
      aenderung "Firewall: eingehend verweigern (vorher ${wert:-unbekannt})"
    else
      log_warnung "ufw: Standard für eingehend liess sich nicht setzen (${ausgabe##*$'\n'})"
    fi
  fi
  wert=$(_sicherheit_ufw_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  if [[ "$wert" != ACCEPT ]]; then
    ausgabe=$($SUDO ufw default allow outgoing 2>&1) || true
    if [[ "$(_sicherheit_ufw_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)" == ACCEPT ]]; then
      aenderung "Firewall: ausgehend erlauben (vorher ${wert:-unbekannt})"
    else
      log_warnung "ufw: Standard für ausgehend liess sich nicht setzen (${ausgabe##*$'\n'})"
    fi
  fi

  if [[ "$(_sicherheit_ufw_wert IPV6 /etc/default/ufw)" != yes ]]; then
    log_warnung "IPv6 ist in ufw ausgeschaltet (IPV6 in /etc/default/ufw), SSH-Regeln nur für IPv4"
    netze=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
  fi

  mapfile -t fehlend < <(_sicherheit_ssh_fehlend "${netze[@]}")
  (( ${#fehlend[@]} > 0 )) || return 0
  # Die Ausgabe von ufw bleibt still: Ohne Netzfilter-Rechte (chroot, Container) meldet es Warnungen, legt die
  # Regeln aber trotzdem an. Gezählt wird, was danach wirklich in den Regeln steht.
  for netz in "${fehlend[@]}"; do
    ausgabe=$($SUDO ufw allow proto tcp from "$netz" to any port 22 comment 'zenOS SSH lokal' 2>&1) || true
  done
  mapfile -t danach < <(_sicherheit_ssh_fehlend "${netze[@]}")
  for netz in "${fehlend[@]}"; do
    if [[ " ${danach[*]} " != *" $netz "* ]]; then
      aenderung "Firewall: SSH (22/tcp) aus $netz erlaubt (vorbereitet, ufw bleibt aus)"
    fi
  done
  if (( ${#danach[@]} > 0 )); then
    log_warnung "SSH-Regeln liessen sich nicht anlegen für: ${danach[*]} (${ausgabe##*$'\n'})"
  fi
}

# core.hooksPath=.githooks im Quell-Repo, damit gitleaks vor jedem Commit läuft
_sicherheit_hook() {
  local quelle code wurzel ist
  quelle=$(readlink -f -- "$ZENOS_QUELLE")
  code=$(readlink -m -- "$ZENOS_CODE")
  [[ "$quelle" != "$code" ]] || return 0
  wurzel=$(git -C "$quelle" rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ "$(readlink -f -- "$wurzel")" == "$quelle" ]] || return 0
  if [[ "$(stat -c '%U' -- "$quelle" 2>/dev/null)" != "$ZENOS_BENUTZER" ]]; then
    log_info "Quell-Repo gehört nicht $ZENOS_BENUTZER, gitleaks-Hook nicht gesetzt"
    return 0
  fi
  if [[ ! -x "$quelle/.githooks/pre-commit" ]]; then
    log_warnung "$quelle/.githooks/pre-commit fehlt oder ist nicht ausführbar, gitleaks-Hook nicht gesetzt"
    return 0
  fi

  ist=$(git -C "$quelle" config --local --get core.hooksPath 2>/dev/null) || ist=""
  if [[ -n "$ist" ]]; then
    [[ "$ist" == /* ]] || ist="$quelle/$ist"
    [[ "$(readlink -m -- "$ist")" != "$quelle/.githooks" ]] || return 0
    log_info "core.hooksPath zeigte auf ${ist/#"$ZENOS_HOME"/\~}, jetzt .githooks"
  fi
  git -C "$quelle" config --local core.hooksPath .githooks
  aenderung "gitleaks-Hook in ${quelle/#"$ZENOS_HOME"/\~} (core.hooksPath=.githooks)"
}
