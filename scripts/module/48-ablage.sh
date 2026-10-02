#!/usr/bin/env bash
# 48-ablage: der eine Ordner ~/Ablage, die XDG-Benutzerordner und der Dateimanager Thunar
# shellcheck shell=bash
#
# System: Thunar nachziehen (scripts/pakete/ablage.txt, installiert 20-pakete), /etc/xdg/labwc-mimeapps.list (Ordner
# öffnet Thunar, nur in der labwc-Sitzung; eine eigene Wahl in ~/.config/mimeapps.list geht vor) und zwei
# Hilfsstarter von Thunar ausblenden: «Bulk Rename» und «Thunar Preferences» sind in Thunar selbst erreichbar und
# gehören nicht ins Befehlsfeld. Hidden=true in /usr/local/share/applications/ heisst nach der Desktop-Entry-
# Spezifikation «gelöscht» und überdeckt die Datei gleichen Namens in /usr/share/applications/.
# Benutzer: ~/Ablage anlegen, wenn sie fehlt, und die XDG-Benutzerordner darauf richten; in Thunar öffnet
# «Terminal hier öffnen» kitty (~/.config/Thunar/uca.xml). Gründe: docs/module/ablage.md.

modul_system() {
  # Die Pakete installiert 20-pakete gesammelt; hier nur nachziehen, falls etwas fehlt.
  local -a pakete=()
  local zeile datei
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_QUELLE/scripts/pakete/ablage.txt"
  pakete_sicherstellen "${pakete[@]}"

  datei_installieren "$ZENOS_CODE/system/xdg/labwc-mimeapps.list" /etc/xdg/labwc-mimeapps.list 0644 root:root
  for datei in thunar-bulk-rename.desktop thunar-settings.desktop; do
    datei_installieren "$ZENOS_CODE/system/applications/$datei" "/usr/local/share/applications/$datei" 0644 root:root
  done
}

modul_benutzer() {
  local uca=$ZENOS_CODE/system/thunar/uca.xml
  _ablage_ordner
  _ablage_screenshots
  _ablage_eigene_datei "$ZENOS_HOME/.config/user-dirs.dirs" "$(_ablage_marke)" < <(_ablage_user_dirs)
  _ablage_eigene_datei "$ZENOS_HOME/.config/user-dirs.conf" "$(_ablage_marke)" <<EOF
$(_ablage_marke)
# xdg-user-dirs-update lässt user-dirs.dirs unverändert, falls xdg-user-dirs einmal installiert wird.
enabled=False
EOF
  # «Terminal hier öffnen» in Thunar mit kitty (Gründe in der Vorlage). Hat Thunar die Datei selbst geschrieben
  # (eigene Aktionen), bleibt sie ohne Hinweis.
  if [[ -f "$uca" ]]; then
    _ablage_eigene_datei "$ZENOS_HOME/.config/Thunar/uca.xml" "$(_ablage_uca_marke)" leise < "$uca"
  else
    log_warnung "Vorlage $uca fehlt; Thunar behält die Beispiel-Aktion «Open Terminal Here»"
  fi
}

# Erste Zeile der Benutzerordner-Dateien, die dieses Modul im Home schreibt. Fehlt sie, gehört die Datei dir und
# bleibt unverändert.
_ablage_marke() { printf '%s' '# zenOS: Benutzerordner zeigen auf ~/Ablage (scripts/module/48-ablage.sh)'; }
# Erste Zeile von ~/.config/Thunar/uca.xml (wie in system/thunar/uca.xml)
_ablage_uca_marke() { printf '%s' '<!-- zenOS: Thunar-Aktion «Terminal hier öffnen» mit kitty (scripts/module/48-ablage.sh) -->'; }

# ~/Ablage anlegen, wenn sie fehlt: 0700, nur für dich lesbar wie ~/.config/zenos (Downloads und Dokumente sind
# persönlich, und ausser dir braucht kein Konto Zugriff). Danach bleibt sie, wie sie ist: zenOS löscht und
# verschiebt sie nie und setzt die Rechte nicht zurück. Ein Verweis auf einen Ordner (etwa in einen Sync-Ordner)
# ist erlaubt. Liegt dort etwas anderes, bleibt es mit einer Warnung liegen.
_ablage_ordner() {
  local ablage=$ZENOS_HOME/Ablage
  [[ -d "$ablage" ]] && return 0
  if [[ -e "$ablage" || -L "$ablage" ]]; then
    log_warnung "$ablage ist kein Ordner und bleibt unverändert; der Ablage-Knopf der Leiste öffnet dann nichts"
    return 0
  fi
  # -m setzt den Modus unabhängig von der umask
  mkdir -m 0700 -- "$ablage"
  aenderung "Ordner $ablage"
}

# Bildschirmfotos (zenos-bildschirmfoto) liegen in ~/Ablage/Screenshots. Der Unterordner entsteht gleich hier,
# damit er in der Ablage sichtbar ist. Der frühere Ort ~/Bilder/Screenshots verschwindet nur, wenn er leer ist
# (ebenso ein danach leeres ~/Bilder); liegen dort noch Bilder, bleiben sie, und das Protokoll sagt, wie man sie holt.
_ablage_screenshots() {
  local ablage=$ZENOS_HOME/Ablage alt=$ZENOS_HOME/Bilder/Screenshots
  [[ -d "$ablage" ]] || return 0
  if [[ ! -e "$ablage/Screenshots" && ! -L "$ablage/Screenshots" ]]; then
    mkdir -- "$ablage/Screenshots"
    aenderung "Ordner $ablage/Screenshots"
  fi
  [[ -d "$alt" && ! -L "$alt" ]] || return 0
  if rmdir -- "$alt" 2> /dev/null; then
    aenderung "leeren Ordner $alt entfernt (Bildschirmfotos liegen jetzt in $ablage/Screenshots)"
    if rmdir -- "$ZENOS_HOME/Bilder" 2> /dev/null; then aenderung "leeren Ordner $ZENOS_HOME/Bilder entfernt"; fi
  else
    log_info "Hinweis: In $alt liegen noch Bildschirmfotos. Holen mit: mv ~/Bilder/Screenshots/* ~/Ablage/Screenshots/"
  fi
}

# Inhalt von ~/.config/user-dirs.dirs. Apps lesen die Datei selbst (GLib, Qt, Chrome, Firefox), ein Paket braucht
# es dafür nicht. «$HOME» steht wörtlich in der Datei (Format von xdg-user-dirs). Vorlagen und Öffentlich zeigen auf
# $HOME, das heisst bei xdg-user-dirs «abgeschaltet», und es entsteht kein Ordner: Thunar liest den
# Vorlagen-Ordner bei «Dokument erstellen» rekursiv ein und böte sonst jede Datei der Ablage als Vorlage an, und
# der Ordner zum Freigeben im Netz zeigt nie auf deine Dateien.
# Dazu ~/.config/user-dirs.conf mit enabled=False: Kommt xdg-user-dirs später mit einem anderen Paket dazu, läuft
# xdg-user-dirs-update bei jeder Anmeldung und richtete einen Eintrag, dessen Ordner gerade fehlt, wieder auf
# Desktop, Downloads … (und legte diese Ordner an).
_ablage_user_dirs() {
  local name ziel
  _ablage_marke
  printf '\n'
  printf '%s\n' \
    '# Ein Ordner ohne vorgegebene Struktur: Downloads, Dokumente, Bilder, Musik und Videos landen in ~/Ablage.' \
    '# Vorlagen und Öffentlich zeigen aufs Home, so sind sie abgeschaltet. Eigene Fassung: die erste Zeile' \
    '# entfernen, dann ändert zenOS die Datei nicht mehr.'
  for name in DESKTOP DOWNLOAD TEMPLATES PUBLICSHARE DOCUMENTS MUSIC PICTURES VIDEOS; do
    case "$name" in TEMPLATES | PUBLICSHARE) ziel="" ;; *) ziel=Ablage ;; esac
    # shellcheck disable=SC2016
    printf 'XDG_%s_DIR="$HOME/%s"\n' "$name" "$ziel"
  done
}

# Schreibt ZIEL mit dem Inhalt von stdin, wenn es fehlt oder seine erste Zeile MARKE ist (von zenOS); sonst bleibt es,
# mit einem Hinweis im Log (ohne mit «leise»). Ein Verweis (z. B. aus Dotfiles) gilt als eigene Fassung.
#   _ablage_eigene_datei ZIEL MARKE [leise]
_ablage_eigene_datei() {
  local ziel=$1 marke=$2 leise=${3:-} erste=""
  if [[ -e "$ziel" || -L "$ziel" ]]; then
    if [[ -f "$ziel" && ! -L "$ziel" ]]; then
      IFS= read -r erste < "$ziel" || true
    fi
    if [[ "$erste" != "$marke" ]]; then
      [[ -n "$leise" ]] || log_info "Hinweis: $ziel stammt nicht von zenOS und bleibt unverändert (docs/module/ablage.md)"
      return 0
    fi
  fi
  benutzer_datei_schreiben "$ziel" 0644
}
