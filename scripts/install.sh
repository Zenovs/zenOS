#!/usr/bin/env bash
# install.sh – installiert zenOS. Idempotent: darf beliebig oft laufen, der zweite Lauf ändert nichts.
#
#   scripts/install.sh [--image] [--nur-benutzer] [--nur-code] [--ruhig]
#
# Läuft als normaler Benutzer und holt sich Root-Rechte mit sudo für die Systemteile. Als root über
# sudo aufgerufen, läuft es als der aufrufende Benutzer weiter. Die Module unter scripts/module/*.sh
# laufen in Namensreihenfolge in zwei Durchgängen: erst alle modul_system, dann alle modul_benutzer.
# Log: /var/log/zenos/install.log (mit --nur-benutzer ohne Schreibrecht dort:
# ~/.local/state/zenos/install.log).

set -Eeuo pipefail
umask 022

_hilfe() {
  cat <<'EOF'
Aufruf: scripts/install.sh [--image] [--nur-benutzer] [--nur-code] [--ruhig]

  --image         für den Image-Bau im chroot: ohne Benutzerteile, ohne proprietäre Apps,
                  ohne laufende Dienste (nur aktivieren)
  --nur-benutzer  nur die Benutzerteile, ohne sudo (auch beim Sitzungsstart)
  --nur-code      nur root: nur /opt/zenos auf den Stand dieser Quelle bringen (Modul 10-code),
                  ohne Netz; für zenos-kanal-nachstart.service nach einem Abbruch
  --ruhig         im Terminal nur Warnungen und Fehler, alles andere ins Log
EOF
}

ZENOS_IMAGE=0
_NUR_BENUTZER=0
_NUR_CODE=0
_RUHIG=0
for _arg in "$@"; do
  case "$_arg" in
    --image) ZENOS_IMAGE=1 ;;
    --nur-benutzer) _NUR_BENUTZER=1 ;;
    --nur-code) _NUR_CODE=1 ;;
    --ruhig) _RUHIG=1 ;;
    -h | --hilfe | --help) _hilfe; exit 0 ;;
    *) printf 'install.sh: unbekannte Option «%s»\n\n' "$_arg" >&2; _hilfe >&2; exit 2 ;;
  esac
done
if (( ZENOS_IMAGE + _NUR_BENUTZER + _NUR_CODE > 1 )); then
  echo "install.sh: --image, --nur-benutzer und --nur-code schliessen sich aus" >&2
  exit 2
fi
if (( _NUR_CODE && EUID != 0 )); then
  echo "install.sh: --nur-code läuft nur als root (zenos-kanal-nachstart.service)" >&2
  exit 2
fi

_SKRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
ZENOS_QUELLE=$(cd -- "$(dirname -- "$_SKRIPT")/.." && pwd -P)
# Fest: eine Umgebungsvariable ZENOS_CODE (z. B. aus Oberflächentests) darf das Ziel nie verschieben.
ZENOS_CODE=/opt/zenos

# Als root über sudo aufgerufen: als der aufrufende Benutzer weiterlaufen (Systemteile dann mit sudo).
if (( EUID == 0 && ! ZENOS_IMAGE && ! _NUR_CODE )) && [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
  _home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  printf 'install.sh läuft als Benutzer %s weiter.\n' "$SUDO_USER"
  exec sudo -u "$SUDO_USER" env "HOME=$_home" "$_SKRIPT" "$@"
fi

# Zielbenutzer und Rechte
if (( EUID == 0 )); then SUDO=""; else SUDO=sudo; fi
if (( ZENOS_IMAGE )) || (( EUID == 0 )); then
  ZENOS_BENUTZER=""
  ZENOS_HOME=""
  if (( _NUR_BENUTZER )); then
    echo "install.sh: --nur-benutzer läuft als normaler Benutzer, nicht als root" >&2
    exit 2
  fi
else
  ZENOS_BENUTZER=$(id -un)
  ZENOS_HOME=$(getent passwd "$ZENOS_BENUTZER" | cut -d: -f6)
  [[ -n "$ZENOS_HOME" ]] || ZENOS_HOME=$HOME
fi
# Benutzerteile dürfen nie sudo nutzen
if (( _NUR_BENUTZER )); then SUDO=""; fi
if [[ -d /run/systemd/system ]]; then ZENOS_SYSTEMD=1; else ZENOS_SYSTEMD=0; fi
ZENOS_AENDERUNGEN=0
ZENOS_WARNUNGEN=0

# shellcheck source=lib/gemeinsam.sh
source "$ZENOS_QUELLE/scripts/lib/gemeinsam.sh"

readonly ZENOS_QUELLE ZENOS_CODE ZENOS_IMAGE ZENOS_BENUTZER ZENOS_HOME ZENOS_SYSTEMD
export ZENOS_QUELLE ZENOS_CODE ZENOS_IMAGE ZENOS_BENUTZER ZENOS_HOME ZENOS_SYSTEMD

if (( ZENOS_IMAGE )); then _MODUS=image; elif (( _NUR_BENUTZER )); then _MODUS=benutzer
elif (( _NUR_CODE )); then _MODUS=code; else _MODUS=normal; fi
_LOG=""
_TEE_PID=""
_SUDO_WACH_PID=""

# --- Ende und Fehler -------------------------------------------------------

_anzahl() { # ZAHL EINZAHL MEHRZAHL
  if (( $1 == 1 )); then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi
}

_fehler_melden() {
  local rc=$? zeile=$1 befehl=$2 datei
  (( BASH_SUBSHELL == 0 )) || return "$rc"
  datei=${BASH_SOURCE[1]:-install.sh}
  datei=${datei#"$ZENOS_QUELLE"/}
  log_fehler "Befehl fehlgeschlagen (Exit $rc) in ${ZENOS_MODUL:-install.sh} · $datei:$zeile: $befehl"
  return "$rc"
}

_ende() {
  local rc=$?
  set +e
  trap - ERR
  # Die Ende-Zeile muss ins Log, auch wenn das Terminal gerade wegfällt (SSH getrennt, Leser der Ausgabe beendet)
  trap '' HUP PIPE
  _zenos_aufraeumen
  _hand_vermerk_entfernen
  if [[ -n "$_SUDO_WACH_PID" ]]; then kill "$_SUDO_WACH_PID" 2>/dev/null; fi
  local aenderungen warnungen
  aenderungen=$(zenos_anzahl aenderung)
  warnungen=$(zenos_anzahl warnung)
  if [[ -n "${ZENOS_TMP:-}" ]]; then rm -rf -- "$ZENOS_TMP"; fi
  # Ausgabe zurück aufs Terminal und warten, bis tee alles geschrieben hat
  if [[ -n "$_TEE_PID" ]]; then
    exec 1>&3 2>&4
    wait "$_TEE_PID" 2>/dev/null
  fi
  if [[ -n "$_LOG" ]]; then
    local ergebnis=ok
    if (( rc != 0 )); then
      ergebnis="abbruch (Exit $rc)"
      printf '\nzenOS-Installation abgebrochen (Exit %s) · %s · Log: %s\n' "$rc" \
        "$(_anzahl "$aenderungen" Änderung Änderungen)" "$_LOG" | tee -a -- "$_LOG" >&2
    fi
    printf '== Ende %s · %s · %s · %s · %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_MODUS" "$ergebnis" \
      "$(_anzahl "$aenderungen" Änderung Änderungen)" "$(_anzahl "$warnungen" Warnung Warnungen)" \
      >> "$_LOG"
  fi
  exit "$rc"
}

# Jedes Signal, das den Lauf beendet, endet als «abbruch (Exit 128+N)» im Log. Ohne eigenen Trap stünde ein Abbruch
# durch SIGHUP (SSH-Verbindung weg, ohne tmux) oder SIGPIPE als «ok» dort. Ein SIGKILL oder Stromausfall hinterlässt
# «== Beginn» ohne «== Ende»; das meldet zen doctor.
trap _ende EXIT
trap '_fehler_melden "$LINENO" "$BASH_COMMAND"' ERR
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 141' PIPE
trap 'exit 143' TERM

# --- Sperre: nie zwei Läufe gleichzeitig -----------------------------------

# Ordner der Sperren, die nur root halten kann (wie in zenos-kanal): /run/zenos-sperre, 0700. Eine Sperre in /run/lock
# (für alle beschreibbar) könnte jeder Benutzer anlegen oder lesend öffnen und halten (flock geht auch so).
_ROOT_SPERREN=/run/zenos-sperre
_HAND_VERMERK=""

# Als root (Kanal, nachstart --nur-code): die Sperre in _ROOT_SPERREN, an die kein Benutzer kommt. Sonst (von Hand als
# Benutzer, auch die Benutzerteile beim Anmelden, und im Image) /run/lock/zenos-install.lock wie bisher. Zum Schreiben
# öffnet install.sh dort nur die eigene Sperrdatei: Eine fremde lehnt der Kern in /run/lock (sticky, für alle
# beschreibbar) wegen fs.protected_regular ab, auch für root. flock geht auch lesend. Bleibt die Sperre 15 Minuten
# belegt: Exit 75, ohne etwas begonnen zu haben (zenos-kanal zählt den Versuch dann nicht).
_sperren() {
  local sperre=/run/lock/zenos-install.lock
  if (( EUID == 0 && ! ZENOS_IMAGE )) && [[ -d /run && ! -L "$_ROOT_SPERREN" ]]; then
    install -d -m 0700 -o root -g root -- "$_ROOT_SPERREN" 2>/dev/null || true
    sperre=$_ROOT_SPERREN/install.lock
    if [[ -d "$_ROOT_SPERREN" && -O "$_ROOT_SPERREN" && ! -L "$_ROOT_SPERREN" && ! -L "$sperre" ]] &&
      { exec 9>>"$sperre"; } 2>/dev/null; then
      :
    else
      echo "install.sh: $_ROOT_SPERREN nicht nutzbar, weiter ohne Sperre" >&2
      return 0
    fi
  elif [[ -e "$sperre" || -L "$sperre" ]]; then
    if [[ -O "$sperre" && ! -L "$sperre" ]] && { exec 9>>"$sperre"; } 2>/dev/null; then
      :
    elif ! { exec 9<"$sperre"; } 2>/dev/null; then
      echo "install.sh: Sperrdatei $sperre nicht lesbar, weiter ohne Sperre" >&2
      return 0
    fi
  elif [[ -d /run/lock && -w /run/lock ]]; then
    # Hat ein anderer Lauf sie gerade angelegt, gehört sie ihm: dann lesend
    if ! { exec 9>>"$sperre"; } 2>/dev/null && ! { exec 9<"$sperre"; } 2>/dev/null; then
      echo "install.sh: Sperrdatei $sperre nicht nutzbar, weiter ohne Sperre" >&2
      return 0
    fi
  else
    return 0
  fi
  if ! flock -n 9; then
    (( _RUHIG )) || echo "Eine andere zenOS-Installation läuft gerade, warte …" >&2
    flock -w 900 9 || { echo "install.sh: Sperre $sperre nicht frei geworden" >&2; exit 75; }
  fi
}

# Ein Lauf von Hand (aus ~/zenOS oder aus /opt/zenos, nicht der Kanal, nicht Image, nicht nur Benutzerteile) vermerkt
# sich für zenos-kanal: Er wartet auf die Kanal-Sperre (nur root, über sudo), trägt darunter seine PID in
# /run/zenos-sperre/hand ein und gibt sie wieder frei. Solange dieser Prozess läuft, installiert der Kanal nichts
# (zen update meldet es); umgekehrt wartet ein Lauf von Hand, bis der Kanal fertig ist. Den Vermerk kann nur root
# schreiben, ein anderer Benutzer kann den Kanal so nicht anhalten. Am Ende entfernt _ende ihn.
_hand_vermerken() {
  local warten=900
  (( ! ZENOS_IMAGE && ! _NUR_BENUTZER && ! _NUR_CODE )) || return 0
  [[ "${ZENOS_KANAL_LAUF:-}" != 1 ]] || return 0
  befehl_vorhanden flock && [[ -d /run ]] || return 0
  $SUDO install -d -m 0700 -o root -g root -- "$_ROOT_SPERREN"
  if printf '%s\n' "$$" | $SUDO flock -n "$_ROOT_SPERREN/kanal.lock" tee -- "$_ROOT_SPERREN/hand" > /dev/null; then
    _HAND_VERMERK=$_ROOT_SPERREN/hand
    return 0
  fi
  (( _RUHIG )) || echo "Der Kanal prüft oder installiert gerade, warte (höchstens $(( warten / 60 )) Minuten) …" >&2
  if ! printf '%s\n' "$$" |
    $SUDO flock -w "$warten" "$_ROOT_SPERREN/kanal.lock" tee -- "$_ROOT_SPERREN/hand" > /dev/null; then
    echo "install.sh: Der Kanal ist nach $(( warten / 60 )) Minuten nicht fertig" >&2
    exit 75
  fi
  _HAND_VERMERK=$_ROOT_SPERREN/hand
}

# Den eigenen Vermerk entfernen (nur, wenn er noch diese PID trägt). Ohne sudo-Anmeldung bleibt er liegen; zenos-kanal
# übergeht ihn, sobald dieser Prozess nicht mehr läuft.
_hand_vermerk_entfernen() {
  [[ -n "$_HAND_VERMERK" ]] || return 0
  local -a als_root=()
  if [[ -n "$SUDO" ]]; then als_root=(sudo -n); fi
  if [[ "$("${als_root[@]}" cat -- "$_HAND_VERMERK" 2>/dev/null)" == "$$" ]]; then
    "${als_root[@]}" rm -f -- "$_HAND_VERMERK" 2>/dev/null || true
  fi
}

# --- sudo ------------------------------------------------------------------

_sudo_vorbereiten() {
  [[ -n "$SUDO" ]] || return 0
  befehl_vorhanden sudo || { echo "install.sh: sudo fehlt" >&2; exit 1; }
  # Ohne Passwortabfrage erlaubt (-k: zwischengespeicherte Anmeldung nicht mitzählen): nichts zu tun
  sudo -n -k true 2>/dev/null && return 0
  if ! sudo -n true 2>/dev/null; then
    echo "zenOS braucht sudo für die Systemteile."
    sudo -v || { echo "install.sh: ohne sudo-Rechte geht es nicht" >&2; exit 1; }
  fi
  # sudo-Anmeldung während langer Schritte (Quickshell-Bau) frisch halten, endet mit install.sh
  (
    trap - ERR EXIT
    exec 9>&-
    while kill -0 "$$" 2>/dev/null; do
      sudo -n -v 2>/dev/null || true
      sleep 50
    done
  ) >/dev/null 2>&1 &
  _SUDO_WACH_PID=$!
}

# --- Log -------------------------------------------------------------------

_log_vorbereiten() {
  local ordner=/var/log/zenos datei=/var/log/zenos/install.log besitzer gruppe=root ist
  local -a vorab=()
  if (( ! _NUR_BENUTZER )); then
    if getent group adm >/dev/null; then gruppe=adm; fi
    besitzer=${ZENOS_BENUTZER:-root}
    # Ohne Zielbenutzer (als root, Image) bleibt eine vorhandene Datei beim Benutzer: sonst schreibt
    # --nur-benutzer beim nächsten Anmelden nicht mehr hinein
    if [[ -z "$ZENOS_BENUTZER" && -f "$datei" ]]; then
      besitzer=$(stat -c '%U' -- "$datei")
      getent passwd "$besitzer" >/dev/null || besitzer=root
    fi
    if [[ ! -d "$ordner" ]]; then
      $SUDO install -d -m 0755 -o root -g root "$ordner"
      vorab+=("Ordner $ordner")
    fi
    if [[ ! -f "$datei" ]]; then
      $SUDO install -m 0640 -o "$besitzer" -g "$gruppe" /dev/null "$datei"
      vorab+=("$datei")
    else
      ist=$(stat -c '%U:%G %a' -- "$datei")
      if [[ "$ist" != "$besitzer:$gruppe 640" ]]; then
        $SUDO chown "$besitzer:$gruppe" -- "$datei"
        $SUDO chmod 0640 -- "$datei"
        vorab+=("$datei ($besitzer:$gruppe 640)")
      fi
    fi
    _LOG=$datei
  elif [[ -w "$datei" ]]; then
    _LOG=$datei
  else
    _LOG=$ZENOS_HOME/.local/state/zenos/install.log
    mkdir -p -- "${_LOG%/*}"
  fi

  # Log klein halten: über 2 MiB bleiben die letzten 512 KiB
  if [[ -f "$_LOG" ]] && (( $(stat -c %s -- "$_LOG") > 2097152 )); then
    local rest
    rest=$(mktemp "$ZENOS_TMP/log.XXXXXX")
    tail -c 524288 -- "$_LOG" > "$rest"
    cat -- "$rest" > "$_LOG"
  fi

  exec 3>&1 4>&2
  if (( _RUHIG )); then
    # Beide hängen nur mit O_APPEND an dieselbe Datei an.
    # shellcheck disable=SC2094
    exec 1>>"$_LOG" 2> >(tee -i -a -- "$_LOG" >&4)
  else
    exec > >(tee -i -a -- "$_LOG") 2>&1
  fi
  _TEE_PID=$!

  printf '\n== Beginn %s · %s · zenOS-Installation\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_MODUS" >> "$_LOG"
  if (( ! _RUHIG )); then
    # HOME fehlt womöglich (systemd-Dienst ohne User=); dann bleibt die Quelle ungekürzt
    local quelle=$ZENOS_QUELLE
    if [[ -n "${HOME:-}" && "$HOME" != / && "$quelle" == "$HOME"/* ]]; then quelle=\~/${quelle#"$HOME"/}; fi
    printf 'zenOS-Installation · %s · Quelle %s\n' "$_MODUS" "$quelle" >&3
  fi
  local t
  for t in "${vorab[@]}"; do aenderung "$t"; done
}

# --- Module ----------------------------------------------------------------

_funktionen() { declare -F | awk '{ print $3 }' | LC_ALL=C sort; }

# _module_ausfuehren system|benutzer
_module_ausfuehren() {
  local phase=$1 datei name kurz beschreibung f
  local -a dateien neu
  local vorher nachher
  dateien=()
  while IFS= read -r -d '' datei; do dateien+=("$datei"); done < <(
    find "$ZENOS_QUELLE/scripts/module" -maxdepth 1 -type f -name '*.sh' -print0 | LC_ALL=C sort -z
  )
  for datei in "${dateien[@]}"; do
    name=$(basename -- "$datei" .sh)
    # --nur-code: nur die Übernahme des Codes, kein anderes Modul (auch nicht laden)
    if (( _NUR_CODE )) && [[ "$name" != 10-code ]]; then continue; fi
    kurz=${name#[0-9][0-9]-}
    kurz=${kurz//-/_}
    vorher=$(_funktionen)
    # shellcheck source=/dev/null
    source "$datei"
    nachher=$(_funktionen)
    mapfile -t neu < <(LC_ALL=C comm -13 <(printf '%s\n' "$vorher") <(printf '%s\n' "$nachher"))

    if [[ "$phase" == system || "$_MODUS" == benutzer ]]; then
      for f in "${neu[@]}"; do
        case "$f" in
          modul_system | modul_benutzer | "_${kurz}_"*) ;;
          *) log_warnung "Modul $name definiert die Funktion $f (erlaubt: modul_system, modul_benutzer, _${kurz}_*)" ;;
        esac
      done
    fi

    if declare -F "modul_$phase" >/dev/null; then
      beschreibung=$(sed -n 's/^# [0-9][0-9]-[a-z0-9-]*: //p' "$datei" | head -n 1)
      ZENOS_MODUL=$name
      _ZENOS_MODUL_START=$(zenos_anzahl aenderung)
      ZENOS_PHASE=$phase
      log_schritt "$name${beschreibung:+ · $beschreibung}"
      "modul_$phase"
      ZENOS_PHASE=""
      ZENOS_MODUL=""
    fi
    for f in "${neu[@]}"; do unset -f "$f"; done
  done
}

# --- Oberfläche --------------------------------------------------------------

# Quickshell lädt die Oberfläche bei jeder geänderten QML-Datei sofort neu, ohne auf weitere Änderungen zu
# warten, und sieht Änderungen während des Ladens nicht mehr. Ändern sich viele Dateien nacheinander
# (10-code, git in zen update), kann so ein Mix aus alten und neuen Dateien geladen bleiben (Leiste,
# Befehlsfeld oder Mitteilungen fehlen bis zum nächsten Neustart). Deshalb am Ende eines normalen Laufs:
# Ist eine Datei der Oberfläche neuer als der geladene Stand oder Quickshell selbst neuer als der laufende
# Prozess, startet install.sh zenos-shell.service einmal neu. Wartende Mitteilungen gehen dabei verloren (wie bei einem Absturz).
# Gesperrt nie: Während der Sperre ruht das Neuladen, und die Sperre lädt nach dem Entsperren selbst neu
# (sperre/Sperre.qml). Ein Neustart wäre auch dann sicher (die neue Shell sperrt über den Marker wieder).
_oberflaeche_auffrischen() {
  local laufzeit=${XDG_RUNTIME_DIR:-/run/user/$EUID} ordner=$ZENOS_HOME/.config/quickshell
  local ipc=$ZENOS_CODE/scripts/bin/zenos-ipc start bezug geladen="" geaendert status ende qs
  [[ "$ZENOS_SYSTEMD" == 1 && -S "$laufzeit/bus" && -e "$ordner/shell.qml" ]] || return 0
  XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-shell.service 2>/dev/null || return 0
  start=$(XDG_RUNTIME_DIR=$laufzeit systemctl --user show --property=ExecMainStartTimestamp --timestamp=unix \
    --value zenos-shell.service 2>/dev/null) || return 0
  [[ "$start" =~ ^@[0-9]+$ ]] || return 0

  # Hat die Sperre die Oberfläche nach dem Entsperren im selben Prozess neu geladen (M7), steht in
  # oberflaeche-geladen der Zeitpunkt davor (Unix-Sekunden). Es gilt der neuere von beiden, der geladene
  # aber nur, wenn er vor diesem Lauf liegt: Ein Neuladen während der Übernahme sah womöglich nur einen Teil.
  bezug=$start
  if [[ -f "$laufzeit/zenos/oberflaeche-geladen" ]]; then
    read -r geladen < "$laufzeit/zenos/oberflaeche-geladen" || true
  fi
  if [[ "$geladen" =~ ^[0-9]{1,12}$ ]] && (( geladen > ${start#@} && geladen < _LAUF_BEGINN )); then
    bezug=@$geladen
  fi

  # Sekundengenau: Was in derselben Sekunde wie der Start geschrieben wurde, zählt als neuer
  geaendert=$(find -L "$ordner/" -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' -o -name qmldir \) \
    -newermt "$bezug" -print -quit 2>/dev/null) || geaendert=""
  # Quickshell selbst lädt nur ein Neustart neu
  qs=$(readlink -f -- /usr/local/bin/quickshell 2>/dev/null) || qs=""
  if [[ -z "$geaendert" && -n "$qs" ]]; then
    geaendert=$(find "$qs" -maxdepth 0 -newermt "$start" -print 2>/dev/null) || geaendert=""
  fi
  [[ -n "$geaendert" ]] || return 0

  if [[ -e "$laufzeit/zenos/gesperrt" ]]; then
    log_info "Oberfläche geändert; sie lädt nach dem Entsperren neu."
    return 0
  fi
  status=$(XDG_RUNTIME_DIR=$laufzeit timeout 5 "$ipc" sperre status 2>/dev/null) || status=""
  if [[ "${status//[[:space:]]/}" == gesperrt ]]; then
    log_info "Oberfläche geändert; sie lädt nach dem Entsperren neu."
    return 0
  fi
  # Läuft install.sh selbst in der Oberfläche (ihrer cgroup), endete es mit ihr
  if grep -q '/zenos-shell\.service$' /proc/self/cgroup 2>/dev/null; then
    log_info "Oberfläche geändert. Neu starten: systemctl --user restart zenos-shell.service"
    return 0
  fi

  log_info "Oberfläche geändert, während sie lief: starte sie neu …"
  if ! XDG_RUNTIME_DIR=$laufzeit timeout 30 systemctl --user try-restart zenos-shell.service 2>/dev/null; then
    log_warnung "Oberfläche liess sich nicht neu starten (systemctl --user restart zenos-shell.service)"
    return 0
  fi
  ende=$((SECONDS + 30))
  until XDG_RUNTIME_DIR=$laufzeit timeout 5 "$ipc" sperre status >/dev/null 2>&1; do
    if (( SECONDS >= ende )); then
      log_warnung "Oberfläche antwortet nach dem Neustart nicht (journalctl --user -u zenos-shell.service)"
      return 0
    fi
    sleep 1
  done
  log_info "Oberfläche neu gestartet."
}

# --- Ablauf ----------------------------------------------------------------

_sperren
# Beginn dieses Laufs (nach der Sperre), für _oberflaeche_auffrischen
printf -v _LAUF_BEGINN '%(%s)T' -1
_sudo_vorbereiten
_hand_vermerken
ZENOS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/zenos-install.XXXXXX")
export ZENOS_TMP
: > "$ZENOS_TMP/zaehler"
_zenos_policy_altlast_entfernen
_log_vorbereiten

if (( ! _NUR_BENUTZER )); then
  _module_ausfuehren system
  ZENOS_PHASE=system
  systemd_neu_laden
  ZENOS_PHASE=""
fi

if (( ZENOS_IMAGE )); then
  printf '\n'
  log_info "Image-Modus: Benutzerteile folgen beim ersten Login."
elif (( _NUR_CODE )); then
  printf '\n'
  log_info "Nur der Code: Pakete, Units und Benutzerteile folgen mit dem nächsten vollen Lauf (zen update)."
elif [[ -z "$ZENOS_BENUTZER" ]]; then
  printf '\n'
  log_info "Als root ohne Zielbenutzer: Benutzerteile übersprungen (später mit «zen benutzer»)."
else
  _module_ausfuehren benutzer
  _zenos_benutzer_systemd_neu_laden
  # Von Hand auch nach --nur-benutzer: zen update holt den Code als root (zenos-kanal) und richtet danach die
  # Benutzerteile so ein; beim Sitzungsstart (--ruhig) läuft die Oberfläche noch nicht
  if [[ "$_MODUS" == normal ]] || (( _NUR_BENUTZER && ! _RUHIG )); then _oberflaeche_auffrischen; fi
fi

if git -c safe.directory="$ZENOS_CODE" -C "$ZENOS_CODE" rev-parse --git-dir >/dev/null 2>&1; then
  _version=$(zenos_version "$ZENOS_CODE")
else
  _version=$(zenos_version "$ZENOS_QUELLE")
fi
_zusatz=""
case "$_MODUS" in
  image) _zusatz=" (Image)" ;;
  benutzer) _zusatz=" (Benutzerteile)" ;;
  code) _zusatz=" (nur Code)" ;;
esac
_aenderungen=$(zenos_anzahl aenderung)
_warnungen=$(zenos_anzahl warnung)
_zeile="zenOS $_version installiert$_zusatz · $(_anzahl "$_aenderungen" Änderung Änderungen)"
if (( _warnungen > 0 )); then _zeile+=" · $(_anzahl "$_warnungen" Warnung Warnungen)"; fi
printf '\n%s\n' "$_zeile"
if (( _RUHIG && _warnungen > 0 )); then printf '%s\n' "$_zeile" >&4; fi
