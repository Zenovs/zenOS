#!/usr/bin/env bash
# 10-code: /opt/zenos als Git-Checkout auf den Arbeitsstand der Quelle bringen, Kanal festlegen
# shellcheck shell=bash
#
# Läuft install.sh aus einem anderen Checkout (z. B. ~/zenOS), bekommt /opt/zenos genau dessen Stand:
# Commit und Branch (per git fetch), Tags, origin (GitHub-URL der Quelle, ohne Zugangsdaten, SSH als
# HTTPS, weil root keinen SSH-Schlüssel hat), dazu nicht committete und neue, nicht ignorierte Dateien.
# In der Quelle gelöschte Dateien verschwinden auch in /opt/zenos. Läuft install.sh aus /opt/zenos
# selbst (zen update), wird nichts synchronisiert.

modul_system() {
  local quelle ziel
  quelle=$(readlink -f -- "$ZENOS_QUELLE")
  ziel=$(readlink -m -- "$ZENOS_CODE")
  if [[ "$quelle" != "$ziel" ]]; then
    _code_synchronisieren "$quelle" "$ziel"
  elif [[ ! -d "$ziel/.git" ]]; then
    abbruch "$ziel ist kein Git-Checkout"
  fi
  _code_besitz "$ziel"
  _code_kanal "$ziel"
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

  # Commit und Branch
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
      _code_git_root checkout --quiet --force -B "$zweig" "$commit"
    else
      _code_git_root checkout --quiet --force --detach "$commit"
    fi
    aenderung "$_CODE_ZIEL auf ${commit:0:7} (${zweig:-losgelöst})"
  fi

  _code_tags
  _code_origin
  _code_arbeitsstand
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

# Nicht committete, neue und gelöschte Dateien übernehmen
_code_arbeitsstand() {
  local tmp="$ZENOS_TMP/code" pfad ordner
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

  if (( ${#entfernen[@]} > 0 )); then
    for pfad in "${entfernen[@]}"; do
      $SUDO rm -f -- "$_CODE_ZIEL/$pfad"
      ordner=$(dirname -- "$pfad")
      if [[ "$ordner" != . ]]; then
        (cd -- "$_CODE_ZIEL" && $SUDO rmdir -p --ignore-fail-on-non-empty -- "$ordner" 2>/dev/null) || true
      fi
      aenderung "$_CODE_ZIEL/$pfad entfernt (fehlt in der Quelle)"
    done
  fi

  if (( ${#kopieren[@]} > 0 )); then
    printf '%s\0' "${kopieren[@]}" > "$tmp/liste"
    # Besitz root, Rechte 0644 bzw. 0755, unabhängig von der umask der Quelle
    tar -c -f - -C "$_CODE_QUELLE" --owner=0 --group=0 --numeric-owner --mode='u+rw,go-w,a+rX' \
      --null --no-recursion --files-from="$tmp/liste" |
      $SUDO tar -x -f - -C "$_CODE_ZIEL" --no-same-owner
    for pfad in "${kopieren[@]}"; do
      aenderung "$_CODE_ZIEL/$pfad (aus dem Arbeitsstand)"
    done
  fi

  _code_git_root update-index -q --refresh >/dev/null 2>&1 || true
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

# Kanal für zen update, nur beim ersten Mal: main → main, sonst dev (oder ZENOS_KANAL für den Image-Bau)
_code_kanal() {
  local ziel=$1 datei=/etc/xdg/zenos/kanal zweig kanal
  [[ -e "$datei" ]] && return 0
  if [[ -n "${ZENOS_KANAL:-}" ]]; then
    [[ "$ZENOS_KANAL" =~ ^[A-Za-z0-9._/-]+$ ]] || abbruch "Ungültiger Kanal in ZENOS_KANAL"
    kanal=$ZENOS_KANAL
  else
    zweig=$(git -c safe.directory="$ziel" -C "$ziel" symbolic-ref --quiet --short HEAD 2>/dev/null) || zweig=""
    if [[ "$zweig" == main ]]; then kanal=main; else kanal=dev; fi
  fi
  printf '%s\n' "$kanal" | datei_schreiben "$datei" 0644 root:root
  log_info "Kanal für zen update: $kanal"
}
