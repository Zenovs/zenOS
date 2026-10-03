#!/usr/bin/env bash
# 35-netzwerk: NetworkManager für das WLAN-Menü (umgestellt wird nur mit «zen netzwerk umstellen»)
# shellcheck shell=bash
#
# Immer: Pakete aus scripts/pakete/netzwerk.txt nachziehen (20-pakete installiert sie schon), Einheiten ablegen:
# zenos-wlan-land.service (WLAN-Land mit iw), zenos-netzwerk-erststart.service (nur fürs Image) und ein Drop-in,
# das systemd-networkd-wait-online überspringt, solange NetworkManager das Netz verwaltet.
#
# Umgestellt ist, wenn /etc/netplan/90-zenos-netzwerk.yaml existiert (scripts/bin/zenos-netzwerk, docs/module/netzwerk.md).
# - Nicht umgestellt: Das Paket aktiviert NetworkManager und NetworkManager-wait-online bei der Installation. zenOS
#   schaltet beide wieder ab, damit der nächste Neustart genau wie vorher hochfährt (netplan mit systemd-networkd;
#   ohne laufenden NetworkManager wartete NetworkManager-wait-online sonst bei jedem Start). Ausnahme: NetworkManager
#   läuft schon oder hat Profile – dann gehört er jemandem und bleibt, wie er ist.
# - Umgestellt: NetworkManager, NetworkManager-wait-online und (mit Land) zenos-wlan-land bleiben aktiviert; die
#   Zusatzdateien von «umstellen» (WPA3-Option, cloud-init) werden aufgefrischt, falls sie noch da sind.
# - Image (--image): NetworkManager aktiviert, WPA3-Option (arm64), Marke /var/lib/zenos/netzwerk-erststart und
#   zenos-netzwerk-erststart.service: Der erste Start stellt nach cloud-init um. Die cloud-init-Datei nie im Image,
#   sonst griffe das WLAN aus dem Raspberry Pi Imager nicht.
# Gestartet oder angewendet wird nie etwas: kein «netplan apply», kein Start von NetworkManager (SSH bleibt).

modul_system() {
  _netzwerk_pakete
  local quelle=$ZENOS_CODE/system/systemd/system
  datei_installieren "$quelle/zenos-wlan-land.service" /etc/systemd/system/zenos-wlan-land.service
  datei_installieren "$quelle/zenos-netzwerk-erststart.service" /etc/systemd/system/zenos-netzwerk-erststart.service
  datei_installieren "$quelle/systemd-networkd-wait-online.service.d/zenos-netzwerk.conf" \
    /etc/systemd/system/systemd-networkd-wait-online.service.d/zenos-netzwerk.conf

  if [[ "$ZENOS_IMAGE" == 1 ]]; then
    _netzwerk_image
  elif [[ -e /etc/netplan/90-zenos-netzwerk.yaml ]]; then
    _netzwerk_umgestellt
  else
    _netzwerk_vorher
  fi
}

_netzwerk_pakete() {
  local zeile
  local -a pakete=()
  while IFS= read -r zeile || [[ -n "$zeile" ]]; do
    zeile=${zeile%%#*}
    zeile=${zeile//[[:space:]]/}
    [[ -n "$zeile" ]] && pakete+=("$zeile")
  done < "$ZENOS_CODE/scripts/pakete/netzwerk.txt"
  pakete_sicherstellen "${pakete[@]}"
}

# Deaktiviert eine Einheit, falls sie aktiviert ist (Gegenstück zu dienst_aktivieren)
_netzwerk_abschalten() {
  local einheit=$1 zustand
  zustand=$(systemctl is-enabled "$einheit" 2> /dev/null) || true
  case "$zustand" in
    enabled | enabled-runtime) ;;
    *) return 0 ;;
  esac
  $SUDO systemctl disable --quiet "$einheit"
  aenderung "Dienst deaktiviert: $einheit (bis «zen netzwerk umstellen»)"
}

# Wahr, wenn NetworkManager schon Profile hat: eigene (/etc/NetworkManager/system-connections) oder von netplan
# erzeugte (/run/NetworkManager/system-connections, nur bei «renderer: NetworkManager»)
_netzwerk_nm_hat_profile() {
  local ordner
  for ordner in /etc/NetworkManager/system-connections /run/NetworkManager/system-connections; do
    $SUDO test -d "$ordner" || continue
    [[ -n "$($SUDO find "$ordner" -mindepth 1 -maxdepth 1 -print -quit 2> /dev/null)" ]] && return 0
  done
  return 1
}

_netzwerk_vorher() {
  paket_installiert network-manager || return 0
  if [[ "$ZENOS_SYSTEMD" == 1 ]] && systemctl is-active --quiet NetworkManager.service 2> /dev/null; then
    log_info "NetworkManager läuft schon ohne «zen netzwerk umstellen» und bleibt, wie er ist"
    return 0
  fi
  if _netzwerk_nm_hat_profile; then
    log_info "NetworkManager hat schon Profile und bleibt, wie er ist"
    return 0
  fi
  _netzwerk_abschalten NetworkManager.service
  _netzwerk_abschalten NetworkManager-wait-online.service
}

_netzwerk_umgestellt() {
  dienst_aktivieren NetworkManager.service
  dienst_aktivieren NetworkManager-wait-online.service
  if [[ -f /etc/xdg/zenos/wlan-land ]]; then dienst_aktivieren zenos-wlan-land.service; fi
  # Nur auffrischen, was «umstellen» angelegt hat (wer eine Datei bewusst entfernt, bekommt sie nicht zurück)
  if [[ -e /etc/modprobe.d/zenos-brcmfmac.conf ]]; then
    datei_installieren "$ZENOS_CODE/system/modprobe/zenos-brcmfmac.conf" /etc/modprobe.d/zenos-brcmfmac.conf
  fi
  if [[ -e /etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg ]]; then
    datei_installieren "$ZENOS_CODE/system/cloud/99-zenos-netzwerk.cfg" /etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg
  fi
}

_netzwerk_image() {
  dienst_aktivieren NetworkManager.service
  dienst_aktivieren NetworkManager-wait-online.service
  dienst_aktivieren zenos-netzwerk-erststart.service
  # Das Image ist für den Raspberry Pi (WLAN-Chip mit brcmfmac); die Option muss beim ersten Laden des Treibers liegen
  if [[ "$(dpkg --print-architecture 2> /dev/null)" == arm64 ]]; then
    datei_installieren "$ZENOS_CODE/system/modprobe/zenos-brcmfmac.conf" /etc/modprobe.d/zenos-brcmfmac.conf
  fi
  ordner_sicherstellen /var/lib/zenos 0755 root:root
  printf '%s\n' '# zenOS: beim ersten Start auf NetworkManager umstellen (zenos-netzwerk-erststart.service, einmal)' |
    datei_schreiben /var/lib/zenos/netzwerk-erststart 0644 root:root
}
