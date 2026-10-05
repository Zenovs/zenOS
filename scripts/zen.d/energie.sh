#!/usr/bin/env bash
# hilfe: energie [status|aus] – Energie: Zeiten zeigen oder sofort sperren und den Bildschirm ausschalten
# «status» (Standard) zeigt ohne sudo, was ohne Eingabe geschieht: wann gesperrt wird, wann der Bildschirm ausgeht und
# ob zenOS nach langer Sperre ausschaltet (aus ~/.config/zenos/einstellungen.json, begrenzt durch die Leitplanken),
# was das Ausschalten gerade aufhält (SSH, tmux, Updates …), die Ein/Aus-Taste, den Bildschirm in der laufenden Sitzung
# und ob der Kernel Bereitschaft anbietet.
# «aus» sperrt sofort (zen lock) und schaltet danach den Bildschirm aus, auch per SSH. Eine Eingabe am Gerät weckt
# ihn wieder, die Sperre bleibt. Dasselbe wie Super+Shift+L und «Bildschirm aus» im System-Menü.
# Leitplanke: Der Bildschirm geht nie ungesperrt aus. Schlägt die Sperre fehl, bleibt er an.
# Exit 0 erledigt · 1 fehlgeschlagen · 2 falscher Aufruf · 3 keine grafische Sitzung
# shellcheck shell=bash

# Gespiegelt aus shell/modi/zustandslogik.js (LEITPLANKEN.sperreTrotzHemmerMinuten, test/einheiten/zen-energie.test.py
# gleicht ab): So lange hält ein Idle-Hemmer (Video) die automatische Sperre höchstens auf.
_ENERGIE_HEMMER_MINUTEN=60
# Sekunden zwischen Sperre und «Bildschirm aus»: Das Loslassen von Super+Shift+L (oder der Maustaste) zählt sonst
# schon als Eingabe und weckt den Bildschirm gleich wieder. ZENOS_ENERGIE_PAUSE nur für die Einheitentests (0–5).
_ENERGIE_PAUSE=1
if [[ "${ZENOS_ENERGIE_PAUSE:-}" =~ ^[0-5]$ ]]; then _ENERGIE_PAUSE=$ZENOS_ENERGIE_PAUSE; fi

befehl_energie() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen energie [status|aus])"
    return 2
  fi
  case "${1:-status}" in
    status) _energie_status ;;
    aus) _energie_aus ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, aus)"
      return 2
      ;;
  esac
}

# Umgebung der Sitzung, auch per SSH (wie zen lock): Laufzeitordner und Sitzungsbus der Benutzerinstanz
_energie_umgebung() {
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$EUID}
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$XDG_RUNTIME_DIR/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  fi
}

_energie_status() {
  _energie_umgebung
  local idle=$ZEN_SKRIPTE/bin/zenos-idle name wert art
  local sperre=5 sperre_art=standard bildschirm=1 bildschirm_art=standard
  local aus_min=60 aus_min_art=standard aus_wenn=akku aus_wenn_art=standard taste=sperren taste_art=standard
  if [[ -x "$idle" ]]; then
    while read -r name wert art; do
      case "$name:$wert" in
        ausschaltenwenn:nie | ausschaltenwenn:akku | ausschaltenwenn:immer) aus_wenn=$wert aus_wenn_art=$art ;;
        taste:sperren | taste:menue | taste:ausschalten) taste=$wert taste_art=$art ;;
      esac
      [[ "$wert" =~ ^[0-9]+$ ]] || continue
      case "$name" in
        sperre) sperre=$wert sperre_art=$art ;;
        bildschirm) bildschirm=$wert bildschirm_art=$art ;;
        ausschalten) aus_min=$wert aus_min_art=$art ;;
      esac
    done < <("$idle" energie 2>/dev/null || true)
  else
    zen_fehler "$idle fehlt, es gelten die Standardwerte"
  fi

  printf 'Ohne Eingabe       gesperrt nach %s Min. · Bildschirm aus nach %s Min.\n' "$sperre" "$((sperre + bildschirm))"
  printf 'Sperre             %s Min. ohne Eingabe (Leitplanke: 1–15 Min., lässt sich nicht abschalten)%s\n' \
    "$sperre" "$(_energie_art_text "$sperre_art" 1 15)"
  printf 'Bildschirm aus     %s Min. nach der Sperre, nie ungesperrt%s\n' \
    "$bildschirm" "$(_energie_art_text "$bildschirm_art" 1 10)"
  printf 'Video              Ein Idle-Hemmer hält die Sperre höchstens %s Min. ohne Eingabe auf\n' "$_ENERGIE_HEMMER_MINUTEN"
  # Zwei Schlüssel (ausschalten, ausschaltenNachMinuten): ein Hinweis für beide
  local aus_art=einstellung
  if [[ "$aus_wenn_art" == ungueltig || "$aus_min_art" == ungueltig ]]; then
    aus_art=ungueltig
  elif [[ "$aus_min_art" == begrenzt ]]; then
    aus_art=begrenzt
  elif [[ "$aus_wenn_art" == standard && ( "$aus_min_art" == standard || "$aus_wenn" == nie ) ]]; then
    aus_art=standard
  fi
  printf 'Ausschalten        %s%s\n' "$(_energie_aus_text "$aus_wenn" "$aus_min")" "$(_energie_art_text "$aus_art" 30 240)"
  if [[ "$aus_wenn" != nie ]]; then
    printf 'Zurzeit            %s\n' "$(_energie_zurzeit)"
  fi
  printf 'Ein/Aus-Taste      %s%s\n' "$(_energie_taste_text "$taste")" "$(_energie_art_text "$taste_art" 0 0)"
  printf 'Bildschirm jetzt   %s\n' "$(_energie_bildschirm_jetzt)"
  printf 'Bereitschaft       %s\n' "$(_energie_bereitschaft)"
  printf '\nSofort sperren und Bildschirm aus: zen energie aus oder Super+Shift+L\n'
}

_energie_art_text() { # ART MIN MAX
  case "$1" in
    begrenzt) printf ' · Wert in einstellungen.json ausserhalb von %s–%s, begrenzt' "$2" "$3" ;;
    ungueltig) printf ' · Wert in einstellungen.json ungültig, es gilt der Standard' ;;
    standard) printf ' · Standard' ;;
  esac
}

_energie_aus_text() { # WENN MINUTEN
  case "$1" in
    nie) printf 'nie' ;;
    immer) printf 'nach %s Min. gesperrt, mit 60 s Vorwarnung' "$2" ;;
    *) printf 'nach %s Min. gesperrt im Akkubetrieb, mit 60 s Vorwarnung' "$2" ;;
  esac
}

_energie_taste_text() { # TASTE
  case "$1" in
    menue) printf 'System-Menü (gesperrt: Bildschirm an oder aus)' ;;
    ausschalten) printf 'ausschalten (logind)' ;;
    *) printf 'sperren und Bildschirm aus (gesperrt: Bildschirm an oder aus)' ;;
  esac
}

# Was das Ausschalten gerade aufhält (zenos-energie status, nur lesen)
_energie_zurzeit() {
  local helfer=$ZEN_SKRIPTE/bin/zenos-energie antwort
  if [[ ! -x "$helfer" ]]; then
    printf 'unbekannt (zenos-energie fehlt)'
    return 0
  fi
  antwort=$(timeout 20 "$helfer" status 2>/dev/null | tail -n 1) || true
  case "$antwort" in
    ja) printf 'möglich, nichts im Weg' ;;
    "nein: "*) printf 'nicht möglich: %s' "${antwort#nein: }" ;;
    *) printf 'unbekannt (zenos-energie status)' ;;
  esac
}

_energie_bildschirm_jetzt() {
  local helfer=$ZEN_SKRIPTE/bin/zenos-bildschirm status rc=0
  if [[ ! -x "$helfer" ]]; then
    printf 'unbekannt (zenos-bildschirm fehlt)'
    return 0
  fi
  status=$(timeout 10 "$helfer" status 2>/dev/null) || rc=$?
  case "$rc:$status" in
    0:an) printf 'an' ;;
    0:aus) printf 'aus' ;;
    0:teils) printf 'teils aus' ;;
    3:*) printf 'keine laufende Sitzung' ;;
    *) printf 'unbekannt (zenos-bildschirm status, Exit %s)' "$rc" ;;
  esac
}

# Bereitschaft (Suspend) nur als Anzeige: zenOS nutzt sie nicht
_energie_bereitschaft() {
  local zustaende
  zustaende=$(cat /sys/power/state 2>/dev/null) || zustaende=""
  if [[ " $zustaende " == *" mem "* || " $zustaende " == *" freeze "* ]]; then
    printf 'Der Kernel bietet sie an (%s), zenOS nutzt sie noch nicht' "$zustaende"
  else
    printf 'auf diesem Gerät nicht verfügbar (der Kernel bietet keinen Schlafzustand an)'
  fi
}

# Läuft zenos-idle mit einem swayidle, das den Bildschirm ausschalten kann? Dann weckt dessen resume ihn wieder.
_energie_swayidle_bereit() {
  local pid
  systemctl --user --quiet is-active zenos-idle.service 2>/dev/null || return 1
  pid=$(systemctl --user show -p MainPID --value zenos-idle.service 2>/dev/null) || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  pgrep -u "$EUID" -P "$pid" -f '(^|/)swayidle .*/zenos-bildschirm aus' >/dev/null 2>&1
}

_energie_aus() {
  if (( EUID == 0 )); then
    zen_fehler "zen energie aus läuft als normaler Benutzer, nicht als root"
    return 2
  fi
  _energie_umgebung
  local bildschirm=$ZEN_SKRIPTE/bin/zenos-bildschirm rc=0

  # Erst sperren, und zwar sofort. Ohne bestätigte Sperre bleibt der Bildschirm an (dunkel heisst gesperrt).
  "$ZEN_SKRIPTE/zen" lock || rc=$?
  if (( rc != 0 )); then
    zen_fehler "nicht gesperrt, der Bildschirm bleibt an"
    return "$rc"
  fi
  sleep "$_ENERGIE_PAUSE"

  # Über zenos-idle: SIGUSR1 löst die Timeouts von swayidle sofort aus (sperren, dann Bildschirm aus), die nächste
  # Eingabe weckt ihn über resume. Nur der Hauptprozess (zenos-idle) bekommt das Signal und reicht es weiter.
  if _energie_swayidle_bereit &&
    systemctl --user kill --kill-whom=main --signal=USR1 zenos-idle.service 2>/dev/null; then
    printf 'Bildschirm aus. Eine Eingabe weckt ihn, die Sperre bleibt.\n'
    return 0
  fi

  # Sonst direkt. Geweckt wird dann über die Sperre der Oberfläche (Eingabe bei dunklem Bildschirm).
  if [[ ! -x "$bildschirm" ]]; then
    zen_fehler "$bildschirm fehlt: gesperrt, der Bildschirm bleibt an"
    return 1
  fi
  rc=0
  "$bildschirm" aus || rc=$?
  if (( rc != 0 )); then
    zen_fehler "Bildschirm aus fehlgeschlagen (zenos-bildschirm, Exit $rc): gesperrt, der Bildschirm bleibt an"
    return "$rc"
  fi
  printf 'Bildschirm aus. Eine Taste weckt ihn, die Sperre bleibt.\n'
}
