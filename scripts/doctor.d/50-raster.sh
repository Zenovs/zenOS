#!/usr/bin/env bash
# 50-raster: labwc-Konfiguration (Raster, Tastenkürzel), Bildschirm-Profile (kanshi)
# Ohne Inhalte: keine Raster- oder Profilnamen, keine Ausgänge (Anzahl und Gültigkeit prüft 55-konfig).
# shellcheck shell=bash

pruefe_raster() {
  abschnitt "Raster und Bildschirme"
  local bin=/opt/zenos/scripts/bin rc
  local labwc_rc="$HOME/.config/labwc/rc.xml" kanshi_conf="$HOME/.config/kanshi/config"

  if [[ ! -x "$bin/zenos-labwc" || ! -x "$bin/zenos-kanshi" ]]; then
    fehler "zenos-labwc oder zenos-kanshi fehlt unter /opt/zenos/scripts/bin"
    return 0
  fi

  # labwc: rc.xml von zenOS, aktuell und gültig?
  if [[ ! -f "$labwc_rc" ]]; then
    fehler "$labwc_rc fehlt – Raster und Tastenkürzel fehlen (zen benutzer)"
  elif ! grep -q "Erzeugt von zenos-labwc" "$labwc_rc" 2>/dev/null; then
    warnung "$labwc_rc stammt nicht von zenOS (zen benutzer sichert sie und schreibt sie neu)"
  else
    rc=0
    "$bin/zenos-labwc" --pruefen >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0) ok "labwc-Konfiguration aktuell (Raster, Tastenkürzel)" ;;
      1) warnung "labwc-Konfiguration nicht aktuell oder aktives Raster ungültig (zenos-labwc schreibt sie neu)" ;;
      *) fehler "zenos-labwc kann die labwc-Konfiguration nicht erzeugen (Exit $rc)" ;;
    esac
    if python3 -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$labwc_rc" 2>/dev/null; then
      ok "rc.xml ist gültiges XML"
    else
      fehler "$labwc_rc ist kein gültiges XML – labwc lädt dann Vorgaben"
    fi
  fi
  if [[ -L "$HOME/.config/labwc/menu.xml" && "$(readlink -- "$HOME/.config/labwc/menu.xml")" == /opt/zenos/system/labwc/menu.xml ]]; then
    ok "labwc-Menü verknüpft"
  else
    warnung "$HOME/.config/labwc/menu.xml zeigt nicht auf /opt/zenos/system/labwc/menu.xml (zen benutzer)"
  fi

  # kanshi: Paket, Konfiguration, Dienst
  if ! command -v kanshi >/dev/null 2>&1; then
    fehler "kanshi fehlt – Bildschirm-Profile wirken nicht (install.sh)"
  fi
  if [[ ! -f /etc/systemd/user/zenos-kanshi.service ]]; then
    fehler "zenos-kanshi.service fehlt unter /etc/systemd/user (install.sh)"
  elif ! cmp -s /etc/systemd/user/zenos-kanshi.service /opt/zenos/system/systemd/user/zenos-kanshi.service; then
    warnung "zenos-kanshi.service weicht von zenOS ab (install.sh stellt ihn wieder her)"
  fi
  if [[ ! -f "$kanshi_conf" ]]; then
    fehler "$kanshi_conf fehlt (zen benutzer)"
  else
    rc=0
    "$bin/zenos-kanshi" --pruefen >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0) ok "kanshi-Konfiguration aktuell" ;;
      1) warnung "kanshi-Konfiguration nicht aktuell oder bildschirme.json ungültig (Details lokal: zenos-kanshi --pruefen)" ;;
      *) fehler "zenos-kanshi kann die kanshi-Konfiguration nicht erzeugen (Exit $rc)" ;;
    esac
  fi

  # Nur in einer laufenden Sitzung: Dienst aktiv?
  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  if [[ -S "$laufzeit/bus" ]] &&
    XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-sitzung.target 2>/dev/null; then
    if XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-kanshi.service 2>/dev/null; then
      ok "zenos-kanshi.service läuft"
    else
      warnung "zenos-kanshi.service läuft nicht (systemctl --user status zenos-kanshi)"
    fi
  else
    hinweis "Keine laufende Sitzung – kanshi wird beim Anmelden gestartet"
  fi
}
