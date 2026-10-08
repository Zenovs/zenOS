#!/usr/bin/env bash
# installer-e2e.sh <schritt>… – Ende-zu-Ende-Test des zen Installers im Testcontainer (als root im Container). Getestet
# wird mit dem echten zenos-installer, zenos-installer-bedienen, systemd, den Units, apt, dpkg, pkexec und polkit und mit
# der zenOS-Oberfläche als Sitzung wie auf dem Pi (Fenster «zen Installer», Einstellungen › Apps). Die Test-Pakete
# brauchen keine Abhängigkeiten aus dem Netz.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, Arbeitsstand nach /opt/zenos):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-installer-e2e
#   docker exec zenos-installer-e2e bash -c 'apt-get update -qq && apt-get install -y -qq wtype file'
#   docker exec -u tester -w /home/tester/zenOS zenos-installer-e2e ./scripts/install.sh
# Dann: docker exec zenos-installer-e2e bash /repo/test/container/installer-e2e.sh alle   (oder einzelne Schritte;
# «alle» dauert rund 5 Minuten, vor allem install.sh: am besten im Hintergrund starten und das Protokoll lesen)
#
# pkexec: Im Container zeigt kein Bildschirm den Passwortdialog, und docker exec öffnet keine logind-Sitzung. Für die
# Schritte mit der Oberfläche legt «oberflaeche» deshalb eine polkit-Regel nur in diesem Container an
# (/etc/polkit-1/rules.d/10-zenos-installer-e2e.rules): tester darf die zwei Aktionen des zen Installers ohne Passwort.
# So läuft der echte Weg (Knopf → pkexec → polkit-Aktion über exec.path und argv1 → Helfer als root mit PKEXEC_UID).
# Wo der Test Zeitpunkt und Prozess selbst steuern muss (Ablehnungen, Sperren, Stopp), ruft er den Helfer als root mit
# PKEXEC_UID auf, genau so, wie pkexec ihn startet (bereinigte Umgebung, PKEXEC_UID des Aufrufers); «installieren» und
# «entfernen» gehen zusätzlich über sudo (zen install im Terminal).
#
# Schritte (nach «einrichten» in dieser Reihenfolge):
#   einrichten   Test-.deb bauen (Programm, Starter, Symbol, Systemdienst, postinst und prerm) in ~tester/Ablage, dazu
#                eine für eine fremde Architektur; Timer von Kanal, Basis und apt-daily halten an
#   standard     .deb öffnet in der labwc-Sitzung der zen Installer (gio, xdg-mime)
#   ansehen      als tester: JSON mit bereit, neu, Hinweisen (Skripte, Dienst), Plan, Symbol
#   geaendert    Datei nach dem Ansehen verändert (andere SHA-256): Exit 3, nichts installiert, Ablage leer
#   plan         ein anderer Plan als der angezeigte: Exit 3, nichts installiert
#   architektur  fremde Architektur: ansehen «abgelehnt» (architektur); der Helfer installiert sie trotzdem nicht (Exit 3)
#   verweis      Verweis auf die Test-.deb und eine Datei, die root gehört: der Helfer lehnt beide ab (Exit 3), die Unit
#                startet nicht, Ablage leer
#   installieren sudo zenos-installer-bedienen installieren PFAD SHA256 PLAN: Unit mit der SHA-256 als Instanz, das
#                Paket ist installiert, sein Dienst läuft, Liste, letzte.json mit dem Starter, Ablage leer, Log,
#                keine Unit «failed»; danach sagt ansehen «installiert»
#   entfernen    sudo zenos-installer-bedienen entfernen PAKET (Instanz maskiert): Paket und Dienst weg, Liste leer
#   gleichzeitig Kanal oder Basis halten kanal.lock: Der Installer wartet («wartet» in status), nichts ist installiert;
#                danach installiert er. Während apt läuft (das postinst hält an): zenos-basis pruefen und zenos-kanal
#                pruefen Exit 75. Stopp der Unit während des Wartens: Exit 10, nichts installiert, Ablage leer
#   oberflaeche  zenOS-Oberfläche als Sitzung wie auf dem Pi (oberflaeche.sh start --sitzung), Einrichtung zu,
#                polkit-Regel nur im Container
#   doppelklick  gio open (Thunar, Firefox) und xdg-open (Chrome) der Test-.deb als tester → Fenster «zen Installer»
#                offen, ohne Rechte angesehen («bereit»). xdg-open braucht «file» für den Dateityp (auf Ubuntu Server
#                da, im Testbild nachinstallieren)
#   fenster      Tab und Enter (wtype): echtes pkexec aus dem Fenster, «fertig», Paket installiert, Dienst läuft
#   oeffnen      Enter auf «Öffnen»: das Programm läuft als tester in eigener Einheit (app.slice), das Fenster ist zu
#   einstellungen Einstellungen › Apps zeigt das Paket (IPC installer liste); Entfernen wie der Knopf dort (pkexec …
#                entfernen PAKET als tester): Paket weg, die Liste sagt «keine»
#   installsh    Oberfläche zu, polkit-Regel weg, install.sh zweimal von Hand (root) mit 0 Änderungen
#   aufraeumen   Oberfläche, polkit-Regel, Timer-Drop-ins, Test-Pakete und Dateien weg
#   alle         alle Schritte in dieser Reihenfolge

set -euo pipefail

TESTER=tester
TESTER_UID=$(id -u "$TESTER")
LAUFZEIT=/run/user/$TESTER_UID
REPO=/home/$TESTER/zenOS
PAKET=zenos-e2e-app
DIENST=zenos-e2e-app.service
FREMD_PAKET=zenos-e2e-fremd
ABLAGE=/home/$TESTER/Ablage/installer-e2e
DEB=$ABLAGE/zenos-e2e-app_1.0-1.deb
FREMD_DEB=$ABLAGE/zenos-e2e-fremd_1.0-1.deb
BAU=/srv/installer-e2e
HALT=/run/zenos-installer-e2e
PROGRAMM=/opt/zenos/scripts/bin/zenos-installer
HELFER=/opt/zenos/scripts/bin/zenos-installer-bedienen
BASIS=/usr/local/libexec/zenos/zenos-basis
KANAL=/usr/local/libexec/zenos/zenos-kanal
ZUSTAND=/var/lib/zenos/installer
SPERRE=/run/zenos-sperre/kanal.lock
REGEL=/etc/polkit-1/rules.d/10-zenos-installer-e2e.rules
TIMER=(zenos-basis-automatik.timer zenos-basis-gelegenheit.timer zenos-kanal.timer zenos-kanal-gelegenheit.timer
  apt-daily.timer apt-daily-upgrade.timer)
ALLE=(einrichten standard ansehen geaendert plan architektur verweis installieren entfernen gleichzeitig oberflaeche
  doppelklick fenster oeffnen einstellungen installsh aufraeumen)

fehler=0
ok() { printf '  ✓ %s\n' "$*"; }
nein() { printf '  ✗ %s\n' "$*"; fehler=$((fehler + 1)); }
pruefe() { # TEXT BEFEHL…
  local text=$1
  shift
  if "$@"; then ok "$text"; else nein "$text"; fi
}
als_tester() { runuser -u "$TESTER" -- env -C "/home/$TESTER" XDG_RUNTIME_DIR="$LAUFZEIT" "$@"; }
# Wie ein Programm in der Sitzung (Thunar, Chrome, Terminal): Wayland, Sitzungsbus, Desktop labwc
als_sitzung() {
  local wayland
  wayland=$(cat /srv/oberflaeche/wayland 2> /dev/null || true)
  runuser -u "$TESTER" -- env -C "/home/$TESTER" HOME="/home/$TESTER" XDG_RUNTIME_DIR="$LAUFZEIT" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$LAUFZEIT/bus" WAYLAND_DISPLAY="$wayland" XDG_SESSION_TYPE=wayland \
    XDG_CURRENT_DESKTOP=labwc:wlroots "$@"
}
oberflaeche() { als_tester env HOME="/home/$TESTER" bash "$REPO/test/container/oberflaeche.sh" "$@"; }
ipc() { als_tester /opt/zenos/scripts/bin/zenos-ipc "$@" 2> /dev/null | tail -n 1; }
json() { python3 -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"; }
ansehen_json() { als_tester "$PROGRAMM" ansehen "${1:-$DEB}" --json; }
# Der Helfer, wie pkexec ihn startet: als root, Umgebung bereinigt, PKEXEC_UID des Aufrufers
wie_pkexec() { env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 PKEXEC_UID="$TESTER_UID" "$HELFER" "$@"; }
installiert() { [[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2> /dev/null || true)" == installed ]]; }
nicht_installiert() { ! installiert "$1"; }
ablage_leer() { [[ -z "$(ls -A "$ZUSTAND/ablage")" ]]; }
sperre_frei() { flock -n "$SPERRE" true; }
gleich() { [[ "$("${@:2}")" == "$1" ]]; }
ohne_aenderungen() { [[ "$1" == *' · normal · ok · 0 Änderungen · '* ]]; }

# warte_bis SEKUNDEN BEFEHL… – bis BEFEHL gelingt (Takt 0,25 s)
warte_bis() {
  local ende=$((SECONDS + $1))
  shift
  until "$@" > /dev/null 2>&1; do
    (( SECONDS < ende )) || return 1
    sleep 0.25
  done
}

# warte_ipc SEKUNDEN ANTWORT ZIEL FUNKTION… – bis die Oberfläche genau ANTWORT gibt
warte_ipc() {
  local sekunden=$1 antwort=$2
  shift 2
  warte_bis "$sekunden" gleich "$antwort" ipc "$@"
}

# Phase einer laufenden Unit des Installers (status --json), sonst leer
lauf_phase() { als_tester "$PROGRAMM" status --json | json '(d["laeuft"] or [{}])[0].get("phase") or ""'; }

# Paket bauen: NAME ARCH ZIEL
paket_bauen() {
  local name=$1 arch=$2 ziel=$3 wurzel=$BAU/$1
  rm -rf -- "$wurzel"
  mkdir -p "$wurzel/DEBIAN" "$wurzel/usr/bin" "$wurzel/usr/share/applications" "$wurzel/usr/lib/systemd/system" \
    "$wurzel/usr/share/icons/hicolor/scalable/apps"
  cat > "$wurzel/DEBIAN/control" <<EOF
Package: $name
Version: 1.0-1
Architecture: $arch
Maintainer: Beispiel <info@example.org>
Homepage: https://example.org
Description: Testpaket für den zen Installer
 Nur im Testcontainer.
EOF
  # postinst: hält an, solange $HALT/halt besteht (höchstens 2 Minuten; Schritt «gleichzeitig»), dann der Dienst
  cat > "$wurzel/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ -e $HALT/halt ]; then
  : > $HALT/wartet
  i=0
  while [ -e $HALT/halt ] && [ \$i -lt 600 ]; do sleep 0.2; i=\$((i + 1)); done
fi
if [ -d /run/systemd/system ]; then systemctl daemon-reload; systemctl enable --now $name.service; fi
EOF
  printf '#!/bin/sh\nset -e\nif [ -d /run/systemd/system ]; then systemctl disable --now %s.service || true; fi\n' \
    "$name" > "$wurzel/DEBIAN/prerm"
  chmod 0755 "$wurzel/DEBIAN/postinst" "$wurzel/DEBIAN/prerm"
  # Das Programm merkt sich seine PID (Schritt «oeffnen») und wartet
  cat > "$wurzel/usr/bin/$name" <<EOF
#!/bin/sh
printf '%s\n' "\$\$" > "\${XDG_RUNTIME_DIR:-/tmp}/$name.pid"
exec sleep infinity
EOF
  chmod 0755 "$wurzel/usr/bin/$name"
  printf '[Unit]\nDescription=zenOS-Test\n[Service]\nExecStart=/bin/sleep infinity\n[Install]\nWantedBy=multi-user.target\n' \
    > "$wurzel/usr/lib/systemd/system/$name.service"
  printf '[Desktop Entry]\nType=Application\nName=E2E-App\nExec=%s\nIcon=%s\n' "$name" "$name" \
    > "$wurzel/usr/share/applications/$name.desktop"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"></svg>\n' \
    > "$wurzel/usr/share/icons/hicolor/scalable/apps/$name.svg"
  dpkg-deb --root-owner-group --build "$wurzel" "$ziel" > /dev/null
  chown "$TESTER:$TESTER" "$ziel"
}

paket_weg() { # NAME…
  local name
  for name in "$@"; do
    if dpkg-query -W "$name" > /dev/null 2>&1; then apt-get purge -y -q "$name" > /dev/null 2>&1 || true; fi
  done
}

schritt_einrichten() {
  echo "== einrichten"
  local timer native fremd
  native=$(dpkg --print-architecture)
  if [[ "$native" == arm64 ]]; then fremd=amd64; else fremd=arm64; fi
  install -d -o "$TESTER" -g "$TESTER" "/home/$TESTER/Ablage" "$ABLAGE"
  install -d -m 0755 "$HALT"
  install -d -o "$TESTER" -g "$TESTER" -m 0700 "$LAUFZEIT"
  paket_bauen "$PAKET" "$native" "$DEB"
  paket_bauen "$FREMD_PAKET" "$fremd" "$FREMD_DEB"
  pruefe "Test-Pakete gebaut ($native und $fremd)" test -s "$DEB" -a -s "$FREMD_DEB"
  for timer in "${TIMER[@]}"; do
    install -d -m 0755 "/run/systemd/system/$timer.d"
    printf '# Nur im Ende-zu-Ende-Test: kein Lauf von selbst\n[Timer]\nOnBootSec=\nOnCalendar=\nOnCalendar=2099-01-01 00:00:00\nPersistent=false\n' \
      > "/run/systemd/system/$timer.d/e2e.conf"
  done
  systemctl daemon-reload
  ok "Timer lösen im Test nicht von selbst aus"
  pruefe "Sperre frei" sperre_frei
}

schritt_standard() {
  echo "== standard"
  local gio xdg
  gio=$(als_tester env XDG_CURRENT_DESKTOP=labwc:wlroots LC_ALL=C gio mime application/vnd.debian.binary-package |
    sed -n 's/^Default application for .*: //p')
  pruefe "gio: .deb öffnet zenos-installer.desktop" test "$gio" = zenos-installer.desktop
  xdg=$(als_tester env XDG_CURRENT_DESKTOP=labwc:wlroots xdg-mime query default application/vnd.debian.binary-package)
  pruefe "xdg-mime: .deb öffnet zenos-installer.desktop (Chrome)" test "$xdg" = zenos-installer.desktop
  pruefe "Starter liegt bereit" test -f /usr/local/share/applications/zenos-installer.desktop
}

schritt_ansehen() {
  echo "== ansehen"
  local daten
  daten=$(ansehen_json)
  pruefe "bereit und neu" test "$(json '(d["ergebnis"], d["zustand"])' <<< "$daten")" = "('bereit', 'neu')"
  pruefe "Hinweise: Skripte und Dienst" test "$(json '[h["art"] for h in d["hinweise"]]' <<< "$daten")" = \
    "['skripte', 'dienste']"
  pruefe "Name aus dem Starter" test "$(json 'd["name"]' <<< "$daten")" = E2E-App
  pruefe "Symbol im Laufzeitordner" test -s "$(json 'd["symbol"]' <<< "$daten")"
}

schritt_geaendert() {
  echo "== geaendert"
  local daten sha plan rc=0
  daten=$(ansehen_json)
  sha=$(json 'd["sha256"]' <<< "$daten")
  plan=$(json 'd["plan"]' <<< "$daten")
  cp -p -- "$DEB" "$DEB.vorher"
  printf 'x' >> "$DEB"
  als_tester sudo "$HELFER" installieren "$DEB" "$sha" "$plan" || rc=$?
  pruefe "Exit 3 (Datei seit dem Ansehen geändert, über sudo)" test "$rc" = 3
  rc=0
  wie_pkexec installieren "$DEB" "$sha" "$plan" 2> "$BAU/geaendert.txt" || rc=$?
  mv -f -- "$DEB.vorher" "$DEB"
  pruefe "Exit 3 (dasselbe wie über pkexec)" test "$rc" = 3
  pruefe "Grund: seit dem Ansehen geändert" grep -q "seit dem Ansehen geändert" "$BAU/geaendert.txt"
  pruefe "nicht installiert" nicht_installiert "$PAKET"
  pruefe "Ablage leer" ablage_leer
}

schritt_plan() {
  echo "== plan"
  local sha rc=0
  sha=$(ansehen_json | json 'd["sha256"]')
  als_tester sudo "$HELFER" installieren "$DEB" "$sha" "$(printf '0%.0s' {1..40})" || rc=$?
  pruefe "Exit 3 (Plan geändert)" test "$rc" = 3
  pruefe "letzte.json: abgelehnt" test "$(json 'd["ergebnis"]' < "$ZUSTAND/letzte.json")" = abgelehnt
  pruefe "nicht installiert" nicht_installiert "$PAKET"
  pruefe "Ablage leer" ablage_leer
}

schritt_architektur() {
  echo "== architektur"
  local daten sha rc=0
  daten=$(ansehen_json "$FREMD_DEB" || true)
  pruefe "ansehen: abgelehnt wegen der Architektur" \
    test "$(json '(d["ergebnis"], d["ablehnung"])' <<< "$daten")" = "('abgelehnt', 'architektur')"
  pruefe "kein Plan für eine Ablehnung" test "$(json 'd["plan"]' <<< "$daten")" = None
  sha=$(json 'd["sha256"]' <<< "$daten")
  wie_pkexec installieren "$FREMD_DEB" "$sha" "$(printf 'a%.0s' {1..40})" || rc=$?
  pruefe "Helfer: Exit 3" test "$rc" = 3
  pruefe "letzte.json: abgelehnt mit der Architektur" \
    test "$(json '(d["ergebnis"], "braucht" in d["grund"])' < "$ZUSTAND/letzte.json")" = "('abgelehnt', True)"
  pruefe "nicht installiert" nicht_installiert "$FREMD_PAKET"
  pruefe "Ablage leer" ablage_leer
}

schritt_verweis() {
  echo "== verweis"
  local sha rc=0 seit
  sha=$(ansehen_json | json 'd["sha256"]')
  ln -sfn -- "$DEB" "$ABLAGE/verweis.deb"
  chown -h "$TESTER:$TESTER" "$ABLAGE/verweis.deb"
  seit=$(date '+%Y-%m-%d %H:%M:%S')
  wie_pkexec installieren "$ABLAGE/verweis.deb" "$sha" "$(printf 'a%.0s' {1..40})" 2> "$BAU/verweis.txt" || rc=$?
  pruefe "Verweis: Exit 3" test "$rc" = 3
  pruefe "Grund: Verweis" grep -q "ist ein Verweis" "$BAU/verweis.txt"
  # Eine Datei, die nicht dem Aufrufer gehört (root, für alle lesbar)
  install -m 0644 -o root -g root -- "$DEB" "$ABLAGE/fremd.deb"
  rc=0
  wie_pkexec installieren "$ABLAGE/fremd.deb" "$sha" "$(printf 'a%.0s' {1..40})" 2> "$BAU/fremd.txt" || rc=$?
  pruefe "fremde Datei: Exit 3" test "$rc" = 3
  pruefe "Grund: gehört nicht dir" grep -q "gehört nicht dir" "$BAU/fremd.txt"
  rm -f -- "$ABLAGE/verweis.deb" "$ABLAGE/fremd.deb"
  pruefe "keine Unit gestartet" bash -c "! journalctl --since '$seit' --no-pager -q -u 'zenos-installer-installieren@*' | grep -q ."
  pruefe "nicht installiert" nicht_installiert "$PAKET"
  pruefe "Ablage leer" ablage_leer
}

schritt_installieren() {
  echo "== installieren"
  local daten sha plan rc=0 seit
  daten=$(ansehen_json)
  sha=$(json 'd["sha256"]' <<< "$daten")
  plan=$(json 'd["plan"]' <<< "$daten")
  seit=$(date '+%Y-%m-%d %H:%M:%S')
  als_tester sudo "$HELFER" installieren "$DEB" "$sha" "$plan" || rc=$?
  pruefe "Exit 0" test "$rc" = 0
  pruefe "Paket installiert" test "$(dpkg-query -W -f='${db:Status-Status} ${Version}' "$PAKET")" = "installed 1.0-1"
  pruefe "Dienst des Pakets läuft" systemctl --quiet is-active "$DIENST"
  pruefe "Unit lief mit der SHA-256 als Instanz" bash -c "journalctl --since '$seit' -u 'zenos-installer-installieren@$sha.service' --no-pager | grep -q 'ist installiert'"
  pruefe "letzte.json: installiert, Starter" test "$(json '(d["ergebnis"], d["programme"])' < "$ZUSTAND/letzte.json")" = \
    "('installiert', [{'id': '$PAKET.desktop', 'name': 'E2E-App'}])"
  pruefe "Liste" test "$(als_tester "$PROGRAMM" liste --json | json '[p["name"] for p in d["pakete"]]')" = "['$PAKET']"
  pruefe "Ablage leer" ablage_leer
  pruefe "Log" grep -q "· installieren $PAKET 1.0-1 ·" /var/log/zenos/installer.log
  pruefe "Log nur root und adm" test "$(stat -c '%a %U %G' /var/log/zenos/installer.log)" = "640 root adm"
  pruefe "keine Unit failed" bash -c "! systemctl --failed --no-legend --plain | grep -q zenos-installer"
  pruefe "ansehen sagt jetzt «installiert»" test "$(ansehen_json | json 'd["ergebnis"]')" = installiert
  pruefe "status --kurz" bash -c "$PROGRAMM status --kurz | grep -q '^installiert '"
}

schritt_entfernen() {
  echo "== entfernen"
  local rc=0
  als_tester sudo "$HELFER" entfernen "$PAKET" || rc=$?
  pruefe "Exit 0" test "$rc" = 0
  pruefe "Paket weg" nicht_installiert "$PAKET"
  pruefe "Dienst weg" bash -c "! systemctl --quiet is-active $DIENST"
  pruefe "Liste leer" test "$(als_tester "$PROGRAMM" liste --json | json 'd["pakete"]')" = "[]"
  pruefe "letzte.json: entfernt" test "$(json 'd["ergebnis"]' < "$ZUSTAND/letzte.json")" = entfernt
  rc=0
  als_tester sudo "$HELFER" entfernen bash || rc=$?
  pruefe "bash kam nicht über den zen Installer: Exit 3" test "$rc" = 3
}

schritt_gleichzeitig() {
  echo "== gleichzeitig"
  local daten sha plan rc=0 halter helfer
  daten=$(ansehen_json)
  sha=$(json 'd["sha256"]' <<< "$daten")
  plan=$(json 'd["plan"]' <<< "$daten")
  install -d -m 0700 /run/zenos-sperre

  # Ein Lauf von Kanal oder Basis hält die gemeinsame Sperre (flock -o auf dieselbe Datei: nur flock hält sie)
  flock -o "$SPERRE" sleep 600 &
  halter=$!
  warte_bis 5 bash -c "! flock -n '$SPERRE' true"
  rm -f -- "$HALT/wartet"
  : > "$HALT/halt"
  wie_pkexec installieren "$DEB" "$sha" "$plan" > "$BAU/gleichzeitig.txt" 2>&1 &
  helfer=$!
  pruefe "Installer wartet auf die Sperre («wartet»)" warte_bis 30 gleich wartet lauf_phase
  sleep 3
  pruefe "solange die Sperre gehalten ist: nichts installiert" nicht_installiert "$PAKET"
  kill "$halter" 2> /dev/null || true
  wait "$halter" 2> /dev/null || true
  # Jetzt läuft apt, das postinst hält an: Kanal und Basis sind belegt
  pruefe "danach läuft apt (postinst hält an)" warte_bis 60 test -e "$HALT/wartet"
  pruefe "Phase «installiert»" gleich installiert lauf_phase
  rc=0
  /usr/bin/python3 -I "$BASIS" pruefen > "$BAU/basis.txt" 2>&1 || rc=$?
  pruefe "zenos-basis pruefen: Exit 75" test "$rc" = 75
  rc=0
  /usr/bin/python3 -I "$KANAL" pruefen > "$BAU/kanal.txt" 2>&1 || rc=$?
  pruefe "zenos-kanal pruefen: Exit 75" test "$rc" = 75
  rm -f -- "$HALT/halt"
  rc=0
  wait "$helfer" || rc=$?
  pruefe "Installer danach: Exit 0" test "$rc" = 0
  pruefe "Paket installiert" installiert "$PAKET"
  pruefe "Sperre frei" sperre_frei
  pruefe "Ablage leer" ablage_leer

  # Wieder weg (wie über pkexec), dann ein Stopp während des Wartens
  rc=0
  wie_pkexec entfernen "$PAKET" > /dev/null 2>&1 || rc=$?
  pruefe "entfernt (wie über pkexec): Exit 0" test "$rc" = 0
  flock -o "$SPERRE" sleep 600 &
  halter=$!
  warte_bis 5 bash -c "! flock -n '$SPERRE' true"
  wie_pkexec installieren "$DEB" "$sha" "$plan" > "$BAU/stopp.txt" 2>&1 &
  helfer=$!
  warte_bis 30 gleich wartet lauf_phase || true
  systemctl stop "zenos-installer-installieren@$sha.service"
  rc=0
  wait "$helfer" || rc=$?
  kill "$halter" 2> /dev/null || true
  wait "$halter" 2> /dev/null || true
  pruefe "Stopp während des Wartens: Exit 10" test "$rc" = 10
  pruefe "letzte.json: wartet" test "$(json 'd["ergebnis"]' < "$ZUSTAND/letzte.json")" = wartet
  pruefe "nicht installiert" nicht_installiert "$PAKET"
  pruefe "Ablage leer" ablage_leer
  pruefe "keine Unit failed" bash -c "! systemctl --failed --no-legend --plain | grep -q zenos-installer"
  pruefe "Sperre frei" sperre_frei
}

schritt_oberflaeche() {
  echo "== oberflaeche"
  # Nur in diesem Container (siehe Kopf): tester darf den zen Installer ohne Passwort bedienen
  cat > "$REGEL" <<'EOF'
// Nur im Testcontainer (test/container/installer-e2e.sh, Schritt «aufraeumen» entfernt die Datei): Im Container zeigt
// kein Bildschirm den Passwortdialog. Auf Geräten gilt immer auth_admin (system/polkit/org.zenos.installer.policy).
polkit.addRule(function (action, subject) {
    if ((action.id === "org.zenos.installer.installieren" || action.id === "org.zenos.installer.entfernen") &&
        subject.user === "tester")
        return polkit.Result.YES;
});
EOF
  chmod 0644 "$REGEL"
  # Die Sitzung braucht die systemd-Benutzerinstanz von tester; docker exec öffnet keine logind-Sitzung (linger, wie im
  # Dockerfile; «aufraeumen» nimmt es zurück, wenn es vorher aus war)
  if [[ ! -e "/var/lib/systemd/linger/$TESTER" ]]; then
    : > "$BAU/linger-war-aus"
    loginctl enable-linger "$TESTER"
  fi
  pruefe "Benutzerinstanz von $TESTER läuft" warte_bis 30 test -S "$LAUFZEIT/bus"
  oberflaeche stopp > /dev/null 2>&1 || true
  pruefe "Oberfläche als Sitzung gestartet" oberflaeche start --sitzung
  ipc einrichtung schliessen > /dev/null || true
  pruefe "Einrichtung zu" warte_ipc 20 zu einrichtung status
  pruefe "zen Installer zu" warte_ipc 20 zu installer status
}

schritt_doppelklick() {
  echo "== doppelklick"
  local rc=0
  # Thunar und Firefox öffnen über GIO
  als_sitzung gio open "$DEB" > "$BAU/gio-open.txt" 2>&1 || rc=$?
  pruefe "gio open: Exit 0" test "$rc" = 0
  pruefe "Fenster offen und angesehen («bereit»)" warte_ipc 60 bereit installer status
  ipc installer schliessen > /dev/null || true
  pruefe "Fenster zu" warte_ipc 10 zu installer status
  # Chrome öffnet einen Download über xdg-open (generisch unter labwc: Dateityp über «file», dann die mimeapps)
  pruefe "file da (xdg-open braucht es für den Dateityp)" command -v file
  rc=0
  als_sitzung xdg-open "$DEB" > "$BAU/xdg-open.txt" 2>&1 || rc=$?
  pruefe "xdg-open: Exit 0" test "$rc" = 0
  pruefe "Fenster wieder offen und angesehen («bereit»)" warte_ipc 60 bereit installer status
  oberflaeche bild installer-e2e-bereit > /dev/null 2>&1 || true
}

schritt_fenster() {
  echo "== fenster"
  local seit
  seit=$(date '+%Y-%m-%d %H:%M:%S')
  # Kein Knopf hat von selbst den Fokus: Tab führt zum Primärknopf «Installieren», Enter drückt ihn
  pruefe "Tab und Enter" oberflaeche taste Tab Return
  pruefe "Installation fertig («fertig»)" warte_ipc 180 fertig installer status
  pruefe "über pkexec (uid $TESTER_UID)" bash -c "journalctl --since '$seit' -t zenos-installer-bedienen --no-pager | grep -q 'pkexec, uid $TESTER_UID'"
  pruefe "Paket installiert" installiert "$PAKET"
  pruefe "Dienst des Pakets läuft" systemctl --quiet is-active "$DIENST"
  pruefe "Ablage leer" ablage_leer
  oberflaeche bild installer-e2e-fertig > /dev/null 2>&1 || true
}

schritt_oeffnen() {
  echo "== oeffnen"
  local pidfile=$LAUFZEIT/$PAKET.pid pid
  rm -f -- "$pidfile"
  # Der Primärknopf «Öffnen» hat den Fokus noch vom Klick auf «Installieren» (er war während der Installation nur aus)
  pruefe "Enter" oberflaeche taste Return
  pruefe "Programm gestartet" warte_bis 20 test -s "$pidfile"
  pid=$(cat "$pidfile" 2> /dev/null || echo 0)
  pruefe "läuft als $TESTER" test "$(ps -o user= -p "$pid" 2> /dev/null | tr -d ' ')" = "$TESTER"
  pruefe "in eigener Einheit (app.slice)" grep -q 'app.slice' "/proc/$pid/cgroup"
  pruefe "Fenster zu" warte_ipc 10 zu installer status
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then kill "$pid" 2> /dev/null || true; fi
}

schritt_einstellungen() {
  echo "== einstellungen"
  local rc=0
  ipc einstellungen oeffnen apps/installer > /dev/null || true
  ipc installer liste > /dev/null || true
  pruefe "Einstellungen › Apps zeigt das Paket" warte_ipc 20 "$PAKET" installer liste
  oberflaeche bild installer-e2e-einstellungen > /dev/null 2>&1 || true
  # Genau der Aufruf des Knopfs «Entfernen …» (installer.js entfernenBefehl), als tester in der Sitzung
  als_sitzung pkexec "$HELFER" entfernen "$PAKET" > "$BAU/pkexec-entfernen.txt" 2>&1 || rc=$?
  pruefe "pkexec … entfernen: Exit 0" test "$rc" = 0
  pruefe "Paket weg" nicht_installiert "$PAKET"
  pruefe "Liste in den Einstellungen leer («keine»)" warte_ipc 20 keine installer liste
  oberflaeche bild installer-e2e-einstellungen-leer > /dev/null 2>&1 || true
  ipc einstellungen schliessen > /dev/null || true
}

# install.sh zweimal von Hand (root, wie basis-e2e): jeweils 0 Änderungen
schritt_installsh() {
  echo "== installsh"
  local n zeile rc
  oberflaeche stopp > /dev/null 2>&1 || true
  rm -f -- "$REGEL"
  for n in 1 2; do
    rc=0
    env HOME=/root /opt/zenos/scripts/install.sh --ruhig < /dev/null > "$BAU/install-$n.txt" 2>&1 || rc=$?
    zeile=$(grep '^== Ende' /var/log/zenos/install.log | tail -n 1)
    if (( rc != 0 )); then tail -n 30 "$BAU/install-$n.txt"; fi
    pruefe "install.sh Lauf $n: Exit 0" test "$rc" = 0
    pruefe "install.sh Lauf $n: 0 Änderungen ($zeile)" ohne_aenderungen "$zeile"
  done
  pruefe "Ablage leer" ablage_leer
}

schritt_aufraeumen() {
  echo "== aufraeumen"
  local timer
  oberflaeche stopp > /dev/null 2>&1 || true
  rm -f -- "$REGEL" "$HALT/halt" "$HALT/wartet" "$LAUFZEIT/$PAKET.pid"
  paket_weg "$PAKET" "$FREMD_PAKET"
  for timer in "${TIMER[@]}"; do rm -rf "/run/systemd/system/$timer.d"; done
  systemctl daemon-reload
  if [[ -e "$BAU/linger-war-aus" ]]; then loginctl disable-linger "$TESTER"; fi
  rm -rf -- "$BAU" "$ABLAGE" "$HALT"
  ok "aufgeräumt"
}

(( $# >= 1 )) || { sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
(( EUID == 0 )) || { echo "installer-e2e.sh: als root im Container" >&2; exit 2; }
[[ -f /.dockerenv || -n "${container:-}" ]] || { echo "installer-e2e.sh: nur im Testcontainer" >&2; exit 2; }
schritte=()
for s in "$@"; do
  case "$s" in
    alle) schritte+=("${ALLE[@]}") ;;
    *)
      if [[ " ${ALLE[*]} " == *" $s "* ]]; then schritte+=("$s"); else
        echo "installer-e2e.sh: unbekannter Schritt «$s»" >&2
        exit 2
      fi
      ;;
  esac
done
mkdir -p "$BAU"
for s in "${schritte[@]}"; do "schritt_$s"; done
echo
if (( fehler )); then echo "$fehler Fehler"; exit 1; fi
echo "alles in Ordnung"
