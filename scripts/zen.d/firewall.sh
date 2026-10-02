#!/usr/bin/env bash
# hilfe: firewall [status|aktivieren|deaktivieren] – Firewall (ufw) anzeigen, ein- oder ausschalten
# Die Firewall ist standardmässig an: install.sh (auch bei zen update) schaltet sie ein, ausser du hast sie
# bewusst ausgeschaltet. Eingehend verweigern, ausgehend erlauben, SSH (22/tcp) nur aus den lokalen Netzen
# 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, fe80::/10 und fd00::/8, je Adresse höchstens 5 neue Verbindungen
# in 30 s («limit», die sechste wird abgewiesen). DHCP, mDNS und ICMP lässt ufw selbst durch.
# «aktivieren» prüft SSH-Regeln, SSH-Port und ob alle laufenden SSH-Verbindungen erlaubt bleiben, und schaltet
# erst nach der Eingabe «aktivieren» ein. «deaktivieren» schaltet nach der Eingabe «deaktivieren» aus und merkt
# sich das (/var/lib/zenos/firewall): install.sh und zen update lassen sie dann aus. Dasselbe geht in den
# Einstellungen (System) mit dem Schalter «Firewall»; Ausschalten verlangt dort jedes Mal dein Passwort.
# shellcheck shell=bash

# Die Hilfsfunktionen kommen aus scripts/lib/firewall.sh; zen doctor (doctor.d/70-sicherheit.sh) sourct diese
# Datei und nutzt sie mit.
# shellcheck source=../lib/firewall.sh
source "$ZEN_SKRIPTE/lib/firewall.sh"

# Der Helfer ist derselbe, den die Einstellungen über pkexec aufrufen (feste Stelle in /opt/zenos)
_FIREWALL_HELFER=$ZENOS_CODE/scripts/bin/zenos-firewall

befehl_firewall() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen firewall [status|aktivieren|deaktivieren])"
    return 2
  fi
  case "${1:-status}" in
    status) _firewall_status ;;
    aktivieren) _firewall_aktivieren ;;
    deaktivieren) _firewall_deaktivieren ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, aktivieren, deaktivieren)"
      return 2
      ;;
  esac
}

# Datum des bewussten Zustands (TT.MM.JJJJ HH:MM) oder leer
_firewall_seit_text() {
  local seit
  seit=$(_firewall_seit)
  [[ -n "$seit" ]] || return 0
  date -d "$seit" '+%d.%m.%Y %H:%M' 2>/dev/null || printf '%s' "${seit%%T*}"
}

# --- status ----------------------------------------------------------------

_firewall_status() {
  if ! _firewall_installiert; then
    zen_fehler "ufw ist nicht installiert (install.sh ausführen)"
    return 1
  fi
  local eingehend ausgehend ipv6 tupel ausgabe seit
  local -a fehlend=() unbegrenzt=() netze=()
  mapfile -t netze < <(_firewall_netze)
  eingehend=$(_firewall_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  ausgehend=$(_firewall_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  ipv6=$(_firewall_wert IPV6 /etc/default/ufw)
  seit=$(_firewall_seit_text)

  if _firewall_aktiv; then
    printf 'Firewall (ufw): an\n'
  elif [[ "$(_firewall_zustand)" == aus ]]; then
    printf 'Firewall (ufw): aus – bewusst ausgeschaltet%s\n' "${seit:+ am $seit}"
  else
    printf 'Firewall (ufw): aus – install.sh bzw. zen update schaltet sie ein\n'
  fi
  case "$ipv6" in yes) ipv6=ja ;; no) ipv6=nein ;; *) ipv6=unbekannt ;; esac
  printf '  Eingehend: %s · Ausgehend: %s · IPv6: %s\n' "$(_firewall_politik "$eingehend")" \
    "$(_firewall_politik "$ausgehend")" "$ipv6"

  if ! tupel=$(_firewall_tupel); then
    printf '  Regeln nicht lesbar (braucht sudo)\n'
    return 1
  fi
  if ! ausgabe=$(_firewall_auswerten fehlend "${netze[@]}" <<< "$tupel"); then
    zen_fehler "Die Regeln liessen sich nicht auswerten (python3)"
    return 1
  fi
  mapfile -t fehlend < <(printf '%s' "$ausgabe" | sed '/^$/d')
  ausgabe=$(_firewall_auswerten unbegrenzt "${netze[@]}" <<< "$tupel") || ausgabe=""
  mapfile -t unbegrenzt < <(printf '%s' "$ausgabe" | sed '/^$/d')
  if (( ${#fehlend[@]} == 0 )); then
    printf '  SSH (22/tcp) erlaubt aus: %s\n' "$(_firewall_liste "${netze[@]}")"
  else
    printf '  SSH-Regeln fehlen für: %s (install.sh legt sie an)\n' "$(_firewall_liste "${fehlend[@]}")"
  fi
  if (( ${#unbegrenzt[@]} > 0 )); then
    printf '  Ohne Begrenzung (allow statt limit): %s (install.sh stellt um)\n' "$(_firewall_liste "${unbegrenzt[@]}")"
  fi

  printf '\n'
  if _firewall_aktiv; then
    $SUDO ufw status verbose
    printf '\nAusschalten: zen firewall deaktivieren (oder Einstellungen → System)\n'
  else
    $SUDO ufw show added
    printf '\nEinschalten: zen firewall aktivieren (oder Einstellungen → System)\n'
  fi
}

# --- aktivieren ------------------------------------------------------------

_firewall_aktivieren() {
  if ! _firewall_installiert; then
    zen_fehler "ufw ist nicht installiert (install.sh ausführen)"
    return 1
  fi
  if _firewall_aktiv && [[ "$(_firewall_zustand)" != aus ]]; then
    printf 'Die Firewall ist schon an.\n\n'
    _firewall_status
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen firewall aktivieren braucht eine Bestätigung im Terminal (Eingabe «aktivieren»)"
    return 2
  fi
  if [[ ! -x "$_FIREWALL_HELFER" ]]; then
    zen_fehler "$_FIREWALL_HELFER fehlt (install.sh ausführen)"
    return 1
  fi

  # Dieselbe Prüfung wie beim Einschalten selbst, vor der Frage: SSH-Regeln, Port, laufende Verbindungen
  local eingehend ausgehend
  local -a netze=()
  if ! $SUDO "$_FIREWALL_HELFER" pruefen > /dev/null; then
    zen_fehler "Die Firewall bleibt aus."
    return 1
  fi
  mapfile -t netze < <(_firewall_netze)
  eingehend=$(_firewall_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  ausgehend=$(_firewall_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  printf 'Die Firewall (ufw) wird eingeschaltet und startet danach bei jedem Hochfahren:\n'
  printf '  Eingehend: %s · Ausgehend: %s\n' "$(_firewall_politik "$eingehend")" "$(_firewall_politik "$ausgehend")"
  printf '  SSH (22/tcp) bleibt erlaubt aus: %s\n' "$(_firewall_liste "${netze[@]}")"
  printf '  Alle laufenden SSH-Verbindungen kommen aus einem erlaubten Netz\n\n'
  $SUDO ufw show added
  printf '\nWieder ausschalten: zen firewall deaktivieren\n\n'

  local antwort=""
  read -r -p 'Zum Einschalten «aktivieren» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != aktivieren ]]; then
    printf 'Abgebrochen. Die Firewall bleibt aus.\n'
    return 1
  fi

  $SUDO "$_FIREWALL_HELFER" ein || return 1
  printf '\n'
  $SUDO ufw status verbose
}

# --- deaktivieren ----------------------------------------------------------

_firewall_deaktivieren() {
  if ! _firewall_installiert; then
    zen_fehler "ufw ist nicht installiert (install.sh ausführen)"
    return 1
  fi
  local seit
  if ! _firewall_aktiv && [[ "$(_firewall_zustand)" == aus ]]; then
    seit=$(_firewall_seit_text)
    printf 'Die Firewall ist schon aus (bewusst ausgeschaltet%s).\n' "${seit:+ am $seit}"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen firewall deaktivieren braucht eine Bestätigung im Terminal (Eingabe «deaktivieren»)"
    return 2
  fi
  if [[ ! -x "$_FIREWALL_HELFER" ]]; then
    zen_fehler "$_FIREWALL_HELFER fehlt (install.sh ausführen)"
    return 1
  fi

  if _firewall_aktiv; then
    printf 'Die Firewall (ufw) wird ausgeschaltet. Eingehende Verbindungen sind danach nicht mehr gesperrt.\n'
  else
    printf 'Die Firewall ist schon aus, wird aber bei zen update wieder eingeschaltet.\n'
  fi
  printf 'zenOS merkt sich, dass du sie ausgeschaltet hast: install.sh und zen update lassen sie aus, bis du\n'
  printf 'sie wieder einschaltest (zen firewall aktivieren oder Einstellungen → System).\n\n'

  local antwort=""
  read -r -p 'Zum Ausschalten «deaktivieren» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != deaktivieren ]]; then
    printf 'Abgebrochen. Nichts geändert.\n'
    return 1
  fi
  $SUDO "$_FIREWALL_HELFER" aus
}
