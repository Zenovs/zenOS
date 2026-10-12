#!/usr/bin/env bash
# 84-dock: Docks und Bildschirm über USB – udev-Regel und Benutzerdienst installiert, Befunde von zenos-dock
# (Bildausgänge, USB-C-Docks mit Billboard, DisplayLink, Netzwerk über USB), letzter Lauf des Dienstes
# shellcheck shell=bash
#
# Liest nur: Dateien unter /etc und /opt/zenos, /sys über «zenos-dock pruefen» (nennt Hersteller, Produkt und vid:pid,
# keine Seriennummern, keine Netzwerknamen) und den Zustand der Benutzereinheit.

_dock_code=/opt/zenos

pruefe_dock() {
  abschnitt "Docks und Bildschirm über USB"
  _dock_dateien
  _dock_befunde
  _dock_dienst
}

_dock_dateien() {
  local paar quelle ziel alle=1
  for paar in system/udev/73-zenos-dock.rules:/etc/udev/rules.d/73-zenos-dock.rules \
    system/systemd/user/zenos-dock.service:/etc/systemd/user/zenos-dock.service; do
    quelle=$_dock_code/${paar%%:*}
    ziel=${paar#*:}
    if [[ ! -f "$ziel" ]]; then
      fehler "$ziel fehlt (install.sh)"
      alle=0
    elif [[ -r "$quelle" ]] && ! cmp -s -- "$quelle" "$ziel"; then
      warnung "$ziel weicht vom Stand in $_dock_code ab (install.sh)"
      alle=0
    fi
  done
  (( ! alle )) || ok "udev-Regel und Benutzerdienst zenos-dock installiert"
}

# Befunde aus zenos-dock pruefen (je Zeile «art<TAB>text»)
_dock_befunde() {
  local programm=$_dock_code/scripts/bin/zenos-dock art text gelesen=0
  if [[ ! -r "$programm" ]]; then
    fehler "$programm fehlt (zen update oder install.sh)"
    return 0
  fi
  while IFS=$'\t' read -r art text; do
    gelesen=1
    case "$art" in
      ok) ok "$text" ;;
      hinweis) hinweis "$text" ;;
      warnung) warnung "$text" ;;
      fehler) fehler "$text" ;;
      *) warnung "zenos-dock pruefen: unerwartete Zeile" ;;
    esac
  done < <(timeout 20 python3 -I "$programm" pruefen 2> /dev/null)
  (( gelesen )) || fehler "zenos-dock pruefen gibt nichts aus (python3 -I $programm pruefen)"
}

# Der Dienst läuft kurz und endet; der Rede wert ist nur ein gescheiterter letzter Lauf
_dock_dienst() {
  local laufzeit zustand
  laufzeit=/run/user/$(id -u)
  [[ -S "$laufzeit/bus" ]] || return 0
  zustand=$(XDG_RUNTIME_DIR=$laufzeit systemctl --user is-failed zenos-dock.service 2> /dev/null) || zustand=""
  if [[ "$zustand" == failed ]]; then
    warnung "zenos-dock.service ist zuletzt gescheitert (journalctl --user -u zenos-dock)"
  fi
  return 0
}
