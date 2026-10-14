#!/usr/bin/env bash
# einrichten.sh – richtet zenOS am Ende der Ubuntu-Installation auf einem x86-Rechner ein (Installer-Stick).
#
#   bash /cdrom/zenos/einrichten.sh /target
#
# Läuft als root im Ubuntu-Installer (late-commands in image/x86/autoinstall.yaml), das neu installierte System liegt
# unter ZIEL (/target). Dasselbe wie Schritt 4 und 5 von image/bauen.sh für das Pi-Image:
#   1. Stand lesen: zenos/stand neben diesem Skript (Tag, Commit, Kanal, Version, origin, signiert; geschrieben von
#      image/x86-stick.sh, der den Tag vorher mit image/tag-pruefen.sh geprüft hat), dazu zenos/zenos.bundle.
#   2. chroot vorbereiten: /dev, /proc, /sys als Bind, /run und /tmp als frische tmpfs (ohne /run/systemd/system weiss
#      install.sh, dass kein systemd läuft), Namensauflösung über /run/systemd/resolve/, policy-rc.d gegen
#      Dienststarts. /var/tmp bleibt auf der Platte (Quickshell-Bau, etwa 3,5 GB).
#   3. /opt/zenos: Klon aus dem Bundle, losgelöst auf dem Commit, ohne Zweige, mit allen Tags, origin auf GitHub
#      (https), Besitz root, sauber.
#   3a. Ubuntu Desktop als Grundlage: Ein anderer Anmeldedienst (gdm3) wird deaktiviert, sein Paket bleibt. Sonst liesse
#      install.sh greetd aus (40-sitzung, auf einem laufenden System richtig), und es käme GNOME statt zenOS.
#   4. «ZENOS_KANAL=<kanal> /opt/zenos/scripts/install.sh --image» mit leerer Umgebung im chroot.
#   4a. Verwaltet NetworkManager das Netz schon (Ubuntu Desktop), entfällt die Umstellung beim ersten Start.
#   5. Prüfen: Kanal wie im Stand; bei einem signierten Tag Anker vollständig und «zenos-kanal image <tag>» (prüft den
#      Tag im installierten System noch einmal wie ein Gerät und legt den Zustand ab Werk an). Kennung zenOS nur mit
#      nachgewiesener Ubuntu-Sicherheitsquelle (zenos-sicherheitsquelle).
#   6. Aufräumen: apt-Cache, Bundle, policy-rc.d, Namensauflösung, Einhängepunkte. Das Protokoll liegt danach unter
#      /var/log/zenos/stick.log im installierten System.
# Benutzer, Passwort, Rechnername, SSH-Hostschlüssel und machine-id kommen vom Ubuntu-Installer; hier wird nichts davon
# angefasst. Persönliches entsteht beim ersten Start (Einrichtung von zenOS), proprietäre Apps nur mit Zustimmung.
# Exit 0: eingerichtet. Sonst meldet der Installer einen Fehler; Ubuntu ist installiert, zenOS lässt sich nach dem
# Neustart von Hand einrichten (ANLEITUNG.md, Abschnitt «x86»).

set -Eeuo pipefail

# Mit leerer Umgebung neu starten: Der Desktop-Installer läuft als Snap, und dessen Umgebung (LD_LIBRARY_PATH,
# PYTHONPATH, SNAP*) gehört nicht in Werkzeuge des Systems und nicht in den chroot
if [[ "${BASH_SOURCE[0]}" == "$0" && "${ZENOS_EINRICHTEN_SAUBER:-}" != 1 ]]; then
  exec /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 TERM=dumb \
    ZENOS_EINRICHTEN_SAUBER=1 /bin/bash "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
fi

umask 022
export LC_ALL=C.UTF-8
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ZIEL=${1:-}
QUELLE=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)
LOG=/var/log/zenos-einrichten.log
START=$SECONDS

declare -a EINGEHAENGT=()
POLICY=0
RESOLV_ERSETZT=0
RESOLV_LINK=""
RESOLV_SICHERUNG=""
BUNDLE_ZIEL=""
FERTIG=0

schritt() { printf '\n── [%02d:%02d] %s\n' $(( (SECONDS - START) / 60 )) $(( (SECONDS - START) % 60 )) "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
die() {
  printf '\nzenOS: %s\n' "$*" >&2
  exit 1
}

# Befehl im chroot, mit sauberer Umgebung (nichts aus der Umgebung des Installers gelangt hinein)
in_chroot() {
  chroot "$ZIEL" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root LANG=C.UTF-8 TERM=dumb DEBIAN_FRONTEND=noninteractive \
    "$@"
}

aufraeumen() {
  local rc=$? i
  set +e
  if [[ -n "$BUNDLE_ZIEL" ]]; then rm -f -- "$BUNDLE_ZIEL"; fi
  if (( POLICY )); then rm -f -- "$ZIEL/usr/sbin/policy-rc.d"; fi
  if (( RESOLV_ERSETZT )); then
    rm -f -- "$ZIEL/etc/resolv.conf"
    if [[ -n "$RESOLV_LINK" ]]; then
      ln -s -- "$RESOLV_LINK" "$ZIEL/etc/resolv.conf"
    elif [[ -n "$RESOLV_SICHERUNG" ]]; then
      cp -a -- "$RESOLV_SICHERUNG" "$ZIEL/etc/resolv.conf"
    fi
  fi
  # In umgekehrter Reihenfolge aushängen; hängt etwas noch, lazy (der Installer hängt /target danach selbst aus)
  for (( i = ${#EINGEHAENGT[@]} - 1; i >= 0; i-- )); do
    umount -- "${EINGEHAENGT[i]}" 2>/dev/null || umount -l -- "${EINGEHAENGT[i]}" 2>/dev/null
  done
  if [[ -d "$ZIEL/var/log" ]]; then
    install -d -m 0755 "$ZIEL/var/log/zenos"
    install -m 0640 -- "$LOG" "$ZIEL/var/log/zenos/stick.log" 2>/dev/null
  fi
  if (( ! FERTIG )); then
    cat >&2 <<'EOF'

zenOS: Die Einrichtung von zenOS ist gescheitert (Grund oben). Ubuntu ist installiert und startet.
  Protokoll nach dem Neustart: /var/log/zenos/stick.log und /var/log/zenos/install.log
  zenOS von Hand einrichten: ANLEITUNG.md, Abschnitt «x86» (git clone, dann scripts/install.sh).
EOF
  fi
  exit "$rc"
}

# Wert aus zenos/stand (Zeilen «schluessel=wert», nur bekannte Schlüssel)
stand_wert() {
  sed -n "s/^$1=//p" -- "$QUELLE/stand" | head -n 1
}

stand_lesen() {
  [[ -f "$QUELLE/stand" && -f "$QUELLE/zenos.bundle" ]] || die "zenos/stand oder zenos/zenos.bundle fehlt auf dem Stick"
  TAG=$(stand_wert tag)
  COMMIT=$(stand_wert commit)
  KANAL=$(stand_wert kanal)
  VERSION=$(stand_wert version)
  ORIGIN=$(stand_wert origin)
  SIGNIERT=$(stand_wert signiert)
  [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "Commit im Stand ungültig: «$COMMIT»"
  [[ -z "$TAG" || "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$ ]] ||
    die "Tag im Stand ungültig: «$TAG»"
  case "$KANAL" in stabil | vorschau | dev) ;; *) die "Kanal im Stand ungültig: «$KANAL»" ;; esac
  [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+_-]*$ ]] || die "Version im Stand ungültig: «$VERSION»"
  [[ -z "$ORIGIN" || "$ORIGIN" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9._/-]+$ ]] || die "origin im Stand ungültig: «$ORIGIN»"
  case "$SIGNIERT" in 0 | 1) ;; *) die "Wert signiert im Stand ungültig: «$SIGNIERT»" ;; esac
  if [[ "$SIGNIERT" == 1 && -z "$TAG" ]]; then die "Stand signiert, aber ohne Tag"; fi
  info "zenOS $VERSION · Stand ${COMMIT:0:12} · Kanal $KANAL${TAG:+ · Tag $TAG}"
  if [[ "$SIGNIERT" == 1 ]]; then
    info "Tag beim Bau des Sticks gültig signiert (image/tag-pruefen.sh)"
  else
    warn "Testbau ohne gültige Signatur: nicht für den Alltag, ohne Zustand ab Werk"
  fi
}

ziel_pruefen() {
  [[ "$ZIEL" == /* && -d "$ZIEL" ]] || die "Aufruf: einrichten.sh /target"
  ZIEL=$(readlink -f -- "$ZIEL")
  [[ "$ZIEL" != / ]] || die "Ziel ist das laufende System, nicht das neu installierte"
  [[ -f "$ZIEL/etc/os-release" && -x "$ZIEL/usr/bin/env" ]] || die "Unter $ZIEL liegt kein installiertes System"
  [[ ! -e "$ZIEL/opt/zenos" ]] || die "/opt/zenos gibt es im installierten System schon"
}

# tmpfs kommt immer frisch darüber: Läge unter /run schon etwas vom Installer (/run/systemd/system), hielte install.sh
# den Installer für ein laufendes System und startete dort Dienste. /dev, /proc und /sys dürfen schon eingehängt sein.
einhaengen() { # ART QUELLE ZIEL
  local art=$1 von=$2 nach=$ZIEL$3
  if [[ "$art" != tmpfs ]] && mountpoint -q -- "$nach"; then
    info "$3 ist schon eingehängt"
    return 0
  fi
  install -d -m 0755 -- "$nach"
  case "$art" in
    bind) mount --bind -- "$von" "$nach" ;;
    *) mount -t "$art" -o nosuid,nodev -- "$von" "$nach" ;;
  esac
  EINGEHAENGT+=("$nach")
}

chroot_vorbereiten() {
  einhaengen bind /dev /dev
  einhaengen bind /dev/pts /dev/pts
  einhaengen proc proc /proc
  einhaengen sysfs sysfs /sys
  einhaengen tmpfs tmpfs /run
  einhaengen tmpfs tmpfs /tmp
  chmod 1777 -- "$ZIEL/tmp"

  # Namensauflösung wie im Installer; /etc/resolv.conf des Systems zeigt normalerweise nach /run/systemd/resolve/
  local wirt="$ZIEL/run/zenos-resolv.conf" ziel="$ZIEL/etc/resolv.conf" link=""
  if [[ -r /etc/resolv.conf ]]; then cat -- /etc/resolv.conf > "$wirt"; else : > "$wirt"; fi
  install -d -m 0755 -- "$ZIEL/run/systemd/resolve"
  install -m 0644 -- "$wirt" "$ZIEL/run/systemd/resolve/stub-resolv.conf"
  install -m 0644 -- "$wirt" "$ZIEL/run/systemd/resolve/resolv.conf"
  if [[ -L "$ziel" ]]; then link=$(readlink -- "$ziel"); fi
  case "$link" in
    ../run/systemd/resolve/* | /run/systemd/resolve/*) ;;
    *)
      if [[ -n "$link" ]]; then
        RESOLV_LINK=$link
      elif [[ -e "$ziel" ]]; then
        RESOLV_SICHERUNG="$ZIEL/run/zenos-resolv.conf.system"
        cp -a -- "$ziel" "$RESOLV_SICHERUNG"
      fi
      rm -f -- "$ziel"
      install -m 0644 -- "$wirt" "$ziel"
      RESOLV_ERSETZT=1
      ;;
  esac

  if [[ -e "$ZIEL/usr/sbin/policy-rc.d" || -L "$ZIEL/usr/sbin/policy-rc.d" ]]; then
    info "policy-rc.d gibt es schon, sie bleibt"
  else
    printf '#!/bin/sh\n# zenOS-Installer-Stick (image/x86/einrichten.sh): im chroot keine Dienste starten\nexit 101\n' \
      > "$ZIEL/usr/sbin/policy-rc.d"
    chmod 0755 -- "$ZIEL/usr/sbin/policy-rc.d"
    POLICY=1
  fi

  local arch
  arch=$(in_chroot dpkg --print-architecture)
  [[ "$arch" == amd64 ]] || die "Architektur im installierten System ist $arch, der Stick ist für amd64"
  if ! in_chroot test -x /usr/bin/git; then
    info "git fehlt im installierten System, wird installiert"
    in_chroot apt-get -q update
    in_chroot apt-get -q -y install git
  fi
  info "chroot bereit (amd64, Netz über die Namensauflösung des Installers)"
}

code_einrichten() {
  local ref name ziel=/opt/zenos
  BUNDLE_ZIEL="$ZIEL/var/tmp/zenos-stick.bundle"
  install -m 0600 -- "$QUELLE/zenos.bundle" "$BUNDLE_ZIEL"
  in_chroot git -c init.defaultBranch=main clone --quiet --no-checkout /var/tmp/zenos-stick.bundle "$ziel"
  in_chroot git -C "$ziel" cat-file -e "$COMMIT^{commit}" || die "Commit ${COMMIT:0:12} fehlt im Bundle"
  in_chroot git -C "$ziel" -c advice.detachedHead=false checkout --quiet --detach "$COMMIT"
  # Nur der Stand und die Tags, keine Zweige: «zen update» holt den Kanal von origin
  while read -r ref; do
    [[ -n "$ref" ]] || continue
    if [[ "$ref" == refs/heads/* ]]; then
      name=${ref#refs/heads/}
      in_chroot git -C "$ziel" config --remove-section "branch.$name" 2>/dev/null || true
    fi
    in_chroot git -C "$ziel" update-ref --no-deref -d "$ref"
  done < <(in_chroot git -C "$ziel" for-each-ref --format='%(refname)' refs/heads refs/remotes)
  if [[ -n "$ORIGIN" ]]; then
    in_chroot git -C "$ziel" remote set-url origin "$ORIGIN"
  else
    in_chroot git -C "$ziel" remote remove origin
    warn "Ohne origin: «zen update» geht erst nach «git remote add origin …»"
  fi
  in_chroot git -C "$ziel" reflog expire --expire=now --all
  in_chroot git -C "$ziel" gc --quiet --prune=now
  rm -f -- "$BUNDLE_ZIEL"
  BUNDLE_ZIEL=""
  if [[ -n "$TAG" ]]; then
    [[ "$(in_chroot git -C "$ziel" rev-parse --verify --quiet "refs/tags/$TAG^{commit}")" == "$COMMIT" ]] ||
      die "Tag $TAG zeigt im Bundle nicht auf ${COMMIT:0:12}"
  fi
  chown -R 0:0 -- "$ZIEL$ziel"
  chmod 0755 -- "$ZIEL$ziel"
  [[ -z "$(in_chroot git -C "$ziel" status --porcelain)" ]] || die "/opt/zenos ist nach dem Auschecken nicht sauber"
  info "/opt/zenos: $(in_chroot git -C "$ziel" describe --tags --always) (${COMMIT:0:12}), origin ${ORIGIN:-keins}"
}

zenos_installieren() {
  local rc=0
  info "ZENOS_KANAL=$KANAL /opt/zenos/scripts/install.sh --image (mit dem Bau von Quickshell, dauert eine Weile)"
  in_chroot ZENOS_KANAL="$KANAL" /opt/zenos/scripts/install.sh --image || rc=$?
  if [[ -f "$ZIEL/var/log/zenos/install.log" ]]; then
    info "install.log: $(grep '^== Ende' -- "$ZIEL/var/log/zenos/install.log" | tail -n 1 || true)"
  fi
  (( rc == 0 )) || die "install.sh --image ist gescheitert (Exit $rc, Protokoll /var/log/zenos/install.log)"
}

# Ubuntu Desktop bringt gdm3 als Anmeldedienst mit (display-manager.service). install.sh liesse greetd dann aus, damit
# auf einem laufenden System nie still der Login wechselt. Hier, bei einer frischen Installation vom Stick, soll der
# Login von zenOS kommen: Der andere Dienst wird deaktiviert (systemctl disable im chroot entfernt den Verweis), sein
# Paket bleibt installiert. Rückweg: ANLEITUNG H.
anmeldung_vorbereiten() {
  local dm="$ZIEL/etc/systemd/system/display-manager.service" dienst
  if [[ ! -L "$dm" ]]; then
    info "Kein anderer Anmeldedienst eingerichtet"
    return 0
  fi
  dienst=$(basename -- "$(readlink -- "$dm")")
  [[ "$dienst" != greetd.service ]] || return 0
  [[ "$dienst" =~ ^[A-Za-z0-9@._-]+\.service$ ]] || die "display-manager.service zeigt auf «$dienst»"
  in_chroot systemctl disable --quiet "$dienst" || die "$dienst lässt sich nicht deaktivieren"
  if [[ -L "$dm" ]]; then rm -f -- "$dm"; fi
  info "Anmeldedienst $dienst deaktiviert (das Paket bleibt); den Login übernimmt greetd mit zenOS"
}

# Verwaltet NetworkManager das Netz schon (Ubuntu Desktop: netplan mit «renderer: NetworkManager»), entfällt die
# Umstellung beim ersten Start: zenos-netzwerk-erststart ist für netplan mit systemd-networkd gebaut und schaltete
# NetworkManager ab, wenn sie scheitert. Das WLAN-Menü braucht nur einen laufenden NetworkManager.
netz_abschliessen() {
  if grep -rqsE '^[[:space:]]*renderer:[[:space:]]*NetworkManager' -- "$ZIEL/etc/netplan"; then
    rm -f -- "$ZIEL/var/lib/zenos/netzwerk-erststart"
    info "NetworkManager verwaltet das Netz schon: keine Umstellung beim ersten Start"
  elif [[ -e "$ZIEL/var/lib/zenos/netzwerk-erststart" ]]; then
    info "Beim ersten Start stellt zenOS das Netz auf NetworkManager um (zenos-netzwerk-erststart)"
  fi
}

# Wie check_identity und prepare_channel in image/bauen.sh. Die Kennung ist nicht Pflicht (install.sh lässt sie bei
# Ubuntu, wenn die Sicherheitsquelle sonst nicht erlaubt wäre), die Sicherheitsquelle schon.
pruefen() {
  local kanal ausgabe rc=0 programm=/usr/local/libexec/zenos/zenos-kanal
  ausgabe=$(in_chroot /opt/zenos/scripts/bin/zenos-sicherheitsquelle 2>&1) || rc=$?
  (( rc == 0 )) || die "Ubuntu-Sicherheitsquelle nicht nachgewiesen (zenos-sicherheitsquelle Exit $rc): $ausgabe"
  info "Sicherheitsquelle: ${ausgabe%%$'\n'*}"
  info "Kennung: $(sed -n 's/^PRETTY_NAME=//p' -- "$ZIEL/usr/lib/os-release" | tr -d '"')"
  if [[ -f "$ZIEL/etc/default/grub" ]]; then
    [[ -f "$ZIEL/etc/default/grub.d/zenos-distributor.cfg" ]] ||
      die "/etc/default/grub.d/zenos-distributor.cfg fehlt (72-kennung): Der Bootloader bekäme den Namen zenOS"
    info "GRUB behält den Namen Ubuntu"
  fi

  [[ -x "$ZIEL$programm" ]] || die "$programm fehlt (Modul 14-kanal, Protokoll /var/log/zenos/install.log)"
  kanal=$(head -n 1 -- "$ZIEL/etc/xdg/zenos/kanal" 2>/dev/null | tr -d '[:space:]') || kanal=""
  [[ "$kanal" == "$KANAL" ]] || die "Kanal ist «$kanal» statt «$KANAL» (/etc/xdg/zenos/kanal)"
  info "Kanal für zen update: $kanal"
  [[ "$(readlink -- "$ZIEL/etc/systemd/system/display-manager.service" 2>/dev/null)" == */greetd.service ]] ||
    die "greetd ist nicht der Anmeldedienst (display-manager.service): Es käme nicht der Login von zenOS"
  info "Anmeldung: greetd mit dem Login von zenOS"
  if [[ "$SIGNIERT" != 1 ]]; then
    info "Testbau: kein Zustand ab Werk"
    return 0
  fi
  rc=0
  ausgabe=$(in_chroot "$programm" anker --pruefen /etc/zenos/vertrauen 2>&1) || rc=$?
  (( rc == 0 )) || die "Anker /etc/zenos/vertrauen: ${ausgabe:-nicht prüfbar} (Exit $rc)"
  info "Anker: $ausgabe"
  rc=0
  ausgabe=$(in_chroot "$programm" image "$TAG" 2>&1) || rc=$?
  (( rc == 0 )) || die "zenos-kanal image $TAG (Exit $rc): ${ausgabe//$'\n'/; }"
  info "$ausgabe"
}

abschliessen() {
  in_chroot apt-get -q clean
  if [[ -n "$(in_chroot git -C /opt/zenos status --porcelain)" ]]; then warn "/opt/zenos ist nach install.sh nicht mehr sauber"; fi
  FERTIG=1
  schritt "zenOS ist eingerichtet. Nach dem Neustart erscheint der Login von zenOS."
}

main() {
  [[ $EUID -eq 0 ]] || die "einrichten.sh läuft nur als root (im Ubuntu-Installer)"
  : > "$LOG"
  exec > >(tee -a -- "$LOG") 2>&1
  trap aufraeumen EXIT
  schritt "zenOS einrichten"
  ziel_pruefen
  stand_lesen
  schritt "chroot vorbereiten"
  chroot_vorbereiten
  anmeldung_vorbereiten
  schritt "/opt/zenos"
  code_einrichten
  schritt "install.sh --image"
  zenos_installieren
  netz_abschliessen
  schritt "Prüfen"
  pruefen
  abschliessen
}

# Als Skript ausführen; Tests laden es nur (stand_lesen ohne root)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main; fi
