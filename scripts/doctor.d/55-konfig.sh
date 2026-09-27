#!/usr/bin/env bash
# 55-konfig: Modi, Zustände und übrige Konfiguration gültig? Bildschirmfreigabe eingerichtet?
# Ohne Inhalte: nur Anzahl und Gültigkeit, keine Dateinamen (sie enthalten Modusnamen).
# shellcheck shell=bash

pruefe_konfig() {
  abschnitt "Modi und Zustände"
  local konfig=/opt/zenos/scripts/bin/zenos-konfig bericht zeilen
  if [[ ! -x "$konfig" ]]; then
    fehler "zenos-konfig fehlt unter /opt/zenos/scripts/bin"
    return 0
  fi
  if ! python3 -c 'import jsonschema' 2>/dev/null; then
    fehler "python3-jsonschema fehlt – Einstellungen können nicht gespeichert werden (sudo apt install python3-jsonschema)"
    return 0
  fi
  if [[ ! -d "$HOME/.config/zenos" ]]; then
    warnung "Ordner ~/.config/zenos fehlt (zen benutzer)"
  else
    bericht=$("$konfig" pruefe --json 2>/dev/null)
    if [[ -z "$bericht" ]]; then
      fehler "zenos-konfig pruefe lieferte keinen Bericht"
    else
      zeilen=$(python3 -c '
import json, sys
b = json.load(sys.stdin)
a = b["arten"]
def n(art, eins, viele):
    k = a[art]["anzahl"]
    return f"{k} {eins if k == 1 else viele}"
print("ok\t" + " · ".join([n("modi", "Modus", "Modi"), n("zustaende", "Zustand", "Zustände"), n("raster", "Raster", "Raster")]))
for art, text in (("modi", "Modi"), ("zustaende", "Zustände"), ("raster", "Raster"), ("einstellungen", "einstellungen.json"),
                  ("bildschirme", "bildschirme.json"), ("webapps", "webapps.json"), ("laufzeit", "laufzeit.json")):
    u = a[art]["ungueltig"]
    if u:
        print(f"warnung\t{text}: {u} ungültig – Details lokal mit: zenos-konfig pruefe")
d = b["dateien"]
if b["ungueltig"] == 0 and d > 0:
    wort = "Konfigurationsdatei" if d == 1 else "Konfigurationsdateien"
    print(f"ok\t{d} {wort} gültig")
if a["zustaende"]["anzahl"] == 0:
    print("hinweis\tKeine Zustände angelegt (Einstellungen → Neuer Zustand)")
if a["modi"]["anzahl"] == 0:
    print("hinweis\tNoch kein Modus angelegt (Einstellungen → Neuer Modus)")
' <<< "$bericht" 2>/dev/null)
      if [[ -z "$zeilen" ]]; then
        fehler "Bericht von zenos-konfig nicht lesbar"
      fi
      local art text
      while IFS=$'\t' read -r art text; do
        case "$art" in
          ok) ok "$text" ;;
          warnung) warnung "$text" ;;
          hinweis) hinweis "$text" ;;
        esac
      done <<< "$zeilen"
    fi
  fi

  abschnitt "Bildschirmfreigabe"
  local conf=/etc/xdg/xdg-desktop-portal-wlr/config
  if [[ ! -f "$conf" ]]; then
    fehler "$conf fehlt – Sitzung startet nicht bei Bildschirmfreigabe (install.sh)"
  elif [[ -r /opt/zenos/system/portal/xdpw.conf ]] && ! cmp -s "$conf" /opt/zenos/system/portal/xdpw.conf; then
    warnung "$conf weicht von zenOS ab (install.sh stellt sie wieder her)"
  else
    ok "Portal-Konfiguration mit zenos-freigabe"
  fi
  if [[ -f "$HOME/.config/xdg-desktop-portal-wlr/config" ]]; then
    warnung "$HOME/.config/xdg-desktop-portal-wlr/config überdeckt die zenOS-Konfiguration (Sitzung startet dann nicht automatisch)"
  fi
  if command -v slurp >/dev/null 2>&1; then
    ok "slurp für die Wahl des Bildschirms"
  else
    fehler "slurp fehlt – Bildschirmfreigabe kann keinen Bildschirm wählen"
  fi
  if [[ -x /opt/zenos/scripts/bin/zenos-freigabe ]]; then
    if [[ "$(/opt/zenos/scripts/bin/zenos-freigabe status 2>/dev/null)" == aktiv* ]]; then
      hinweis "Bildschirm wird gerade geteilt"
    fi
  else
    fehler "zenos-freigabe fehlt"
  fi
}
