#!/usr/bin/env bash
# hilfe: rollback <tag> – zu einem getaggten Stand zurück und installieren
# Holt vorher die Tags von origin (falls erreichbar), setzt /opt/zenos auf den Tag (losgelöst) und
# führt install.sh aus. Das nächste «zen update» kehrt auf den Kanal zurück.
# shellcheck shell=bash

befehl_rollback() {
  if (( $# != 1 )); then
    zen_fehler "Aufruf: zen rollback <tag>"
    return 2
  fi
  local tag=$1 alt alt_commit neu neu_commit
  if [[ "$tag" == -* ]] || ! git check-ref-format "refs/tags/$tag"; then
    zen_fehler "Ungültiger Tag-Name «$tag»"
    return 2
  fi
  if ! zen_git rev-parse --git-dir >/dev/null 2>&1; then
    zen_fehler "$ZENOS_CODE ist nicht installiert."
    return 1
  fi

  if zen_git remote get-url origin >/dev/null 2>&1; then
    zen_git_root fetch --quiet --tags --prune origin ||
      zen_hinweis "origin nicht erreichbar, nutze die vorhandenen Tags."
  fi
  if ! zen_git rev-parse --verify --quiet "refs/tags/$tag^{commit}" >/dev/null; then
    zen_fehler "Den Tag «$tag» gibt es nicht."
    local tags
    tags=$(zen_git tag --sort=-creatordate | head -n 10 | paste -sd ' ' -)
    [[ -z "$tags" ]] || printf 'Vorhandene Tags (neueste zuerst): %s\n' "$tags" >&2
    return 1
  fi

  alt=$(zenos_version "$ZENOS_CODE")
  alt_commit=$(zen_git rev-parse --short HEAD 2>/dev/null) || alt_commit="?"
  zen_git_root checkout --quiet --force --detach "refs/tags/$tag"
  zen_git_root clean --quiet -fd
  neu=$(zenos_version "$ZENOS_CODE")
  neu_commit=$(zen_git rev-parse --short HEAD)
  zen_hinweis "$alt ($alt_commit) → $neu ($neu_commit)"
  zen_hinweis "Zurück auf den Kanal mit: zen update"
  zen_hinweis ""
  "$ZENOS_CODE/scripts/install.sh"
}
