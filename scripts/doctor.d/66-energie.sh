#!/usr/bin/env bash
# 66-energie: Energie – wlopm und zenos-bildschirm, Bildschirm aus nach der Sperre (wirksame Zeit), Bildschirm
# in der laufenden Sitzung erreichbar, Stand von zenos-idle, Ausschalten nach langer Sperre (Einstellung und was
# gerade im Weg ist) und am Login-Bildschirm, Hemmer und Tastenkürzel für die Ein/Aus-Taste, Bereitschaft des
# Kernels (nur Anzeige)
# shellcheck shell=bash
#
# Liest nur: zenos-idle energie (wirksame Werte, keine Inhalte aus einstellungen.json), zenos-bildschirm status,
# zenos-energie status, ob /run/zenos/geraet.json einen Akku meldet, die Hemmer von logind (busctl),
# ~/.config/labwc/rc.xml und /sys/power/state.

# Nur für die Einheitentests (test/einheiten/energie-modul.test.py): legt /opt/zenos und /run/zenos darunter
_energie_wurzel=${ZENOS_DOCTOR_TESTWURZEL:-}
_energie_wurzel=${_energie_wurzel%/}
_energie_bin=$_energie_wurzel/opt/zenos/scripts/bin
_energie_geraet=$_energie_wurzel/run/zenos/geraet.json

pruefe_energie() {
  abschnitt "Energie"
  _energie_werkzeuge
  _energie_zeit
  _energie_sitzung
  _energie_ausschalten
  _energie_login
  _energie_taste
  _energie_bereitschaft
}

# Wert NAME aus «zenos-idle energie» (leer, wenn nicht lesbar)
_energie_wert() {
  local name wert
  while read -r name wert _; do
    if [[ "$name" == "$1" ]]; then
      printf '%s' "$wert"
      return 0
    fi
  done < <("$_energie_bin/zenos-idle" energie 2>/dev/null)
}

_energie_werkzeuge() {
  local helfer=$_energie_bin/zenos-bildschirm
  if [[ ! -x "$helfer" ]]; then
    fehler "$helfer fehlt (zen update oder install.sh)"
  fi
  if command -v wlopm >/dev/null 2>&1; then
    ok "wlopm installiert (Bildschirm aus nach der Sperre)"
  else
    warnung "wlopm fehlt – gesperrt wird weiter, aber der Bildschirm bleibt an (sudo apt install wlopm)"
  fi
}

# Wirksame Zeiten aus zenos-idle: Bildschirm aus B Min. nach der Sperre, also nach S+B Min. ohne Eingabe
_energie_zeit() {
  local idle=$_energie_bin/zenos-idle name wert art sperre="" bildschirm="" bildschirm_art=""
  if [[ ! -x "$idle" ]]; then
    fehler "$idle fehlt"
    return 0
  fi
  while read -r name wert art; do
    case "$name" in
      sperre) sperre=$wert ;;
      bildschirm) bildschirm=$wert bildschirm_art=$art ;;
    esac
  done < <("$idle" energie 2>/dev/null)
  if [[ ! "$bildschirm" =~ ^[0-9]+$ ]] || (( bildschirm < 1 || bildschirm > 10 )) || [[ ! "$sperre" =~ ^[0-9]+$ ]]; then
    fehler "Zeit für «Bildschirm aus» nicht ermittelbar (zenos-idle energie)"
    return 0
  fi
  local text="Bildschirm aus $bildschirm Min. nach der Sperre, also nach $((sperre + bildschirm)) Min. ohne Eingabe"
  case "$bildschirm_art" in
    standard) ok "$text (Standard)" ;;
    einstellung) ok "$text" ;;
    begrenzt) warnung "bildschirmAusNachSperre liegt ausserhalb von 1–10, wirksam: $text" ;;
    *) warnung "bildschirmAusNachSperre ist keine Zahl oder einstellungen.json ist ungültig, wirksam: $text" ;;
  esac
}

# In einer laufenden Sitzung: Erreicht wlopm die Bildschirme, und läuft zenos-idle mit dem aktuellen Stand?
_energie_sitzung() {
  local laufzeit einheit=zenos-idle.service start code datei status
  local -a sc
  laufzeit=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  sc=(env "XDG_RUNTIME_DIR=$laufzeit" systemctl --user)
  if [[ ! -S "$laufzeit/bus" ]] || ! "${sc[@]}" --quiet is-active zenos-sitzung.target 2>/dev/null; then
    hinweis "Keine laufende zenOS-Sitzung, Bildschirm-Steuerung erst nach der Anmeldung prüfbar"
    return 0
  fi
  if command -v wlopm >/dev/null 2>&1 && [[ -x "$_energie_bin/zenos-bildschirm" ]]; then
    if status=$(XDG_RUNTIME_DIR=$laufzeit timeout 10 "$_energie_bin/zenos-bildschirm" status 2>/dev/null); then
      ok "Bildschirm-Steuerung in der Sitzung erreichbar (Bildschirm ${status})"
    else
      warnung "wlopm erreicht die Bildschirme der Sitzung nicht – der Bildschirm bliebe an (zenos-bildschirm status)"
    fi
  fi
  "${sc[@]}" --quiet is-active "$einheit" 2>/dev/null || return 0
  start=$("${sc[@]}" show --timestamp=unix -p ExecMainStartTimestamp --value "$einheit" 2>/dev/null)
  start=${start#@}
  [[ "$start" =~ ^[0-9]+$ ]] || return 0
  for datei in "$_energie_bin/zenos-idle" "$_energie_bin/zenos-bildschirm"; do
    code=$(stat -c %Y -- "$datei" 2>/dev/null) || continue
    if [[ "$code" =~ ^[0-9]+$ ]] && (( code > start )); then
      hinweis "zenos-idle läuft mit einem älteren Stand und übernimmt den neuen bei der nächsten Sperre (ein Stand von vor der Bildschirm-Abschaltung erst nach dem nächsten Anmelden)"
      return 0
    fi
  done
}

# Meldet zenos-argon einen Akku? (/run/zenos/geraet.json, «akku.vorhanden», unabhängig vom Alter der Datei)
_energie_akku_da() {
  python3 - "$_energie_geraet" <<'PY' 2>/dev/null
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        akku = json.load(f).get("akku")
except (OSError, ValueError, AttributeError):
    sys.exit(1)
sys.exit(0 if isinstance(akku, dict) and akku.get("vorhanden") is True else 1)
PY
}

# Ausschalten nach langer Sperre: Einstellung und was gerade im Weg ist (zenos-energie status, ohne Journal)
_energie_ausschalten() {
  local helfer=$_energie_bin/zenos-energie wenn minuten antwort
  if [[ ! -x "$helfer" ]]; then
    fehler "$helfer fehlt (zen update oder install.sh)"
    return 0
  fi
  wenn=$(_energie_wert ausschaltenwenn)
  minuten=$(_energie_wert ausschalten)
  case "$wenn" in
    nie)
      hinweis "Ausschalten nach langer Sperre: nie (Einstellung)"
      return 0
      ;;
    akku)
      if ! _energie_akku_da; then
        hinweis "Ausschalten nach ${minuten:-?} Min. gesperrt im Akkubetrieb: kein Akku erkannt, greift auf diesem Gerät nie"
        return 0
      fi
      ok "Ausschalten nach ${minuten:-?} Min. gesperrt im Akkubetrieb, mit 60 s Vorwarnung"
      ;;
    immer) ok "Ausschalten nach ${minuten:-?} Min. gesperrt, mit 60 s Vorwarnung" ;;
    *)
      fehler "Einstellung zum Ausschalten nicht ermittelbar (zenos-idle energie)"
      return 0
      ;;
  esac
  (( EUID != 0 )) || return 0
  antwort=$(timeout 20 "$helfer" status 2>/dev/null | tail -n 1) || true
  case "$antwort" in
    ja) ok "Ausschalten zurzeit möglich (nichts im Weg)" ;;
    "nein: "*) hinweis "Ausschalten zurzeit nicht möglich: ${antwort#nein: }" ;;
    *) warnung "Wächter für das Ausschalten nicht prüfbar (zenos-energie status)" ;;
  esac
}

# Am Login-Bildschirm (Zenos Entscheid, fest, unabhängig von der Einstellung): nur mit Akku
_energie_login() {
  _energie_akku_da || return 0
  ok "Am Login-Bildschirm im Akkubetrieb aus nach 30 Min. ohne Eingabe, mit 60 s Vorwarnung (fest)"
}

# Ein/Aus-Taste: Tastenkürzel in labwc und, in einer laufenden Sitzung, der Hemmer von zenOS bei logind
_energie_taste() {
  local taste rc_xml=$HOME/.config/labwc/rc.xml laufzeit liste
  taste=$(_energie_wert taste)
  if [[ "$taste" == ausschalten ]]; then
    hinweis "Ein/Aus-Taste: kurzer Druck schaltet aus (Einstellung)"
    return 0
  fi
  if [[ -f "$rc_xml" ]] && ! grep -q 'key="XF86PowerOff"' "$rc_xml" 2>/dev/null; then
    warnung "labwc kennt die Ein/Aus-Taste nicht (~/.config/labwc/rc.xml ohne XF86PowerOff, install.sh)"
  fi
  laufzeit=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  if [[ ! -S "$laufzeit/bus" ]] || ! env "XDG_RUNTIME_DIR=$laufzeit" systemctl --user --quiet is-active zenos-idle.service 2>/dev/null; then
    hinweis "Ein/Aus-Taste: Hemmer erst in einer laufenden Sitzung prüfbar"
    return 0
  fi
  if ! liste=$(timeout 10 busctl --system --json=short call org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager ListInhibitors 2>/dev/null); then
    warnung "Hemmer von logind nicht lesbar (busctl)"
    return 0
  fi
  if python3 -c '
import json, os, sys
for was, wer, _, modus, uid, _ in json.loads(sys.argv[1])["data"][0]:
    if wer == "zenOS" and modus == "block" and uid == os.getuid() and "handle-power-key" in was.split(":"):
        sys.exit(0)
sys.exit(1)
' "$liste" 2>/dev/null; then
    ok "Ein/Aus-Taste: kurzer Druck sperrt bzw. schaltet den Bildschirm (Hemmer von zenOS aktiv)"
  else
    warnung "Ein/Aus-Taste: kein Hemmer von zenOS, kurzer Druck schaltet aus (journalctl --user -u zenos-idle)"
  fi
}

# Bereitschaft (Suspend) gibt es nur, wenn der Kernel einen Schlafzustand anbietet. zenOS nutzt sie nicht.
_energie_bereitschaft() {
  local zustaende
  zustaende=$(cat /sys/power/state 2>/dev/null) || zustaende=""
  if [[ " $zustaende " == *" mem "* || " $zustaende " == *" freeze "* ]]; then
    hinweis "Der Kernel bietet Bereitschaft an ($zustaende), zenOS nutzt sie nicht und schaltet den Bildschirm aus"
  else
    hinweis "Bereitschaft auf diesem Gerät nicht verfügbar (Kernel ohne Schlafzustand), zenOS schaltet den Bildschirm aus"
  fi
}
