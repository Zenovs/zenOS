#!/usr/bin/env bash
# 60-terminal: kitty und fish verknüpfen, tldr-Seiten für «?» laden
# shellcheck shell=bash
#
# Die Pakete (scripts/pakete/terminal.txt) installiert 20-pakete. Die Login-Shell bleibt, wie sie ist:
# kitty startet fish direkt (shell in kitty.conf); chsh gehört zu «Benutzer und Passwörter» und
# braucht eine Rückfrage. Die Farben für kitty schreibt zenos-thema (45-thema).

modul_benutzer() {
  verknuepfen "$ZENOS_CODE/system/kitty/kitty.conf" "$ZENOS_HOME/.config/kitty/kitty.conf"
  verknuepfen "$ZENOS_CODE/system/fish/zenos.fish" "$ZENOS_HOME/.config/fish/conf.d/zenos.fish"
  _terminal_tldr_laden
}

# tldr-Seiten (Deutsch und Englisch) einmal laden, danach höchstens alle 30 Tage. Läuft install.sh im
# Terminal, sofort; sonst (Sitzungsstart, Image-System beim ersten Login) im Hintergrund, damit die
# Anmeldung nie auf das Netz wartet. Ohne Netz nur ein Hinweis: «?» erklärt dann, wie man sie lädt.
_terminal_tldr_laden() {
  befehl_vorhanden tldr || return 0
  local cache=${TEALDEER_CACHE_DIR:-${XDG_CACHE_HOME:-$ZENOS_HOME/.cache}/tealdeer}/tldr-pages
  if [[ -d "$cache/pages.de" && -d "$cache/pages.en" ]] &&
    [[ -z "$(find "$cache" -maxdepth 0 -mtime +30 -print 2>/dev/null)" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    if LANG=de_DE.UTF-8 LANGUAGE=de:en timeout 60 tldr --quiet --update >/dev/null 2>&1; then
      aenderung "tldr-Seiten geladen (Deutsch und Englisch)"
    else
      log_info "tldr-Seiten nicht geladen (kein Netz?). Später im Terminal: tldr --update"
    fi
  elif [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]] && befehl_vorhanden setsid && befehl_vorhanden flock; then
    # Eine Sperre verhindert doppelte Downloads, falls die Sitzung mehrmals startet
    setsid -f flock -n "$XDG_RUNTIME_DIR/zenos-tldr.lock" \
      env LANG=de_DE.UTF-8 LANGUAGE=de:en timeout 120 tldr --quiet --update >/dev/null 2>&1 < /dev/null
    log_info "tldr-Seiten werden im Hintergrund geladen"
  else
    log_info "tldr-Seiten fehlen noch. Im Terminal: tldr --update"
  fi
}
