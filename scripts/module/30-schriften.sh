#!/usr/bin/env bash
# 30-schriften: Geist, Geist Mono und Instrument Serif mit Lizenztexten nach /usr/local/share/fonts/zenos
# shellcheck shell=bash
#
# Quelle: assets/fonts/*.ttf und die OFL-Texte (Herkunft und Prüfsummen in assets/fonts/QUELLEN.md).
# Der Ordner /usr/local/share/fonts/zenos gehört zenOS: Dateien, die im Repo nicht mehr liegen, werden
# entfernt. fc-cache läuft nur nach einer Änderung.

modul_system() {
  local quelle="$ZENOS_CODE/assets/fonts" ziel=/usr/local/share/fonts/zenos datei name
  local -A soll=()

  if ! compgen -G "$quelle/*.ttf" >/dev/null; then
    log_warnung "Keine Schriften unter $quelle gefunden"
    return 0
  fi

  # Den Ordner legt datei_installieren an. Kein erzwungener Modus: /usr/local/share/fonts ist unter
  # Ubuntu setgid (2775 root:staff), neue Unterordner erben das Bit.
  for datei in "$quelle"/*.ttf "$quelle"/OFL*.txt "$quelle"/QUELLEN.md; do
    [[ -f "$datei" ]] || continue
    name=$(basename -- "$datei")
    soll[$name]=1
    datei_installieren "$datei" "$ziel/$name" 0644 root:root
  done

  # Was nicht mehr im Repo liegt, kommt weg
  for datei in "$ziel"/*; do
    [[ -e "$datei" || -L "$datei" ]] || continue
    name=$(basename -- "$datei")
    [[ -n "${soll[$name]:-}" ]] && continue
    if [[ -d "$datei" && ! -L "$datei" ]]; then
      log_warnung "Unerwarteter Ordner $datei (bitte von Hand prüfen)"
      continue
    fi
    datei_entfernen "$datei"
  done

  if modul_geaendert; then
    if befehl_vorhanden fc-cache; then
      $SUDO fc-cache -f "$ziel" >/dev/null 2>&1 || log_warnung "fc-cache ist fehlgeschlagen"
      $SUDO fc-cache >/dev/null 2>&1 || true
      log_info "Schriften-Cache aktualisiert"
    else
      log_warnung "fc-cache fehlt (Paket fontconfig), Schriften erscheinen erst nach dem nächsten Lauf"
    fi
  fi
}
