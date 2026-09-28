#!/usr/bin/env bash
# 75-apps: proprietäre Apps (nur Name und Version), zweiter Starter von coremail, Standardbrowser, ihre
# Paketquellen, SSH-Agent von 1Password, Nubix
# shellcheck shell=bash

pruefe_apps() {
  abschnitt "Apps"
  _apps_installiert
  _apps_starter
  _apps_browser
  _apps_quellen
  _apps_agent
  _apps_nubix
}

_apps_version() { # PAKET → Upstream-Version, Rückgabe 1 wenn nicht installiert
  local zeile v
  zeile=$(dpkg-query -W -f='${db:Status-Status} ${Version}' "$1" 2>/dev/null) || return 1
  [[ "$zeile" == "installed "* ]] || return 1
  v=${zeile#installed }
  v=${v#*:}
  [[ "$v" == *-* ]] && v=${v%-*}
  printf '%s' "$v"
}

_apps_installiert() {
  local eintrag paket name app version
  for eintrag in "google-chrome-stable|Google Chrome|chrome" "code|Visual Studio Code|vscode" \
    "1password-cli|1Password-CLI|cli" "coremail-desktop|coremail|coremail"; do
    IFS='|' read -r paket name app <<< "$eintrag"
    if version=$(_apps_version "$paket"); then
      ok "$name $version"
    else
      hinweis "$name nicht installiert (zen apps installieren $app)"
    fi
  done
  if [[ -x /opt/1Password/1password && ( -f /opt/1Password/.zenos-stand || -L /usr/bin/1password ) ]]; then
    version=$(sed -n '/^version=/{s///p;q}' /opt/1Password/.zenos-stand 2>/dev/null)
    ok "1Password ${version:-(Version unbekannt)}"
  elif [[ -x /opt/1Password/1password ]]; then
    warnung "1Password liegt in /opt/1Password, ist aber nicht fertig eingerichtet (zen apps installieren 1password)"
  else
    hinweis "1Password nicht installiert (zen apps installieren 1password)"
  fi
}

# Das Programm einer Exec-Zeile: das erste Wort, bei «env» das erste nach den Zuweisungen NAME=WERT (wie
# _exec_programm in zenos-apps). Rückgabe 1, wenn die Zeile dafür zu verwickelt ist.
_apps_exec_programm() { # EXEC
  local -a teile=()
  local i=0
  [[ "$1" != *[\"\'\\\`\$]* ]] || return 1
  read -r -a teile <<< "$1"
  (( ${#teile[@]} > 0 )) || return 1
  if [[ "${teile[0]}" == env || "${teile[0]}" == */env ]]; then
    i=1
    while (( i < ${#teile[@]} )) && [[ "${teile[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
    (( i < ${#teile[@]} )) && [[ "${teile[i]}" != -* ]] || return 1
  fi
  printf '%s' "${teile[i]}"
}

# coremail (bis mindestens 7.2.0) schreibt beim ersten Start einer neuen Version einen zweiten Starter für
# seine AppImage-Fassung, auch als .deb; das Programm darin gibt es dann nicht. zen benutzer entfernt ihn,
# während der Sitzung auch gleich (zenos-coremail-starter.path). Dieselbe Bedingung wie _coremail_starter
# in zenos-apps.
_apps_starter() {
  local datei=$HOME/.local/share/applications/coremail.desktop zeile programm
  [[ -f "$datei" && ! -L "$datei" ]] || return 0
  _apps_version coremail-desktop > /dev/null || return 0
  zeile=$(sed -n 's/^Exec[[:space:]]*=[[:space:]]*//p' "$datei" | head -n 1)
  [[ "$zeile" == *coremail* ]] || return 0
  programm=$(_apps_exec_programm "$zeile") || return 0
  if [[ "$programm" == */* ]]; then
    [[ ! -x "$programm" ]] || return 0
  else
    ! command -v -- "$programm" > /dev/null 2>&1 || return 0
  fi
  warnung "coremail: zweiter Starter ~/.local/share/applications/coremail.desktop zeigt auf ein fehlendes Programm (zen benutzer entfernt ihn)"
}

# Chrome als Standardbrowser: zen benutzer trägt ihn ein, solange in mimeapps.list nichts anderes gewählt
# ist. Eine andere Wahl ist erlaubt, deshalb nur ein Hinweis.
_apps_browser() {
  local antwort
  _apps_version google-chrome-stable > /dev/null || return 0
  command -v xdg-settings > /dev/null || return 0
  antwort=$(xdg-settings check default-web-browser google-chrome.desktop 2> /dev/null) || return 0
  case "$antwort" in
    yes) ok "Chrome ist Standardbrowser" ;;
    no) hinweis "Chrome ist nicht Standardbrowser (eigene Wahl in ~/.config/mimeapps.list; sonst trägt zen benutzer ihn ein)" ;;
  esac
}

# Paketquellen der Hersteller: nur mit signed-by und nicht doppelt
_apps_quellen() {
  local datei host anzahl signiert schluessel
  local -a liste
  local -A dateien=()
  shopt -s nullglob
  for datei in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
    for host in dl.google.com packages.microsoft.com downloads.1password.com; do
      grep -Eq "^[[:space:]]*(URIs:.*|deb .*)https?://$host" "$datei" 2>/dev/null || continue
      dateien[$host]+="${datei##*/} "
      if [[ "$datei" == *.sources ]]; then
        schluessel=$(sed -n 's/^[[:space:]]*Signed-By:[[:space:]]*//p' "$datei" | head -n 1)
      else
        schluessel=$(grep -Eo 'signed-by=[^] ]+' "$datei" | head -n 1)
        schluessel=${schluessel#signed-by=}
      fi
      signiert=0
      [[ -n "$schluessel" && ( "$schluessel" != /* || -r "$schluessel" ) ]] && signiert=1
      if (( signiert )); then
        ok "Quelle ${datei##*/} ($host, signed-by)"
      else
        warnung "Quelle ${datei##*/} ($host) ohne gültigen signed-by-Schlüssel – apt vertraut ihr zu weit"
      fi
    done
  done
  shopt -u nullglob
  for host in "${!dateien[@]}"; do
    read -r -a liste <<< "${dateien[$host]}"
    anzahl=${#liste[@]}
    if (( anzahl > 1 )); then
      warnung "Mehrere Quellen für $host (${liste[*]}) – eine davon entfernen (zenOS nutzt zenos-*.sources)"
    fi
  done
}

_apps_agent() {
  [[ -x /opt/1Password/1password ]] || return 0
  if [[ -S "$HOME/.1password/agent.sock" ]]; then
    ok "SSH-Agent von 1Password: Socket vorhanden (ja)"
  else
    hinweis "SSH-Agent von 1Password: Socket vorhanden (nein) – in 1Password unter Einstellungen → Entwickler einschalten"
  fi
  # Massgeblich ist der Wert im Benutzer-Manager: Ihn erben die Oberfläche und die Apps, die sie
  # startet. Ubuntus ssh-agent.socket setzt ihn sonst auf den eigenen Agent (Drop-in von zen apps).
  local soll="$HOME/.1password/agent.sock" openssh umgebung wert pid alt
  if [[ ! -f "$HOME/.config/environment.d/zenos-1password.conf" ||
    ! -f "$HOME/.config/systemd/user/ssh-agent.socket.d/zenos-1password.conf" ]]; then
    warnung "SSH_AUTH_SOCK für die Sitzung nicht eingerichtet (zen benutzer richtet es ein)"
    return 0
  fi
  if ! umgebung=$(systemctl --user show-environment 2>/dev/null); then
    hinweis "SSH_AUTH_SOCK für die Sitzung eingerichtet; Benutzer-Manager nicht erreichbar, wirksamer Wert nicht geprüft"
    return 0
  fi
  wert=$(sed -n 's/^SSH_AUTH_SOCK=//p' <<< "$umgebung" | tail -n 1)
  openssh=${XDG_RUNTIME_DIR:-/run/user/$UID}/openssh_agent
  if [[ "$wert" == "$soll" ]]; then
    ok "SSH_AUTH_SOCK der Sitzung zeigt auf 1Password (~/.1password/agent.sock)"
  elif [[ "$wert" == "$openssh" ]]; then
    warnung "SSH_AUTH_SOCK der Sitzung zeigt auf den Agent von OpenSSH statt auf 1Password (ssh-agent.socket von Ubuntu überschreibt ihn) – zen benutzer, dann neu anmelden"
    return 0
  elif [[ -z "$wert" ]]; then
    warnung "SSH_AUTH_SOCK der Sitzung ist nicht gesetzt – zen benutzer, dann neu anmelden"
    return 0
  else
    warnung "SSH_AUTH_SOCK der Sitzung zeigt auf einen anderen Agent statt auf 1Password (systemctl --user show-environment zeigt ihn)"
    return 0
  fi
  # Die laufende Oberfläche hat ihre Umgebung beim Start bekommen
  pid=$(systemctl --user show -p MainPID --value zenos-shell.service 2>/dev/null)
  [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/environ" ]] || return 0
  alt=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^SSH_AUTH_SOCK=//p' | tail -n 1)
  if [[ "$alt" != "$soll" ]]; then
    hinweis "Die laufende Oberfläche kennt den Agent noch nicht – Apps aus dem Befehlsfeld nutzen ihn ab der nächsten Anmeldung"
  fi
}

# Nubix gibt es bisher nur für amd64. Ob inzwischen ein arm64-Build existiert, weiss zen apps
# (letzte Abfrage im Cache); doctor fragt selbst nicht im Netz nach.
_apps_nubix() {
  local arch cache asset version
  if version=$(_apps_version nubix); then
    ok "Nubix $version"
    return 0
  fi
  arch=$(dpkg --print-architecture 2>/dev/null)
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/zenos/apps.json
  if [[ -r "$cache" ]]; then
    asset=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("nubix") or {}).get("asset") or "")' "$cache" 2>/dev/null)
    version=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("nubix") or {}).get("version") or "")' "$cache" 2>/dev/null)
  fi
  if [[ -n "$asset" ]]; then
    hinweis "Nubix ${version:+$version }gibt es jetzt für $arch (zen apps installieren nubix)"
  elif [[ "$arch" == arm64 ]]; then
    hinweis "Nubix: noch kein ARM-Build${version:+ (neueste Version $version)} – offen, zen apps status --netz prüft neu"
  else
    hinweis "Nubix nicht installiert (zen apps installieren nubix)"
  fi
}
