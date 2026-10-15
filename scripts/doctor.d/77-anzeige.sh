#!/usr/bin/env bash
# 77-anzeige: Geräteprofil «Öffentlicher Bildschirm» – Profil, Anzeige-Konto ohne Passwort, Rechte und Schlüssel,
# greetd passend zum Profil, Anzeige-Sitzung und App, Ports in der Firewall, die eigene Sperre unverändert
# shellcheck shell=bash
#
# Ohne Profil erscheint der Abschnitt nur, wenn greetd trotzdem jemanden automatisch anmeldet (das darf nie sein).
# Ausgegeben werden Kontoname, Einheit und Ports, nie Inhalte, Befehlszeilen der App oder Adressen. Was nur root lesen
# kann (Passwortstatus, Schlüssel, Dienste des Anzeige-Kontos, Firewall-Regeln), prüft doctor mit «sudo -n»; ohne
# sudo ohne Passwort bleibt es bei einem Hinweis. Doku: docs/module/anzeige.md.

_ANZEIGE_PROGRAMM=/opt/zenos/scripts/bin/zenos-anzeige

pruefe_anzeige() {
  local konto
  [[ -f "$_ANZEIGE_PROGRAMM" ]] || return 0
  if ! python3 -I "$_ANZEIGE_PROGRAMM" aktiv > /dev/null 2>&1; then
    if grep -q '^[[:space:]]*\[initial_session\]' /etc/greetd/config.toml 2>/dev/null; then
      abschnitt "Öffentlicher Bildschirm"
      fehler "greetd meldet ein Konto automatisch an, das Profil ist aber nicht aktiv (install.sh stellt den Login wieder her)"
    fi
    return 0
  fi
  abschnitt "Öffentlicher Bildschirm"
  konto=$(python3 -I "$_ANZEIGE_PROGRAMM" konto 2>/dev/null)
  if [[ ! "$konto" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; then
    fehler "Profil aktiv, aber das Anzeige-Konto ist nicht lesbar (/var/lib/zenos/anzeige.json)"
    return 0
  fi
  ok "Profil aktiv, Anzeige-Konto $konto"
  _anzeige_konfig
  _anzeige_konto "$konto"
  _anzeige_greetd "$konto"
  _anzeige_sitzung "$konto"
  _anzeige_ports
  _anzeige_eigene_sperre "$konto"
}

_anzeige_konfig() {
  local ausgabe
  if ausgabe=$(python3 -I "$_ANZEIGE_PROGRAMM" konfig 2>&1 > /dev/null); then
    ok "Konfiguration /etc/zenos/anzeige.json gültig"
  else
    fehler "Konfiguration: ${ausgabe#zenos-anzeige: } (die Anzeige läuft ohne App und Ports weiter)"
  fi
}

_anzeige_konto() {
  local konto=$1 eintrag uid shell home status gruppe linger
  local -a gruppen=() verboten=()
  if ! eintrag=$(getent passwd "$konto"); then
    fehler "Das Anzeige-Konto $konto fehlt (sudo zen anzeige einrichten legt es wieder an)"
    return 0
  fi
  IFS=: read -r _ _ uid _ _ home shell <<< "$eintrag"
  if (( uid == 0 || uid > 999 )); then
    fehler "$konto hat UID $uid: kein Systemkonto – das Anzeige-Konto darf nie ein persönliches sein"
  fi
  case "$shell" in
    /usr/sbin/nologin | /sbin/nologin | /usr/bin/false | /bin/false) ok "$konto: Login-Shell $shell (keine Konsole, kein SSH)" ;;
    *) fehler "$konto hat die Login-Shell $shell – damit wäre eine Anmeldung an Konsole oder SSH möglich" ;;
  esac
  read -r -a gruppen <<< "$(id -nG "$konto" 2>/dev/null)"
  for gruppe in "${gruppen[@]}"; do
    case "$gruppe" in
      sudo | admin | wheel | adm | lpadmin | sambashare | plugdev | netdev | docker | lxd | libvirt | systemd-journal | input | disk | shadow)
        verboten+=("$gruppe") ;;
    esac
  done
  if (( ${#verboten[@]} > 0 )); then
    fehler "$konto ist in der Gruppe ${verboten[*]} – das Anzeige-Konto hat keine Rechte"
  else
    ok "$konto: keine Verwaltungsgruppen"
  fi
  if status=$(sudo -n passwd -S "$konto" 2>/dev/null); then
    case "$(awk '{ print $2 }' <<< "$status")" in
      L | NP) ok "$konto: Passwort gesperrt" ;;
      *) fehler "$konto hat ein Passwort – das Anzeige-Konto meldet sich ohne an (sudo usermod --lock $konto)" ;;
    esac
    if sudo -n test -e "$home/.ssh/authorized_keys" 2>/dev/null || sudo -n test -e "$home/.ssh/authorized_keys2" 2>/dev/null; then
      fehler "$konto hat SSH-Schlüssel ($home/.ssh) – das Anzeige-Konto bekommt keine"
    else
      ok "$konto: keine SSH-Schlüssel"
    fi
  else
    hinweis "Passwort und SSH-Schlüssel von $konto nur mit sudo prüfbar (sudo zen doctor)"
  fi
  linger=$(loginctl show-user "$konto" -p Linger --value 2>/dev/null) || linger=""
  if [[ "$linger" == yes ]]; then
    hinweis "$konto: Linger an – Benutzerdienste der App laufen auch ohne Anmeldung (etwa ihre Updates)"
  fi
}

_anzeige_greetd() {
  local konto=$1 soll dm
  if ! soll=$(python3 -I "$_ANZEIGE_PROGRAMM" greetd-konfig 2>/dev/null); then
    fehler "Login: erwartete greetd-Konfiguration nicht erzeugbar"
    return 0
  fi
  if [[ "$soll" == "$(cat /etc/greetd/config.toml 2>/dev/null)" ]]; then
    ok "Login: greetd meldet nur $konto automatisch an, danach dein Login"
  else
    fehler "Login: /etc/greetd/config.toml passt nicht zum Profil (install.sh stellt es wieder her)"
  fi
  dm=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null) || dm=""
  if [[ "$dm" != */greetd.service ]]; then
    fehler "Anmeldedienst ist ${dm##*/}${dm:+, }nicht greetd – die Anzeige startet so nicht"
  fi
}

# Läuft die Anzeige-Sitzung auf seat0, und ist die App aktiv? Die Dienste des Anzeige-Kontos sind nur mit sudo lesbar.
_anzeige_sitzung() {
  local konto=$1 json laeuft einheit art
  json=$(loginctl list-sessions --json=short 2>/dev/null) || json="[]"
  laeuft=$(python3 -I -c 'import json, sys
try:
    sitzungen = json.loads(sys.stdin.read() or "[]")
except ValueError:
    sitzungen = []
print("ja" if any(s.get("user") == sys.argv[1] and s.get("seat") == "seat0" for s in sitzungen) else "nein")' \
    "$konto" <<< "$json")
  if [[ "$laeuft" == ja ]]; then
    ok "Anzeige-Sitzung läuft"
  else
    warnung "Anzeige-Sitzung läuft nicht (sudo zen anzeige neustart, oder am Gerät abgemeldet über den Ausweg)"
    return 0
  fi
  art=$(python3 -I "$_ANZEIGE_PROGRAMM" konfig 2>/dev/null | python3 -I -c 'import json, sys
try:
    app = json.load(sys.stdin).get("app") or {}
except ValueError:
    app = {}
print(app.get("einheit") or ("zenos-anzeige-app.service" if "befehl" in app else ""))')
  einheit=$art
  if [[ -z "$einheit" ]]; then
    hinweis "Keine App in der Konfiguration: Einheiten mit WantedBy=graphical-session.target starten von selbst"
    return 0
  fi
  if ! sudo -n true 2>/dev/null; then
    hinweis "App $einheit nur mit sudo prüfbar (sudo zen doctor)"
    return 0
  fi
  case "$(sudo -n systemctl --user --machine="$konto@.host" is-active "$einheit" 2>/dev/null)" in
    active) ok "App $einheit aktiv" ;;
    activating) warnung "App $einheit startet gerade (oder startet nach einem Absturz neu)" ;;
    *) fehler "App $einheit läuft nicht – die Anzeige zeigt das Ersatzbild (journalctl --user -M $konto@ -u $einheit)" ;;
  esac
}

_anzeige_ports() {
  local tupel ausgabe port netz
  local -a ports=() netze=() ist=() fehlend=()
  mapfile -t ports < <(python3 -I "$_ANZEIGE_PROGRAMM" ports 2>/dev/null)
  if (( ${#ports[@]} == 0 )); then
    ok "Keine Ports für die App freigegeben"
    return 0
  fi
  # shellcheck source=../lib/firewall.sh
  source "$ZEN_SKRIPTE/lib/firewall.sh" || { fehler "lib/firewall.sh nicht ladbar"; return 0; }
  if ! _firewall_installiert; then
    fehler "ufw fehlt: Ports ${ports[*]} der App sind nicht abgesichert"
    return 0
  fi
  if ! _firewall_aktiv; then
    if [[ "$(_firewall_zustand)" == aus ]]; then
      warnung "Firewall bewusst aus: Port ${ports[*]} der App ist aus jedem Netz erreichbar (zen firewall aktivieren)"
    else
      warnung "Firewall aus: Port ${ports[*]} der App ist aus jedem Netz erreichbar (install.sh schaltet sie ein)"
    fi
  fi
  if ! tupel=$(_firewall_tupel --still); then
    hinweis "Regeln für Port ${ports[*]} nur mit sudo prüfbar (sudo zen doctor)"
    return 0
  fi
  ausgabe=$(_firewall_auswerten anzeige <<< "$tupel") || { fehler "Firewall-Regeln nicht auswertbar"; return 0; }
  mapfile -t ist < <(printf '%s' "$ausgabe" | sed '/^$/d')
  mapfile -t netze < <(_firewall_netze)
  for port in "${ports[@]}"; do
    for netz in "${netze[@]}"; do
      printf '%s\n' "${ist[@]}" | grep -qxF -- "$port $netz" || fehlend+=("$port")
    done
  done
  if (( ${#fehlend[@]} > 0 )); then
    fehler "Firewall-Regeln fehlen für Port $(printf '%s\n' "${fehlend[@]}" | sort -un | tr '\n' ' ')(install.sh legt sie an)"
  else
    ok "Port ${ports[*]}/tcp nur aus den lokalen Netzen offen"
  fi
}

# Das persönliche Konto: sperrt wie immer und meldet sich nie automatisch an
_anzeige_eigene_sperre() {
  local konto=$1 ich ergebnis minuten
  ich=$(id -un)
  [[ "$ich" != "$konto" ]] || return 0
  if grep -A3 '^[[:space:]]*\[initial_session\]' /etc/greetd/config.toml 2>/dev/null | grep -q "user = \"$ich\""; then
    fehler "greetd meldet dein Konto $ich automatisch an – das darf nie sein (install.sh stellt es wieder her)"
  else
    ok "Dein Konto $ich meldet sich nie automatisch an"
  fi
  if [[ -x /opt/zenos/scripts/bin/zenos-idle ]] && ergebnis=$(/opt/zenos/scripts/bin/zenos-idle pruefen 2>/dev/null); then
    read -r minuten _ <<< "$ergebnis"
    if [[ "$minuten" =~ ^[0-9]+$ ]] && (( minuten >= 1 && minuten <= 15 )); then
      ok "Deine automatische Sperre: nach $minuten Min. (unverändert)"
    else
      fehler "Deine automatische Sperre ist nicht 1–15 Min. ($ergebnis)"
    fi
  else
    hinweis "Deine Sperrzeit nicht ermittelbar (zenos-idle pruefen)"
  fi
}
