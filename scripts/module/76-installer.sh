#!/usr/bin/env bash
# 76-installer: zen Installer – heruntergeladene Software (.deb) so einfach installieren wie auf dem Mac
# shellcheck shell=bash
#
# Doppelklick auf eine .deb (Thunar, ein Download aus Chrome oder Firefox) öffnet den zen Installer; dort zeigt er, was
# das Paket mitbringt, und installiert es nach «Installieren» und dem Passwort (scripts/bin/zenos-installer):
# - scripts/bin/zenos-installer als root-eigene Kopie nach /usr/local/libexec/zenos/zenos-installer (wie zenos-basis:
#   Die Units und der Helfer führen diese Kopie aus, nicht /opt/zenos). Ist ein Ordner auf dem Weg nicht nur für root
#   schreibbar, unterbleibt alles (root führt die Datei aus).
# - Units nach /etc/systemd/system, statisch: zenos-installer-installieren@.service (Instanz: SHA-256 der Datei) und
#   zenos-installer-entfernen@.service (Instanz: Paketname). Nur scripts/bin/zenos-installer-bedienen startet sie
#   (pkexec aus dem Fenster bzw. den Einstellungen, sudo aus zen install).
# - polkit-Aktionen (system/polkit/org.zenos.installer.policy): installieren und entfernen jedes Mal mit Passwort, nur
#   in der aktiven Sitzung am Gerät.
# - Starter /usr/local/share/applications/zenos-installer.desktop (NoDisplay, MimeType für .deb). Standard für .deb ist
#   er über /etc/xdg/labwc-mimeapps.list (48-ablage); eine eigene Wahl in ~/.config/mimeapps.list geht vor.
# - /var/lib/zenos/installer (root, 0755) für installiert.json und letzte.json, darin ablage/ (root, 0755) für die
#   Datei, solange eine Installation läuft. Das Log /var/log/zenos/installer.log legt zenos-installer selbst an.
# Pakete braucht es keine weiteren (dpkg, apt, pkexec, python3 sind da). Läuft auch im Image-Modus (chroot).
#
# Rückweg: Die Dateien oben entfernen (sudo rm /usr/local/libexec/zenos/zenos-installer
# /etc/systemd/system/zenos-installer-*@.service /usr/share/polkit-1/actions/org.zenos.installer.policy
# /usr/local/share/applications/zenos-installer.desktop) und die zwei Zeilen für .deb aus
# system/xdg/labwc-mimeapps.list nehmen. Installierte Software bleibt; entfernen dann mit «sudo apt remove PAKET».

# Ziele (die Einheitentests setzen andere)
_INSTALLER_LIBEXEC=/usr/local/libexec
_INSTALLER_UNITS=/etc/systemd/system
_INSTALLER_ZUSTAND=/var/lib/zenos
_INSTALLER_POLICY=/usr/share/polkit-1/actions/org.zenos.installer.policy
_INSTALLER_STARTER=/usr/local/share/applications/zenos-installer.desktop
_INSTALLER_EINHEITEN=(zenos-installer-installieren@.service zenos-installer-entfernen@.service)

modul_system() {
  local einheit
  if ! _installer_pfad_sicher "$_INSTALLER_LIBEXEC"; then
    log_warnung "$_INSTALLER_LIBEXEC oder ein Ordner darüber ist nicht nur für root schreibbar: zen Installer bleibt weg"
    return 0
  fi
  ordner_sicherstellen "$_INSTALLER_LIBEXEC/zenos" 0755 root:root
  datei_installieren "$ZENOS_CODE/scripts/bin/zenos-installer" "$_INSTALLER_LIBEXEC/zenos/zenos-installer" 0755 root:root
  for einheit in "${_INSTALLER_EINHEITEN[@]}"; do
    datei_installieren "$ZENOS_CODE/system/systemd/system/$einheit" "$_INSTALLER_UNITS/$einheit" 0644 root:root
  done
  ordner_sicherstellen "$_INSTALLER_ZUSTAND" 0755 root:root
  ordner_sicherstellen "$_INSTALLER_ZUSTAND/installer" 0755 root:root
  ordner_sicherstellen "$_INSTALLER_ZUSTAND/installer/ablage" 0755 root:root
  datei_installieren "$ZENOS_CODE/system/polkit/org.zenos.installer.policy" "$_INSTALLER_POLICY" 0644 root:root
  datei_installieren "$ZENOS_CODE/system/applications/zenos-installer.desktop" "$_INSTALLER_STARTER" 0644 root:root
}

# Gehört jeder vorhandene Ordner auf dem Weg root, und ist keiner für andere schreibbar? (wie 71-basis)
_installer_pfad_sicher() {
  local pfad=$1 rechte
  while [[ "$pfad" != / ]]; do
    if [[ -e "$pfad" ]]; then
      rechte=$(stat -c '%u %a' -- "$pfad") || return 1
      [[ "${rechte%% *}" == 0 ]] || return 1
      (( (8#${rechte##* } & 8#022) == 0 )) || return 1
    fi
    pfad=$(dirname -- "$pfad")
  done
}
