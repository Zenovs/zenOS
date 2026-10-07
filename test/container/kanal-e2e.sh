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
# Schritte (in dieser Reihenfolge; nach «abbruch» und «zweimal» Neustart des Containers, danach wieder «einrichten»):
#   einrichten   CA, Server, Schlüssel, origin mit dem Stand von ~tester/zenOS als dev (idempotent, auch nach Neustart)
#   migration    Arbeitsstand von /repo als neuer Commit auf dev; das alte «zen update» bringt den neuen Kanal
#   dev          Anker ohne Schlüssel: unsignierter Commit, «nein» ändert nichts, «ja» installiert; install.sh
#                zweimal als root aus der Bereitstellung (zweiter Lauf 0 Änderungen)
#   signiert     Anker aus Wegwerf-Schlüsseln, Kanal vorschau, signierter Tag ohne Frage installiert, auch während ein
#                Benutzerprozess install.log laufend kürzt (Gesundheit aus dem root-eigenen install-ergebnis)
#   basis        signierter Stand für Ubuntu 28.04 (system/basis): zen update lässt ihn liegen, zen rollback auch mit
#                «ja» nicht; Prompt=never liegt als Drop-in, zen doctor sagt es; danach dev wieder für 26.04
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
#                «angehalten»; die Automatik ruht darüber (vorschau, jederzeit); zen update kehrt nur mit «ja» zum
#                Kanal zurück
#   stopp        SIGTERM an den Dienst während install.sh (Ausschalten): install.sh läuft zu Ende, Ergebnis gesund
#   notweg       zenos-kanal fehlt: zen update verweist auf ANLEITUNG F; der Notweg ohne zen bringt ihn zurück: mit
#                Anker ein signierter Tag, gegen den Anker des Geräts geprüft (ein unsignierter fällt durch), ohne
#                Anker dev mit Blick auf die neuen Commits; danach geht zen update wieder
#   sperren      die Sperren gehören nur root: Ein Benutzer hält die alten in /run/lock und kommt an die neuen nicht
#                heran, zen update läuft trotzdem; ein install.sh von Hand hält den Kanal an (Exit 75), danach weiter
#   gitsperre    eine zurückgebliebene /opt/zenos/.git/index.lock: zen update räumt sie weg und installiert
#   probelauf    ein geänderter zenos-kanal macht im Selbsttest einen Probelauf; einer mit Laufzeitfehler in update
#                fällt auf: Rückweg (ohne Probelauf), danach geht zen update wieder
#   bedienung    (zuletzt, braucht nur «einrichten» und dieses Programm in /opt/zenos) Einstellungen › System › Updates
#                ohne Oberfläche: zenos-kanal-bedienen als root wie über pkexec. polkit kennt die Aktionen, Zeitpunkt
#                setzen (ein zu kurzes Fenster nicht), «Jetzt prüfen», «Jetzt installieren» (nur für den angezeigten
#                Stand, signiert, ohne Frage, danach neu geprüft), ein Stand, der Netz trifft (installieren wartet, zustimmen für ein anderes Objekt
#                nichts, für das gezeigte installiert), dev unsigniert (zustimmen abgelehnt, installieren wartet);
#                der Helfer liest Exit 3 und 10 und lässt keine Unit «failed» zurück
#   automatik    (braucht «einrichten», «bedienung» oder einen Anker und dieses Programm in /opt/zenos; vor dem ersten
#                install.sh den Notschalter setzen, siehe unten) Timer und Units, Notschalter (install.sh lässt die
#                Timer aus), nie auf dev, «von Hand» nur bereit, Zeitfenster über die Gelegenheit ohne Holen,
#                zenos-energie sagt während der Installation «Update läuft», «bei Sperre» mit einer über PAM gestellten
#                Sitzung auf seat0 und der echten Sperre der Oberfläche (eben gesperrt: noch nicht), zen rollback
#                stellt die verlassene Version zurück, dann ein automatisches Update mit Login-Bildschirm zum Schein
#                → Neustart nötig
#   nach-automatik   bestätigt nach dem Neustart (gut.json), dann ein automatisches Update ohne Login → Neustart nötig
#   nach-automatik-2 erster Start ohne Login: gezählt (wartet 3 Min.) → Neustart nötig
#   nach-automatik-3 zweiter Start ohne Login: gesperrt, zurück auf den guten Stand, greetd neu gestartet; aufräumen
#   automatik-uhr    (danach) stabil mit verstellter Zeit im Hauptbuch: erst gesehen, dann «erstmals» 25 h zurück
#                    (die Uhr sprang, seit dem Start verging kaum etwas: wartet), dann auch die Zeit seit dem Start
#                    25 h zurück (installiert)
#
# Die Timer der Automatik lösen im Test nie von selbst aus (einrichten legt einen Laufzeit-Drop-in an); der Test startet
# ihre Units von Hand. Für «automatik» in einem frischen Container: als root /etc/xdg/zenos/kanal-automatik-aus anlegen,
# origin von ~/zenOS auf die Adresse unten setzen, als tester install.sh, dann einrichten und automatik.

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

anker_leeren() { # ohne Schlüssel: nur die Kommentare aus dem Repo (wie vor den ersten Schlüsseln, die seit 04a5e86 dort stehen)
  local name
  for name in release wurzel widerrufen serie; do
    grep -E '^[[:space:]]*(#|$)' "/repo/system/vertrauen/$name" > "/etc/zenos/vertrauen/$name" || true
    chmod 0644 "/etc/zenos/vertrauen/$name"
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
  automatik_timer_zahm
  ok "Timer der Automatik lösen im Test nicht von selbst aus"
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
  # Befund sich-01: install.log gehört nach einem Lauf von Hand dem Benutzer. Ein Prozess als Benutzer kürzt es während
  # der ganzen Installation; die Gesundheitsprüfung liest nur das root-eigene Ergebnis und bleibt davon unberührt.
  chown "$TESTER" /var/log/zenos/install.log
  rm -f "$E2E/kuerzen.stopp"
  printf '%s\n' '#!/bin/bash' "until [[ -e $E2E/kuerzen.stopp ]]; do : > /var/log/zenos/install.log; sleep 0.2; done" \
    > "$E2E/kuerzen.sh"
  chmod 0755 "$E2E/kuerzen.sh"
  runuser -u "$TESTER" -- "$E2E/kuerzen.sh" &
  local kuerzer=$!
  zen_als_tester "" zen update || rc=$?
  : > "$E2E/kuerzen.stopp"
  wait "$kuerzer" || true
  erwarte_rc "$rc" 0 "zen update, während ein Benutzerprozess install.log laufend kürzt"
  [[ "$(stat -c '%U %a' "$STAND/install-ergebnis")" == "root 644" ]] || fehler "install-ergebnis nicht root 0644"
  grep -q '^== Ende .* · normal · ok · ' "$STAND/install-ergebnis" || fehler "install-ergebnis ohne «== Ende … ok»"
  ok "Gesundheit aus dem root-eigenen Ergebnis"
  if grep -q "Tippe «ja»" "$E2E/zen.txt"; then fehler "fragte trotz Signatur"; fi
  erwarte_kopf "$neu" "v0.1.1-rc1 installiert"
  [[ "$(cat "$STAND/hoechste")" == v0.1.1-rc1 ]] || fehler "hoechste"
  ok "hoechste v0.1.1-rc1"
  runuser -u "$TESTER" -- zen version > "$E2E/zen.txt"
  erwarte_text "^Update  *v0.1.1-rc1" "zen version zeigt den Stand"
  runuser -u "$TESTER" -- zen doctor > "$E2E/zen.txt" 2>&1 || true
  erwarte_text "Installation: v0.1.1-rc1" "zen doctor: Installation"
}

s_basis() {
  schritt "basis: ein Stand für eine andere Ubuntu-Version kommt nie"
  local vorher rc=0
  anker_schreiben
  kanal vorschau
  vorher=$(kopf)
  neuer_commit "e2e: für Ubuntu 28.04" system/basis $'28.04\n' > /dev/null
  signieren v0.9.0-rc1
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update mit einem Stand für 28.04"
  erwarte_text "v0.9.0-rc1 ist kein Ziel: gebaut für Ubuntu 28.04, dieses Gerät läuft auf Ubuntu 26.04" \
    "Hinweis: kein Ziel"
  erwarte_kopf "$vorher" "nichts installiert"
  [[ "$(json "$STAND/stand.json" .basis.geraet)" == 26.04 ]] || fehler "stand.json: basis.geraet"
  [[ "$(json "$STAND/stand.json" '.basis.fremd | any(. == "v0.9.0-rc1")')" == true ]] ||
    fehler "stand.json: basis.fremd"
  [[ "$(json "$STAND/stand.json" .zustand)" == aktuell ]] || fehler "stand.json: zustand"
  ok "stand.json: aktuell, v0.9.0-rc1 unter basis.fremd"
  rc=0
  zen_als_tester "ja" zen rollback v0.9.0-rc1 || rc=$?
  erwarte_rc "$rc" 3 "zen rollback v0.9.0-rc1 mit «ja»"
  erwarte_text "gebaut für Ubuntu 28.04" "abgelehnt: andere Basis"
  if grep -q "Tippe «ja»" "$E2E/zen.txt"; then fehler "fragte nach «ja»"; fi
  erwarte_kopf "$vorher" "auch mit «ja» nichts installiert"
  neuer_commit "e2e: wieder für Ubuntu 26.04" system/basis $'26.04\n' > /dev/null
  ok "dev wieder für 26.04 (die Schritte danach)"

  schritt "basis: Prompt=never"
  cmp -s /etc/update-manager/release-upgrades.d/zenos.cfg /opt/zenos/system/update-manager/zenos.cfg ||
    fehler "Drop-in /etc/update-manager/release-upgrades.d/zenos.cfg fehlt oder weicht ab"
  [[ "$(stat -c '%U %a' /etc/update-manager/release-upgrades.d/zenos.cfg)" == "root 644" ]] ||
    fehler "Drop-in nicht root 0644"
  ok "Drop-in Prompt=never (root, 0644)"
  runuser -u "$TESTER" -- zen doctor > "$E2E/zen.txt" 2>&1 || true
  erwarte_text "Kein Wechsel der Ubuntu-Hauptversion: Prompt=never" "zen doctor: Prompt=never"
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
  # Seit Teil B ist eine gesperrte Version kein Ziel von zen update mehr; noch einmal nur mit zen rollback und «ja»
  rc=0
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 0 "nochmals zen update: gesperrt ist kein Ziel"
  erwarte_text "v0.1.1-rc2 ist gesperrt .* und kein Ziel" "Hinweis «gesperrt»"
  erwarte_kopf "$gut" "nichts geändert"
  rc=0
  zen_als_tester "nein" zen rollback v0.1.1-rc2 || rc=$?
  erwarte_rc "$rc" 10 "zen rollback auf die gesperrte Version: nur mit «ja»"
  erwarte_text "v0.1.1-rc2 ist gesperrt:" "Grund «gesperrt»"
  erwarte_kopf "$gut" "nichts geändert"
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
  ok "jetzt den Container neu starten (docker restart), dann: einrichten, nach-abbruch"
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
  ok "zwei Abbrüche, jetzt den Container neu starten (docker restart), dann: einrichten, nach-zweimal"
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
  local rc=0 spitze tag=v0.1.1-rc5 ziel
  anker_schreiben
  ziel=$(g -C "$REMOTE" rev-parse "$tag^{commit}")
  spitze=$(neuer_commit "e2e: vor dem notweg" e2e/vor-notweg "1")
  rm -f /usr/local/libexec/zenos/zenos-kanal
  zen_als_tester "" zen update || rc=$?
  erwarte_rc "$rc" 1 "zen update ohne zenos-kanal"
  erwarte_text "ANLEITUNG.md, Abschnitt F" "Verweis auf den Notweg"
  # Mit Anker: ein signierter Tag, mit den Befehlen aus ANLEITUNG F gegen den Anker des Geräts geprüft
  runuser -u "$TESTER" -- sudo git -C /opt/zenos fetch --no-tags origin "+refs/tags/$tag:refs/tags/$tag"
  runuser -u "$TESTER" -- sudo git -C /opt/zenos -c gpg.ssh.allowedSignersFile=/etc/zenos/vertrauen/release \
    -c gpg.ssh.revocationFile=/etc/zenos/vertrauen/widerrufen verify-tag -v "$tag" > "$E2E/zen.txt" 2>&1 ||
    { cat "$E2E/zen.txt" >&2; fehler "verify-tag gegen den Anker"; }
  erwarte_text "^tag $tag\$" "Name im Tag"
  erwarte_text 'Good "git" signature for zenos-release' "Signatur gegen den Anker"
  runuser -u "$TESTER" -- sudo git -C /opt/zenos fetch --no-tags origin "+refs/tags/v0.1.0-rc3:refs/tags/v0.1.0-rc3"
  if runuser -u "$TESTER" -- sudo git -C /opt/zenos -c gpg.ssh.allowedSignersFile=/etc/zenos/vertrauen/release \
    -c gpg.ssh.revocationFile=/etc/zenos/vertrauen/widerrufen verify-tag -v v0.1.0-rc3 > /dev/null 2>&1; then
    fehler "ein unsignierter Tag besteht die Prüfung des Notwegs"
  fi
  ok "ein unsignierter Tag fällt durch"
  runuser -u "$TESTER" -- sudo git -C /opt/zenos checkout --quiet --force "$tag"
  runuser -u "$TESTER" -- env HOME=/home/$TESTER /opt/zenos/scripts/install.sh > "$E2E/zen.txt" 2>&1 ||
    { tail -n 30 "$E2E/zen.txt" >&2; fehler "install.sh nach dem Notweg (Tag)"; }
  erwarte_kopf "$ziel" "Notweg auf $tag"
  [[ -f /usr/local/libexec/zenos/zenos-kanal ]] || fehler "install.sh hat zenos-kanal nicht wiederhergestellt"
  ok "zenos-kanal wieder da"
  # Ohne Anker: dev, mit Blick auf die neuen Commits
  anker_leeren
  runuser -u "$TESTER" -- sudo git -C /opt/zenos fetch --no-tags origin dev
  runuser -u "$TESTER" -- sudo git -C /opt/zenos log --format='%h %an %s' HEAD..origin/dev > "$E2E/zen.txt"
  erwarte_text "e2e: vor dem notweg" "neue Commits gezeigt"
  runuser -u "$TESTER" -- sudo git -C /opt/zenos checkout --quiet --force -B dev origin/dev
  runuser -u "$TESTER" -- env HOME=/home/$TESTER /opt/zenos/scripts/install.sh > "$E2E/zen.txt" 2>&1 ||
    { tail -n 30 "$E2E/zen.txt" >&2; fehler "install.sh nach dem Notweg (dev)"; }
  erwarte_kopf "$spitze" "Notweg auf origin/dev"
  [[ ! -e /run/zenos-sperre/hand ]] || fehler "Vermerk des Laufs von Hand bleibt liegen"
  ok "Vermerk des Laufs von Hand wieder weg"
  rc=0
  kanal dev
  neuer_commit "e2e: nach dem notweg" e2e/notweg "1" > /dev/null
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update danach"
}

s_sperren() {
  schritt "sperren: nur root kommt an die Sperren"
  local neu rc=0 i quelle=/home/$TESTER/zenOS hand
  anker_leeren
  kanal dev
  # Ein Benutzer hält die Sperren, die früher galten (auch die von install.sh, an der früher der Kanal 15 Minuten
  # wartete und dann «kaputt» endete). zenos-kanal direkt als root, ohne zen: Die Benutzerteile danach liefen als
  # tester und warteten zu Recht auf dessen eigene Sperre.
  # flock -o: Nur flock selbst hält die Sperre (nicht sleep), pkill gibt sie wieder frei
  runuser -u "$TESTER" -- flock -o /run/lock/zenos-install.lock sleep 600 &
  runuser -u "$TESTER" -- flock -o /run/lock/zenos-kanal.lock sleep 600 &
  runuser -u "$TESTER" -- flock -o /run/lock/zenos-kanal-bedienung.lock sleep 600 &
  sleep 1
  neu=$(neuer_commit "e2e: sperren" e2e/sperren "1")
  printf 'ja\n' | script -qefc "/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal update" /dev/null \
    > "$E2E/zen.out" 2>&1 || rc=$?
  tr -d '\r' < "$E2E/zen.out" > "$E2E/zen.txt"
  pkill -u "$TESTER" -f 'flock -o /run/lock/zenos' || true
  wait || true
  erwarte_rc "$rc" 0 "zen update, während ein Benutzer die alten Sperren hält"
  erwarte_kopf "$neu" "installiert"
  [[ "$(stat -c '%U %a' /run/zenos-sperre)" == "root 700" ]] ||
    fehler "/run/zenos-sperre: $(stat -c '%U %a' /run/zenos-sperre)"
  if runuser -u "$TESTER" -- flock -n /run/zenos-sperre/kanal.lock true 2>/dev/null; then
    fehler "ein Benutzer kommt an die Kanal-Sperre"
  fi
  ok "/run/zenos-sperre gehört root (0700), ein Benutzer kommt nicht an die Sperre"

  schritt "sperren: ein install.sh von Hand hält den Kanal an"
  if [[ ! -f "$ARBEIT/scripts/module/11-e2e-warten.sh" ]]; then
    neuer_commit "e2e: warten" scripts/module/11-e2e-warten.sh \
      $'#!/usr/bin/env bash\n# 11-e2e-warten: nur im Ende-zu-Ende-Test: wartet, solange /srv/kanal-e2e/warten da ist\n# shellcheck shell=bash\nmodul_system() {\n  local i=0\n  log_info "e2e: warte"\n  while [[ -e /srv/kanal-e2e/warten ]] && (( i < 600 )); do sleep 1; i=$((i + 1)); done\n}\n' > /dev/null
  fi
  runuser -u "$TESTER" -- git -C "$quelle" fetch -q origin dev
  runuser -u "$TESTER" -- git -C "$quelle" checkout -q --force -B werkbank FETCH_HEAD
  touch "$E2E/warten"
  runuser -u "$TESTER" -- env HOME=/home/$TESTER "$quelle/scripts/install.sh" > "$E2E/hand.txt" 2>&1 &
  hand=$!
  for i in $(seq 1 120); do
    [[ -f /run/zenos-sperre/hand ]] && grep -q "e2e: warte" /var/log/zenos/install.log 2>/dev/null &&
      [[ "$(tail -n 3 /var/log/zenos/install.log)" == *"e2e: warte"* ]] && break
    sleep 1
  done
  (( i < 120 )) || fehler "install.sh von Hand kam nicht bis zum Warten"
  ok "Vermerk /run/zenos-sperre/hand ($(cat /run/zenos-sperre/hand))"
  neu=$(neuer_commit "e2e: während der Hand" e2e/hand "1")
  rc=0
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 75 "zen update während eines Laufs von Hand"
  erwarte_text "install.sh von Hand läuft gerade" "Grund: Lauf von Hand"
  rm -f "$E2E/warten"
  wait "$hand" || { tail -n 30 "$E2E/hand.txt" >&2; fehler "install.sh von Hand"; }
  [[ ! -e /run/zenos-sperre/hand ]] || fehler "Vermerk bleibt nach dem Lauf von Hand"
  ok "Vermerk nach dem Lauf von Hand weg"
  rc=0
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update danach"
  erwarte_kopf "$neu" "installiert"
}

s_gitsperre() {
  schritt "gitsperre: zurückgebliebene index.lock in /opt/zenos"
  local neu rc=0
  anker_leeren
  kanal dev
  neu=$(neuer_commit "e2e: gitsperre" e2e/gitsperre "1")
  touch /opt/zenos/.git/index.lock /opt/zenos/.git/HEAD.lock
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update mit index.lock und HEAD.lock"
  erwarte_kopf "$neu" "installiert"
  [[ ! -e /opt/zenos/.git/index.lock && ! -e /opt/zenos/.git/HEAD.lock ]] || fehler "Sperren von git bleiben liegen"
  enthaelt "index.lock" json "$STAND/letzte.json" '.hinweise[]' || fehler "Hinweis auf die entfernte Sperre fehlt"
  ok "Sperren von git entfernt, mit Hinweis"
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
  install -d -m 0700 /run/zenos-sperre
  flock /run/zenos-sperre/kanal.lock sleep 8 &
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
  # Die Automatik ruht über einem Stand von Hand, auch auf vorschau zum Zeitpunkt «jederzeit» (Prüfung Teil B)
  if [[ -f /etc/systemd/system/zenos-kanal-gelegenheit.service ]]; then
    kanal vorschau
    /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal zeitpunkt jederzeit > /dev/null
    # Der Notschalter (für «automatik» gesetzt) hielte die Automatik vor dem Blick auf «angehalten» an
    if [[ -e "$AUS" ]]; then mv -f -- "$AUS" "$AUS.e2e"; fi
    rc=0
    /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal automatik gelegenheit > "$E2E/zen.txt" 2>&1 || rc=$?
    if [[ -e "$AUS.e2e" ]]; then mv -f -- "$AUS.e2e" "$AUS"; fi
    erwarte_rc "$rc" 0 "Automatik über einem Stand von Hand"
    erwarte_text "Von Hand angehalten" "die Automatik ruht"
    erwarte_kopf "$lokal" "der Arbeitsstand bleibt"
    /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal zeitpunkt sperre > /dev/null
    kanal dev
    rc=0
  fi
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

s_probelauf() {
  schritt "probelauf: ein geänderter zenos-kanal macht im Selbsttest einen Probelauf"
  local neu rc=0
  anker_leeren
  kanal dev
  printf '\n# e2e: geändert\n' >> "$ARBEIT/scripts/bin/zenos-kanal"
  neu=$(neuer_commit "e2e: zenos-kanal geändert")
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update mit geändertem zenos-kanal"
  erwarte_kopf "$neu" "installiert"
  enthaelt "Selbsttest mit Probelauf" json "$STAND/letzte.json" '.hinweise[]' || fehler "kein Probelauf"
  [[ ! -e "$STAND/selbsttest" ]] || fehler "Wegwerf-Zustand des Probelaufs bleibt liegen"
  ok "Probelauf lief, Wegwerf-Zustand weg"

  schritt "probelauf: Laufzeitfehler in update fällt auf, Rückweg ohne Probelauf"
  sed -i 's/^def cmd_update(argv):$/def cmd_update(argv):\n    raise RuntimeError("e2e: Laufzeitfehler")/' \
    "$ARBEIT/scripts/bin/zenos-kanal"
  grep -q 'e2e: Laufzeitfehler' "$ARBEIT/scripts/bin/zenos-kanal" || fehler "Laufzeitfehler nicht eingebaut"
  neuer_commit "e2e: zenos-kanal mit Laufzeitfehler" > /dev/null
  rc=0
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 4 "zen update mit kaputtem zenos-kanal"
  erwarte_text "Probelauf «update»: RuntimeError" "Grund: Probelauf"
  erwarte_kopf "$neu" "zurück auf dem Stand davor"
  if grep -q 'e2e: Laufzeitfehler' /usr/local/libexec/zenos/zenos-kanal; then fehler "kaputter zenos-kanal bleibt"; fi
  ok "der vorige zenos-kanal ist zurück"
  sed -i '/e2e: Laufzeitfehler/d' "$ARBEIT/scripts/bin/zenos-kanal"
  neu=$(neuer_commit "e2e: zenos-kanal repariert")
  rc=0
  zen_als_tester "ja" zen update || rc=$?
  erwarte_rc "$rc" 0 "zen update danach"
  erwarte_kopf "$neu" "installiert"
}

s_bedienung() {
  schritt "bedienung: polkit und Zeitpunkt"
  local helfer=/opt/zenos/scripts/bin/zenos-kanal-bedienen neu gut objekt rc aktion anderes
  [[ -x "$helfer" ]] || fehler "$helfer fehlt (install.sh mit diesem Stand)"
  for aktion in pruefen installieren zeitpunkt zustimmen; do
    pkaction --action-id "org.zenos.kanal.$aktion" --verbose > "$E2E/zen.txt" 2>&1 ||
      fehler "polkit kennt org.zenos.kanal.$aktion nicht"
  done
  erwarte_text "implicit active: *auth_admin$" "polkit: zustimmen nur mit Passwort"
  pkaction --action-id org.zenos.kanal.installieren --verbose > "$E2E/zen.txt" 2>&1
  erwarte_text "implicit active: *yes$" "polkit: installieren ohne Passwort"
  erwarte_text "implicit any: *no$" "polkit: nicht aus SSH"
  systemd-analyze verify /etc/systemd/system/zenos-kanal-jetzt@.service \
    "/etc/systemd/system/zenos-kanal-zustimmen@.service" > "$E2E/verify.txt" 2>&1 ||
    { cat "$E2E/verify.txt" >&2; fehler "systemd-analyze verify"; }
  ok "systemd-analyze verify ohne Befund"
  rm -f /etc/xdg/zenos/kanal-zeitpunkt
  rc=0
  "$helfer" zeitpunkt fenster 22:00 06:00 > "$E2E/zen.txt" 2>&1 || rc=$?
  erwarte_rc "$rc" 0 "zeitpunkt fenster 22:00 06:00"
  [[ "$(stat -c '%U %a' /etc/xdg/zenos/kanal-zeitpunkt)" == "root 644" ]] || fehler "kanal-zeitpunkt: Besitz, Rechte"
  runuser -u "$TESTER" -- env HOME=/home/$TESTER zen kanal zeitpunkt > "$E2E/zen.txt" 2>&1 || true
  erwarte_text "Zeitpunkt: fenster 22:00-06:00" "zen kanal zeitpunkt zeigt das Fenster"
  rc=0
  "$helfer" zeitpunkt fenster 03:00 03:30 > "$E2E/zen.txt" 2>&1 || rc=$?
  erwarte_rc "$rc" 2 "zu kurzes Fenster"
  erwarte_text "mindestens 60 Minuten" "Grund «zu kurz»"
  rc=0
  "$helfer" zeitpunkt sperre > "$E2E/zen.txt" 2>&1 || rc=$?
  erwarte_rc "$rc" 0 "zurück auf «sperre»"
  enthaelt "Zeitpunkt: nur gesperrt oder ohne Anmeldung, vorher zwischen 22:00 und 06:00" \
    journalctl -t zenos-kanal --no-pager -o cat -n 20 || fehler "Wechsel des Zeitpunkts nicht im Journal"
  ok "Wechsel im Journal"

  schritt "bedienung: jetzt prüfen, jetzt installieren (signiert, ohne Frage)"
  anker_schreiben
  kanal vorschau
  neu=$(neuer_commit "e2e: bedienung" e2e/bedienung "1")
  signieren v0.5.0-rc1
  rc=0
  "$helfer" pruefen > "$E2E/zen.txt" 2>&1 || rc=$?
  erwarte_rc "$rc" 0 "pruefen"
  [[ "$(json "$STAND/stand.json" .zustand)" == bereit ]] || fehler "stand.json: $(json "$STAND/stand.json" .zustand)"
  ok "stand.json: bereit $(json "$STAND/stand.json" .bereit.version)"
  objekt=$(json "$STAND/stand.json" .bereit.objekt)
  rc=0
  "$helfer" installieren "$(printf '%040d' 0)" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 10 "installieren für einen anderen Stand als den angezeigten"
  [[ "$(json "$STAND/stand.json" .wunsch.grund)" == "Angezeigt war "* ]] || fehler "Grund: $(json "$STAND/stand.json" .wunsch.grund)"
  ok "nichts installiert: angezeigt war ein anderer Stand"
  rc=0
  "$helfer" installieren "$objekt" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 0 "installieren"
  erwarte_kopf "$neu" "v0.5.0-rc1 installiert"
  [[ "$(json "$STAND/letzte.json" .ergebnis)" == installiert ]] || fehler "letzte.json"
  [[ "$(json "$STAND/stand.json" .zustand)" == aktuell ]] || fehler "danach nicht neu geprüft"
  ok "letzte.json installiert, danach neu geprüft: aktuell"
  enthaelt "Jetzt installieren" journalctl -t zenos-kanal-bedienen --no-pager -o cat -n 20 || fehler "Journal: Helfer"
  ok "Aufruf im Journal"

  schritt "bedienung: Netz betroffen → installieren wartet, zustimmen nur für das gezeigte Objekt"
  gut=$(kopf)
  printf '\n# e2e bedienung\n' >> "$ARBEIT/scripts/module/35-netzwerk.sh"
  neu=$(neuer_commit "e2e: bedienung netz")
  signieren v0.5.0-rc2
  "$helfer" pruefen > "$E2E/zen.txt" 2>&1 || true
  [[ "$(json "$STAND/stand.json" .zustand)" == zustimmung ]] || fehler "stand.json: $(json "$STAND/stand.json" .grund)"
  objekt=$(json "$STAND/stand.json" .bereit.objekt)
  ok "stand.json: zustimmung für ${objekt:0:12}"
  rc=0
  "$helfer" installieren "$objekt" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 10 "installieren wartet"
  erwarte_kopf "$gut" "nichts installiert"
  [[ "$(systemctl is-failed "zenos-kanal-jetzt@$objekt.service")" != failed ]] || fehler "jetzt «failed» bei Exit 10"
  ok "Unit nicht «failed»"
  anderes=$(printf '%040d' 0)
  rc=0
  "$helfer" zustimmen "$anderes" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 10 "zustimmen für ein anderes Objekt"
  erwarte_kopf "$gut" "nichts installiert"
  enthaelt "braucht eine neue Zustimmung" journalctl -u "zenos-kanal-zustimmen@$anderes.service" --no-pager -o cat ||
    fehler "Grund im Journal der Unit"
  rc=0
  "$helfer" zustimmen "$objekt" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 0 "zustimmen für das gezeigte Objekt"
  erwarte_kopf "$neu" "v0.5.0-rc2 installiert"
  [[ "$(json "$STAND/gut.json" .freigabe)" == ja ]] || fehler "gut.json: freigabe"
  ok "gut.json: mit Zustimmung"

  schritt "bedienung: dev unsigniert → zustimmen abgelehnt, installieren wartet"
  kanal dev
  gut=$(kopf)
  neu=$(neuer_commit "e2e: bedienung dev unsigniert" e2e/bedienung "2")
  "$helfer" pruefen > "$E2E/zen.txt" 2>&1 || true
  rc=0
  "$helfer" zustimmen "$neu" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 3 "zustimmen auf dev"
  rc=0
  "$helfer" installieren "$neu" > "$E2E/zen.txt" 2>&1 < /dev/null || rc=$?
  erwarte_rc "$rc" 10 "installieren auf dev (braucht «ja»)"
  erwarte_kopf "$gut" "nichts installiert"
  [[ "$(systemctl is-failed "zenos-kanal-zustimmen@$neu.service")" != failed ]] || fehler "Unit «failed» bei Exit 3"
  [[ "$(systemctl is-failed zenos-kanal-pruefen.service)" != failed ]] || fehler "Prüfen «failed» nach «wartet»"
  ok "Units nicht «failed», auch das Prüfen unterwegs nicht"
  kanal vorschau
}

# --- Automatik ---------------------------------------------------------------------------------------------------

AUS=/etc/xdg/zenos/kanal-automatik-aus
PROGRAMM=/usr/local/libexec/zenos/zenos-kanal
TESTER_UID=1000

zeitpunkt() { /usr/bin/python3 -I "$PROGRAMM" zeitpunkt "$@" > /dev/null; }

als_tester() { runuser -u "$TESTER" -- env HOME=/home/$TESTER XDG_RUNTIME_DIR=/run/user/$TESTER_UID "$@"; }

signierter_commit() { # NACHRICHT – Commit auf dev, mit dem Wegwerf-Release-Schlüssel signiert, gepusht; gibt die ID aus
  ga -c user.signingkey="$E2E/schluessel/rel" commit -q -S --allow-empty -m "$1"
  pushen dev
  ga rev-parse HEAD
}

# Startet eine Unit der Automatik und wartet auf ihr Ende; was das Programm sagte, steht danach in $E2E/zen.txt
# (Journal seit dem Start), was es tat in automatik.json
automatik() { # UNIT (Standard: zenos-kanal-automatik.service)
  local unit=${1:-zenos-kanal-automatik.service} seit
  seit=$(date +%s)
  sleep 1
  systemctl start "$unit" > "$E2E/start.txt" 2>&1 || true
  journalctl -u "$unit" --since "@$seit" --no-pager -o cat > "$E2E/zen.txt" 2>&1 || true
}

erwarte_lauf() { # ERGEBNIS MUSTER TEXT – automatik.json nach dem letzten Lauf
  local ergebnis grund
  ergebnis=$(json "$STAND/automatik.json" .ergebnis)
  grund=$(json "$STAND/automatik.json" .grund)
  if [[ "$ergebnis" != "$1" || "$grund" != *"$2"* ]]; then
    sed 's/^/      /' "$E2E/zen.txt" | tail -n 30 >&2
    fehler "$3: «$ergebnis» – $grund (erwartet «$1» mit «$2»)"
  fi
  ok "$3: $ergebnis – ${grund:0:110}"
}

# Die Timer der Automatik lösen im Test nie von selbst aus (Laufzeit-Drop-in, nach jedem Neustart neu): Ein Lauf hielte
# die Sperre der Bedienung mitten in einem Schritt. Der Test startet die Units von Hand.
automatik_timer_zahm() {
  local timer
  for timer in zenos-kanal.timer zenos-kanal-gelegenheit.timer; do
    install -d -m 0755 "/run/systemd/system/$timer.d"
    printf '# Nur im Ende-zu-Ende-Test: kein Lauf von selbst\n[Timer]\nOnBootSec=\nOnCalendar=\nOnCalendar=2099-01-01 00:00:00\n' \
      > "/run/systemd/system/$timer.d/e2e.conf"
  done
  systemctl daemon-reload
}

# Wartet, bis eine Unit (oneshot) fertig ist: «activating» zählt als laufend (is-active sagt dann nein)
warte_bis_fertig() { # UNIT [SEKUNDEN]
  local i zustand
  for i in $(seq 1 "${2:-300}"); do
    zustand=$(systemctl show -p ActiveState --value "$1")
    case "$zustand" in activating | active | deactivating | reloading) sleep 1 ;; *) return 0 ;; esac
  done
  fehler "$1 ist nach ${2:-300} s nicht fertig"
}

# Erste freie Version v0.N.0 (N ab 6) für die Automatik: So läuft der Schritt auch ein zweites Mal im selben Container
version_frei() {
  local n=6
  while g -C "$REMOTE" rev-parse -q --verify "refs/tags/v0.$n.0-rc1" > /dev/null; do n=$((n + 1)); done
  printf 'v0.%s.0' "$n"
}

minute_plus() { # MINUTEN – Uhrzeit (HH:MM, Ortszeit) in MINUTEN Minuten, auch negativ
  local jetzt
  jetzt=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
  jetzt=$(( ((jetzt + $1) % 1440 + 1440) % 1440 ))
  printf '%02d:%02d' $(( jetzt / 60 )) $(( jetzt % 60 ))
}

s_automatik() {
  schritt "automatik: Units, Timer, Notschalter"
  local neu gut vorher holen_vorher langsam i timer offset marker v
  v=$(version_frei)
  printf '%s\n' "$v" > "$E2E/automatik-version"
  [[ -f /etc/systemd/system/zenos-kanal.timer ]] || fehler "zenos-kanal.timer fehlt (install.sh mit diesem Stand)"
  systemd-analyze verify /etc/systemd/system/zenos-kanal{,-gelegenheit,-bestaetigen}.timer \
    /etc/systemd/system/zenos-kanal-{automatik,gelegenheit,bestaetigen}.service > "$E2E/verify.txt" 2>&1 ||
    { cat "$E2E/verify.txt" >&2; fehler "systemd-analyze verify"; }
  ok "systemd-analyze verify ohne Befund"
  [[ "$(systemctl show -p Triggers --value zenos-kanal.timer)" == zenos-kanal-automatik.service ]] ||
    fehler "zenos-kanal.timer löst nicht zenos-kanal-automatik.service aus"
  [[ "$(systemctl show -p Triggers --value zenos-kanal-gelegenheit.timer)" == zenos-kanal-gelegenheit.service ]] ||
    fehler "zenos-kanal-gelegenheit.timer löst nicht seine Unit aus"
  [[ "$(systemctl is-enabled zenos-kanal-bestaetigen.timer)" == enabled ]] || fehler "bestaetigen.timer nicht aktiviert"
  ok "Timer lösen die Units aus, die Bestätigung nach dem Start ist aktiviert"
  anker_schreiben
  /usr/bin/python3 -I "$PROGRAMM" automatik aus > /dev/null
  systemd-run --quiet --wait --collect --pipe -p Environment=HOME=/root -p Environment=ZENOS_KANAL_LAUF=1 \
    /opt/zenos/scripts/install.sh --ruhig < /dev/null > "$E2E/root-install.txt" 2>&1 ||
    { tail -n 30 "$E2E/root-install.txt" >&2; fehler "install.sh als root"; }
  for timer in zenos-kanal.timer zenos-kanal-gelegenheit.timer; do
    [[ "$(systemctl is-enabled "$timer")" == disabled ]] || fehler "$timer trotz Notschalter aktiviert"
    ! systemctl --quiet is-active "$timer" || fehler "$timer läuft trotz Notschalter"
  done
  ok "Notschalter: install.sh lässt die Timer aus"
  zen_als_tester "" zen kanal automatik || true
  erwarte_text "^Automatik   aus" "zen kanal automatik: aus"
  zen_als_tester "" zen kanal automatik an || fehler "zen kanal automatik an"
  for timer in zenos-kanal.timer zenos-kanal-gelegenheit.timer; do
    [[ "$(systemctl is-enabled "$timer")" == enabled ]] || fehler "$timer nach «an» nicht aktiviert"
    systemctl --quiet is-active "$timer" || fehler "$timer nach «an» nicht aktiv"
  done
  [[ ! -e "$AUS" ]] || fehler "Notschalter nach «an» noch da"
  enthaelt "zenos-kanal-automatik.service" systemctl list-timers --all --no-pager || fehler "list-timers"
  ok "an: Timer aktiviert und aktiv (systemctl list-timers)"
  zen_als_tester "" zen kanal automatik aus || fehler "zen kanal automatik aus"
  [[ -e "$AUS" && "$(systemctl is-enabled zenos-kanal.timer)" == disabled ]] || fehler "aus"
  enthaelt "Automatik aus (sudo, uid $TESTER_UID)" journalctl -t zenos-kanal --no-pager -o cat -n 20 ||
    fehler "Notschalter nicht im Journal"
  automatik
  [[ "$(systemctl show -p ConditionResult --value zenos-kanal-automatik.service)" == no ]] ||
    fehler "die Automatik startete trotz Notschalter"
  ok "aus: im Journal, die Unit startet nicht"
  /usr/bin/python3 -I "$PROGRAMM" automatik an > /dev/null
  automatik_timer_zahm

  schritt "automatik: dev nie, auch nicht signiert"
  kanal dev
  zeitpunkt jederzeit
  vorher=$(kopf)
  neu=$(signierter_commit "e2e: automatik dev signiert")
  automatik
  erwarte_kopf "$vorher" "dev: nichts installiert"
  erwarte_lauf nichts "Kanal dev" "Automatik auf dev"
  [[ "$(json "$STAND/stand.json" .zustand)" == dev && "$(json "$STAND/stand.json" .dev.commit)" == "$neu" ]] ||
    fehler "stand.json kennt den neuen dev-Stand nicht"
  ok "stand.json: dev, neuer Stand gesehen"

  schritt "automatik: vorschau, «von Hand» → nur bereit"
  kanal vorschau
  zeitpunkt hand
  neu=$(neuer_commit "e2e: automatik 1" e2e/automatik "1")
  signieren "$v-rc1"
  automatik
  erwarte_kopf "$vorher" "von Hand: nichts installiert"
  erwarte_lauf wartet "von Hand" "Automatik bei «von Hand»"
  [[ "$(json "$STAND/stand.json" .zustand)" == bereit && "$(json "$STAND/stand.json" .bereit.version)" == "$v-rc1" ]] ||
    fehler "stand.json: nicht bereit"
  [[ "$(json "$STAND/automatik-bereit" .version)" == "$v-rc1" ]] || fehler "automatik-bereit fehlt"
  ok "bereit $v-rc1, Marker für die Gelegenheit"
  [[ "$(json "$STAND/stand.json" .uhr_synchron)" == true ]] || fehler "Prüfen sieht die Uhr nicht (timedatectl)"
  [[ "$(json "$STAND/gesehen.json" ".tags[\"$v-rc1\"].erstmals_start.start")" == \
    "$(cat /proc/sys/kernel/random/boot_id)" ]] || fehler "erstmals ohne Start-ID"
  ok "das Prüfen liest die Uhr (synchron) und die Start-ID"

  schritt "automatik: Zeitfenster, Gelegenheit ohne Holen"
  gut=$(json "$STAND/gut.json" .commit)
  zeitpunkt fenster "$(minute_plus 120)" "$(minute_plus 180)"
  automatik zenos-kanal-gelegenheit.service
  erwarte_kopf "$vorher" "ausserhalb des Fensters nichts"
  erwarte_lauf wartet "ausserhalb des Zeitfensters" "Gelegenheit ausserhalb"
  zeitpunkt fenster "$(minute_plus -60)" "$(minute_plus 60)"
  holen_vorher=$(date +%s)
  automatik zenos-kanal-gelegenheit.service
  erwarte_kopf "$neu" "im Fenster installiert"
  erwarte_lauf installiert "automatisch" "Gelegenheit im Fenster"
  if journalctl -u zenos-kanal-holen.service --since "@$holen_vorher" --no-pager -o cat | grep -q .; then
    fehler "die Gelegenheit hat geholt"
  fi
  ok "die Gelegenheit holte nicht"
  [[ "$(json "$STAND/unbestaetigt.json" .commit)" == "$neu" && "$(json "$STAND/gut.json" .commit)" == "$gut" ]] ||
    fehler "unbestaetigt.json bzw. gut.json"
  ok "wartet auf die Bestätigung nach dem Neustart, gut.json bleibt"
  [[ ! -e "$STAND/automatik-bereit" ]] || fehler "automatik-bereit nach der Installation"
  zen_als_tester "" zen update || fehler "zen update danach"
  erwarte_text "Schon installiert" "zen update: schon installiert"
  zen_als_tester "" zen kanal status || true
  erwarte_text "gilt als gut nach einem Neustart mit Login" "zen kanal status: unbestätigt"

  schritt "automatik: Ausschalten wartet auf die Installation (zenos-energie als Benutzer)"
  zeitpunkt jederzeit
  langsam=$'#!/usr/bin/env bash\n# 99-e2e-langsam: nur im Ende-zu-Ende-Test: wartet, solange /srv/kanal-e2e/langsam da ist\n# shellcheck shell=bash\nmodul_system() {\n  local i=0\n  log_info "e2e: langsam"\n  while [[ -e /srv/kanal-e2e/langsam ]] && (( i < 300 )); do sleep 1; i=$((i + 1)); done\n}\n'
  neu=$(neuer_commit "e2e: automatik langsam" scripts/module/99-e2e-langsam.sh "$langsam")
  signieren "$v-rc2"
  touch "$E2E/langsam"
  offset=$(grep -c 'e2e: langsam' /var/log/zenos/install.log || true)
  systemctl start --no-block zenos-kanal-automatik.service
  for i in $(seq 1 240); do
    (( $(grep -c 'e2e: langsam' /var/log/zenos/install.log || true) > offset )) && break
    sleep 1
  done
  (( i < 240 )) || { rm -f "$E2E/langsam"; fehler "install.sh kam nicht bis zum langsamen Modul"; }
  als_tester systemctl list-units --type=service --state=activating,active,deactivating,reloading --no-legend \
    --plain --no-pager 'zenos-kanal-*.service' > "$E2E/zen.txt" 2>&1 || true
  erwarte_text "^zenos-kanal-installieren.service" "ein Benutzer sieht die laufende Installation (systemd)"
  if als_tester ls /run/zenos-sperre > /dev/null 2>&1; then fehler "ein Benutzer liest /run/zenos-sperre"; fi
  ok "die Sperren in /run/zenos-sperre sieht er nicht"
  install -d -o "$TESTER" -g "$TESTER" /home/$TESTER/.config/zenos
  printf '{"ausschalten": "immer"}\n' > /home/$TESTER/.config/zenos/einstellungen.json
  chown "$TESTER:$TESTER" /home/$TESTER/.config/zenos/einstellungen.json
  als_tester /opt/zenos/scripts/bin/zenos-energie status > "$E2E/zen.txt" 2>&1 || true
  erwarte_text "^nein: Update läuft (zenos-kanal-" "zenos-energie: nicht ausschalten"
  rm -f "$E2E/langsam"
  warte_bis_fertig zenos-kanal-automatik.service
  erwarte_kopf "$neu" "danach installiert"
  als_tester /opt/zenos/scripts/bin/zenos-energie status > "$E2E/zen.txt" 2>&1 || true
  if grep -q "Update läuft" "$E2E/zen.txt"; then fehler "zenos-energie: nach der Installation noch «Update läuft»"; fi
  ok "danach nicht mehr «Update läuft» ($(head -n 1 "$E2E/zen.txt"))"
  rm -f /home/$TESTER/.config/zenos/einstellungen.json

  schritt "automatik: «bei Sperre» mit Sitzung auf seat0 und der echten Sperre der Oberfläche"
  zeitpunkt sperre
  vorher=$(kopf)
  ga rm -q scripts/module/99-e2e-langsam.sh
  neu=$(neuer_commit "e2e: automatik sperre" e2e/automatik "3")
  signieren "$v-rc3"
  loginctl enable-linger "$TESTER"
  systemctl stop e2e-sitzung.service 2>/dev/null || true
  systemd-run --quiet --unit=e2e-sitzung -p PAMName=login -p User="$TESTER" -p Environment=XDG_SEAT=seat0 \
    -p Environment=XDG_VTNR=7 -p Environment=XDG_SESSION_CLASS=user -p Environment=XDG_SESSION_TYPE=wayland \
    /usr/bin/sleep infinity
  for i in $(seq 1 20); do
    loginctl list-sessions --json=short | jq -e '.[] | select(.seat == "seat0" and .class == "user")' > /dev/null && break
    sleep 1
  done
  (( i < 20 )) || fehler "keine Sitzung auf seat0"
  ok "Sitzung von $TESTER auf seat0 (gestellt über PAM)"
  automatik
  erwarte_kopf "$vorher" "angemeldet, nicht gesperrt: nichts"
  erwarte_lauf wartet "$TESTER ist angemeldet, nicht gesperrt" "Automatik mit offener Sitzung"
  als_tester bash /home/$TESTER/zenOS/test/container/oberflaeche.sh start --sitzung > "$E2E/oberflaeche.txt" 2>&1 ||
    { tail -n 20 "$E2E/oberflaeche.txt" >&2; fehler "Oberfläche startet nicht"; }
  als_tester /opt/zenos/scripts/zen lock > "$E2E/zen.txt" 2>&1 || true
  for i in $(seq 1 30); do
    [[ "$(als_tester /opt/zenos/scripts/bin/zenos-ipc sperre status 2>/dev/null | tail -n 1)" == gesperrt ]] && break
    sleep 1
  done
  (( i < 30 )) || fehler "die Oberfläche sperrt nicht"
  marker=/run/user/$TESTER_UID/zenos/gesperrt
  [[ -f "$marker" ]] || fehler "Marker $marker fehlt"
  ok "gesperrt (zenos-ipc sperre status), Marker da"
  automatik
  erwarte_kopf "$vorher" "eben gesperrt: noch nicht"
  erwarte_lauf wartet "erst seit Kurzem gesperrt" "Automatik direkt nach der Sperre"
  touch -d '-10 min' "$marker"
  automatik
  erwarte_kopf "$neu" "seit 10 Min. gesperrt: installiert"
  erwarte_lauf installiert "" "Automatik während der Sperre"
  enthaelt "(gesperrt)" cat "$E2E/zen.txt" || fehler "Grund «gesperrt» fehlt im Journal"
  ok "die Unit fragte die Oberfläche als $TESTER (setpriv, zenos-ipc) in ihrer Sandbox"
  als_tester bash /home/$TESTER/zenOS/test/container/oberflaeche.sh stopp > /dev/null 2>&1 || true
  rm -f "$marker"
  systemctl stop e2e-sitzung.service

  schritt "automatik: zen rollback stellt die verlassene Version zurück"
  gut=$(g -C "$REMOTE" rev-parse "$v-rc2^{commit}")
  zen_als_tester "" zen rollback "$v-rc2" || fehler "zen rollback $v-rc2"
  erwarte_kopf "$gut" "auf $v-rc2"
  [[ "$(json "$STAND/zurueckgestellt.json" .zurueckgestellt)" == "$v-rc3" ]] || fehler "zurueckgestellt.json"
  ok "$v-rc3 zurückgestellt"
  zeitpunkt jederzeit
  automatik
  erwarte_kopf "$gut" "die Automatik bringt $v-rc3 nicht wieder"
  [[ "$(json "$STAND/stand.json" .grund)" == *"zurückgestellt"* ]] || fehler "stand.json nennt die Rückstellung nicht"
  ok "stand.json: zurückgestellt"
  zen_als_tester "" zen update || fehler "zen update von Hand"
  erwarte_kopf "$neu" "zen update von Hand: wieder $v-rc3"
  [[ ! -e "$STAND/zurueckgestellt.json" ]] || fehler "Rückstellung bleibt nach zen update"
  ok "zen update hebt die Rückstellung auf"

  schritt "automatik: Bestätigung nach dem Neustart vorbereiten"
  gut=$neu
  neu=$(neuer_commit "e2e: automatik bestaetigen" e2e/automatik "4")
  signieren "$v-rc4"
  automatik
  erwarte_kopf "$neu" "automatisch installiert"
  [[ "$(json "$STAND/unbestaetigt.json" .commit)" == "$neu" && "$(json "$STAND/gut.json" .commit)" == "$gut" ]] ||
    fehler "unbestaetigt.json bzw. gut.json"
  # greetd zum Schein (im Container gibt es kein VT) und ein Login-Bildschirm: ein Prozess «quickshell» als _greetd
  install -d /etc/systemd/system/greetd.service.d "$E2E/greeter"
  printf '# Nur im Ende-zu-Ende-Test\n[Service]\nExecStart=\nExecStart=/usr/bin/sleep infinity\n' \
    > /etc/systemd/system/greetd.service.d/e2e.conf
  # Ein Skript namens quickshell: Der Kern nennt den Prozess danach (comm); sleep selbst ist ein Multicall-Programm
  printf '#!/bin/sh\n# e2e: Login-Bildschirm zum Schein (comm «quickshell»)\nwhile :; do sleep 3600; done\n' \
    > "$E2E/greeter/quickshell"
  chmod 0755 "$E2E/greeter/quickshell"
  printf '[Unit]\nDescription=e2e: Login-Bildschirm zum Schein\nWants=greetd.service\nAfter=greetd.service\n[Service]\nUser=_greetd\nExecStart=%s infinity\n[Install]\nWantedBy=multi-user.target\n' \
    "$E2E/greeter/quickshell" > /etc/systemd/system/e2e-greeter.service
  systemctl daemon-reload
  systemctl enable --quiet e2e-greeter.service
  automatik zenos-kanal-bestaetigen.service
  erwarte_text "kein Neustart" "im selben Start keine Bestätigung"
  [[ -f "$STAND/unbestaetigt.json" ]] || fehler "unbestaetigt.json"
  printf '%s %s\n' "$gut" "$neu" > "$E2E/automatik-bestaetigen"
  ok "jetzt den Container neu starten (docker restart), dann: einrichten, nach-automatik"
}

s_nach_automatik() {
  schritt "nach-automatik: Login kommt → bestätigt"
  local gut neu alt pid i v
  v=$(cat "$E2E/automatik-version")
  read -r gut neu < "$E2E/automatik-bestaetigen"
  systemctl --quiet is-active greetd.service || fehler "greetd (zum Schein) läuft nicht"
  for i in $(seq 1 60); do
    pid=$(systemctl show -p MainPID --value e2e-greeter.service)
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] && (( $(ps -o etimes= -p "$pid") >= 25 )) && break
    sleep 1
  done
  (( i < 60 )) || fehler "Login-Bildschirm zum Schein läuft nicht"
  automatik zenos-kanal-bestaetigen.service
  journalctl -b -u zenos-kanal-bestaetigen.service --no-pager -o cat > "$E2E/zen.txt"
  erwarte_text "Bestätigt: $v-rc4" "bestätigt (der Login-Bildschirm läuft)"
  [[ "$(json "$STAND/gut.json" .commit)" == "$neu" && "$(json "$STAND/gut.json" .bestaetigt)" != null ]] ||
    fehler "gut.json nach der Bestätigung"
  [[ ! -e "$STAND/unbestaetigt.json" ]] || fehler "unbestaetigt.json bleibt"
  ok "gut.json: $v-rc4, bestätigt"

  schritt "nach-automatik: ohne Login vorbereiten"
  alt=$neu
  neu=$(neuer_commit "e2e: automatik ohne Login" e2e/automatik "5")
  signieren "$v-rc5"
  automatik
  erwarte_kopf "$neu" "automatisch installiert"
  systemctl disable --now --quiet e2e-greeter.service
  systemctl stop greetd.service
  printf '%s %s\n' "$alt" "$neu" > "$E2E/automatik-zurueck"
  ok "kein Login mehr; jetzt den Container neu starten, dann: einrichten, nach-automatik-2"
}

s_nach_automatik_2() {
  schritt "nach-automatik-2: erster Start ohne Login (wartet bis zu 3 Min.)"
  local alt neu v
  v=$(cat "$E2E/automatik-version")
  read -r alt neu < "$E2E/automatik-zurueck"
  automatik zenos-kanal-bestaetigen.service
  journalctl -b -u zenos-kanal-bestaetigen.service --no-pager -o cat > "$E2E/zen.txt"
  erwarte_text "Nach dem Neustart kein Login (greetd läuft nicht" "erster Start ohne Login gezählt"
  [[ "$(json "$STAND/unbestaetigt.json" '.fehlstarts | length')" == 1 ]] || fehler "fehlstarts"
  [[ "$(systemctl is-failed zenos-kanal-bestaetigen.service)" != failed ]] || fehler "Unit «failed» bei Exit 10"
  erwarte_kopf "$neu" "noch auf $v-rc5"
  ok "jetzt den Container neu starten, dann: einrichten, nach-automatik-3"
}

s_nach_automatik_3() {
  schritt "nach-automatik-3: zweiter Start ohne Login → zurück auf den guten Stand"
  local alt neu v
  v=$(cat "$E2E/automatik-version")
  read -r alt neu < "$E2E/automatik-zurueck"
  automatik zenos-kanal-bestaetigen.service
  journalctl -b -u zenos-kanal-bestaetigen.service --no-pager -o cat > "$E2E/zen.txt"
  erwarte_text "kam bei 2 Starts kein Login" "zweiter Start ohne Login"
  erwarte_kopf "$alt" "zurück auf $v-rc4"
  [[ "$(json "$STAND/letzte.json" .ergebnis)" == zurueck ]] || fehler "letzte.json"
  [[ "$(json "$STAND/gesperrt/$v-rc5" .grund)" == *"kein Login"* ]] || fehler "$v-rc5 nicht gesperrt"
  [[ ! -e "$STAND/unbestaetigt.json" && "$(json "$STAND/gut.json" .commit)" == "$alt" ]] || fehler "gut.json"
  ok "$v-rc5 gesperrt, letzte.json «zurueck», gut.json $v-rc4"
  systemctl --quiet is-active greetd.service || fehler "greetd wurde nicht neu gestartet"
  ok "greetd neu gestartet (niemand angemeldet)"
  automatik
  erwarte_kopf "$alt" "die gesperrte Version kommt nicht wieder"
  # Aufräumen: greetd wieder echt, kein Login zum Schein, Zeitpunkt Standard, Notschalter wie nach einrichten
  rm -f /etc/systemd/system/greetd.service.d/e2e.conf /etc/systemd/system/e2e-greeter.service
  systemctl daemon-reload
  systemctl stop greetd.service 2>/dev/null || true
  rm -f /etc/xdg/zenos/kanal-zeitpunkt
  /usr/bin/python3 -I "$PROGRAMM" automatik aus > /dev/null
  ok "aufgeräumt"
}

s_automatik_uhr() {
  schritt "automatik-uhr: stabil wartet 24 h, ein Sprung der Uhr verkürzt nichts"
  local v vorher neu jetzt seit
  v=$(cat "$E2E/automatik-version")
  /usr/bin/python3 -I "$PROGRAMM" automatik an > /dev/null
  automatik_timer_zahm
  kanal stabil
  zeitpunkt jederzeit
  vorher=$(kopf)
  neu=$(neuer_commit "e2e: automatik stabil" e2e/automatik "6")
  signieren "$v"
  automatik
  erwarte_kopf "$vorher" "eben gesehen: nichts"
  erwarte_lauf wartet "24 h" "Automatik auf stabil"
  [[ "$(json "$STAND/gesehen.json" ".tags[\"$v\"].erstmals")" != null ]] || fehler "erstmals fehlt (Uhr synchron)"
  ok "erstmals gesehen: $(json "$STAND/gesehen.json" ".tags[\"$v\"].erstmals")"
  # Die Uhr springt 25 h vor (NTP): «erstmals» liegt 25 h zurück, seit dem Start verging aber kaum etwas
  jetzt=$(date -u -d '-25 hours' +%Y-%m-%dT%H:%M:%SZ)
  jq --arg v "$v" --arg t "$jetzt" '.tags[$v].erstmals = $t' "$STAND/gesehen.json" > "$STAND/.gesehen.e2e"
  mv "$STAND/.gesehen.e2e" "$STAND/gesehen.json"
  automatik
  erwarte_kopf "$vorher" "Uhr gesprungen: nichts"
  erwarte_lauf wartet "24 h" "Automatik nach dem Sprung der Uhr"
  # Jetzt vergehen die 25 h auch seit dem Start
  seit=$(awk '{ printf "%d", $1 - 25 * 3600 }' /proc/uptime)
  jq --argjson s "$seit" --arg v "$v" '.tags[$v].erstmals_start.seit_start = $s' "$STAND/gesehen.json" \
    > "$STAND/.gesehen.e2e"
  mv "$STAND/.gesehen.e2e" "$STAND/gesehen.json"
  automatik
  erwarte_kopf "$neu" "25 h vergangen: installiert"
  erwarte_lauf installiert "" "Automatik nach 24 h"
  kanal vorschau
  rm -f /etc/xdg/zenos/kanal-zeitpunkt
  /usr/bin/python3 -I "$PROGRAMM" automatik aus > /dev/null
  ok "aufgeräumt"
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
  basis) s_basis ;;
  notweg) s_notweg ;;
  stopp) s_stopp ;;
  werkbank) s_werkbank ;;
  sperren) s_sperren ;;
  gitsperre) s_gitsperre ;;
  probelauf) s_probelauf ;;
  bedienung) s_bedienung ;;
  automatik) s_automatik ;;
  nach-automatik) s_nach_automatik ;;
  nach-automatik-2) s_nach_automatik_2 ;;
  nach-automatik-3) s_nach_automatik_3 ;;
  automatik-uhr) s_automatik_uhr ;;
  *) sed -n '2,64p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
