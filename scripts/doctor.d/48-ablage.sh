#!/usr/bin/env bash
# 48-ablage: ~/Ablage, die XDG-Benutzerordner und der Dateimanager (Thunar als Standard für Ordner)
# shellcheck shell=bash
#
# Nur lesen. user-dirs.dirs wird nie ausgeführt (source), nur Zeile für Zeile gelesen.

pruefe_ablage() {
  abschnitt "Ablage und Dateimanager"
  _ablage_dateimanager
  _ablage_ordner
  _ablage_user_dirs
  _ablage_thunar_aktion
}

_ablage_code=/opt/zenos

_ablage_dateimanager() {
  local standard version
  if command -v thunar > /dev/null 2>&1; then
    version=$(thunar --version 2> /dev/null | head -n 1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
    ok "Thunar ${version:-?}"
  else
    warnung "Thunar fehlt (Paket thunar); Ordner öffnen dann in kitty"
  fi
  if [[ -f /etc/xdg/labwc-mimeapps.list ]] &&
    cmp -s -- "$_ablage_code/system/xdg/labwc-mimeapps.list" /etc/xdg/labwc-mimeapps.list; then
    ok "/etc/xdg/labwc-mimeapps.list wie im Repo"
  else
    warnung "/etc/xdg/labwc-mimeapps.list fehlt oder weicht ab (install.sh)"
  fi
  # Wie in der Sitzung: gio liest labwc-mimeapps.list nur mit diesem XDG_CURRENT_DESKTOP
  if command -v gio > /dev/null 2>&1; then
    standard=$(XDG_CURRENT_DESKTOP=labwc:wlroots LC_ALL=C gio mime inode/directory 2> /dev/null |
      sed -n 's/^Default application for .*: //p' | head -n 1)
    case "$standard" in
      thunar.desktop) ok "Ordner öffnet Thunar" ;;
      "") warnung "Keine App für Ordner; zenos-oeffnen nimmt kitty" ;;
      *) hinweis "Ordner öffnet ${standard%.desktop} (eigene Wahl in ~/.config/mimeapps.list)" ;;
    esac
  fi
  local datei fehlend=0
  for datei in thunar-bulk-rename.desktop thunar-settings.desktop; do
    cmp -s -- "$_ablage_code/system/applications/$datei" "/usr/local/share/applications/$datei" || fehlend=1
  done
  if (( fehlend )); then
    hinweis "Hilfsstarter von Thunar nicht ausgeblendet (/usr/local/share/applications, install.sh)"
  else
    ok "Hilfsstarter von Thunar im Befehlsfeld ausgeblendet"
  fi
}

_ablage_ordner() {
  local ablage=$HOME/Ablage
  if [[ -L "$ablage" && -d "$ablage" ]]; then
    ok "Ablage: ~/Ablage ist ein Verweis auf einen Ordner"
  elif [[ -d "$ablage" ]]; then
    ok "Ablage: ~/Ablage vorhanden ($(stat -c '%a' -- "$ablage" 2> /dev/null || printf '?'))"
  elif [[ -e "$ablage" || -L "$ablage" ]]; then
    warnung "Ablage: ~/Ablage ist kein Ordner, der Ablage-Knopf öffnet nichts"
  else
    warnung "Ablage: ~/Ablage fehlt (zen benutzer legt sie an)"
  fi
}

# Wert eines Eintrags aus user-dirs.dirs wie in der Datei, etwa «$HOME/Ablage» (leer, wenn er fehlt):
# _ablage_eintrag DATEI NAME
_ablage_eintrag() {
  sed -n "s/^XDG_$2_DIR=\"\\(.*\\)\"[[:space:]]*\$/\\1/p" "$1" 2> /dev/null | tail -n 1
}

_ablage_user_dirs() {
  local datei=$HOME/.config/user-dirs.dirs download
  if [[ ! -f "$datei" ]]; then
    warnung "Benutzerordner: ~/.config/user-dirs.dirs fehlt, Downloads landen nicht in ~/Ablage (zen benutzer)"
    return 0
  fi
  download=$(_ablage_eintrag "$datei" DOWNLOAD)
  if [[ "$(head -n 1 -- "$datei")" == '# zenOS: '* ]]; then
    ok "Benutzerordner von zenOS: Downloads, Dokumente, Bilder, Musik, Videos landen in ~/Ablage"
  elif [[ "$download" == "\$HOME/Ablage" ]]; then
    ok "Eigene user-dirs.dirs, Downloads landen in ~/Ablage"
  elif [[ -z "$download" ]]; then
    hinweis "Eigene user-dirs.dirs ohne Download-Ordner, Downloads landen in ~/Downloads"
  elif [[ "$download" == "\$HOME"* ]]; then
    hinweis "Eigene user-dirs.dirs, Downloads landen in ~${download#"\$HOME"}"
  else
    # Ein absoluter Pfad kann den Benutzernamen enthalten: nicht ausgeben
    hinweis "Eigene user-dirs.dirs, Downloads landen ausserhalb von ~"
  fi
}

# «Terminal hier öffnen» in Thunar (~/.config/Thunar/uca.xml, Benutzerteil von 48-ablage)
_ablage_thunar_aktion() {
  local datei=$HOME/.config/Thunar/uca.xml
  if [[ ! -e "$datei" ]]; then
    hinweis "Thunar: ~/.config/Thunar/uca.xml fehlt, «Terminal hier öffnen» zeigt einen Fehler (zen benutzer)"
  elif [[ "$(head -n 1 -- "$datei" 2> /dev/null)" == '<!-- zenOS: '* ]]; then
    ok "Thunar: «Terminal hier öffnen» startet kitty"
  elif grep -q -- '--launch TerminalEmulator' "$datei" 2> /dev/null; then
    # Thunar kopiert beim ersten Start die Beispiel-Aktion, falls zenOS die Datei noch nicht angelegt hat
    hinweis "Thunar: «Terminal hier öffnen» nutzt exo-open und zeigt einen Fehler (docs/module/ablage.md)"
  else
    ok "Thunar: eigene Aktionen (~/.config/Thunar/uca.xml)"
  fi
}
