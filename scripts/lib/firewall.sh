#!/usr/bin/env bash
# shellcheck shell=bash
# firewall.sh – gemeinsame Teile der Firewall (ufw) für «zen firewall», «zen doctor» und den Helfer
# scripts/bin/zenos-firewall (läuft als root über pkexec, sudo oder install.sh).
#
# Beim Sourcen passiert nichts ausser Konstanten und Funktionen. Gelesen werden nur /etc/ufw, /etc/default/ufw
# und der bewusste Zustand; schreiben tut allein der Helfer.
#
#   _FIREWALL_NETZE                   lokale Netze, aus denen SSH erlaubt ist (dieselbe Liste steht in
#                                     scripts/module/70-sicherheit.sh)
#   _FIREWALL_ZUSTAND                 bewusster Zustand (/var/lib/zenos/firewall, root, 0644)
#   _firewall_installiert             ufw ist installiert
#   _firewall_wert SCHLUESSEL DATEI   Wert aus einer ufw-Konfigurationsdatei (ohne Anführungszeichen)
#   _firewall_aktiv                   ENABLED=yes in /etc/ufw/ufw.conf (startet auch beim Hochfahren)
#   _firewall_zustand [DATEI]         bewusster Zustand: «an», «aus» oder leer (nie geschaltet = Standard an)
#   _firewall_seit [DATEI]            Zeitpunkt des bewussten Zustands (ISO 8601) oder leer
#   _firewall_netze                   Netze, für die eine SSH-Regel da sein muss (ohne IPv6 in ufw nur IPv4)
#   _firewall_politik WERT            Klartext einer Standardregel (DROP → verweigern …)
#   _firewall_tupel [--still]         Regel-Tupel aus user.rules/user6.rules (nur für root lesbar)
#   _firewall_auswerten MODUS …       Tupel von stdin auswerten (fehlend, unbegrenzt, offen; siehe dort)
#   _firewall_ssh_gegenstellen        Gegenstellen aller laufenden SSH-Verbindungen (eingehend auf Port 22)
#   _firewall_ssh_ports               Ports von sshd aus «sshd -T» (stdin), «22» oder z. B. «22 2222»
#   _firewall_liste WERT…             «a, b, c»
#
# Der bewusste Zustand: Schaltet der Benutzer die Firewall über den Schalter in den Einstellungen oder mit
# «zen firewall deaktivieren» aus, steht dort «zustand=aus». install.sh und zen update schalten sie dann nicht
# wieder ein. Ohne Datei (Neuinstallation) gilt der Standard: an.

_FIREWALL_NETZE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fe80::/10 fd00::/8)
_FIREWALL_ZUSTAND=/var/lib/zenos/firewall

_firewall_installiert() { dpkg-query -W -f='${db:Status-Status}' ufw 2>/dev/null | grep -qx installed; }

_firewall_wert() { # SCHLUESSEL DATEI
  sed -n "s/^$1=//p" "$2" 2>/dev/null | tail -n 1 | tr -d '"'"'"
}

_firewall_aktiv() { [[ "$(_firewall_wert ENABLED /etc/ufw/ufw.conf)" == yes ]]; }

# Nur genau «an» oder «aus» zählen; alles andere ist kein bewusster Zustand (Standard an). Rückgabe immer 0
# (auch ohne Datei), damit Aufrufer mit «set -e» nicht abbrechen.
_firewall_zustand() { # [DATEI]
  local datei=${1:-$_FIREWALL_ZUSTAND}
  [[ -r "$datei" ]] || return 0
  sed -nE 's/^zustand=(an|aus)[[:space:]]*$/\1/p' "$datei" 2>/dev/null | tail -n 1 || true
}

_firewall_seit() { # [DATEI]
  local datei=${1:-$_FIREWALL_ZUSTAND}
  [[ -r "$datei" ]] || return 0
  sed -nE 's/^seit=([0-9][0-9T:+-]{9,31})[[:space:]]*$/\1/p' "$datei" 2>/dev/null | tail -n 1 || true
}

# Netze, für die eine SSH-Regel da sein muss: ohne IPv6 in ufw nur die IPv4-Netze (wie in 70-sicherheit)
_firewall_netze() {
  local netz
  for netz in "${_FIREWALL_NETZE[@]}"; do
    if [[ "$netz" == *:* && "$(_firewall_wert IPV6 /etc/default/ufw)" != yes ]]; then continue; fi
    printf '%s\n' "$netz"
  done
}

_firewall_politik() {
  case "$1" in
    DROP) printf 'verweigern' ;;
    REJECT) printf 'abweisen' ;;
    ACCEPT) printf 'erlauben' ;;
    *) printf 'unbekannt' ;;
  esac
}

# Regel-Tupel aus user.rules und user6.rules (nur für root lesbar). Als root direkt; sonst über sudo (fragt bei
# Bedarf nach dem Passwort), mit --still nur, wenn sudo ohne Passwort geht (für zen doctor).
# Rückgabe 1, wenn die Dateien nicht lesbar sind.
_firewall_tupel() { # [--still]
  local -a praefix=()
  if (( EUID != 0 )); then
    if [[ "${1:-}" == --still ]]; then praefix=(sudo -n); else praefix=(sudo); fi
  fi
  "${praefix[@]}" test -r /etc/ufw/user.rules 2>/dev/null || return 1
  {
    "${praefix[@]}" cat -- /etc/ufw/user.rules 2>/dev/null
    "${praefix[@]}" cat -- /etc/ufw/user6.rules 2>/dev/null
  } | grep '^### tuple ###' || true
}

# Wertet Regel-Tupel (stdin) aus:
#   fehlend NETZ…     druckt die Netze ohne SSH-Regel «allow» oder «limit» für tcp 22 von NETZ
#   unbegrenzt NETZ…  druckt die Netze, deren SSH-Regel «allow» statt «limit» ist (ohne Schutz vor Durchprobieren)
#   offen ADRESSE…    druckt die Adressen, deren SSH-Verbindungen (22/tcp) keine Regel erlaubt
# Rückgabe ungleich 0, wenn die Auswertung scheitert – dann gilt nichts als geprüft.
_firewall_auswerten() {
  local tupel
  tupel=$(cat)
  # Das Programm kommt über stdin, die Tupel deshalb über die Umgebung. -I: ohne PYTHON*-Variablen und
  # ohne Benutzer-Pakete (der Helfer läuft als root).
  _FIREWALL_TUPEL=$tupel python3 -I - "$@" <<'PY'
import ipaddress
import os
import sys

modus, werte = sys.argv[1], sys.argv[2:]
regeln = []
for zeile in os.environ.get("_FIREWALL_TUPEL", "").splitlines():
    t = zeile.split()
    if t[:3] != ["###", "tuple", "###"]:
        continue
    t = [x for x in t[3:] if not x.startswith("comment=")]
    # Aktion Protokoll Zielport Ziel Quellport Quelle [Ziel-App Quell-App] Richtung
    if len(t) not in (7, 9):
        continue
    regeln.append({"aktion": t[0], "proto": t[1], "dport": t[2], "dst": t[3],
                   "sport": t[4], "src": t[5], "richtung": t[-1]})


def port_22(dport):
    if dport == "any":
        return True
    for teil in dport.split(","):
        if ":" in teil:
            von, bis = teil.split(":", 1)
            if von.isdigit() and bis.isdigit() and int(von) <= 22 <= int(bis):
                return True
        elif teil == "22":
            return True
    return False


def ssh_regel(r, netz, aktionen):
    return (r["aktion"] in aktionen and r["proto"] == "tcp" and r["dport"] == "22"
            and r["dst"] in ("0.0.0.0/0", "::/0") and r["sport"] == "any"
            and r["src"] == netz and r["richtung"] == "in")


if modus == "fehlend":
    for netz in werte:
        if not any(ssh_regel(r, netz, ("allow", "limit")) for r in regeln):
            print(netz)
elif modus == "unbegrenzt":
    for netz in werte:
        if (any(ssh_regel(r, netz, ("allow",)) for r in regeln)
                and not any(ssh_regel(r, netz, ("limit",)) for r in regeln)):
            print(netz)
elif modus == "offen":
    for wert in werte:
        try:
            adresse = ipaddress.ip_address(wert.split("%", 1)[0])
        except ValueError:
            print(wert)
            continue
        if adresse.version == 6 and adresse.ipv4_mapped:
            adresse = adresse.ipv4_mapped
        # Loopback lässt ufw immer durch (before.rules)
        erlaubt = adresse.is_loopback
        for r in regeln:
            if r["aktion"] not in ("allow", "limit") or r["proto"] not in ("tcp", "any"):
                continue
            if not port_22(r["dport"]) or r["sport"] != "any":
                continue
            if r["richtung"] != "in" and not r["richtung"].startswith("in_"):
                continue
            try:
                netz = ipaddress.ip_network(r["src"], strict=False)
            except ValueError:
                continue
            if netz.version == adresse.version and adresse in netz:
                erlaubt = True
                break
        if not erlaubt:
            print(wert)
else:
    sys.exit(2)
PY
}

# Gegenstellen aller laufenden SSH-Verbindungen (eingehend auf Port 22) und die eigene aus SSH_CONNECTION
_firewall_ssh_gegenstellen() {
  local zeile adresse
  {
    if command -v ss >/dev/null 2>&1; then
      ss -Htn state established '( sport = :22 )' 2>/dev/null | while read -r _ _ _ gegenstelle _; do
        adresse=${gegenstelle%:*}
        adresse=${adresse#[}
        adresse=${adresse%]}
        printf '%s\n' "$adresse"
      done
    fi
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
      read -r adresse _ <<< "$SSH_CONNECTION"
      printf '%s\n' "$adresse"
    fi
  } | while IFS= read -r zeile; do
    [[ -n "$zeile" ]] && printf '%s\n' "$zeile"
  done | sort -u
}

# Ports, auf denen sshd lauscht, aus der Ausgabe von «sshd -T» (stdin): «port N» und «listenaddress ADRESSE:N»
# (eine ListenAddress mit eigenem Port ersetzt Port). Sortiert, ohne Doppelte, durch Leerzeichen getrennt.
_firewall_ssh_ports() {
  awk '
    $1 == "port" && $2 ~ /^[0-9]+$/ { print $2 }
    $1 == "listenaddress" && $2 ~ /:[0-9]+$/ { n = split($2, t, ":"); print t[n] }
  ' | sort -un | tr '\n' ' ' | sed 's/ $//'
}

_firewall_liste() { local IFS=,; printf '%s' "$*" | sed 's/,/, /g'; }
