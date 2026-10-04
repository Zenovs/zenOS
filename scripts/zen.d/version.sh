#!/usr/bin/env bash
# hilfe: version – zenOS-Version, Basis (Ubuntu), Kanal, Commit, Quickshell, labwc, Architektur
# Die Basis kommt aus der os-release von Ubuntu (/usr/lib/os-release.ubuntu, solange die Kennung zenOS gilt).
# shellcheck shell=bash

befehl_version() {
  local zenos="nicht installiert" kanal commit zweig qs labwc basis arch

  if zen_git rev-parse --git-dir >/dev/null 2>&1; then
    zenos=$(zenos_version "$ZENOS_CODE")
    commit=$(zen_git rev-parse --short HEAD 2>/dev/null) || commit="?"
    zweig=$(zen_git symbolic-ref --quiet --short HEAD 2>/dev/null) || zweig="losgelöst"
    commit="$commit ($zweig)"
  else
    commit="–"
  fi

  kanal=$(_version_kanal)

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
    Quickshell "$qs" \
    labwc "$labwc" \
    Architektur "$arch"
}

_version_kanal() {
  local k
  if [[ -r /etc/xdg/zenos/kanal ]]; then
    k=$(head -n 1 /etc/xdg/zenos/kanal | tr -d '[:space:]')
    printf '%s' "${k:-dev}"
  else
    printf 'dev (Standard)'
  fi
}
