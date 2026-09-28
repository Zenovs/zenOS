#!/usr/bin/env bash
# 42-bootsplash: Bootsplash-Theme (Plymouth) installiert und aktuell, eingeschaltet oder nur vorbereitet
# shellcheck shell=bash
#
# Nur lesen. Nicht eingeschaltet ist der Normalfall (Bootloader-Gebiet, nur nach Rückfrage) und ein Hinweis.

pruefe_bootsplash() {
  abschnitt "Bootsplash"
  # shellcheck source=../zen.d/bootsplash.sh
  source "$ZEN_SKRIPTE/zen.d/bootsplash.sh" || { fehler "zen.d/bootsplash.sh nicht ladbar"; return 0; }
  _bootsplash_theme
  case "$(_bootsplash_zustand)" in
    aktiv)
      ok "Bootsplash eingeschaltet (Theme zenos, «splash» in $(_bootsplash_datei))"
      if _bootsplash_initramfs_alt; then
        hinweis "Das initramfs ist älter als das Theme, beim Start erscheint noch der alte Stand (zen bootsplash aktivieren)"
      fi
      ;;
    vorbereitet) hinweis "Bootsplash vorbereitet, nicht aktiv (zen bootsplash aktivieren nach Rückfrage)" ;;
    teilweise) hinweis "Bootsplash teilweise eingeschaltet (zen bootsplash status)" ;;
  esac
}

_bootsplash_theme() {
  local quelle=/opt/zenos/system/plymouth/zenos anzahl
  local -a abweichungen=()
  if [[ ! -f "$_BOOTSPLASH_THEME" ]]; then
    warnung "Bootsplash-Theme fehlt unter $_BOOTSPLASH_ORDNER (install.sh ausführen)"
    return 0
  fi
  if [[ -d "$quelle" ]]; then
    mapfile -t abweichungen < <(_bootsplash_abweichungen "$quelle")
  fi
  anzahl=${#abweichungen[@]}
  if (( anzahl > 0 )); then
    warnung "Bootsplash-Theme weicht in $anzahl Datei(en) von /opt/zenos ab (install.sh ausführen)"
  else
    ok "Bootsplash-Theme installiert ($_BOOTSPLASH_ORDNER)"
  fi
}
