#!/usr/bin/env bash
# container-bauen.sh – baut das Installations-ISO im Container ubuntu:26.04 (GitHub Actions, x86.yml und image.yml):
# installiert die Werkzeuge für image/x86/bauen.sh und ruft es mit allen Argumenten auf. Der Container muss
# privilegiert laufen (chroot, overlayfs, Einhängen).
#
#   docker run --privileged … ubuntu:26.04 /quelle/image/x86/container-bauen.sh [Optionen von bauen.sh]
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

apt-get -q update
apt-get -q -y install --no-install-recommends \
  debootstrap squashfs-tools xorriso dosfstools mtools git openssh-client python3 ubuntu-keyring ca-certificates \
  util-linux mount kmod
exec "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/bauen.sh" "$@"
