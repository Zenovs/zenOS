#!/usr/bin/env bash
# bauen.sh – baut das Installations-ISO von zenOS für x86-Rechner (amd64): Ubuntu 26.04 als Grundlage, zenOS fertig
# eingerichtet, Calamares als grafischer Installer. Nichts von Ubuntu Desktop, und «Ubuntu» steht nirgends, wo man
# es beim Installieren und im Alltag sieht.
#
#   sudo image/x86/bauen.sh --ref vX.Y.Z[-rcN] [optionen]   (alle Optionen: image/x86/bauen.sh --hilfe)
#
# Läuft als root auf amd64-Linux mit Ubuntu 26.04 (GitHub Actions: im Container ubuntu:26.04, .github/workflows/
# x86.yml und image.yml). Ablauf:
#  1. Stand, Tag und Signatur wie image/bauen.sh (image/tag-pruefen.sh gegen den Anker im Commit des Tags), Kanal und
#     Version aus dem Tag. Ein Testbau (--testbau-ohne-signatur) baut auch einen Zweig; sein ISO endet auf
#     «-testbau», bekommt keinen Zustand ab Werk und ist nie ein Release. Anders als beim Pi-Image geht er auch in
#     GitHub Actions (x86.yml, nur als Artefakt für wenige Tage): Auf dem Pi lässt sich ein amd64-ISO nicht bauen.
#  2. Grundlage: debootstrap aus archive.ubuntu.com (Release-Datei mit dem Archivschlüssel von Ubuntu geprüft), dann
#     ubuntu-server wie auf dem Pi, Kernel linux-generic mit Firmware und Microcode, GRUB und shim (signiert) und die
#     Werkzeuge für Verschlüsselung. Paketquellen wie nach einer Installation von Ubuntu Server (deb822).
#  3. zenOS: /opt/zenos aus dem Stand, «install.sh --image» im chroot, Kennung, Sicherheitsquelle, Kanal und Zustand
#     ab Werk wie im Pi-Image. Für x86 dazu: NetworkManager verwaltet das Netz ab dem ersten Start, Startbild von
#     zenOS (Plymouth), cloud-init aus (Calamares legt Benutzer und Rechnernamen an).
#  4. System-Schicht casper/zenos.squashfs: genau das, was Calamares auf die Platte kopiert.
#  5. Live-Schicht casper/zenos.live.squashfs (overlayfs über dem System, nur ihre Änderungen): casper, Calamares
#     mit Einstellungen und Branding aus image/x86/calamares, die Installer-Sitzung aus image/x86/live (labwc nur mit
#     Calamares), alles, was im Live-System ins Netz ginge, maskiert. Dazu das initrd mit casper und Startbild.
#  6. ISO: shim und GRUB von Ubuntu (signiert) für UEFI mit Secure Boot, Startmenü «zenOS installieren», angehängte
#     EFI-Partition (GPT, startet als USB-Stick und als DVD), Datenträgername zenOS. Nur UEFI, kein BIOS.
# Ergebnis in <ausgabe>: zenos-<version>-x86-amd64.iso, zenos-<version>-x86-amd64.pakete.txt und SHA256SUMS.
# Doku: docs/image-und-releases.md, Abschnitt «Bürorechner (x86)», und image/README.md.

set -Eeuo pipefail
umask 022
export LC_ALL=C.UTF-8
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# «&» in Ersetzungen ${x//a/b} wörtlich nehmen (bash 5.2 setzt dort sonst den Treffer ein): Texte der Folien
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
X86_DIR=$(dirname -- "$SCRIPT")
REPO_DIR=$(cd -- "$X86_DIR/../.." && pwd -P)

readonly ARCHIV=http://archive.ubuntu.com/ubuntu/
readonly SICHERHEIT=http://security.ubuntu.com/ubuntu/
readonly ARCHIV_SCHLUESSEL=/usr/share/keyrings/ubuntu-archive-keyring.gpg
# Release-Tags wie in zenos-kanal (VERSION_RE), image/tag-pruefen.sh und image/bauen.sh
readonly VERSION_ERE='^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(-rc[1-9][0-9]{0,8})?$'

# Grundlage wie Ubuntu Server auf dem Pi, dazu, was ein PC zum Starten und Entschlüsseln braucht. Kein Desktop.
readonly SYSTEM_PAKETE=(
  ubuntu-minimal ubuntu-standard ubuntu-server
  linux-generic linux-firmware intel-microcode amd64-microcode
  grub-efi-amd64 grub-efi-amd64-signed shim-signed efibootmgr mokutil
  cryptsetup dosfstools e2fsprogs
  plymouth plymouth-label
  locales keyboard-configuration console-setup
  network-manager sudo openssh-server
)
# Nur in der Live-Schicht: Start von USB/DVD (casper, initramfs-tools) und der Installer
readonly LIVE_PAKETE=(casper calamares rsync squashfs-tools)
# Im Live-System nie starten: Login, SSH, Netz, Zeitabgleich, Prüfung des Datenträgers, Zufall vom Netz
readonly LIVE_MASKIERT=(
  greetd.service ssh.service ssh.socket NetworkManager.service NetworkManager-wait-online.service
  systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service wpa_supplicant.service
  systemd-timesyncd.service casper-md5check.service pollinate.service snapd.service snapd.socket
  unattended-upgrades.service
)

usage() {
  cat <<'EOF'
Aufruf: sudo image/x86/bauen.sh --ref vX.Y.Z[-rcN] [optionen]

  --ref REF          Git-Stand für /opt/zenos: ein Release-Tag vX.Y.Z oder vX.Y.Z-rcN, gültig signiert
                     (Standard: HEAD, das geht nur im Testbau)
  --version V        Version im Dateinamen (Standard: der Tag ohne «v»; im Testbau ohne Tag git describe)
  --quelle ORDNER    Git-Repo mit zenOS (Standard: das Repo dieses Skripts)
  --origin URL       origin von /opt/zenos für «zen update», nur https (Standard: origin der Quelle)
  --kanal K          Kanal für «zen update»: stabil, vorschau oder dev (Standard: aus dem Tag; ohne Tag dev).
                     Ein anderer als der des Tags nur im Testbau
  --serie NAME       Ubuntu-Serie für debootstrap (Standard: resolute, Ubuntu 26.04)
  --arbeit ORDNER    Arbeitsordner (Standard: /var/tmp/zenos-x86)
  --ausgabe ORDNER   Ziel für ISO, Paketliste und SHA256SUMS (Standard: <arbeit>/ausgabe)
  --testbau-ohne-signatur
                     Testbau: Stand ohne gültig signierten Tag (Zweig, Commit) und ein anderer Kanal sind erlaubt;
                     die Version endet auf «-testbau», ohne Zustand ab Werk, nie ein Release
  --nur-pruefen      nur Stand, Tag, Signatur, Kanal und Version prüfen und zeigen (ohne root, baut nichts)
  -h, --hilfe        diese Hilfe
EOF
}

# --- Optionen --------------------------------------------------------------

ORIG_ARGS=("$@")
opt_ref=HEAD
opt_version=""
opt_source=$REPO_DIR
opt_origin=""
opt_channel=""
opt_series=resolute
opt_work=/var/tmp/zenos-x86
opt_output=""
opt_unsigned_test=0
opt_check_only=0

while (( $# > 0 )); do
  case "$1" in
    -h | --hilfe | --help) usage; exit 0 ;;
    --testbau-ohne-signatur) opt_unsigned_test=1; shift; continue ;;
    --nur-pruefen) opt_check_only=1; shift; continue ;;
    --ref | --version | --quelle | --origin | --kanal | --serie | --arbeit | --ausgabe)
      if (( $# < 2 )); then
        printf 'bauen.sh: %s braucht einen Wert\n' "$1" >&2
        exit 2
      fi
      ;;
    *) printf 'bauen.sh: unbekannte Option «%s»\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  case "$1" in
    --ref) opt_ref=$2 ;;
    --version) opt_version=$2 ;;
    --quelle) opt_source=$2 ;;
    --origin) opt_origin=$2 ;;
    --kanal) opt_channel=$2 ;;
    --serie) opt_series=$2 ;;
    --arbeit) opt_work=$2 ;;
    --ausgabe) opt_output=$2 ;;
  esac
  shift 2
done

# Eigener, privater Mount-Namensraum wie in image/bauen.sh: Die Einhängepunkte bleiben für den Host unsichtbar und
# verschwinden spätestens mit dem Ende des Skripts.
if (( EUID == 0 && ! opt_check_only )) && [[ "${ZENOS_BAU_NAMENSRAUM:-}" != 1 ]] && command -v unshare >/dev/null; then
  export ZENOS_BAU_NAMENSRAUM=1
  exec unshare --mount --propagation private -- bash "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}"
fi

# --- Ausgabe und Fehler ----------------------------------------------------

START=$SECONDS
WARNINGS=0

elapsed() { printf '%02d:%02d' $(( (SECONDS - START) / 60 )) $(( (SECONDS - START) % 60 )); }
step() { printf '\n── [%s] %s\n' "$(elapsed)" "$*"; }
info() { printf '   %s\n' "$*"; }
warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '   ! Warnung: %s\n' "$*" >&2
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then printf '::warning::%s\n' "$*"; fi
}
die() {
  printf '   ✗ Fehler: %s\n' "$*" >&2
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then printf '::error::%s\n' "$*"; fi
  exit 1
}

on_error() {
  local rc=$?
  printf '   ✗ Befehl fehlgeschlagen (Exit %s) · bauen.sh:%s: %s\n' "$rc" "$1" "$2" >&2
  return "$rc"
}

# Zustand für das Aufräumen
TMP_DIR=""
GIT_CONFIG_FILE=""
WORK=""
SYSTEM=""
LIVE=""
LOG_SAVED=0
DONE=0
TAG=""
SIGNED=0
SEED=0
TEST_BUILD=0
SIG_KEY=""
SIG_SERIES=""
SIG_ROOT=""
KVER=""

cleanup() {
  local rc=$?
  set +e
  trap - ERR
  exec 1>&7 2>&8
  if (( ! DONE && opt_check_only )); then
    printf '\nVorprüfung gescheitert (Exit %s). Kein ISO.\n' "$rc" >&2
  elif (( ! DONE )); then
    printf '\nISO-Bau abgebrochen (Exit %s). Räume Einhängepunkte auf.\n' "$rc" >&2
    save_install_log
  fi
  if [[ -n "$LIVE" ]]; then unmount_below "$LIVE"; fi
  if [[ -n "$SYSTEM" ]]; then unmount_below "$SYSTEM"; fi
  if [[ -n "$TMP_DIR" ]]; then rm -rf -- "$TMP_DIR"; fi
  if [[ -n "$GIT_CONFIG_FILE" ]]; then rm -f -- "$GIT_CONFIG_FILE"; fi
  exit "$rc"
}

# --- Hilfen ----------------------------------------------------------------

# Führt einen Befehl still aus; bei einem Fehler erscheint seine Ausgabe.
quiet() {
  local log="$TMP_DIR/befehl.log" rc=0
  "$@" >"$log" 2>&1 || rc=$?
  if (( rc != 0 )); then
    tail -n 60 -- "$log" | sed 's/^/     /' >&2
    die "$1 fehlgeschlagen (Exit $rc)"
  fi
}

mib() { printf '%s MiB' $(( $1 / 1048576 )); }

# Befehl im chroot ROOT, mit sauberer Umgebung (nichts vom Host oder aus der CI gelangt hinein). Führende
# NAME=WERT-Argumente setzt env im chroot.
in_root() {
  local root=$1
  shift
  chroot "$root" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root LANG=C.UTF-8 TERM=dumb DEBIAN_FRONTEND=noninteractive \
    "$@"
}

apt_in() { # ROOT apt-get-Argumente …
  local root=$1
  shift
  in_root "$root" apt-get -q -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    -o APT::Install-Recommends=true "$@"
}

git_source() { git -C "$opt_source" "$@"; }

# Zugangsdaten aus der URL entfernen, GitHub-SSH als HTTPS (wie image/bauen.sh)
clean_url() {
  local url=$1
  if [[ "$url" =~ ^git@github\.com:(.+)$ ]]; then
    url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^ssh://git@github\.com/(.+)$ ]]; then
    url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^(https?://)[^/@]*@(.+)$ ]]; then
    url="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
  printf '%s' "$url"
}

# --- Einhängen -------------------------------------------------------------

# Prozesse, die im chroot ROOT weiterlaufen (z. B. gpg-agent), halten sonst die Einhängepunkte fest
stop_root_processes() {
  local root_real proc link pid names="" try
  local -a pids=() alive
  [[ -d "$1" ]] || return 0
  root_real=$(readlink -f -- "$1")
  for proc in /proc/[0-9]*; do
    link=$(readlink -- "$proc/root" 2>/dev/null) || continue
    if [[ "$link" == "$root_real" || "$link" == "$root_real"/* ]]; then pids+=("${proc#/proc/}"); fi
  done
  (( ${#pids[@]} > 0 )) || return 0
  for pid in "${pids[@]}"; do names+=" $(cat -- "/proc/$pid/comm" 2>/dev/null || true)[$pid]"; done
  warn "Prozesse im chroot werden beendet:$names"
  kill -TERM "${pids[@]}" 2>/dev/null || true
  for try in 1 2 3 4 5; do
    alive=()
    for pid in "${pids[@]}"; do
      if [[ -d "/proc/$pid" ]]; then alive+=("$pid"); fi
    done
    (( ${#alive[@]} > 0 )) || return 0
    sleep "$try"
  done
  kill -KILL "${alive[@]}" 2>/dev/null || true
}

# Alles unter ROOT aushängen (tiefste zuerst), auch ROOT selbst, wenn es ein Einhängepunkt ist
unmount_below() {
  local root=$1 target try
  local -a targets=()
  [[ -d "$root" ]] || return 0
  stop_root_processes "$root"
  mapfile -t targets < <(findmnt -rn -o TARGET | awk -v p="$root" '$0 == p || index($0, p "/") == 1' | LC_ALL=C sort -r)
  for target in "${targets[@]}"; do
    for try in 1 2 3; do
      umount -- "$target" 2>/dev/null && continue 2
      sleep "$try"
    done
    warn "$target ist belegt, nur verzögert ausgehängt"
    umount -l -- "$target" || warn "$target liess sich nicht aushängen"
  done
}

# chroot vorbereiten: /proc, /sys, /dev vom Host, /run und /tmp frisch (ohne /run/systemd/system gilt systemd im
# chroot als nicht laufend), /var/tmp im Arbeitsordner (Quickshell-Bau, etwa 3,5 GB), Namensauflösung des Hosts,
# policy-rc.d gegen Dienststarts
mount_root() {
  local root=$1
  mount -t proc -o nosuid,nodev,noexec proc "$root/proc"
  mount --rbind /sys "$root/sys"
  mount --make-rslave "$root/sys"
  mount --rbind /dev "$root/dev"
  mount --make-rslave "$root/dev"
  mount -t tmpfs -o nosuid,nodev,mode=0755 tmpfs "$root/run"
  install -d -m 1777 "$root/run/lock"
  mount -t tmpfs -o nosuid,nodev,mode=1777 tmpfs "$root/tmp"
  install -d -m 1777 "$WORK/vartmp"
  mount --bind "$WORK/vartmp" "$root/var/tmp"

  local host="$TMP_DIR/resolv.conf"
  if [[ -r /etc/resolv.conf ]]; then cat -- /etc/resolv.conf > "$host"; else : > "$host"; fi
  install -d -m 0755 "$root/run/systemd/resolve"
  install -m 0644 "$host" "$root/run/systemd/resolve/stub-resolv.conf"
  install -m 0644 "$host" "$root/run/systemd/resolve/resolv.conf"
  # Vor systemd-resolved (debootstrap) ist /etc/resolv.conf eine Datei: dann die des Hosts
  if [[ ! -L "$root/etc/resolv.conf" ]]; then install -m 0644 "$host" "$root/etc/resolv.conf"; fi

  if [[ ! -e "$root/usr/sbin/policy-rc.d" ]]; then
    printf '#!/bin/sh\n# zenOS-ISO-Bau (image/x86/bauen.sh): im chroot keine Dienste starten\nexit 101\n' \
      > "$root/usr/sbin/policy-rc.d"
    chmod 0755 "$root/usr/sbin/policy-rc.d"
  fi
}

umount_root() {
  local root=$1
  rm -f -- "$root/usr/sbin/policy-rc.d"
  unmount_below "$root/proc"
  unmount_below "$root/sys"
  unmount_below "$root/dev"
  unmount_below "$root/run"
  unmount_below "$root/tmp"
  unmount_below "$root/var/tmp"
}

save_install_log() {
  (( ! LOG_SAVED )) || return 0
  [[ -n "$SYSTEM" && -f "$SYSTEM/var/log/zenos/install.log" && -n "$WORK" ]] || return 0
  install -m 0644 -- "$SYSTEM/var/log/zenos/install.log" "$WORK/install.log" 2>/dev/null && LOG_SAVED=1
  return 0
}

# --- Stand, Tag und Signatur (wie image/bauen.sh) --------------------------

release_tag() {
  local name=${1#refs/tags/}
  if [[ "$name" =~ $VERSION_ERE ]] && git_source rev-parse --verify --quiet "refs/tags/$name" >/dev/null 2>&1; then
    printf '%s' "$name"
  fi
}

check_signature() {
  local output key value rc=0
  SIGNED=0
  if [[ -z "$TAG" ]]; then
    (( TEST_BUILD )) || die "«$opt_ref» ist kein Release-Tag vX.Y.Z oder vX.Y.Z-rcN in $opt_source. Gebaut wird nur ein gültig signierter Tag (Testbau: --testbau-ohne-signatur)"
    warn "Testbau: «$opt_ref» ist kein Release-Tag, die Signatur wird nicht geprüft"
    return 0
  fi
  output=$("$REPO_DIR/image/tag-pruefen.sh" --quelle "$opt_source" --commit "$COMMIT" "$TAG") || rc=$?
  if (( rc != 0 )); then
    (( TEST_BUILD )) || die "Der Tag $TAG ist nicht gültig signiert (image/tag-pruefen.sh, Exit $rc, Grund oben). Kein ISO."
    warn "Testbau: Der Tag $TAG ist nicht gültig signiert (Exit $rc, Grund oben)"
    return 0
  fi
  while IFS='=' read -r key value; do
    case "$key" in
      schluessel) SIG_KEY=$value ;;
      serie) SIG_SERIES=$value ;;
      wurzel) SIG_ROOT=$value ;;
    esac
  done <<< "$output"
  [[ "$SIG_KEY" == SHA256:* && "$SIG_SERIES" =~ ^[1-9][0-9]{0,3}$ ]] || die "image/tag-pruefen.sh: unerwartete Ausgabe"
  SIGNED=1
}

resolve_source() {
  local derived
  if (( opt_unsigned_test )); then TEST_BUILD=1; fi
  command -v git >/dev/null || die "git fehlt"
  opt_source=$(realpath -e -- "$opt_source") || die "Quelle «$opt_source» gibt es nicht"
  GIT_CONFIG_FILE=$(mktemp)
  git config --file "$GIT_CONFIG_FILE" --add safe.directory "$opt_source"
  git config --file "$GIT_CONFIG_FILE" --add safe.directory "$opt_source/.git"
  git config --file "$GIT_CONFIG_FILE" uploadpack.allowAnySHA1InWant true
  export GIT_CONFIG_GLOBAL=$GIT_CONFIG_FILE GIT_CONFIG_NOSYSTEM=1
  git_source rev-parse --git-dir >/dev/null 2>&1 || die "$opt_source ist kein Git-Repo"
  COMMIT=$(git_source rev-parse --verify --quiet "$opt_ref^{commit}") || die "Stand «$opt_ref» gibt es in $opt_source nicht"

  TAG=$(release_tag "$opt_ref")
  check_signature

  # Kanal: folgt dem Tag (wie das Pi-Image: vX.Y.Z → stabil, -rcN → vorschau, dev nie automatisch)
  derived=dev
  if [[ -n "$TAG" ]]; then
    derived=stabil
    if [[ "$TAG" == *-rc* ]]; then derived=vorschau; fi
  fi
  if [[ -z "$opt_channel" ]]; then
    opt_channel=$derived
  elif [[ "$opt_channel" != "$derived" ]] && (( ! TEST_BUILD )); then
    die "Kanal «$opt_channel» passt nicht zu $TAG: Das ISO folgt dem Kanal des Tags ($derived)"
  fi
  case "$opt_channel" in
    stabil | vorschau | dev) ;;
    *) die "Ungültiger Kanal «$opt_channel» (erlaubt: stabil, vorschau, dev)" ;;
  esac
  if (( SIGNED )) && [[ "$opt_channel" == "$derived" ]]; then SEED=1; fi

  if [[ -n "$TAG" ]]; then
    if [[ -n "$opt_version" && "$opt_version" != "${TAG#v}" ]] && (( ! TEST_BUILD )); then
      die "--version $opt_version passt nicht zum Tag $TAG"
    fi
    opt_version=${opt_version:-${TAG#v}}
  elif [[ -z "$opt_version" ]]; then
    opt_version=$(git_source describe --tags --always "$COMMIT")
    opt_version=${opt_version#v}
  fi
  VERSION=$opt_version
  if (( opt_unsigned_test )); then VERSION+=-testbau; fi
  [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+_-]*$ ]] || die "Ungültige Version «$VERSION»"

  if [[ -n "$opt_origin" ]]; then
    ORIGIN_URL=$opt_origin
  else
    ORIGIN_URL=$(clean_url "$(git_source remote get-url origin 2>/dev/null || true)")
  fi
  if [[ -n "$ORIGIN_URL" && ! "$ORIGIN_URL" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9._/-]+$ ]]; then
    die "origin «$ORIGIN_URL» ist keine https-Adresse ohne Zugangsdaten (--origin)"
  fi

  info "zenOS $VERSION · Stand ${COMMIT:0:12} aus $opt_source · Kanal $opt_channel"
  if (( SIGNED )); then
    info "Tag $TAG gültig signiert: Release-Schlüssel $SIG_KEY, Anker Serie $SIG_SERIES, Wurzel $SIG_ROOT"
  else
    info "Testbau ohne gültige Signatur: nicht für Releases, ohne Zustand ab Werk"
  fi
}

preflight() {
  local tool missing="" avail_mib p
  (( EUID == 0 )) || die "bauen.sh braucht root (sudo image/x86/bauen.sh …)"
  for tool in debootstrap mksquashfs xorriso mkfs.vfat mmd mcopy git ssh-keygen chroot unshare findmnt mount \
    umount python3 sha256sum awk flock; do
    command -v "$tool" >/dev/null || missing+=" $tool"
  done
  if [[ -n "$missing" ]]; then
    die "Es fehlen:$missing (Ubuntu: apt-get install debootstrap squashfs-tools xorriso dosfstools mtools git openssh-client python3)"
  fi
  [[ -r "$ARCHIV_SCHLUESSEL" ]] || die "$ARCHIV_SCHLUESSEL fehlt (Paket ubuntu-keyring)"
  [[ "$(uname -m)" == x86_64 ]] || die "Host ist $(uname -m). Gebaut wird auf amd64 (x86_64)."
  [[ "$opt_series" =~ ^[a-z]+$ ]] || die "Ungültige Serie «$opt_series»"
  grep -qw overlay /proc/filesystems || modprobe overlay 2>/dev/null || true
  grep -qw overlay /proc/filesystems || die "Der Kernel kann kein overlayfs (für die Live-Schicht)"

  WORK=$(realpath -m -- "$opt_work")
  OUTPUT=$(realpath -m -- "${opt_output:-$WORK/ausgabe}")
  for p in "$WORK" "$OUTPUT"; do
    [[ "$p" =~ ^/[A-Za-z0-9._/+-]+$ && "$p" != / ]] || die "Ungültiger Ordner «$p» (nur A–Z, a–z, 0–9 und ._/+-)"
  done
  mkdir -p -- "$WORK"
  exec 9>"$WORK/.sperre"
  flock -n 9 || die "In $WORK läuft schon ein ISO-Bau"
  avail_mib=$(( $(df -Pk -- "$WORK" | awk 'NR == 2 { print $4 }') / 1024 ))
  if (( avail_mib < 30720 )); then
    warn "In $WORK sind nur $avail_mib MiB frei, gebraucht werden etwa 30 GiB"
  fi
  info "Arbeitsordner $WORK ($avail_mib MiB frei) · Ausgabe $OUTPUT"
}

# Reste eines abgebrochenen Laufs im selben Arbeitsordner wegräumen
clean_work() {
  SYSTEM="$WORK/system"
  LIVE="$WORK/live"
  unmount_below "$LIVE"
  unmount_below "$SYSTEM"
  rm -rf -- "$SYSTEM" "$LIVE" "$WORK/live-oben" "$WORK/live-arbeit" "$WORK/iso" "$WORK/vartmp" "$WORK"/tmp.* \
    "$WORK/efi.img" "$WORK/install.log" "$WORK/pakete.txt"
  mkdir -p -- "$SYSTEM" "$WORK/iso"
  TMP_DIR=$(mktemp -d "$WORK/tmp.XXXXXX")
}

# --- Grundlage -------------------------------------------------------------

write_sources() {
  local root=$1
  rm -f -- "$root/etc/apt/sources.list"
  cat > "$root/etc/apt/sources.list.d/ubuntu.sources" <<EOF
## Ubuntu distribution repository (wie nach einer Installation von Ubuntu Server)
Types: deb
URIs: $ARCHIV
Suites: $opt_series $opt_series-updates $opt_series-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

## Ubuntu security updates
Types: deb
URIs: $SICHERHEIT
Suites: $opt_series-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

build_base() {
  info "debootstrap $opt_series aus $ARCHIV (amd64)"
  quiet debootstrap --arch=amd64 --components=main,restricted,universe,multiverse \
    --keyring="$ARCHIV_SCHLUESSEL" "$opt_series" "$SYSTEM" "$ARCHIV"
  grep -qx 'ID=ubuntu' -- "$SYSTEM/usr/lib/os-release" || die "Die Grundlage sieht nicht nach Ubuntu aus"
  info "$(sed -n 's/^PRETTY_NAME=//p' -- "$SYSTEM/usr/lib/os-release" | tr -d '"')"
  mount_root "$SYSTEM"
  write_sources "$SYSTEM"
  quiet apt_in "$SYSTEM" update
  quiet apt_in "$SYSTEM" full-upgrade
  info "Pakete: ${SYSTEM_PAKETE[*]}"
  quiet apt_in "$SYSTEM" install "${SYSTEM_PAKETE[@]}"
  local -a kernels=()
  mapfile -t kernels < <(find "$SYSTEM/boot" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' | sed 's/^vmlinuz-//' | sort -V)
  (( ${#kernels[@]} == 1 )) || die "Erwartet genau einen Kernel in /boot, gefunden: ${kernels[*]:-keinen}"
  KVER=${kernels[0]}
  info "Kernel $KVER, $(in_root "$SYSTEM" dpkg-query -W -f='${Version}' shim-signed 2>/dev/null | sed 's/^/shim-signed /')"
}

# --- zenOS (wie image/bauen.sh) --------------------------------------------

prepare_code() {
  local dest="$SYSTEM/opt/zenos" ref name
  local -a git_dest=(git -C "$dest")
  [[ ! -e "$dest" ]] || die "/opt/zenos gibt es in der Grundlage schon"
  install -d -m 0755 "$SYSTEM/opt"
  git clone --quiet --no-local --no-checkout -- "$opt_source" "$dest"
  if ! "${git_dest[@]}" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
    "${git_dest[@]}" fetch --quiet --no-tags -- "$opt_source" "$COMMIT"
  fi
  "${git_dest[@]}" -c advice.detachedHead=false checkout --quiet --detach "$COMMIT"
  while read -r ref; do
    [[ -n "$ref" ]] || continue
    if [[ "$ref" == refs/heads/* ]]; then
      name=${ref#refs/heads/}
      "${git_dest[@]}" config --remove-section "branch.$name" 2>/dev/null || true
    fi
    "${git_dest[@]}" update-ref --no-deref -d "$ref"
  done < <("${git_dest[@]}" for-each-ref --format='%(refname)' refs/heads refs/remotes)
  if [[ -n "$ORIGIN_URL" ]]; then
    "${git_dest[@]}" remote set-url origin "$ORIGIN_URL"
  else
    "${git_dest[@]}" remote remove origin
    warn "Ohne origin: «zen update» geht erst nach «git remote add origin …»"
  fi
  "${git_dest[@]}" reflog expire --expire=now --all
  "${git_dest[@]}" gc --quiet --prune=now
  local -a meta=("$dest/.git/config")
  for name in logs FETCH_HEAD ORIG_HEAD packed-refs; do
    if [[ -e "$dest/.git/$name" ]]; then meta+=("$dest/.git/$name"); fi
  done
  if grep -rlF -- "$opt_source" "${meta[@]}" >/dev/null 2>&1; then
    die "Der Pfad der Quelle steht noch in /opt/zenos/.git"
  fi
  chown -R 0:0 -- "$dest"
  chmod 0755 -- "$dest"
  [[ -z "$("${git_dest[@]}" status --porcelain)" ]] || die "/opt/zenos ist nach dem Auschecken nicht sauber"
  info "/opt/zenos: $("${git_dest[@]}" describe --tags --always) (${COMMIT:0:12}), origin ${ORIGIN_URL:-keins}"
}

run_install() {
  local rc=0 end_line
  info "ZENOS_KANAL=$opt_channel /opt/zenos/scripts/install.sh --image"
  in_root "$SYSTEM" ZENOS_KANAL="$opt_channel" /opt/zenos/scripts/install.sh --image || rc=$?
  save_install_log
  if [[ -f "$WORK/install.log" ]]; then
    end_line=$(grep '^== Ende' -- "$WORK/install.log" | tail -n 1 || true)
    if [[ -n "$end_line" ]]; then info "install.log: $end_line"; fi
  fi
  (( rc == 0 )) || die "install.sh --image ist im chroot fehlgeschlagen (Exit $rc)"
}

# Kennung zenOS und Sicherheitsquelle (wie check_identity in image/bauen.sh). Kein ISO ohne nachgewiesene
# Ubuntu-Sicherheitsupdates.
check_identity() {
  local r=$SYSTEM os_file="$SYSTEM/usr/lib/os-release" ubuntu_file="$SYSTEM/usr/lib/os-release.ubuntu"
  local target codename lsb pretty output rc=0
  target=$(in_root "$r" dpkg-divert --truename /usr/lib/os-release)
  [[ "$target" == /usr/lib/os-release.ubuntu ]] || die "Umlenkung von /usr/lib/os-release fehlt (72-kennung, Install-Log)"
  [[ -f "$ubuntu_file" ]] || die "/usr/lib/os-release.ubuntu fehlt"
  grep -qx 'ID=zenos' -- "$os_file" || die "/usr/lib/os-release meldet nicht ID=zenos"
  codename=$(sed -n 's/^VERSION_CODENAME=//p' -- "$ubuntu_file" | tr -d '"')
  lsb=$(in_root "$r" lsb_release -cs 2>/dev/null) || true
  [[ -n "$codename" && "$lsb" == "$codename" ]] || die "lsb_release -cs meldet «$lsb» statt des Ubuntu-Codenamens «$codename»"
  pretty=$(sed -n 's/^PRETTY_NAME=//p' -- "$os_file" | tr -d '"')
  [[ -n "$pretty" && "$pretty" != *[Uu]buntu* ]] || die "PRETTY_NAME «$pretty» ist leer oder nennt Ubuntu"
  output=$(in_root "$r" /opt/zenos/scripts/bin/zenos-sicherheitsquelle 2>&1) || rc=$?
  (( rc == 0 )) || die "Ubuntu-Sicherheitsquelle nicht nachgewiesen (zenos-sicherheitsquelle Exit $rc): $output"
  rc=0
  output=$(in_root "$r" /usr/local/sbin/zenos-kennung pruefen 2>&1) || rc=$?
  (( rc == 0 )) || die "zenos-kennung pruefen (Exit $rc): ${output//$'\n'/; }"
  [[ -f "$r/etc/default/grub.d/zenos-distributor.cfg" ]] ||
    die "/etc/default/grub.d/zenos-distributor.cfg fehlt (72-kennung): GRUB fände EFI/ubuntu nicht wieder"
  info "Kennung: $pretty · Basis $(sed -n 's/^PRETTY_NAME=//p' -- "$ubuntu_file" | tr -d '"') · Codename $lsb"
}

# Kanal, Vertrauensanker und Zustand ab Werk (wie prepare_channel in image/bauen.sh)
prepare_channel() {
  local r=$SYSTEM name channel output rc=0
  local program=/usr/local/libexec/zenos/zenos-kanal
  [[ -x "$r$program" ]] || die "$program fehlt (Modul 14-kanal, Install-Log)"
  channel=$(head -n 1 -- "$r/etc/xdg/zenos/kanal" 2>/dev/null | tr -d '[:space:]') || channel=""
  [[ "$channel" == "$opt_channel" ]] || die "Kanal ist «$channel» statt «$opt_channel» (/etc/xdg/zenos/kanal)"
  info "Kanal für zen update: $channel"
  output=$(in_root "$r" "$program" anker --pruefen /etc/zenos/vertrauen 2>&1) || rc=$?
  if (( ! SIGNED )); then
    info "Anker: ${output:-?}"
    info "Testbau ohne gültige Signatur: kein Zustand ab Werk"
    return 0
  fi
  (( rc == 0 )) || die "Anker /etc/zenos/vertrauen: ${output:-nicht prüfbar} (Exit $rc)"
  for name in release wurzel widerrufen serie; do
    cmp -s -- "$r/opt/zenos/system/vertrauen/$name" "$r/etc/zenos/vertrauen/$name" ||
      die "/etc/zenos/vertrauen/$name ist nicht system/vertrauen/$name des Stands"
  done
  info "Anker: $output"
  if (( ! SEED )); then
    info "Testbau mit anderem Kanal als dem des Tags: kein Zustand ab Werk"
    return 0
  fi
  rc=0
  output=$(in_root "$r" "$program" image "$TAG" 2>&1) || rc=$?
  (( rc == 0 )) || die "zenos-kanal image $TAG (Exit $rc): ${output//$'\n'/; }"
  info "$output"
}

# Was ein PC anders braucht als das Pi-Image
prepare_x86() {
  local r=$SYSTEM theme=/usr/share/plymouth/themes/zenos/zenos.plymouth

  # Netz: NetworkManager verwaltet alles ab dem ersten Start (WLAN-Menü). Die Umstellung beim ersten Start
  # (zenos-netzwerk-erststart) ist für netplan mit systemd-networkd aus cloud-init gebaut und entfällt.
  install -d -m 0755 "$r/etc/netplan"
  printf '%s\n' '# zenOS (Installations-ISO für x86): NetworkManager verwaltet alle Netzwerkgeräte' \
    'network:' '  version: 2' '  renderer: NetworkManager' > "$r/etc/netplan/01-zenos-networkmanager.yaml"
  chmod 0600 "$r/etc/netplan/01-zenos-networkmanager.yaml"
  rm -f -- "$r/var/lib/zenos/netzwerk-erststart"
  info "Netz: NetworkManager ab dem ersten Start"

  # Benutzer und Rechnername legt Calamares an, nicht cloud-init
  if [[ -d "$r/etc/cloud" ]]; then
    : > "$r/etc/cloud/cloud-init.disabled"
    info "cloud-init aus (/etc/cloud/cloud-init.disabled)"
  fi

  # Startbild von zenOS: beim Start, beim Entschlüsseln und beim Ausschalten (Calamares setzt «splash»)
  [[ -f "$r$theme" ]] || die "Startbild fehlt ($theme, Modul 42-bootsplash)"
  quiet in_root "$r" update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$theme" 100
  quiet in_root "$r" update-alternatives --set default.plymouth "$theme"
  info "Startbild: $(in_root "$r" update-alternatives --query default.plymouth | sed -n 's/^Value: //p')"

  # Der Rechnername kommt aus dem Installer; bis dahin keiner aus dem Bau
  rm -f -- "$r/etc/hostname"
}

# Paketliste: je Zeile Paket, Version, Quellpaket, Quellversion (Tab), wie im Pi-Image
write_package_list() {
  local file="$WORK/pakete.txt" count
  # shellcheck disable=SC2016 # ${…} ist das Format von dpkg-query, keine Shell-Variable
  in_root "$SYSTEM" dpkg-query -W \
    -f='${db:Status-Status}\t${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n' |
    awk -F '\t' -v OFS='\t' '$1 == "installed" { print $2, $3, $4, $5 }' | LC_ALL=C sort > "$file.teil"
  mv -- "$file.teil" "$file"
  count=$(wc -l < "$file")
  (( count > 100 )) || die "Paketliste mit nur $count Einträgen"
  install -D -m 0644 -o root -g root -- "$file" "$SYSTEM/usr/local/share/doc/zenos/pakete.txt"
  info "Paketliste: $count Pakete aus $(cut -f 3 -- "$file" | sort -u | wc -l) Quellpaketen"
  # Was nicht drin sein darf: Desktop von Ubuntu und Telemetrie
  local bad
  bad=$(cut -f 1 -- "$file" | sed 's/:.*//' | grep -xE 'ubuntu-desktop(-minimal)?|gnome-shell|gdm3|whoopsie|ubuntu-report|ubuntu-insights|popularity-contest|apport-gtk|snap-store' || true)
  [[ -z "$bad" ]] || die "Im System sind Pakete, die nicht hineingehören: ${bad//$'\n'/ }"
}

# Aufräumen vor dem Packen: wie clean_image in image/bauen.sh
clean_root() {
  local r=$1
  in_root "$r" apt-get clean
  rm -rf -- "$r"/var/lib/apt/lists/*
  install -d -m 0755 "$r/var/lib/apt/lists/partial"
  stop_root_processes "$r"
  if [[ -d "$r/etc/ssh" ]]; then
    find "$r/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete
  fi
  if [[ -e "$r/etc/machine-id" ]]; then : > "$r/etc/machine-id"; fi
  if [[ -f "$r/var/lib/dbus/machine-id" && ! -L "$r/var/lib/dbus/machine-id" ]]; then
    rm -f -- "$r/var/lib/dbus/machine-id"
  fi
  rm -f -- "$r/var/lib/systemd/random-seed" "$r/var/lib/systemd/credential.secret"
  rm -f -- "$r/var/log/zenos/install.log"
  find "$r/var/log" -type f \( -name '*.gz' -o -name '*.xz' -o -name '*.zst' -o -name '*.[0-9]' -o -name '*.old' \) -delete
  find "$r/var/log" -type f -size +0 -exec truncate -s 0 {} +
  if [[ -d "$r/var/log/journal" ]]; then find "$r/var/log/journal" -mindepth 1 -delete; fi
  if [[ -d "$r/var/crash" ]]; then find "$r/var/crash" -mindepth 1 -delete; fi
  rm -f -- "$r"/var/cache/debconf/*-old
  rm -f -- "$r/root/.bash_history" "$r/root/.lesshst" "$r/root/.python_history" "$r/root/.wget-hsts" "$r/root/.viminfo"
  rm -rf -- "$r/root/.cache"
  # Namensauflösung: im installierten System wieder die von systemd-resolved
  if [[ ! -L "$r/etc/resolv.conf" ]]; then
    rm -f -- "$r/etc/resolv.conf"
    ln -s ../run/systemd/resolve/stub-resolv.conf "$r/etc/resolv.conf"
  fi
}

clean_system() {
  local dirty
  clean_root "$SYSTEM"
  if [[ -n "$(find "$SYSTEM/home" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    warn "/home ist nicht leer: $(find "$SYSTEM/home" -mindepth 1 -maxdepth 1 -printf '%f ')"
  fi
  dirty=$(git -C "$SYSTEM/opt/zenos" status --porcelain --ignored)
  if [[ -n "$dirty" ]]; then
    warn "install.sh hat /opt/zenos verändert, wird zurückgesetzt:"
    printf '%s\n' "$dirty" | sed 's/^/     /' >&2
    git -C "$SYSTEM/opt/zenos" reset --quiet --hard
    git -C "$SYSTEM/opt/zenos" clean --quiet -ffdx
  fi
  info "System: $(du -sxm -- "$SYSTEM" | cut -f 1) MiB"
}

# --- Schichten -------------------------------------------------------------

squash() { # QUELLE ZIEL
  quiet mksquashfs "$1" "$2" -noappend -no-progress -comp zstd -Xcompression-level 19 -b 1M -xattrs
  info "${2##*/}: $(mib "$(stat -c %s -- "$2")")"
}

# Werte aus shell/theme/tokens.json des Stands für Branding und Folien, je Zeile NAME=WERT. Farben nur #RRGGBB.
branding_values() {
  python3 -I - "$SYSTEM/opt/zenos/shell/theme/tokens.json" <<'PY'
import json, re, sys
t = json.load(open(sys.argv[1], encoding="utf-8"))
f = t["farben"]
d = f["dunkel"]
akzent = f["akzente"][f["standardAkzent"]]["dunkel"]
farben = {"GRUND": d["grund"], "FLAECHE": d["flaeche"], "FLAECHE2": d["flaeche2"], "LINIE": d["linie"],
          "TEXT": d["text"], "TEXT2": d["text2"], "GEDAEMPFT": d["gedaempft"], "EINGABERAND": d["eingabeRand"],
          "AKZENT": akzent, "AKZENT_TEXT": d["grund"]}
for name, wert in farben.items():
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", wert):
        sys.exit("Farbe %s ist kein #RRGGBB: %r" % (name, wert))
    print("%s=%s" % (name, wert))
s = t["schrift"]
g = s["groessen"]
print("SCHRIFT=%s" % s["text"])
print("SCHRIFT_ANZEIGE=%s" % s["anzeige"])
print("GROESSE=%d" % g["text"])
print("GROESSE_GROSS=%d" % g["gross"])
print("GROESSE_TITEL=%d" % g["titel"])
print("RADIUS=%d" % t["radius"]["feld"])
print("RADIUS_KLEIN=%d" % t["radius"]["xs"])
print("DAUER=%d" % t["bewegung"]["maximal"])
PY
}

# Folien aus folien.txt als JSON-Liste [{de: {titel, zeile1, zeile2}, en: {…}}, …]
slides_json() {
  python3 -I - "$1" <<'PY'
import json, sys
folien = {}
for zeile in open(sys.argv[1], encoding="utf-8"):
    zeile = zeile.rstrip("\n")
    if not zeile or zeile.startswith("#"):
        continue
    teile = zeile.split("|")
    if len(teile) != 5 or teile[1] not in ("de", "en") or not teile[0].isdigit():
        sys.exit("folien.txt: ungültige Zeile %r" % zeile)
    folien.setdefault(int(teile[0]), {})[teile[1]] = {"titel": teile[2], "zeile1": teile[3], "zeile2": teile[4]}
liste = [folien[n] for n in sorted(folien)]
if not liste or any(set(f) != {"de", "en"} for f in liste):
    sys.exit("folien.txt: jede Folie braucht de und en")
print(json.dumps(liste, ensure_ascii=False))
PY
}

# Vorlage QUELLE mit Platzhaltern @NAME@ nach ZIEL; jeder Platzhalter muss einen Wert haben
fill_template() { # QUELLE ZIEL NAME=WERT…
  local quelle=$1 ziel=$2 text paar
  shift 2
  text=$(cat -- "$quelle")
  for paar in "$@"; do text=${text//@${paar%%=*}@/${paar#*=}}; done
  if [[ "$text" =~ @[A-Z][A-Z0-9_]*@ ]]; then die "${quelle#"$REPO_DIR"/}: Platzhalter ohne Wert (${BASH_REMATCH[0]})"; fi
  printf '%s\n' "$text" > "$ziel"
}

install_calamares_config() {
  local r=$LIVE src="$SYSTEM/opt/zenos/image/x86/calamares" dest="$LIVE/etc/calamares" folien name
  local -a werte=()
  mapfile -t werte < <(branding_values) || true
  (( ${#werte[@]} == 18 )) || die "Werte aus shell/theme/tokens.json unvollständig (${#werte[@]} statt 18)"
  werte+=("VERSION=$VERSION")
  folien=$(slides_json "$src/branding/zenos/folien.txt") || die "Folien aus folien.txt nicht lesbar"

  rm -rf -- "$dest"
  install -d -m 0755 "$dest/modules" "$dest/branding/zenos"
  install -m 0644 -- "$src/settings.conf" "$dest/settings.conf"
  for name in "$src"/modules/*.conf; do install -m 0644 -- "$name" "$dest/modules/${name##*/}"; done
  fill_template "$src/branding/zenos/branding.desc.in" "$dest/branding/zenos/branding.desc" "${werte[@]}"
  fill_template "$src/branding/zenos/stylesheet.qss.in" "$dest/branding/zenos/stylesheet.qss" "${werte[@]}"
  fill_template "$src/branding/zenos/show.qml.in" "$dest/branding/zenos/show.qml" "${werte[@]}" "FOLIEN=$folien"
  for name in zenos-zeichen-dunkel.svg zenos-schriftzug-dunkel.svg; do
    install -m 0644 -- "$SYSTEM/opt/zenos/assets/zeichen/$name" "$dest/branding/zenos/$name"
  done
  info "Calamares: settings.conf, $(find "$dest/modules" -name '*.conf' | wc -l) Module, Branding zenos (Version $VERSION)"
  [[ -x "$r/usr/bin/calamares" ]] || die "Calamares fehlt in der Live-Schicht"
}

install_live_session() {
  local r=$LIVE src="$SYSTEM/opt/zenos/image/x86/live" name unit
  install -d -m 0755 "$r/usr/local/libexec/zenos-iso" "$r/etc/zenos-iso/labwc"
  for name in sitzung calamares-starten tastatur abschluss protokoll; do
    install -m 0755 -- "$src/$name" "$r/usr/local/libexec/zenos-iso/$name"
  done
  install -m 0644 -- "$src/rc.xml" "$r/etc/zenos-iso/labwc/rc.xml"
  for name in zenos-iso-sitzung.service zenos-iso-tastatur.path zenos-iso-tastatur.service; do
    install -m 0644 -- "$src/$name" "$r/etc/systemd/system/$name"
  done
  quiet in_root "$r" systemctl enable zenos-iso-sitzung.service zenos-iso-tastatur.path

  # Live-System: kein Login von zenOS, kein Netz, keine Zeitpläne und keine Dienste von zenOS. Die Masken liegen nur
  # in der Live-Schicht; das installierte System bekommt sie nie.
  rm -f -- "$r/etc/systemd/system/display-manager.service"
  for unit in "${LIVE_MASKIERT[@]}"; do
    ln -sfn /dev/null "$r/etc/systemd/system/$unit"
  done
  while read -r unit _; do
    case "$unit" in
      *.timer | zenos-*.service | zenos-*.socket | zenos-*.path)
        [[ "$unit" == zenos-iso-* ]] || ln -sfn /dev/null "$r/etc/systemd/system/$unit"
        ;;
    esac
  done < <(in_root "$r" systemctl list-unit-files --no-legend --state=enabled,static,alias 2>/dev/null || true)
  info "Live-System: Installer-Sitzung auf tty1, maskiert: $(find "$r/etc/systemd/system" -maxdepth 1 -lname /dev/null | wc -l) Einheiten"

  # casper: Live-Benutzer und Rechnername zenos (ohne Benutzer kommt der von Ubuntu)
  cat > "$r/etc/casper.conf" <<'EOF'
# zenOS-ISO: Live-System (casper). Die Installer-Sitzung läuft als root, der Live-Benutzer bleibt ungenutzt.
export USERNAME="zenos"
export USERFULLNAME="zenOS"
export HOST="zenos"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="zenOS"
EOF
  # Sprachen des Installers
  sed -i -E 's/^# *(de_DE\.UTF-8 UTF-8|en_US\.UTF-8 UTF-8)$/\1/' "$r/etc/locale.gen"
  quiet in_root "$r" locale-gen
}

build_live() {
  local oben="$WORK/live-oben" arbeit="$WORK/live-arbeit" uuid
  mkdir -p -- "$oben" "$arbeit" "$LIVE"
  mount -t overlay overlay -o "lowerdir=$SYSTEM,upperdir=$oben,workdir=$arbeit" "$LIVE"
  mount_root "$LIVE"
  quiet apt_in "$LIVE" update
  info "Pakete: ${LIVE_PAKETE[*]}"
  quiet apt_in "$LIVE" install "${LIVE_PAKETE[@]}"
  install_calamares_config
  install_live_session

  # initrd für den Start vom Datenträger: casper (initramfs-tools statt dracut, nur in dieser Schicht) mit Startbild
  # und Kennung des Datenträgers. Neu erzeugen (-c): Das vorhandene stammt von dracut.
  rm -f -- "$LIVE/boot/initrd.img-$KVER"
  quiet in_root "$LIVE" CASPER_GENERATE_UUID=1 update-initramfs -c -k "$KVER"
  install -m 0644 -- "$LIVE/boot/initrd.img-$KVER" "$WORK/iso/casper/initrd"
  rm -rf -- "$TMP_DIR/initrd"
  quiet in_root "$LIVE" unmkinitramfs "/boot/initrd.img-$KVER" /tmp/initrd
  uuid=$(find "$LIVE/tmp/initrd" -path '*/conf/uuid.conf' -exec cat {} \; -quit 2>/dev/null || true)
  [[ "$uuid" =~ ^[0-9a-f-]{36}$ ]] || die "Kennung des Datenträgers im initrd nicht gefunden (casper, CASPER_GENERATE_UUID)"
  install -d -m 0755 "$WORK/iso/.disk"
  printf '%s\n' "$uuid" > "$WORK/iso/.disk/casper-uuid-generic"
  [[ -n "$(find "$LIVE/tmp/initrd" -path '*/usr/share/plymouth/themes/zenos/zenos.script' -print -quit)" ]] ||
    warn "Im initrd fehlt das Startbild von zenOS (Plymouth)"
  rm -f -- "$LIVE/boot/initrd.img-$KVER"
  info "initrd: $(mib "$(stat -c %s -- "$WORK/iso/casper/initrd")"), Kennung $uuid"

  clean_root "$LIVE"
  umount_root "$LIVE"
  unmount_below "$LIVE"
  squash "$oben" "$WORK/iso/casper/zenos.live.squashfs"
}

# --- ISO -------------------------------------------------------------------

# Signierte Datei aus dem System: die erste vorhandene
pick() {
  local name
  for name in "$@"; do
    if [[ -f "$SYSTEM$name" ]]; then
      printf '%s' "$SYSTEM$name"
      return 0
    fi
  done
  die "Keine von: $*"
}

build_iso() {
  local iso="$WORK/iso" efi="$WORK/efi.img" kennung shim grub mm volid name="zenos-$VERSION-x86-amd64.iso" zusatz=""
  install -d -m 0755 "$iso/boot/grub" "$iso/EFI/boot" "$iso/.disk"
  install -m 0644 -- "$SYSTEM/boot/vmlinuz-$KVER" "$iso/casper/vmlinuz"

  # shim: zweifach signiert (alte und neue UEFI-CA von Microsoft) startet auf alten und neuen Rechnern
  shim=$(pick /usr/lib/shim/shimx64.efi.dualsigned /usr/lib/shim/shimx64.efi.signed.latest /usr/lib/shim/shimx64.efi.signed)
  grub=$(pick /usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed)
  mm=$(pick /usr/lib/shim/mmx64.efi.signed /usr/lib/shim/mmx64.efi)
  info "shim ${shim##*/}, GRUB ${grub##*/}, MokManager ${mm##*/}"

  kennung=$(cat /proc/sys/kernel/random/uuid)
  : > "$iso/.disk/zenos-$kennung"
  printf 'zenOS %s amd64 (%s)\n' "$VERSION" "$(date -u +%Y%m%d)" > "$iso/.disk/info"
  # Testbau: Meldungen von Kernel und systemd auch auf die serielle Schnittstelle (test/x86/qemu-test.py liest mit)
  if (( TEST_BUILD )); then zusatz="console=tty0 console=ttyS0,115200 plymouth.ignore-serial-consoles"; fi
  fill_template "$SYSTEM/opt/zenos/image/x86/iso/grub.cfg.in" "$iso/boot/grub/grub.cfg" "VERSION=$VERSION" "ZUSATZ=$zusatz"
  fill_template "$SYSTEM/opt/zenos/image/x86/iso/grub-efi.cfg.in" "$TMP_DIR/grub-efi.cfg" "KENNUNG=$kennung"
  install -m 0644 -- "$shim" "$iso/EFI/boot/bootx64.efi"
  install -m 0644 -- "$grub" "$iso/EFI/boot/grubx64.efi"
  install -m 0644 -- "$mm" "$iso/EFI/boot/mmx64.efi"

  # EFI-Partition: shim, GRUB, MokManager und die erste GRUB-Konfiguration
  rm -f -- "$efi"
  quiet mkfs.vfat -C -n ZENOS_EFI "$efi" 16384
  quiet mmd -i "$efi" ::/EFI ::/EFI/boot ::/boot ::/boot/grub
  quiet mcopy -i "$efi" "$shim" ::/EFI/boot/bootx64.efi
  quiet mcopy -i "$efi" "$grub" ::/EFI/boot/grubx64.efi
  quiet mcopy -i "$efi" "$mm" ::/EFI/boot/mmx64.efi
  quiet mcopy -i "$efi" "$TMP_DIR/grub-efi.cfg" ::/boot/grub/grub.cfg

  volid="zenOS ${VERSION}"
  volid=${volid:0:32}
  mkdir -p -- "$OUTPUT"
  rm -f -- "$OUTPUT/$name" "$OUTPUT/SHA256SUMS"
  quiet xorriso -as mkisofs -r -J -joliet-long -iso-level 3 -V "$volid" -A "zenOS $VERSION" \
    -partition_offset 16 -appended_part_as_gpt \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$efi" \
    -iso_mbr_part_type EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 \
    -c /boot.catalog -e --interval:appended_partition_2:all:: -no-emul-boot \
    -o "$OUTPUT/$name" "$iso"
  ISO_FILE="$OUTPUT/$name"
  info "$name: $(mib "$(stat -c %s -- "$ISO_FILE")"), Datenträger «$volid»"
}

finish_output() {
  local list="zenos-$VERSION-x86-amd64.pakete.txt"
  cp -- "$WORK/pakete.txt" "$OUTPUT/$list"
  (cd -- "$OUTPUT" && sha256sum -- "${ISO_FILE##*/}" "$list" > SHA256SUMS && sha256sum --check --quiet SHA256SUMS)
  {
    printf 'serie=%s\n' "$opt_series"
    printf 'kernel=%s\n' "$KVER"
    printf 'zenos_version=%s\n' "$VERSION"
    printf 'zenos_commit=%s\n' "$COMMIT"
    printf 'kanal=%s\n' "$opt_channel"
    printf 'tag=%s\n' "$TAG"
    if (( SIGNED )); then printf 'signatur=%s\n' "$SIG_KEY"; else printf 'signatur=keine (Testbau)\n'; fi
    printf 'anker_serie=%s\n' "$SIG_SERIES"
    printf 'iso_groesse=%s\n' "$(stat -c %s -- "$ISO_FILE")"
  } > "$WORK/basis.txt"
  info "SHA256SUMS geprüft"
}

# --- Ablauf ----------------------------------------------------------------

exec 7>&1 8>&2
trap cleanup EXIT
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

step "Vorbereitung: Tag und Signatur"
resolve_source
if (( opt_check_only )); then
  DONE=1
  info "Nur geprüft (--nur-pruefen), nichts gebaut."
  exit 0
fi

step "Vorbereitung"
preflight
clean_work

step "Grundlage: Ubuntu ($opt_series) mit debootstrap"
build_base

step "zenOS nach /opt/zenos"
prepare_code

step "install.sh --image im chroot"
run_install

step "Kennung, Sicherheitsquelle, Kanal und Zustand ab Werk"
check_identity
prepare_channel

step "Anpassungen für PCs"
prepare_x86
write_package_list

step "System-Schicht packen"
clean_system
umount_root "$SYSTEM"
install -d -m 0755 "$WORK/iso/casper"
cp -- "$WORK/pakete.txt" "$WORK/iso/casper/zenos.manifest"
squash "$SYSTEM" "$WORK/iso/casper/zenos.squashfs"

step "Live-Schicht: casper, Calamares und die Installer-Sitzung"
build_live

step "ISO"
build_iso
finish_output
DONE=1

step "Fertig"
info "$ISO_FILE"
info "$OUTPUT/zenos-$VERSION-x86-amd64.pakete.txt"
info "$OUTPUT/SHA256SUMS"
if (( WARNINGS > 0 )); then info "$WARNINGS Warnung(en), siehe oben"; fi
