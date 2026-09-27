#!/usr/bin/env bash
# hilfe: update – neuen Stand vom Kanal holen und installieren
# Holt in /opt/zenos «git fetch --tags --prune» von origin, setzt den Checkout hart auf
# origin/<kanal> (Kanal aus /etc/xdg/zenos/kanal, Standard dev), räumt unversionierte Dateien weg
# und führt danach /opt/zenos/scripts/install.sh aus. Lokale Änderungen in /opt/zenos gehen verloren;
# ein Rollback-Stand endet damit wieder auf dem Kanal.
# shellcheck shell=bash

befehl_update() {
  if (( $# > 0 )); then
    zen_fehler "zen update kennt keine Argumente"
    return 2
  fi
  _update_bereit || return 1

  local kanal alt alt_commit neu neu_commit
  kanal=$(_update_kanal) || return 1
  alt=$(zenos_version "$ZENOS_CODE")
  alt_commit=$(zen_git rev-parse --short HEAD 2>/dev/null) || alt_commit="?"

  if [[ -n "$(zen_git status --porcelain 2>/dev/null)" ]]; then
    zen_hinweis "Lokale Änderungen in $ZENOS_CODE werden verworfen."
  fi

  zen_hinweis "Hole Stand von origin (Kanal $kanal) …"
  zen_git_root fetch --quiet --tags --prune origin || { zen_fehler "git fetch ist fehlgeschlagen"; return 1; }
  if ! zen_git rev-parse --verify --quiet "refs/remotes/origin/$kanal^{commit}" >/dev/null; then
    zen_fehler "Den Kanal «$kanal» gibt es auf origin nicht (siehe /etc/xdg/zenos/kanal)"
    return 1
  fi
  zen_git_root checkout --quiet --force -B "$kanal" "refs/remotes/origin/$kanal"
  zen_git_root reset --quiet --hard "refs/remotes/origin/$kanal"
  zen_git_root clean --quiet -fd

  neu=$(zenos_version "$ZENOS_CODE")
  neu_commit=$(zen_git rev-parse --short HEAD)
  if [[ "$alt_commit" == "$neu_commit" && "$alt" == "$neu" ]]; then
    zen_hinweis "Schon aktuell: $neu ($neu_commit)"
  else
    zen_hinweis "$alt ($alt_commit) → $neu ($neu_commit)"
  fi
  zen_hinweis ""
  "$ZENOS_CODE/scripts/install.sh"
}

_update_bereit() {
  if ! zen_git rev-parse --git-dir >/dev/null 2>&1; then
    zen_fehler "$ZENOS_CODE ist nicht installiert. Zuerst im Repo ./scripts/install.sh ausführen."
    return 1
  fi
  if ! zen_git remote get-url origin >/dev/null 2>&1; then
    zen_fehler "$ZENOS_CODE hat kein origin. install.sh aus einem Klon von GitHub ausführen."
    return 1
  fi
}

_update_kanal() {
  local kanal=dev
  if [[ -r /etc/xdg/zenos/kanal ]]; then
    kanal=$(head -n 1 /etc/xdg/zenos/kanal | tr -d '[:space:]')
    [[ -n "$kanal" ]] || kanal=dev
  fi
  if [[ ! "$kanal" =~ ^[A-Za-z0-9._/-]+$ ]] || ! git check-ref-format "refs/heads/$kanal"; then
    zen_fehler "Ungültiger Kanal in /etc/xdg/zenos/kanal"
    return 1
  fi
  printf '%s' "$kanal"
}
