#!/usr/bin/env bash
# anzeige-e2e.sh – Ende-zu-Ende-Test des Geräteprofils «Öffentlicher Bildschirm» (zen anzeige) im Testcontainer.
#
# Läuft als root im Container aus dem installierten Image (systemd, echtes useradd, greetd, ufw, labwc und
# Quickshell), mit /opt/zenos auf dem Stand dieses Codes:
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-anzeige-e2e
#   docker exec zenos-anzeige-e2e /opt/zenos/test/container/anzeige-e2e.sh
#
# Ablauf (Exit 0 nur, wenn alles stimmt):
#   1. Ausgangszustand merken: /etc/greetd/config.toml, Firewall-Regeln, kein Konto «anzeige».
#   2. /etc/zenos/anzeige.json mit einer Test-App als Befehl (sleep, als Argumentliste) und Port 8080, dann
#      «zenos-anzeige einrichten --ja»: Konto als Systemkonto mit nologin und gesperrtem Passwort, ohne Gruppen,
#      greetd mit [initial_session] für «anzeige» und [default_session] unverändert, polkit-Regel, Einheiten, Regeln
#      für 8080/tcp nur aus den lokalen Netzen. Ein zweites «anwenden» ändert nichts.
#   3. Die Anzeige-Sitzung ohne Bildschirm (WLR_BACKENDS=headless) als «anzeige», mit dem Benutzer-Manager über Linger:
#      zenos-anzeige.target aktiv, die App läuft, das Ersatzbild läuft, der Hemmer gegen Standby steht in
#      «systemd-inhibit --list», zenos-idle und die Oberfläche von zenOS laufen nicht. Der Ausweg (labwc endet) stoppt
#      das Ziel.
#   4. «zenos-anzeige entfernen --ja»: greetd Byte für Byte wie vorher, Regeln für 8080 weg, Konto weg, polkit-Regel
#      und Einheiten weg, Zustand weg.
# Die Logik im Einzelnen prüfen die Einheitentests (test/einheiten/anzeige.test.py).

set -uo pipefail

PROGRAMM=/opt/zenos/scripts/bin/zenos-anzeige
KONTO=anzeige
BEFUND=0
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

gut() { printf '  ✓ %s\n' "$*"; }
schlecht() { printf '  ✗ %s\n' "$*"; BEFUND=1; }
pruefe() {
  local ja=$1 nein=$2
  shift 2
  if "$@"; then gut "$ja"; else schlecht "$nein"; fi
}
abschnitt() { printf '\n── %s\n' "$*"; }

warte_auf() { # SEKUNDEN BEFEHL… – bis BEFEHL gelingt
  local bis=$((SECONDS + $1))
  shift
  until "$@"; do
    (( SECONDS < bis )) || return 1
    sleep 1
  done
}

(( EUID == 0 )) || { printf 'anzeige-e2e: läuft als root im Testcontainer\n' >&2; exit 2; }
[[ -f "$PROGRAMM" ]] || { printf 'anzeige-e2e: %s fehlt (install.sh)\n' "$PROGRAMM" >&2; exit 2; }
if python3 -I "$PROGRAMM" aktiv; then
  printf 'anzeige-e2e: Das Profil ist schon aktiv, erst entfernen\n' >&2
  exit 2
fi

abschnitt "Ausgangszustand"
cp -a /etc/greetd/config.toml "$TMP/greetd.vorher"
ufw show added > "$TMP/ufw.vorher" 2>&1 || true
pruefe "kein Konto $KONTO" "Konto $KONTO gibt es schon" bash -c '! getent passwd anzeige > /dev/null'
pruefe "greetd ohne [initial_session]" "greetd hat schon einen Autologin" \
  bash -c '! grep -q "^\[initial_session\]" /etc/greetd/config.toml'

abschnitt "Einrichten"
install -d -m 0755 /etc/zenos
cat > /etc/zenos/anzeige.json <<'EOF'
{ "version": 1, "konto": "anzeige", "app": { "befehl": ["/usr/bin/sleep", "infinity"] }, "ports": [8080] }
EOF
if ! python3 -I "$PROGRAMM" einrichten --ja > "$TMP/einrichten.log" 2>&1; then
  sed 's/^/    /' "$TMP/einrichten.log"
  schlecht "einrichten gescheitert"
  exit 1
fi
gut "einrichten"
IFS=: read -r _ _ uid _ _ home shell <<< "$(getent passwd "$KONTO")"
pruefe "Systemkonto (UID $uid)" "UID $uid ist kein Systemkonto" test "$uid" -lt 1000
pruefe "Login-Shell nologin" "Login-Shell $shell" test "$shell" = /usr/sbin/nologin
pruefe "Passwort gesperrt" "Passwort nicht gesperrt" bash -c "passwd -S $KONTO | awk '{ exit !(\$2 == \"L\") }'"
pruefe "keine Gruppen ausser der eigenen" "Gruppen: $(id -nG "$KONTO")" test "$(id -nG "$KONTO")" = "$KONTO"
pruefe "Home $home" "Home fehlt" test -d "$home"
pruefe "greetd: [default_session] wie vorher" "greetd: Anfang verändert" \
  bash -c "head -c \"\$(stat -c %s '$TMP/greetd.vorher')\" /etc/greetd/config.toml | cmp -s - '$TMP/greetd.vorher'"
pruefe "greetd: [initial_session] für $KONTO" "greetd: kein Autologin für $KONTO" \
  grep -qx "user = \"$KONTO\"" /etc/greetd/config.toml
pruefe "polkit-Regel" "polkit-Regel fehlt" test -f /etc/polkit-1/rules.d/50-zenos-anzeige.rules
pruefe "Einheiten der Anzeige" "Einheiten fehlen" test -f /etc/systemd/user/zenos-anzeige.target
if command -v ufw > /dev/null; then
  pruefe "Firewall: 8080/tcp aus 192.168.0.0/16" "Firewall-Regel fehlt" \
    bash -c 'ufw show added | grep -q "allow proto tcp from 192.168.0.0/16 to any port 8080"'
  pruefe "Firewall: 8080/tcp nicht aus jedem Netz" "8080 aus jedem Netz offen" \
    bash -c '! ufw show added | grep -qE "allow 8080(/tcp)?( |$)"'
fi
pruefe "anwenden zum zweiten Mal ändert nichts" "anwenden ändert noch etwas" \
  bash -c "test -z \"\$(python3 -I '$PROGRAMM' anwenden --melden)\""

abschnitt "Anzeige-Sitzung (ohne Bildschirm)"
loginctl enable-linger "$KONTO"
laufzeit=/run/user/$uid
if ! warte_auf 30 test -S "$laufzeit/bus"; then
  schlecht "Benutzer-Manager von $KONTO startet nicht"
else
  als() { setpriv --reuid="$uid" --regid="$uid" --init-groups -- env XDG_RUNTIME_DIR="$laufzeit" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$laufzeit/bus" HOME="$home" "$@"; }
  als env WLR_BACKENDS=headless WLR_RENDERER=pixman LIBSEAT_BACKEND=noop \
    /opt/zenos/scripts/bin/zenos-anzeige-sitzung > "$TMP/sitzung.log" 2>&1 &
  sitzung=$!
  pruefe "zenos-anzeige.target aktiv" "zenos-anzeige.target nicht aktiv" \
    warte_auf 60 als systemctl --user --quiet is-active zenos-anzeige.target
  pruefe "App läuft (Befehl als Argumentliste)" "App läuft nicht" \
    warte_auf 30 als systemctl --user --quiet is-active zenos-anzeige-app.service
  pruefe "Ersatzbild läuft" "Ersatzbild läuft nicht" \
    warte_auf 30 als systemctl --user --quiet is-active zenos-anzeige-ersatz.service
  pruefe "Hemmer gegen Standby" "kein Hemmer gegen Standby" \
    warte_auf 30 bash -c 'systemd-inhibit --list --no-pager | grep -q "zenOS-Anzeige"'
  pruefe "keine Sperre (zenos-idle läuft nicht)" "zenos-idle läuft" \
    bash -c "! setpriv --reuid=$uid --regid=$uid --init-groups -- env XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-idle.service"
  pruefe "keine Oberfläche von zenOS" "zenos-shell läuft" \
    bash -c "! setpriv --reuid=$uid --regid=$uid --init-groups -- env XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-shell.service"
  # Ausweg: labwc endet (wie mit Strg + Alt + Shift + Rücktaste), das Ziel endet mit
  kill "$sitzung" 2> /dev/null
  pkill -u "$uid" -x labwc 2> /dev/null
  pruefe "nach dem Ausweg ist die Anzeige gestoppt" "zenos-anzeige.target läuft nach dem Ende von labwc weiter" \
    warte_auf 30 bash -c "! setpriv --reuid=$uid --regid=$uid --init-groups -- env XDG_RUNTIME_DIR=$laufzeit systemctl --user --quiet is-active zenos-anzeige.target"
fi

abschnitt "Entfernen"
if ! python3 -I "$PROGRAMM" entfernen --ja > "$TMP/entfernen.log" 2>&1; then
  sed 's/^/    /' "$TMP/entfernen.log"
  schlecht "entfernen gescheitert"
fi
pruefe "greetd Byte für Byte wie vorher" "greetd weicht ab" cmp -s /etc/greetd/config.toml "$TMP/greetd.vorher"
pruefe "Konto $KONTO entfernt" "Konto $KONTO gibt es noch" bash -c '! getent passwd anzeige > /dev/null'
pruefe "Home bleibt (Daten nur auf Rückfrage)" "Home gelöscht" test -d "$home"
pruefe "polkit-Regel weg" "polkit-Regel noch da" test ! -e /etc/polkit-1/rules.d/50-zenos-anzeige.rules
pruefe "Einheiten weg" "Einheiten noch da" test ! -e /etc/systemd/user/zenos-anzeige.target
pruefe "Zustand weg" "Zustand noch da" test ! -e /var/lib/zenos/anzeige.json
if command -v ufw > /dev/null; then
  ufw show added > "$TMP/ufw.nachher" 2>&1 || true
  pruefe "Firewall-Regeln wie vorher" "Firewall-Regeln weichen ab" cmp -s "$TMP/ufw.vorher" "$TMP/ufw.nachher"
fi
rm -rf -- "$home"
rm -f /etc/zenos/anzeige.json

printf '\n'
if (( BEFUND )); then
  printf 'anzeige-e2e: Befunde (oben ✗)\n'
  exit 1
fi
printf 'anzeige-e2e: alles in Ordnung\n'
