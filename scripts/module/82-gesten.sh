#!/usr/bin/env bash
# 82-gesten: Wischen mit drei Fingern – Dienstbenutzer, udev-Regel für reine Touchpads, Dienst zenos-gesten
# shellcheck shell=bash
#
# labwc 0.9.3 bindet keine Touchpad-Gesten. Der Systemdienst zenos-gesten (scripts/bin/zenos-gesten) liest deshalb die
# Touchpads mit, nur lesend und ohne Grab, und meldet «oben» und «unten» an die Oberfläche (shell/dienste/Gesten.qml).
# - Benutzer und Gruppe zenos-gesten über systemd-sysusers (/etc/sysusers.d/zenos-gesten.conf): gesperrt, ohne Home,
#   ohne weitere Gruppen. Niemand sonst kommt in diese Gruppe, und niemand in die Gruppe input.
# - udev-Regel /etc/udev/rules.d/72-zenos-gesten.rules: Knoten reiner Touchpads (ohne Tasten) gehören
#   root:zenos-gesten mit 0640 statt root:input mit 0660 und ziehen den Dienst nach (SYSTEMD_WANTS). Nach einer
#   Änderung lädt das Modul die Regeln neu und stösst die Touchpads an (udevadm trigger), wenn udev läuft (nicht im
#   Image, nicht im Testcontainer ohne udev).
# - zenos-gesten.service nach /etc/systemd/system, ohne [Install]: Er läuft nur, wenn es ein Touchpad gibt. Gibt es
#   eins, startet ihn das Modul (nicht im Image); nach einer Änderung an Einheit, Regel oder Programm neu.
# Keine Pakete: libinput10 kommt mit labwc, python3 und systemd sind da.
#
# Rückweg (Notschalter /etc/xdg/zenos/gesten-aus, «sudo touch …», dann install.sh): Das Modul nimmt alles zurück. Es
# stoppt den Dienst (auch mitten im Neustart), beendet übrige Prozesse von zenos-gesten (etwa den Messmodus), entfernt
# die Regel, gibt die Touchpads zurück (root:input 0660 wie ohne Regel), entfernt Einheit und sysusers-Datei und löscht
# Benutzer und Gruppe. Lässt sich einer davon nicht löschen, warnt es nur (der nächste Lauf versucht es wieder, zen
# doctor meldet den Rest). Ohne Schalter richtet der nächste Lauf alles wieder ein. Ein
# zen rollback auf einen Stand ohne dieses Modul lässt alles liegen, harmlos: Ohne /opt/zenos/scripts/bin/zenos-gesten
# startet der Dienst nicht, und die Touchpads liest dann niemand ausser labwc (über logind).

_GESTEN_EINHEIT=zenos-gesten.service
_GESTEN_REGEL=/etc/udev/rules.d/72-zenos-gesten.rules
_GESTEN_SYSUSERS=/etc/sysusers.d/zenos-gesten.conf
_GESTEN_AUS=/etc/xdg/zenos/gesten-aus
_GESTEN_NAME=zenos-gesten

modul_system() {
  local vorher regel_neu=0
  if [[ -e "$_GESTEN_AUS" ]]; then
    log_info "Notschalter $_GESTEN_AUS gesetzt: Gesten aus (Super+Tab geht immer)"
    _gesten_entfernen
    return 0
  fi
  datei_installieren "$ZENOS_CODE/system/sysusers/zenos-gesten.conf" "$_GESTEN_SYSUSERS" 0644 root:root
  _gesten_benutzer
  datei_installieren "$ZENOS_CODE/system/systemd/system/$_GESTEN_EINHEIT" "/etc/systemd/system/$_GESTEN_EINHEIT" \
    0644 root:root
  vorher=$(zenos_anzahl aenderung)
  datei_installieren "$ZENOS_CODE/system/udev/72-zenos-gesten.rules" "$_GESTEN_REGEL" 0644 root:root
  (( $(zenos_anzahl aenderung) > vorher )) && regel_neu=1
  _gesten_udev "$regel_neu"
  _gesten_dienst
}

# Benutzer und Gruppe anlegen, wenn eins davon fehlt (systemd-sysusers, auch im Image: es schreibt nur /etc)
_gesten_benutzer() {
  local mitglieder
  if ! getent passwd "$_GESTEN_NAME" > /dev/null || ! getent group "$_GESTEN_NAME" > /dev/null; then
    if ! befehl_vorhanden systemd-sysusers; then
      log_warnung "systemd-sysusers fehlt: Benutzer $_GESTEN_NAME nicht angelegt, der Gestendienst startet nicht"
      return 0
    fi
    $SUDO systemd-sysusers "$_GESTEN_SYSUSERS"
    aenderung "Benutzer und Gruppe $_GESTEN_NAME (systemd-sysusers)"
  fi
  mitglieder=$(getent group "$_GESTEN_NAME" | cut -d: -f4) || mitglieder=""
  if [[ -n "$mitglieder" ]]; then
    log_warnung "Die Gruppe $_GESTEN_NAME hat Mitglieder, sie gehört nur dem Dienst (gpasswd -d …)"
  fi
}

# Läuft udev? Nicht im Image und nicht im Testcontainer, wo systemd-udevd maskiert ist
_gesten_udev_da() {
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 1
  befehl_vorhanden udevadm || return 1
  $SUDO udevadm control --ping > /dev/null 2>&1
}

# Knoten reiner Touchpads (ID_INPUT_TOUCHPAD ohne ID_INPUT_KEY und ID_INPUT_KEYBOARD) laut udev, je Zeile «eventN»
_gesten_touchpads() {
  local pfad eigenschaften
  for pfad in /sys/class/input/event*; do
    [[ -e "$pfad" ]] || continue
    eigenschaften=$(udevadm info --query=property --path="$pfad" 2> /dev/null) || continue
    grep -qx 'ID_INPUT_TOUCHPAD=1' <<< "$eigenschaften" || continue
    grep -qE '^ID_INPUT_(KEY|KEYBOARD)=.' <<< "$eigenschaften" && continue
    printf '%s\n' "${pfad##*/}"
  done
}

# 0, wenn ein reines Touchpad noch nicht root:zenos-gesten 0640 gehört (Regel kam, als udev nicht lief)
_gesten_knoten_falsch() {
  local knoten
  while IFS= read -r knoten; do
    [[ -e "/dev/input/$knoten" ]] || continue
    [[ "$(stat -c '%U:%G %a' -- "/dev/input/$knoten" 2> /dev/null)" == "root:$_GESTEN_NAME 640" ]] || return 0
  done < <(_gesten_touchpads)
  return 1
}

# Regeln neu laden und die Touchpads anstossen (change), wenn die Regel neu ist oder ein Knoten nicht passt
_gesten_udev() {
  local regel_neu=$1
  _gesten_udev_da || return 0
  if (( ! regel_neu )) && ! _gesten_knoten_falsch; then return 0; fi
  $SUDO udevadm control --reload
  $SUDO udevadm trigger --action=change --subsystem-match=input --property-match=ID_INPUT_TOUCHPAD=1 --settle
  if _gesten_knoten_falsch; then
    log_warnung "Ein Touchpad gehört nach der udev-Regel nicht root:$_GESTEN_NAME 0640 (zen doctor, Abschnitt Gesten)"
  elif (( ! regel_neu )); then
    aenderung "Touchpads: Knoten wieder root:$_GESTEN_NAME 0640 (udev)"
  fi
}

# 0, wenn der Dienst läuft und zenos-gesten seit seinem Start geändert wurde (z. B. nach zen update)
_gesten_code_neuer() {
  local start code
  start=$(systemctl show --timestamp=unix -p ExecMainStartTimestamp --value "$_GESTEN_EINHEIT" 2> /dev/null) || return 1
  start=${start#@}
  code=$(stat -c %Y -- "$ZENOS_CODE/scripts/bin/zenos-gesten" 2> /dev/null) || return 1
  [[ "$start" =~ ^[0-9]+$ && "$code" =~ ^[0-9]+$ ]] || return 1
  (( code > start ))
}

# Dienst starten bzw. neu starten (nicht im Image). Ohne Touchpad bleibt er aus. Ein Fehler hält die Installation
# nicht auf: Ohne Dienst geht nur das Wischen nicht, Super+Tab bleibt.
_gesten_dienst() {
  local knoten touchpad=0
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  if systemctl --quiet is-active "$_GESTEN_EINHEIT" 2> /dev/null; then
    if modul_geaendert || _gesten_code_neuer; then
      systemd_neu_laden
      if $SUDO systemctl restart "$_GESTEN_EINHEIT"; then
        log_info "Dienst neu gestartet: $_GESTEN_EINHEIT"
      else
        log_warnung "$_GESTEN_EINHEIT liess sich nicht neu starten (journalctl -u $_GESTEN_EINHEIT)"
      fi
    fi
    return 0
  fi
  while IFS= read -r knoten; do
    [[ "$(stat -c %G -- "/dev/input/$knoten" 2> /dev/null)" == "$_GESTEN_NAME" ]] && touchpad=1
  done < <(_gesten_touchpads)
  (( touchpad )) || return 0
  systemd_neu_laden
  $SUDO systemctl reset-failed "$_GESTEN_EINHEIT" 2> /dev/null || true
  if $SUDO systemctl start "$_GESTEN_EINHEIT"; then
    log_info "Dienst gestartet: $_GESTEN_EINHEIT"
  else
    log_warnung "$_GESTEN_EINHEIT liess sich nicht starten (journalctl -u $_GESTEN_EINHEIT)"
  fi
}

# Rückweg: alles zurücknehmen, die Touchpads wieder root:input 0660
_gesten_entfernen() {
  local regel_weg=0 vorher
  _gesten_stoppen
  vorher=$(zenos_anzahl aenderung)
  datei_entfernen "$_GESTEN_REGEL"
  (( $(zenos_anzahl aenderung) > vorher )) && regel_weg=1
  if (( regel_weg )) && _gesten_udev_da; then
    $SUDO udevadm control --reload
  fi
  _gesten_knoten_zurueck
  datei_entfernen "/etc/systemd/system/$_GESTEN_EINHEIT"
  datei_entfernen "$_GESTEN_SYSUSERS"
  systemd_neu_laden
  if [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]]; then
    $SUDO systemctl reset-failed "$_GESTEN_EINHEIT" 2> /dev/null || true
  fi
  # Erst jetzt Benutzer und Gruppe: Kein Prozess läuft mehr als zenos-gesten, kein Knoten gehört noch der Gruppe.
  # userdel nimmt die gleichnamige Gruppe meist gleich mit. Scheitert es doch (ein Prozess kam neu dazu), bricht die
  # Installation nicht ab: Regel und Einheit sind weg, der nächste Lauf versucht es wieder.
  if getent passwd "$_GESTEN_NAME" > /dev/null; then
    if $SUDO userdel "$_GESTEN_NAME"; then
      aenderung "Benutzer $_GESTEN_NAME gelöscht"
    else
      log_warnung "Benutzer $_GESTEN_NAME liess sich nicht löschen (läuft noch ein Prozess?)," \
        "der nächste Lauf versucht es wieder"
    fi
  fi
  if getent group "$_GESTEN_NAME" > /dev/null; then
    if $SUDO groupdel "$_GESTEN_NAME"; then
      aenderung "Gruppe $_GESTEN_NAME gelöscht"
    else
      log_warnung "Gruppe $_GESTEN_NAME liess sich nicht löschen, der nächste Lauf versucht es wieder"
    fi
  fi
}

# Dienst stoppen, auch wenn er gerade startet oder auf den Neustart wartet (is-active: activating), dann jeden
# übrigen Prozess von zenos-gesten beenden, etwa den Messmodus in einem zweiten Terminal. Nicht im Image: Dort zeigte
# /proc womöglich Prozesse des bauenden Rechners.
_gesten_stoppen() {
  local zustand
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  zustand=$(systemctl is-active "$_GESTEN_EINHEIT" 2> /dev/null) || true
  case "$zustand" in
    inactive | failed | unknown | "") ;;
    *)
      $SUDO systemctl stop "$_GESTEN_EINHEIT" || log_warnung "$_GESTEN_EINHEIT liess sich nicht stoppen"
      aenderung "Dienst gestoppt: $_GESTEN_EINHEIT"
      ;;
  esac
  getent passwd "$_GESTEN_NAME" > /dev/null || return 0
  befehl_vorhanden pgrep || return 0
  pgrep -u "$_GESTEN_NAME" > /dev/null 2>&1 || return 0
  $SUDO pkill -TERM -u "$_GESTEN_NAME" 2> /dev/null || true
  for _ in {1..30}; do
    pgrep -u "$_GESTEN_NAME" > /dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -u "$_GESTEN_NAME" > /dev/null 2>&1; then
    $SUDO pkill -KILL -u "$_GESTEN_NAME" 2> /dev/null || true
    sleep 0.2
  fi
  aenderung "Prozesse von $_GESTEN_NAME beendet (z. B. Messmodus)"
}

# Knoten der Gruppe zenos-gesten wieder so, wie udev sie ohne die Regel anlegt (50-udev-default.rules: root:input
# 0660). Direkt statt über «udevadm trigger»: Die Vorgaben von udev greifen nur bei «add», und ein zweites «add» für ein
# laufendes Touchpad sähe labwc (libinput) womöglich als weiteres Gerät. Nicht im Image (dort ist /dev nicht das Ziel).
_gesten_knoten_zurueck() {
  local knoten
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  getent group "$_GESTEN_NAME" > /dev/null || return 0
  while IFS= read -r -d '' knoten; do
    $SUDO chgrp input -- "$knoten"
    $SUDO chmod 0660 -- "$knoten"
    aenderung "$knoten wieder root:input 0660"
  done < <(find /dev/input -maxdepth 1 -name 'event*' -group "$_GESTEN_NAME" -print0 2> /dev/null)
}
