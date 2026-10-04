#!/usr/bin/env bash
# shellcheck shell=bash
# aufraeumen.sh – gemeinsame Teile für das Entfernen von snapd und landscape-common (scripts/module/22-aufraeumen.sh)
# und die Prüfung in «zen doctor» (scripts/doctor.d/70-sicherheit.sh).
#
# Beim Sourcen passiert nichts ausser Konstanten und Funktionen. Die Funktionen lesen nur stdin und Argumente,
# fassen das System nicht an und laufen auch mit bash 3.2 (Einheitentest auf dem Mac).
#
#   _AUFRAEUMEN_PIN                       Pin-Datei, die snapd von apt fernhält
#   _AUFRAEUMEN_ZIELE                     Pakete, die zenOS entfernt (snapd, landscape-common)
#   _aufraeumen_snap_liste                Namen aus der Ausgabe von «snap list» (stdin)
#   _aufraeumen_state_liste               Namen aus /var/lib/snapd/state.json (stdin); Exit 1 bei ungültigem JSON
#   _aufraeumen_snap_dateien              Namen aus Dateinamen unter /var/lib/snapd/snaps (stdin, je Zeile einer)
#   _aufraeumen_eigene                    Snaps ausser dem Grundbestand (stdin: Namen), sortiert und ohne Doppelte
#   _aufraeumen_geschuetzt                Ubuntu-Pakete, die beim Entfernen nie mitgehen dürfen
#   _aufraeumen_simulation_pruefen SIM QUELLEN GESCHUETZT ZIEL…
#                                         prüft die Ausgabe von «apt-get -s purge ZIEL…» (siehe dort)
#   _aufraeumen_liste NAME…               «a, b, c»
#
# Grundbestand sind die Snaps, die snapd selbst mitbringt oder nachlädt, ohne dass jemand etwas installiert:
# snapd, core und core<NN> (Basis-Snaps) sowie bare. Das Raspi-Image von Ubuntu 26.04 hat nur den Seed snapd
# (/var/lib/snapd/seed/seed.yaml). Alles andere zählt als eigener Snap, auch ein Snap mit Instanzschlüssel
# (core22_test) oder ein weiterer Seed: Ob er je benutzt wurde, lässt sich nicht verlässlich sagen.

# shellcheck disable=SC2034  # gelesen vom Modul und von zen doctor
_AUFRAEUMEN_PIN=/etc/apt/preferences.d/zenos-ohne-snapd
# shellcheck disable=SC2034
_AUFRAEUMEN_ZIELE=(snapd landscape-common)

# Snap-Namen: Kleinbuchstaben, Ziffern und Bindestriche, dazu optional ein Instanzschlüssel nach «_»
_aufraeumen_snap_liste() {
  awk '
    !kopf { if ($1 == "Name") kopf = 1; next }
    $1 ~ /^[a-z0-9][a-z0-9-]*(_[a-z0-9]+)?$/ { print $1 }
  ' | LC_ALL=C sort -u
}

# state.json von snapd: Die installierten Snaps stehen als Schlüssel unter data.snaps (fehlt der Schlüssel, ist
# keiner installiert). Liest nur, was eine Liste von Namen ergibt; alles andere gilt als ungültig (Exit 1).
_aufraeumen_state_liste() {
  python3 -c '
import json, sys
try:
    daten = json.load(sys.stdin)
    snaps = (daten.get("data") or {}).get("snaps") or {}
    if not isinstance(snaps, dict):
        raise ValueError
except (ValueError, AttributeError):
    sys.exit(1)
for name in sorted(snaps):
    print(name)
'
}

# /var/lib/snapd/snaps/<name>[_<schlüssel>]_<revision>.snap; lokale Revisionen heissen x1, x2 …
_aufraeumen_snap_dateien() {
  sed -n 's/^\([a-z0-9][a-z0-9_-]*\)_x\{0,1\}[0-9][0-9]*\.snap$/\1/p' | LC_ALL=C sort -u
}

# Nie mit grep: Ohne Treffer endete es mit Exit 1, und install.sh (pipefail, ERR-Trap) bräche ab.
_aufraeumen_eigene() {
  awk 'NF && $1 !~ /^(snapd|core|core[0-9]+|bare)$/ { print $1 }' | LC_ALL=C sort -u
}

# Was nie mitgehen darf, auch wenn apt es wollte (Bauplan «NICHT entfernen»). Die zenOS-Pakete aus
# scripts/pakete/*.txt kommen im Modul dazu.
_aufraeumen_geschuetzt() {
  printf '%s\n' ubuntu-minimal ubuntu-standard ubuntu-server ubuntu-server-raspi ubuntu-pro-client \
    lsb-release distro-info-data python3-distro-info update-notifier-common ubuntu-release-upgrader-core \
    motd-news-config apport fonts-ubuntu-console lxd-installer ubuntu-keyring base-files
}

# _aufraeumen_simulation_pruefen SIM QUELLEN GESCHUETZT ZIEL…
#   SIM        Ausgabe von «LC_ALL=C apt-get -s purge ZIEL…» (Zeilen «Purg NAME …», «Remv …», «Inst …»)
#   QUELLEN    je installiertem Paket eine Zeile «PAKET QUELLPAKET» (dpkg-query ${Package} ${source:Package})
#   GESCHUETZT je Zeile ein Paket, das nie gehen darf
# Erlaubt ist nur, was ein Ziel ist oder aus demselben Quellpaket stammt wie ein Ziel («eigene Teile», etwa
# landscape-client neben landscape-common). Druckt sortiert, was nicht stimmt: «mehr: PAKET» (ginge mit, ohne
# erlaubt zu sein), «geschuetzt: PAKET», «installiert: PAKET» (apt wollte etwas installieren) und «fehlt: ZIEL»
# (apt entfernte ein Ziel nicht). Exit 0 nur, wenn nichts davon zutrifft. Architektur-Zusätze («:arm64») zählen nicht.
_aufraeumen_simulation_pruefen() {
  local sim=$1 quellen=$2 geschuetzt=$3 ausgabe rc=0
  shift 3
  ausgabe=$(awk -v ziele="$*" -v datei_quellen="$quellen" -v datei_schutz="$geschuetzt" '
    function name(p) { sub(/:.*/, "", p); return p }
    BEGIN {
      n = split(ziele, z, " ")
      for (i = 1; i <= n; i++) ziel[z[i]] = 1
      while ((getline zeile < datei_quellen) > 0) {
        if (split(zeile, f, " ") >= 2) quelle[name(f[1])] = f[2]
      }
      while ((getline zeile < datei_schutz) > 0) {
        sub(/#.*/, "", zeile)
        if (split(zeile, f, " ") >= 1) schutz[name(f[1])] = 1
      }
    }
    $1 == "Purg" || $1 == "Remv" { weg[name($2)] = 1; next }
    $1 == "Inst" { neu[name($2)] = 1; next }
    END {
      for (p in ziel) if (p in quelle) eigen[quelle[p]] = 1
      fehler = 0
      for (p in ziel) if (!(p in weg)) { print "fehlt: " p; fehler = 1 }
      for (p in weg) {
        if (p in schutz) { print "geschuetzt: " p; fehler = 1 }
        else if (!(p in ziel) && !((p in quelle) && (quelle[p] in eigen))) { print "mehr: " p; fehler = 1 }
      }
      for (p in neu) { print "installiert: " p; fehler = 1 }
      exit fehler
    }' "$sim") || rc=$?
  if [[ -n "$ausgabe" ]]; then printf '%s\n' "$ausgabe" | LC_ALL=C sort; fi
  return "$rc"
}

_aufraeumen_liste() { # NAME… → «a, b, c»
  local IFS=,
  local text="$*"
  printf '%s' "${text//,/, }"
}
