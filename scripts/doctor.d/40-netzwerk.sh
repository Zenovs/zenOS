#!/usr/bin/env bash
# 40-netzwerk: Netz-Stack fürs WLAN-Menü: NetworkManager umgestellt oder nicht, wait-online, WPA3 im WLAN-Treiber,
# Rechte der Sitzung (polkit), Konnektivitätsprüfung von Ubuntu
# shellcheck shell=bash
#
# Ausgegeben werden nur Zustände und Anzahlen, nie WLAN-Namen, Adressen oder Passwörter.

pruefe_netzwerk() {
  abschnitt "Netz"
  if ! paket_installiert network-manager; then
    warnung "NetworkManager fehlt; das WLAN-Menü oben rechts braucht ihn (zen update installiert ihn)"
    return 0
  fi
  if paket_installiert network-manager-config-connectivity-ubuntu; then
    warnung "Ubuntus Konnektivitätsprüfung ist installiert: NetworkManager fragt regelmässig bei connectivity-check.ubuntu.com nach (sudo apt purge network-manager-config-connectivity-ubuntu)"
  fi
  if [[ -e /etc/netplan/90-zenos-netzwerk.yaml ]]; then
    _netzwerk_umgestellt
  else
    _netzwerk_vorher
  fi
  _netzwerk_wpa3
}

_netzwerk_zustand() { systemctl is-active "$1" 2> /dev/null || true; }
_netzwerk_an() { systemctl is-enabled "$1" 2> /dev/null || true; }

# Start des Systems in Unix-Sekunden
_netzwerk_hochgefahren() { awk '$1 == "btime" { print $2; exit }' /proc/stat 2> /dev/null; }

_netzwerk_umgestellt() {
  local seit start anzahl offen datei ergebnis bedingung
  seit=$(stat -c %Y /etc/netplan/90-zenos-netzwerk.yaml 2> /dev/null || echo 0)
  start=$(_netzwerk_hochgefahren)
  if [[ "$(_netzwerk_zustand NetworkManager.service)" == active ]]; then
    ok "NetworkManager verwaltet das Netz (WLAN-Menü oben rechts)"
  elif [[ "$start" =~ ^[0-9]+$ ]] && (( seit > start )); then
    hinweis "Umgestellt, wirksam nach dem Neustart (sudo reboot)"
  else
    fehler "Umgestellt, aber NetworkManager läuft nicht (systemctl status NetworkManager; Rückweg: zen netzwerk zurueck)"
  fi
  if [[ "$(_netzwerk_an NetworkManager.service)" != enabled ]]; then
    warnung "NetworkManager ist nicht aktiviert und startet beim nächsten Mal nicht (install.sh holt es nach)"
  fi

  anzahl=$(find /etc/netplan -maxdepth 1 -name '90-NM-*.yaml' 2> /dev/null | wc -l)
  ok "$anzahl WLAN-Profile von NetworkManager unter /etc/netplan"
  offen=$(find /etc/netplan -maxdepth 1 -name '*.yaml' ! -perm 600 2> /dev/null | wc -l)
  if (( offen > 0 )); then
    warnung "$offen Dateien unter /etc/netplan sind nicht nur für root lesbar (sudo chmod 600 /etc/netplan/*.yaml)"
  fi

  if [[ -f /etc/xdg/zenos/wlan-land ]]; then
    ergebnis=$(systemctl show -p Result --value zenos-wlan-land.service 2> /dev/null || true)
    bedingung=$(systemctl show -p ConditionResult --value zenos-wlan-land.service 2> /dev/null || true)
    if [[ "$(_netzwerk_an zenos-wlan-land.service)" != enabled ]]; then
      warnung "WLAN-Land eingetragen, aber zenos-wlan-land.service ist nicht aktiviert (install.sh)"
    elif [[ "$bedingung" == no ]]; then
      hinweis "WLAN-Land nicht gesetzt: beim Start war kein WLAN-Treiber geladen"
    elif [[ "$ergebnis" == success && "$(_netzwerk_zustand zenos-wlan-land.service)" == active ]]; then
      ok "WLAN-Land gesetzt (zenos-wlan-land)"
    elif [[ "$ergebnis" == success ]]; then
      hinweis "WLAN-Land wird beim nächsten Start gesetzt (zenos-wlan-land)"
    else
      warnung "zenos-wlan-land.service meldet «${ergebnis:-unbekannt}» (journalctl -b -u zenos-wlan-land)"
    fi
  fi

  datei=/etc/systemd/system/systemd-networkd-wait-online.service.d/zenos-netzwerk.conf
  if [[ ! -f "$datei" ]]; then
    warnung "systemd-networkd-wait-online wird nicht übersprungen und wartet beim Start bis zu 2 Minuten (install.sh legt $datei ab)"
  elif [[ "$(_netzwerk_zustand systemd-networkd-wait-online.service)" == failed ]]; then
    warnung "systemd-networkd-wait-online ist gescheitert (Neustart nach der Umstellung ausstehend?)"
  else
    ok "systemd-networkd-wait-online bremst den Start nicht"
  fi
  if [[ "$(_netzwerk_zustand NetworkManager-wait-online.service)" == failed ]]; then
    warnung "NetworkManager-wait-online ist gescheitert: beim Start kam keine Verbindung zustande"
  fi
  _netzwerk_sitzung
}

_netzwerk_vorher() {
  hinweis "Netz über netplan mit systemd-networkd; das WLAN-Menü kommt mit «zen netzwerk umstellen»"
  if [[ "$(_netzwerk_zustand NetworkManager.service)" == active ]]; then
    hinweis "NetworkManager läuft, ohne dass zenOS umgestellt hat"
  elif [[ "$(_netzwerk_an NetworkManager-wait-online.service)" == enabled ]]; then
    warnung "NetworkManager-wait-online ist aktiviert, NetworkManager aber aus: Das bremst den Start (install.sh schaltet es ab)"
  fi
}

# polkit erlaubt Verbinden und Vergessen ohne Passwort nur einer lokalen, aktiven Sitzung. Für die Oberfläche
# (Benutzerdienst) nimmt polkit die «Display»-Sitzung des Benutzers; die muss die grafische sein, nicht SSH.
_netzwerk_sitzung() {
  local benutzer sitzung typ entfernt aktiv s grafisch=0
  benutzer=$(id -un)
  sitzung=$(loginctl show-user "$benutzer" -p Display --value 2> /dev/null || true)
  if [[ -n "$sitzung" ]]; then
    typ=$(loginctl show-session "$sitzung" -p Type --value 2> /dev/null || true)
    entfernt=$(loginctl show-session "$sitzung" -p Remote --value 2> /dev/null || true)
    aktiv=$(loginctl show-session "$sitzung" -p Active --value 2> /dev/null || true)
    if [[ "$typ" == wayland && "$entfernt" == no && "$aktiv" == yes ]]; then
      ok "Sitzung am Gerät ist lokal und aktiv: Das WLAN-Menü darf verbinden und vergessen"
      return 0
    elif [[ "$typ" == wayland && "$entfernt" == no ]]; then
      hinweis "Sitzung am Gerät ist gerade nicht aktiv; das WLAN-Menü darf erst wieder verbinden, wenn sie es ist"
      return 0
    fi
  fi
  # Massgeblich ist keine grafische Sitzung: Gibt es trotzdem eine, lehnt polkit Verbinden im Menü ab
  for s in $(loginctl show-user "$benutzer" -p Sessions --value 2> /dev/null || true); do
    [[ "$(loginctl show-session "$s" -p Type --value 2> /dev/null || true)" == wayland ]] && grafisch=1
  done
  if (( grafisch )); then
    warnung "polkit sieht nicht die Sitzung am Gerät, sondern «${typ:-?}»: Verbinden im WLAN-Menü wird abgelehnt (abmelden und am Gerät neu anmelden)"
  else
    hinweis "Keine Sitzung am Gerät angemeldet; die Rechte fürs WLAN-Menü gelten erst mit der Anmeldung dort"
  fi
}

# WPA3 im WLAN-Treiber brcmfmac (Raspberry Pi, Compute Module): Unter NetworkManager muss es aus sein, sonst scheitern
# WPA2/WPA3-Mischnetze. «iw phy» meldet «SAE with AUTHENTICATE», solange der Treiber WPA3 anbietet.
_netzwerk_wpa3() {
  [[ -d /sys/module/brcmfmac ]] || return 0
  local iw="" sae=""
  if command -v iw > /dev/null 2>&1; then iw=$(command -v iw); elif [[ -x /usr/sbin/iw ]]; then iw=/usr/sbin/iw; fi
  if [[ -n "$iw" ]]; then
    if "$iw" phy 2> /dev/null | grep -q 'SAE with AUTHENTICATE'; then sae=ja; else sae=nein; fi
  fi
  if [[ -e /etc/netplan/90-zenos-netzwerk.yaml ]]; then
    if [[ "$sae" == ja && -f /etc/modprobe.d/zenos-brcmfmac.conf ]]; then
      warnung "WLAN-Treiber meldet noch WPA3, obwohl die Option liegt (Neustart ausstehend? Treiber im initramfs?)"
    elif [[ "$sae" == ja ]]; then
      warnung "WLAN-Treiber meldet WPA3: WPA2/WPA3-Mischnetze scheitern unter NetworkManager (/etc/modprobe.d/zenos-brcmfmac.conf fehlt)"
    elif [[ "$sae" == nein ]]; then
      ok "WPA3 im WLAN-Treiber aus: Mischnetze verbinden über WPA2"
    fi
  elif [[ -f /etc/modprobe.d/zenos-brcmfmac.conf ]]; then
    hinweis "WPA3 im WLAN-Treiber ist aus (/etc/modprobe.d/zenos-brcmfmac.conf)"
  fi
}
