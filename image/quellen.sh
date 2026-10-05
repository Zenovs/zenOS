#!/usr/bin/env bash
# quellen.sh – holt den Quellcode aller Pakete eines zenOS-Images und packt ihn in Teile für die Release-Seite.
#
#   image/quellen.sh PAKETLISTE ZIELORDNER [--version V] [--teilgroesse MiB]
#
# Warum: Das Image gibt GPL-Software als Binärpakete weiter. Das ist nur zusammen mit dem Quellcode in genau den
# ausgelieferten Versionen erlaubt (GPLv2 §3, GPLv3 §6), auf derselben Seite wie das Image und so lange wie dieses.
#
# PAKETLISTE ist zenos-<version>-pi5-arm64.pakete.txt aus image/bauen.sh: je Zeile Paket, Version, Quellpaket,
# Quellversion (Tab). Je Paar (Quellpaket, Quellversion) holt das Skript die .dsc samt Dateien:
#   1. «apt-get source --download-only» aus dem Ubuntu-Archiv (ports.ubuntu.com, alle Komponenten, resolute,
#      -updates, -security) mit eigener apt-Konfiguration, ohne Root. apt prüft die Signatur der Release-Datei und
#      die Prüfsummen aus Sources.
#   2. Fehlt die Version dort (ersetzt durch ein Update), von Launchpad (getPublishedSources, sourceFileUrls über
#      https). Geprüft wird jede Datei gegen Checksums-Sha256 aus der .dsc.
# Fehlt eine Quelle in beiden, endet das Skript mit Exit 1: Ohne vollständige Quellen gibt es kein Release.
# Dazu Quickshell als git archive am Commit aus scripts/module/25-quickshell.sh (geprüft nach dem Klonen).
#
# Ergebnis in ZIELORDNER: zenos-<v>-quellen-teil<N>.tar (ganze Quellpakete, je Teil höchstens --teilgroesse MiB,
# Standard 1900: GitHub nimmt Release-Dateien nur unter 2 GiB an), zenos-<v>-quickshell-<qv>.tar und
# zenos-<v>-QUELLEN.txt (Herkunft jedes Paars). Läuft auf Ubuntu mit apt, curl, jq, git und tar (GitHub-Runner).

set -Eeuo pipefail
umask 022
export LC_ALL=C.UTF-8

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
REPO_DIR=$(cd -- "$(dirname -- "$SCRIPT")/.." && pwd -P)

readonly ARCHIVE=http://ports.ubuntu.com/ubuntu-ports
readonly SUITE=resolute
readonly KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
readonly LAUNCHPAD=https://api.launchpad.net/1.0/ubuntu/+archive/primary
readonly QUICKSHELL_URLS=(https://git.outfoxxed.me/quickshell/quickshell https://github.com/quickshell-mirror/quickshell)

usage() { sed -n '3,5p' "$SCRIPT" | sed 's/^# \{0,1\}//'; }
die() {
  printf 'quellen.sh: %s\n' "$*" >&2
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then printf '::error::%s\n' "$*"; fi
  exit 1
}
info() { printf '   %s\n' "$*"; }

list="" target="" version="" part_mib=1900
while (( $# > 0 )); do
  case "$1" in
    -h | --hilfe) usage; exit 0 ;;
    --version) [[ $# -ge 2 ]] || die "--version braucht einen Wert"; version=$2; shift 2 ;;
    --teilgroesse) [[ $# -ge 2 ]] || die "--teilgroesse braucht einen Wert"; part_mib=$2; shift 2 ;;
    -*) die "unbekannte Option $1" ;;
    *)
      if [[ -z "$list" ]]; then list=$1
      elif [[ -z "$target" ]]; then target=$1
      else die "zu viele Argumente"
      fi
      shift
      ;;
  esac
done
[[ -n "$list" && -n "$target" ]] || { usage; exit 2; }
[[ -s "$list" ]] || die "Paketliste fehlt oder ist leer: $list"
if [[ ! "$part_mib" =~ ^[0-9]+$ ]] || (( part_mib < 100 || part_mib > 2047 )); then
  die "--teilgroesse muss 100 bis 2047 sein"
fi
if [[ -z "$version" ]]; then
  version=$(basename -- "$list")
  version=${version#zenos-}
  version=${version%-pi5-arm64.pakete.txt}
fi
[[ "$version" =~ ^[0-9A-Za-z.+~-]+$ ]] || die "Version «$version» nicht lesbar (--version)"
for tool in apt-get curl jq git tar sha256sum; do
  command -v "$tool" >/dev/null || die "$tool fehlt"
done
[[ -f "$KEYRING" ]] || die "$KEYRING fehlt (Paket ubuntu-keyring)"

mkdir -p -- "$target"
target=$(cd -- "$target" && pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/zenos-quellen.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
SOURCES="$WORK/quellen"
mkdir -p -- "$SOURCES"

# --- Eigene apt-Konfiguration nur für Quellpakete ---------------------------

setup_apt() {
  local d="$WORK/apt"
  mkdir -p -- "$d/etc/sources.list.d" "$d/etc/preferences.d" "$d/etc/apt.conf.d" "$d/state/lists/partial" \
    "$d/cache/archives/partial"
  cat > "$d/etc/sources.list.d/ubuntu.sources" <<EOF
Types: deb-src
URIs: $ARCHIVE
Suites: $SUITE $SUITE-updates $SUITE-security
Components: main restricted universe multiverse
Signed-By: $KEYRING
EOF
  : > "$d/status"
  cat > "$d/apt.conf" <<EOF
Dir::Etc "$d/etc";
Dir::Etc::sourcelist "/dev/null";
Dir::State "$d/state";
Dir::State::status "$d/status";
Dir::Cache "$d/cache";
Acquire::Retries "3";
APT::Sandbox::User "";
EOF
  export APT_CONFIG="$d/apt.conf"
  apt-get -q update > "$WORK/apt-update.log" 2>&1 || { tail -n 20 -- "$WORK/apt-update.log" >&2; die "apt-get update für Quellen fehlgeschlagen"; }
}

# --- Holen -----------------------------------------------------------------

# Prüft die Dateien einer .dsc gegen Checksums-Sha256 (in ORDNER)
verify_dsc() { # ORDNER DSC
  local dir=$1 dsc=$2 sums
  sums=$(awk '/^Checksums-Sha256:/ { on = 1; next } on && /^ / { print $1 "  " $3; next } on { exit }' "$dir/$dsc")
  [[ -n "$sums" ]] || return 1
  (cd -- "$dir" && sha256sum --check --quiet --strict - <<< "$sums")
}

fetch_apt() { # QUELLE VERSION ORDNER
  local src=$1 ver=$2 dir=$3
  (cd -- "$dir" && apt-get -q source --download-only --only-source "$src=$ver" > "$WORK/apt-source.log" 2>&1)
}

fetch_launchpad() { # QUELLE VERSION ORDNER
  local src=$1 ver=$2 dir=$3 link url name
  local -a urls=()
  link=$(curl -fsS --retry 3 --get "$LAUNCHPAD" --data-urlencode ws.op=getPublishedSources \
    --data-urlencode "source_name=$src" --data-urlencode "version=$ver" --data-urlencode exact_match=true |
    jq -r '.entries[0].self_link // empty') || return 1
  [[ -n "$link" ]] || return 1
  mapfile -t urls < <(curl -fsS --retry 3 --get "$link" --data-urlencode ws.op=sourceFileUrls | jq -r '.[]') || return 1
  (( ${#urls[@]} > 0 )) || return 1
  for url in "${urls[@]}"; do
    [[ "$url" == https://launchpad.net/* ]] || return 1
    name=$(basename -- "$url")
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9.+~_-]*$ ]] || return 1
    curl -fsSL --retry 3 -o "$dir/$name" -- "$url" || return 1
  done
}

# Ordnername eines Paars, eindeutig und ohne Sonderzeichen ausser . + ~ _ -
pair_dir() { printf '%s_%s' "$1" "${2//:/%3a}"; }

fetch_all() {
  local src ver dir dsc origin count=0 total
  local -a missing=()
  total=$(cut -f 3,4 -- "$list" | sort -u | grep -c .)
  info "$total Quellpakete aus $(grep -c . -- "$list") Binärpaketen"
  : > "$WORK/herkunft.tsv"
  while IFS=$'\t' read -r src ver; do
    [[ -n "$src" && -n "$ver" ]] || continue
    [[ "$src" =~ ^[a-z0-9][a-z0-9.+-]+$ && "$ver" =~ ^[A-Za-z0-9.+~:-]+$ ]] || die "Ungültige Zeile in der Paketliste: $src $ver"
    count=$((count + 1))
    dir="$SOURCES/$(pair_dir "$src" "$ver")"
    mkdir -p -- "$dir"
    origin=""
    if fetch_apt "$src" "$ver" "$dir"; then
      origin=ubuntu-archiv
    else
      find "$dir" -mindepth 1 -delete
      if fetch_launchpad "$src" "$ver" "$dir"; then origin=launchpad; fi
    fi
    dsc=$(find "$dir" -maxdepth 1 -name '*.dsc' -printf '%f\n' | head -n 1)
    if [[ -z "$origin" || -z "$dsc" ]] || ! verify_dsc "$dir" "$dsc"; then
      missing+=("$src=$ver")
      rm -rf -- "$dir"
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$src" "$ver" "$origin" "$(du -sk -- "$dir" | cut -f 1)" >> "$WORK/herkunft.tsv"
    if (( count % 50 == 0 )); then info "$count von $total"; fi
  done < <(cut -f 3,4 -- "$list" | LC_ALL=C sort -u)
  if (( ${#missing[@]} > 0 )); then
    die "Quellen fehlen für ${#missing[@]} Paar(e): ${missing[*]}"
  fi
  info "Alle $count Quellpakete geholt ($(awk -F '\t' '$3 == "launchpad"' "$WORK/herkunft.tsv" | wc -l) von Launchpad)"
}

# --- Quickshell ------------------------------------------------------------

fetch_quickshell() {
  local module="$REPO_DIR/scripts/module/25-quickshell.sh" line qv commit url ist
  line=$(grep -m 1 -E '^[[:space:]]*local version=[0-9.]+ commit=[0-9a-f]{40}$' -- "$module") ||
    die "Version und Commit von Quickshell in $module nicht gefunden"
  qv=$(sed -E 's/.*version=([0-9.]+) .*/\1/' <<< "$line")
  commit=$(sed -E 's/.*commit=([0-9a-f]{40}).*/\1/' <<< "$line")
  for url in "${QUICKSHELL_URLS[@]}"; do
    if git -c advice.detachedHead=false clone --quiet --depth 1 --single-branch --branch "v$qv" -- "$url" \
      "$WORK/quickshell" 2> "$WORK/quickshell.log"; then
      break
    fi
    rm -rf -- "$WORK/quickshell"
  done
  [[ -d "$WORK/quickshell" ]] || die "Quickshell v$qv nicht erreichbar"
  ist=$(git -C "$WORK/quickshell" rev-parse --verify 'HEAD^{commit}')
  [[ "$ist" == "$commit" ]] || die "Quickshell v$qv zeigt auf $ist statt auf $commit"
  QS_FILE="zenos-$version-quickshell-$qv.tar"
  git -C "$WORK/quickshell" archive --format=tar --prefix="quickshell-$qv/" -o "$target/$QS_FILE" "$commit"
  QS_LINE="Quickshell $qv, Commit $commit ($url), als $QS_FILE"
  info "$QS_LINE"
}

# --- Packen ----------------------------------------------------------------

pack_parts() {
  local limit=$(( part_mib * 1024 )) size=0 part=1 src ver origin kb dir
  local -a members=()
  : > "$WORK/teile.tsv"
  flush() {
    (( ${#members[@]} > 0 )) || return 0
    local name
    name=$(printf 'zenos-%s-quellen-teil%02d.tar' "$version" "$part")
    tar --create --file "$target/$name" --directory "$SOURCES" --sort=name --owner=0 --group=0 --numeric-owner \
      --mtime=@0 -- "${members[@]}"
    printf '%s\n' "${members[@]}" | sed "s/\$/\t$name/" >> "$WORK/teile.tsv"
    info "$name: ${#members[@]} Quellpakete, $(( $(stat -c %s -- "$target/$name") / 1048576 )) MiB"
    members=()
    size=0
    part=$((part + 1))
  }
  while IFS=$'\t' read -r src ver origin kb; do
    dir=$(pair_dir "$src" "$ver")
    (( kb < limit )) || die "$src $ver ist mit $(( kb / 1024 )) MiB grösser als ein Teil (--teilgroesse)"
    if (( size + kb >= limit )); then flush; fi
    members+=("$dir")
    size=$((size + kb))
  done < "$WORK/herkunft.tsv"
  flush
}

write_overview() {
  local file="$target/zenos-$version-QUELLEN.txt"
  {
    printf 'zenOS %s – Quellcode der enthaltenen Pakete\n\n' "$version"
    printf 'Jedes Quellpaket liegt in genau der Version, die im Image steckt (Paketliste\n'
    printf 'zenos-%s-pi5-arm64.pakete.txt), als .dsc samt Dateien in einem der Teile unten.\n' "$version"
    printf 'Auspacken: tar -xf <teil>.tar; dann z. B. dpkg-source -x <paket>_<version>.dsc\n'
    printf 'Firmware-Dateien, die es nur binär gibt, stecken so in ihren Quellpaketen, wie Ubuntu sie verteilt.\n\n'
    printf '%s\n' "$QS_LINE"
    printf 'zenOS selbst: Tag v%s im Repo (MIT-Lizenz)\n\n' "$version"
    printf 'Quellpaket\tVersion\tHerkunft\tTeil\n'
    join -t $'\t' -1 1 -2 1 \
      <(awk -F '\t' -v OFS='\t' '{ print $1 "_" $2, $1, $2, $3 }' "$WORK/herkunft.tsv" | LC_ALL=C sort -t $'\t' -k 1,1) \
      <(sed -E 's/%3a/:/' "$WORK/teile.tsv" | LC_ALL=C sort -t $'\t' -k 1,1) |
      cut -f 2- | LC_ALL=C sort
  } > "$file"
  info "$(basename -- "$file")"
}

printf '── Quellen für zenOS %s\n' "$version"
setup_apt
fetch_all
fetch_quickshell
pack_parts
write_overview
printf '── Fertig: %s\n' "$target"
