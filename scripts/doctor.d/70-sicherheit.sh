#!/usr/bin/env bash
# 70-sicherheit: automatische Updates (auch: Ubuntu-Sicherheitsquelle erlaubt), ufw und unattended-upgrades manuell
# installiert, Chrome- und VS Code-Richtlinie, Ubuntu-Nachrichten, ohne snapd und landscape-common, gitleaks und Hook,
# Firewall
# shellcheck shell=bash
#
# Die sudo-Regel aus dem Bau prüft schon 00-basis. Die Firewall ist standardmässig an; ist sie aus, warnt doctor
# (auch wenn der Benutzer sie bewusst ausgeschaltet hat). Die Firewall-Regeln sind nur für root lesbar; ohne
# sudo ohne Passwort bleibt es bei einem Hinweis. Ausgegeben werden nur Anzahlen, keine Adressen.

pruefe_sicherheit() {
  abschnitt "Sicherheit"
  _sicherheit_updates
  _sicherheit_markierung
  _sicherheit_chrome
  _sicherheit_vscode
  _sicherheit_nachrichten
  _sicherheit_ohne_snapd
  _sicherheit_gitleaks
  _sicherheit_firewall
}

_sicherheit_apt_wert() {
  apt-config shell WERT "$1" 2>/dev/null | sed -n "s/^WERT='\(.*\)'\$/\1/p"
}

_sicherheit_updates() {
  local datei wert anzahl
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
  _sicherheit_quelle

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
    _sicherheit_letzter_lauf
  fi

  if [[ -e /run/reboot-required ]]; then
    anzahl=""
    if [[ -r /run/reboot-required.pkgs ]]; then anzahl=$(sort -u /run/reboot-required.pkgs | grep -c .); fi
    hinweis "Nach Updates steht ein Neustart an${anzahl:+ (Pakete: $anzahl)} – automatische Neustarts sind aus"
  fi
}

# Erlaubt unattended-upgrades die Ubuntu-Sicherheitsquelle? zenos-sicherheitsquelle prüft das mit der Logik von
# unattended-upgrades selbst (Exit 0 erlaubt, 1 nicht erlaubt, 2 nicht prüfbar, etwa vor dem ersten apt update).
# 51zenos-ubuntu-quellen hält die Ubuntu-Quellen erlaubt, auch wenn /etc/os-release nicht Ubuntu meldet. Mit der
# Kennung von Ubuntu wirkt noch die Vorgabe aus 50unattended-upgrades, dann ist eine fehlende Datei nur eine Warnung;
# mit der Kennung zenOS (72-kennung) ein Fehler.
_sicherheit_quelle() {
  local programm=/opt/zenos/scripts/bin/zenos-sicherheitsquelle datei=/etc/apt/apt.conf.d/51zenos-ubuntu-quellen
  local ausgabe rc=0
  if [[ ! -f "$datei" && "$(os_release_wert ID)" == zenos ]]; then
    fehler "$datei fehlt – mit der Kennung zenOS kommen so keine Ubuntu-Sicherheitsupdates (install.sh)"
  elif [[ ! -f "$datei" ]]; then
    warnung "$datei fehlt – Ubuntu-Sicherheitsupdates hängen an der Kennung in /etc/os-release (install.sh)"
  elif [[ -r /opt/zenos/system/apt/51zenos-ubuntu-quellen ]] && ! cmp -s "$datei" /opt/zenos/system/apt/51zenos-ubuntu-quellen; then
    warnung "$datei weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  fi

  if [[ ! -x "$programm" ]]; then
    warnung "$programm fehlt – Sicherheitsquelle nicht geprüft (install.sh)"
    return 0
  fi
  ausgabe=$("$programm" 2>/dev/null) || rc=$?
  ausgabe=$(head -n 1 <<< "$ausgabe")
  case "$rc" in
    0) ok "Ubuntu-Sicherheitsquelle erlaubt: ${ausgabe#erlaubt: }" ;;
    1)
      # Ohne die Liste der erlaubten Quellen (steht in der vollen Ausgabe des Programms)
      ausgabe=${ausgabe#nicht erlaubt: }
      [[ "$ausgabe" != *"; erlaubt sind:"* ]] || ausgabe="${ausgabe%%; erlaubt sind:*})"
      fehler "Keine Ubuntu-Sicherheitsupdates: unattended-upgrades erlaubt $ausgabe nicht (install.sh; Einzelheiten: $programm)"
      ;;
    2) hinweis "Sicherheitsquelle nicht prüfbar: ${ausgabe#nicht prüfbar: }" ;;
    *) warnung "zenos-sicherheitsquelle ist gescheitert (Exit $rc)" ;;
  esac
}

# zenOS-Pakete, die beim Wegfallen eines Ubuntu-Metapakets nicht mit «apt autoremove» verschwinden dürfen. install.sh
# markiert alle Pakete aus scripts/pakete/*.txt als manuell installiert (20-pakete); geprüft werden die zwei, ohne die
# es keine Firewall und keine automatischen Sicherheitsupdates gibt.
_sicherheit_markierung() {
  local -a auto=()
  mapfile -t auto < <(apt-mark showauto ufw unattended-upgrades 2>/dev/null)
  if (( ${#auto[@]} > 0 )); then
    warnung "Als automatisch installiert markiert: ${auto[*]} – apt autoremove entfernte sie mit, wenn ein Ubuntu-Metapaket wegfällt (install.sh markiert sie als manuell)"
  elif paket_installiert ufw && paket_installiert unattended-upgrades; then
    ok "ufw und unattended-upgrades als manuell installiert markiert (bleiben bei apt autoremove)"
  fi
}

# Letzter erfolgreicher Lauf: apt.systemd.daily berührt /var/lib/apt/periodic/upgrade-stamp nur, wenn
# unattended-upgrade im täglichen Lauf mit Erfolg endet (für alle lesbar). Die Zeit des Timers taugt nicht:
# systemd legt seinen Stempel schon beim ersten Start des Timers an. Result des Dienstes zählt nur, wenn er
# in diesem Boot lief, sonst ist es der Grundwert «success»; einen Fehler von unattended-upgrade gibt
# apt.systemd.daily ohnehin nicht weiter.
_sicherheit_letzter_lauf() {
  local stempel=/var/lib/apt/periodic/upgrade-stamp zeit start zustand ergebnis alter datum gelaufen=0
  zeit=$(stat -c %Y -- "$stempel" 2>/dev/null) || zeit=""
  start=$(systemctl show -p ExecMainStartTimestamp --value --timestamp=unix apt-daily-upgrade.service 2>/dev/null)
  zustand=$(systemctl show -p ActiveState --value apt-daily-upgrade.service 2>/dev/null)
  ergebnis=$(systemctl show -p Result --value apt-daily-upgrade.service 2>/dev/null)
  [[ ! "$start" =~ ^@[1-9][0-9]*$ ]] || gelaufen=1

  if [[ "$zustand" == activating || "$zustand" == active ]]; then
    hinweis "unattended-upgrades läuft gerade (apt-daily-upgrade)"
  elif (( gelaufen )) && [[ "$ergebnis" != success ]]; then
    warnung "Letzter Lauf von unattended-upgrades ist gescheitert (${ergebnis:-unbekannt}; journalctl -u apt-daily-upgrade)"
  elif [[ ! "$zeit" =~ ^[1-9][0-9]*$ ]]; then
    if (( gelaufen )); then
      warnung "unattended-upgrades lief, aber ohne Erfolg (journalctl -u apt-daily-upgrade, /var/log/unattended-upgrades/)"
    else
      hinweis "unattended-upgrades ist noch nie gelaufen (täglich gegen 6 Uhr, war der Pi aus: kurz nach dem Start)"
    fi
  else
    alter=$(( ($(date +%s) - zeit) / 86400 ))
    datum=$(date -d "@$zeit" '+%d.%m.%Y %H:%M' 2>/dev/null)
    if (( alter < 3 )); then
      ok "Letzter erfolgreicher Lauf von unattended-upgrades: $datum"
    elif (( ! gelaufen && $(_sicherheit_seit_start) < 7200 )); then
      # War der Pi einige Tage aus, holt der Timer (Persistent=true) den Lauf kurz nach dem Start nach
      hinweis "Letzter erfolgreicher Lauf von unattended-upgrades am $datum; der nächste folgt kurz nach dem Start"
    else
      warnung "Seit $alter Tagen kein erfolgreicher Lauf von unattended-upgrades (journalctl -u apt-daily-upgrade, /var/log/unattended-upgrades/)"
    fi
  fi
}

# Sekunden seit dem Start des Systems
_sicherheit_seit_start() {
  local sekunden=0
  read -r sekunden _ 2>/dev/null < /proc/uptime || sekunden=0
  printf '%s\n' "${sekunden%%.*}"
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
# motd-news: install.sh maskiert Timer und Dienst und legt 50-motd-news per statoverride still. Ältere Stände setzten
# stattdessen ENABLED=0 in /etc/default/motd-news; das bleibt stehen und hält das Skript ebenfalls an.
_sicherheit_nachrichten() {
  local datei=/etc/default/motd-news skript=/etc/update-motd.d/50-motd-news wert=""
  if [[ -f "$datei" ]]; then
    wert=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}ENABLED=//p' "$datei" 2>/dev/null |
      tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '"'"'"'[:space:]')
  fi
  if [[ "$(systemctl is-enabled motd-news.timer 2>/dev/null)" == masked ]]; then
    ok "motd-news aus (Timer maskiert)"
  elif [[ "$wert" == 1 ]]; then
    warnung "motd-news ist eingeschaltet und ruft zweimal täglich motd.ubuntu.com auf (install.sh schaltet es ab)"
  elif [[ -f "$datei" || -f "$skript" ]]; then
    hinweis "motd-news nur über ENABLED in $datei aus, der Timer läuft noch (install.sh maskiert ihn)"
  fi
  if [[ -f "$skript" && ! -L "$skript" ]] && ! dpkg-statoverride --list "$skript" >/dev/null 2>&1; then
    hinweis "$skript läuft noch bei jeder Anmeldung (zeigt Zwischengespeichertes; install.sh legt es still)"
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

# snapd und landscape-common entfernt, snapd per apt-Pin gesperrt (scripts/module/22-aufraeumen.sh). Bleibt eines,
# weil es bewusst installiert ist (manuell markiert) oder snapd wegen eigener Snaps, ist das ein Hinweis. Solange
# snapd installiert ist, darf der Pin nicht liegen: Er hielte snapd ohne Updates fest.
_sicherheit_ohne_snapd() {
  local quelle=/opt/zenos/system/apt/zenos-ohne-snapd pin eigene
  local -a namen=()
  # shellcheck source=../lib/aufraeumen.sh
  source "$ZEN_SKRIPTE/lib/aufraeumen.sh" || { fehler "lib/aufraeumen.sh nicht ladbar"; return 0; }
  pin=$_AUFRAEUMEN_PIN

  if paket_installiert landscape-common; then
    if [[ -n "$(apt-mark showmanual landscape-common 2>/dev/null)" ]]; then
      hinweis "landscape-common bleibt: bewusst installiert (als manuell markiert)"
    else
      warnung "landscape-common ist noch installiert (zen update entfernt es)"
    fi
  fi

  if paket_installiert snapd; then
    if [[ -n "$(apt-mark showmanual snapd 2>/dev/null)" ]]; then
      hinweis "snapd bleibt: bewusst installiert (als manuell markiert; entfernen: sudo apt-mark auto snapd, dann zen update)"
    else
      eigene=$(_sicherheit_eigene_snaps)
      if [[ -n "$eigene" ]]; then
        mapfile -t namen <<< "$eigene"
        hinweis "snapd bleibt wegen eigener Snaps: $(_aufraeumen_liste "${namen[@]}") (Daten aus ~/snap sichern, sudo snap remove <name>, dann zen update)"
      else
        warnung "snapd ist noch installiert (zen update entfernt es)"
      fi
    fi
    if [[ -e "$pin" ]]; then
      warnung "$pin liegt, obwohl snapd installiert ist – snapd bekommt so keine Updates (install.sh entfernt den Pin)"
    fi
    return 0
  fi

  if [[ ! -f "$pin" ]]; then
    warnung "$pin fehlt – apt könnte snapd als Empfehlung wieder installieren (install.sh)"
  elif [[ -r "$quelle" ]] && ! cmp -s "$pin" "$quelle"; then
    warnung "$pin weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  elif paket_installiert landscape-common; then
    ok "Ohne snapd (per apt-Pin gesperrt)"
  else
    ok "Ohne snapd und landscape-common (snapd per apt-Pin gesperrt)"
  fi
}

# Eigene Snaps ohne Root-Rechte: die Snap-Dateien unter /var/lib/snapd/snaps (für alle lesbar) und, nur wenn snapd
# läuft, «snap list» (sonst startete der Aufruf snapd über snapd.socket)
_sicherheit_eigene_snaps() {
  {
    find /var/lib/snapd/snaps -maxdepth 1 ! -type d -name '*.snap' -printf '%f\n' 2>/dev/null | _aufraeumen_snap_dateien
    if systemctl --quiet is-active snapd.service 2>/dev/null; then
      LC_ALL=C timeout 30 snap list 2>/dev/null | _aufraeumen_snap_liste
    fi
  } | _aufraeumen_eigene
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
  local eingehend ausgehend tupel ausgabe seit policy=/usr/share/polkit-1/actions/org.zenos.firewall.policy
  local -a fehlend=() unbegrenzt=() netze=()
  # Gemeinsame Hilfsfunktionen (scripts/lib/firewall.sh) und die Liste der lokalen Netze
  # shellcheck source=../zen.d/firewall.sh
  source "$ZEN_SKRIPTE/zen.d/firewall.sh" || { fehler "zen.d/firewall.sh nicht ladbar"; return 0; }

  if ! _firewall_installiert; then
    fehler "ufw fehlt – keine Firewall (install.sh ausführen)"
    return 0
  fi
  if _firewall_aktiv; then
    ok "Firewall an (eingehend gesperrt, SSH nur aus lokalen Netzen)"
    if [[ "$(systemctl is-enabled ufw.service 2>/dev/null)" != enabled ]]; then
      warnung "ufw.service ist nicht aktiviert – die Firewall startet beim Hochfahren nicht (install.sh)"
    fi
    # ufw.service lädt die Regeln beim Hochfahren; scheitert das, steht in ufw.conf trotzdem «an»
    if [[ "$(systemctl is-active ufw.service 2>/dev/null)" == failed ]]; then
      warnung "ufw.service ist beim Hochfahren gescheitert – die Regeln sind womöglich nicht geladen (journalctl -u ufw)"
    fi
  elif [[ "$(_firewall_zustand)" == aus ]]; then
    seit=$(_firewall_seit_text)
    warnung "Firewall ist aus – bewusst ausgeschaltet${seit:+ am $seit} (einschalten: Einstellungen → System oder zen firewall aktivieren)"
  else
    warnung "Firewall ist aus – install.sh bzw. zen update schaltet sie ein (sofort: zen firewall aktivieren)"
  fi
  eingehend=$(_firewall_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  ausgehend=$(_firewall_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  if [[ "$eingehend" == DROP && "$ausgehend" == ACCEPT ]]; then
    ok "Firewall-Standard: eingehend verweigern, ausgehend erlauben"
  else
    warnung "Firewall-Standard: eingehend $(_firewall_politik "$eingehend"), ausgehend $(_firewall_politik "$ausgehend") (erwartet: verweigern, erlauben)"
  fi

  # Schalter in den Einstellungen: pkexec und die polkit-Aktionen
  if ! command -v pkexec >/dev/null 2>&1; then
    warnung "pkexec fehlt – der Schalter «Firewall» in den Einstellungen geht nicht (install.sh)"
  elif [[ ! -f "$policy" ]]; then
    warnung "polkit-Aktionen der Firewall fehlen ($policy) – der Schalter in den Einstellungen geht nicht (install.sh)"
  elif [[ -r /opt/zenos/system/polkit/org.zenos.firewall.policy ]] && ! cmp -s "$policy" /opt/zenos/system/polkit/org.zenos.firewall.policy; then
    warnung "polkit-Aktionen der Firewall weichen vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  else
    ok "Schalter in den Einstellungen bereit (Ausschalten nur mit Passwort)"
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
  ausgabe=$(_firewall_auswerten unbegrenzt "${netze[@]}" <<< "$tupel") || ausgabe=""
  mapfile -t unbegrenzt < <(printf '%s' "$ausgabe" | sed '/^$/d')
  if (( ${#fehlend[@]} == 0 )); then
    ok "SSH (22/tcp) aus den lokalen Netzen erlaubt (${#netze[@]} Regeln)"
  elif _firewall_aktiv; then
    fehler "Firewall an, aber ${#fehlend[@]} von ${#netze[@]} SSH-Regeln fehlen – SSH aus dem lokalen Netz kann gesperrt sein"
  else
    warnung "${#fehlend[@]} von ${#netze[@]} SSH-Regeln fehlen (install.sh legt sie an)"
  fi
  if (( ${#unbegrenzt[@]} > 0 )); then
    hinweis "${#unbegrenzt[@]} SSH-Regeln ohne Begrenzung (allow statt limit; install.sh stellt um)"
  fi
  if [[ "$(_firewall_wert IPV6 /etc/default/ufw)" != yes ]]; then
    warnung "IPv6 ist in ufw ausgeschaltet (IPV6 in /etc/default/ufw) – IPv6-Verkehr bliebe ungefiltert"
  fi
}
