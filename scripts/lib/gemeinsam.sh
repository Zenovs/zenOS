#!/usr/bin/env bash
# shellcheck shell=bash
# gemeinsam.sh – Hilfsfunktionen für install.sh, die Module unter scripts/module/ und zen.
#
# Variablen (install.sh setzt sie; beim Sourcen von anderswo gelten die Standardwerte unten):
#   ZENOS_QUELLE    Wurzel des Repos, aus dem install.sh läuft
#   ZENOS_CODE      Ziel-Checkout /opt/zenos. Alle Symlinks und Dienste zeigen hierhin.
#   ZENOS_IMAGE     1 im --image-Modus, sonst 0
#   SUDO            «sudo» oder leer (als root). Aufruf: $SUDO befehl …
#   ZENOS_BENUTZER  Zielbenutzer, ZENOS_HOME dessen Home (beide leer im Image-Modus)
#   ZENOS_SYSTEMD   1, wenn systemd als PID 1 läuft, sonst 0 (chroot, Container ohne systemd)
#
# Funktionen (Vertrag, Bauplan Abschnitt 4):
#   log_schritt | log_info | log_warnung | log_fehler TEXT
#   abbruch TEXT                         Fehlermeldung, Exit 1
#   aenderung TEXT                       zählt eine Änderung, loggt «geändert: TEXT»
#   modul_geaendert                      wahr, wenn das laufende Modul schon etwas geändert hat
#   pakete_sicherstellen PAKET…          installiert nur fehlende Pakete (siehe unten)
#   datei_installieren QUELLE ZIEL [MODUS=0644] [BESITZER=root:root]
#                                        legt fehlende Elternordner an; Symlinks im Pfad bleiben erhalten
#   datei_schreiben ZIEL [MODUS=0644] [BESITZER=root:root]      Inhalt von stdin
#   benutzer_datei_schreiben ZIEL [MODUS=0644]                  Inhalt von stdin, als Benutzer
#   verknuepfen QUELLE ZIEL              Symlink als Benutzer
#   system_verknuepfen QUELLE ZIEL       Symlink als root
#   dienst_aktivieren EINHEIT            systemctl enable, nur wenn nötig (auch ohne laufendes systemd)
#   dienst_neustarten_falls EINHEIT      restart nur mit laufendem systemd, ohne --image und nur, wenn
#                                        das laufende Modul etwas geändert hat
#   systemd_neu_laden                    daemon-reload nur mit laufendem systemd und nur nach Änderungen
#                                        an Units (install.sh ruft es nach dem Systemdurchgang ohnehin auf)
#   befehl_vorhanden NAME
#   json_pruefen DATEI SCHEMA            0 gültig, 1 ungültig (Meldungen auf stderr), 2 technisches Problem
#
# Zusätzliche Hilfsfunktionen:
#   ordner_sicherstellen PFAD [MODUS=0755] [BESITZER=root:root]   als root; Modus und Besitzer werden erzwungen
#   benutzer_ordner_sicherstellen PFAD [MODUS]                    als Benutzer; Modus nur, wenn angegeben
#   datei_entfernen ZIEL                 als root; entfernt Datei oder Symlink, falls vorhanden
#   benutzer_datei_entfernen ZIEL        dasselbe als Benutzer
#   paket_installiert PAKET              wahr, wenn das Paket installiert ist
#   apt_quellen_geaendert                nach neuen Paketquellen: nächstes pakete_sicherstellen macht apt-get update
#   zenos_version [PFAD]                 «git describe --tags --always --dirty» des Checkouts (Standard ZENOS_CODE)
#   git_code ARG…                        lesendes git in ZENOS_CODE als Benutzer (safe.directory)
#   aufraeumen_bei_ende BEFEHL [ARG…]    führt den Befehl am Ende von install.sh aus (auch bei Abbruch);
#                                        nur externe Befehle, Modulfunktionen sind dann schon entfernt
#   zenos_anzahl aenderung|warnung       bisherige Anzahl in diesem Lauf
#
# Regeln:
#   - Jede echte Änderung läuft über diese Funktionen (oder ruft aenderung), damit der zweite Lauf
#     «0 Änderungen» meldet. Die Zähler liegen während install.sh in $ZENOS_TMP, deshalb zählen auch
#     Aufrufe aus Subshells mit (z. B. «printf … | datei_schreiben ZIEL»).
#   - Root-Funktionen (pakete_sicherstellen, datei_*, system_verknuepfen, ordner_sicherstellen,
#     dienst_*, systemd_neu_laden) sind nur in modul_system erlaubt, Benutzerfunktionen
#     (benutzer_*, verknuepfen) nur in modul_benutzer. Ein Verstoss bricht mit Meldung ab.
#   - Dienststarts durch apt: pakete_sicherstellen legt für die Dauer von apt-get ein
#     /usr/sbin/policy-rc.d mit «exit 101» an (Markierung in der zweiten Zeile). Damit starten
#     Pakete wie greetd ihre Dienste nicht sofort; aktiviert (enable) werden sie trotzdem.
#     Eine schon vorhandene fremde policy-rc.d bleibt unangetastet. Die Datei wird direkt nach
#     apt-get entfernt, spätestens beim Ende von install.sh (auch nach einem Abbruch), und eine
#     liegengebliebene eigene Datei aus einem abgestürzten Lauf räumt der nächste Lauf weg.
#     Module, die einen Dienst sofort brauchen, starten ihn mit dienst_neustarten_falls.
#   - apt-get läuft nicht-interaktiv (DEBIAN_FRONTEND=noninteractive, confdef/confold,
#     needrestart ausgesetzt) und wartet bis zu 5 Minuten auf die dpkg-Sperre.

# Standardwerte, falls die Datei ausserhalb von install.sh gesourct wird
: "${ZENOS_CODE:=/opt/zenos}"
: "${ZENOS_QUELLE:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
: "${ZENOS_IMAGE:=0}"
if [[ -z "${SUDO+x}" ]]; then
  if (( EUID == 0 )); then SUDO=""; else SUDO=sudo; fi
fi
if [[ -z "${ZENOS_BENUTZER+x}" ]]; then
  if (( EUID == 0 )) || [[ "$ZENOS_IMAGE" == 1 ]]; then
    ZENOS_BENUTZER=""
    ZENOS_HOME=""
  else
    ZENOS_BENUTZER=$(id -un)
    ZENOS_HOME=${HOME:-}
  fi
fi
: "${ZENOS_HOME:=}"
if [[ -z "${ZENOS_SYSTEMD+x}" ]]; then
  if [[ -d /run/systemd/system ]]; then ZENOS_SYSTEMD=1; else ZENOS_SYSTEMD=0; fi
fi

: "${ZENOS_AENDERUNGEN:=0}"
: "${ZENOS_WARNUNGEN:=0}"
: "${ZENOS_MODUL:=}"
: "${ZENOS_PHASE:=}"
_ZENOS_MODUL_START=0

_ZENOS_POLICY=/usr/sbin/policy-rc.d
_ZENOS_POLICY_MARKE='# zenOS: temporär während apt-get, verhindert Dienststarts (scripts/lib/gemeinsam.sh)'
_ZENOS_POLICY_AKTIV=0
_ZENOS_APT_AKTUELL=0
_ZENOS_UNITS_GEAENDERT=0
_ZENOS_BENUTZER_UNITS_GEAENDERT=0
_ZENOS_AUFRAEUMEN=()

# Zähler und Merker: während install.sh als Dateien in $ZENOS_TMP (subshell-fest), sonst Variablen
_zenos_zaehlerdatei() {
  [[ -n "${ZENOS_TMP:-}" && -f "$ZENOS_TMP/zaehler" ]] && printf '%s' "$ZENOS_TMP/zaehler"
}

_zenos_zaehlen() { # aenderung|warnung|unit|unit-benutzer
  local datei
  if datei=$(_zenos_zaehlerdatei); then printf '%s\n' "$1" >> "$datei"; fi
  case "$1" in
    aenderung) ZENOS_AENDERUNGEN=$((ZENOS_AENDERUNGEN + 1)) ;;
    warnung) ZENOS_WARNUNGEN=$((ZENOS_WARNUNGEN + 1)) ;;
    unit) _ZENOS_UNITS_GEAENDERT=1 ;;
    unit-benutzer) _ZENOS_BENUTZER_UNITS_GEAENDERT=1 ;;
  esac
}

zenos_anzahl() { # aenderung|warnung|unit|unit-benutzer
  local datei
  if datei=$(_zenos_zaehlerdatei); then
    grep -cx -- "$1" "$datei" || true
    return 0
  fi
  case "$1" in
    aenderung) printf '%s\n' "$ZENOS_AENDERUNGEN" ;;
    warnung) printf '%s\n' "$ZENOS_WARNUNGEN" ;;
    unit) printf '%s\n' "$_ZENOS_UNITS_GEAENDERT" ;;
    unit-benutzer) printf '%s\n' "$_ZENOS_BENUTZER_UNITS_GEAENDERT" ;;
  esac
}

# Setzt einen Merker (unit, unit-benutzer) zurück
_zenos_merker_loeschen() {
  local datei
  if datei=$(_zenos_zaehlerdatei); then sed -i "/^$1\$/d" "$datei"; fi
  case "$1" in
    unit) _ZENOS_UNITS_GEAENDERT=0 ;;
    unit-benutzer) _ZENOS_BENUTZER_UNITS_GEAENDERT=0 ;;
  esac
}

# --- Ausgabe ---------------------------------------------------------------

log_schritt() { printf '\n── %s\n' "$*"; }
log_info() { printf '   %s\n' "$*"; }
log_warnung() {
  _zenos_zaehlen warnung
  printf '   ! Warnung: %s\n' "$*" >&2
}
log_fehler() { printf '   ✗ Fehler: %s\n' "$*" >&2; }
abbruch() {
  log_fehler "$*"
  exit 1
}

aenderung() {
  _zenos_zaehlen aenderung
  printf '   geändert: %s\n' "$*"
}

# install.sh setzt _ZENOS_MODUL_START vor jeder Modulfunktion auf den Zählerstand
modul_geaendert() { (( $(zenos_anzahl aenderung) > _ZENOS_MODUL_START )); }

befehl_vorhanden() { command -v -- "$1" >/dev/null 2>&1; }

# Nur externe Befehle eintragen: Modulfunktionen sind am Ende schon wieder entfernt.
aufraeumen_bei_ende() {
  (( $# > 0 )) || return 0
  local IFS=$'\x1f'
  _ZENOS_AUFRAEUMEN+=("$*")
}

# Führt alle registrierten Aufräumbefehle aus (install.sh ruft das beim Ende auf).
_zenos_aufraeumen() {
  local eintrag
  local -a teile
  for eintrag in "${_ZENOS_AUFRAEUMEN[@]}"; do
    mapfile -t -d $'\x1f' teile < <(printf '%s' "$eintrag")
    "${teile[@]}" || true
  done
  _ZENOS_AUFRAEUMEN=()
  _zenos_policy_aus
  _zenos_policy_altlast_entfernen
}

# --- Phasen-Wächter --------------------------------------------------------

_zenos_nur_system() {
  if [[ "$ZENOS_PHASE" == benutzer ]]; then
    abbruch "$1 ist nur in modul_system erlaubt (Modul ${ZENOS_MODUL:-?})"
  fi
}

_zenos_nur_benutzer() {
  if [[ "$ZENOS_PHASE" == system ]]; then
    abbruch "$1 ist nur in modul_benutzer erlaubt (Modul ${ZENOS_MODUL:-?})"
  fi
  if [[ "$ZENOS_IMAGE" == 1 ]] || (( EUID == 0 )) || [[ -z "$ZENOS_HOME" ]]; then
    abbruch "$1: Benutzerteile laufen nie als root und nie im Image-Modus (Modul ${ZENOS_MODUL:-?})"
  fi
}

# --- interne Helfer --------------------------------------------------------

# Oktalmodus normalisieren: 0644 → 644, 04755 → 4755
_zenos_modus() {
  [[ "$1" =~ ^[0-7]{3,4}$ ]] || abbruch "Ungültiger Dateimodus: $1"
  printf '%o' "$((8#$1))"
}

# Besitzer normalisieren: «benutzer» → «benutzer:benutzer»
_zenos_besitzer() {
  local b=$1
  [[ "$b" == *:* ]] || b="$b:$b"
  [[ "$b" =~ ^[a-z_][a-z0-9_.-]*:[a-z_][a-z0-9_.-]*$ ]] || abbruch "Ungültiger Besitzer: $1"
  printf '%s' "$b"
}

# Präfix für Lesezugriffe: leer, wenn der Elternordner für den Benutzer durchsuchbar ist.
_zenos_lese_sudo() {
  local eltern
  eltern=$(dirname -- "$1")
  if [[ -x "$eltern" ]]; then printf ''; else printf '%s' "$SUDO"; fi
}

_zenos_tmp() { printf '%s' "${ZENOS_TMP:-${TMPDIR:-/tmp}}"; }

# Merkt sich Änderungen an systemd-Units (für systemd_neu_laden)
_zenos_unit_merken() {
  case "$1" in
    */systemd/user/*) _zenos_zaehlen unit-benutzer; _zenos_zaehlen unit ;;
    */systemd/*) _zenos_zaehlen unit ;;
  esac
}

# Legt den Elternordner von ZIEL als root an, nur wenn er fehlt. Nie «install -D»: uutils (Ubuntu 26.04)
# ersetzt damit einen Symlink auf einen Ordner im Pfad durch einen leeren Ordner (z. B. /etc/xdg/systemd/user).
# mkdir -p folgt Symlinks wie erwartet.
_zenos_eltern_anlegen() {
  local eltern s
  eltern=$(dirname -- "$1")
  s=$(_zenos_lese_sudo "$eltern")
  $s test -d "$eltern" && return 0
  $SUDO mkdir -p -- "$eltern"
}

# 0, wenn ZIEL eine reguläre Datei mit gleichem Inhalt, Modus und Besitzer wie QUELLE ist
_zenos_datei_gleich() {
  local quelle=$1 ziel=$2 modus=$3 besitzer=$4 s ist
  s=$(_zenos_lese_sudo "$ziel")
  if $s test -L "$ziel" || ! $s test -f "$ziel"; then return 1; fi
  ist=$($s stat -c '%a %U:%G' -- "$ziel") || return 1
  [[ "$ist" == "$modus $besitzer" ]] || return 1
  if [[ -r "$ziel" ]]; then
    cmp -s -- "$quelle" "$ziel"
  else
    $SUDO cmp -s -- "$quelle" "$ziel"
  fi
}

# --- apt -------------------------------------------------------------------

paket_installiert() {
  local status
  status=$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) || return 1
  [[ "$status" == installed ]]
}

apt_quellen_geaendert() { _ZENOS_APT_AKTUELL=0; }

_zenos_apt() {
  $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l \
    apt-get -o DPkg::Lock::Timeout=300 "$@"
}

_zenos_policy_an() {
  if [[ -e "$_ZENOS_POLICY" ]]; then
    # Eigene Datei aus einem abgebrochenen Lauf übernehmen, fremde respektieren
    if grep -qxF -- "$_ZENOS_POLICY_MARKE" "$_ZENOS_POLICY" 2>/dev/null; then _ZENOS_POLICY_AKTIV=1; fi
    return 0
  fi
  printf '#!/bin/sh\n%s\nexit 101\n' "$_ZENOS_POLICY_MARKE" | $SUDO tee "$_ZENOS_POLICY" >/dev/null
  $SUDO chmod 0755 "$_ZENOS_POLICY"
  _ZENOS_POLICY_AKTIV=1
}

_zenos_policy_aus() {
  [[ "$_ZENOS_POLICY_AKTIV" == 1 ]] || return 0
  _ZENOS_POLICY_AKTIV=0
  _zenos_policy_altlast_entfernen
}

# Entfernt eine policy-rc.d, die zenOS angelegt hat (erkennbar an der Markierung)
_zenos_policy_altlast_entfernen() {
  [[ -e "$_ZENOS_POLICY" ]] || return 0
  [[ -n "$SUDO" ]] || (( EUID == 0 )) || return 0
  if grep -qxF -- "$_ZENOS_POLICY_MARKE" "$_ZENOS_POLICY" 2>/dev/null; then
    $SUDO rm -f -- "$_ZENOS_POLICY" 2>/dev/null || true
  fi
}

pakete_sicherstellen() {
  _zenos_nur_system pakete_sicherstellen
  local paket rc=0
  local -a fehlend=() unklar=()
  for paket in "$@"; do
    [[ -n "$paket" ]] || continue
    [[ "$paket" =~ ^[a-z0-9][a-z0-9+.-]+(:[a-z0-9]+)?$ ]] || abbruch "Ungültiger Paketname: $paket"
    paket_installiert "$paket" || fehlend+=("$paket")
  done
  (( ${#fehlend[@]} > 0 )) || return 0

  if [[ "$_ZENOS_APT_AKTUELL" != 1 ]]; then
    log_info "Paketlisten aktualisieren"
    _zenos_apt update -qq || abbruch "apt-get update ist fehlgeschlagen"
    _ZENOS_APT_AKTUELL=1
  fi
  log_info "Pakete installieren: ${fehlend[*]}"
  _zenos_policy_an
  _zenos_apt install -y -q --no-install-recommends \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    "${fehlend[@]}" || rc=$?
  _zenos_policy_aus
  (( rc == 0 )) || abbruch "apt-get install ist fehlgeschlagen (Exit $rc): ${fehlend[*]}"

  for paket in "${fehlend[@]}"; do
    paket_installiert "$paket" || unklar+=("$paket")
  done
  if (( ${#unklar[@]} > 0 )); then
    log_warnung "Nach der Installation nicht als installiert erkannt (virtuelles Paket? echten Namen eintragen): ${unklar[*]}"
  fi
  aenderung "Pakete installiert: ${fehlend[*]}"
}

# --- Dateien als root ------------------------------------------------------

datei_installieren() {
  _zenos_nur_system datei_installieren
  (( $# >= 2 && $# <= 4 )) || abbruch "datei_installieren QUELLE ZIEL [MODUS] [BESITZER]"
  local quelle=$1 ziel=$2 modus besitzer s
  modus=$(_zenos_modus "${3:-0644}")
  besitzer=$(_zenos_besitzer "${4:-root:root}")
  [[ -f "$quelle" ]] || abbruch "Quelldatei fehlt: $quelle"
  _zenos_datei_gleich "$quelle" "$ziel" "$modus" "$besitzer" && return 0

  s=$(_zenos_lese_sudo "$ziel")
  if $s test -d "$ziel" && ! $s test -L "$ziel"; then abbruch "$ziel ist ein Ordner, erwartet war eine Datei"; fi
  if $s test -L "$ziel"; then $SUDO rm -f -- "$ziel"; fi
  _zenos_eltern_anlegen "$ziel"
  $SUDO install -m "$modus" -o "${besitzer%%:*}" -g "${besitzer##*:}" -- "$quelle" "$ziel"
  _zenos_unit_merken "$ziel"
  aenderung "$ziel"
}

datei_schreiben() {
  _zenos_nur_system datei_schreiben
  (( $# >= 1 && $# <= 3 )) || abbruch "datei_schreiben ZIEL [MODUS] [BESITZER]"
  local tmp
  tmp=$(mktemp "$(_zenos_tmp)/zenos-datei.XXXXXX")
  cat > "$tmp"
  datei_installieren "$tmp" "$@"
  rm -f -- "$tmp"
}

datei_entfernen() {
  _zenos_nur_system datei_entfernen
  local ziel=$1 s
  s=$(_zenos_lese_sudo "$ziel")
  $s test -e "$ziel" || $s test -L "$ziel" || return 0
  if $s test -d "$ziel" && ! $s test -L "$ziel"; then abbruch "datei_entfernen: $ziel ist ein Ordner"; fi
  $SUDO rm -f -- "$ziel"
  _zenos_unit_merken "$ziel"
  aenderung "entfernt: $ziel"
}

ordner_sicherstellen() {
  _zenos_nur_system ordner_sicherstellen
  (( $# >= 1 && $# <= 3 )) || abbruch "ordner_sicherstellen PFAD [MODUS] [BESITZER]"
  local pfad=$1 modus besitzer s ist
  modus=$(_zenos_modus "${2:-0755}")
  besitzer=$(_zenos_besitzer "${3:-root:root}")
  s=$(_zenos_lese_sudo "$pfad")
  if $s test -L "$pfad" || { $s test -e "$pfad" && ! $s test -d "$pfad"; }; then
    abbruch "$pfad existiert, ist aber kein Ordner"
  fi
  if ! $s test -d "$pfad"; then
    $SUDO install -d -m "$modus" -o "${besitzer%%:*}" -g "${besitzer##*:}" -- "$pfad"
    aenderung "Ordner $pfad"
    return 0
  fi
  ist=$($s stat -c '%a %U:%G' -- "$pfad")
  if [[ "$ist" != "$modus $besitzer" ]]; then
    $SUDO chown "$besitzer" -- "$pfad"
    $SUDO chmod "$modus" -- "$pfad"
    aenderung "Ordner $pfad ($modus $besitzer)"
  fi
}

# --- Dateien als Benutzer --------------------------------------------------

benutzer_datei_schreiben() {
  _zenos_nur_benutzer benutzer_datei_schreiben
  (( $# >= 1 && $# <= 2 )) || abbruch "benutzer_datei_schreiben ZIEL [MODUS]"
  local ziel=$1 modus ordner tmp
  modus=$(_zenos_modus "${2:-0644}")
  ordner=$(dirname -- "$ziel")
  mkdir -p -- "$ordner"
  tmp=$(mktemp "$ordner/.zenos-neu.XXXXXX")
  cat > "$tmp"
  if [[ -f "$ziel" && ! -L "$ziel" ]] && [[ "$(stat -c '%a' -- "$ziel")" == "$modus" ]] &&
    cmp -s -- "$tmp" "$ziel"; then
    rm -f -- "$tmp"
    return 0
  fi
  if [[ -d "$ziel" && ! -L "$ziel" ]]; then
    rm -f -- "$tmp"
    abbruch "$ziel ist ein Ordner, erwartet war eine Datei"
  fi
  chmod "$modus" -- "$tmp"
  mv -f -- "$tmp" "$ziel"
  _zenos_unit_merken "$ziel"
  aenderung "$ziel"
}

benutzer_datei_entfernen() {
  _zenos_nur_benutzer benutzer_datei_entfernen
  local ziel=$1
  [[ -e "$ziel" || -L "$ziel" ]] || return 0
  if [[ -d "$ziel" && ! -L "$ziel" ]]; then abbruch "benutzer_datei_entfernen: $ziel ist ein Ordner"; fi
  rm -f -- "$ziel"
  aenderung "entfernt: $ziel"
}

benutzer_ordner_sicherstellen() {
  _zenos_nur_benutzer benutzer_ordner_sicherstellen
  (( $# >= 1 && $# <= 2 )) || abbruch "benutzer_ordner_sicherstellen PFAD [MODUS]"
  local pfad=$1 modus=""
  [[ -n "${2:-}" ]] && modus=$(_zenos_modus "$2")
  if [[ -L "$pfad" || ( -e "$pfad" && ! -d "$pfad" ) ]]; then
    abbruch "$pfad existiert, ist aber kein Ordner"
  fi
  if [[ ! -d "$pfad" ]]; then
    mkdir -p -- "$pfad"
    [[ -z "$modus" ]] || chmod "$modus" -- "$pfad"
    aenderung "Ordner $pfad"
  elif [[ -n "$modus" && "$(stat -c '%a' -- "$pfad")" != "$modus" ]]; then
    chmod "$modus" -- "$pfad"
    aenderung "Ordner $pfad ($modus)"
  fi
}

# --- Symlinks --------------------------------------------------------------

# _zenos_verknuepfen PRAEFIX QUELLE ZIEL – PRAEFIX ist leer (Benutzer) oder $SUDO
_zenos_verknuepfen() {
  local s=$1 quelle=$2 ziel=$3 sicherung
  if [[ -L "$ziel" && "$(readlink -- "$ziel")" == "$quelle" ]]; then return 0; fi
  if [[ ! -e "$quelle" && ! -L "$quelle" ]]; then log_warnung "Ziel der Verknüpfung fehlt: $quelle"; fi
  $s mkdir -p -- "$(dirname -- "$ziel")"
  if [[ -e "$ziel" && ! -L "$ziel" ]]; then
    sicherung="$ziel.vor-zenos"
    if [[ -e "$sicherung" || -L "$sicherung" ]]; then sicherung="$ziel.vor-zenos.$(date +%Y%m%d-%H%M%S)"; fi
    $s mv -- "$ziel" "$sicherung"
    log_info "gesichert: $ziel → $sicherung"
  fi
  $s ln -sfn -- "$quelle" "$ziel"
  _zenos_unit_merken "$ziel"
  aenderung "$ziel → $quelle"
}

verknuepfen() {
  _zenos_nur_benutzer verknuepfen
  (( $# == 2 )) || abbruch "verknuepfen QUELLE ZIEL"
  _zenos_verknuepfen "" "$1" "$2"
}

system_verknuepfen() {
  _zenos_nur_system system_verknuepfen
  (( $# == 2 )) || abbruch "system_verknuepfen QUELLE ZIEL"
  _zenos_verknuepfen "$SUDO" "$1" "$2"
}

# --- systemd ---------------------------------------------------------------

dienst_aktivieren() {
  _zenos_nur_system dienst_aktivieren
  local einheit=$1 zustand
  zustand=$(systemctl is-enabled "$einheit" 2>/dev/null) || true
  case "$zustand" in
    enabled | enabled-runtime | static | alias | generated) return 0 ;;
    masked)
      log_warnung "Dienst $einheit ist maskiert und bleibt aus (systemctl unmask $einheit, falls gewollt)"
      return 0
      ;;
  esac
  $SUDO systemctl enable --quiet "$einheit"
  aenderung "Dienst aktiviert: $einheit"
}

dienst_neustarten_falls() {
  _zenos_nur_system dienst_neustarten_falls
  local einheit=$1
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  modul_geaendert || return 0
  systemd_neu_laden
  $SUDO systemctl restart "$einheit"
  log_info "Dienst neu gestartet: $einheit"
}

systemd_neu_laden() {
  _zenos_nur_system systemd_neu_laden
  (( $(zenos_anzahl unit) > 0 )) || return 0
  _zenos_merker_loeschen unit
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 ]] || return 0
  $SUDO systemctl daemon-reload
  log_info "systemd neu geladen"
  _zenos_benutzer_systemd_neu_laden
}

# Lädt die systemd-Benutzerinstanz neu, wenn sich Benutzer-Units geändert haben und sie erreichbar ist.
_zenos_benutzer_systemd_neu_laden() {
  (( $(zenos_anzahl unit-benutzer) > 0 )) || return 0
  _zenos_merker_loeschen unit-benutzer
  [[ "$ZENOS_SYSTEMD" == 1 && "$ZENOS_IMAGE" != 1 && -n "$ZENOS_BENUTZER" ]] || return 0
  (( EUID != 0 )) || return 0
  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$EUID}
  [[ -S "$laufzeit/bus" ]] || return 0
  if XDG_RUNTIME_DIR=$laufzeit systemctl --user daemon-reload 2>/dev/null; then
    log_info "systemd-Benutzerinstanz neu geladen"
  fi
}

# --- JSON ------------------------------------------------------------------

json_pruefen() {
  (( $# == 2 )) || abbruch "json_pruefen DATEI SCHEMA"
  befehl_vorhanden python3 || { echo "json_pruefen: python3 fehlt" >&2; return 2; }
  python3 - "$1" "$2" <<'PY'
import json
import sys

try:
    import jsonschema
except ImportError:
    print("json_pruefen: python3-jsonschema fehlt", file=sys.stderr)
    sys.exit(2)

datei, schema_datei = sys.argv[1], sys.argv[2]
try:
    with open(schema_datei, encoding="utf-8") as f:
        schema = json.load(f)
except (OSError, ValueError) as e:
    print(f"{schema_datei}: Schema nicht lesbar: {e}", file=sys.stderr)
    sys.exit(2)
try:
    with open(datei, encoding="utf-8") as f:
        daten = json.load(f)
except (OSError, ValueError) as e:
    print(f"{datei}: {e}", file=sys.stderr)
    sys.exit(1)

klasse = jsonschema.validators.validator_for(schema)
try:
    klasse.check_schema(schema)
except jsonschema.exceptions.SchemaError as e:
    print(f"{schema_datei}: ungültiges Schema: {e.message}", file=sys.stderr)
    sys.exit(2)
pruefer = getattr(klasse, "FORMAT_CHECKER", None) or jsonschema.FormatChecker()
fehler = sorted(klasse(schema, format_checker=pruefer).iter_errors(daten),
                key=lambda e: [str(p) for p in e.absolute_path])
for e in fehler:
    ort = "/".join(str(p) for p in e.absolute_path) or "(Wurzel)"
    print(f"{datei}: {ort}: {e.message}", file=sys.stderr)
sys.exit(1 if fehler else 0)
PY
}

# --- Git -------------------------------------------------------------------

git_code() { git -c safe.directory="$ZENOS_CODE" -C "$ZENOS_CODE" "$@"; }

zenos_version() {
  local pfad=${1:-$ZENOS_CODE}
  git -c safe.directory="$pfad" -C "$pfad" describe --tags --always --dirty 2>/dev/null || printf 'unbekannt\n'
}
