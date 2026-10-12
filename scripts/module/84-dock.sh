#!/usr/bin/env bash
# 84-dock: Docks und Bildschirm über USB erkennen – udev-Regel und Benutzerdienst zenos-dock
# shellcheck shell=bash
#
# Ein USB-C-Dock ohne Bild (Billboard) oder ein DisplayLink-Gerät startet über die udev-Regel
# /etc/udev/rules.d/73-zenos-dock.rules den Benutzerdienst zenos-dock.service (SYSTEMD_USER_WANTS). Der meldet einmal,
# was geht (scripts/bin/zenos-dock, docs/module/dock.md). Die Regel ändert keine Rechte und startet nichts als root.
# - Benutzereinheit nach /etc/systemd/user (wie 50-raster); zenos-sitzung.target startet sie auch beim Anmelden.
# - Nach einer neuen oder geänderten Regel lädt das Modul die Regeln neu und stösst nur Billboard- und
#   DisplayLink-Geräte an (udevadm trigger --action=change, nie «add»), damit ein schon eingestecktes Dock gleich erkannt
#   wird. Nicht im Image und nicht im Testcontainer ohne udev.
# Keine Pakete: python3, systemd und notify-send (libnotify-bin aus basis.txt) sind da. Kein Treiber: Der
# DisplayLink-Treiber ist proprietär und kommt nie ins Image.
# Ein zen rollback auf einen Stand ohne dieses Modul lässt Regel und Einheit liegen, harmlos: Ohne
# /opt/zenos/scripts/bin/zenos-dock startet der Dienst nicht (ConditionFileIsExecutable).

_DOCK_REGEL=/etc/udev/rules.d/73-zenos-dock.rules
_DOCK_EINHEIT=/etc/systemd/user/zenos-dock.service

modul_system() {
  local vorher
  datei_installieren "$ZENOS_CODE/system/systemd/user/zenos-dock.service" "$_DOCK_EINHEIT" 0644 root:root
  vorher=$(zenos_anzahl aenderung)
  datei_installieren "$ZENOS_CODE/system/udev/73-zenos-dock.rules" "$_DOCK_REGEL" 0644 root:root
  (( $(zenos_anzahl aenderung) > vorher )) || return 0
  _dock_udev_da || return 0
  # Erst die Einheit bekannt machen (auch der Benutzerinstanz), dann die Geräte anstossen
  systemd_neu_laden
  $SUDO udevadm control --reload
  _dock_anstossen --attr-match=bDeviceClass=11
  _dock_anstossen --attr-match=idVendor=17e9
  _dock_anstossen --attr-match=bInterfaceClass=11
}

# Läuft udev? Nicht im Image und nicht im Testcontainer, wo systemd-udevd maskiert ist
_dock_udev_da() {
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 1
  befehl_vorhanden udevadm || return 1
  $SUDO udevadm control --ping > /dev/null 2>&1
}

# Passende USB-Geräte noch einmal durch die Regeln schicken. Scheitert das, erkennt zenOS das Dock beim nächsten
# Einstecken oder Anmelden: nur eine Warnung.
_dock_anstossen() {
  if ! $SUDO udevadm trigger --action=change --subsystem-match=usb "$1"; then
    log_warnung "udevadm trigger $1 gescheitert: Ein schon eingestecktes Dock meldet sich erst beim nächsten Einstecken"
  fi
}
