#!/usr/bin/env bash
# 76-installer: zen Installer – eingerichtet, Standard für .deb, Ablage leer, letzte Installation
# shellcheck shell=bash
#
# Ohne root, nur lesend. Nennt keine Dateinamen aus dem Home, nur Paketnamen und Ergebnisse.

# Programm, Units und Ziele (die Einheitentests setzen andere)
_INSTALLER_PROGRAMM=/usr/local/libexec/zenos/zenos-installer
_INSTALLER_QUELLE=/opt/zenos/scripts/bin/zenos-installer
_INSTALLER_UNITS=/etc/systemd/system
_INSTALLER_POLICY=/usr/share/polkit-1/actions/org.zenos.installer.policy
_INSTALLER_STARTER=/usr/local/share/applications/zenos-installer.desktop
_INSTALLER_ABLAGE=/var/lib/zenos/installer/ablage
_INSTALLER_PYTHON=/usr/bin/python3
_INSTALLER_EINHEITEN=(zenos-installer-installieren@.service zenos-installer-entfernen@.service)

pruefe_installer() {
  abschnitt "zen Installer"
  if [[ ! -f "$_INSTALLER_PROGRAMM" ]]; then
    hinweis "zen Installer noch nicht eingerichtet ($_INSTALLER_PROGRAMM fehlt; install.sh richtet ihn ein)"
    return 0
  fi
  _installer_einrichtung
  _installer_standard
  _installer_zustand
}

_installer_einrichtung() {
  local einheit fehlt=()
  if ! _installer_nur_root "$_INSTALLER_PROGRAMM"; then
    fehler "$_INSTALLER_PROGRAMM oder ein Ordner darüber ist nicht nur für root schreibbar – root führt es aus (install.sh)"
  elif [[ -r "$_INSTALLER_QUELLE" ]] && ! cmp -s "$_INSTALLER_PROGRAMM" "$_INSTALLER_QUELLE"; then
    warnung "$_INSTALLER_PROGRAMM weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  fi
  for einheit in "${_INSTALLER_EINHEITEN[@]}"; do
    [[ -f "$_INSTALLER_UNITS/$einheit" ]] || fehlt+=("$einheit")
  done
  [[ -f "$_INSTALLER_POLICY" ]] || fehlt+=("polkit-Aktionen")
  [[ -f "$_INSTALLER_STARTER" ]] || fehlt+=("Starter")
  if (( ${#fehlt[@]} )); then
    warnung "zen Installer unvollständig, es fehlt: ${fehlt[*]} (install.sh)"
  else
    ok "zen Installer eingerichtet"
  fi
}

# Wie in der Sitzung: gio liest labwc-mimeapps.list nur mit diesem XDG_CURRENT_DESKTOP
_installer_standard() {
  local standard
  command -v gio > /dev/null 2>&1 || return 0
  standard=$(XDG_CURRENT_DESKTOP=labwc:wlroots LC_ALL=C gio mime application/vnd.debian.binary-package 2> /dev/null |
    sed -n 's/^Default application for .*: //p' | head -n 1)
  case "$standard" in
    zenos-installer.desktop) ok ".deb-Pakete öffnet der zen Installer" ;;
    "") warnung "Keine App für .deb-Pakete (/etc/xdg/labwc-mimeapps.list, install.sh)" ;;
    *) hinweis ".deb-Pakete öffnet ${standard%.desktop} (eigene Wahl in ~/.config/mimeapps.list)" ;;
  esac
}

_installer_zustand() {
  local zeile zustand text anzahl
  # Arithmetik statt der rohen Ausgabe: BSD-wc rückt die Zahl mit Leerzeichen ein
  anzahl=$(($(find "$_INSTALLER_ABLAGE" -mindepth 1 -maxdepth 1 2> /dev/null | wc -l)))
  zeile=$("$_INSTALLER_PYTHON" -I "$_INSTALLER_PROGRAMM" status --kurz 2> /dev/null | head -n 1) || zeile=""
  zustand=${zeile%% *}
  text=${zeile#* }
  if (( anzahl > 0 )) && [[ "$zustand" != laeuft ]]; then
    hinweis "Ablage des zen Installers nicht leer ($anzahl Dateien, Rest einer abgebrochenen Installation; die nächste räumt nach einer Stunde auf)"
  fi
  case "$zustand" in
    keine | "") ;;
    laeuft) hinweis "zen Installer: $text" ;;
    installiert | gleich | entfernt) ok "zen Installer zuletzt $text" ;;
    abgelehnt | wartet) hinweis "zen Installer zuletzt $text" ;;
    fehler) warnung "zen Installer zuletzt gescheitert $text" ;;
    *) warnung "zen Installer: unbekanntes Ergebnis «$zustand»" ;;
  esac
}

# Gehört PFAD und jeder Ordner darüber root, und ist nichts davon für andere schreibbar?
_installer_nur_root() {
  local pfad=$1 rechte
  while [[ -n "$pfad" && "$pfad" != / ]]; do
    rechte=$(stat -c '%u %a' -- "$pfad" 2>/dev/null) || return 1
    [[ "${rechte%% *}" == 0 ]] || return 1
    (( (8#${rechte##* } & 8#022) == 0 )) || return 1
    pfad=$(dirname -- "$pfad")
  done
}
