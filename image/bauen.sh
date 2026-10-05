#!/usr/bin/env bash
# bauen.sh – baut das zenOS-Image für den Raspberry Pi 5 aus dem offiziellen Ubuntu-Server-Image.
#
#   sudo image/bauen.sh --ref vX.Y.Z[-rcN] [optionen]   (alle Optionen: image/bauen.sh --hilfe)
#
# Gebaut wird nur ein gültig signierter Release-Tag: image/tag-pruefen.sh prüft ihn vor allem anderen gegen den Anker
# system/vertrauen in seinem Commit (git verify-tag gehärtet und ssh-keygen -Y verify), sonst bricht der Bau ab. Der
# Kanal folgt dem Tag: vX.Y.Z → stabil, vX.Y.Z-rcN → vorschau. Nur ein Testbau (--testbau-ohne-signatur, nie in
# GitHub Actions) nimmt auch einen unsignierten Stand; seine Version endet auf «-testbau».
#
# Ablauf: Ubuntu 26.04 Server (preinstalled, arm64+raspi) laden, die GPG-Signatur von SHA256SUMS und die
# Prüfsumme kontrollieren, entpacken, vergrössern, Boot- und Root-Partition über Loop-Geräte einhängen,
# /opt/zenos als Git-Checkout des Tags anlegen, im chroot «ZENOS_KANAL=<kanal> /opt/zenos/scripts/install.sh --image»
# ausführen, die Kennung zenOS und die Ubuntu-Sicherheitsquelle prüfen (sonst Abbruch), Anker und Kanal prüfen und
# den Zustand ab Werk anlegen (12-vertrauen füllt /etc/zenos/vertrauen nur im Image aus system/vertrauen;
# «zenos-kanal image <tag>» prüft den Tag im chroot wie ein Gerät und schreibt gut.json, hoechste und gesehen.json),
# den ersten Start einrichten (Benutzer «user», Rechner «zenos», image/erststart/), die Paketliste schreiben,
# aufräumen, verkleinern, mit xz packen und SHA256SUMS schreiben. Ergebnis in <ausgabe>:
# zenos-<version>-pi5-arm64.img.xz, zenos-<version>-pi5-arm64.pakete.txt und SHA256SUMS.
# Läuft als root auf arm64-Linux (GitHub-Runner ubuntu-24.04-arm oder lokal). Mehr in image/README.md.
# «--nur-pruefen» prüft nur Tag, Signatur, Kanal und Version, ohne root und ohne zu bauen.

set -Eeuo pipefail
umask 022
export LC_ALL=C.UTF-8
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
REPO_DIR=$(cd -- "$(dirname -- "$SCRIPT")/.." && pwd -P)

readonly CDIMAGE_BASE=https://cdimage.ubuntu.com/releases
# «Ubuntu CD Image Automatic Signing Key (2012) <cdimage@ubuntu.com>» signiert SHA256SUMS auf cdimage.ubuntu.com
readonly CDIMAGE_FINGERPRINT=843938DF228D22F7B3742BC0D94AA3F0EFE21092
# GitHub nimmt Release-Dateien nur unter 2 GiB an
readonly RELEASE_LIMIT=2147483648
# Release-Tags wie in zenos-kanal (VERSION_RE) und image/tag-pruefen.sh
readonly VERSION_ERE='^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(-rc[1-9][0-9]{0,8})?$'

usage() {
  cat <<'EOF'
Aufruf: sudo image/bauen.sh --ref vX.Y.Z[-rcN] [optionen]

  --ref REF          Git-Stand für /opt/zenos: ein Release-Tag vX.Y.Z oder vX.Y.Z-rcN, gültig signiert
                     (Standard: HEAD, das geht nur im Testbau)
  --version V        Version im Dateinamen (Standard: der Tag ohne «v»; im Testbau ohne Tag git describe)
  --quelle ORDNER    Git-Repo mit zenOS (Standard: das Repo dieses Skripts)
  --origin URL       origin von /opt/zenos für «zen update», nur https (Standard: origin der Quelle)
  --kanal K          Kanal für «zen update»: stabil, vorschau oder dev (Standard: aus dem Tag, vX.Y.Z → stabil,
                     vX.Y.Z-rcN → vorschau; ohne Tag dev). Ein anderer als der des Tags nur im Testbau
  --ubuntu V         Ubuntu-Version auf cdimage.ubuntu.com (Standard: 26.04, neueste Punktversion)
  --arbeit ORDNER    Arbeitsordner (Standard: /var/tmp/zenos-image)
  --ausgabe ORDNER   Ziel für .img.xz, Paketliste und SHA256SUMS (Standard: <arbeit>/ausgabe)
  --cache ORDNER     Ubuntu-Image dort behalten und wiederverwenden (sonst nach dem Entpacken gelöscht)
  --zusatz-mib N     Root-Partition vor dem chroot um N MiB vergrössern (Standard: 6144)
  --reserve-mib N    nach dem Verkleinern frei lassen (Standard: 256)
  --xz-stufe N       Kompression 0–9 (Standard: 9)
  --testbau-ohne-signatur
                     nur für lokale Testbauten: Stand ohne gültig signierten Tag (Zweig, Commit, unsignierter Tag)
                     und ein anderer Kanal sind erlaubt; die Version endet auf «-testbau». Ohne gültige Signatur
                     gibt es keinen Zustand ab Werk. In GitHub Actions verweigert, nie für Releases
  --nur-mechanik     Test: im chroot nur Prüfbefehle statt install.sh (Image nicht für Releases, Version
                     «-mechanik», ohne Pflicht zur Signatur)
  --nur-pruefen      nur Stand, Tag, Signatur, Kanal und Version prüfen und zeigen, dann Ende (ohne root, baut nichts)
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
opt_ubuntu=26.04
opt_work=/var/tmp/zenos-image
opt_output=""
opt_cache=""
opt_extra_mib=6144
opt_reserve_mib=256
opt_xz_level=9
opt_mechanics=0
opt_unsigned_test=0
opt_check_only=0

while (( $# > 0 )); do
  case "$1" in
    -h | --hilfe | --help) usage; exit 0 ;;
    --nur-mechanik) opt_mechanics=1; shift; continue ;;
    --testbau-ohne-signatur) opt_unsigned_test=1; shift; continue ;;
    --nur-pruefen) opt_check_only=1; shift; continue ;;
    --ref | --version | --quelle | --origin | --kanal | --ubuntu | --arbeit | --ausgabe | --cache | \
      --zusatz-mib | --reserve-mib | --xz-stufe)
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
    --ubuntu) opt_ubuntu=$2 ;;
    --arbeit) opt_work=$2 ;;
    --ausgabe) opt_output=$2 ;;
    --cache) opt_cache=$2 ;;
    --zusatz-mib) opt_extra_mib=$2 ;;
    --reserve-mib) opt_reserve_mib=$2 ;;
    --xz-stufe) opt_xz_level=$2 ;;
  esac
  shift 2
done

# Eigener, privater Mount-Namensraum: Die Einhängepunkte des Images bleiben für den Host und seine Dienste
# unsichtbar und verschwinden spätestens mit dem Ende des Skripts. Sonst übernehmen Dienste mit eigenem
# Namensraum (auf dem GitHub-Runner z. B. systemd-resolved, systemd-logind, ModemManager) eine Kopie und
# halten das Loop-Gerät fest; e2fsck meldet es beim Verkleinern dann als belegt. --nur-pruefen hängt nichts ein
# (und läuft so auch in Containern ohne CAP_SYS_ADMIN).
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
IMG=""
ROOT_MNT=""
LOOP_DEV=""
LOOP_ROOT=""
LOOP_BOOT=""
LOOPS=()
BOOTDIR_CREATED=0
POLICY_CREATED=0
RESOLV_REPLACED=0
RESOLV_LINK=""
RESOLV_BACKUP=""
LOG_SAVED=0
DONE=0
# Entpacktes Image (compress_image), für das Manifest des Raspberry Pi Imagers
IMAGE_SIZE=""
IMAGE_SHA=""
# Tag und Signatur (resolve_source): TAG leer ohne Release-Tag; SIGNED 1 nach gültiger Prüfung; SEED 1, wenn das Image
# den Zustand ab Werk bekommt (signiert und Kanal des Tags); TEST_BUILD 1 im Testbau und mit --nur-mechanik
TAG=""
SIGNED=0
SEED=0
TEST_BUILD=0
SIG_KEY=""
SIG_SERIES=""
SIG_ROOT=""

cleanup() {
  local rc=$?
  set +e
  trap - ERR
  # Kam der Abbruch während einer umgeleiteten Ausgabe (quiet), gehören die Meldungen wieder aufs Terminal
  exec 1>&7 2>&8
  if (( ! DONE && opt_check_only )); then
    printf '\nVorprüfung gescheitert (Exit %s). Kein Image.\n' "$rc" >&2
  elif (( ! DONE )); then
    if [[ -n "$ROOT_MNT" ]]; then
      printf '\nImage-Bau abgebrochen (Exit %s). Räume Einhängepunkte und Loop-Geräte auf.\n' "$rc" >&2
    else
      printf '\nImage-Bau abgebrochen (Exit %s).\n' "$rc" >&2
    fi
    save_install_log
  fi
  unmount_all 0
  detach_loops
  if [[ -n "$ROOT_MNT" ]]; then rmdir -- "$ROOT_MNT" 2>/dev/null || true; fi
  if [[ -n "$TMP_DIR" ]]; then rm -rf -- "$TMP_DIR"; fi
  if [[ -n "$GIT_CONFIG_FILE" ]]; then rm -f -- "$GIT_CONFIG_FILE"; fi
  if (( ! DONE )) && [[ -n "$IMG" && -e "$IMG" ]]; then
    printf 'Rohes Image zur Fehlersuche: %s\n' "$IMG" >&2
  fi
  exit "$rc"
}

# --- Hilfen ----------------------------------------------------------------

# Führt einen Befehl still aus; bei einem Fehler erscheint seine Ausgabe.
quiet() {
  local log="$TMP_DIR/befehl.log" rc=0
  "$@" >"$log" 2>&1 || rc=$?
  if (( rc != 0 )); then
    sed 's/^/     /' -- "$log" >&2
    die "$1 fehlgeschlagen (Exit $rc)"
  fi
}

mib() { printf '%s MiB' $(( $1 / 1048576 )); }

sha256_of() { sha256sum -- "$1" | awk '{ print $1 }'; }

# fetch URL ZIEL [gross] – nur https; «gross»: auch nach abgerissenen Verbindungen weiterladen
fetch() {
  local -a options=(--silent --show-error)
  if [[ "${3:-}" == gross ]]; then
    if [[ -t 2 ]]; then options=(--progress-bar); fi
    options+=(--retry-all-errors --continue-at -)
  fi
  curl "${options[@]}" --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 30 --retry 5 --retry-delay 10 --output "$2" -- "$1"
}

# Befehl im chroot, mit sauberer Umgebung (nichts vom Host oder aus der CI gelangt hinein)
in_chroot() {
  chroot "$ROOT_MNT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root LANG=C.UTF-8 TERM=dumb DEBIAN_FRONTEND=noninteractive \
    "$@"
}

git_source() { git -C "$opt_source" "$@"; }

# Zugangsdaten aus der URL entfernen, GitHub-SSH als HTTPS (root im Image hat keinen SSH-Schlüssel)
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

# --- Loop-Geräte -----------------------------------------------------------

# attach_loop DATEI OFFSET GRÖSSE (Bytes) → LOOP_DEV
attach_loop() {
  local file=$1 offset=$2 size=$3 dev
  if ! dev=$(losetup --find --show --offset "$offset" --sizelimit "$size" -- "$file" 2>/dev/null); then
    # In Containern legt niemand die Gerätedatei eines neuen Loop-Geräts an
    dev=$(losetup --find) || die "Kein freies Loop-Gerät"
    if [[ ! -b "$dev" && "$dev" =~ ^/dev/loop([0-9]+)$ ]]; then
      mknod -m 0660 "$dev" b 7 "${BASH_REMATCH[1]}"
    fi
    losetup --offset "$offset" --sizelimit "$size" -- "$dev" "$file"
  fi
  LOOPS+=("$dev")
  LOOP_DEV=$dev
}

detach_loop() {
  local dev=$1 i
  losetup --detach "$dev"
  for i in "${!LOOPS[@]}"; do
    if [[ "${LOOPS[$i]}" == "$dev" ]]; then unset 'LOOPS[i]'; fi
  done
}

# Alle eigenen Loop-Geräte lösen, auch liegengebliebene aus einem früheren Lauf mit derselben Datei
detach_loops() {
  local dev
  for dev in "${LOOPS[@]}"; do losetup --detach "$dev" 2>/dev/null || true; done
  LOOPS=()
  if [[ -n "$IMG" && -e "$IMG" ]]; then
    while read -r dev; do
      if [[ -n "$dev" ]]; then losetup --detach "$dev" 2>/dev/null || true; fi
    done < <(losetup --list --noheadings --output NAME --associated "$IMG" 2>/dev/null)
  fi
}

# --- Einhängen -------------------------------------------------------------

# Prozesse, die im chroot weiterlaufen (z. B. gpg-agent), halten sonst die Einhängepunkte fest
stop_chroot_processes() {
  [[ -n "$ROOT_MNT" && -d "$ROOT_MNT" ]] || return 0
  local root_real proc link pid names="" try
  local -a pids=() alive
  root_real=$(readlink -f -- "$ROOT_MNT")
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

mount_all() {
  local os_file="$ROOT_MNT/usr/lib/os-release"
  mount -t ext4 -o noatime -- "$LOOP_ROOT" "$ROOT_MNT"
  if [[ ! -d "$ROOT_MNT/boot" || ! -f "$os_file" ]] || ! grep -qx 'ID=ubuntu' -- "$os_file"; then
    die "Das Root-Dateisystem sieht nicht nach Ubuntu aus"
  fi
  info "$(sed -n 's/^PRETTY_NAME=//p' -- "$os_file" | tr -d '"')"
  # Ubuntu legt /boot/firmware erst beim ersten Start an (systemd, fstab)
  if [[ ! -d "$ROOT_MNT/boot/firmware" ]]; then
    mkdir -- "$ROOT_MNT/boot/firmware"
    BOOTDIR_CREATED=1
  fi
  attach_loop "$IMG" $(( P1_START * 512 )) $(( P1_SIZE * 512 ))
  LOOP_BOOT=$LOOP_DEV
  mount -t vfat -o noatime -- "$LOOP_BOOT" "$ROOT_MNT/boot/firmware"

  mount -t proc -o nosuid,nodev,noexec proc "$ROOT_MNT/proc"
  mount --rbind /sys "$ROOT_MNT/sys"
  mount --make-rslave "$ROOT_MNT/sys"
  mount --rbind /dev "$ROOT_MNT/dev"
  mount --make-rslave "$ROOT_MNT/dev"
  # /run frisch statt vom Host: ohne /run/systemd/system gilt systemd im chroot als nicht laufend
  mount -t tmpfs -o nosuid,nodev,mode=0755 tmpfs "$ROOT_MNT/run"
  install -d -m 1777 "$ROOT_MNT/run/lock"
  mount -t tmpfs -o nosuid,nodev,mode=1777 tmpfs "$ROOT_MNT/tmp"
  # /var/tmp auf dem Host: der Quickshell-Bau (etwa 3,5 GB) belegt keinen Platz im Image
  install -d -m 1777 "$WORK/vartmp"
  mount --bind "$WORK/vartmp" "$ROOT_MNT/var/tmp"
}

# unmount_all 1|0 – 1: ein selbst angelegtes /boot/firmware wieder entfernen
unmount_all() {
  [[ -n "$ROOT_MNT" ]] || return 0
  local target
  local -a targets=()
  stop_chroot_processes
  mapfile -t targets < <(findmnt -rn -o TARGET | awk -v p="$ROOT_MNT/" 'index($0, p) == 1' | LC_ALL=C sort -r)
  for target in "${targets[@]}"; do
    umount_target "$target"
  done
  if mountpoint -q -- "$ROOT_MNT"; then
    if (( $1 && BOOTDIR_CREATED )); then
      rmdir -- "$ROOT_MNT/boot/firmware"
      BOOTDIR_CREATED=0
    fi
    umount_target "$ROOT_MNT"
  fi
}

# Erst normal aushängen (mit kurzen Wiederholungen), «umount -l» nur als sichtbarer Rückfall: Ein verzögert
# ausgehängtes Dateisystem hält das Loop-Gerät weiter, und e2fsck meldet es danach als belegt.
umount_target() {
  local target=$1 try
  for try in 1 2 3; do
    umount -- "$target" 2>/dev/null && return 0
    sleep "$try"
  done
  warn "$target ist belegt, nur verzögert ausgehängt"
  if command -v fuser >/dev/null; then fuser -vm -- "$target" 2>&1 | sed 's/^/     /' >&2 || true; fi
  umount -l -- "$target" || warn "$target liess sich nicht aushängen"
}

# Andere Mount-Namensräume (z. B. von Diensten des Hosts, die während des Baus starten) behalten eine Kopie
# der Einhängepunkte unter ROOT_MNT und halten so das Loop-Gerät. Dort gezielt aushängen.
release_foreign_mounts() {
  local root_real proc ns pid path
  local -A seen=()
  root_real=$(readlink -f -- "$ROOT_MNT")
  for proc in /proc/[0-9]*; do
    pid=${proc#/proc/}
    ns=$(readlink -- "$proc/ns/mnt" 2>/dev/null) || continue
    [[ -z "${seen[$ns]:-}" ]] || continue
    seen[$ns]=1
    grep -q -- " $root_real" "$proc/mountinfo" 2>/dev/null || continue
    warn "Mount-Namensraum von $(cat -- "$proc/comm" 2>/dev/null || true)[$pid] hält das Image noch"
    while read -r path; do
      nsenter --target "$pid" --mount -- umount -l -- "$path" 2>/dev/null || true
    done < <(awk -v p="$root_real" '$5 == p || index($5, p "/") == 1 { print $5 }' "$proc/mountinfo" | LC_ALL=C sort -r)
  done
}

# Wartet, bis niemand mehr GERÄT offen hält (udev/udisks prüfen ein Gerät nach dem Aushängen kurz)
wait_device_free() {
  local dev=$1 try
  release_foreign_mounts
  for try in 1 2 3 4 5 6 7 8 9 10; do
    if command -v udevadm >/dev/null; then udevadm settle --timeout=10 2>/dev/null || true; fi
    if ! findmnt -rn -S "$dev" >/dev/null 2>&1 && ! grep -qs -- "^$dev " /proc/mounts; then
      return 0
    fi
    sleep 2
  done
  warn "$dev ist nach dem Aushängen noch eingehängt"
}

# Namensauflösung im chroot. Ubuntu: /etc/resolv.conf → ../run/systemd/resolve/stub-resolv.conf, und /run ist
# hier ein tmpfs. Die Datei im Image bleibt dann unberührt; sonst wird sie getauscht und am Ende zurückgelegt.
setup_resolv() {
  local host="$TMP_DIR/resolv.conf" target="$ROOT_MNT/etc/resolv.conf" link=""
  if [[ -r /etc/resolv.conf ]]; then
    cat -- /etc/resolv.conf > "$host"
  else
    warn "Keine /etc/resolv.conf auf dem Host: im chroot gibt es keine Namensauflösung"
    : > "$host"
  fi
  install -d -m 0755 "$ROOT_MNT/run/systemd/resolve"
  install -m 0644 "$host" "$ROOT_MNT/run/systemd/resolve/stub-resolv.conf"
  install -m 0644 "$host" "$ROOT_MNT/run/systemd/resolve/resolv.conf"
  if [[ -L "$target" ]]; then link=$(readlink -- "$target"); fi
  case "$link" in
    ../run/systemd/resolve/* | /run/systemd/resolve/*) return 0 ;;
  esac
  if [[ -n "$link" ]]; then
    RESOLV_LINK=$link
  elif [[ -e "$target" ]]; then
    RESOLV_BACKUP="$TMP_DIR/resolv.conf.image"
    cp -a -- "$target" "$RESOLV_BACKUP"
  fi
  rm -f -- "$target"
  install -m 0644 "$host" "$target"
  RESOLV_REPLACED=1
}

restore_resolv() {
  (( RESOLV_REPLACED )) || return 0
  local target="$ROOT_MNT/etc/resolv.conf"
  rm -f -- "$target"
  if [[ -n "$RESOLV_LINK" ]]; then
    ln -s -- "$RESOLV_LINK" "$target"
  elif [[ -n "$RESOLV_BACKUP" ]]; then
    cp -a -- "$RESOLV_BACKUP" "$target"
  fi
  RESOLV_REPLACED=0
}

# Im chroot keine Dienste starten. install.sh respektiert eine fremde policy-rc.d.
setup_policy() {
  local file="$ROOT_MNT/usr/sbin/policy-rc.d"
  if [[ -e "$file" || -L "$file" ]]; then
    info "policy-rc.d gibt es im Image schon, sie bleibt"
    return 0
  fi
  printf '#!/bin/sh\n# zenOS-Image-Bau (image/bauen.sh): im chroot keine Dienste starten\nexit 101\n' > "$file"
  chmod 0755 "$file"
  POLICY_CREATED=1
}

save_install_log() {
  (( ! LOG_SAVED )) || return 0
  [[ -n "$ROOT_MNT" && -f "$ROOT_MNT/var/log/zenos/install.log" && -n "${WORK:-}" ]] || return 0
  install -m 0644 -- "$ROOT_MNT/var/log/zenos/install.log" "$WORK/install.log" 2>/dev/null && LOG_SAVED=1
  return 0
}

# --- Ubuntu-Grundlage ------------------------------------------------------

# Öffentlicher Schlüssel (minimal exportiert). Geprüft wird der Fingerabdruck der gültigen Signatur.
cdimage_keyring() {
  base64 -d <<'EOF'
mQINBE+tjmgBEAC7pKK78t89DW7mvMoSgiScLfPNF8/TSF380is0hFRL3dOmcXEfNsX26jtv8bdv
vtkElB1fPwOntmqSAsrLOuURVQ6GSxH7IDU5QFfaTIsudtLR5YTlC3ZuOTOb1HWEK26fDRXuIWjh
FDXJH3KLv+rSrq0+x7ZtH++CHq5XJWk7VUh/wWcGxZefs7+1HTivymhjXCOwQvqblzZ5MAec9i4Q
IXxkqX1HY7ryxGVdjj9lApOnoU5EcSYr08cm7xQEgrdDLAZFQxDYBLDuV6E6jKEfAfwZINSEe4Oc
m82vtCF5K0HiwhFU09ky2yogbMuTTi2f8ibN8SbbhZDJlDPd2ZkkpsKNfIALmOiPhHGvXGmtg6Fd
zRUOSGirSm8tcakpS+d0/IElbD453sksxg6s3cTs7Q+PudaccyQ0BqatMnzmfxCVOotT65kVnmz2
P+4Q0gRSQ/Zi9Inz+OrzWxtn6/Tdw+FMUwvBccxW1r88k6uVLz23jW/8jOuwnUp4JKmZta/U2UZK
TyPyrvTYhp/zK332BEnxiRY4ZfQjA4Iwlw00l4pYBDLLc6TFJtLbDv859UCisXa8MtWYWrlM3YfG
Fs9k1WemML8u79g2DK8g3VPkD94Q5anqufEGm74K/keOmss8cQoBX9VPFMpS1mFCT+2UdGP0UvMl
ADct0aFnAwtb9QARAQABtEFVYnVudHUgQ0QgSW1hZ2UgQXV0b21hdGljIFNpZ25pbmcgS2V5ICgy
MDEyKSA8Y2RpbWFnZUB1YnVudHUuY29tPokCNwQTAQoAIQUCT62OaAIbAwULCQgHAwUVCgkICwUW
AgMBAAIeAQIXgAAKCRDZSqPw7+IQkkhAEACJjZZXuAabMrC49Z52HywVZipJgoV5ufMi2LQYMkyG
KVQQ/E74lUjccMmbQ4j00ihTYB+F/i29AxfavJnlSpWgmwjPO4YY5jvooUiXQmVHX10oM1w3+Y9w
ScmeUY3IhTtwiFaBJr6TZ7RvOTg/pbQ0GvzxNlkSobuqFCZ023mcl2Y7OkY1PZgxiLafD6Rx2O/g
clQPs4YfHo8bKRA4o10702nE8YE+dixIgAQw67Txhq5idNxsWpudKq9J1fLgnEz7i9AJUOf12sg9
X7ZvpXZ3QvMV5iOvLA4DRLv9HIxyz70XqeakS+uzfKXuCMzhdUTIb/tNACNB37+reIqdPsyUF3tx
VyWaL1jMkRsv617yKAiYvPNwMDRvrbKiJ4Icnd4tPzmqz5HBFUyULns3JzJNjpgKCvLGhVq+lVsd
pMlpQxEG5/bhzJgB1jrIbkcOSfnQ1y0Gv9CItel+1q0BHMn0dPVWaNfKYFGsz4igW+uj//C09/gt
GMm78PQfjqEoR2j/Tam/tmucxSK331yfm5ag2CQYGC3bswfII+4EanX9dN/RG3/2dsSyYruWpTIQ
G6Xa7+AZtYBDEXNYovgdJtXWyUtW0X7R6vIjh1HYer3dR6ivJ+q/bWGY45zHeNBNU33hlnlxEENi
f3RZ/j/w3SjGrtSQK69maNR6onq492e+6w==
EOF
}

# SHA256SUMS laden, Signatur prüfen, neueste Punktversion wählen → UBUNTU_FILE, UBUNTU_SHA, UBUNTU_URL
select_ubuntu() {
  local dir="$CDIMAGE_BASE/$opt_ubuntu/release" sums="$TMP_DIR/SHA256SUMS" sig="$TMP_DIR/SHA256SUMS.gpg"
  local status="$TMP_DIR/gpgv.status" signers pattern hash name point best=""
  info "Quelle: $dir/"
  fetch "$dir/SHA256SUMS" "$sums" || die "SHA256SUMS nicht erreichbar – gibt es Ubuntu $opt_ubuntu auf cdimage.ubuntu.com?"
  fetch "$dir/SHA256SUMS.gpg" "$sig" || die "SHA256SUMS.gpg nicht erreichbar"

  cdimage_keyring > "$TMP_DIR/cdimage.gpg"
  install -d -m 0700 "$TMP_DIR/gnupg"
  if ! gpgv --homedir "$TMP_DIR/gnupg" --keyring "$TMP_DIR/cdimage.gpg" --status-fd 3 \
    "$sig" "$sums" 3>"$status" >"$TMP_DIR/gpgv.log" 2>&1; then
    sed 's/^/     /' -- "$TMP_DIR/gpgv.log" >&2
    die "Die Signatur von SHA256SUMS stimmt nicht"
  fi
  signers=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3; print $NF }' "$status")
  if ! grep -qxF -- "$CDIMAGE_FINGERPRINT" <<< "$signers"; then
    die "SHA256SUMS ist nicht mit dem Ubuntu-CD-Schlüssel $CDIMAGE_FINGERPRINT signiert"
  fi
  info "Signatur von SHA256SUMS gültig (Ubuntu CD Image Signing Key ${CDIMAGE_FINGERPRINT: -16})"

  pattern="^ubuntu-${opt_ubuntu//./\\.}(\\.[0-9]+)?-preinstalled-server-arm64\\+raspi\\.img\\.xz\$"
  while read -r hash name; do
    name=${name#\*}
    [[ "$hash" =~ ^[0-9a-f]{64}$ && "$name" =~ $pattern ]] || continue
    point=${name#ubuntu-}
    point=${point%%-*}
    printf '%s %s %s\n' "$point" "$name" "$hash"
  done < "$sums" | LC_ALL=C sort -V -k1,1 > "$TMP_DIR/kandidaten"
  best=$(tail -n 1 -- "$TMP_DIR/kandidaten")
  [[ -n "$best" ]] || die "In SHA256SUMS steht kein Server-Image für den Raspberry Pi (Ubuntu $opt_ubuntu)"
  read -r _ UBUNTU_FILE UBUNTU_SHA <<< "$best"
  UBUNTU_URL="$dir/$UBUNTU_FILE"
  info "Gewählt: $UBUNTU_FILE"
}

fetch_ubuntu() {
  local dir=${opt_cache:-$WORK/download}
  mkdir -p -- "$dir"
  UBUNTU_XZ="$dir/$UBUNTU_FILE"
  if [[ -f "$UBUNTU_XZ" ]]; then
    if [[ "$(sha256_of "$UBUNTU_XZ")" == "$UBUNTU_SHA" ]]; then
      info "Schon geladen und geprüft: $UBUNTU_XZ"
      return 0
    fi
    warn "Vorhandene Datei hat eine andere Prüfsumme, lade neu: $UBUNTU_XZ"
    rm -f -- "$UBUNTU_XZ"
  fi
  info "Lade $UBUNTU_FILE"
  rm -f -- "$UBUNTU_XZ.teil"
  fetch "$UBUNTU_URL" "$UBUNTU_XZ.teil" gross || die "Download von $UBUNTU_URL fehlgeschlagen"
  if [[ "$(sha256_of "$UBUNTU_XZ.teil")" != "$UBUNTU_SHA" ]]; then
    rm -f -- "$UBUNTU_XZ.teil"
    die "Die Prüfsumme von $UBUNTU_FILE stimmt nicht mit SHA256SUMS überein"
  fi
  mv -- "$UBUNTU_XZ.teil" "$UBUNTU_XZ"
  info "Prüfsumme stimmt: ${UBUNTU_SHA:0:16}…, $(mib "$(stat -c %s -- "$UBUNTU_XZ")")"
}

# --- Partitionen -----------------------------------------------------------

# → P1_START P1_SIZE P2_START P2_SIZE (Sektoren zu 512 Byte)
read_partitions() {
  local dump nr start sectors type
  dump=$(sfdisk --dump -- "$IMG")
  grep -qx 'label: dos' <<< "$dump" || die "Die Partitionstabelle ist nicht MBR (dos)"
  if grep -q '^sector-size:' <<< "$dump" && ! grep -qx 'sector-size: 512' <<< "$dump"; then
    die "Unerwartete Sektorgrösse im Ubuntu-Image"
  fi
  P1_START=""
  P2_START=""
  while read -r nr start sectors type; do
    case "$nr" in
      1) P1_START=$start; P1_SIZE=$sectors; P1_TYPE=$type ;;
      2) P2_START=$start; P2_SIZE=$sectors; P2_TYPE=$type ;;
      *) die "Unerwartete Partition $nr im Ubuntu-Image" ;;
    esac
  done < <(partx -g -r -o NR,START,SECTORS,TYPE -- "$IMG")
  [[ -n "$P1_START" && -n "$P2_START" ]] || die "Boot- und Root-Partition nicht gefunden"
  [[ "$P1_TYPE" == 0xc ]] || die "Partition 1 ist nicht FAT32 (Typ $P1_TYPE)"
  [[ "$P2_TYPE" == 0x83 ]] || die "Partition 2 ist nicht Linux (Typ $P2_TYPE)"
  (( P2_START > P1_START )) || die "Die Root-Partition liegt nicht hinter der Boot-Partition"
}

# Partition 2 neu setzen: START,GRÖSSE (Sektoren; «+» = bis zum Ende)
set_partition2() {
  printf '%s,%s,83\n' "$P2_START" "$1" > "$TMP_DIR/sfdisk.in"
  quiet sfdisk --no-reread --no-tell-kernel -N 2 -- "$IMG" < "$TMP_DIR/sfdisk.in"
  read_partitions
}

fsck_root() { # GERÄT [-n]
  local rc mode=-p try
  if [[ "${2:-}" == -n ]]; then mode=-n; fi
  for try in 1 2 3 4 5 6; do
    rc=0
    e2fsck -f "$mode" -- "$1" > "$TMP_DIR/e2fsck.log" 2>&1 || rc=$?
    # Exit 8 mit «in use»: ein anderer Prozess hält das Gerät gerade offen (kein Fehler im Dateisystem)
    if (( rc != 8 )) || ! grep -q 'in use' -- "$TMP_DIR/e2fsck.log"; then break; fi
    warn "$1 ist noch belegt, e2fsck wartet (Versuch $try)"
    release_foreign_mounts
    if command -v udevadm >/dev/null; then udevadm settle --timeout=10 2>/dev/null || true; fi
    sleep $(( try * 2 ))
  done
  if (( rc >= 4 )) || { [[ "$mode" == -n ]] && (( rc != 0 )); }; then
    sed 's/^/     /' -- "$TMP_DIR/e2fsck.log" >&2
    if grep -q 'in use' -- "$TMP_DIR/e2fsck.log"; then device_diagnose "$1"; fi
    die "e2fsck meldet Fehler im Root-Dateisystem (Exit $rc)"
  fi
}

# Wer hält GERÄT? Für die Fehlersuche im Log des Workflows
device_diagnose() {
  local dev=$1 name
  name=$(basename -- "$dev")
  {
    echo "     Diagnose für $dev:"
    findmnt -rn -S "$dev" 2>&1 | sed 's/^/       findmnt: /' || true
    find "/sys/block/$name/holders" -mindepth 1 -maxdepth 1 -printf '       holders: %f\n' 2>&1 || true
    if command -v fuser >/dev/null; then fuser -v -- "$dev" 2>&1 | sed 's/^/       fuser: /' || true; fi
    grep -ls -- "$(readlink -f -- "$ROOT_MNT")" /proc/[0-9]*/mountinfo 2>/dev/null | head -5 | sed 's/^/       mountinfo: /' || true
  } >&2
}

fs_value() { # GERÄT FELD – Wert aus dumpe2fs -h
  dumpe2fs -h -- "$1" 2>/dev/null | awk -F: -v f="$2" '$1 == f { gsub(/[[:space:]]/, "", $2); print $2 }'
}

# --- /opt/zenos ------------------------------------------------------------

prepare_code() {
  local dest="$ROOT_MNT/opt/zenos" ref name
  local -a git_dest=(git -C "$dest")
  [[ ! -e "$dest" ]] || die "/opt/zenos gibt es im Ubuntu-Image schon"
  install -d -m 0755 "$ROOT_MNT/opt"
  git clone --quiet --no-local --no-checkout -- "$opt_source" "$dest"
  if ! "${git_dest[@]}" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
    # Stand ohne Zweig und Tag (z. B. losgelöster HEAD): gezielt holen
    "${git_dest[@]}" fetch --quiet --no-tags -- "$opt_source" "$COMMIT"
  fi
  "${git_dest[@]}" -c advice.detachedHead=false checkout --quiet --detach "$COMMIT"

  # Nur der Stand und die Tags: keine Zweige der Quelle. «zen update» holt den Kanal von origin.
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
    warn "Ohne origin: «zen update» geht im Image erst nach «git remote add origin …»"
  fi
  "${git_dest[@]}" reflog expire --expire=now --all
  "${git_dest[@]}" gc --quiet --prune=now

  # Der Pfad der Quelle (lokal z. B. ein Home-Ordner) darf nicht im Image landen
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

# --- chroot ----------------------------------------------------------------

run_install() {
  local rc=0 end_line
  info "ZENOS_KANAL=$opt_channel /opt/zenos/scripts/install.sh --image"
  in_chroot ZENOS_KANAL="$opt_channel" /opt/zenos/scripts/install.sh --image || rc=$?
  save_install_log
  if [[ -f "$WORK/install.log" ]]; then
    end_line=$(grep '^== Ende' -- "$WORK/install.log" | tail -n 1 || true)
    if [[ -n "$end_line" ]]; then info "install.log: $end_line"; fi
  fi
  (( rc == 0 )) || die "install.sh --image ist im chroot fehlgeschlagen (Exit $rc)"
}

# Test der Mechanik ohne install.sh: Architektur, Netz und apt im chroot, Aufruf von install.sh, Git-Stand
run_mechanics() {
  local arch describe
  arch=$(in_chroot dpkg --print-architecture)
  [[ "$arch" == arm64 ]] || die "Architektur im chroot ist $arch statt arm64"
  info "Architektur im chroot: $arch"
  quiet in_chroot apt-get -q update
  info "apt-get update im chroot: Netz und Namensauflösung gehen"
  quiet in_chroot /opt/zenos/scripts/install.sh --hilfe
  info "install.sh im chroot aufrufbar"
  in_chroot touch /var/tmp/zenos-mechanik
  [[ -f "$WORK/vartmp/zenos-mechanik" ]] || die "/var/tmp im chroot liegt nicht im Arbeitsordner"
  rm -f -- "$WORK/vartmp/zenos-mechanik"
  info "/var/tmp im chroot liegt auf dem Host"
  describe=$(in_chroot git -C /opt/zenos describe --tags --always)
  info "git im chroot: /opt/zenos auf $describe"
}

# Nach install.sh: Kennung zenOS und Sicherheitsquelle. Kein Image ohne nachgewiesene Ubuntu-Sicherheitsupdates
# (docs/module/kennung.md). Die Paketlisten liegen nach dem apt-get update von install.sh im chroot vor.
check_identity() {
  local r=$ROOT_MNT os_file="$ROOT_MNT/usr/lib/os-release" ubuntu_file="$ROOT_MNT/usr/lib/os-release.ubuntu"
  local target codename lsb pretty output rc=0
  target=$(in_chroot dpkg-divert --truename /usr/lib/os-release)
  [[ "$target" == /usr/lib/os-release.ubuntu ]] || die "Umlenkung von /usr/lib/os-release fehlt (72-kennung, Install-Log)"
  [[ -f "$ubuntu_file" ]] || die "/usr/lib/os-release.ubuntu fehlt"
  grep -qx 'ID=zenos' -- "$os_file" || die "/usr/lib/os-release meldet nicht ID=zenos"
  codename=$(sed -n 's/^VERSION_CODENAME=//p' -- "$ubuntu_file" | tr -d '"')
  lsb=$(in_chroot lsb_release -cs 2>/dev/null) || true
  [[ -n "$codename" && "$lsb" == "$codename" ]] || die "lsb_release -cs meldet «$lsb» statt des Ubuntu-Codenamens «$codename»"
  pretty=$(sed -n 's/^PRETTY_NAME=//p' -- "$os_file" | tr -d '"')
  [[ -n "$pretty" && "$pretty" != *[Uu]buntu* ]] || die "PRETTY_NAME «$pretty» ist leer oder nennt Ubuntu"
  [[ -f "$r/etc/apt/apt.conf.d/51zenos-ubuntu-quellen" ]] || die "/etc/apt/apt.conf.d/51zenos-ubuntu-quellen fehlt"
  output=$(in_chroot /opt/zenos/scripts/bin/zenos-sicherheitsquelle 2>&1) || rc=$?
  (( rc == 0 )) || die "Ubuntu-Sicherheitsquelle nicht nachgewiesen (zenos-sicherheitsquelle Exit $rc): $output"
  rc=0
  output=$(in_chroot /usr/local/sbin/zenos-kennung pruefen 2>&1) || rc=$?
  (( rc == 0 )) || die "zenos-kennung pruefen (Exit $rc): ${output//$'\n'/; }"
  info "Kennung: $pretty · Basis $(sed -n 's/^PRETTY_NAME=//p' -- "$ubuntu_file" | tr -d '"') · Codename $lsb"
  info "Sicherheitsquelle: $(in_chroot /opt/zenos/scripts/bin/zenos-sicherheitsquelle 2>&1)"
  if ! grep -qx "ZENOS_VERSION=\"$opt_version\"" -- "$os_file"; then
    warn "ZENOS_VERSION in os-release ($(sed -n 's/^ZENOS_VERSION=//p' -- "$os_file")) ist nicht die Version im Dateinamen ($opt_version)"
  fi
}

# Nach install.sh: Kanal und Vertrauensanker des Images, dann der Zustand ab Werk. 12-vertrauen füllt
# /etc/zenos/vertrauen nur im Image aus system/vertrauen des Stands; hier muss er genau diesen Inhalt haben und
# vollständig sein. «zenos-kanal image <tag>» prüft den Tag danach im chroot noch einmal wie ein Gerät (mit git und
# ssh-keygen des Images, gegen den Anker des Images) und schreibt gut.json, hoechste und gesehen.json: Das Gerät
# kennt so ab dem ersten Start seinen guten Stand und seine Mindestversion, und ein später verschobener Tag gilt
# schon beim ersten Kontakt als ALARM.
prepare_channel() {
  local r=$ROOT_MNT name channel output rc=0
  local program=/usr/local/libexec/zenos/zenos-kanal
  [[ -x "$r$program" ]] || die "$program fehlt im Image (Modul 14-kanal, Install-Log)"
  channel=$(head -n 1 -- "$r/etc/xdg/zenos/kanal" 2>/dev/null | tr -d '[:space:]') || channel=""
  [[ "$channel" == "$opt_channel" ]] || die "Kanal im Image ist «$channel» statt «$opt_channel» (/etc/xdg/zenos/kanal)"
  info "Kanal für zen update: $channel"
  output=$(in_chroot "$program" anker --pruefen /etc/zenos/vertrauen 2>&1) || rc=$?
  if (( ! SIGNED )); then
    info "Anker: ${output:-?}"
    info "Testbau ohne gültige Signatur: kein Zustand ab Werk"
    return 0
  fi
  (( rc == 0 )) || die "Anker /etc/zenos/vertrauen im Image: ${output:-nicht prüfbar} (Exit $rc)"
  for name in release wurzel widerrufen serie; do
    cmp -s -- "$r/opt/zenos/system/vertrauen/$name" "$r/etc/zenos/vertrauen/$name" ||
      die "/etc/zenos/vertrauen/$name im Image ist nicht system/vertrauen/$name des Stands"
  done
  info "Anker: $output"
  if (( ! SEED )); then
    info "Testbau mit Kanal $opt_channel: kein Zustand ab Werk"
    return 0
  fi
  rc=0
  output=$(in_chroot "$program" image "$TAG" 2>&1) || rc=$?
  (( rc == 0 )) || die "zenos-kanal image $TAG (Exit $rc): ${output//$'\n'/; }"
  info "$output"
}

# Erster Start ohne Einstellungen aus dem Imager: Standardbenutzer «user» (sudo nur mit Passwort), Rechnername
# «zenos», README von zenOS auf der Startpartition, USB-2 im Host-Modus für das Compute Module 5. Die Dateien
# kommen aus image/erststart/ des gebauten Stands. user-data und 90-zenos-benutzer.cfg gehören zusammen: chpasswd
# setzt das Passwort für den Benutzer, den cloud-init aus default_user anlegt.
prepare_first_boot() {
  local r=$ROOT_MNT boot="$ROOT_MNT/boot/firmware" code="$ROOT_MNT/opt/zenos/image/erststart" datei
  for datei in user-data 90-zenos-benutzer.cfg README; do
    [[ -f "$code/$datei" ]] || die "image/erststart/$datei fehlt"
  done
  [[ -f "$boot/user-data" && -f "$boot/config.txt" ]] || die "user-data oder config.txt fehlt auf der Startpartition"
  grep -qE '^[[:space:]]*- name: ubuntu$' -- "$boot/user-data" ||
    warn "Die user-data von Ubuntu sieht anders aus als erwartet (Benutzer ubuntu); sie wird trotzdem ersetzt"

  # Startpartition (vfat: ohne Rechte und Besitzer)
  cp -- "$code/user-data" "$boot/user-data"
  cp -- "$code/README" "$boot/README"
  if grep -qx 'dtoverlay=dwc2,dr_mode=host' -- <(sed -n '/^\[cm5\]$/,/^\[/p' -- "$boot/config.txt"); then
    info "config.txt: [cm5] mit USB-2 im Host-Modus ist schon da"
  else
    printf '\n[cm5]\n# zenOS: USB-2-Anschluss im Host-Modus (Argon ONE UP: Tastatur, Touchpad, USB)\n%s\n\n[all]\n' \
      'dtoverlay=dwc2,dr_mode=host' >> "$boot/config.txt"
    info "config.txt: [cm5] dtoverlay=dwc2,dr_mode=host"
  fi

  install -D -m 0644 -o root -g root -- "$code/90-zenos-benutzer.cfg" "$r/etc/cloud/cloud.cfg.d/90-zenos-benutzer.cfg"
  printf 'zenos\n' > "$r/etc/hostname"
  if grep -qE '^127\.0\.1\.1[[:space:]]+ubuntu([[:space:]]|$)' -- "$r/etc/hosts" 2>/dev/null; then
    sed -i -E 's/^(127\.0\.1\.1[[:space:]]+)ubuntu([[:space:]]|$)/\1zenos\2/' -- "$r/etc/hosts"
  fi
  info "Erster Start ohne Imager: Benutzer user (Passwort user, muss geändert werden), Rechner zenos"
}

# Paketliste des Images: je Zeile Paket, Version, Quellpaket, Quellversion (Tab). Release-Datei für das
# Quellcode-Angebot und im Image unter /usr/local/share/doc/zenos/pakete.txt (Stand bei Auslieferung).
write_package_list() {
  local file="$WORK/pakete.txt" count
  # shellcheck disable=SC2016 # ${…} ist das Format von dpkg-query, keine Shell-Variable
  in_chroot dpkg-query -W \
    -f='${db:Status-Status}\t${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n' |
    awk -F '\t' -v OFS='\t' '$1 == "installed" { print $2, $3, $4, $5 }' | LC_ALL=C sort > "$file.teil"
  mv -- "$file.teil" "$file"
  count=$(wc -l < "$file")
  (( count > 100 )) || die "Paketliste mit nur $count Einträgen"
  install -D -m 0644 -o root -g root -- "$file" "$ROOT_MNT/usr/local/share/doc/zenos/pakete.txt"
  info "Paketliste: $count Pakete aus $(cut -f 3 -- "$file" | sort -u | wc -l) Quellpaketen"
}

# --- Aufräumen im Image ----------------------------------------------------

clean_image() {
  local r=$ROOT_MNT dirty link channel
  in_chroot apt-get clean
  stop_chroot_processes

  if (( POLICY_CREATED )); then
    rm -f -- "$r/usr/sbin/policy-rc.d"
    POLICY_CREATED=0
  fi
  restore_resolv
  if [[ -n "$RESOLV_ORIGINAL" ]]; then
    link=$(readlink -- "$r/etc/resolv.conf" 2>/dev/null || true)
    [[ "$link" == "$RESOLV_ORIGINAL" ]] || warn "/etc/resolv.conf im Image zeigt jetzt auf «$link» statt «$RESOLV_ORIGINAL»"
  fi

  # Schlüssel und Kennungen: jede Kopie des Images erzeugt beim ersten Start eigene
  if [[ -d "$r/etc/ssh" ]]; then
    find "$r/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -printf '   entfernt: /etc/ssh/%f\n' -delete
  fi
  if [[ -s "$r/etc/machine-id" ]]; then : > "$r/etc/machine-id"; fi
  if [[ -f "$r/var/lib/dbus/machine-id" && ! -L "$r/var/lib/dbus/machine-id" ]]; then
    rm -f -- "$r/var/lib/dbus/machine-id"
  fi
  rm -f -- "$r/var/lib/systemd/random-seed" "$r/var/lib/systemd/credential.secret"

  # Logs: rotierte weg, die übrigen leeren (Besitz und Rechte bleiben), das Install-Log löschen
  rm -f -- "$r/var/log/zenos/install.log"
  find "$r/var/log" -type f \( -name '*.gz' -o -name '*.xz' -o -name '*.zst' -o -name '*.[0-9]' -o -name '*.old' \) -delete
  find "$r/var/log" -type f -size +0 -exec truncate -s 0 {} +
  if [[ -d "$r/var/log/journal" ]]; then find "$r/var/log/journal" -mindepth 1 -delete; fi
  if [[ -d "$r/var/crash" ]]; then find "$r/var/crash" -mindepth 1 -delete; fi
  rm -f -- "$r"/var/cache/debconf/*-old

  # Verlauf und Caches von root (Benutzer gibt es im Image keine)
  rm -f -- "$r/root/.bash_history" "$r/root/.lesshst" "$r/root/.python_history" "$r/root/.wget-hsts" "$r/root/.viminfo"
  rm -rf -- "$r/root/.cache"
  find "$r/home" -mindepth 2 -maxdepth 2 -name '.bash_history' -delete
  if [[ -n "$(find "$r/home" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    warn "/home im Image ist nicht leer: $(find "$r/home" -mindepth 1 -maxdepth 1 -printf '%f ')"
  fi

  # /opt/zenos: sauberer Checkout des Stands
  dirty=$(git -C "$r/opt/zenos" status --porcelain --ignored)
  if [[ -n "$dirty" ]]; then
    warn "install.sh hat /opt/zenos verändert, wird zurückgesetzt:"
    printf '%s\n' "$dirty" | sed 's/^/     /' >&2
    git -C "$r/opt/zenos" reset --quiet --hard
    git -C "$r/opt/zenos" clean --quiet -ffdx
  fi
  if [[ -f "$r/etc/xdg/zenos/kanal" ]]; then
    channel=$(head -n 1 -- "$r/etc/xdg/zenos/kanal")
    info "Kanal für zen update: $channel"
    [[ "$channel" == "$opt_channel" ]] || warn "Kanal im Image ist «$channel» statt «$opt_channel»"
  elif (( ! opt_mechanics )); then
    warn "/etc/xdg/zenos/kanal fehlt nach install.sh"
  fi

  info "Belegt im Image: $(df -Ph -- "$r" | awk 'NR == 2 { print $3 " von " $2 }')"
  if (( ! opt_mechanics )); then
    info "Grösste Ordner:"
    du -x -m --max-depth=3 -- "$r/usr" "$r/var" "$r/opt" > "$TMP_DIR/du.txt" 2>/dev/null || true
    sort -rn -- "$TMP_DIR/du.txt" | awk -v r="$r" '{
      p = $2; if (index(p, r) == 1) p = substr(p, length(r) + 1)
      tiefe = p; if (gsub("/", "", tiefe) != 3 || ++n > 10) next
      printf "     %6d MiB  %s\n", $1, p }'
  fi

  # Freie Blöcke verwerfen: gelöschte Daten verschwinden, xz packt Nullen
  if fstrim -- "$r" >/dev/null 2>&1 && fstrim -- "$r/boot/firmware" >/dev/null 2>&1; then
    TRIMMED=1
    info "Freier Platz verworfen (fstrim)"
  else
    TRIMMED=0
    info "fstrim geht hier nicht, der freie Platz wird nach dem Verkleinern genullt"
  fi
}

# --- Verkleinern und packen ------------------------------------------------

shrink_image() {
  local bs blocks target part_blocks sectors rc
  fsck_root "$LOOP_ROOT"
  quiet resize2fs -M -- "$LOOP_ROOT"
  bs=$(fs_value "$LOOP_ROOT" 'Block size')
  blocks=$(fs_value "$LOOP_ROOT" 'Block count')
  [[ "$bs" =~ ^[0-9]+$ && "$blocks" =~ ^[0-9]+$ ]] || die "Grösse des Root-Dateisystems nicht lesbar"
  target=$(( blocks + opt_reserve_mib * 1048576 / bs ))
  part_blocks=$(( P2_SIZE * 512 / bs ))
  if (( target > part_blocks )); then target=$part_blocks; fi
  if (( target > blocks )); then quiet resize2fs -- "$LOOP_ROOT" "$target"; fi
  fsck_root "$LOOP_ROOT"
  if (( ! TRIMMED )); then
    if command -v zerofree >/dev/null; then
      rc=0
      zerofree -- "$LOOP_ROOT" || rc=$?
      (( rc == 0 )) || warn "zerofree fehlgeschlagen (Exit $rc): das Image wird grösser"
    else
      warn "Weder fstrim noch zerofree: gelöschte Daten bleiben im freien Platz, das Image wird grösser"
    fi
  fi
  detach_loop "$LOOP_ROOT"
  LOOP_ROOT=""

  sectors=$(( target * bs / 512 ))
  sectors=$(( (sectors + 2047) / 2048 * 2048 ))
  set_partition2 "$sectors"
  (( P2_SIZE == sectors )) || die "Partition 2 hat $P2_SIZE statt $sectors Sektoren"
  truncate -s $(( (P2_START + P2_SIZE) * 512 )) -- "$IMG"

  # Gegenprobe über die neue Partition
  attach_loop "$IMG" $(( P2_START * 512 )) $(( P2_SIZE * 512 ))
  fsck_root "$LOOP_DEV" -n
  detach_loop "$LOOP_DEV"
  info "Root-Dateisystem: $(mib $(( target * bs ))) (davon $(mib $(( (target - blocks) * bs ))) frei gelassen)"
  info "Image: $(mib "$(stat -c %s -- "$IMG")")"
}

compress_image() {
  local name="zenos-$VERSION-pi5-arm64.img.xz" list="zenos-$VERSION-pi5-arm64.pakete.txt" size
  local -a files=("$name")
  OUTPUT_FILE="$OUTPUT/$name"
  mkdir -p -- "$OUTPUT"
  rm -f -- "$OUTPUT_FILE" "$OUTPUT_FILE.teil" "$OUTPUT/SHA256SUMS" "$OUTPUT/$list"
  # Für das Manifest des Raspberry Pi Imagers (extract_size, extract_sha256)
  IMAGE_SIZE=$(stat -c %s -- "$IMG")
  IMAGE_SHA=$(sha256sum -- "$IMG" | cut -d ' ' -f 1)
  info "xz -T0 -$opt_xz_level → $name"
  xz -T0 "-$opt_xz_level" -c -- "$IMG" > "$OUTPUT_FILE.teil"
  xz -t -T0 -- "$OUTPUT_FILE.teil"
  mv -- "$OUTPUT_FILE.teil" "$OUTPUT_FILE"
  if [[ -f "$WORK/pakete.txt" ]]; then
    cp -- "$WORK/pakete.txt" "$OUTPUT/$list"
    files+=("$list")
  fi
  (cd -- "$OUTPUT" && sha256sum -- "${files[@]}" > SHA256SUMS && sha256sum --check --quiet SHA256SUMS)
  size=$(stat -c %s -- "$OUTPUT_FILE")
  info "$(mib "$size"), SHA256SUMS geprüft"
  if (( size >= RELEASE_LIMIT )); then
    warn "$name ist $(mib "$size") gross – GitHub nimmt Release-Dateien nur unter 2 GiB an"
  fi
}

# --- Vorbereitung ----------------------------------------------------------

# Release-Tag zu REF («vX.Y.Z[-rcN]» oder «refs/tags/vX.Y.Z[-rcN]», wenn es den Tag in der Quelle gibt), sonst leer
release_tag() {
  local name=${1#refs/tags/}
  if [[ "$name" =~ $VERSION_ERE ]] && git_source rev-parse --verify --quiet "refs/tags/$name" >/dev/null 2>&1; then
    printf '%s' "$name"
  fi
}

# Ist TAG gültig signiert? image/tag-pruefen.sh (aus dem Repo dieses Skripts) gegen den Anker im Commit des Tags,
# gebunden an COMMIT. Ohne gültige Signatur Abbruch, im Testbau nur eine Warnung. Setzt SIGNED und SIG_*.
check_signature() {
  local output key value rc=0
  SIGNED=0
  if [[ -z "$TAG" ]]; then
    (( TEST_BUILD )) || die "«$opt_ref» ist kein Release-Tag vX.Y.Z oder vX.Y.Z-rcN in $opt_source. Gebaut wird nur ein gültig signierter Tag (lokaler Testbau: --testbau-ohne-signatur)"
    warn "Testbau: «$opt_ref» ist kein Release-Tag, die Signatur wird nicht geprüft"
    return 0
  fi
  output=$("$REPO_DIR/image/tag-pruefen.sh" --quelle "$opt_source" --commit "$COMMIT" "$TAG") || rc=$?
  if (( rc != 0 )); then
    (( TEST_BUILD )) || die "Der Tag $TAG ist nicht gültig signiert (image/tag-pruefen.sh, Exit $rc, Grund oben). Kein Image."
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

# Quelle, Stand, Tag und Signatur, Kanal, Version und origin. Ohne root, ohne Einhängen: läuft vor allem anderen und
# allein mit --nur-pruefen.
resolve_source() {
  local derived
  if (( opt_unsigned_test || opt_mechanics )); then TEST_BUILD=1; fi
  if (( opt_unsigned_test )) && [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    die "--testbau-ohne-signatur gibt es in GitHub Actions nicht: Ein Image von dort kommt nur aus einem gültig signierten Tag"
  fi
  command -v git >/dev/null || die "git fehlt"
  opt_source=$(realpath -e -- "$opt_source") || die "Quelle «$opt_source» gibt es nicht"
  # Eigene Git-Konfiguration für den Lauf: nichts aus der von root, und die Quelle gilt als sicher, auch wenn
  # sie einem anderen Benutzer gehört (Runner: sudo auf den Checkout von «runner»). «git -c safe.directory»
  # reicht nicht: beim lokalen Klonen erreicht es upload-pack nicht. (image/tag-pruefen.sh hat eine eigene.)
  GIT_CONFIG_FILE=$(mktemp)
  git config --file "$GIT_CONFIG_FILE" --add safe.directory "$opt_source"
  git config --file "$GIT_CONFIG_FILE" --add safe.directory "$opt_source/.git"
  git config --file "$GIT_CONFIG_FILE" uploadpack.allowAnySHA1InWant true
  export GIT_CONFIG_GLOBAL=$GIT_CONFIG_FILE GIT_CONFIG_NOSYSTEM=1
  git_source rev-parse --git-dir >/dev/null 2>&1 || die "$opt_source ist kein Git-Repo"
  COMMIT=$(git_source rev-parse --verify --quiet "$opt_ref^{commit}") || die "Stand «$opt_ref» gibt es in $opt_source nicht"

  TAG=$(release_tag "$opt_ref")
  check_signature

  # Kanal: folgt dem Tag (Entscheid Zeno: das Image folgt stabil, rc-Images folgen vorschau; dev nie automatisch)
  derived=dev
  if [[ -n "$TAG" ]]; then
    derived=stabil
    if [[ "$TAG" == *-rc* ]]; then derived=vorschau; fi
  fi
  if [[ -z "$opt_channel" ]]; then
    opt_channel=$derived
  elif [[ "$opt_channel" != "$derived" ]] && (( ! TEST_BUILD )); then
    die "Kanal «$opt_channel» passt nicht zu $TAG: Das Image folgt dem Kanal des Tags ($derived)"
  fi
  case "$opt_channel" in
    stabil | vorschau | dev) ;;
    *) die "Ungültiger Kanal «$opt_channel» (erlaubt: stabil, vorschau, dev)" ;;
  esac
  if (( SIGNED )) && [[ "$opt_channel" == "$derived" ]]; then SEED=1; fi

  # Version: die des Tags
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
  if (( opt_mechanics )); then VERSION+=-mechanik; fi
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
  if (( TEST_BUILD && SIGNED && ! SEED )); then info "Testbau mit anderem Kanal als dem des Tags: ohne Zustand ab Werk"; fi
}

preflight() {
  local tool missing="" arch avail_mib need_mib
  (( EUID == 0 )) || die "bauen.sh braucht root (sudo image/bauen.sh …)"

  for tool in curl gpgv sha256sum base64 xz losetup sfdisk partx e2fsck resize2fs dumpe2fs mount umount \
    mountpoint findmnt fstrim chroot git ssh-keygen truncate flock mknod awk stat df cmp; do
    command -v "$tool" >/dev/null || missing+=" $tool"
  done
  if [[ -n "$missing" ]]; then
    die "Es fehlen:$missing (Ubuntu: apt-get install curl gpgv xz-utils e2fsprogs fdisk util-linux mount git openssh-client)"
  fi

  arch=$(uname -m)
  if [[ "$arch" != aarch64 ]]; then
    if [[ -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64; then
      warn "Host ist $arch: der chroot läuft über qemu-user (langsam, nicht getestet)"
    else
      die "Host ist $arch. Gebaut wird auf arm64 (oder mit qemu-user-static für aarch64)."
    fi
  fi

  if [[ ! "$opt_extra_mib" =~ ^[1-9][0-9]*$ ]] || (( opt_extra_mib < 256 )); then
    die "--zusatz-mib braucht eine Zahl ab 256"
  fi
  [[ "$opt_reserve_mib" =~ ^(0|[1-9][0-9]*)$ ]] || die "--reserve-mib braucht eine Zahl"
  [[ "$opt_xz_level" =~ ^[0-9]$ ]] || die "--xz-stufe braucht eine Zahl von 0 bis 9"
  [[ "$opt_ubuntu" =~ ^[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$ ]] || die "Ungültige Ubuntu-Version «$opt_ubuntu»"

  WORK=$(realpath -m -- "$opt_work")
  OUTPUT=$(realpath -m -- "${opt_output:-$WORK/ausgabe}")
  if [[ -n "$opt_cache" ]]; then opt_cache=$(realpath -m -- "$opt_cache"); fi
  local p
  for p in "$WORK" "$OUTPUT" ${opt_cache:+"$opt_cache"}; do
    # findmnt und die Aufräumlogik vertragen keine Leer- und Sonderzeichen
    [[ "$p" =~ ^/[A-Za-z0-9._/+-]+$ && "$p" != / ]] || die "Ungültiger Ordner «$p» (nur A–Z, a–z, 0–9 und ._/+-)"
  done

  mkdir -p -- "$WORK"
  exec 9>"$WORK/.sperre"
  flock -n 9 || die "In $WORK läuft schon ein Image-Bau (oder ein Prozess eines abgebrochenen Laufs arbeitet noch im chroot)"

  avail_mib=$(( $(df -Pk -- "$WORK" | awk 'NR == 2 { print $4 }') / 1024 ))
  if (( opt_mechanics )); then need_mib=7168; else need_mib=11264; fi
  if (( avail_mib < need_mib )); then
    warn "In $WORK sind nur $avail_mib MiB frei, gebraucht werden etwa $need_mib MiB"
  fi

  info "Arbeitsordner $WORK ($avail_mib MiB frei) · Ausgabe $OUTPUT"
  if (( opt_mechanics )); then info "Nur Mechanik: install.sh läuft nicht, das Image ist nicht für Releases"; fi
}

# Reste eines abgebrochenen Laufs im selben Arbeitsordner wegräumen
clean_work() {
  ROOT_MNT="$WORK/wurzel"
  IMG="$WORK/zenos.img"
  local left
  unmount_all 0
  left=$(findmnt -rn -o TARGET | awk -v p="$ROOT_MNT" '$0 == p || index($0, p "/") == 1')
  [[ -z "$left" ]] || die "Unter $ROOT_MNT ist noch etwas eingehängt: $left"
  detach_loops
  mkdir -p -- "$ROOT_MNT"
  rm -f -- "$IMG" "$IMG.teil" "$WORK/install.log" "$WORK/basis.txt"
  rm -rf -- "$WORK/vartmp" "$WORK"/tmp.*
  TMP_DIR=$(mktemp -d "$WORK/tmp.XXXXXX")
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

step "Ubuntu-Grundlage"
select_ubuntu
fetch_ubuntu

step "Entpacken und vergrössern"
xz -dc -T0 -- "$UBUNTU_XZ" > "$IMG.teil"
mv -- "$IMG.teil" "$IMG"
if [[ -z "$opt_cache" ]]; then rm -rf -- "$WORK/download"; fi
read_partitions
info "Ubuntu-Image: $(mib "$(stat -c %s -- "$IMG")"), Root-Partition $(mib $(( P2_SIZE * 512 )))"
truncate -s "+${opt_extra_mib}M" -- "$IMG"
set_partition2 +
attach_loop "$IMG" $(( P2_START * 512 )) $(( P2_SIZE * 512 ))
LOOP_ROOT=$LOOP_DEV
fsck_root "$LOOP_ROOT"
quiet resize2fs -- "$LOOP_ROOT"
info "Root-Partition vergrössert auf $(mib $(( P2_SIZE * 512 )))"

step "Einhängen"
mount_all
RESOLV_ORIGINAL=$(readlink -- "$ROOT_MNT/etc/resolv.conf" 2>/dev/null || true)
setup_resolv
setup_policy
info "Root ${LOOP_ROOT}, Boot ${LOOP_BOOT} unter $ROOT_MNT"

step "zenOS nach /opt/zenos"
prepare_code

if (( opt_mechanics )); then
  step "Mechanik-Test im chroot"
  run_mechanics
else
  step "install.sh --image im chroot"
  run_install
  step "Kennung und Sicherheitsquelle prüfen"
  check_identity
  step "Kanal, Vertrauensanker und Zustand ab Werk"
  prepare_channel
  step "Erster Start und Paketliste"
  prepare_first_boot
  write_package_list
fi

step "Aufräumen im Image"
clean_image

step "Aushängen und verkleinern"
unmount_all 1
wait_device_free "$LOOP_ROOT"
shrink_image

step "Packen"
compress_image
{
  printf 'ubuntu_datei=%s\n' "$UBUNTU_FILE"
  printf 'ubuntu_sha256=%s\n' "$UBUNTU_SHA"
  printf 'ubuntu_quelle=%s\n' "$UBUNTU_URL"
  printf 'zenos_version=%s\n' "$VERSION"
  printf 'zenos_commit=%s\n' "$COMMIT"
  printf 'kanal=%s\n' "$opt_channel"
  printf 'tag=%s\n' "$TAG"
  if (( SIGNED )); then printf 'signatur=%s\n' "$SIG_KEY"; else printf 'signatur=keine (Testbau)\n'; fi
  printf 'anker_serie=%s\n' "$SIG_SERIES"
  printf 'image_groesse=%s\n' "$IMAGE_SIZE"
  printf 'image_sha256=%s\n' "$IMAGE_SHA"
} > "$WORK/basis.txt"
rm -f -- "$IMG"
rm -rf -- "$WORK/vartmp"
DONE=1

step "Fertig"
info "$OUTPUT_FILE"
if [[ -f "$OUTPUT/zenos-$VERSION-pi5-arm64.pakete.txt" ]]; then info "$OUTPUT/zenos-$VERSION-pi5-arm64.pakete.txt"; fi
info "$OUTPUT/SHA256SUMS"
if (( WARNINGS > 0 )); then info "$WARNINGS Warnung(en), siehe oben"; fi
