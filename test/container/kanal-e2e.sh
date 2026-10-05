#!/usr/bin/env bash
# kanal-e2e.sh <schritt> – Ende-zu-Ende-Test des signierten Kanals im Testcontainer (als root im Container).
#
# Baut ein eigenes origin: einen https-Server im Container (zenos-remote.test:8443, Wegwerf-CA, «dumb HTTP» über
# Python) mit einem blanken Repo, dazu Wegwerf-Schlüssel (Release, Wurzel), alles zur Laufzeit unter /srv/kanal-e2e.
# Nichts davon verlässt den Container. Getestet wird mit dem echten zen, install.sh, systemd und den Units.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, ~/zenOS auf dem Stand vor diesem Code):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-kanal-e2e
#   docker exec -u tester -w /home/tester/zenOS zenos-kanal-e2e ./scripts/install.sh   (alter Stand nach /opt/zenos)
# Dann je Schritt: docker exec zenos-kanal-e2e bash /repo/test/container/kanal-e2e.sh <schritt>
#
# Schritte (in dieser Reihenfolge; «abbruch» und «zweimal» verlangen danach einen Neustart des Containers):
#   einrichten   CA, Server, Schlüssel, origin mit dem Stand von ~tester/zenOS als dev (idempotent, auch nach Neustart)
#   migration    Arbeitsstand von /repo als neuer Commit auf dev; das alte «zen update» bringt den neuen Kanal
#   dev          Anker ohne Schlüssel: unsignierter Commit, «nein» ändert nichts, «ja» installiert; install.sh
#                zweimal als root aus der Bereitstellung (zweiter Lauf 0 Änderungen)
#   signiert     Anker aus Wegwerf-Schlüsseln, Kanal vorschau, signierter Tag ohne Frage installiert
#   kaputt       signierter Stand mit Modul, das abbricht: Rückweg, gesperrt
#   gesundheit   signierter Stand mit leerem scripts/zen: Rückweg
#   platz        kleines tmpfs auf bereit/: wartet (Exit 10), nichts geändert
#   rueckfrage   signierter Stand, der Netz trifft: nur mit Zustimmung
#   abbruch      Installation mit SIGKILL mitten im Lauf, danach halbe Übernahme nachgestellt → Neustart nötig
#   nach-abbruch nachstart lief vor greetd und hat den Code vollendet; zen update setzt fort
#   zweimal      zwei Abbrüche hintereinander → Neustart nötig
#   nach-zweimal nachstart nahm den Rückweg; zen update meldet «zurueck»
#   rollback     zen rollback auf einen signierten Tag (ohne Frage) und auf einen unsignierten (nur mit «ja»), dann
#                zurück mit dem alten zen update dieses Stands
#   werkbank     install.sh von Hand aus ~/zenOS mit einem nicht gepushten Commit: wartet auf die Kanal-Sperre,
#                «angehalten»; zen update kehrt nur mit «ja» zum Kanal zurück
#   stopp        SIGTERM an den Dienst während install.sh (Ausschalten): install.sh läuft zu Ende, Ergebnis gesund
#   notweg       zenos-kanal fehlt: zen update verweist auf ANLEITUNG F; der Notweg ohne zen (fetch, checkout,
#                install.sh) bringt ihn zurück, danach geht zen update wieder

set -euo pipefail

E2E=/srv/kanal-e2e
REMOTE=$E2E/remote/zenOS.git
ARBEIT=$E2E/arbeit
URL=https://zenos-remote.test:8443/zenOS.git
STAND=/var/lib/zenos/kanal
TESTER=tester

ok() { printf '  ok  %s\n' "$*"; }
fehler() { printf '  FEHLER  %s\n' "$*" >&2; exit 1; }
schritt() { printf '\n== %s\n' "$*"; }

# Git als root in fremden Ordnern (/repo gehört dem Mac-Benutzer), nur für diese Aufrufe
g() { GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' git "$@"; }
ga() { g -C "$ARBEIT" -c user.name=e2e -c user.email=e2e@example.invalid -c gpg.format=ssh "$@"; }

# enthaelt MUSTER BEFEHL… – kommt MUSTER in der Ausgabe von BEFEHL vor? Ohne Pipe: Mit pipefail scheiterte
# «BEFEHL | grep -q», sobald grep früh schliesst und BEFEHL an SIGPIPE endet.
enthaelt() {
  local muster=$1 text
  shift
  text=$("$@" 2>/dev/null) || true
  grep -q -- "$muster" <<< "$text"
}

json() { # DATEI AUSDRUCK – Wert aus einer JSON-Datei (jq)
  jq -r "$2" "$1" 2>/dev/null || printf '?'
}

# zen als tester in einem Pseudo-Terminal; ANTWORT geht als Eingabe hinein. Ausgabe in $E2E/zen.out, Rückgabe der Exit
zen_als_tester() { # ANTWORT BEFEHL…
  local antwort=$1 rc=0
  shift
  printf '%s\n' "$antwort" | runuser -u "$TESTER" -- env HOME=/home/$TESTER script -qefc "$*" /dev/null \
    > "$E2E/zen.out" 2>&1 || rc=$?
  tr -d '\r' < "$E2E/zen.out" > "$E2E/zen.txt"
  return "$rc"
}

pushen() { # REF…
  ga push -q --force "$REMOTE" "$@"
  g -C "$REMOTE" update-server-info
}

neuer_commit() { # NACHRICHT [DATEI INHALT]… – Commit auf dev in $ARBEIT, gepusht; gibt die ID aus
  local nachricht=$1
  shift
  while (( $# >= 2 )); do
    mkdir -p "$ARBEIT/$(dirname "$1")"
    printf '%s' "$2" > "$ARBEIT/$1"
    [[ "$1" != *.sh ]] || chmod 0755 "$ARBEIT/$1"
    shift 2
  done
  ga add -A
  ga commit -q --allow-empty -m "$nachricht"
  pushen dev
  ga rev-parse HEAD
}

signieren() { # TAG – signierter Tag auf HEAD von $ARBEIT mit dem Wegwerf-Release-Schlüssel, gepusht
  ga -c user.signingkey="$E2E/schluessel/rel" tag -s -m "zenOS $1" "$1"
  pushen "refs/tags/$1"
}

kopf() { git -c safe.directory=/opt/zenos -C /opt/zenos rev-parse HEAD; }

erwarte_kopf() { # COMMIT TEXT
  [[ "$(kopf)" == "$1" ]] || fehler "$2: /opt/zenos steht auf $(kopf | cut -c1-12), erwartet ${1:0:12}"
  [[ -z "$(git -c safe.directory=/opt/zenos -C /opt/zenos status --porcelain)" ]] || fehler "$2: /opt/zenos nicht sauber"
  ok "$2: /opt/zenos auf ${1:0:12}, sauber"
}

erwarte_rc() { # IST SOLL TEXT
  [[ "$1" == "$2" ]] || { sed 's/^/      /' "$E2E/zen.txt" | tail -n 40 >&2; fehler "$3: Exit $1, erwartet $2"; }
  ok "$3: Exit $1"
}

erwarte_text() { # MUSTER TEXT
  grep -q -- "$1" "$E2E/zen.txt" || { sed 's/^/      /' "$E2E/zen.txt" | tail -n 40 >&2; fehler "$2: «$1» fehlt"; }
  ok "$2"
}

anker_schreiben() { # mit Wegwerf-Schlüsseln, Serie 1
  install -d -m 0755 /etc/zenos/vertrauen
  printf 'zenos-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$E2E/schluessel/rel.pub")" > /etc/zenos/vertrauen/release
  printf 'zenos-wurzel namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$E2E/schluessel/wur.pub")" > /etc/zenos/vertrauen/wurzel
  printf '# keine\n' > /etc/zenos/vertrauen/widerrufen
  printf '1\n' > /etc/zenos/vertrauen/serie
  chmod 0644 /etc/zenos/vertrauen/*
}

anker_leeren() { # wie heute im Repo: nur Kommentare
  local name
  for name in release wurzel widerrufen serie; do
    install -m 0644 "/repo/system/vertrauen/$name" "/etc/zenos/vertrauen/$name"
  done
}

kanal() { printf '%s\n' "$1" > /etc/xdg/zenos/kanal; }

# --- Schritte ------------------------------------------------------------------------------------------------------

s_einrichten() {
  schritt "einrichten"
  install -d -m 0755 "$E2E" "$E2E/ca" "$E2E/remote"
  install -d -m 0700 "$E2E/schluessel"
  if [[ ! -f "$E2E/ca/server.crt" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out "$E2E/ca/ca.key" 2>/dev/null
    openssl req -x509 -new -key "$E2E/ca/ca.key" -subj "/CN=zenOS e2e CA" -days 3 -out "$E2E/ca/ca.crt" \
      -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign 2>/dev/null
    openssl ecparam -name prime256v1 -genkey -noout -out "$E2E/ca/server.key" 2>/dev/null
    openssl req -new -key "$E2E/ca/server.key" -subj "/CN=zenos-remote.test" -out "$E2E/ca/server.csr" 2>/dev/null
    printf 'subjectAltName=DNS:zenos-remote.test\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' \
      > "$E2E/ca/server.ext"
    openssl x509 -req -in "$E2E/ca/server.csr" -CA "$E2E/ca/ca.crt" -CAkey "$E2E/ca/ca.key" -CAcreateserial \
      -days 3 -out "$E2E/ca/server.crt" -extfile "$E2E/ca/server.ext" 2>/dev/null
    install -m 0644 "$E2E/ca/ca.crt" /usr/local/share/ca-certificates/zenos-e2e.crt
    update-ca-certificates > /dev/null 2>&1
  fi
  grep -q 'zenos-remote\.test' /etc/hosts || printf '127.0.0.1 zenos-remote.test\n' >> /etc/hosts
  cat > "$E2E/server.py" <<'PY'
import functools
import http.server
import ssl

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/srv/kanal-e2e/remote")
server = http.server.ThreadingHTTPServer(("127.0.0.1", 8443), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/srv/kanal-e2e/ca/server.crt", "/srv/kanal-e2e/ca/server.key")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
  if ! systemctl --quiet is-active zenos-e2e-remote.service; then
    systemctl reset-failed zenos-e2e-remote.service 2>/dev/null || true
    systemd-run --quiet --unit=zenos-e2e-remote --property=Restart=always /usr/bin/python3 "$E2E/server.py"
    sleep 1
  fi
  ok "https-Server zenos-remote.test:8443"
  for name in rel wur; do
    [[ -f "$E2E/schluessel/$name" ]] || ssh-keygen -q -t ed25519 -N '' -C '' -f "$E2E/schluessel/$name"
  done
  ok "Wegwerf-Schlüssel (Release, Wurzel)"
  if [[ ! -d "$REMOTE" ]]; then
    g init -q --bare "$REMOTE"
    g clone -q --no-local "/home/$TESTER/zenOS" "$ARBEIT"
    ga checkout -q -B dev
    pushen dev 'refs/tags/*'
  fi
  g ls-remote "$URL" refs/heads/dev > /dev/null || fehler "origin über https nicht erreichbar"
  ok "origin $URL mit dev $(g -C "$REMOTE" rev-parse --short dev)"
  [[ "$(git -c safe.directory=/opt/zenos -C /opt/zenos remote get-url origin)" == "$URL" ]] ||
    fehler "/opt/zenos hat nicht origin $URL (zuerst install.sh aus ~/zenOS mit diesem origin)"
  ok "/opt/zenos folgt $URL"
}

s_migration() {
  schritt "migration: altes zen update bringt den neuen Kanal"
  local neu rc=0 datei
  ga rm -q -r --cached . > /dev/null
  find "$ARBEIT" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  g -C /repo ls-files -z -co --exclude-standard | while IFS= read -r -d '' datei; do
    [[ -e "/repo/$datei" || -L "/repo/$datei" ]] && printf '%s\0' "$datei"
  done | tar -C /repo --null -T - -cf - | tar -C "$ARBEIT" -xf -
  neu=$(neuer_commit "kanal: Stand aus /repo (e2e)")
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 0 "altes zen update"
  erwarte_kopf "$neu" "neuer Stand"
  grep -q 'def cmd_install' /usr/local/libexec/zenos/zenos-kanal || fehler "neuer zenos-kanal fehlt"
  for datei in installieren nachstart; do
    [[ -f "/etc/systemd/system/zenos-kanal-$datei.service" ]] || fehler "zenos-kanal-$datei.service fehlt"
  done
  [[ "$(systemctl is-enabled zenos-kanal-nachstart.service)" == enabled ]] || fehler "nachstart nicht aktiviert"
  ok "zenos-kanal, Units, nachstart aktiviert"
  systemd-analyze verify /etc/systemd/system/zenos-kanal-*.service > "$E2E/verify.txt" 2>&1 ||
    { cat "$E2E/verify.txt" >&2; fehler "systemd-analyze verify"; }
  ok "systemd-analyze verify ohne Befund"
}

s_dev() {
  schritt "dev ohne Anker: nur mit «ja», gebunden an den Commit"
  local neu rc=0 bereit zeile
  anker_leeren
  kanal dev
  neu=$(neuer_commit "e2e: dev unsigniert" e2e/dev "1")
  zen_als_tester "nein" zen update || rc=$?
  erwarte_rc "$rc" 10 "zen update mit «nein»"
  erwarte_text "Anker fehlt" "Hinweis «Anker fehlt»"
  erwarte_text "? ${neu:0:12} e2e: dev unsigniert" "neuer Commit gezeigt"
  [[ "$(kopf)" != "$neu" ]] || fehler "ohne «ja» installiert"
  ok "ohne «ja» nichts installiert"
  rc=0
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update mit «ja»"
  erwarte_kopf "$neu" "dev installiert"
  [[ "$(json "$STAND/gut.json" .commit)" == "$neu" ]] || fehler "gut.json"
  [[ "$(json "$STAND/letzte.json" .ergebnis)" == installiert ]] || fehler "letzte.json"
  erwarte_text "Benutzerteile\|install.sh\|Änderung" "Benutzerteile danach"
  ok "gut.json und letzte.json"
  enthaelt "install.sh aus $STAND/bereit/$neu" journalctl -b -u zenos-kanal-installieren.service --no-pager -o cat ||
    fehler "Journal der Installation"
  ok "Installation lief als Dienst (Journal)"

  schritt "install.sh als root aus der Bereitstellung, ohne Terminal, zweimal"
  bereit=$STAND/bereit/$neu
  for _ in 1 2; do
    systemd-run --quiet --wait --collect --pipe -p Environment=HOME=/root -p Environment=ZENOS_KANAL_LAUF=1 \
      "$bereit/scripts/install.sh" --ruhig < /dev/null > "$E2E/root-install.txt" 2>&1 ||
      { cat "$E2E/root-install.txt" >&2; fehler "install.sh als root"; }
  done
  zeile=$(grep '^== Ende' /var/log/zenos/install.log | tail -n 1)
  [[ "$zeile" == *" · normal · ok · 0 Änderungen · "* ]] || fehler "zweiter Lauf: $zeile"
  ok "zweiter Lauf: $zeile"
}

s_signiert() {
  schritt "signiert: vorschau, Tag ohne Frage"
  local neu rc=0
  anker_schreiben
  kanal vorschau
  neu=$(neuer_commit "e2e: signiert" e2e/signiert "1")
  signieren v0.1.1-rc1
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update"
  if grep -q "Tippe «ja»" "$E2E/zen.txt"; then fehler "fragte trotz Signatur"; fi
  erwarte_kopf "$neu" "v0.1.1-rc1 installiert"
  [[ "$(cat "$STAND/hoechste")" == v0.1.1-rc1 ]] || fehler "hoechste"
  ok "hoechste v0.1.1-rc1"
  runuser -u "$TESTER" -- zen version > "$E2E/zen.txt"
  erwarte_text "^Update  *v0.1.1-rc1" "zen version zeigt den Stand"
  runuser -u "$TESTER" -- zen doctor > "$E2E/zen.txt" 2>&1 || true
  erwarte_text "Installation: v0.1.1-rc1" "zen doctor: Installation"
}

s_kaputt() {
  schritt "kaputt: Modul bricht ab → Rückweg"
  local gut rc=0
  gut=$(kopf)
  neuer_commit "e2e: kaputt" scripts/module/99-e2e-kaputt.sh \
    $'#!/usr/bin/env bash\n# 99-e2e-kaputt: nur im Ende-zu-Ende-Test\n# shellcheck shell=bash\nmodul_system() { abbruch "e2e: absichtlich kaputt"; }\n' > /dev/null
  signieren v0.1.1-rc2
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 4 "zen update"
  erwarte_text "zurück auf dem Stand davor" "Ergebnis «zurueck»"
  erwarte_kopf "$gut" "zurück auf v0.1.1-rc1"
  [[ ! -e /opt/zenos/scripts/module/99-e2e-kaputt.sh ]] || fehler "kaputtes Modul liegt noch da"
  [[ -f "$STAND/gesperrt/v0.1.1-rc2" ]] || fehler "nicht gesperrt"
  ok "v0.1.1-rc2 gesperrt, Modul weg"
  rc=0
  zen_als_tester "nein" zen update || rc=$?
  erwarte_rc "$rc" 10 "nochmals: gesperrt, nur mit «ja»"
  erwarte_text "ist gesperrt" "Grund «gesperrt»"
}

s_gesundheit() {
  schritt "gesundheit: leeres scripts/zen → Rückweg"
  local gut rc=0
  gut=$(kopf)
  ga rm -q scripts/module/99-e2e-kaputt.sh
  neuer_commit "e2e: zen leer" scripts/zen "" > /dev/null
  signieren v0.1.1-rc3
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 4 "zen update"
  [[ "$(json "$STAND/letzte.json" .grund)" == *"scripts/zen fehlt oder ist leer"* ]] || fehler "Grund"
  erwarte_kopf "$gut" "zurück"
  [[ -s /opt/zenos/scripts/zen ]] || fehler "scripts/zen leer"
  ok "scripts/zen wieder da"
  ga checkout -q HEAD~1 -- scripts/zen
}

s_platz() {
  schritt "platz: kleines tmpfs auf bereit/ → wartet"
  local gut rc=0
  gut=$(kopf)
  neuer_commit "e2e: platz" e2e/platz "1" > /dev/null
  signieren v0.1.1-rc4
  mount -t tmpfs -o size=20m tmpfs "$STAND/bereit"
  zen_als_tester "" zen update || rc=$?
  umount "$STAND/bereit"
  erwarte_rc "$rc" 10 "zen update"
  erwarte_text "MB frei" "Grund «Platz»"
  erwarte_kopf "$gut" "nichts geändert"
}

s_rueckfrage() {
  schritt "rueckfrage: Netz betroffen → nur mit Zustimmung"
  local gut rc=0
  gut=$(kopf)
  printf '\n# e2e\n' >> "$ARBEIT/scripts/module/35-netzwerk.sh"
  neuer_commit "e2e: netz" > /dev/null
  signieren v0.1.1-rc5
  zen_als_tester "nein" zen update || rc=$?
  erwarte_rc "$rc" 10 "zen update mit «nein»"
  erwarte_text "Betrifft Firewall, Netz oder Boot: scripts/module/35-netzwerk.sh" "Rückfrage-Pfad genannt"
  erwarte_kopf "$gut" "nichts geändert"
  /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal status --kurz > "$E2E/zen.txt"
  erwarte_text "^zustimmung " "Status «zustimmung»"
  rc=0
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update mit «ja»"
}

s_abbruch() {
  schritt "abbruch: SIGKILL während install.sh"
  local neu i
  neu=$(neuer_commit "e2e: warten" scripts/module/11-e2e-warten.sh \
    $'#!/usr/bin/env bash\n# 11-e2e-warten: nur im Ende-zu-Ende-Test: wartet, solange /srv/kanal-e2e/warten da ist\n# shellcheck shell=bash\nmodul_system() {\n  local i=0\n  log_info "e2e: warte"\n  while [[ -e /srv/kanal-e2e/warten ]] && (( i < 600 )); do sleep 1; i=$((i + 1)); done\n}\n')
  signieren v0.1.2-rc1
  touch "$E2E/warten"
  (zen_als_tester "" zen update || true) &
  for i in $(seq 1 120); do
    grep -q "e2e: warte" /var/log/zenos/install.log 2>/dev/null && [[ "$(kopf)" == "$neu" ]] && break
    sleep 1
  done
  (( i < 120 )) || fehler "install.sh kam nicht bis zum Warten"
  enthaelt "zenOS wird aktualisiert" systemd-inhibit --list --no-pager || fehler "kein Inhibitor"
  ok "Block-Inhibitor während install.sh"
  [[ -f /run/zenos-kanal/uebernahme ]] || fehler "Flag uebernahme fehlt"
  ok "Flag /run/zenos-kanal/uebernahme"
  systemctl kill --signal=KILL zenos-kanal-installieren.service
  wait || true
  sleep 1
  [[ "$(json "$STAND/laeuft.json" .versuche.ziel)" == 1 ]] || fehler "laeuft.json"
  ok "laeuft.json bleibt (Versuch 1)"
  # Halbe Übernahme nachstellen: zwei Dateien noch alt
  printf '# alt\n' >> /opt/zenos/scripts/zen.d/version.sh
  rm -f /opt/zenos/scripts/module/11-e2e-warten.sh
  printf '%s\n' "$neu" > "$E2E/abbruch-ziel"
  ok "jetzt den Container neu starten (docker restart), dann: nach-abbruch"
}

s_nach_abbruch() {
  schritt "nach-abbruch: nachstart vor greetd, dann zen update"
  local neu rc=0 ende start
  neu=$(cat "$E2E/abbruch-ziel")
  journalctl -b -u zenos-kanal-nachstart.service --no-pager -o cat > "$E2E/zen.txt"
  erwarte_text "Code vollständig" "nachstart hat den Code vollendet"
  ende=$(systemctl show -p ExecMainExitTimestampMonotonic --value zenos-kanal-nachstart.service)
  start=$(systemctl show -p InactiveExitTimestampMonotonic --value greetd.service)
  if [[ "$start" =~ ^[1-9][0-9]*$ ]]; then
    (( ende <= start )) || fehler "greetd startete vor dem Ende von nachstart"
    ok "nachstart endete vor dem Start von greetd"
  else
    enthaelt zenos-kanal-nachstart systemctl list-dependencies --after greetd.service --plain --no-pager ||
      fehler "greetd ist nicht nach nachstart geordnet"
    ok "greetd ist nach nachstart geordnet (startet im Container nicht)"
  fi
  erwarte_kopf "$neu" "Code nach dem Start vollständig"
  [[ -f "$STAND/laeuft.json" ]] || fehler "laeuft.json fehlt"
  rm -f "$E2E/warten"
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update setzt fort"
  erwarte_text "unterbrochen" "Hinweis «unterbrochen»"
  [[ "$(json "$STAND/letzte.json" .versuche.ziel)" == 2 ]] || fehler "Versuch 2"
  erwarte_kopf "$neu" "fertig installiert"
}

s_zweimal() {
  schritt "zweimal: zwei Abbrüche"
  local gut neu i n vorher
  gut=$(kopf)
  neu=$(neuer_commit "e2e: zweimal" e2e/zweimal "1")
  signieren v0.1.2-rc2
  touch "$E2E/warten"
  vorher=$(grep -c 'e2e: warte' /var/log/zenos/install.log || true)
  for n in 1 2; do
    (zen_als_tester "" zen update || true) &
    for i in $(seq 1 120); do
      [[ "$(json "$STAND/laeuft.json" .versuche.ziel)" == "$n" ]] &&
        (( $(grep -c 'e2e: warte' /var/log/zenos/install.log || true) >= vorher + n )) && break
      sleep 1
    done
    (( i < 120 )) || fehler "Lauf $n kam nicht bis zum Warten"
    systemctl kill --signal=KILL zenos-kanal-installieren.service
    wait || true
    sleep 1
  done
  [[ "$(json "$STAND/laeuft.json" .versuche.ziel)" == 2 ]] || fehler "laeuft.json nach zwei Abbrüchen"
  rm -f "$E2E/warten"
  printf '%s %s\n' "$gut" "$neu" > "$E2E/zweimal"
  ok "zwei Abbrüche, jetzt den Container neu starten (docker restart), dann: nach-zweimal"
}

s_nach_zweimal() {
  schritt "nach-zweimal: nachstart nimmt den Rückweg"
  local gut rc=0
  read -r gut _ < "$E2E/zweimal"
  journalctl -b -u zenos-kanal-nachstart.service --no-pager -o cat > "$E2E/zen.txt"
  erwarte_text "gesperrt, Rückweg" "nachstart: gesperrt, Rückweg"
  erwarte_kopf "$gut" "Code des Rückwegs vor dem Login"
  [[ -f "$STAND/gesperrt/v0.1.2-rc2" ]] || fehler "nicht gesperrt"
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 4 "zen update vollendet den Rückweg"
  [[ "$(json "$STAND/letzte.json" .ergebnis)" == zurueck ]] || fehler "letzte.json"
  erwarte_kopf "$gut" "Rückweg fertig"
}

s_rollback() {
  schritt "rollback: signiert ohne Frage, unsigniert nur mit «ja»"
  local rc=0 ziel
  ziel=$(g -C "$REMOTE" rev-parse 'v0.1.1-rc5^{commit}')
  zen_als_tester "" zen rollback v0.1.1-rc5 || rc=$?
  erwarte_rc "$rc" 0 "zen rollback v0.1.1-rc5"
  if grep -q "Tippe «ja»" "$E2E/zen.txt"; then fehler "fragte trotz Signatur"; fi
  erwarte_kopf "$ziel" "auf v0.1.1-rc5"
  [[ "$(cat "$STAND/hoechste")" == v0.1.2-rc1 ]] || fehler "hoechste sank"
  ok "hoechste bleibt v0.1.2-rc1"
  ziel=$(g -C "$REMOTE" rev-parse 'v0.1.0-rc3^{commit}')
  rc=0
  zen_als_tester "nein" zen rollback v0.1.0-rc3 || rc=$?
  erwarte_rc "$rc" 10 "unsigniert mit «nein»"
  erwarte_text "ungeprüft (nicht gültig signiert: unsigniert)" "Grund «unsigniert»"
  erwarte_text "Betrifft Firewall, Netz oder Boot" "Grund «Rückfrage-Pfade»"
  rc=0
  zen_als_tester "ja" zen rollback v0.1.0-rc3 || rc=$?
  erwarte_rc "$rc" 0 "unsigniert mit «ja»"
  erwarte_kopf "$ziel" "auf v0.1.0-rc3 (alter Stand ohne diesen Kanal-Code)"
  # Der alte zen update kennt nur Branches als Kanal
  kanal dev
  rc=0
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update (alter Weg aus v0.1.0-rc3) zurück auf dev"
}

s_notweg() {
  schritt "notweg: ANLEITUNG F ohne zen, auch wenn der Kanal kaputt ist"
  local rc=0 spitze
  spitze=$(neuer_commit "e2e: vor dem notweg" e2e/vor-notweg "1")
  rm -f /usr/local/libexec/zenos/zenos-kanal
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 1 "zen update ohne zenos-kanal"
  erwarte_text "ANLEITUNG.md, Abschnitt F" "Verweis auf den Notweg"
  runuser -u "$TESTER" -- sudo git -C /opt/zenos fetch --no-tags origin dev
  runuser -u "$TESTER" -- sudo git -C /opt/zenos checkout --force -B dev origin/dev
  runuser -u "$TESTER" -- env HOME=/home/$TESTER /opt/zenos/scripts/install.sh > "$E2E/zen.txt" 2>&1 ||
    { tail -n 30 "$E2E/zen.txt" >&2; fehler "install.sh nach dem Notweg"; }
  erwarte_kopf "$spitze" "Notweg auf origin/dev"
  [[ -f /usr/local/libexec/zenos/zenos-kanal ]] || fehler "install.sh hat zenos-kanal nicht wiederhergestellt"
  ok "zenos-kanal wieder da"
  anker_leeren
  rc=0
  kanal dev
  neuer_commit "e2e: nach dem notweg" e2e/notweg "1" > /dev/null
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update danach"
}

s_werkbank() {
  schritt "werkbank: install.sh von Hand aus ~/zenOS wartet auf den Kanal und hält ihn an"
  local spitze lokal rc=0 halter quelle=/home/$TESTER/zenOS
  anker_leeren
  kanal dev
  spitze=$(neuer_commit "e2e: vor der werkbank" e2e/werkbank-vorher "1")
  runuser -u "$TESTER" -- git -C "$quelle" fetch -q origin dev
  runuser -u "$TESTER" -- git -C "$quelle" checkout -q --force -B werkbank FETCH_HEAD
  runuser -u "$TESTER" -- mkdir -p "$quelle/e2e"
  printf '1\n' | runuser -u "$TESTER" -- tee "$quelle/e2e/werkbank" > /dev/null
  runuser -u "$TESTER" -- git -C "$quelle" add e2e/werkbank
  runuser -u "$TESTER" -- git -C "$quelle" -c user.name=e2e -c user.email=e2e@example.invalid commit -q -m "e2e: werkbank"
  lokal=$(runuser -u "$TESTER" -- git -C "$quelle" rev-parse HEAD)
  # Die Kanal-Sperre 8 s lang halten, als liefe gerade eine Prüfung
  flock /run/lock/zenos-kanal.lock sleep 8 &
  halter=$!
  sleep 1
  runuser -u "$TESTER" -- env HOME=/home/$TESTER "$quelle/scripts/install.sh" > "$E2E/zen.txt" 2>&1 ||
    { tail -n 30 "$E2E/zen.txt" >&2; fehler "install.sh aus ~/zenOS"; }
  wait "$halter"
  erwarte_text "Der Kanal prüft oder installiert gerade, warte" "wartet auf die Kanal-Sperre"
  erwarte_kopf "$lokal" "Arbeitsstand in /opt/zenos"
  [[ "$(json "$STAND/angehalten" .commit)" == "$lokal" ]] || fehler "angehalten fehlt"
  /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal status --installation > "$E2E/zen.txt"
  erwarte_text "^angehalten " "Status «angehalten»"
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update"
  erwarte_text "liegt nicht in origin/dev" "Grund: Stand nicht auf origin (aus /opt/zenos verglichen)"
  erwarte_kopf "$spitze" "zurück auf dem Kanal"
  [[ ! -e "$STAND/angehalten" ]] || fehler "angehalten bleibt"
  ok "angehalten aufgehoben"
}

s_stopp() {
  schritt "stopp: SIGTERM an den Dienst (KillMode=mixed) bricht install.sh nicht ab"
  local neu i
  anker_leeren
  kanal dev
  [[ -f "$ARBEIT/scripts/module/11-e2e-warten.sh" ]] || fehler "zuerst «abbruch» (Modul 11-e2e-warten)"
  neu=$(neuer_commit "e2e: stopp" e2e/stopp "1")
  touch "$E2E/warten"
  (zen_als_tester "ja" zen update || true) &
  for i in $(seq 1 120); do
    [[ "$(kopf)" == "$neu" ]] && enthaelt "e2e: warte" tail -n 5 /var/log/zenos/install.log && break
    sleep 1
  done
  (( i < 120 )) || fehler "install.sh kam nicht bis zum Warten"
  systemctl stop --no-block zenos-kanal-installieren.service
  sleep 3
  [[ "$(systemctl show -p ActiveState --value zenos-kanal-installieren.service)" == deactivating ]] ||
    fehler "Dienst nicht im Zustand deactivating"
  pgrep -f "bereit/$neu/scripts/install.sh" > /dev/null || fehler "install.sh wurde beendet"
  ok "nach SIGTERM: Dienst wartet, install.sh läuft weiter"
  rm -f "$E2E/warten"
  wait || true
  # Der Stopp bricht den wartenden Start-Auftrag ab: zen update kehrt früher zurück als der Dienst. Auf ihn warten.
  for i in $(seq 1 120); do
    case "$(systemctl show -p ActiveState --value zenos-kanal-installieren.service)" in inactive | failed) break ;; esac
    sleep 1
  done
  (( i < 120 )) || fehler "Dienst nach dem Stopp nicht fertig"
  [[ "$(json "$STAND/letzte.json" .ergebnis)" == installiert ]] || fehler "letzte.json: $(json "$STAND/letzte.json" .grund)"
  enthaelt "Stopp" json "$STAND/letzte.json" '.hinweise[]' || fehler "Hinweis auf den Stopp fehlt"
  erwarte_kopf "$neu" "trotz Stopp fertig installiert und gesund"
}

case "${1:-}" in
  einrichten) s_einrichten ;;
  migration) s_migration ;;
  dev) s_dev ;;
  signiert) s_signiert ;;
  kaputt) s_kaputt ;;
  gesundheit) s_gesundheit ;;
  platz) s_platz ;;
  rueckfrage) s_rueckfrage ;;
  abbruch) s_abbruch ;;
  nach-abbruch) s_nach_abbruch ;;
  zweimal) s_zweimal ;;
  nach-zweimal) s_nach_zweimal ;;
  rollback) s_rollback ;;
  notweg) s_notweg ;;
  stopp) s_stopp ;;
  werkbank) s_werkbank ;;
  *) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
