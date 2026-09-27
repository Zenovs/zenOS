#!/usr/bin/env bash
# hilfe: firewall [status|aktivieren] – Firewall (ufw) anzeigen oder nach Bestätigung einschalten
# install.sh bereitet ufw nur vor: eingehend verweigern, ausgehend erlauben, SSH (22/tcp) nur aus den
# lokalen Netzen 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, fe80::/10 und fd00::/8.
# «zen firewall aktivieren» zeigt die Regeln, prüft die SSH-Regeln, den SSH-Port und ob alle laufenden
# SSH-Verbindungen erlaubt bleiben, und schaltet ufw erst nach der Eingabe «aktivieren» ein.
# Wieder ausschalten: sudo ufw disable
# shellcheck shell=bash

# Die Hilfsfunktionen _firewall_* nutzt auch scripts/doctor.d/70-sicherheit.sh.

# Lokale Netze, aus denen SSH erlaubt ist (dieselbe Liste steht in scripts/module/70-sicherheit.sh)
_FIREWALL_NETZE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fe80::/10 fd00::/8)

befehl_firewall() {
  if (( $# > 1 )); then
    zen_fehler "zu viele Argumente (zen firewall [status|aktivieren])"
    return 2
  fi
  case "${1:-status}" in
    status) _firewall_status ;;
    aktivieren) _firewall_aktivieren ;;
    *)
      zen_fehler "unbekannter Unterbefehl «$1» (erlaubt: status, aktivieren)"
      return 2
      ;;
  esac
}

# --- Hilfsfunktionen (auch für zen doctor) ---------------------------------

_firewall_installiert() { dpkg-query -W -f='${db:Status-Status}' ufw 2>/dev/null | grep -qx installed; }

# Wert aus einer ufw-Konfigurationsdatei (ohne Anführungszeichen)
_firewall_wert() { # SCHLUESSEL DATEI
  sed -n "s/^$1=//p" "$2" 2>/dev/null | tail -n 1 | tr -d '"'"'"
}

_firewall_aktiv() { [[ "$(_firewall_wert ENABLED /etc/ufw/ufw.conf)" == yes ]]; }

# Netze, für die eine SSH-Regel da sein muss: ohne IPv6 in ufw nur die IPv4-Netze (wie in 70-sicherheit)
_firewall_netze() {
  local netz
  for netz in "${_FIREWALL_NETZE[@]}"; do
    if [[ "$netz" == *:* && "$(_firewall_wert IPV6 /etc/default/ufw)" != yes ]]; then continue; fi
    printf '%s\n' "$netz"
  done
}

# Klartext einer Standardregel
_firewall_politik() {
  case "$1" in
    DROP) printf 'verweigern' ;;
    REJECT) printf 'abweisen' ;;
    ACCEPT) printf 'erlauben' ;;
    *) printf 'unbekannt' ;;
  esac
}

# Regel-Tupel aus user.rules und user6.rules (nur für root lesbar). Ohne Argument über sudo (fragt bei
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
#   fehlend NETZ…    druckt die Netze ohne die Regel «allow tcp 22 von NETZ» (wie 70-sicherheit sie anlegt)
#   offen ADRESSE…   druckt die Adressen, deren SSH-Verbindungen (22/tcp) keine Regel erlaubt
# Rückgabe ungleich 0, wenn die Auswertung scheitert – dann gilt nichts als geprüft.
_firewall_auswerten() {
  local tupel
  tupel=$(cat)
  # Das Programm kommt über stdin, die Tupel deshalb über die Umgebung
  _FIREWALL_TUPEL=$tupel python3 - "$@" <<'PY'
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


if modus == "fehlend":
    for netz in werte:
        if not any(r["aktion"] == "allow" and r["proto"] == "tcp" and r["dport"] == "22"
                   and r["dst"] in ("0.0.0.0/0", "::/0") and r["sport"] == "any"
                   and r["src"] == netz and r["richtung"] == "in" for r in regeln):
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

# --- status ----------------------------------------------------------------

_firewall_status() {
  if ! _firewall_installiert; then
    zen_fehler "ufw ist nicht installiert (install.sh ausführen)"
    return 1
  fi
  local eingehend ausgehend ipv6 tupel ausgabe
  local -a fehlend=() netze=()
  mapfile -t netze < <(_firewall_netze)
  eingehend=$(_firewall_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  ausgehend=$(_firewall_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  ipv6=$(_firewall_wert IPV6 /etc/default/ufw)

  if _firewall_aktiv; then
    printf 'Firewall (ufw): aktiv\n'
  else
    printf 'Firewall (ufw): vorbereitet, nicht aktiv\n'
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
  if (( ${#fehlend[@]} == 0 )); then
    printf '  SSH (22/tcp) erlaubt aus: %s\n' "$(_firewall_liste "${netze[@]}")"
  else
    printf '  SSH-Regeln fehlen für: %s (install.sh bereitet sie vor)\n' "$(_firewall_liste "${fehlend[@]}")"
  fi

  printf '\n'
  if _firewall_aktiv; then
    $SUDO ufw status verbose
  else
    $SUDO ufw show added
    printf '\nEinschalten: zen firewall aktivieren\n'
  fi
}

_firewall_liste() { local IFS=,; printf '%s' "$*" | sed 's/,/, /g'; }

# --- aktivieren ------------------------------------------------------------

_firewall_aktivieren() {
  if (( EUID == 0 )); then
    zen_fehler "zen firewall aktivieren läuft als normaler Benutzer (holt sich sudo selbst), damit die laufenden SSH-Verbindungen geprüft werden können"
    return 2
  fi
  if ! _firewall_installiert; then
    zen_fehler "ufw ist nicht installiert (install.sh ausführen)"
    return 1
  fi
  if _firewall_aktiv; then
    printf 'Die Firewall ist schon aktiv.\n\n'
    _firewall_status
    return 0
  fi
  if [[ ! -t 0 ]]; then
    zen_fehler "zen firewall aktivieren braucht eine Bestätigung im Terminal (Eingabe «aktivieren»)"
    return 2
  fi

  local tupel ausgabe eingehend ausgehend ports
  local -a fehlend=() offen=() gegenstellen=() netze=()
  mapfile -t netze < <(_firewall_netze)
  if ! tupel=$(_firewall_tupel); then
    zen_fehler "Die Regeln von ufw sind nicht lesbar (sudo nötig)"
    return 1
  fi

  # SSH muss aus allen lokalen Netzen erlaubt sein
  if ! ausgabe=$(_firewall_auswerten fehlend "${netze[@]}" <<< "$tupel"); then
    zen_fehler "Die Regeln liessen sich nicht auswerten (python3). Die Firewall bleibt aus."
    return 1
  fi
  mapfile -t fehlend < <(printf '%s' "$ausgabe" | sed '/^$/d')
  if (( ${#fehlend[@]} > 0 )); then
    zen_fehler "SSH-Regeln fehlen für: $(_firewall_liste "${fehlend[@]}"). Erst ./scripts/install.sh ausführen, es bereitet sie vor. Die Firewall bleibt aus."
    return 1
  fi

  # SSH muss auf Port 22 laufen, sonst greifen die Regeln nicht
  if [[ -x /usr/sbin/sshd ]]; then
    ports=$($SUDO /usr/sbin/sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | sort -u | tr '\n' ' ')
    ports=${ports% }
    if [[ -n "$ports" && " $ports " != *" 22 "* ]]; then
      zen_fehler "SSH läuft auf Port $ports, die Regeln erlauben nur 22/tcp. Die Firewall bleibt aus."
      return 1
    fi
  fi

  # Keine laufende SSH-Verbindung darf abgeschnitten werden
  mapfile -t gegenstellen < <(_firewall_ssh_gegenstellen)
  if (( ${#gegenstellen[@]} > 0 )); then
    if ! ausgabe=$(_firewall_auswerten offen "${gegenstellen[@]}" <<< "$tupel"); then
      zen_fehler "Die SSH-Verbindungen liessen sich nicht prüfen (python3). Die Firewall bleibt aus."
      return 1
    fi
    mapfile -t offen < <(printf '%s' "$ausgabe" | sed '/^$/d')
    if (( ${#offen[@]} > 0 )); then
      zen_fehler "Diese SSH-Verbindung(en) kommen aus einem Netz, das die Regeln nicht erlauben: $(_firewall_liste "${offen[@]}"). Die Firewall bliebe für sie zu, deshalb bleibt sie aus."
      return 1
    fi
  fi

  eingehend=$(_firewall_wert DEFAULT_INPUT_POLICY /etc/default/ufw)
  ausgehend=$(_firewall_wert DEFAULT_OUTPUT_POLICY /etc/default/ufw)
  printf 'Die Firewall (ufw) wird eingeschaltet und startet danach bei jedem Hochfahren:\n'
  printf '  Eingehend: %s · Ausgehend: %s\n' "$(_firewall_politik "$eingehend")" "$(_firewall_politik "$ausgehend")"
  printf '  SSH (22/tcp) bleibt erlaubt aus: %s\n' "$(_firewall_liste "${netze[@]}")"
  if (( ${#gegenstellen[@]} > 0 )); then
    printf '  Alle laufenden SSH-Verbindungen kommen aus einem erlaubten Netz\n'
  fi
  printf '\n'
  $SUDO ufw show added
  printf '\nWieder ausschalten: sudo ufw disable\n\n'

  local antwort=""
  read -r -p 'Zum Einschalten «aktivieren» eintippen (alles andere bricht ab): ' antwort || antwort=""
  if [[ "$antwort" != aktivieren ]]; then
    printf 'Abgebrochen. Die Firewall bleibt aus.\n'
    return 1
  fi

  $SUDO ufw --force enable
  printf '\n'
  $SUDO ufw status verbose
}
