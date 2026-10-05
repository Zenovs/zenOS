#!/usr/bin/env bash
# shellcheck shell=bash
# wechsel.sh – gemeinsame Teile von «zen update» und «zen rollback»: Sperren, Platzprüfung, Holen von origin.
#
# Beim Sourcen passiert nichts ausser Konstanten und Funktionen. Gesourct von scripts/zen.d/update.sh und
# scripts/zen.d/rollback.sh; nutzt ZENOS_CODE, SUDO, zen_git, zen_fehler, zen_warnung und zen_hinweis aus scripts/zen.
#
#   _WECHSEL_SPERRE              eigene Sperre für Holen, Wechsel und install.sh (/run/lock/zenos-kanal.lock)
#   _WECHSEL_INSTALL_SPERRE      Sperre von install.sh (/run/lock/zenos-install.lock)
#   _WECHSEL_WARTEN              so lange wartet eine Sperre höchstens (Sekunden)
#   _WECHSEL_FRIST               Zeitlimit für ein «git fetch» (Sekunden)
#   _WECHSEL_MIN_FREI_KB         so viel muss vor einem Wechsel frei sein (KiB)
#   _wechsel_sperren             nimmt _WECHSEL_SPERRE auf Deskriptor 8; sie gilt bis zum Ende von zen
#   _wechsel_platz PFAD          1 mit Meldung, wenn auf dem Dateisystem von PFAD zu wenig frei ist
#   _wechsel_holen ARG…          «git fetch ARG…» in ZENOS_CODE als root, mit Zeitlimit und ohne Rückfragen
#   _wechsel_branch_holen        holt die Branches von origin ohne Tags; 1 mit Meldung, wenn das scheitert
#   _wechsel_tags_holen          holt die Tags von origin ohne --force; scheitert nie, meldet nur Warnungen
#   _wechsel_install_warten      wartet, bis kein install.sh mehr läuft, und hält dessen Sperre (Deskriptor 7)
#   _wechsel_install_freigeben   gibt sie wieder frei (vor dem eigenen install.sh)
#
# Ablauf in update.sh und rollback.sh: sperren, Platz prüfen, holen, auf install.sh warten, umstellen, freigeben,
# install.sh starten (ohne die Deskriptoren 7 und 8). Die Kanal-Sperre bleibt während install.sh gehalten: Ein
# zweites «zen update» stellt /opt/zenos nicht um, während ein install.sh daraus noch Module liest.
#
# Tags: «git fetch --tags» lehnt einen Tag ab, der auf origin inzwischen auf einen anderen Commit zeigt («would
# clobber existing tag», Exit 1), mit --quiet sogar ohne Meldung. So geschehen mit v0.1.0-rc1: zen update brach mit
# «git fetch ist fehlgeschlagen» ab, obwohl der Branch längst da war. Deshalb kommt der Branch getrennt und ohne
# Tags, die Tags danach ohne --force. Ein verschobener Tag bleibt hier beim alten Stand und erscheint nur als
# Warnung mit Grund: zen überschreibt Tags nie, ein Rollback geht auf den Stand, den das Gerät unter dem Namen kennt.
# Auf origin gelöschte Tags bleiben ebenfalls (kein --prune für Tags).

_WECHSEL_SPERRE=/run/lock/zenos-kanal.lock
_WECHSEL_INSTALL_SPERRE=/run/lock/zenos-install.lock
_WECHSEL_WARTEN=900
_WECHSEL_FRIST=180
# Bei voller Platte schreibt git checkout Dateien nur halb (scripts/zen mit 0 Byte, zenos-greeter abgeschnitten:
# Sperre und Login fallen aus). 1 GiB reicht für den Checkout, die apt-Läufe von install.sh und das Log; einen
# Neubau von Quickshell (etwa 3,5 GB in /var/tmp) prüft 25-quickshell selbst.
_WECHSEL_MIN_FREI_KB=1048576

# SEKUNDEN → «1 Minute» bzw. «N Minuten», aufgerundet
_wechsel_minuten() {
  local m=$(( ($1 + 59) / 60 ))
  if (( m == 1 )); then printf '1 Minute'; else printf '%s Minuten' "$m"; fi
}

# Die eigene Sperrdatei öffnet zen schreibend, eine fremde (von root, einem Dienst oder einem anderen Benutzer) nur
# lesend: In /run/lock (sticky, für alle beschreibbar) lehnt der Kern das Öffnen einer fremden Datei zum Schreiben ab
# (fs.protected_regular), auch für root. flock geht auch lesend. Wie _sperren in install.sh.
_wechsel_sperren() {
  local sperre=$_WECHSEL_SPERRE offen=0
  if ! command -v flock >/dev/null 2>&1; then
    zen_warnung "flock fehlt, weiter ohne Sperre"
    return 0
  fi
  if [[ -L "$sperre" ]]; then
    offen=0
  elif [[ -O "$sperre" ]]; then
    if { exec 8>>"$sperre"; } 2>/dev/null; then offen=1; fi
  elif [[ -e "$sperre" ]]; then
    if { exec 8<"$sperre"; } 2>/dev/null; then offen=1; fi
  elif { exec 8>>"$sperre"; } 2>/dev/null; then
    offen=1
  elif { exec 8<"$sperre"; } 2>/dev/null; then
    # Ein anderer Lauf hat sie gerade angelegt, sie gehört ihm
    offen=1
  fi
  if (( ! offen )); then
    zen_warnung "Sperrdatei $sperre nicht nutzbar, weiter ohne Sperre"
    return 0
  fi
  flock -n 8 && return 0
  zen_hinweis "Ein anderes Update oder Rollback läuft gerade, warte (höchstens $(_wechsel_minuten "$_WECHSEL_WARTEN")) …"
  flock -w "$_WECHSEL_WARTEN" 8 && return 0
  exec 8<&-
  zen_fehler "Das andere Update oder Rollback ist nach $(_wechsel_minuten "$_WECHSEL_WARTEN") nicht fertig. Nichts geändert."
  return 1
}

_wechsel_platz() { # PFAD
  local pfad=$1 frei_kb
  frei_kb=$(df -P -k -- "$pfad" 2>/dev/null | awk 'NR == 2 { print $4 }')
  if [[ ! "$frei_kb" =~ ^[0-9]+$ ]]; then
    zen_warnung "Freier Platz unter $pfad nicht ermittelbar, weiter ohne Prüfung"
    return 0
  fi
  (( frei_kb < _WECHSEL_MIN_FREI_KB )) || return 0
  zen_fehler "Nur $(( frei_kb / 1024 )) MB frei unter $pfad, ein Wechsel braucht mindestens $(( _WECHSEL_MIN_FREI_KB / 1024 )) MB. Nichts geändert. Zuerst Platz schaffen, dann noch einmal."
  return 1
}

# Als root (über sudo), damit die Dateien in ZENOS_CODE root gehören. sudo fragt vor dem Zeitlimit nach dem Passwort:
# timeout läuft in einer eigenen Prozessgruppe und dürfte nicht vom Terminal lesen. GIT_TERMINAL_PROMPT=0: Will
# origin Zugangsdaten (Repo privat, Adresse falsch), scheitert fetch sofort, statt zu warten.
_wechsel_holen() { # ARG…
  $SUDO env GIT_TERMINAL_PROMPT=0 timeout --kill-after=10 "$_WECHSEL_FRIST" \
    git -c safe.directory="$ZENOS_CODE" -C "$ZENOS_CODE" fetch "$@"
}

# Grund eines gescheiterten fetch für die Meldung (Exit-Code von _wechsel_holen, Datei mit stderr)
_wechsel_grund() { # RC DATEI
  local rc=$1 datei=$2 zeile=""
  if (( rc == 124 || rc == 137 )); then
    printf 'nach %s s abgebrochen, Netz langsam oder weg?' "$_WECHSEL_FRIST"
    return 0
  fi
  if [[ -n "$datei" && -r "$datei" ]]; then
    zeile=$(grep -m 1 -E '^(fatal|error): ' -- "$datei" 2>/dev/null) || zeile=""
  fi
  if [[ -n "$zeile" ]]; then printf 'Exit %s: %s' "$rc" "$zeile"; else printf 'Exit %s' "$rc"; fi
}

# Temp-Datei für stderr von git, leer, wenn keine anzulegen war (dann ohne Grund in der Meldung)
_wechsel_temp() { mktemp "${TMPDIR:-/tmp}/zen-wechsel.XXXXXX" 2>/dev/null || true; }

_wechsel_branch_holen() {
  local fehler rc=0
  fehler=$(_wechsel_temp)
  _wechsel_holen --quiet --no-tags --prune origin 2> "${fehler:-/dev/null}" || rc=$?
  if (( rc != 0 )); then
    zen_fehler "git fetch ist fehlgeschlagen ($(_wechsel_grund "$rc" "$fehler")). Am installierten Stand hat sich nichts geändert."
  fi
  [[ -z "$fehler" ]] || rm -f -- "$fehler"
  (( rc == 0 ))
}

# Kurzform des Commits, auf den ein Objekt (Tag oder Commit) zeigt; ohne das Objekt dessen eigene Kurzform
_wechsel_kurz() { # OBJEKT
  zen_git rev-parse --short --verify --quiet "$1^{commit}" 2>/dev/null || printf '%s\n' "${1:0:7}"
}

# «git fetch --porcelain» schreibt je Ref eine Zeile «<flag> <alt> <neu> <ref>» auf stdout; «!» heisst abgelehnt.
_wechsel_tags_holen() {
  local fehler ausgabe rc=0 flag alt neu ref name abgelehnt=0
  fehler=$(_wechsel_temp)
  ausgabe=$(_wechsel_holen --porcelain --no-tags origin 'refs/tags/*:refs/tags/*' 2> "${fehler:-/dev/null}") || rc=$?
  while read -r flag alt neu ref; do
    [[ "$flag" == '!' && "$ref" == refs/tags/?* ]] || continue
    name=${ref#refs/tags/}
    abgelehnt=$(( abgelehnt + 1 ))
    if [[ "$alt" =~ ^[0-9a-f]+$ && ! "$alt" =~ ^0+$ ]]; then
      zen_warnung "Tag $name wurde auf origin verschoben (dort $(_wechsel_kurz "$neu"), hier $(_wechsel_kurz "$alt")). Hier bleibt der alte Stand, zen überschreibt keine Tags. Übernehmen: sudo git -C $ZENOS_CODE tag -d $name, dann noch einmal zen update."
    else
      zen_warnung "Tag $name von origin liess sich nicht anlegen"
    fi
  done <<< "$ausgabe"
  if (( rc != 0 && abgelehnt == 0 )); then
    zen_warnung "Tags von origin nicht geholt ($(_wechsel_grund "$rc" "$fehler")), es gelten die vorhandenen"
  fi
  [[ -z "$fehler" ]] || rm -f -- "$fehler"
  return 0
}

# Läuft gerade ein install.sh (aus /opt/zenos oder einem Arbeits-Checkout), wartet der Wechsel darauf: Es liest
# seine Module nacheinander aus dem Checkout. Die Sperre bleibt bis _wechsel_install_freigeben gehalten, also nur
# für die Umstellung selbst; das eigene install.sh nimmt sie danach wieder.
_wechsel_install_warten() {
  local sperre=$_WECHSEL_INSTALL_SPERRE
  command -v flock >/dev/null 2>&1 || return 0
  [[ -f "$sperre" && ! -L "$sperre" ]] || return 0
  { exec 7<"$sperre"; } 2>/dev/null || return 0
  flock -n 7 && return 0
  zen_hinweis "Eine zenOS-Installation läuft gerade. Der Wechsel wartet, bis sie fertig ist (höchstens $(_wechsel_minuten "$_WECHSEL_WARTEN")) …"
  flock -w "$_WECHSEL_WARTEN" 7 && return 0
  exec 7<&-
  zen_fehler "Die laufende Installation ist nach $(_wechsel_minuten "$_WECHSEL_WARTEN") nicht fertig. Nichts geändert."
  return 1
}

_wechsel_install_freigeben() { exec 7<&-; }
