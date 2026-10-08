#!/usr/bin/env bash
# installer-e2e.sh <schritt>… – Ende-zu-Ende-Test des zen Installers (zenos-installer) im Testcontainer (als root im
# Container). Getestet wird mit dem echten zenos-installer, zenos-installer-bedienen (über sudo als tester, wie
# «zen install» im Terminal; pkexec braucht einen Agenten am Bildschirm), systemd, den Units, apt und dpkg. Das
# Test-Paket braucht keine Abhängigkeiten aus dem Netz.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, Arbeitsstand nach /opt/zenos):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-installer-e2e
#   docker exec -u tester -w /home/tester/zenOS zenos-installer-e2e ./scripts/install.sh
# Dann: docker exec zenos-installer-e2e bash /repo/test/container/installer-e2e.sh alle   (oder einzelne Schritte)
#
# Schritte (nach «einrichten» in dieser Reihenfolge):
#   einrichten   Test-.deb bauen (Programm, Starter, Symbol, Systemdienst mit postinst und prerm) in ~tester/Ablage
#   standard     .deb öffnet in der labwc-Sitzung der zen Installer (gio, xdg-mime)
#   ansehen      als tester: JSON mit bereit, neu, Hinweisen (Skripte, Dienst), Plan, Symbol
#   geaendert    Datei nach dem Ansehen verändert: Exit 3, nichts installiert, Ablage leer
#   plan         ein anderer Plan als der angezeigte: Exit 3, nichts installiert
#   installieren sudo zenos-installer-bedienen installieren PFAD SHA256 PLAN: Unit mit der SHA-256 als Instanz, das
#                Paket ist installiert, sein Dienst läuft, Liste, letzte.json mit dem Starter, Ablage leer, Log,
#                keine Unit «failed»; danach sagt ansehen «installiert»
#   entfernen    sudo zenos-installer-bedienen entfernen PAKET (Instanz maskiert): Paket und Dienst weg, Liste leer
#   aufraeumen   Test-Paket (falls noch da) und Dateien weg
#   alle         einrichten standard ansehen geaendert plan installieren entfernen aufraeumen

set -euo pipefail

TESTER=tester
PAKET=zenos-e2e-app
DIENST=zenos-e2e-app.service
ABLAGE=/home/$TESTER/Ablage/installer-e2e
DEB=$ABLAGE/zenos-e2e-app_1.0-1.deb
BAU=/srv/installer-e2e
PROGRAMM=/opt/zenos/scripts/bin/zenos-installer
HELFER=/opt/zenos/scripts/bin/zenos-installer-bedienen
ZUSTAND=/var/lib/zenos/installer

fehler=0
ok() { printf '  ✓ %s\n' "$*"; }
nein() { printf '  ✗ %s\n' "$*"; fehler=$((fehler + 1)); }
pruefe() { # TEXT BEFEHL…
  local text=$1
  shift
  if "$@"; then ok "$text"; else nein "$text"; fi
}
als_tester() { runuser -u "$TESTER" -- env -C "/home/$TESTER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TESTER")" "$@"; }
json() { python3 -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"; }
ansehen_json() { als_tester "$PROGRAMM" ansehen "$DEB" --json; }

schritt_einrichten() {
  echo "== einrichten"
  rm -rf -- "$BAU"
  mkdir -p "$BAU/paket/DEBIAN" "$BAU/paket/usr/bin" "$BAU/paket/usr/share/applications" \
    "$BAU/paket/usr/lib/systemd/system" "$BAU/paket/usr/share/icons/hicolor/scalable/apps"
  cat > "$BAU/paket/DEBIAN/control" <<EOF
Package: $PAKET
Version: 1.0-1
Architecture: $(dpkg --print-architecture)
Maintainer: Beispiel <info@example.org>
Homepage: https://example.org
Description: Testpaket für den zen Installer
 Nur im Testcontainer.
EOF
  printf '#!/bin/sh\nset -e\nif [ -d /run/systemd/system ]; then systemctl daemon-reload; systemctl enable --now %s; fi\n' \
    "$DIENST" > "$BAU/paket/DEBIAN/postinst"
  printf '#!/bin/sh\nset -e\nif [ -d /run/systemd/system ]; then systemctl disable --now %s || true; fi\n' \
    "$DIENST" > "$BAU/paket/DEBIAN/prerm"
  chmod 0755 "$BAU/paket/DEBIAN/postinst" "$BAU/paket/DEBIAN/prerm"
  printf '#!/bin/sh\nexec sleep infinity\n' > "$BAU/paket/usr/bin/$PAKET"
  chmod 0755 "$BAU/paket/usr/bin/$PAKET"
  printf '[Unit]\nDescription=zenOS-Test\n[Service]\nExecStart=/usr/bin/%s\n[Install]\nWantedBy=multi-user.target\n' \
    "$PAKET" > "$BAU/paket/usr/lib/systemd/system/$DIENST"
  printf '[Desktop Entry]\nType=Application\nName=E2E-App\nExec=%s\nIcon=%s\n' "$PAKET" "$PAKET" \
    > "$BAU/paket/usr/share/applications/$PAKET.desktop"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"></svg>\n' \
    > "$BAU/paket/usr/share/icons/hicolor/scalable/apps/$PAKET.svg"
  install -d -o "$TESTER" -g "$TESTER" "/home/$TESTER/Ablage" "$ABLAGE"
  dpkg-deb --root-owner-group --build "$BAU/paket" "$DEB" > /dev/null
  chown "$TESTER:$TESTER" "$DEB"
  install -d -o "$TESTER" -g "$TESTER" -m 0700 "/run/user/$(id -u "$TESTER")"
  pruefe "Test-Paket gebaut" test -s "$DEB"
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
  mv -f -- "$DEB.vorher" "$DEB"
  pruefe "Exit 3 (Datei seit dem Ansehen geändert)" test "$rc" = 3
  pruefe "nicht installiert" bash -c "! dpkg-query -W $PAKET > /dev/null 2>&1"
  pruefe "Ablage leer" test -z "$(ls -A "$ZUSTAND/ablage")"
}

schritt_plan() {
  echo "== plan"
  local sha rc=0
  sha=$(ansehen_json | json 'd["sha256"]')
  als_tester sudo "$HELFER" installieren "$DEB" "$sha" "$(printf '0%.0s' {1..40})" || rc=$?
  pruefe "Exit 3 (Plan geändert)" test "$rc" = 3
  pruefe "letzte.json: abgelehnt" test "$(json 'd["ergebnis"]' < "$ZUSTAND/letzte.json")" = abgelehnt
  pruefe "nicht installiert" bash -c "! dpkg-query -W $PAKET > /dev/null 2>&1"
  pruefe "Ablage leer" test -z "$(ls -A "$ZUSTAND/ablage")"
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
  pruefe "Ablage leer" test -z "$(ls -A "$ZUSTAND/ablage")"
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
  pruefe "Paket weg" bash -c "! dpkg-query -W -f='\${db:Status-Status}' $PAKET 2>/dev/null | grep -q '^installed'"
  pruefe "Dienst weg" bash -c "! systemctl --quiet is-active $DIENST"
  pruefe "Liste leer" test "$(als_tester "$PROGRAMM" liste --json | json 'd["pakete"]')" = "[]"
  pruefe "letzte.json: entfernt" test "$(json 'd["ergebnis"]' < "$ZUSTAND/letzte.json")" = entfernt
  rc=0
  als_tester sudo "$HELFER" entfernen bash || rc=$?
  pruefe "bash kam nicht über den zen Installer: Exit 3" test "$rc" = 3
}

schritt_aufraeumen() {
  echo "== aufraeumen"
  if dpkg-query -W "$PAKET" > /dev/null 2>&1; then apt-get remove -y -q "$PAKET" > /dev/null; fi
  rm -rf -- "$BAU" "$ABLAGE"
  ok "aufgeräumt"
}

(( $# >= 1 )) || { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
(( EUID == 0 )) || { echo "installer-e2e.sh: als root im Container" >&2; exit 2; }
schritte=()
for s in "$@"; do
  case "$s" in
    alle) schritte+=(einrichten standard ansehen geaendert plan installieren entfernen aufraeumen) ;;
    einrichten | standard | ansehen | geaendert | plan | installieren | entfernen | aufraeumen) schritte+=("$s") ;;
    *) echo "installer-e2e.sh: unbekannter Schritt «$s»" >&2; exit 2 ;;
  esac
done
for s in "${schritte[@]}"; do "schritt_$s"; done
echo
if (( fehler )); then echo "$fehler Fehler"; exit 1; fi
echo "alles in Ordnung"
