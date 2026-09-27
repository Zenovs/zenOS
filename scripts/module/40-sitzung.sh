#!/usr/bin/env bash
# 40-sitzung: Login (greetd mit zenOS-Greeter), Sitzung (labwc, systemd-Benutzereinheiten), Portale
# shellcheck shell=bash
#
# greetd wird nur aktiviert, nie gestartet: Der grafische Login erscheint erst nach dem Neustart, eine
# laufende SSH-Sitzung bleibt unberührt. Standardziel ist graphical.target.
# Die Benutzereinheiten liegen in /etc/systemd/user: systemd 259 sucht /etc/xdg/systemd/user nur, wenn
# XDG_CONFIG_DIRS gesetzt ist (in der Benutzerinstanz nicht). Ubuntu verweist /etc/xdg/systemd/user auf
# /etc/systemd/user; install -D aus uutils (Ubuntu 26.04) ersetzt diesen Verweis durch einen Ordner.
# Das Modul stellt ihn wieder her. labwc bekommt autostart, environment und shutdown als Verweise.

modul_system() {
  local code=$ZENOS_CODE einheit

  datei_installieren "$code/system/greetd/config.toml" /etc/greetd/config.toml 0644 root:root
  _sitzung_greetd_aktivieren
  _sitzung_standardziel

  _sitzung_xdg_verweis
  for einheit in zenos-sitzung.target zenos-shell.service; do
    datei_installieren "$code/system/systemd/user/$einheit" "/etc/systemd/user/$einheit" 0644 root:root
  done

  datei_installieren "$code/system/portal/labwc-portals.conf" \
    /etc/xdg/xdg-desktop-portal/labwc-portals.conf 0644 root:root
}

modul_benutzer() {
  local ordner=$ZENOS_HOME/.config/labwc datei
  benutzer_ordner_sicherstellen "$ordner"
  for datei in autostart environment shutdown; do
    verknuepfen "$ZENOS_CODE/system/labwc/$datei" "$ordner/$datei"
  done
}

# greetd aktivieren (display-manager.service), ausser ein anderer Anmeldedienst ist schon eingerichtet
_sitzung_greetd_aktivieren() {
  local dm=/etc/systemd/system/display-manager.service ziel
  if [[ ! -e /usr/lib/systemd/system/greetd.service && ! -e /lib/systemd/system/greetd.service ]]; then
    log_warnung "greetd.service fehlt (Paket greetd), Login nicht eingerichtet"
    return 0
  fi
  if [[ -L "$dm" ]]; then
    ziel=$(basename -- "$(readlink -- "$dm")")
    if [[ "$ziel" != greetd.service ]]; then
      log_warnung "Anderer Anmeldedienst aktiv ($ziel), greetd bleibt aus. Wechsel: sudo systemctl disable $ziel, dann install.sh"
      return 0
    fi
  fi
  dienst_aktivieren greetd.service
}

_sitzung_standardziel() {
  local ist
  ist=$(systemctl get-default 2> /dev/null) || ist=""
  [[ "$ist" == graphical.target ]] && return 0
  $SUDO systemctl set-default graphical.target > /dev/null 2>&1 ||
    abbruch "Standardziel graphical.target liess sich nicht setzen"
  aenderung "Standardziel graphical.target (vorher ${ist:-unbekannt})"
}

# /etc/xdg/systemd/user ist im systemd-Paket ein Verweis auf ../../systemd/user. Wurde er durch einen
# Ordner ersetzt (install -D von uutils), kommen die zenOS-Einheiten daraus nach /etc/systemd/user
# und der Verweis zurück. Fremde Dateien darin bleiben unangetastet (dann nur eine Warnung).
_sitzung_xdg_verweis() {
  local xdg=/etc/xdg/systemd/user ziel=/etc/systemd/user datei name
  [[ -d "$xdg" && ! -L "$xdg" && -d "$ziel" ]] || return 0
  for datei in "$xdg"/* "$xdg"/.[!.]*; do
    [[ -e "$datei" || -L "$datei" ]] || continue
    name=$(basename -- "$datei")
    if [[ "$name" != zenos-* || ! -f "$datei" || -L "$datei" ]]; then
      log_warnung "$xdg ist ein Ordner statt eines Verweises auf $ziel und enthält $name – bitte von Hand prüfen"
      return 0
    fi
  done
  for datei in "$xdg"/zenos-*; do
    [[ -f "$datei" ]] || continue
    $SUDO mv -f -- "$datei" "$ziel/"
  done
  $SUDO rmdir -- "$xdg"
  $SUDO ln -s ../../systemd/user "$xdg"
  # systemd-Benutzerinstanz neu laden lassen (Merker der lib, sonst reicht der nächste Lauf)
  if declare -F _zenos_unit_merken > /dev/null; then _zenos_unit_merken "$ziel/"; fi
  aenderung "$xdg wieder als Verweis auf $ziel (wie im systemd-Paket)"
}
