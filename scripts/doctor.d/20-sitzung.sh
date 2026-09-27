#!/usr/bin/env bash
# 20-sitzung: Pakete, Quickshell (Stempel und Qt), Schriften, Login (greetd), Sitzung (Einheiten, labwc), Portale
# shellcheck shell=bash

pruefe_sitzung() {
  _sitzung_pakete
  _sitzung_quickshell
  _sitzung_schriften
  _sitzung_login
  _sitzung_sitzung
}

_sitzung_code=/opt/zenos

# Gleich wie die Datei im Repo?
_sitzung_gleich() { [[ -f "$2" ]] && cmp -s -- "$1" "$2"; }

_sitzung_pakete() {
  abschnitt "Pakete"
  local datei zeile wort anzahl=0
  local -a woerter fehlend=()
  local -A gesehen=()
  for datei in "$_sitzung_code"/scripts/pakete/*.txt; do
    [[ -f "$datei" && "$(basename -- "$datei")" != quickshell-bau.txt ]] || continue
    while IFS= read -r zeile || [[ -n "$zeile" ]]; do
      read -ra woerter <<< "${zeile%%#*}"
      for wort in "${woerter[@]}"; do
        [[ -z "${gesehen[$wort]:-}" ]] || continue
        gesehen[$wort]=1
        anzahl=$((anzahl + 1))
        if [[ "$(dpkg-query -W -f='${db:Status-Status}' "$wort" 2> /dev/null)" != installed ]]; then
          fehlend+=("$wort")
        fi
      done
    done < "$datei"
  done
  if (( anzahl == 0 )); then
    fehler "Keine Paketlisten unter $_sitzung_code/scripts/pakete"
  elif (( ${#fehlend[@]} == 0 )); then
    ok "$anzahl Pakete aus scripts/pakete installiert"
  else
    fehler "${#fehlend[@]} von $anzahl Paketen fehlen: ${fehlend[*]} (install.sh)"
  fi
}

_sitzung_quickshell() {
  abschnitt "Quickshell"
  local stempel=/usr/local/share/zenos/quickshell.version soll_commit ist_commit ist_version gebaut qt
  if [[ ! -x /usr/local/bin/quickshell ]]; then
    fehler "Quickshell fehlt unter /usr/local/bin (install.sh baut es)"
    return 0
  fi
  if /usr/local/bin/quickshell --version > /dev/null 2>&1; then
    ok "$(LC_ALL=C.UTF-8 /usr/local/bin/quickshell --version 2> /dev/null | head -n 1)"
  else
    fehler "quickshell --version schlägt fehl (Qt-Bibliotheken passen nicht? install.sh baut neu)"
  fi

  if [[ ! -r "$stempel" ]]; then
    warnung "Stempel $stempel fehlt (install.sh baut Quickshell neu)"
    return 0
  fi
  soll_commit=$(grep -oE 'commit=[0-9a-f]{40}' "$_sitzung_code/scripts/module/25-quickshell.sh" 2> /dev/null | head -n 1)
  soll_commit=${soll_commit#commit=}
  ist_commit=$(sed -n 's/^commit=//p' "$stempel" | head -n 1)
  ist_version=$(sed -n 's/^version=//p' "$stempel" | head -n 1)
  gebaut=$(sed -n 's/^qt=//p' "$stempel" | head -n 1)
  if [[ -n "$soll_commit" && "$ist_commit" != "$soll_commit" ]]; then
    warnung "Quickshell-Stand ${ist_commit:0:7} statt ${soll_commit:0:7} (install.sh baut neu)"
  else
    ok "Stempel: v${ist_version:-?} (${ist_commit:0:7})"
  fi

  qt=$(dpkg-query -W -f='${Version}' libqt6core6t64 2> /dev/null)
  if [[ -z "$qt" ]]; then
    fehler "libqt6core6t64 ist nicht installiert"
  elif [[ "$qt" == "$gebaut" ]]; then
    ok "Gebaut gegen Qt $qt (installiert)"
  elif [[ "${qt%%[+-]*}" != "${gebaut%%[+-]*}" ]]; then
    fehler "Qt wurde aktualisiert ($gebaut → $qt). Quickshell nutzt private Qt-APIs: neu bauen mit install.sh"
  else
    warnung "Qt-Paket aktualisiert ($gebaut → $qt), gleiche Qt-Version. install.sh baut Quickshell vorsorglich neu"
  fi

  if [[ -e /usr/local/share/applications/org.quickshell.desktop ]]; then
    hinweis "Starter org.quickshell.desktop liegt noch da (install.sh entfernt ihn)"
  fi
}

_sitzung_schriften() {
  abschnitt "Schriften"
  local familien familie fehlt=()
  if ! command -v fc-list > /dev/null; then
    fehler "fc-list fehlt (Paket fontconfig)"
    return 0
  fi
  familien=$(fc-list : family 2> /dev/null | tr ',' '\n')
  for familie in "Geist" "Geist Mono" "Instrument Serif"; do
    grep -qxF -- "$familie" <<< "$familien" || fehlt+=("$familie")
  done
  if (( ${#fehlt[@]} > 0 )); then
    fehler "Schriften fehlen: ${fehlt[*]} (install.sh)"
  else
    ok "Geist, Geist Mono und Instrument Serif installiert"
  fi
  if [[ ! -d /usr/local/share/fonts/zenos ]]; then
    warnung "/usr/local/share/fonts/zenos fehlt"
  fi
}

_sitzung_login() {
  abschnitt "Login"
  local zustand dm ziel
  zustand=$(systemctl is-enabled greetd.service 2> /dev/null)
  case "$zustand" in
    enabled) ok "greetd aktiviert" ;;
    masked) fehler "greetd ist maskiert (systemctl unmask greetd.service)" ;;
    "") fehler "greetd fehlt (Paket greetd, install.sh)" ;;
    *) fehler "greetd ist nicht aktiviert ($zustand; install.sh)" ;;
  esac
  dm=/etc/systemd/system/display-manager.service
  if [[ -L "$dm" ]]; then
    ziel=$(basename -- "$(readlink -- "$dm")")
    [[ "$ziel" == greetd.service ]] || warnung "Anderer Anmeldedienst aktiv: $ziel"
  fi
  if systemctl is-active --quiet greetd.service 2> /dev/null; then
    ok "greetd läuft"
  else
    hinweis "greetd läuft noch nicht (startet nach dem nächsten Neustart)"
  fi

  if _sitzung_gleich "$_sitzung_code/system/greetd/config.toml" /etc/greetd/config.toml; then
    ok "/etc/greetd/config.toml: zenOS-Greeter auf VT 7, ohne Autologin"
  elif [[ -f /etc/greetd/config.toml ]]; then
    warnung "/etc/greetd/config.toml weicht von zenOS ab (install.sh setzt sie zurück)"
  else
    fehler "/etc/greetd/config.toml fehlt"
  fi
  if grep -q '^\[initial_session\]' /etc/greetd/config.toml 2> /dev/null; then
    fehler "Autologin ([initial_session]) in /etc/greetd/config.toml"
  fi

  # polkit: Neustart/Ausschalten im Login und die Sperre vor dem Standby (swayidle braucht die Erlaubnis von logind)
  if systemctl --quiet is-failed polkit.service 2> /dev/null; then
    warnung "polkit ist ausgefallen (Neustart/Ausschalten im Login, Sperre vor dem Standby). Ein Neustart behebt es"
  fi

  if [[ "$(systemctl get-default 2> /dev/null)" == graphical.target ]]; then
    ok "Standardziel graphical.target"
  else
    warnung "Standardziel ist $(systemctl get-default 2> /dev/null) statt graphical.target"
  fi
}

_sitzung_sitzung() {
  abschnitt "Sitzung"
  local einheit datei ziel alle_gleich=1 links_ok bus laufzeit antwort
  for einheit in zenos-sitzung.target zenos-shell.service; do
    if ! _sitzung_gleich "$_sitzung_code/system/systemd/user/$einheit" "/etc/systemd/user/$einheit"; then
      alle_gleich=0
      if [[ -f "/etc/systemd/user/$einheit" ]]; then
        warnung "/etc/systemd/user/$einheit weicht vom Repo ab (install.sh)"
      else
        fehler "/etc/systemd/user/$einheit fehlt (install.sh)"
      fi
    fi
  done
  (( alle_gleich == 0 )) || ok "Benutzereinheiten zenos-sitzung.target, zenos-shell.service in /etc/systemd/user"
  if [[ -d /etc/xdg/systemd/user && ! -L /etc/xdg/systemd/user ]]; then
    warnung "/etc/xdg/systemd/user ist ein Ordner statt eines Verweises auf /etc/systemd/user (install.sh repariert)"
  fi

  laufzeit=/run/user/$(id -u)
  bus=0
  [[ -S "$laufzeit/systemd/private" || -S "$laufzeit/bus" ]] && bus=1
  if (( bus )); then
    if XDG_RUNTIME_DIR=$laufzeit systemctl --user cat zenos-shell.service > /dev/null 2>&1; then
      ok "systemd --user findet die zenOS-Einheiten"
    else
      fehler "systemd --user findet zenos-shell.service nicht (systemctl --user daemon-reload)"
    fi
    if XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-sitzung.target 2> /dev/null; then
      ok "zenOS-Sitzung läuft"
      if XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-shell.service 2> /dev/null; then
        if antwort=$(XDG_RUNTIME_DIR=$laufzeit timeout 5 "$_sitzung_code/scripts/bin/zenos-ipc" thema status 2> /dev/null); then
          ok "Oberfläche läuft und antwortet (Erscheinungsbild ${antwort:-?})"
        else
          warnung "Oberfläche läuft, antwortet aber nicht auf zenos-ipc"
        fi
      else
        fehler "zenos-shell.service läuft nicht (journalctl --user -u zenos-shell.service)"
      fi
    else
      hinweis "Keine grafische zenOS-Sitzung aktiv"
    fi
  else
    hinweis "systemd-Benutzerinstanz nicht erreichbar, Sitzung nicht geprüft"
  fi

  links_ok=1
  for datei in autostart environment shutdown; do
    ziel=$(readlink "$HOME/.config/labwc/$datei" 2> /dev/null)
    if [[ "$ziel" != "$_sitzung_code/system/labwc/$datei" ]]; then
      warnung "labwc: ~/.config/labwc/$datei zeigt nicht auf $_sitzung_code/system/labwc/$datei (zen benutzer)"
      links_ok=0
    fi
  done
  (( links_ok == 0 )) || ok "labwc: autostart, environment, shutdown aus $_sitzung_code/system/labwc"

  if _sitzung_gleich "$_sitzung_code/system/portal/labwc-portals.conf" /etc/xdg/xdg-desktop-portal/labwc-portals.conf; then
    ok "Portale: gtk, Bildschirmfreigabe und Bildschirmfoto über wlr"
  else
    warnung "/etc/xdg/xdg-desktop-portal/labwc-portals.conf fehlt oder weicht ab (install.sh)"
  fi
}
