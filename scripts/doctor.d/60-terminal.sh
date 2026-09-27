#!/usr/bin/env bash
# 60-terminal: kitty, fish, Werkzeuge, tldr-Seiten und man-Seiten für «?»
# shellcheck shell=bash

pruefe_terminal() {
  abschnitt "Terminal"
  _terminal_programme
  _terminal_verknuepfungen
  _terminal_farben
  _terminal_schrift
  _terminal_werkzeuge
  _terminal_hilfen
}

_terminal_version() { "$@" 2>/dev/null | head -n 1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1; }

_terminal_programme() {
  if command -v kitty >/dev/null 2>&1; then
    ok "kitty $(_terminal_version kitty --version)"
  else
    fehler "kitty fehlt (Paket kitty)"
  fi
  if command -v fish >/dev/null 2>&1; then
    ok "fish $(_terminal_version fish --version) · startet in kitty direkt, die Login-Shell bleibt unverändert"
  else
    fehler "fish fehlt (Paket fish)"
  fi
  if [[ -d /usr/lib/kitty/shell-integration/fish ]]; then
    ok "Shell-Integration von kitty vorhanden (Sprung zwischen Befehlen, schlaues Ctrl+C)"
  else
    warnung "Shell-Integration von kitty fehlt (Paket kitty-shell-integration)"
  fi
}

# Verknüpfung auf den Code-Checkout; eine eigene Datei ist ein Hinweis, kein Fehler
_terminal_link() { # ZIEL QUELLE NAME
  local ziel=$1 quelle=$2 name=$3
  if [[ -L "$ziel" && "$(readlink -- "$ziel")" == "$quelle" ]]; then
    if [[ -e "$ziel" ]]; then
      ok "$name verknüpft"
    else
      fehler "$name zeigt ins Leere (${quelle}) – ./scripts/install.sh ausführen"
    fi
  elif [[ -e "$ziel" || -L "$ziel" ]]; then
    warnung "$name ist eine eigene Datei, nicht die von zenOS (${ziel/#"$HOME"/\~}); zen benutzer stellt sie wieder her"
  else
    warnung "$name fehlt – zen benutzer ausführen"
  fi
}

_terminal_verknuepfungen() {
  _terminal_link "$HOME/.config/kitty/kitty.conf" /opt/zenos/system/kitty/kitty.conf "kitty.conf"
  _terminal_link "$HOME/.config/fish/conf.d/zenos.fish" /opt/zenos/system/fish/zenos.fish "fish-Einstellungen"
}

# Farbdateien von zenos-thema (kitty wählt sie selbst nach hell/dunkel)
_terminal_farben() {
  local ordner=$HOME/.config/kitty datei fehlend=()
  for datei in dark-theme.auto.conf light-theme.auto.conf; do
    [[ -f "$ordner/$datei" ]] || fehlend+=("$datei")
  done
  if (( ${#fehlend[@]} == 0 )); then
    ok "kitty-Farben aus den Design-Tokens (hell und dunkel)"
  else
    warnung "kitty-Farben fehlen (${fehlend[*]}); kitty zeigt seine Grundfarben – zen thema wechseln oder zen benutzer"
  fi
}

_terminal_schrift() {
  if ! command -v fc-list >/dev/null 2>&1; then
    hinweis "Schrift nicht prüfbar (fc-list fehlt)"
  elif fc-list 'Geist Mono' family 2>/dev/null | grep -q .; then
    ok "Schrift Geist Mono vorhanden"
  else
    warnung "Schrift Geist Mono fehlt, kitty nimmt eine Ersatzschrift (./scripts/install.sh, Modul 30-schriften)"
  fi
}

_terminal_werkzeuge() {
  local befehl fehlend=() da=()
  for befehl in eza zoxide fzf tldr man; do
    if command -v "$befehl" >/dev/null 2>&1; then da+=("$befehl"); else fehlend+=("$befehl"); fi
  done
  if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then da+=(bat); else fehlend+=(bat); fi
  if (( ${#fehlend[@]} == 0 )); then
    ok "Werkzeuge: ${da[*]}"
  else
    warnung "Werkzeuge fehlen: ${fehlend[*]} (./scripts/install.sh installiert sie)"
  fi
}

# «?» braucht die tldr-Seiten und die man-Seiten
_terminal_hilfen() {
  local cache=${TEALDEER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer}/tldr-pages alter
  if [[ -d "$cache/pages.en" ]]; then
    alter=$(( ($(date +%s) - $(stat -c %Y -- "$cache")) / 86400 ))
    if [[ -d "$cache/pages.de" ]]; then
      ok "tldr-Seiten für «?» vorhanden (Deutsch und Englisch, Stand vor $alter Tagen)"
    else
      hinweis "tldr-Seiten nur auf Englisch (Deutsch laden: LANGUAGE=de:en tldr --update)"
    fi
  else
    hinweis "tldr-Seiten für «?» noch nicht geladen (mit Internet: tldr --update)"
  fi
  # Minimierte Ubuntu-Systeme ersetzen man durch einen Hinweis und lassen die Seiten weg
  if dpkg-divert --list /usr/bin/man 2>/dev/null | grep -q 'man.REAL'; then
    hinweis "man-Seiten fehlen (minimiertes System); «?» erklärt dann keine Optionen. Wiederherstellen: sudo unminimize"
  elif [[ -e /usr/share/man/man1/man.1.gz ]]; then
    ok "man-Seiten vorhanden"
  else
    hinweis "man-Seiten fehlen; «?» erklärt dann keine Optionen"
  fi
}
