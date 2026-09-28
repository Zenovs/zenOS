#!/usr/bin/env bash
# 42-bootsplash: Bootsplash-Theme (Plymouth) nach /usr/share/plymouth/themes/zenos, ohne es einzuschalten
# shellcheck shell=bash
#
# Kopiert nur die Theme-Dateien aus system/plymouth/zenos (zenos.plymouth, zenos.script, bilder/). Das Modul setzt
# kein Standard-Theme, baut kein initramfs und ändert die Boot-Kommandozeile nicht: Das ist Bootloader-Gebiet und
# läuft nur mit «zen bootsplash aktivieren» nach Rückfrage. Auch plymouth und plymouth-label installiert erst das
# (scripts/pakete/bootsplash.txt): Der postinst von plymouth stösst update-initramfs an, auf dem Pi schreibt
# flash-kernel danach neue Startdateien nach /boot/firmware/new/.

modul_system() {
  local quelle=$ZENOS_CODE/system/plymouth/zenos ziel=/usr/share/plymouth/themes/zenos rel ordner
  local -a dateien=() vorhanden=() leer=()
  local -A soll=() ordner_soll=()

  if [[ ! -f "$quelle/zenos.plymouth" ]]; then
    log_warnung "Bootsplash-Theme fehlt unter $quelle"
    return 0
  fi
  # Nur, was Plymouth braucht: Alles im Theme-Ordner landet auch im initramfs (erzeugen.py bleibt weg)
  mapfile -t dateien < <(find "$quelle" -type f \( -name '*.plymouth' -o -name '*.script' -o -name '*.png' \) \
    -printf '%P\n' | LC_ALL=C sort)

  for rel in "${dateien[@]}"; do
    soll[$rel]=1
    ordner=$rel
    while [[ "$ordner" == */* ]]; do
      ordner=${ordner%/*}
      ordner_soll[$ordner]=1
    done
  done
  ordner_sicherstellen "$ziel" 0755 root:root
  while IFS= read -r ordner; do
    [[ -n "$ordner" ]] && ordner_sicherstellen "$ziel/$ordner" 0755 root:root
  done < <(printf '%s\n' "${!ordner_soll[@]}" | LC_ALL=C sort)
  for rel in "${dateien[@]}"; do
    datei_installieren "$quelle/$rel" "$ziel/$rel" 0644 root:root
  done

  # Was nicht mehr zum Theme gehört (umbenannte oder entfernte Bilder), kommt weg
  mapfile -t vorhanden < <(find "$ziel" -type f -printf '%P\n' | LC_ALL=C sort)
  for rel in "${vorhanden[@]}"; do
    [[ -n "${soll[$rel]:-}" ]] || datei_entfernen "$ziel/$rel"
  done
  mapfile -t leer < <($SUDO find "$ziel" -mindepth 1 -type d -empty -printf '%P\n' -delete)
  for ordner in "${leer[@]}"; do
    aenderung "entfernt: $ziel/$ordner"
  done

  modul_geaendert || return 0
  if [[ "$(_bootsplash_standard)" == "$ziel/zenos.plymouth" ]]; then
    log_info "Hinweis: Der Bootsplash ist eingeschaltet; das geänderte Theme kommt mit dem nächsten initramfs (zen bootsplash aktivieren)."
  else
    log_info "Hinweis: Bootsplash vorbereitet, nicht aktiv (zen bootsplash aktivieren, Bootloader: nur nach Rückfrage)."
  fi
}

# Theme, auf das default.plymouth zeigt (leer, wenn keins gesetzt ist); nur lesen
_bootsplash_standard() {
  update-alternatives --query default.plymouth 2> /dev/null | sed -n 's/^Value: //p'
}
