# Bauumgebung für zenOS 1.0: Debian 13 «trixie» arm64 mit mkosi, systemd-repart und QEMU.
# Läuft auf dem Mac in der Colima-VM «zenos» (Docker-Kontext colima-zenos), gestartet von mkosi/bauen.sh.
# Das Basis-Image ist über seinen Digest festgelegt, damit jeder Bau dieselbe Umgebung hat.
FROM debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6

ARG DEBIAN_FRONTEND=noninteractive

# mkosi und was es für Debian-Images braucht (apt, Schlüsselring, bubblewrap als Sandbox, repart, ukify),
# die Werkzeuge für die Dateisysteme (erofs für das schreibgeschützte System, vfat für die Bootpartition),
# dtc und fdtoverlay für das eigene Overlay des Deckels (mkosi/start/zenos-deckel.dts),
# QEMU mit UEFI-Firmware für die Angriffstests und python3-pexpect, um die Konsole im Test zu bedienen.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      mkosi apt dpkg debian-archive-keyring gpg gpgv bubblewrap \
      systemd systemd-container systemd-repart systemd-ukify systemd-boot-efi \
      erofs-utils dosfstools mtools cryptsetup-bin e2fsprogs fdisk util-linux \
      kmod cpio zstd xz-utils device-tree-compiler \
      qemu-system-arm qemu-efi-aarch64 qemu-utils \
      python3 python3-pexpect \
      ca-certificates curl git jq \
 && rm -rf /var/lib/apt/lists/*
