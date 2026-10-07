#!/usr/bin/env bash
# basis-e2e.sh <schritt>… – Ende-zu-Ende-Test der Basis-Updates (zenos-basis) im Testcontainer (als root im Container).
#
# Baut eine eigene Paketquelle im Container: file:/srv/basis-e2e/repo mit den Taschen «e2e» und «e2e-security»
# (Release-Dateien wie bei Ubuntu, Origin zenos-e2e, ohne Signatur: «Trusted: yes» gilt nur hier, im Wegwerf-Container)
# und Attrappen-Pakete, die in dieser Quelle neue Versionen bekommen. Die Quellen von Ubuntu liegen während des Tests
# beiseite (zurück mit «aufraeumen»): So sieht apt nur die Attrappen, und jeder Lauf ist ohne Netz gleich. Getestet wird
# mit dem echten zen, zenos-basis, zenos-kanal, install.sh, apt, dpkg, systemd und den Units.
#
# Vorbereitung auf dem Mac (Container aus dem installierten Image, Arbeitsstand nach /opt/zenos):
#   ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-basis-e2e
#   docker exec -u tester -w /home/tester/zenOS zenos-basis-e2e ./scripts/install.sh
# Dann: docker exec zenos-basis-e2e bash /repo/test/container/basis-e2e.sh alle   (oder einzelne Schritte)
#
# Schritte (nach «einrichten» in beliebiger Reihenfolge und wiederholbar: Jeder Schritt bietet neue Versionen an):
#   einrichten   Paketquelle, Quellen von Ubuntu beiseite, Attrappen in Version 1.0 installiert, Timer lösen nicht von
#                selbst aus (Basis, Kanal, apt-daily), Zeitpunkt «jederzeit», kein Notschalter (idempotent)
#   automatik    Update ohne heikles Paket, mit neuer greetd-Version und einem Dienst: Zeitpunkt «von Hand» wartet
#                (bereit, Marker automatik-bereit), «jederzeit» installiert über die Gelegenheit. greetd startet nicht
#                neu (die policy-rc.d der Basis lehnt ab), der Dienst der Attrappe schon; Neustart nötig wegen greetd
#   zen-update   Update ohne heikles Paket über «zen update --nur-basis --ja» (ohne Frage, Sicherheit gezählt), danach
#                install.sh zweimal von Hand (root) mit 0 Änderungen
#   kernel       Attrappe linux-image-e2e-raspi: die Automatik installiert nicht («warten auf dich»), «Jetzt
#                installieren» ohne Passwort Exit 10, zen update fragt: «nein» ändert nichts, «ja» installiert; danach
#                «Neustart nötig» (zenos-basis status, zen version)
#   schutz       full-upgrade würde ein geschütztes Paket entfernen (Attrappe lxd-installer, automatisch installiert):
#                gesperrt, zen update --ja Exit 3, auch mit Zustimmung und über die Automatik nichts. Danach eine
#                Entfernung eines ungeschützten Pakets: nie automatisch, ohne Passwort Exit 10, nur nach «ja»
#   abbruch      kill der Unit mitten in dpkg (postinst der Attrappe wartet): Marker, Inhibitor und policy-rc.d während
#                des Laufs; danach dpkg unterbrochen, die policy-rc.d der Basis bleibt liegen, die Sperre ist frei. Das
#                nächste zen update holt in der Prüfung «dpkg --configure -a» nach (apt-get -s allein sagte «aktuell»)
#   sperre       nie zwei Paketvorgänge zugleich: Während eine Basis-Installation läuft, enden zenos-kanal pruefen,
#                zen update --nur-zenos und ein zweites zenos-basis installieren mit Exit 75, ein install.sh von Hand
#                (als tester) wartet und läuft erst danach. Hält der Kanal die Sperre (flock auf dieselbe Datei), enden
#                zen update --nur-basis und zenos-basis installieren mit 75; ebenso, solange der Vermerk eines
#                install.sh von Hand gilt
#   aufraeumen   Quellen von Ubuntu zurück, Attrappen weg (greetd bleibt in der Version aus dem Test, gleicher Inhalt),
#                Timer und Zeitpunkt wie vorher
#   alle         einrichten automatik zen-update kernel schutz abbruch sperre aufraeumen
#
# Danach braucht apt für die Pakete von Ubuntu wieder ein «apt-get update» (mit Netz). Container danach entfernen.

set -euo pipefail

E2E=/srv/basis-e2e
REPO=$E2E/repo
POOL=$E2E/pool
BAU=$E2E/bau
BEISEITE=$E2E/beiseite
QUELLE=/etc/apt/sources.list.d/zenos-e2e.sources
PROGRAMM=/usr/local/libexec/zenos/zenos-basis
KANAL=/usr/local/libexec/zenos/zenos-kanal
STAND=/var/lib/zenos/basis
POLICY=/usr/sbin/policy-rc.d
TESTER=tester
INSTALLIEREN=zenos-basis-installieren.service
TIMER=(zenos-basis-automatik.timer zenos-basis-gelegenheit.timer zenos-kanal.timer zenos-kanal-gelegenheit.timer
  apt-daily.timer apt-daily-upgrade.timer)
# Attrappen, die «einrichten» in Version 1.0 installiert (mit «auto»: als automatisch installiert markiert)
GRUNDSTOCK=(zenos-e2e-auto zenos-e2e-dienst zenos-e2e-werkzeug zenos-e2e-sicher linux-image-e2e-raspi
  zenos-e2e-konflikt zenos-e2e-frei:auto lxd-installer:auto zenos-e2e-halten)

ok() { printf '  ok  %s\n' "$*"; }
fehler() { printf '  FEHLER  %s\n' "$*" >&2; exit 1; }
schritt() { printf '\n== %s\n' "$*"; }

# enthaelt MUSTER BEFEHL… – kommt MUSTER in der Ausgabe von BEFEHL vor? (ohne Pipe, siehe kanal-e2e.sh)
enthaelt() {
  local muster=$1 text
  shift
  text=$("$@" 2>/dev/null) || true
  grep -q -- "$muster" <<< "$text"
}

json() { # DATEI AUSDRUCK – Wert aus einer JSON-Datei (jq)
  jq -r "$2" "$1" 2>/dev/null || printf '?'
}

basis() { /usr/bin/python3 -I "$PROGRAMM" "$@"; }

# zen als tester in einem Pseudo-Terminal; ANTWORT geht als Eingabe hinein. Ausgabe in DATEI.txt, Rückgabe der Exit
zen_lauf() { # DATEI ANTWORT BEFEHL…
  local datei=$1 antwort=$2 rc=0
  shift 2
  printf '%s\n' "$antwort" | runuser -u "$TESTER" -- env HOME=/home/$TESTER script -qefc "$*" /dev/null \
    > "$datei.out" 2>&1 || rc=$?
  tr -d '\r' < "$datei.out" > "$datei.txt"
  return "$rc"
}

zen_als_tester() { zen_lauf "$E2E/zen" "$@"; }

erwarte_rc() { # IST SOLL TEXT [DATEI]
  [[ "$1" == "$2" ]] || { sed 's/^/      /' "${4:-$E2E/zen.txt}" | tail -n 40 >&2; fehler "$3: Exit $1, erwartet $2"; }
  ok "$3: Exit $1"
}

erwarte_text() { # MUSTER TEXT [DATEI]
  grep -q -- "$1" "${3:-$E2E/zen.txt}" ||
    { sed 's/^/      /' "${3:-$E2E/zen.txt}" | tail -n 40 >&2; fehler "$2: «$1» fehlt"; }
  ok "$2"
}

ohne_text() { # MUSTER TEXT [DATEI]
  if grep -q -- "$1" "${3:-$E2E/zen.txt}"; then
    sed 's/^/      /' "${3:-$E2E/zen.txt}" | tail -n 40 >&2
    fehler "$2: «$1» kommt vor"
  fi
  ok "$2"
}

# Ausgabe eines Befehls als root in DATEI, Rückgabe der Exit
root_lauf() { # DATEI BEFEHL…
  local datei=$1 rc=0
  shift
  "$@" < /dev/null > "$datei" 2>&1 || rc=$?
  return "$rc"
}

version() { # NAME – installierte Version oder leer
  local status
  status=$(dpkg-query -W -f='${db:Status-Status} ${Version}' "$1" 2>/dev/null) || return 0
  [[ "$status" == "installed "* ]] && printf '%s' "${status#installed }"
  return 0
}

erwarte_version() { # NAME VERSION TEXT
  [[ "$(version "$1")" == "$2" ]] || fehler "$3: $1 ist «$(version "$1")», erwartet «$2»"
  ok "$3: $1 $2"
}

# Nächste Version einer Attrappe: 1.0, wenn sie fehlt, sonst die nächste ganze Zahl (1.0 → 2.0)
naechste() { # NAME
  local v
  v=$(version "$1")
  if [[ -z "$v" ]]; then printf '1.0'; else printf '%s.0' "$(( ${v%%.*} + 1 ))"; fi
}

# Nächste Version von greetd: die echte mit «+e2eN» (gleicher Inhalt wie das Paket aus dem Cache)
naechste_greetd() {
  local v n
  v=$(version greetd)
  [[ -n "$v" ]] || fehler "greetd ist nicht installiert"
  n=0
  if [[ "$v" == *+e2e* ]]; then n=${v##*+e2e}; fi
  printf '%s+e2e%s' "${v%%+e2e*}" "$(( n + 1 ))"
}

# --- Attrappen und Paketquelle -------------------------------------------------------------------------------------

# Maintainer-Skripte der Attrappen (nur im Test)
postinst_text() { # NAME
  case "$1" in
    zenos-e2e-dienst)
      # wie dh_installsystemd: beim Upgrade neu starten (deb-systemd-invoke fragt die policy-rc.d)
      cat <<'SH'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
  deb-systemd-helper enable zenos-e2e-dienst.service >/dev/null || true
  if [ -d /run/systemd/system ]; then
    systemctl --system daemon-reload >/dev/null || true
    deb-systemd-invoke restart zenos-e2e-dienst.service >/dev/null || true
  fi
fi
SH
      ;;
    linux-image-e2e-raspi)
      # wie notify-reboot-required (update-notifier-common fehlt im Testbild)
      cat <<'SH'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
  echo '*** System restart required ***' > /run/reboot-required
  grep -qx linux-image-e2e-raspi /run/reboot-required.pkgs 2>/dev/null || echo linux-image-e2e-raspi >> /run/reboot-required.pkgs
fi
SH
      ;;
    zenos-e2e-halten)
      # hält dpkg an, solange /srv/basis-e2e/halten da ist (höchstens 10 Minuten)
      cat <<'SH'
#!/bin/sh
set -e
if [ "$1" = configure ] && [ -e /srv/basis-e2e/halten ]; then
  : > /srv/basis-e2e/halten.laeuft
  i=0
  while [ -e /srv/basis-e2e/halten ] && [ "$i" -lt 600 ]; do sleep 1; i=$((i + 1)); done
fi
rm -f /srv/basis-e2e/halten.laeuft
SH
      ;;
  esac
}

# prerm und postrm der Attrappe eines Dienstes (wie dh_installsystemd)
dienst_skript() { # prerm|postrm
  case "$1" in
    prerm)
      cat <<'SH'
#!/bin/sh
set -e
if [ "$1" = remove ] && [ -d /run/systemd/system ]; then
  deb-systemd-invoke stop zenos-e2e-dienst.service >/dev/null || true
fi
SH
      ;;
    postrm)
      cat <<'SH'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
  deb-systemd-helper purge zenos-e2e-dienst.service >/dev/null || true
fi
SH
      ;;
  esac
}

bauen() { # NAME VERSION [ZUSATZ] – baut $POOL/NAME_VERSION_all.deb (Attrappe), wenn es fehlt
  local name=$1 version=$2 zusatz=${3:-} ziel ordner text
  ziel=$POOL/${name}_${version}_all.deb
  [[ -f "$ziel" ]] && return 0
  ordner=$BAU/$name-$version
  rm -rf "$ordner"
  install -d "$ordner/DEBIAN" "$ordner/usr/share/doc/$name"
  {
    printf 'Package: %s\nVersion: %s\nArchitecture: all\n' "$name" "$version"
    printf 'Maintainer: zenOS e2e <e2e@example.invalid>\nPriority: optional\nSection: misc\n'
    [[ -z "$zusatz" ]] || printf '%s\n' "$zusatz"
    printf 'Description: Attrappe im Ende-zu-Ende-Test von zenos-basis\n'
  } > "$ordner/DEBIAN/control"
  printf 'Attrappe %s %s (test/container/basis-e2e.sh)\n' "$name" "$version" > "$ordner/usr/share/doc/$name/e2e"
  text=$(postinst_text "$name")
  if [[ -n "$text" ]]; then
    printf '%s\n' "$text" > "$ordner/DEBIAN/postinst"
    chmod 0755 "$ordner/DEBIAN/postinst"
  fi
  if [[ "$name" == zenos-e2e-dienst ]]; then
    install -d "$ordner/usr/lib/systemd/system"
    printf '[Unit]\nDescription=zenOS e2e: Attrappe eines Dienstes\n\n[Service]\nExecStart=/usr/bin/sleep infinity\n\n[Install]\nWantedBy=multi-user.target\n' \
      > "$ordner/usr/lib/systemd/system/zenos-e2e-dienst.service"
    dienst_skript prerm > "$ordner/DEBIAN/prerm"
    dienst_skript postrm > "$ordner/DEBIAN/postrm"
    chmod 0755 "$ordner/DEBIAN/prerm" "$ordner/DEBIAN/postrm"
  fi
  dpkg-deb --root-owner-group -Zxz --build "$ordner" "$ziel" > /dev/null
}

greetd_bauen() { # VERSION – greetd aus dem Paket im Cache, nur mit anderer Version (Inhalt und Skripte wie echt)
  local version=$1 ziel arch
  arch=$(dpkg --print-architecture)
  ziel=$POOL/greetd_${version}_$arch.deb
  [[ -f "$ziel" ]] && return 0
  rm -rf "$BAU/greetd"
  dpkg-deb -R "$E2E/greetd-original.deb" "$BAU/greetd"
  sed -i "s/^Version: .*/Version: $version/" "$BAU/greetd/DEBIAN/control"
  dpkg-deb --root-owner-group -Zxz --build "$BAU/greetd" "$ziel" > /dev/null
}

# quelle [TASCHE:NAME=VERSION]… – die Paketquelle bietet genau diese Pakete an (sonst nichts), dann apt-get update
quelle() {
  local eintrag tasche name version arch datei paketliste
  arch=$(dpkg --print-architecture)
  rm -rf "$REPO"
  for tasche in e2e e2e-security; do
    install -d "$REPO/dists/$tasche/main/binary-$arch" "$REPO/pool/$tasche"
  done
  for eintrag in "$@"; do
    tasche=${eintrag%%:*}
    name=${eintrag#*:}
    version=${name#*=}
    name=${name%%=*}
    datei=""
    for datei in "$POOL/${name}_${version}_"*.deb; do break; done
    [[ -f "$datei" ]] || fehler "quelle: $name $version ist nicht gebaut"
    cp "$datei" "$REPO/pool/$tasche/"
  done
  for tasche in e2e e2e-security; do
    paketliste=dists/$tasche/main/binary-$arch/Packages
    (cd "$REPO" && dpkg-scanpackages --multiversion "pool/$tasche" /dev/null > "$paketliste" 2>/dev/null)
    {
      printf 'Origin: zenos-e2e\nLabel: zenos-e2e\nSuite: %s\nCodename: %s\nVersion: 26.04\n' "$tasche" "$tasche"
      printf 'Architectures: %s\nComponents: main\nDate: %s\nSHA256:\n' "$arch" "$(LC_ALL=C date -Ru)"
      printf ' %s %s main/binary-%s/Packages\n' "$(sha256sum < "$REPO/$paketliste" | cut -d' ' -f1)" \
        "$(stat -c %s "$REPO/$paketliste")" "$arch"
    } > "$REPO/dists/$tasche/Release"
  done
  apt-get -qq update > "$E2E/apt-update.txt" 2>&1 || { cat "$E2E/apt-update.txt" >&2; fehler "apt-get update"; }
}

# Simulation wie zenos-basis (ohne autoremove)
simulation() { LC_ALL=C apt-get -s -o APT::Get::AutomaticRemove=false full-upgrade 2>/dev/null; }

# Eine Attrappe in Version 1.0 installieren, falls sie fehlt (danach bietet die Quelle nichts mehr an)
grundstock() { # NAME[:auto]…
  local eintrag name fehlend=() auto=() beschreibung
  for eintrag in "$@"; do
    name=${eintrag%%:*}
    if [[ "$name" == lxd-installer && -n "$(version lxd-installer)" ]]; then
      beschreibung=$(dpkg-query -W -f='${Description}' lxd-installer)
      [[ "$beschreibung" == Attrappe* ]] || fehler "lxd-installer ist echt installiert: dieser Test braucht ein Gerät ohne"
    fi
    [[ -z "$(version "$name")" ]] || continue
    bauen "$name" 1.0
    fehlend+=("$name")
    [[ "$eintrag" != *:auto ]] || auto+=("$name")
  done
  (( ${#fehlend[@]} )) || return 0
  local liste=()
  for name in "${fehlend[@]}"; do liste+=("e2e:$name=1.0"); done
  quelle "${liste[@]}"
  DEBIAN_FRONTEND=noninteractive apt-get -qq -y --no-remove install "${fehlend[@]}" > "$E2E/apt-install.txt" 2>&1 ||
    { cat "$E2E/apt-install.txt" >&2; fehler "Attrappen installieren"; }
  (( ${#auto[@]} == 0 )) || apt-mark auto "${auto[@]}" > /dev/null
  quelle
}

# --- Zustand ---------------------------------------------------------------------------------------------------------

zeitpunkt() { /usr/bin/python3 -I "$KANAL" zeitpunkt "$1" > /dev/null; }

liste() { json "$STAND/stand.json" .liste; }

invocation() { systemctl show -p InvocationID --value "$1"; }

# Startet eine oneshot-Unit und wartet; Exit des Programms (ExecMainStatus), auch bei SuccessExitStatus
unit_lauf() { # UNIT
  systemctl start "$1" || true
  systemctl show -p ExecMainStatus --value "$1"
}

neustart_vergessen() { rm -f /run/reboot-required /run/reboot-required.pkgs; }

nicht_ausgefallen() { # UNIT…
  local unit
  for unit in "$@"; do
    if systemctl --quiet is-failed "$unit"; then fehler "$unit ist «failed»"; fi
  done
}

danach_sauber() { # TEXT – nach einem Lauf: keine policy-rc.d, kein Marker, Sperre frei
  [[ ! -e "$POLICY" ]] || fehler "$1: $POLICY bleibt liegen"
  [[ ! -e /run/zenos-basis ]] || fehler "$1: /run/zenos-basis bleibt"
  flock -n /run/zenos-sperre/kanal.lock true || fehler "$1: kanal.lock bleibt belegt"
  ok "$1: keine policy-rc.d, kein Marker, Sperre frei"
}

dpkg_unterbrochen() {
  local datei
  for datei in /var/lib/dpkg/updates/*; do
    [[ "${datei##*/}" =~ ^[0-9]+$ ]] && return 0
  done
  return 1
}

# --- Schritte --------------------------------------------------------------------------------------------------------

s_einrichten() {
  schritt "einrichten: Paketquelle, Attrappen 1.0, Timer, Zeitpunkt"
  local datei timer arch greetd_v
  (( EUID == 0 )) || fehler "nur als root im Testcontainer"
  [[ -f "$PROGRAMM" && -f "$KANAL" && -x /opt/zenos/scripts/install.sh ]] ||
    fehler "zenos-basis, zenos-kanal oder /opt/zenos fehlen (zuerst install.sh aus ~/zenOS)"
  grep -q 'def cmd_update' "$PROGRAMM" || fehler "$PROGRAMM ist zu alt (zuerst install.sh aus ~/zenOS)"
  install -d -m 0755 "$E2E" "$POOL" "$BAU" "$BEISEITE"

  # Quellen von Ubuntu (und alle anderen) beiseite, nur die Testquelle bleibt
  for datei in /etc/apt/sources.list.d/*; do
    [[ -e "$datei" && "$datei" != "$QUELLE" ]] || continue
    mv -- "$datei" "$BEISEITE/"
  done
  if [[ -s /etc/apt/sources.list ]] && grep -qE '^[[:space:]]*deb' /etc/apt/sources.list; then
    mv /etc/apt/sources.list "$BEISEITE/sources.list"
  fi
  printf '# Nur im Ende-zu-Ende-Test (test/container/basis-e2e.sh): lokale Quelle ohne Signatur\nTypes: deb\nURIs: file:%s\nSuites: e2e e2e-security\nComponents: main\nTrusted: yes\n' \
    "$REPO" > "$QUELLE"
  ok "Quellen von Ubuntu beiseite ($BEISEITE), nur file:$REPO"

  # greetd im Original (Inhalt und Maintainer-Skripte wie echt), nur die Version ändert der Test
  if [[ ! -f "$E2E/greetd-original.deb" ]]; then
    arch=$(dpkg --print-architecture)
    greetd_v=$(version greetd)
    greetd_v=${greetd_v%%+e2e*}
    datei=/var/cache/apt/archives/greetd_${greetd_v//:/%3a}_$arch.deb
    [[ -f "$datei" ]] || fehler "$datei fehlt (vor einrichten: apt-get download greetd)"
    cp "$datei" "$E2E/greetd-original.deb"
  fi
  ok "greetd $(dpkg-deb -f "$E2E/greetd-original.deb" Version) aus dem Cache"

  grundstock "${GRUNDSTOCK[@]}"
  quelle
  for datei in "${GRUNDSTOCK[@]}"; do
    [[ -n "$(version "${datei%%:*}")" ]] || fehler "${datei%%:*} fehlt"
  done
  [[ "$(apt-mark showauto lxd-installer zenos-e2e-frei | sort | tr '\n' ' ')" == "lxd-installer zenos-e2e-frei " ]] ||
    fehler "lxd-installer und zenos-e2e-frei nicht automatisch installiert"
  ok "Attrappen installiert (${#GRUNDSTOCK[@]}, lxd-installer und zenos-e2e-frei automatisch)"

  for timer in "${TIMER[@]}"; do
    install -d -m 0755 "/run/systemd/system/$timer.d"
    printf '# Nur im Ende-zu-Ende-Test: kein Lauf von selbst\n[Timer]\nOnBootSec=\nOnCalendar=\nOnCalendar=2099-01-01 00:00:00\nPersistent=false\n' \
      > "/run/systemd/system/$timer.d/e2e.conf"
  done
  systemctl daemon-reload
  ok "Timer lösen im Test nicht von selbst aus (${TIMER[*]})"

  if [[ -e /etc/xdg/zenos/kanal-automatik-aus ]]; then
    mv /etc/xdg/zenos/kanal-automatik-aus "$BEISEITE/kanal-automatik-aus"
  fi
  if [[ ! -e "$BEISEITE/kanal-zeitpunkt" && ! -e "$BEISEITE/kanal-zeitpunkt.fehlte" ]]; then
    if [[ -f /etc/xdg/zenos/kanal-zeitpunkt ]]; then
      cp -p /etc/xdg/zenos/kanal-zeitpunkt "$BEISEITE/kanal-zeitpunkt"
    else
      : > "$BEISEITE/kanal-zeitpunkt.fehlte"
    fi
  fi
  zeitpunkt jederzeit
  ok "Zeitpunkt jederzeit, kein Notschalter"
  neustart_vergessen
  systemctl reset-failed 'zenos-basis-*' 2> /dev/null || true
}

s_automatik() {
  schritt "automatik: «von Hand» wartet, «jederzeit» installiert (mit greetd und einem Dienst)"
  local v_auto v_dienst v_greetd alt_greetd greetd_id greetd_zustand dienst_id beginn rc
  v_auto=$(naechste zenos-e2e-auto)
  v_dienst=$(naechste zenos-e2e-dienst)
  v_greetd=$(naechste_greetd)
  alt_greetd=$(version greetd)
  bauen zenos-e2e-auto "$v_auto"
  bauen zenos-e2e-dienst "$v_dienst"
  greetd_bauen "$v_greetd"
  quelle "e2e:zenos-e2e-auto=$v_auto" "e2e:zenos-e2e-dienst=$v_dienst" "e2e:greetd=$v_greetd"
  neustart_vergessen
  systemctl start zenos-e2e-dienst.service
  greetd_id=$(invocation greetd.service)
  greetd_zustand=$(systemctl show -p ActiveState --value greetd.service)
  dienst_id=$(invocation zenos-e2e-dienst.service)

  zeitpunkt hand
  rc=$(unit_lauf zenos-basis-automatik.service)
  [[ "$rc" == 0 ]] || fehler "Automatik (von Hand): Exit $rc"
  [[ "$(json "$STAND/stand.json" .ergebnis)" == bereit ]] || fehler "stand.json: $(json "$STAND/stand.json" .grund)"
  [[ "$(json "$STAND/stand.json" .anzahl)" == 3 && "$(json "$STAND/stand.json" .neustart)" == true ]] ||
    fehler "stand.json: anzahl $(json "$STAND/stand.json" .anzahl), neustart $(json "$STAND/stand.json" .neustart)"
  [[ "$(json "$STAND/stand.json" '.neustart_wegen | join(" ")')" == greetd ]] || fehler "neustart_wegen"
  ok "geprüft: 3 Updates bereit, Neustart voraussichtlich nötig (greetd)"
  [[ "$(cat "$STAND/automatik-bereit")" == "$(liste)" ]] || fehler "Marker automatik-bereit fehlt oder passt nicht"
  [[ "$(json "$STAND/automatik.json" .ergebnis)" == wartet ]] ||
    fehler "automatik.json: $(json "$STAND/automatik.json" .ergebnis) – $(json "$STAND/automatik.json" .grund)"
  erwarte_version zenos-e2e-auto "$(( ${v_auto%%.*} - 1 )).0" "von Hand: nichts installiert"
  ok "von Hand: wartet ($(json "$STAND/automatik.json" .grund))"

  zeitpunkt jederzeit
  beginn=$(date +%s)
  sleep 1
  rc=$(unit_lauf zenos-basis-gelegenheit.service)
  [[ "$rc" == 0 ]] || fehler "Gelegenheit: Exit $rc"
  [[ "$(json "$STAND/automatik.json" .art) $(json "$STAND/automatik.json" .ergebnis)" == "gelegenheit installiert" ]] ||
    fehler "automatik.json: $(json "$STAND/automatik.json" .ergebnis) – $(json "$STAND/automatik.json" .grund)"
  erwarte_version zenos-e2e-auto "$v_auto" "Gelegenheit"
  erwarte_version zenos-e2e-dienst "$v_dienst" "Gelegenheit"
  erwarte_version greetd "$v_greetd" "Gelegenheit"
  [[ "$(json "$STAND/letzte.json" '"\(.ergebnis) \(.von) \(.zustimmung)"')" == "installiert automatik false" ]] ||
    fehler "letzte.json: $(json "$STAND/letzte.json" .ergebnis) – $(json "$STAND/letzte.json" .grund)"
  ok "letzte.json: installiert, von der Automatik, ohne Zustimmung"
  [[ "$(json "$STAND/stand.json" .ergebnis)" == aktuell && ! -e "$STAND/automatik-bereit" ]] ||
    fehler "danach nicht aktuell oder Marker automatik-bereit bleibt"
  ok "danach aktuell, Marker automatik-bereit weg"
  nicht_ausgefallen "$INSTALLIEREN" zenos-basis-gelegenheit.service zenos-basis-automatik.service
  danach_sauber "Gelegenheit"

  schritt "automatik: greetd startet nicht neu, andere Dienste schon"
  [[ "$(invocation greetd.service)" == "$greetd_id" &&
    "$(systemctl show -p ActiveState --value greetd.service)" == "$greetd_zustand" ]] ||
    fehler "greetd wurde neu gestartet ($greetd_zustand → $(systemctl show -p ActiveState --value greetd.service))"
  [[ -z "$(journalctl -q -u greetd.service --since "@$beginn" -o cat)" ]] || fehler "greetd im Journal seit dem Update"
  ok "greetd unberührt ($greetd_zustand, $alt_greetd → $v_greetd)"
  enthaelt "policy-rc.d denied execution of restart" journalctl -q -u "$INSTALLIEREN" --since "@$beginn" -o cat ||
    fehler "keine Ablehnung durch die policy-rc.d im Journal"
  ok "policy-rc.d der Basis lehnte den Neustart von greetd ab"
  [[ "$(invocation zenos-e2e-dienst.service)" != "$dienst_id" ]] || fehler "zenos-e2e-dienst nicht neu gestartet"
  systemctl --quiet is-active zenos-e2e-dienst.service || fehler "zenos-e2e-dienst läuft nicht"
  ok "zenos-e2e-dienst neu gestartet (wie bei Ubuntu)"
  grep -qx greetd /run/reboot-required.pkgs 2>/dev/null || fehler "greetd fehlt in /run/reboot-required.pkgs"
  [[ "$(json "$STAND/letzte.json" .neustart)" == true ]] || fehler "letzte.json: neustart"
  ok "Neustart nötig wegen greetd (/run/reboot-required.pkgs, letzte.json)"
}

s_zen_update() {
  schritt "zen-update: zen update --nur-basis --ja ohne Frage"
  local v_werkzeug v_sicher rc=0 n zeile
  neustart_vergessen
  v_werkzeug=$(naechste zenos-e2e-werkzeug)
  v_sicher=$(naechste zenos-e2e-sicher)
  bauen zenos-e2e-werkzeug "$v_werkzeug"
  bauen zenos-e2e-sicher "$v_sicher"
  quelle "e2e:zenos-e2e-werkzeug=$v_werkzeug" "e2e-security:zenos-e2e-sicher=$v_sicher"
  zen_als_tester "" zen update --nur-basis --ja || rc=$?
  erwarte_rc "$rc" 0 "zen update --nur-basis --ja"
  erwarte_text "Updates: 2, davon Sicherheit: 1" "Zusammenfassung: 2 Updates, 1 Sicherheit"
  erwarte_text "Kernel, Firmware, Bootloader: nein" "Zusammenfassung: kein Kernel"
  ohne_text "Tippe «ja»" "keine Rückfrage mit --ja"
  ohne_text "Schritt 1 von 2" "nur der Basis-Schritt"
  erwarte_text "Ubuntu-Basis: gelungen." "Schritt meldet «gelungen»"
  erwarte_version zenos-e2e-werkzeug "$v_werkzeug" "zen update"
  erwarte_version zenos-e2e-sicher "$v_sicher" "zen update"
  [[ "$(json "$STAND/letzte.json" '"\(.ergebnis) \(.von) \(.zustimmung) \(.sicherheit)"')" == \
    "installiert zen update true 1" ]] || fehler "letzte.json: $(json "$STAND/letzte.json" .grund)"
  ok "letzte.json: installiert über zen update, 1 Sicherheitsupdate"
  grep -q '^== Ende .* · normal · ok · ' "$STAND/install-ergebnis" || fehler "install-ergebnis ohne «== Ende … ok»"
  ok "install.sh lief danach (install-ergebnis)"
  danach_sauber "zen update"

  schritt "zen-update: nichts mehr da"
  rc=0
  zen_als_tester "" zen update --nur-basis || rc=$?
  erwarte_rc "$rc" 0 "zen update --nur-basis ohne Updates"
  erwarte_text "Die Ubuntu-Basis ist aktuell." "aktuell"
  ohne_text "Tippe «ja»" "keine Rückfrage ohne Updates"

  schritt "zen-update: install.sh danach zweimal von Hand, 0 Änderungen"
  for n in 1 2; do
    root_lauf "$E2E/install-$n.txt" env HOME=/root /opt/zenos/scripts/install.sh --ruhig ||
      { tail -n 30 "$E2E/install-$n.txt" >&2; fehler "install.sh Lauf $n"; }
    zeile=$(grep '^== Ende' /var/log/zenos/install.log | tail -n 1)
    [[ "$zeile" == *" · normal · ok · 0 Änderungen · "* ]] || fehler "install.sh Lauf $n: $zeile"
    ok "install.sh Lauf $n: $zeile"
  done
}

s_kernel() {
  schritt "kernel: Attrappe linux-image-e2e-raspi"
  local v_kernel v_werkzeug alt_kernel rc=0 hash
  neustart_vergessen
  alt_kernel=$(version linux-image-e2e-raspi)
  v_kernel=$(naechste linux-image-e2e-raspi)
  v_werkzeug=$(naechste zenos-e2e-werkzeug)
  bauen linux-image-e2e-raspi "$v_kernel"
  bauen zenos-e2e-werkzeug "$v_werkzeug"
  quelle "e2e:linux-image-e2e-raspi=$v_kernel" "e2e:zenos-e2e-werkzeug=$v_werkzeug"

  rc=$(unit_lauf zenos-basis-automatik.service)
  [[ "$rc" == 0 ]] || fehler "Automatik: Exit $rc"
  [[ "$(json "$STAND/stand.json" '"\(.ergebnis) \(.heikel | join(",")) \(.neustart)"')" == \
    "zustimmung linux-image-e2e-raspi true" ]] || fehler "stand.json: $(json "$STAND/stand.json" .grund)"
  ok "geprüft: braucht Zustimmung (Kernel linux-image-e2e-raspi), Neustart voraussichtlich"
  [[ "$(json "$STAND/automatik.json" .ergebnis)" == zustimmung ]] || fehler "automatik.json: $(json "$STAND/automatik.json" .ergebnis)"
  enthaelt "Basis-Updates warten auf dich" json "$STAND/automatik.json" .grund || fehler "automatik.json: Grund"
  [[ ! -e "$STAND/automatik-bereit" ]] || fehler "Marker automatik-bereit trotz Kernel"
  erwarte_version linux-image-e2e-raspi "$alt_kernel" "Automatik installiert keinen Kernel"
  erwarte_version zenos-e2e-werkzeug "$(( ${v_werkzeug%%.*} - 1 )).0" "Automatik installiert auch den Rest nicht"
  rc=$(unit_lauf zenos-basis-gelegenheit.service)
  erwarte_version linux-image-e2e-raspi "$alt_kernel" "Gelegenheit (ohne Marker) installiert nichts"

  hash=$(liste)
  rc=0
  root_lauf "$E2E/jetzt.txt" basis jetzt "$hash" || rc=$?
  erwarte_rc "$rc" 10 "«Jetzt installieren» ohne Passwort" "$E2E/jetzt.txt"
  erwarte_version linux-image-e2e-raspi "$alt_kernel" "ohne Passwort nichts"
  nicht_ausgefallen "$INSTALLIEREN"

  rc=0
  zen_als_tester "nein" zen update --nur-basis || rc=$?
  erwarte_rc "$rc" 10 "zen update mit «nein»"
  erwarte_text "Kernel, Firmware, Bootloader: linux-image-e2e-raspi" "Zusammenfassung nennt den Kernel"
  erwarte_text "Neustart voraussichtlich nötig" "Zusammenfassung: Neustart voraussichtlich"
  erwarte_text "Tippe «ja»" "Rückfrage"
  erwarte_text "Nichts geändert." "«nein» ändert nichts"
  erwarte_version linux-image-e2e-raspi "$alt_kernel" "nach «nein»"

  rc=0
  zen_als_tester "ja" zen update --nur-basis || rc=$?
  erwarte_rc "$rc" 0 "zen update mit «ja»"
  erwarte_version linux-image-e2e-raspi "$v_kernel" "nach «ja»"
  erwarte_version zenos-e2e-werkzeug "$v_werkzeug" "nach «ja»"
  erwarte_text "Neustart nötig" "Ergebnis nennt «Neustart nötig»"
  grep -qx linux-image-e2e-raspi /run/reboot-required.pkgs 2>/dev/null || fehler "/run/reboot-required.pkgs"
  [[ "$(json "$STAND/letzte.json" '"\(.ergebnis) \(.zustimmung) \(.neustart) \(.heikel | join(","))"')" == \
    "installiert true true linux-image-e2e-raspi" ]] || fehler "letzte.json: $(json "$STAND/letzte.json" .grund)"
  ok "letzte.json: installiert mit Zustimmung, Neustart nötig"
  basis status > "$E2E/status.txt"
  erwarte_text "^Neustart  *nötig (linux-image-e2e-raspi)" "zenos-basis status: Neustart nötig" "$E2E/status.txt"
  runuser -u "$TESTER" -- zen version > "$E2E/version.txt"
  erwarte_text "^Pakete  *aktuell · Neustart nötig" "zen version: «Pakete … Neustart nötig»" "$E2E/version.txt"
  danach_sauber "Kernel"
}

s_schutz() {
  schritt "schutz: geschütztes Paket ginge weg – gesperrt"
  local v_konflikt v_werkzeug alt_konflikt alt_werkzeug rc=0 hash
  grundstock lxd-installer:auto zenos-e2e-frei:auto zenos-e2e-konflikt zenos-e2e-werkzeug
  alt_konflikt=$(version zenos-e2e-konflikt)
  alt_werkzeug=$(version zenos-e2e-werkzeug)
  v_konflikt=$(naechste zenos-e2e-konflikt)
  v_werkzeug=$(naechste zenos-e2e-werkzeug)
  bauen zenos-e2e-konflikt "$v_konflikt" "Conflicts: lxd-installer"
  bauen zenos-e2e-werkzeug "$v_werkzeug"
  quelle "e2e:zenos-e2e-konflikt=$v_konflikt" "e2e:zenos-e2e-werkzeug=$v_werkzeug"
  enthaelt "^Remv lxd-installer" simulation || fehler "Vorbedingung: apt-get -s full-upgrade entfernt lxd-installer nicht"
  ok "Vorbedingung: apt-get -s full-upgrade entfernt lxd-installer"

  zen_als_tester "" zen update --nur-basis --ja || rc=$?
  erwarte_rc "$rc" 3 "zen update --nur-basis --ja"
  erwarte_text "geschützte Pakete entfernen (lxd-installer)" "Grund: geschütztes Paket"
  erwarte_text "Ubuntu-Basis: nicht gelungen – abgelehnt (Exit 3)." "Schritt meldet «abgelehnt»"
  [[ "$(json "$STAND/stand.json" '"\(.ergebnis) \(.geschuetzt | join(","))"')" == "gesperrt lxd-installer" ]] ||
    fehler "stand.json: $(json "$STAND/stand.json" .grund)"
  ok "stand.json: gesperrt (lxd-installer)"
  hash=$(liste)
  rc=0
  root_lauf "$E2E/zustimmen.txt" basis zustimmen "$hash" || rc=$?
  erwarte_rc "$rc" 3 "«Mit Passwort installieren»" "$E2E/zustimmen.txt"
  rc=0
  root_lauf "$E2E/hand.txt" basis installieren --liste "$hash" --zustimmung || rc=$?
  erwarte_rc "$rc" 3 "zenos-basis installieren --zustimmung" "$E2E/hand.txt"
  rc=$(unit_lauf zenos-basis-automatik.service)
  [[ "$(json "$STAND/automatik.json" .ergebnis)" == gesperrt ]] || fehler "automatik.json: $(json "$STAND/automatik.json" .ergebnis)"
  ok "Automatik: gesperrt"
  [[ -n "$(version lxd-installer)" ]] || fehler "lxd-installer wurde entfernt"
  erwarte_version zenos-e2e-konflikt "$alt_konflikt" "gesperrt"
  erwarte_version zenos-e2e-werkzeug "$alt_werkzeug" "gesperrt: auch der Rest nicht"
  ok "lxd-installer bleibt"
  nicht_ausgefallen "$INSTALLIEREN"
  danach_sauber "gesperrt"

  schritt "schutz: ein ungeschütztes Paket ginge weg – nur nach «ja»"
  v_konflikt=$(naechste zenos-e2e-konflikt)
  v_konflikt=$(( ${v_konflikt%%.*} + 1 )).0
  bauen zenos-e2e-konflikt "$v_konflikt" "Conflicts: zenos-e2e-frei"
  quelle "e2e:zenos-e2e-konflikt=$v_konflikt"
  enthaelt "^Remv zenos-e2e-frei" simulation || fehler "Vorbedingung: apt-get -s full-upgrade entfernt zenos-e2e-frei nicht"
  rc=$(unit_lauf zenos-basis-automatik.service)
  [[ "$(json "$STAND/stand.json" '"\(.ergebnis) \(.entfernen | join(","))"')" == "zustimmung zenos-e2e-frei" ]] ||
    fehler "stand.json: $(json "$STAND/stand.json" .grund)"
  [[ "$(json "$STAND/automatik.json" .ergebnis)" == zustimmung && -n "$(version zenos-e2e-frei)" ]] ||
    fehler "Automatik entfernte oder wartete nicht"
  ok "Automatik: wartet auf dich, zenos-e2e-frei bleibt"
  rc=0
  root_lauf "$E2E/jetzt.txt" basis jetzt "$(liste)" || rc=$?
  erwarte_rc "$rc" 10 "«Jetzt installieren» ohne Passwort" "$E2E/jetzt.txt"
  rc=0
  zen_als_tester "ja" zen update --nur-basis || rc=$?
  erwarte_rc "$rc" 0 "zen update mit «ja»"
  erwarte_text "Entfernungen: zenos-e2e-frei" "Zusammenfassung nennt die Entfernung"
  [[ -z "$(version zenos-e2e-frei)" ]] || fehler "zenos-e2e-frei noch da"
  erwarte_version zenos-e2e-konflikt "$v_konflikt" "nach «ja»"
  [[ "$(json "$STAND/letzte.json" '.entfernt | join(",")')" == zenos-e2e-frei ]] || fehler "letzte.json: entfernt"
  ok "zenos-e2e-frei entfernt, letzte.json nennt es"
  danach_sauber "Entfernung"

  # Grundstock wieder herstellen: zenos-e2e-konflikt ohne Konflikt, zenos-e2e-frei wieder da (automatisch installiert)
  v_konflikt=$(naechste zenos-e2e-konflikt)
  bauen zenos-e2e-konflikt "$v_konflikt"
  bauen zenos-e2e-frei 1.0
  quelle "e2e:zenos-e2e-konflikt=$v_konflikt" "e2e:zenos-e2e-frei=1.0"
  DEBIAN_FRONTEND=noninteractive apt-get -qq -y --no-remove install zenos-e2e-konflikt zenos-e2e-frei \
    > "$E2E/apt-install.txt" 2>&1 || { cat "$E2E/apt-install.txt" >&2; fehler "Grundstock wieder herstellen"; }
  apt-mark auto zenos-e2e-frei > /dev/null
  quelle
}

s_abbruch() {
  schritt "abbruch: kill der Unit mitten in dpkg"
  local v_halten alt_halten rc=0 hinten beginn
  grundstock zenos-e2e-halten
  alt_halten=$(version zenos-e2e-halten)
  v_halten=$(naechste zenos-e2e-halten)
  bauen zenos-e2e-halten "$v_halten"
  quelle "e2e:zenos-e2e-halten=$v_halten"
  rm -f "$E2E/halten.laeuft"
  : > "$E2E/halten"
  zen_lauf "$E2E/hinten" "" zen update --nur-basis --ja &
  hinten=$!
  for _ in $(seq 1 180); do [[ -e "$E2E/halten.laeuft" ]] && break; sleep 1; done
  [[ -e "$E2E/halten.laeuft" ]] || { rm -f "$E2E/halten"; wait "$hinten" || true; fehler "dpkg kam nicht bis zur Attrappe"; }
  ok "dpkg steht im postinst von zenos-e2e-halten"
  [[ -f /run/zenos-basis/uebernahme ]] || fehler "Übernahme-Marker fehlt während des Laufs"
  enthaelt "Ubuntu-Basis wird aktualisiert" systemd-inhibit --list --no-pager || fehler "Inhibitor fehlt während des Laufs"
  grep -q '^# zenOS-Basis: ' "$POLICY" 2>/dev/null || fehler "$POLICY der Basis fehlt während des Laufs"
  ok "während des Laufs: Marker, Inhibitor, policy-rc.d der Basis"
  systemctl kill --signal=KILL "$INSTALLIEREN"
  rc=0
  wait "$hinten" || rc=$?
  [[ "$rc" != 0 ]] || fehler "zen update meldet nach dem kill Erfolg"
  erwarte_text "Ubuntu-Basis: nicht gelungen" "zen update meldet den Abbruch (Exit $rc)" "$E2E/hinten.txt"
  rm -f "$E2E/halten"
  for _ in $(seq 1 30); do systemctl --quiet is-active "$INSTALLIEREN" || break; sleep 1; done
  dpkg_unterbrochen || fehler "dpkg ist nach dem kill nicht unterbrochen (/var/lib/dpkg/updates leer)"
  ok "dpkg unterbrochen (/var/lib/dpkg/updates, zenos-e2e-halten $(dpkg-query -W -f='${db:Status-Status}' zenos-e2e-halten))"
  grep -q '^# zenOS-Basis: ' "$POLICY" 2>/dev/null || fehler "$POLICY der Basis ist nach dem kill weg (erwartet: bleibt liegen)"
  [[ ! -e /run/zenos-basis ]] || fehler "/run/zenos-basis bleibt nach dem kill"
  flock -n /run/zenos-sperre/kanal.lock true || fehler "kanal.lock bleibt nach dem kill belegt"
  ok "nach dem kill: policy-rc.d der Basis bleibt liegen, Marker weg, Sperre frei"

  schritt "abbruch: das nächste zen update repariert"
  # Auswertung von jetzt: apt-get -s sähe den halb konfigurierten Stand als «aktuell» (nur eine Zeile «Conf»)
  if enthaelt "^Inst " simulation; then fehler "Vorbedingung: apt-get -s full-upgrade zeigt noch «Inst»"; fi
  enthaelt "^Conf zenos-e2e-halten" simulation || fehler "Vorbedingung: apt-get -s full-upgrade ohne «Conf zenos-e2e-halten»"
  ok "Vorbedingung: apt-get -s zeigt nur «Conf zenos-e2e-halten» (ohne Nachholen hiesse das «aktuell»)"
  beginn=$(date +%s)
  sleep 1
  rc=0
  zen_als_tester "" zen update --nur-basis --ja || rc=$?
  erwarte_rc "$rc" 0 "zen update --nur-basis --ja"
  erwarte_text "Die Prüfung holt zuerst «dpkg --configure -a» nach" "zen update sagt, dass dpkg unterbrochen war"
  enthaelt "dpkg wurde unterbrochen: dpkg --configure -a" journalctl -q -u zenos-basis-pruefen.service \
    --since "@$beginn" -o cat || fehler "die Prüfung holte «dpkg --configure -a» nicht nach (Journal)"
  ok "die Prüfung holte «dpkg --configure -a» nach (Journal)"
  erwarte_text "Die Ubuntu-Basis ist aktuell." "danach aktuell"
  if [[ -n "$(dpkg --audit 2>/dev/null)" ]] || dpkg_unterbrochen; then
    fehler "dpkg danach nicht sauber: $(dpkg --audit 2>&1 | head -n 3)"
  fi
  ok "dpkg danach sauber (dpkg --audit ohne Befund)"
  erwarte_version zenos-e2e-halten "$v_halten" "nach der Reparatur"
  [[ "$alt_halten" != "$v_halten" ]] || fehler "Version unverändert"
  danach_sauber "Reparatur"
}

s_sperre() {
  schritt "sperre: während einer Basis-Installation"
  local v_halten rc=0 hinten hand parallel=0 hash
  grundstock zenos-e2e-halten
  v_halten=$(naechste zenos-e2e-halten)
  bauen zenos-e2e-halten "$v_halten"
  quelle "e2e:zenos-e2e-halten=$v_halten"
  rm -f "$E2E/halten.laeuft"
  : > "$E2E/halten"
  zen_lauf "$E2E/hinten" "" zen update --nur-basis --ja &
  hinten=$!
  for _ in $(seq 1 180); do [[ -e "$E2E/halten.laeuft" ]] && break; sleep 1; done
  [[ -e "$E2E/halten.laeuft" ]] || { rm -f "$E2E/halten"; wait "$hinten" || true; fehler "dpkg kam nicht bis zur Attrappe"; }
  ok "Basis-Installation läuft (dpkg im postinst der Attrappe)"
  hash=$(liste)

  rc=0
  root_lauf "$E2E/kanal.txt" /usr/bin/python3 -I "$KANAL" pruefen || rc=$?
  erwarte_rc "$rc" 75 "zenos-kanal pruefen" "$E2E/kanal.txt"
  rc=0
  zen_als_tester "" zen update --nur-zenos || rc=$?
  erwarte_rc "$rc" 75 "zen update --nur-zenos"
  erwarte_text "läuft" "zen update --nur-zenos: läuft gerade"
  rc=0
  root_lauf "$E2E/zweite.txt" basis installieren --liste "$hash" || rc=$?
  erwarte_rc "$rc" 75 "zweites zenos-basis installieren" "$E2E/zweite.txt"
  ! systemctl --quiet is-active zenos-kanal-installieren.service || fehler "zenos-kanal-installieren läuft parallel"
  # install.sh von Hand wie dokumentiert als Benutzer (sudo nur für die Systemteile). Als root (sudo -i) nähme es zuerst
  # die Sperre von install.sh und wartete dann auf die des Kanals, während das install.sh der Basis auf die erste wartet:
  # bis 15 Minuten, dann Exit 75 (README, «Grenzen»)
  runuser -u "$TESTER" -- env HOME=/home/$TESTER /home/$TESTER/zenOS/scripts/install.sh < /dev/null \
    > "$E2E/hand-wartet.txt" 2>&1 &
  hand=$!
  for _ in $(seq 1 60); do
    grep -q "Der Kanal prüft oder installiert gerade, warte" "$E2E/hand-wartet.txt" && break
    sleep 1
  done
  grep -q "Der Kanal prüft oder installiert gerade, warte" "$E2E/hand-wartet.txt" ||
    { cat "$E2E/hand-wartet.txt" >&2; fehler "install.sh von Hand wartete nicht"; }
  [[ ! -e /run/zenos-sperre/hand ]] || fehler "install.sh von Hand läuft neben der Basis"
  kill -0 "$hand" 2>/dev/null || { cat "$E2E/hand-wartet.txt" >&2; fehler "install.sh von Hand endete"; }
  ok "install.sh von Hand (tester) wartet auf die Sperre"

  rm -f "$E2E/halten"
  # Bis zum Ende der Basis darf der Vermerk des Laufs von Hand nie auftauchen
  while systemctl --quiet is-active "$INSTALLIEREN" || [[ "$(systemctl show -p ActiveState --value "$INSTALLIEREN")" == activating ]]; do
    [[ ! -e /run/zenos-sperre/hand ]] || parallel=1
    sleep 0.5
  done
  rc=0
  wait "$hinten" || rc=$?
  erwarte_rc "$rc" 0 "Basis-Installation" "$E2E/hinten.txt"
  (( ! parallel )) || fehler "install.sh von Hand lief, während die Basis installierte"
  erwarte_version zenos-e2e-halten "$v_halten" "Basis-Installation"
  rc=0
  wait "$hand" || rc=$?
  erwarte_rc "$rc" 0 "install.sh von Hand danach" "$E2E/hand-wartet.txt"
  ok "nie parallel: install.sh von Hand begann erst nach der Basis"

  schritt "sperre: der Kanal hält die Sperre"
  v_halten=$(naechste zenos-e2e-halten)
  bauen zenos-e2e-halten "$v_halten"
  quelle "e2e:zenos-e2e-halten=$v_halten"
  rc=$(unit_lauf zenos-basis-pruefen.service)
  hash=$(liste)
  # wie ein Lauf des Kanals: dieselbe Sperre /run/zenos-sperre/kanal.lock (flock -o: nur flock hält sie)
  flock -o /run/zenos-sperre/kanal.lock sleep 600 &
  local halter=$!
  sleep 1
  rc=0
  zen_als_tester "" zen update --nur-basis --ja || rc=$?
  erwarte_rc "$rc" 75 "zen update --nur-basis --ja"
  erwarte_text "läuft gerade" "Grund: läuft gerade"
  rc=0
  root_lauf "$E2E/zweite.txt" basis installieren --liste "$hash" || rc=$?
  erwarte_rc "$rc" 75 "zenos-basis installieren" "$E2E/zweite.txt"
  kill "$halter" 2>/dev/null || true
  wait "$halter" 2>/dev/null || true
  erwarte_version zenos-e2e-halten "$(( ${v_halten%%.*} - 1 )).0" "nichts installiert"

  schritt "sperre: ein install.sh von Hand läuft (Vermerk wie _hand_vermerken)"
  # Der Vermerk, den install.sh von Hand unter der Sperre des Kanals schreibt: seine PID in /run/zenos-sperre/hand. Eine
  # Attrappe namens install.sh, die wartet, hält den Zeitpunkt fest (ein echter Lauf wäre in Sekunden fertig)
  install -d -m 0755 "$E2E/hand"
  printf '#!/bin/bash\n# Attrappe: ein install.sh von Hand, das gerade läuft (test/container/basis-e2e.sh)\nsleep 600\n' \
    > "$E2E/hand/install.sh"
  chmod 0755 "$E2E/hand/install.sh"
  "$E2E/hand/install.sh" &
  hand=$!
  printf '%s\n' "$hand" > /run/zenos-sperre/hand
  rc=0
  root_lauf "$E2E/zweite.txt" basis installieren --liste "$hash" || rc=$?
  erwarte_rc "$rc" 75 "zenos-basis installieren" "$E2E/zweite.txt"
  erwarte_text "install.sh von Hand läuft gerade (PID $hand)" "Grund: install.sh von Hand" "$E2E/zweite.txt"
  rc=0
  zen_als_tester "" zen update --nur-basis --ja || rc=$?
  erwarte_rc "$rc" 75 "zen update --nur-basis --ja"
  erwarte_text "install.sh von Hand läuft gerade" "zen update: Grund install.sh von Hand"
  kill "$hand" 2>/dev/null || true
  wait "$hand" 2>/dev/null || true
  rm -f /run/zenos-sperre/hand
  erwarte_version zenos-e2e-halten "$(( ${v_halten%%.*} - 1 )).0" "nichts installiert"
  rc=0
  zen_als_tester "" zen update --nur-basis --ja || rc=$?
  erwarte_rc "$rc" 0 "zen update danach"
  erwarte_version zenos-e2e-halten "$v_halten" "danach installiert"
  danach_sauber "Sperre"
}

s_aufraeumen() {
  schritt "aufraeumen"
  local datei timer attrappen=() name
  for name in zenos-e2e-auto zenos-e2e-dienst zenos-e2e-werkzeug zenos-e2e-sicher linux-image-e2e-raspi \
    zenos-e2e-konflikt zenos-e2e-frei zenos-e2e-halten lxd-installer; do
    if [[ "$name" == lxd-installer ]] && [[ "$(dpkg-query -W -f='${Description}' lxd-installer 2>/dev/null)" != Attrappe* ]]; then
      continue
    fi
    dpkg-query -W "$name" > /dev/null 2>&1 && attrappen+=("$name")
  done
  if (( ${#attrappen[@]} )); then
    dpkg --purge "${attrappen[@]}" > "$E2E/purge.txt" 2>&1 || { cat "$E2E/purge.txt" >&2; fehler "Attrappen entfernen"; }
  fi
  ok "Attrappen entfernt (${#attrappen[@]})"
  rm -f "$QUELLE" "$E2E/halten" "$E2E/halten.laeuft"
  for datei in "$BEISEITE"/*; do
    [[ -e "$datei" ]] || continue
    case "${datei##*/}" in
      sources.list) mv "$datei" /etc/apt/sources.list ;;
      kanal-automatik-aus | kanal-zeitpunkt) mv "$datei" "/etc/xdg/zenos/${datei##*/}" ;;
      kanal-zeitpunkt.fehlte) rm -f /etc/xdg/zenos/kanal-zeitpunkt "$datei" ;;
      *) mv "$datei" /etc/apt/sources.list.d/ ;;
    esac
  done
  ok "Quellen, Zeitpunkt und Notschalter wie vorher (apt-get update mit Netz holt die Listen von Ubuntu wieder)"
  for timer in "${TIMER[@]}"; do rm -rf "/run/systemd/system/$timer.d"; done
  systemctl daemon-reload
  neustart_vergessen
  ok "Timer wie vorher"
}

if (( $# == 0 )); then
  sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
for arg in "$@"; do
  case "$arg" in
    einrichten | automatik | zen-update | kernel | schutz | abbruch | sperre | aufraeumen | alle) ;;
    *) sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
for arg in "$@"; do
  case "$arg" in
    einrichten) s_einrichten ;;
    automatik) s_automatik ;;
    zen-update) s_zen_update ;;
    kernel) s_kernel ;;
    schutz) s_schutz ;;
    abbruch) s_abbruch ;;
    sperre) s_sperre ;;
    aufraeumen) s_aufraeumen ;;
    alle) s_einrichten; s_automatik; s_zen_update; s_kernel; s_schutz; s_abbruch; s_sperre; s_aufraeumen ;;
  esac
done
printf '\nalles gut: %s\n' "$*"
