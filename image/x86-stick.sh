#!/usr/bin/env bash
# x86-stick.sh – baut den Installer-Stick von zenOS für x86-Rechner (amd64): das offizielle ISO von Ubuntu Desktop mit
# seinem grafischen Installer, dazu die Einrichtung von zenOS (image/x86/). Das Ergebnis schreibst du mit balenaEtcher
# (oder dd) auf einen USB-Stick, mindestens 8 GB.
#
#   image/x86-stick.sh [--ref vX.Y.Z[-rcN]] [optionen]
#
# Ablauf:
#   1. Stand: ein Release-Tag, gültig signiert (image/tag-pruefen.sh gegen die feste Wurzel von zenOS). Ohne --ref der
#      Release-Tag auf HEAD. Kanal und Version folgen dem Tag wie beim Pi-Image (vX.Y.Z → stabil, -rcN → vorschau).
#   2. Ubuntu: SHA256SUMS und SHA256SUMS.gpg von releases.ubuntu.com, Signatur mit gpgv gegen den «Ubuntu CD Image
#      Automatic Signing Key (2012)» (fest unten, dieselbe Kopie wie in image/bauen.sh), neueste Punktversion von
#      ubuntu-<version>*-desktop-amd64.iso, Download in den Cache und Prüfsumme.
#   3. Auf das ISO kommen /autoinstall.yaml und /zenos/ (einrichten.sh, README, stand, zenos.bundle), alles aus dem
#      Commit des Tags, nicht aus dem Arbeitsstand. Bootteile bleiben unverändert (xorriso «-boot_image any replay»):
#      Der Stick startet mit UEFI und Secure Boot wie das ISO von Ubuntu, und im BIOS-Modus.
#   4. Anpassung an zenOS (image/x86/installer/): eine zusätzliche Schicht des Live-Systems
#      /casper/minimal.standard.live.zenos.squashfs mit /usr/share/desktop-provision/ (whitelabel.yaml mit den Farben
#      aus shell/theme/tokens.json, das Zeichen von zenOS als Bilder, eigene Folien während der Installation). Das
#      Startmenü heisst «zenOS installieren» und lädt die Schicht über layerfs-path; md5sum.txt kennt die geänderten
#      Dateien, damit die Prüfung des Mediums nicht anschlägt. Die Schichten von Ubuntu bleiben unverändert.
#   5. Ergebnis zenos-<version>-x86-installer.iso und daneben die Prüfsumme (.sha256).
# Am Rechner zeigt der grafische Installer von Ubuntu die gewohnten Schritte im Look von zenOS (mit Verschlüsselung); am
# Ende richtet er zenOS ein. GNOME aus Ubuntu Desktop bleibt installiert, den Login übernimmt zenOS (greetd). Die Texte
# des Installers bleiben die von Ubuntu.
# Das fertige ISO (rund 6,5 GB) ist grösser als 2 GiB und liegt deshalb nicht im Release: Jeder baut es selbst aus dem
# offiziellen Ubuntu-ISO. So wird auch kein verändertes Ubuntu-Image weitergegeben.
#
# Optionen:
#   --ref REF          Stand: ein Release-Tag (Standard: der Release-Tag auf HEAD)
#   --quelle ORDNER    Git-Repo mit zenOS (Standard: das Repo dieses Skripts)
#   --ausgabe ORDNER   Ziel für ISO und Prüfsumme (Standard: der aktuelle Ordner)
#   --cache ORDNER     Ubuntu-ISO dort behalten und wiederverwenden (Standard: ~/.cache/zenos/ubuntu)
#   --ubuntu V         Ubuntu-Version auf releases.ubuntu.com (Standard: 26.04, neueste Punktversion)
#   --testbau-ohne-signatur
#                      nur für Tests: Stand ohne gültig signierten Tag (Zweig, HEAD, unsignierter Tag), Kanal dev,
#                      Version mit «-testbau», ohne Zustand ab Werk. Nie für den Alltag
#   --nur-pruefen      nur Stand, Signatur, Kanal und Version zeigen, ohne Download und ohne Bau
#   --nur-anpassung ORDNER
#                      nur für Tests: legt den Inhalt der Schicht (usr/share/desktop-provision/…) unter ORDNER an,
#                      ohne Download und ohne ISO
#   -h, --hilfe        diese Hilfe
#
# Braucht git, curl, gpgv (Paket gpgv bzw. gnupg), xorriso, mksquashfs (squashfs-tools), python3, ssh-keygen,
# sha256sum oder shasum und md5sum oder md5. Läuft ohne root, unter Linux und auf dem Mac (bash 3.2; xorriso, gnupg und
# squashfs aus Homebrew).
# Exit 0 gebaut (bzw. geprüft), 1 Fehler, 2 falscher Aufruf.

set -uo pipefail
export LC_ALL=C

SKRIPT_ORDNER=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ORDNER=$(cd -- "$SKRIPT_ORDNER/.." && pwd -P)

UBUNTU_BASIS=https://releases.ubuntu.com
# «Ubuntu CD Image Automatic Signing Key (2012) <cdimage@ubuntu.com>» signiert SHA256SUMS der Ubuntu-Images
CDIMAGE_FINGERPRINT=843938DF228D22F7B3742BC0D94AA3F0EFE21092
VERSION_ERE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'

opt_ref=""
opt_quelle=$REPO_ORDNER
opt_ausgabe=$PWD
opt_cache=${XDG_CACHE_HOME:-$HOME/.cache}/zenos/ubuntu
opt_ubuntu=26.04
opt_testbau=0
opt_nur_pruefen=0
opt_nur_anpassung=""
# Zusätzliche Schicht des Live-Systems: casper hängt sie über layerfs-path an die Schicht minimal.standard.live
SCHICHT=minimal.standard.live.zenos.squashfs

TMP=""

hilfe() {
  sed -n '2,/^# Exit 0/{s/^# \{0,1\}//;p;}' -- "${BASH_SOURCE[0]}"
}

info() { printf '   %s\n' "$*"; }
schritt() { printf '\n── %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
die() {
  printf '\nx86-stick.sh: %s\n' "$*" >&2
  exit 1
}

aufraeumen() {
  if [[ -n "$TMP" ]]; then rm -rf -- "$TMP"; fi
}

# Hash einer Datei (Linux: sha256sum, Mac: shasum)
sha256_von() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{ print $1 }'
  else
    shasum -a 256 -- "$1" | awk '{ print $1 }'
  fi
}

groesse_von() { wc -c < "$1" | tr -d ' '; }

# MD5 einer Datei für md5sum.txt des ISOs (Linux: md5sum, Mac: md5)
md5_von() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum -- "$1" | awk '{ print $1 }'
  else
    md5 -q -- "$1"
  fi
}

# Nur https; «gross»: auch nach abgerissenen Verbindungen weiterladen
laden() { # URL ZIEL [gross]
  local -a optionen=(--silent --show-error)
  if [[ "${3:-}" == gross ]]; then
    if [[ -t 2 ]]; then optionen=(--progress-bar); fi
    optionen+=(--retry-all-errors --continue-at -)
  fi
  curl "${optionen[@]}" --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 30 --retry 5 --retry-delay 10 --output "$2" -- "$1"
}

g() { git -C "$opt_quelle" "$@"; }

# Zugangsdaten aus der URL entfernen, GitHub-SSH als HTTPS (wie image/bauen.sh)
saubere_url() {
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

# Dieselbe Kopie wie cdimage_keyring in image/bauen.sh (test/einheiten/x86-stick.test.py hält beide gleich)
cdimage_keyring() {
  base64 -d 2>/dev/null <<'EOF' || base64 -D <<'EOF2'
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
EOF2
}

optionen_lesen() {
  while (( $# > 0 )); do
    case "$1" in
      -h | --hilfe | --help) hilfe; exit 0 ;;
      --testbau-ohne-signatur) opt_testbau=1; shift; continue ;;
      --nur-pruefen) opt_nur_pruefen=1; shift; continue ;;
      --ref | --quelle | --ausgabe | --cache | --ubuntu | --nur-anpassung)
        if (( $# < 2 )); then
          printf 'x86-stick.sh: %s braucht einen Wert\n' "$1" >&2
          exit 2
        fi
        ;;
      *) printf 'x86-stick.sh: unbekannte Option «%s» (Hilfe: --hilfe)\n' "$1" >&2; exit 2 ;;
    esac
    case "$1" in
      --ref) opt_ref=$2 ;;
      --quelle) opt_quelle=$2 ;;
      --ausgabe) opt_ausgabe=$2 ;;
      --cache) opt_cache=$2 ;;
      --ubuntu) opt_ubuntu=$2 ;;
      --nur-anpassung) opt_nur_anpassung=$2 ;;
    esac
    shift 2
  done
  [[ "$opt_ubuntu" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'x86-stick.sh: --ubuntu wie 26.04\n' >&2; exit 2; }
}

werkzeuge_pruefen() {
  local w
  for w in git ssh-keygen; do
    command -v "$w" >/dev/null 2>&1 || die "$w fehlt"
  done
  (( opt_nur_pruefen )) && return 0
  command -v python3 >/dev/null 2>&1 || die "python3 fehlt"
  [[ -z "$opt_nur_anpassung" ]] || return 0
  for w in curl gpgv xorriso mksquashfs; do
    command -v "$w" >/dev/null 2>&1 ||
      die "$w fehlt (Linux: sudo apt install curl gpgv xorriso squashfs-tools · Mac: brew install gnupg xorriso squashfs)"
  done
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || die "sha256sum oder shasum fehlt"
  command -v md5sum >/dev/null 2>&1 || command -v md5 >/dev/null 2>&1 || die "md5sum oder md5 fehlt"
}

# Stand, Tag und Signatur, Kanal, Version und origin
stand_bestimmen() {
  local name ausgabe rc=0 kandidat
  opt_quelle=$(cd -- "$opt_quelle" 2>/dev/null && pwd -P) || die "Quelle gibt es nicht"
  g rev-parse --git-dir >/dev/null 2>&1 || die "$opt_quelle ist kein Git-Repo"

  # Ohne --ref: der Release-Tag auf HEAD (liegen vX.Y.Z und vX.Y.Z-rcN auf demselben Commit, die Endversion)
  if [[ -z "$opt_ref" ]]; then
    while read -r kandidat; do
      [[ "$kandidat" =~ $VERSION_ERE ]] || continue
      if [[ -z "$opt_ref" || ( "$opt_ref" == *-rc* && "$kandidat" != *-rc* ) ]]; then opt_ref=$kandidat; fi
    done < <(g tag --points-at HEAD)
    if [[ -z "$opt_ref" ]]; then
      (( opt_testbau )) || die "HEAD ist kein Release-Tag. Mit --ref vX.Y.Z[-rcN] einen wählen (git fetch --tags; Testbau: --testbau-ohne-signatur)"
      opt_ref=HEAD
    fi
  fi
  COMMIT=$(g rev-parse --verify --quiet "$opt_ref^{commit}") || die "Stand «$opt_ref» gibt es in $opt_quelle nicht"
  REF_VOLL=$(g rev-parse --symbolic-full-name --verify --quiet "$opt_ref" 2>/dev/null) || REF_VOLL=""
  if [[ -z "$REF_VOLL" && "$opt_ref" == HEAD ]]; then REF_VOLL=HEAD; fi

  TAG=""
  name=${opt_ref#refs/tags/}
  if [[ "$name" =~ $VERSION_ERE ]] && g rev-parse --verify --quiet "refs/tags/$name" >/dev/null 2>&1; then
    TAG=$name
    REF_VOLL=refs/tags/$name
  fi
  [[ -n "$REF_VOLL" ]] || die "«$opt_ref» ist kein Zweig und kein Tag (ein Bundle braucht einen Namen; z. B. HEAD)"

  SIGNIERT=0
  if [[ -n "$TAG" ]]; then
    ausgabe=$("$SKRIPT_ORDNER/tag-pruefen.sh" --quelle "$opt_quelle" --commit "$COMMIT" "$TAG") || rc=$?
    if (( rc == 0 )); then
      SIGNIERT=1
      SCHLUESSEL=$(printf '%s\n' "$ausgabe" | sed -n 's/^schluessel=//p')
    elif (( opt_testbau )); then
      warn "Testbau: Der Tag $TAG ist nicht gültig signiert (Exit $rc, Grund oben)"
    else
      die "Der Tag $TAG ist nicht gültig signiert (image/tag-pruefen.sh, Exit $rc, Grund oben). Kein Stick."
    fi
  else
    (( opt_testbau )) || die "«$opt_ref» ist kein Release-Tag vX.Y.Z oder vX.Y.Z-rcN. Gebaut wird nur ein gültig signierter Tag"
    warn "Testbau: «$opt_ref» ist kein Release-Tag, die Signatur wird nicht geprüft"
  fi

  # Kanal wie beim Pi-Image: vX.Y.Z → stabil, -rcN → vorschau; ohne gültige Signatur dev
  KANAL=dev
  if (( SIGNIERT )); then
    KANAL=stabil
    if [[ "$TAG" == *-rc* ]]; then KANAL=vorschau; fi
  fi
  if [[ -n "$TAG" ]]; then
    VERSION=${TAG#v}
  else
    VERSION=$(g describe --tags --always "$COMMIT")
    VERSION=${VERSION#v}
  fi
  if (( opt_testbau && ! SIGNIERT )); then VERSION+=-testbau; fi
  [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+_-]*$ ]] || die "Ungültige Version «$VERSION»"

  ORIGIN=$(saubere_url "$(g remote get-url origin 2>/dev/null || true)")
  if [[ -n "$ORIGIN" && ! "$ORIGIN" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9._/-]+$ ]]; then
    warn "origin «$ORIGIN» ist keine https-Adresse; /opt/zenos bekommt keinen origin"
    ORIGIN=""
  fi

  # Der Stand muss den Stick kennen (ab v0.1.0-rc8)
  for name in image/x86/autoinstall.yaml image/x86/einrichten.sh image/x86/README; do
    g cat-file -e "$COMMIT:$name" 2>/dev/null || die "Der Stand ${COMMIT:0:12} hat $name noch nicht (den x86-Stick gibt es ab v0.1.0-rc8)"
  done

  info "zenOS $VERSION · Stand ${COMMIT:0:12} · Kanal $KANAL${TAG:+ · Tag $TAG}"
  if (( SIGNIERT )); then
    info "Tag $TAG gültig signiert (Release-Schlüssel $SCHLUESSEL)"
  else
    info "Testbau ohne gültige Signatur: nicht für den Alltag, ohne Zustand ab Werk"
  fi
  info "origin für zen update: ${ORIGIN:-keiner}"
}

# SHA256SUMS laden und prüfen, neueste Punktversion wählen → ISO_NAME, ISO_SHA, ISO_URL
ubuntu_waehlen() {
  local ordner="$UBUNTU_BASIS/$opt_ubuntu" summen="$TMP/SHA256SUMS" sig="$TMP/SHA256SUMS.gpg" status="$TMP/gpgv.status"
  local hash name punkt bester=-1 muster unterzeichner
  info "Quelle: $ordner/"
  laden "$ordner/SHA256SUMS" "$summen" || die "SHA256SUMS nicht erreichbar – gibt es Ubuntu $opt_ubuntu auf releases.ubuntu.com?"
  laden "$ordner/SHA256SUMS.gpg" "$sig" || die "SHA256SUMS.gpg nicht erreichbar"
  cdimage_keyring > "$TMP/cdimage.gpg" || die "Schlüssel nicht lesbar (base64)"
  mkdir -m 0700 -- "$TMP/gnupg"
  if ! gpgv --homedir "$TMP/gnupg" --keyring "$TMP/cdimage.gpg" --status-fd 3 "$sig" "$summen" \
    3>"$status" >"$TMP/gpgv.log" 2>&1; then
    sed 's/^/     /' -- "$TMP/gpgv.log" >&2
    die "Die Signatur von SHA256SUMS stimmt nicht"
  fi
  unterzeichner=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3; print $NF }' "$status")
  printf '%s\n' "$unterzeichner" | grep -qxF -- "$CDIMAGE_FINGERPRINT" ||
    die "SHA256SUMS ist nicht mit dem Ubuntu-CD-Schlüssel $CDIMAGE_FINGERPRINT signiert"
  info "Signatur von SHA256SUMS gültig (Ubuntu CD Image Signing Key ${CDIMAGE_FINGERPRINT: -16})"

  muster="^ubuntu-${opt_ubuntu//./\\.}(\\.([0-9]+))?-desktop-amd64\\.iso\$"
  ISO_NAME=""
  while read -r hash name; do
    name=${name#\*}
    [[ "$hash" =~ ^[0-9a-f]{64}$ && "$name" =~ $muster ]] || continue
    punkt=${BASH_REMATCH[2]:-0}
    if (( punkt > bester )); then
      bester=$punkt
      ISO_NAME=$name
      ISO_SHA=$hash
    fi
  done < "$summen"
  [[ -n "$ISO_NAME" ]] || die "In SHA256SUMS steht kein Desktop-ISO für amd64 (Ubuntu $opt_ubuntu)"
  ISO_URL="$ordner/$ISO_NAME"
  info "Gewählt: $ISO_NAME"
}

ubuntu_laden() {
  mkdir -p -- "$opt_cache" || die "Cache $opt_cache lässt sich nicht anlegen"
  ISO="$opt_cache/$ISO_NAME"
  if [[ -f "$ISO" ]]; then
    if [[ "$(sha256_von "$ISO")" == "$ISO_SHA" ]]; then
      info "Schon geladen und geprüft: $ISO"
      return 0
    fi
    warn "Vorhandene Datei hat eine andere Prüfsumme, lade neu: $ISO"
    rm -f -- "$ISO"
  fi
  info "Lade $ISO_NAME (rund 6,5 GB)"
  laden "$ISO_URL" "$ISO.teil" gross || die "Download von $ISO_URL fehlgeschlagen (nochmals starten setzt fort)"
  if [[ "$(sha256_von "$ISO.teil")" != "$ISO_SHA" ]]; then
    rm -f -- "$ISO.teil"
    die "Die Prüfsumme von $ISO_NAME stimmt nicht mit SHA256SUMS überein"
  fi
  mv -- "$ISO.teil" "$ISO"
  info "Prüfsumme stimmt: ${ISO_SHA:0:16}…"
}

# /autoinstall.yaml und /zenos/ aus dem Commit des Stands
stick_inhalt() {
  local ordner="$TMP/stick/zenos" name
  mkdir -p -- "$ordner"
  g show "$COMMIT:image/x86/autoinstall.yaml" > "$TMP/stick/autoinstall.yaml"
  g show "$COMMIT:image/x86/einrichten.sh" > "$ordner/einrichten.sh"
  g show "$COMMIT:image/x86/README" > "$ordner/README"
  chmod 0755 -- "$ordner/einrichten.sh"
  {
    printf '# zenOS-Installer-Stick: Stand für image/x86/einrichten.sh (geschrieben von image/x86-stick.sh)\n'
    printf 'tag=%s\ncommit=%s\nkanal=%s\nversion=%s\norigin=%s\nsigniert=%s\n' \
      "$TAG" "$COMMIT" "$KANAL" "$VERSION" "$ORIGIN" "$SIGNIERT"
  } > "$ordner/stand"
  # Der Stand und alle Tags (für zen rollback), keine anderen Zweige
  g bundle create --quiet "$ordner/zenos.bundle" "$REF_VOLL" --tags 2>"$TMP/bundle.log" ||
    { sed 's/^/     /' -- "$TMP/bundle.log" >&2; die "git bundle ist gescheitert"; }
  g bundle verify --quiet "$ordner/zenos.bundle" >/dev/null 2>&1 || die "Das Bundle ist nicht lesbar"
  for name in autoinstall.yaml zenos/einrichten.sh zenos/README zenos/stand zenos/zenos.bundle; do
    [[ -s "$TMP/stick/$name" ]] || die "$name ist leer"
  done
  info "autoinstall.yaml, zenos/einrichten.sh, README, stand und Bundle ($(( $(groesse_von "$ordner/zenos.bundle") / 1024 )) KiB)"
}

# Farben für den Installer aus shell/theme/tokens.json des Stands: Akzent (Standard «salbei»), Grund, Text, Fläche.
# Ausgabe «NAME=#RRGGBB» je Zeile. Die Werte prüft das Programm (nur #RRGGBB), sonst Abbruch.
farben_lesen() {
  g show "$COMMIT:shell/theme/tokens.json" | python3 -I -c '
import json, re, sys
t = json.load(sys.stdin)
f = t["farben"]
a = f["akzente"][f["standardAkzent"]]
werte = {"AKZENT_HELL": a["hell"], "AKZENT_DUNKEL": a["dunkel"],
         "KNOPFTEXT_HELL": f["hell"]["flaeche"], "KNOPFTEXT_DUNKEL": f["dunkel"]["grund"],
         "GRUND": f["dunkel"]["grund"], "TEXT": f["dunkel"]["text"], "TEXT2": f["dunkel"]["gedaempft"]}
for name, wert in werte.items():
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", wert):
        sys.exit("Farbe %s ist kein #RRGGBB: %r" % (name, wert))
    print("%s=%s" % (name, wert))
' || die "Farben aus shell/theme/tokens.json nicht lesbar"
}

# Inhalt der Schicht unter ZIEL: usr/share/desktop-provision (whitelabel.yaml mit den Farben, Bilder, Folien, der Look der
# Live-Sitzung) und etc/xdg/autostart/zenos-live-look.desktop
anpassung_anlegen() { # ZIEL
  local ziel=$1/usr/share/desktop-provision vorlage text name wert nr sprache titel z1 z2 html land
  local -a farben=()
  mkdir -p -- "$ziel/images" "$ziel/slides"
  while IFS= read -r wert; do farben+=("$wert"); done < <(farben_lesen)
  (( ${#farben[@]} == 7 )) || die "Farben aus shell/theme/tokens.json unvollständig"

  text=$(g show "$COMMIT:image/x86/installer/whitelabel.yaml") || die "image/x86/installer/whitelabel.yaml fehlt im Stand"
  for wert in "${farben[@]}"; do text=${text//@${wert%%=*}@/${wert#*=}}; done
  [[ "$text" != *@[A-Z]*@* ]] || die "whitelabel.yaml: Platzhalter ohne Farbe"
  printf '%s\n' "$text" > "$ziel/whitelabel.yaml"

  for name in zenos-schriftzug-hell.svg zenos-schriftzug-dunkel.svg zenos-zeichen-hell.svg zenos-zeichen-dunkel.svg; do
    g show "$COMMIT:assets/zeichen/$name" > "$ziel/images/$name" || die "assets/zeichen/$name fehlt im Stand"
  done

  vorlage=$(g show "$COMMIT:image/x86/installer/folie.html.in") || die "image/x86/installer/folie.html.in fehlt"
  for wert in "${farben[@]}"; do vorlage=${vorlage//@${wert%%=*}@/${wert#*=}}; done
  while IFS='|' read -r nr sprache titel z1 z2; do
    case "$nr" in '' | '#'*) continue ;; esac
    [[ "$nr" =~ ^[1-9]$ && "$sprache" =~ ^(de|en)$ && -n "$titel" && -n "$z1" ]] ||
      die "image/x86/installer/folien.txt: Zeile «$nr|$sprache|…» ungültig"
    case "$titel$z1$z2" in *'<'* | *'>'* | *'&'*) die "folien.txt: kein HTML in den Texten (Folie $nr)" ;; esac
    html=${vorlage//@TITEL@/$titel}
    html=${html//@ZEILE1@/$z1}
    html=${html//@ZEILE2@/$z2}
    mkdir -p -- "$ziel/slides/$nr"
    g show "$COMMIT:assets/zeichen/zenos-zeichen-dunkel.svg" > "$ziel/slides/$nr/zenos-zeichen.svg"
    if [[ "$sprache" == de ]]; then
      for land in DE CH AT; do printf '%s\n' "$html" > "$ziel/slides/$nr/slide_de_$land.html"; done
    else
      printf '%s\n' "$html" > "$ziel/slides/$nr/slide_en_US.html"
    fi
  done < <(g show "$COMMIT:image/x86/installer/folien.txt")
  for nr in "$ziel"/slides/*; do
    [[ -f "$nr/slide_en_US.html" ]] || die "Folie ${nr##*/} hat keinen englischen Rückfall (slide_en_US.html)"
  done
  # Live-Sitzung: dunkles Farbschema und die Grundfarbe von zenOS statt des Hintergrunds von Ubuntu
  text=$(g show "$COMMIT:image/x86/installer/live-look.sh.in") || die "image/x86/installer/live-look.sh.in fehlt"
  for wert in "${farben[@]}"; do text=${text//@${wert%%=*}@/${wert#*=}}; done
  printf '%s\n' "$text" > "$ziel/zenos-live-look"
  mkdir -p -- "$1/etc/xdg/autostart"
  g show "$COMMIT:image/x86/installer/live-look.desktop" > "$1/etc/xdg/autostart/zenos-live-look.desktop" ||
    die "image/x86/installer/live-look.desktop fehlt"
  find "$1" -type d -exec chmod 0755 {} + && find "$1" -type f -exec chmod 0644 {} +
  chmod 0755 -- "$ziel/zenos-live-look"
}

# Schicht, Startmenü und md5sum.txt für das ISO
installer_anpassen() {
  local menue="$TMP/grub.cfg" summen="$TMP/md5sum.txt" eintraege
  xorriso -indev "$ISO" -ls /casper/minimal.standard.live.squashfs >/dev/null 2>&1 ||
    die "Im ISO fehlt /casper/minimal.standard.live.squashfs: Aufbau unbekannt, die Schicht von zenOS passte nicht"
  anpassung_anlegen "$TMP/schicht"
  mkdir -p -- "$TMP/stick/casper"
  mksquashfs "$TMP/schicht" "$TMP/stick/casper/$SCHICHT" -noappend -all-root -comp xz >"$TMP/mksquashfs.log" 2>&1 ||
    { sed 's/^/     /' -- "$TMP/mksquashfs.log" >&2; die "mksquashfs ist gescheitert"; }

  # Startmenü: «zenOS installieren», jede Kernel-Zeile lädt die Schicht dazu
  xorriso -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg "$menue.ubuntu" -extract /md5sum.txt "$summen.ubuntu" \
    >/dev/null 2>&1 || die "grub.cfg oder md5sum.txt im ISO nicht lesbar"
  chmod u+w -- "$menue.ubuntu" "$summen.ubuntu"
  sed -e 's|^menuentry "Try or Install Ubuntu" {|menuentry "zenOS installieren" {|' \
    -e 's|^menuentry "Ubuntu (safe graphics)" {|menuentry "zenOS installieren (einfache Grafik)" {|' \
    -e "s|^\([[:space:]]*linux[[:space:]][[:space:]]*/casper/vmlinuz\)|\1 layerfs-path=$SCHICHT|" \
    -- "$menue.ubuntu" > "$menue"
  eintraege=$(grep -c '^[[:space:]]*linux[[:space:]].*/casper/vmlinuz' "$menue")
  if (( eintraege == 0 )) || (( $(grep -c "layerfs-path=$SCHICHT" "$menue") != eintraege )) ||
    ! grep -q '^menuentry "zenOS installieren" {' "$menue"; then
    die "Das Startmenü des ISOs sieht anders aus als erwartet (boot/grub/grub.cfg)"
  fi

  # md5sum.txt: neue Prüfsumme für grub.cfg, die Schicht dazu (die Prüfung beim Start meldet sonst einen Fehler)
  awk -v neu="$(md5_von "$menue")" '$2 == "./boot/grub/grub.cfg" { print neu "  " $2; next } { print }' \
    "$summen.ubuntu" > "$summen"
  printf '%s  ./casper/%s\n' "$(md5_von "$TMP/stick/casper/$SCHICHT")" "$SCHICHT" >> "$summen"
  info "Schicht $SCHICHT ($(( $(groesse_von "$TMP/stick/casper/$SCHICHT") / 1024 )) KiB), Startmenü «zenOS installieren»"
}

iso_bauen() {
  local ziel
  mkdir -p -- "$opt_ausgabe" || die "Ausgabe $opt_ausgabe lässt sich nicht anlegen"
  opt_ausgabe=$(cd -- "$opt_ausgabe" && pwd -P)
  ziel="$opt_ausgabe/zenos-$VERSION-x86-installer.iso"
  rm -f -- "$ziel" "$ziel.teil" "$ziel.sha256"
  if ! xorriso -indev "$ISO" -outdev "$ziel.teil" \
    -map "$TMP/stick/autoinstall.yaml" /autoinstall.yaml \
    -map "$TMP/stick/zenos" /zenos \
    -map "$TMP/stick/casper/$SCHICHT" "/casper/$SCHICHT" \
    -map "$TMP/grub.cfg" /boot/grub/grub.cfg \
    -map "$TMP/md5sum.txt" /md5sum.txt \
    -boot_image any replay >"$TMP/xorriso.log" 2>&1; then
    sed 's/^/     /' -- "$TMP/xorriso.log" >&2
    rm -f -- "$ziel.teil"
    die "xorriso ist gescheitert"
  fi
  mv -- "$ziel.teil" "$ziel"
  (cd -- "$opt_ausgabe" && printf '%s  %s\n' "$(sha256_von "$ziel")" "$(basename -- "$ziel")" > "$ziel.sha256")
  ERGEBNIS=$ziel
  info "$(basename -- "$ziel"): $(( $(groesse_von "$ziel") / 1048576 )) MiB"
  info "SHA-256 $(cut -c1-16 < "$ziel.sha256")… in $(basename -- "$ziel").sha256"
}

main() {
  optionen_lesen "$@"
  werkzeuge_pruefen
  schritt "Stand und Signatur"
  stand_bestimmen
  if (( opt_nur_pruefen )); then
    printf 'tag=%s\ncommit=%s\nkanal=%s\nversion=%s\nsigniert=%s\n' "$TAG" "$COMMIT" "$KANAL" "$VERSION" "$SIGNIERT"
    exit 0
  fi
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/zenos-x86-stick.XXXXXX") || die "Temp-Ordner fehlt"
  trap aufraeumen EXIT
  if [[ -n "$opt_nur_anpassung" ]]; then
    anpassung_anlegen "$opt_nur_anpassung"
    exit 0
  fi
  schritt "Ubuntu-Desktop-ISO"
  ubuntu_waehlen
  ubuntu_laden
  schritt "Inhalt für den Stick"
  stick_inhalt
  installer_anpassen
  schritt "ISO bauen"
  iso_bauen
  schritt "Fertig: $ERGEBNIS"
  cat <<EOF
   Weiter (ANLEITUNG.md, Abschnitt «x86»):
   1. Mit balenaEtcher auf einen USB-Stick schreiben (mindestens 8 GB; alles darauf wird gelöscht).
   2. Am Rechner vom Stick starten (Boot-Menü, oft F9, F12 oder Esc). Secure Boot darf an bleiben.
   3. Im Startmenü «zenOS installieren». Im Installer Sprache, Tastatur und Netz (Kabel empfohlen).
   4. Festplatte: «Festplatte löschen und Ubuntu installieren», unter «Erweiterte Funktionen» «LVM und Verschlüsselung».
   5. Konto (Name, Rechnername, Benutzer, Passwort) und Zeitzone.
   6. Danach richtet der Installer zenOS ein (20 bis 40 Minuten, Netz nötig). Neu starten: Es kommt der Login von zenOS.
EOF
}

main "$@"
