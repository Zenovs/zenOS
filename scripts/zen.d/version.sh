#!/usr/bin/env bash
# hilfe: version – zenOS-Version, Basis (Ubuntu), Kanal, Commit, Update, Quickshell, labwc, Architektur
# Die Basis kommt aus der os-release von Ubuntu (/usr/lib/os-release.ubuntu, solange die Kennung zenOS gilt). «Update»
# ist der letzte Stand der Installation über den Kanal (zen kanal status zeigt mehr).
# shellcheck shell=bash

befehl_version() {
  local zenos="nicht installiert" kanal commit zweig qs labwc basis arch update

  if zen_git rev-parse --git-dir >/dev/null 2>&1; then
    zenos=$(zenos_version "$ZENOS_CODE")
    commit=$(zen_git rev-parse --short HEAD 2>/dev/null) || commit="?"
    zweig=$(zen_git symbolic-ref --quiet --short HEAD 2>/dev/null) || zweig="losgelöst"
    commit="$commit ($zweig)"
  else
    commit="–"
  fi

  kanal=$(_version_kanal)
  update=$(_version_update)

  qs="nicht installiert"
  if [[ -r /usr/local/share/zenos/quickshell.version ]]; then
    local v c
    v=$(sed -n 's/^version=//p' /usr/local/share/zenos/quickshell.version | head -n 1)
    c=$(sed -n 's/^commit=//p' /usr/local/share/zenos/quickshell.version | head -n 1)
    qs="${v:-?}${c:+ (${c:0:7})}"
  elif befehl_vorhanden quickshell; then
    qs=$(quickshell --version 2>/dev/null | head -n 1) || qs="?"
  fi

  labwc="nicht installiert"
  if befehl_vorhanden labwc; then
    labwc=$(labwc --version 2>/dev/null | awk 'NR == 1 { print $2 }') || labwc="?"
  fi

  basis=$(os_release_wert PRETTY_NAME "$(basis_os_release)")
  arch=$(dpkg --print-architecture 2>/dev/null || uname -m)

  printf '%-12s %s\n' \
    zenOS "$zenos" \
    Basis "${basis:-?}" \
    Kanal "$kanal" \
    Commit "$commit" \
    Update "$update" \
    Quickshell "$qs" \
    labwc "$labwc" \
    Architektur "$arch"
}

_version_kanal() {
  local k
  if [[ -r /etc/xdg/zenos/kanal ]]; then
    k=$(head -n 1 /etc/xdg/zenos/kanal | tr -d '[:space:]')
    case "$k" in
      "") printf 'dev (Standard)' ;;
      main) printf 'stabil (main)' ;;
      stabil | vorschau | dev) printf '%s' "$k" ;;
      *) printf '%s (unbekannt, zen update installiert nichts)' "$k" ;;
    esac
  else
    printf 'dev (Standard)'
  fi
}

# Installation über den Kanal in einer Zeile (ohne root lesbar)
_version_update() {
  local programm=/usr/local/libexec/zenos/zenos-kanal zeile
  if [[ ! -f "$programm" ]]; then
    printf 'ohne Kanal'
    return 0
  fi
  zeile=$(/usr/bin/python3 -I "$programm" status --installation 2>/dev/null | head -n 1) || zeile=""
  if [[ "$zeile" == *" "* ]]; then printf '%s' "${zeile#* }"; else printf '–'; fi
}
