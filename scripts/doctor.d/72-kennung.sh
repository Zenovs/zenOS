#!/usr/bin/env bash
# 72-kennung: Systemkennung zenOS – zenos-kennung und apt-Hook, Stand (Umlenkungen, os-release aktuell, Begrüssung,
# Verweise), Codenamen wie Ubuntu, ausstehendes base-files-Update, apt-check von update-notifier
# shellcheck shell=bash
#
# Die Sicherheitsquelle selbst prüft 70-sicherheit (zenos-sicherheitsquelle). Ausgegeben werden nur Namen und
# Versionen, keine Inhalte persönlicher Dateien.

pruefe_kennung() {
  abschnitt "Systemkennung"
  _kennung_werkzeug || return 0
  _kennung_stand
  [[ "$(os_release_wert ID)" == zenos ]] || return 0
  _kennung_codenamen
  _kennung_verweise
  _kennung_base_files
  _kennung_apt_check
}

# Gehört PFAD und jeder Ordner darüber root, und ist nichts davon für andere schreibbar?
_kennung_nur_root() {
  local pfad=$1 rechte
  while [[ -n "$pfad" && "$pfad" != / ]]; do
    rechte=$(stat -c '%u %a' -- "$pfad" 2>/dev/null) || return 1
    [[ "${rechte%% *}" == 0 ]] || return 1
    (( (8#${rechte##* } & 8#022) == 0 )) || return 1
    pfad=$(dirname -- "$pfad")
  done
}

_kennung_werkzeug() {
  local programm=/usr/local/sbin/zenos-kennung quelle=/opt/zenos/scripts/bin/zenos-kennung
  local hook=/etc/apt/apt.conf.d/60zenos-kennung
  if [[ ! -x "$programm" ]]; then
    if [[ "$(os_release_wert ID)" == zenos ]]; then
      fehler "$programm fehlt – die Kennung zenOS zieht nach apt-Läufen nicht mehr nach (install.sh)"
    else
      hinweis "Kennung zenOS noch nicht eingerichtet ($programm fehlt; install.sh richtet sie ein)"
    fi
    return 1
  fi
  if ! _kennung_nur_root "$programm"; then
    fehler "$programm oder ein Ordner darüber ist nicht nur für root schreibbar – root führt es nach jedem apt-Lauf aus (install.sh)"
  elif [[ -r "$quelle" ]] && ! cmp -s "$programm" "$quelle"; then
    warnung "$programm weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  fi
  if [[ ! -f "$hook" ]]; then
    warnung "$hook fehlt – die Kennung zieht nach Updates von base-files nicht nach (install.sh)"
  elif [[ -r /opt/zenos/system/apt/60zenos-kennung ]] && ! cmp -s "$hook" /opt/zenos/system/apt/60zenos-kennung; then
    warnung "$hook weicht vom Stand in /opt/zenos ab (install.sh stellt ihn wieder her)"
  fi
}

_kennung_stand() {
  local ausgabe rc=0 erste
  local -a zeilen=()
  ausgabe=$(/usr/local/sbin/zenos-kennung pruefen 2>&1) || rc=$?
  mapfile -t zeilen <<< "$ausgabe"
  case "$rc" in
    0) ok "Kennung ${ausgabe#eingerichtet: }" ;;
    3) hinweis "Kennung Ubuntu, ${zeilen[0]}" ;;
    1)
      if [[ "$(os_release_wert ID)" != zenos ]]; then
        warnung "Kennung noch Ubuntu: install.sh stellt um, sobald unattended-upgrades die Ubuntu-Sicherheitsquelle auch mit zenOS zulässt (Meldung im Install-Log)"
      else
        erste=$(printf '%s; ' "${zeilen[@]:0:3}")
        warnung "Kennung zenOS unvollständig: ${erste%; }$( (( ${#zeilen[@]} > 3 )) && printf ' …') (install.sh oder sudo zenos-kennung einrichten)"
      fi
      ;;
    *) warnung "zenos-kennung pruefen ist gescheitert (Exit $rc: ${zeilen[0]})" ;;
  esac
}

# unattended-upgrades, apt und pro lesen den Codenamen aus os-release (lsb_release); update-notifier liest
# UBUNTU_CODENAME mit einem regulären Ausdruck bis zum Zeilenende, Anführungszeichen zählten mit.
_kennung_codenamen() {
  local ubuntu codename lsb zeilen
  ubuntu=$(os_release_wert VERSION_CODENAME /usr/lib/os-release.ubuntu)
  lsb=$(lsb_release -cs 2>/dev/null)
  zeilen=$(grep -c 'UBUNTU_CODENAME' /usr/lib/os-release 2>/dev/null)
  codename=$(sed -n 's/^UBUNTU_CODENAME=//p' /usr/lib/os-release 2>/dev/null)
  if [[ -z "$ubuntu" ]]; then
    fehler "VERSION_CODENAME fehlt in /usr/lib/os-release.ubuntu (sudo apt install --reinstall base-files)"
  elif [[ "$lsb" != "$ubuntu" ]]; then
    fehler "lsb_release meldet den Codenamen «${lsb:-?}», Ubuntu ist bei «$ubuntu» – unattended-upgrades sucht Updates für den falschen Stand (sudo zenos-kennung erneuern)"
  elif [[ "$zeilen" != 1 || ! "$codename" =~ ^[a-z0-9][a-z0-9.+-]*$ ]]; then
    fehler "UBUNTU_CODENAME in /usr/lib/os-release fehlt, steht in Anführungszeichen oder mehrfach – update-notifier zählt dann keine Sicherheitsupdates (sudo zenos-kennung erneuern)"
  elif [[ "$codename" != "$ubuntu" ]]; then
    fehler "UBUNTU_CODENAME «$codename» weicht von Ubuntu («$ubuntu») ab (sudo zenos-kennung erneuern)"
  else
    ok "Codename wie Ubuntu: $ubuntu (lsb_release, UBUNTU_CODENAME)"
  fi
}

# Verweise, ohne die add-apt-repository (python-apt) bzw. distro-info mit der Kennung zenos abbrechen
_kennung_verweise() {
  local verweis ziel n=0
  local -a fehlend=()
  for verweis in /usr/share/python-apt/templates/zenos.info /usr/share/python-apt/templates/zenos.mirrors \
    /usr/share/distro-info/zenos.csv; do
    ziel="${verweis%/*}/ubuntu.${verweis##*.}"
    [[ -f "$ziel" ]] || continue
    if [[ -L "$verweis" && -f "$verweis" ]]; then
      n=$((n + 1))
    else
      fehlend+=("$verweis")
    fi
  done
  if (( ${#fehlend[@]} > 0 )); then
    warnung "Verweis fehlt oder zeigt ins Leere: ${fehlend[*]} – add-apt-repository bricht ab (sudo zenos-kennung einrichten)"
  elif (( n > 0 )); then
    ok "Verweise für python-apt und distro-info auf Ubuntu ($n)"
  fi
}

# base-files kommt aus -updates; das erlaubt unattended-upgrades nicht, und ein Update eines umgelenkten Conffiles
# (/etc/issue, /etc/legal) liesse es ohnehin aus. Von Hand (apt upgrade) läuft es ohne Rückfrage durch.
_kennung_base_files() {
  local installiert kandidat
  installiert=$(dpkg-query -W -f='${Version}' base-files 2>/dev/null)
  kandidat=$(LC_ALL=C apt-cache policy base-files 2>/dev/null | awk '$1 == "Candidate:" { print $2 }')
  [[ -n "$installiert" && -n "$kandidat" && "$kandidat" != "(none)" ]] || return 0
  if dpkg --compare-versions "$kandidat" gt "$installiert"; then
    hinweis "Update für base-files steht aus ($installiert → $kandidat); kommt nicht automatisch: sudo apt upgrade"
  fi
}

# update-notifier (Begrüssung «N Updates», Hinweise) zählt mit apt-check; ein Fehler dort bliebe sonst unbemerkt
_kennung_apt_check() {
  local programm=/usr/lib/update-notifier/apt-check ausgabe rc=0
  [[ -x "$programm" ]] || return 0
  ausgabe=$(timeout 120 "$programm" 2>&1 >/dev/null) || rc=$?
  if (( rc != 0 )) || [[ "$ausgabe" == *Traceback* ]]; then
    fehler "apt-check von update-notifier ist gescheitert (Exit $rc: ${ausgabe##*$'\n'})"
  elif [[ "$ausgabe" =~ ^([0-9]+)\;([0-9]+)$ ]]; then
    ok "apt-check: ${BASH_REMATCH[1]} Updates, davon ${BASH_REMATCH[2]} Sicherheitsupdates"
  else
    warnung "apt-check: unerwartete Ausgabe (${ausgabe##*$'\n'})"
  fi
}
