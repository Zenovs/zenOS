#!/usr/bin/env bash
# 10-code: /opt/zenos als Git-Checkout auf den Arbeitsstand der Quelle bringen, Kanal festlegen
# shellcheck shell=bash
#
# Läuft install.sh aus einem anderen Checkout, bekommt /opt/zenos genau dessen Stand: Commit und Branch (per git
# fetch), Tags, origin (GitHub-URL der Quelle, ohne Zugangsdaten, SSH als HTTPS, weil root keinen SSH-Schlüssel hat),
# dazu nicht committete und neue, nicht ignorierte Dateien. In der Quelle gelöschte Dateien verschwinden auch in
# /opt/zenos. Jede Datei wird atomar ersetzt (siehe _code_arbeitsstand). Läuft install.sh aus /opt/zenos selbst
# (Notweg, von Hand), wird nichts synchronisiert.
#
# Zwei Arten von Quellen:
# - Der Kanal (zen update, zen rollback): zenos-kanal startet install.sh als root aus einer geprüften Bereitstellung
#   (/var/lib/zenos/kanal/bereit/<commit>) mit ZENOS_KANAL_LAUF=1. Er hält die Kanal-Sperre selbst.
# - Von Hand aus einem Arbeits-Checkout (etwa ~/zenOS): install.sh hat vorher auf die Kanal-Sperre
#   (/run/lock/zenos-kanal.lock) gewartet und hält sie bis zum Ende, damit Kanal und Hand nie zugleich /opt/zenos
#   umstellen. Danach gilt der Stand als «angehalten» (/var/lib/zenos/kanal/angehalten): Er stammt nicht aus dem
#   Kanal, bis zum nächsten zen update kommt nichts automatisch.
# Jeder Lauf von Hand (auch aus /opt/zenos, etwa der Notweg) ersetzt eine unterbrochene Kanal-Installation
# (laeuft.json): Die gilt danach als erledigt, statt beim nächsten zen update fortgesetzt zu werden.

_CODE_KANAL_ZUSTAND=/var/lib/zenos/kanal

modul_system() {
  local quelle ziel von_hand=0
  quelle=$(readlink -f -- "$ZENOS_QUELLE")
  ziel=$(readlink -m -- "$ZENOS_CODE")
  if [[ "${ZENOS_KANAL_LAUF:-}" != 1 && "$ZENOS_IMAGE" != 1 ]]; then von_hand=1; fi
  if [[ "$quelle" != "$ziel" ]]; then
    _code_synchronisieren "$quelle" "$ziel"
    if (( von_hand )); then _code_angehalten "$ziel"; fi
  elif [[ ! -d "$ziel/.git" ]]; then
    abbruch "$ziel ist kein Git-Checkout"
  fi
  if (( von_hand )); then _code_lauf_erledigt; fi
  _code_besitz "$ziel"
  _code_kanal "$ziel"
}

# Stand von Hand: Commit und Zeit für zen kanal status (nichts Persönliches, kein Pfad)
_code_angehalten() {
  local ziel=$1 commit
  commit=$(_code_git_lesen rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) || commit=""
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || return 0
  # Schon so vermerkt: nichts schreiben (der zweite Lauf bleibt ohne Änderung)
  if $SUDO grep -qs -- "\"commit\": \"$commit\"" "$_CODE_KANAL_ZUSTAND/angehalten"; then return 0; fi
  ordner_sicherstellen /var/lib/zenos 0755 root:root
  ordner_sicherstellen "$_CODE_KANAL_ZUSTAND" 0755 root:root
  printf '{"version": 1, "commit": "%s", "zeit": "%s"}\n' "$commit" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" |
    $SUDO tee "$_CODE_KANAL_ZUSTAND/angehalten.neu" > /dev/null
  $SUDO chmod 0644 -- "$_CODE_KANAL_ZUSTAND/angehalten.neu"
  $SUDO mv -f -- "$_CODE_KANAL_ZUSTAND/angehalten.neu" "$_CODE_KANAL_ZUSTAND/angehalten"
  log_info "$ziel stammt jetzt aus einem Arbeitsstand: Der Kanal gilt als angehalten, bis zum nächsten zen update."
}

_code_lauf_erledigt() {
  local datei=$_CODE_KANAL_ZUSTAND/laeuft.json
  $SUDO test -e "$datei" || return 0
  $SUDO rm -f -- "$datei"
  aenderung "Unterbrochene Kanal-Installation gilt als erledigt (install.sh von Hand)"
}

_code_git_quelle() { git -c safe.directory="$_CODE_QUELLE" -C "$_CODE_QUELLE" "$@"; }
_code_git_lesen() { git -c safe.directory="$_CODE_ZIEL" -C "$_CODE_ZIEL" "$@"; }
_code_git_root() { $SUDO git -c advice.detachedHead=false -C "$_CODE_ZIEL" "$@"; }

# Zugangsdaten aus der URL entfernen, GitHub-SSH als HTTPS
_code_url() {
  local url=$1
  if [[ "$url" =~ ^git@github\.com:(.+)$ ]]; then
    url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^ssh://git@github\.com/(.+)$ ]]; then
    url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^(https?://)[^/@]*@(.+)$ ]]; then
    url="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
  printf '%s' "$url"
}

_code_synchronisieren() {
  _CODE_QUELLE=$1
  _CODE_ZIEL=$2
  _CODE_INDEX_NEU=0
  local commit zweig ist ist_zweig

  _code_git_quelle rev-parse --git-dir >/dev/null 2>&1 ||
    abbruch "$_CODE_QUELLE ist kein Git-Checkout. zenOS wird aus einem Git-Klon installiert."
  commit=$(_code_git_quelle rev-parse --verify --quiet 'HEAD^{commit}') ||
    abbruch "$_CODE_QUELLE hat noch keinen Commit"
  zweig=$(_code_git_quelle symbolic-ref --quiet --short HEAD) || zweig=""

  # Checkout anlegen
  if [[ ! -e "$_CODE_ZIEL" ]]; then
    $SUDO install -d -m 0755 -o root -g root "$_CODE_ZIEL"
    _code_git_root init --quiet
    aenderung "$_CODE_ZIEL angelegt"
  elif [[ ! -d "$_CODE_ZIEL/.git" ]]; then
    abbruch "$_CODE_ZIEL existiert, ist aber kein Git-Checkout. Bitte prüfen und von Hand wegräumen."
  fi

  # Commit und Branch. Nur Verweis und Index werden umgestellt, nicht die Dateien: git checkout schreibt sie
  # nicht atomar (löschen, anlegen, schreiben), die laufende Oberfläche sähe halbe Dateien. Die Dateien
  # bringt _code_arbeitsstand auf den Stand der Quelle, auch die, die sich nur durch den Commit ändern.
  ist=$(_code_git_lesen rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) || ist=""
  ist_zweig=""
  if [[ -n "$ist" ]]; then ist_zweig=$(_code_git_lesen symbolic-ref --quiet --short HEAD 2>/dev/null) || ist_zweig=""; fi
  if [[ "$ist" != "$commit" || "$ist_zweig" != "$zweig" ]]; then
    if ! _code_git_lesen cat-file -e "$commit^{commit}" 2>/dev/null; then
      _code_git_root fetch --quiet --no-tags "$_CODE_QUELLE" HEAD
      _code_git_lesen cat-file -e "$commit^{commit}" 2>/dev/null ||
        abbruch "Commit $commit liess sich nicht aus $_CODE_QUELLE holen"
    fi
    if [[ -n "$zweig" ]]; then
      _code_git_lesen check-ref-format --branch "$zweig" >/dev/null || abbruch "Ungültiger Branch in der Quelle: $zweig"
      _code_git_root update-ref "refs/heads/$zweig" "$commit"
      _code_git_root symbolic-ref HEAD "refs/heads/$zweig"
    else
      _code_git_root update-ref --no-deref HEAD "$commit"
    fi
    _code_git_root read-tree "$commit"
    _CODE_INDEX_NEU=1
    aenderung "$_CODE_ZIEL auf ${commit:0:7} (${zweig:-losgelöst})"
  fi

  _code_tags
  _code_origin
  _code_arbeitsstand
  # Index nach read-tree oder übernommenen Dateien auffrischen (sonst gelten alle Dateien als geändert)
  if (( _CODE_INDEX_NEU )); then _code_git_root update-index -q --refresh >/dev/null 2>&1 || true; fi
}

# Tags der Quelle, die in /opt/zenos fehlen oder abweichen, übernehmen (nichts löschen)
_code_tags() {
  local fehlend
  fehlend=$(LC_ALL=C comm -23 \
    <(_code_git_quelle for-each-ref --format='%(refname) %(objectname)' refs/tags | LC_ALL=C sort) \
    <(_code_git_lesen for-each-ref --format='%(refname) %(objectname)' refs/tags | LC_ALL=C sort))
  [[ -n "$fehlend" ]] || return 0
  _code_git_root fetch --quiet --force --no-tags "$_CODE_QUELLE" '+refs/tags/*:refs/tags/*'
  aenderung "Tags übernommen: $(printf '%s\n' "$fehlend" | wc -l | tr -d ' ')"
}

_code_origin() {
  local url ist
  url=$(_code_git_quelle remote get-url origin 2>/dev/null) || url=""
  [[ -n "$url" ]] || return 0
  url=$(_code_url "$url")
  ist=$(_code_git_lesen remote get-url origin 2>/dev/null) || ist=""
  if [[ -z "$ist" ]]; then
    _code_git_root remote add origin "$url"
    aenderung "origin für $_CODE_ZIEL gesetzt"
  elif [[ "$ist" != "$url" ]]; then
    _code_git_root remote set-url origin "$url"
    aenderung "origin für $_CODE_ZIEL angepasst"
  fi
}

# 0, wenn Datei A (Quelle) und B (Ziel) gleich sind: Art, Symlink-Ziel, Ausführbarkeit, Inhalt
_code_gleich() {
  local a=$1 b=$2
  if [[ -L "$a" ]]; then
    [[ -L "$b" && "$(readlink -- "$a")" == "$(readlink -- "$b")" ]]
    return
  fi
  [[ -f "$b" && ! -L "$b" ]] || return 1
  if [[ -x "$a" ]]; then [[ -x "$b" ]] || return 1; else [[ ! -x "$b" ]] || return 1; fi
  cmp -s -- "$a" "$b"
}

# Dateien auf den Stand der Quelle bringen: geänderte (durch den Commit oder nicht committet), neue und
# gelöschte. Jede Datei wird atomar ersetzt: tar packt sie als Benutzer aus der Quelle und entpackt sie als
# root nach .git/zenos-uebernahme (dasselbe Dateisystem, von Quickshell nicht beobachtet), dann setzt ein
# einziger Durchgang sie per rename an ihren Platz, erst neue, dann geänderte, zuletzt werden gelöschte
# entfernt. Die laufende Oberfläche lädt bei jeder geänderten QML-Datei neu; so sieht sie nie eine halbe
# oder fehlende Datei (vorher: «Trenner is not a type»). Einen Mix aus alten und neuen Dateien schliesst
# das nicht ganz aus, dafür startet install.sh sie am Ende neu.
# Übernommene Dateien bekommen die Zeit der Übernahme (tar --touch): Die Sperre erkennt daran nach dem
# Entsperren, dass sich die Oberfläche geändert hat, install.sh am Ende ebenso.
_code_arbeitsstand() {
  local tmp="$ZENOS_TMP/code" pfad
  local -a kopieren=() entfernen=()
  local -A in_quelle=()
  mkdir -p -- "$tmp"

  while IFS= read -r -d '' pfad; do
    [[ -e "$_CODE_QUELLE/$pfad" || -L "$_CODE_QUELLE/$pfad" ]] || continue
    in_quelle[$pfad]=1
    _code_gleich "$_CODE_QUELLE/$pfad" "$_CODE_ZIEL/$pfad" || kopieren+=("$pfad")
  done < <(_code_git_quelle ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -zu)

  while IFS= read -r -d '' pfad; do
    [[ -z "${in_quelle[$pfad]:-}" ]] || continue
    [[ -e "$_CODE_ZIEL/$pfad" || -L "$_CODE_ZIEL/$pfad" ]] || continue
    entfernen+=("$pfad")
  done < <(_code_git_lesen ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -zu)

  (( ${#kopieren[@]} + ${#entfernen[@]} > 0 )) || return 0

  local zwischen="$_CODE_ZIEL/.git/zenos-uebernahme"
  # Rest eines abgebrochenen Laufs
  $SUDO rm -rf -- "$zwischen"
  : > "$tmp/kopieren"
  : > "$tmp/entfernen"
  if (( ${#kopieren[@]} > 0 )); then
    printf '%s\0' "${kopieren[@]}" > "$tmp/kopieren"
    $SUDO install -d -m 0700 -o root -g root -- "$zwischen"
    # Besitz root, Rechte 0644 bzw. 0755, unabhängig von der umask der Quelle
    tar -c -f - -C "$_CODE_QUELLE" --owner=0 --group=0 --numeric-owner --mode='u+rw,go-w,a+rX' \
      --null --no-recursion --files-from="$tmp/kopieren" |
      $SUDO tar -x -f - -C "$zwischen" --no-same-owner --touch
  fi
  if (( ${#entfernen[@]} > 0 )); then printf '%s\0' "${entfernen[@]}" > "$tmp/entfernen"; fi

  if ! $SUDO python3 - "$zwischen" "$_CODE_ZIEL" "$tmp/kopieren" "$tmp/entfernen" <<'PY'; then
import os
import stat
import sys

zwischen, ziel, kopieren, entfernen = sys.argv[1:5]


def liste(datei):
    with open(datei, "rb") as f:
        return [os.fsdecode(p) for p in f.read().split(b"\0") if p]


def pruefen(pfad):
    teile = pfad.split("/")
    if pfad.startswith("/") or any(t in ("", ".", "..") for t in teile) or teile[0] == ".git":
        sys.exit(f"unerwarteter Pfad: {pfad!r}")
    # Kein Verweis unterwegs: sonst landete die Datei ausserhalb des Ziels
    ort = ziel
    for teil in teile[:-1]:
        ort = os.path.join(ort, teil)
        if os.path.islink(ort):
            sys.exit(f"{ort} ist ein Verweis, erwartet war ein Ordner")
    return os.path.join(ziel, pfad)


def ordner_anlegen(ordner):
    if os.path.isdir(ordner):
        return
    ordner_anlegen(os.path.dirname(ordner))
    os.mkdir(ordner, 0o755)
    os.chmod(ordner, 0o755)


def einsetzen(pfad):
    quelle, dort = os.path.join(zwischen, pfad), pruefen(pfad)
    ordner_anlegen(os.path.dirname(dort))
    if os.path.isdir(dort) and not os.path.islink(dort):
        try:
            os.rmdir(dort)  # nur ein leerer Ordner weicht einer Datei
        except OSError:
            sys.exit(f"{dort} ist ein Ordner, erwartet war eine Datei")
    os.replace(quelle, dort)


def uebernehmen():
    neu, alt = [], []
    for pfad in liste(kopieren):
        (alt if os.path.lexists(pruefen(pfad)) else neu).append(pfad)
    for pfad in liste(entfernen):
        pruefen(pfad)
    for pfad in neu + alt:
        einsetzen(pfad)
    for pfad in liste(entfernen):
        dort = pruefen(pfad)
        if os.path.lexists(dort) and not stat.S_ISDIR(os.lstat(dort).st_mode):
            os.unlink(dort)
        # Leere Ordner der gelöschten Datei ebenfalls
        ordner = os.path.dirname(dort)
        while ordner != ziel:
            try:
                os.rmdir(ordner)
            except OSError:
                break
            ordner = os.path.dirname(ordner)


try:
    uebernehmen()
except OSError as e:
    sys.exit(f"{e.filename or ziel}: {e.strerror}")
PY
    $SUDO rm -rf -- "$zwischen"
    abbruch "Arbeitsstand liess sich nicht nach $_CODE_ZIEL übernehmen"
  fi
  $SUDO rm -rf -- "$zwischen"

  # Einzeln melden, bei vielen (erste Installation, neuer Commit) zusammengefasst
  if (( ${#entfernen[@]} > 40 )); then
    aenderung "${#entfernen[@]} Dateien in $_CODE_ZIEL entfernt (fehlen in der Quelle)"
  else
    for pfad in "${entfernen[@]}"; do aenderung "$_CODE_ZIEL/$pfad entfernt (fehlt in der Quelle)"; done
  fi
  if (( ${#kopieren[@]} > 40 )); then
    aenderung "${#kopieren[@]} Dateien aus der Quelle nach $_CODE_ZIEL übernommen"
  else
    for pfad in "${kopieren[@]}"; do aenderung "$_CODE_ZIEL/$pfad (aus der Quelle)"; done
  fi
  _CODE_INDEX_NEU=1
}

# /opt/zenos gehört root:root, Ordner 0755
_code_besitz() {
  local ziel=$1 fremd
  [[ -d "$ziel" ]] || return 0
  fremd=$($SUDO find "$ziel" ! -user root -print -quit 2>/dev/null) || fremd=""
  if [[ -z "$fremd" ]]; then fremd=$($SUDO find "$ziel" ! -group root -print -quit 2>/dev/null) || fremd=""; fi
  if [[ -n "$fremd" ]]; then
    $SUDO chown -R root:root -- "$ziel"
    aenderung "$ziel gehört wieder root:root"
  fi
  if [[ "$(stat -c '%a' -- "$ziel")" != 755 ]]; then
    $SUDO chmod 0755 -- "$ziel"
    aenderung "$ziel auf 0755"
  fi
}

# Kanal für zen update: stabil, vorschau oder dev. Beim ersten Mal ZENOS_KANAL (Image-Bau) oder nach dem Branch (main →
# stabil, sonst dev). Ein alter Wert main heisst jetzt stabil; einen unbekannten lässt es stehen (zenos-kanal meldet ihn
# als «blockiert» und installiert nichts darüber, der Notweg in ANLEITUNG F geht trotzdem).
_code_kanal() {
  local ziel=$1 datei=/etc/xdg/zenos/kanal zweig kanal ist
  if [[ -e "$datei" ]]; then
    ist=$(head -n 1 -- "$datei" 2>/dev/null | tr -d '[:space:]') || ist=""
    case "$ist" in
      stabil | vorschau | dev) ;;
      main)
        printf 'stabil\n' | datei_schreiben "$datei" 0644 root:root
        log_info "Kanal main heisst jetzt stabil"
        ;;
      *) log_warnung "Unbekannter Kanal in $datei (erlaubt: stabil, vorschau, dev): zen update installiert nichts" ;;
    esac
    return 0
  fi
  if [[ -n "${ZENOS_KANAL:-}" ]]; then
    case "$ZENOS_KANAL" in
      stabil | vorschau | dev) kanal=$ZENOS_KANAL ;;
      main) kanal=stabil ;;
      *) abbruch "Ungültiger Kanal in ZENOS_KANAL (erlaubt: stabil, vorschau, dev)" ;;
    esac
  else
    zweig=$(git -c safe.directory="$ziel" -C "$ziel" symbolic-ref --quiet --short HEAD 2>/dev/null) || zweig=""
    if [[ "$zweig" == main ]]; then kanal=stabil; else kanal=dev; fi
  fi
  printf '%s\n' "$kanal" | datei_schreiben "$datei" 0644 root:root
  log_info "Kanal für zen update: $kanal"
}
