#!/usr/bin/env bash
# 82-gesten: Gesten – Dienst zenos-gesten, udev-Regel, Benutzer, Touchpads und Tastaturen (Gruppe und Rechte der
# Knoten, drei Finger), keine Rechte der Sitzung an /dev/input, Verbindung der Oberfläche
# shellcheck shell=bash
#
# Liest nur: Dateien unter /etc, Benutzer und Gruppen (ohne Namen auszugeben), /sys/class/input und die udev-Datenbank
# (über zenos-gesten --pruefen, nennt nur Knoten wie «event5»), den Zustand des Dienstes und «zenos-ipc gesten status».

_gesten_code=/opt/zenos
_gesten_aus=/etc/xdg/zenos/gesten-aus

pruefe_gesten() {
  abschnitt "Gesten (Wischen mit drei Fingern)"
  if [[ -e "$_gesten_aus" ]]; then
    _gesten_aus_pruefen
    return 0
  fi
  _gesten_dateien
  _gesten_benutzer
  _gesten_geraete
  _gesten_dienst
  _gesten_oberflaeche
}

# Notschalter gesetzt: Dann darf nichts mehr da sein
_gesten_aus_pruefen() {
  local datei rest=0
  hinweis "Gesten aus (Notschalter $_gesten_aus), Super+Tab geht immer"
  for datei in /etc/udev/rules.d/72-zenos-gesten.rules /etc/systemd/system/zenos-gesten.service \
    /etc/sysusers.d/zenos-gesten.conf; do
    if [[ -e "$datei" ]]; then
      warnung "$datei liegt noch da (install.sh nimmt es zurück)"
      rest=1
    fi
  done
  if getent group zenos-gesten > /dev/null 2>&1 || getent passwd zenos-gesten > /dev/null 2>&1; then
    warnung "Benutzer oder Gruppe zenos-gesten gibt es noch (install.sh nimmt sie zurück)"
    rest=1
  fi
  (( rest )) || ok "Regel, Dienst und Benutzer sind entfernt"
}

_gesten_dateien() {
  local quelle ziel paar alle=1
  for paar in system/systemd/system/zenos-gesten.service:/etc/systemd/system/zenos-gesten.service \
    system/udev/72-zenos-gesten.rules:/etc/udev/rules.d/72-zenos-gesten.rules \
    system/sysusers/zenos-gesten.conf:/etc/sysusers.d/zenos-gesten.conf; do
    quelle=$_gesten_code/${paar%%:*}
    ziel=${paar#*:}
    if [[ ! -f "$ziel" ]]; then
      fehler "$ziel fehlt (install.sh)"
      alle=0
    elif [[ -r "$quelle" ]] && ! cmp -s -- "$quelle" "$ziel"; then
      warnung "$ziel weicht vom Stand in $_gesten_code ab (install.sh)"
      alle=0
    fi
  done
  (( ! alle )) || ok "Dienst, udev-Regel und Benutzer-Eintrag installiert"
}

_gesten_benutzer() {
  local eintrag shell
  if ! eintrag=$(getent passwd zenos-gesten 2> /dev/null); then
    fehler "Benutzer zenos-gesten fehlt (install.sh legt ihn über systemd-sysusers an)"
    return 0
  fi
  shell=${eintrag##*:}
  case "$shell" in
    */nologin | /bin/false | /usr/bin/false) ok "Dienstbenutzer zenos-gesten ohne Anmeldung" ;;
    *) warnung "Dienstbenutzer zenos-gesten hat die Shell $shell statt nologin" ;;
  esac
}

# Touchpads, Tastaturen und Gruppen der Sitzung aus zenos-gesten --pruefen (je Zeile «art<TAB>text»)
_gesten_geraete() {
  local programm=$_gesten_code/scripts/bin/zenos-gesten art text gelesen=0
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
      *) warnung "zenos-gesten --pruefen: unerwartete Zeile" ;;
    esac
  done < <(python3 -I "$programm" --pruefen 2> /dev/null)
  (( gelesen )) || fehler "zenos-gesten --pruefen gibt nichts aus (python3 -I $programm --pruefen)"
}

# Gehört ein Eingabeknoten der Gruppe zenos-gesten (ein reines Touchpad laut Regel)?
_gesten_touchpad_da() {
  getent group zenos-gesten > /dev/null 2>&1 || return 1
  [[ -n "$(find /dev/input -maxdepth 1 -name 'event*' -group zenos-gesten -print -quit 2> /dev/null)" ]]
}

_gesten_dienst() {
  local einheit=zenos-gesten.service zustand pid besitzer
  zustand=$(systemctl is-active "$einheit" 2> /dev/null)
  case "$zustand" in
    active)
      pid=$(systemctl show -p MainPID --value "$einheit" 2> /dev/null)
      besitzer=$(stat -c %U -- "/proc/${pid:-0}" 2> /dev/null) || besitzer=""
      if [[ "$besitzer" == zenos-gesten ]]; then
        ok "Dienst $einheit läuft als zenos-gesten (nur lesend, ohne Grab)"
      elif [[ -n "$besitzer" ]]; then
        fehler "$einheit läuft nicht als zenos-gesten (Einheit prüfen, install.sh)"
      else
        ok "Dienst $einheit läuft"
      fi
      if [[ -S /run/zenos-gesten/gesten.sock ]]; then
        ok "Socket /run/zenos-gesten/gesten.sock für die Oberfläche"
      else
        warnung "/run/zenos-gesten/gesten.sock fehlt, obwohl der Dienst läuft (journalctl -u $einheit)"
      fi
      ;;
    activating) hinweis "$einheit startet gerade (journalctl -u $einheit)" ;;
    failed) fehler "$einheit ist fehlgeschlagen (journalctl -u $einheit)" ;;
    *)
      if _gesten_touchpad_da; then
        fehler "$einheit läuft nicht, obwohl ein Touchpad da ist (journalctl -u $einheit)"
      else
        hinweis "$einheit ruht ohne Touchpad"
      fi
      ;;
  esac
}

# Liest die Oberfläche die Gesten? Nur, wenn eine Sitzung läuft und antwortet.
_gesten_oberflaeche() {
  local laufzeit antwort
  laufzeit=/run/user/$(id -u)
  [[ -d "$laufzeit/quickshell" ]] || return 0
  antwort=$(XDG_RUNTIME_DIR=$laufzeit timeout 5 "$_gesten_code/scripts/bin/zenos-ipc" gesten status 2> /dev/null) ||
    return 0
  case "$antwort" in
    verbunden) ok "Oberfläche liest die Gesten" ;;
    getrennt)
      if systemctl --quiet is-active zenos-gesten.service 2> /dev/null; then
        warnung "Oberfläche ist nicht mit zenos-gesten verbunden (sie versucht es höchstens alle 30 s wieder)"
      else
        hinweis "Oberfläche wartet auf zenos-gesten"
      fi
      ;;
  esac
}
