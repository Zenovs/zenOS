#!/usr/bin/env bash
# hilfe: rollback <tag> – zu einem getaggten Stand zurück und installieren
# Holt vorher neue Tags von origin (falls erreichbar, Zeitlimit 180 s), setzt /opt/zenos auf den Tag (losgelöst)
# und führt install.sh aus. Vorhandene Tags bleiben, wie sie sind: Wurde ein Tag auf origin verschoben, nimmt
# rollback den Stand, den das Gerät unter diesem Namen kennt (mit Warnung). Bricht ab, ohne etwas zu ändern, wenn
# weniger als 1 GB frei ist. Das nächste «zen update» kehrt auf den Kanal zurück.
# shellcheck shell=bash

# shellcheck source=../lib/wechsel.sh
source "$ZEN_SKRIPTE/lib/wechsel.sh"

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
  _wechsel_sperren || return 1
  _wechsel_platz "$ZENOS_CODE" || return 1

  if zen_git remote get-url origin >/dev/null 2>&1; then
    _wechsel_tags_holen
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
  _wechsel_install_warten || return 1
  if ! zen_git_root checkout --quiet --force --detach "refs/tags/$tag" ||
    ! zen_git_root clean --quiet -fd; then
    _wechsel_install_freigeben
    zen_fehler "Der Wechsel auf $tag ist gescheitert, $ZENOS_CODE ist womöglich nur halb umgestellt. Notweg: ANLEITUNG.md, Abschnitt F («zen update bricht ab»)."
    return 1
  fi
  _wechsel_install_freigeben
  neu=$(zenos_version "$ZENOS_CODE")
  neu_commit=$(zen_git rev-parse --short HEAD)
  zen_hinweis "$alt ($alt_commit) → $neu ($neu_commit)"
  zen_hinweis "Zurück auf den Kanal mit: zen update"
  zen_hinweis ""
  # Ohne die Sperren-Deskriptoren: Die Kanal-Sperre hält zen selbst bis zum Ende, install.sh nimmt seine eigene
  "$ZENOS_CODE/scripts/install.sh" 7<&- 8<&-
}
