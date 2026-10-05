#!/usr/bin/env bash
# tag-pruefen.sh – ist ein Release-Tag gültig signiert? Vor jedem Image-Bau (image/bauen.sh, .github/workflows/image.yml).
#
#   image/tag-pruefen.sh [--quelle REPO] [--commit SHA] vX.Y.Z[-rcN]
#
# Gültig ist der Tag nur, wenn alles stimmt (dieselben Regeln wie auf dem Gerät, scripts/bin/zenos-kanal):
#   - Der Name ist vX.Y.Z oder vX.Y.Z-rcN, ohne führende Nullen. Andere Tags gehören zu keinem Kanal.
#   - refs/tags/<name> ist ein annotierter Tag. Sein Kopf hat genau object, type, tag und tagger, das Feld «tag» ist
#     der Name, type ist commit, und er zeigt auf einen Commit (mit --commit genau auf diesen).
#   - Am Ende steht genau eine SSH-Signatur, kein OpenPGP und kein X.509.
#   - Der Anker system/vertrauen im Commit des Tags ist vollständig und streng im Format (wie release-signieren.sh).
#   - «git verify-tag» nimmt den Tag gegen release und widerrufen dieses Ankers für den Prinzipal zenos-release an,
#     und «ssh-keygen -Y verify» nimmt die Signatur unabhängig davon ebenso an (Namespace git, mit den Widerrufen).
#     git läuft mit leerer Umgebung, ohne System- und Benutzer-config, ohne Ersatzobjekte, Hooks und fsmonitor, mit
#     gpg.ssh.program=/usr/bin/ssh-keygen und abgeschaltetem OpenPGP und X.509. Was die config des Repos zu Signaturen
#     sagt, überschreibt die Befehlszeile.
#   - Ab Serie 2 gibt es den Tag vertrauen/NNNN (NNNN = Serie), mit der Wurzel dieses Ankers gültig signiert
#     (Prinzipal zenos-wurzel), und sein Commit trägt genau diesen Anker. Ein Image bekommt so nie einen Anker, den ein
#     Gerät nicht auch über das Netz übernommen hätte.
#
# Ausgabe nur bei Exit 0, auf stdout, eine Zeile «schluessel=wert» je Wert (für $GITHUB_OUTPUT und bauen.sh):
#   tag, version (ohne «v»), kanal (stabil oder vorschau), release (true ohne -rc, sonst false), commit, objekt
#   (Tag-Objekt), schluessel (Fingerabdruck des Release-Schlüssels), serie, wurzel (Fingerabdruck)
# Meldungen auf stderr, in GitHub Actions ein Fehler zusätzlich als ::error::.
# Exit 0 gültig · 1 ungültig oder nicht prüfbar (Grund auf stderr) · 2 falscher Aufruf.
#
# Prüft nur, schreibt nichts ins Repo. Läuft unter Linux und auf dem Mac (bash 3.2), braucht /usr/bin/git und
# /usr/bin/ssh-keygen (OpenSSH 8.2 oder neuer).

set -uo pipefail
export LC_ALL=C
umask 077

GIT=/usr/bin/git
SSH_KEYGEN=/usr/bin/ssh-keygen
SIG_BEGIN='-----BEGIN SSH SIGNATURE-----'
SIG_END='-----END SSH SIGNATURE-----'
VERSION_ERE='^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(-rc[1-9][0-9]{0,8})?$'
ED25519_ERE='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}'
OID_ERE='^[0-9a-f]{40}$'
ANKER_DATEIEN="release wurzel widerrufen serie"

hilfe() {
  sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'
}

TMP=""
# Läuft über «trap … EXIT»
# shellcheck disable=SC2329
aufraeumen() {
  if [[ -n "$TMP" && -d "$TMP" ]]; then rm -rf -- "$TMP"; fi
}

meldung() { printf 'tag-pruefen: %s\n' "$*" >&2; }

ungueltig() {
  meldung "$*"
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then printf '::error::Tag-Prüfung: %s\n' "$*" >&2; fi
  exit 1
}

aufruf_fehler() {
  meldung "$*"
  hilfe >&2
  exit 2
}

# Git zum Prüfen: leere Umgebung, keine fremde config ausser der des Repos, und alles, was eine Signaturprüfung
# beeinflusst, kommt von der Befehlszeile (die gewinnt gegen die config des Repos)
pg() {
  env -i PATH=/usr/bin:/bin HOME=/nonexistent LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_ATTR_NOSYSTEM=1 GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
    "$GIT" -C "$REPO" -c "safe.directory=$REPO" -c "safe.directory=$REPO/.git" \
    -c core.hooksPath=/dev/null -c core.fsmonitor=false -c "gpg.ssh.program=$SSH_KEYGEN" \
    -c gpg.openpgp.program=false -c gpg.x509.program=false -c protocol.allow=never -c gc.auto=0 \
    -c maintenance.auto=false "$@"
}

# fingerabdruck «ssh-ed25519 AAAA…» → SHA256:…
fingerabdruck() {
  printf '%s\n' "$1" | env -i PATH=/usr/bin:/bin "$SSH_KEYGEN" -lf - 2>/dev/null | cut -d' ' -f2
}

# --- Anker -----------------------------------------------------------------------------------------------------

# anker_lesen COMMIT ZIEL – system/vertrauen aus COMMIT nach ZIEL: release.signers und wurzel.signers (Format
# allowedSignersFile, nur die Schlüsselzeilen), widerrufen (nur Schlüssel), dazu *.schluessel (sortiert) und
# serie.wert. 0: vollständig und stimmig; 1: sonst, Grund in GRUND.
anker_lesen() {
  local commit=$1 ziel=$2 name
  GRUND=""
  rm -rf -- "$ziel"
  mkdir -p -- "$ziel"
  for name in $ANKER_DATEIEN; do
    if ! pg cat-file blob "$commit:system/vertrauen/$name" > "$ziel/$name.roh" 2>/dev/null; then
      GRUND="system/vertrauen/$name fehlt im Stand"
      return 1
    fi
    grep -v -E '^[[:space:]]*(#|$)' "$ziel/$name.roh" > "$ziel/$name.zeilen" || true
  done
  if [[ ! -s "$ziel/release.zeilen" && ! -s "$ziel/wurzel.zeilen" && ! -s "$ziel/widerrufen.zeilen" &&
    ! -s "$ziel/serie.zeilen" ]]; then
    GRUND="system/vertrauen hat keine Schlüssel (leer)"
    return 1
  fi
  if grep -v -E "^zenos-release namespaces=\"git\" $ED25519_ERE\$" "$ziel/release.zeilen" > "$ziel/fehl"; then
    GRUND="system/vertrauen/release hat eine ungültige Zeile: $(head -n 1 "$ziel/fehl" | cut -c1-60)"
    return 1
  fi
  if grep -v -E "^zenos-wurzel namespaces=\"git\" $ED25519_ERE\$" "$ziel/wurzel.zeilen" > "$ziel/fehl"; then
    GRUND="system/vertrauen/wurzel hat eine ungültige Zeile: $(head -n 1 "$ziel/fehl" | cut -c1-60)"
    return 1
  fi
  if grep -v -E "^$ED25519_ERE\$" "$ziel/widerrufen.zeilen" > "$ziel/fehl"; then
    GRUND="system/vertrauen/widerrufen hat eine ungültige Zeile: $(head -n 1 "$ziel/fehl" | cut -c1-60)"
    return 1
  fi
  if [[ ! -s "$ziel/release.zeilen" ]]; then
    GRUND="system/vertrauen/release enthält keinen Schlüssel"
    return 1
  fi
  if [[ "$(wc -l < "$ziel/wurzel.zeilen" | tr -d ' ')" != 1 ]]; then
    GRUND="system/vertrauen/wurzel muss genau einen Schlüssel enthalten"
    return 1
  fi
  if [[ "$(wc -l < "$ziel/serie.zeilen" | tr -d ' ')" != 1 ]] || ! grep -q -E '^[1-9][0-9]{0,3}$' "$ziel/serie.zeilen"
  then
    GRUND="system/vertrauen/serie enthält keine Zahl von 1 bis 9999"
    return 1
  fi
  tr -d ' ' < "$ziel/serie.zeilen" > "$ziel/serie.wert"
  cut -d' ' -f3- "$ziel/release.zeilen" | sort -u > "$ziel/release.schluessel"
  cut -d' ' -f3- "$ziel/wurzel.zeilen" | sort -u > "$ziel/wurzel.schluessel"
  sort -u "$ziel/widerrufen.zeilen" > "$ziel/widerrufen.schluessel"
  if [[ -n "$(comm -12 "$ziel/wurzel.schluessel" "$ziel/release.schluessel")" ]]; then
    GRUND="Wurzel- und Release-Schlüssel müssen verschieden sein"
    return 1
  fi
  if [[ -n "$(comm -12 "$ziel/release.schluessel" "$ziel/widerrufen.schluessel")" ]]; then
    GRUND="ein Release-Schlüssel steht auch in widerrufen"
    return 1
  fi
  if [[ -n "$(comm -12 "$ziel/wurzel.schluessel" "$ziel/widerrufen.schluessel")" ]]; then
    GRUND="der Wurzel-Schlüssel steht in widerrufen"
    return 1
  fi
  # Für git und ssh-keygen nur die geprüften Zeilen, ohne Kommentare
  sed 's/^/zenos-release namespaces="git" /' "$ziel/release.schluessel" > "$ziel/release.signers"
  sed 's/^/zenos-wurzel namespaces="git" /' "$ziel/wurzel.schluessel" > "$ziel/wurzel.signers"
  cp -- "$ziel/widerrufen.schluessel" "$ziel/widerrufen"
  return 0
}

# anker_gleich A B → 0, wenn zwei gelesene Anker dieselben Schlüssel und dieselbe Serie haben
anker_gleich() {
  local name
  for name in release.schluessel wurzel.schluessel widerrufen.schluessel serie.wert; do
    cmp -s -- "$1/$name" "$2/$name" || return 1
  done
}

# --- Tags ------------------------------------------------------------------------------------------------------

# tag_pruefen NAME PRINZIPAL SIGNERS WIDERRUFEN [COMMIT] – 0, wenn refs/tags/NAME ein annotierter Tag in der Form oben
# ist (gegebenenfalls auf genau COMMIT) und git verify-tag und ssh-keygen -Y verify ihn gegen SIGNERS und WIDERRUFEN für
# PRINZIPAL annehmen. Setzt TAG_OBJEKT, TAG_COMMIT und TAG_SCHLUESSEL (Fingerabdruck); sonst 1, Grund in GRUND.
tag_pruefen() {
  local name=$1 prinzipal=$2 signers=$3 widerrufen=$4 soll=${5:-} roh="$TMP/tag.roh" kopf letzte anzahl art
  local erwartet fp_git fp_ssh
  GRUND=""
  TAG_OBJEKT=""
  TAG_COMMIT=""
  TAG_SCHLUESSEL=""
  if ! TAG_OBJEKT=$(pg rev-parse --verify --quiet "refs/tags/$name" 2>/dev/null) || [[ ! "$TAG_OBJEKT" =~ $OID_ERE ]]
  then
    GRUND="den Tag $name gibt es in der Quelle nicht"
    return 1
  fi
  art=$(pg cat-file -t "$TAG_OBJEKT" 2>/dev/null) || art=""
  if [[ "$art" != tag ]]; then
    GRUND="$name ist kein annotierter Tag (leichter Tag oder ohne Tag-Objekt geholt)"
    return 1
  fi
  if ! pg cat-file tag "$TAG_OBJEKT" > "$roh" 2>/dev/null; then
    GRUND="Tag-Objekt von $name nicht lesbar"
    return 1
  fi
  # Kopf: genau vier Zeilen object, type, tag, tagger (jede mit Wert), danach eine Leerzeile
  kopf=$(awk 'BEGIN { n = 0; leer = 0; schlecht = 0 }
    $0 == "" { leer = 1; exit }
    { n++; p = index($0, " "); if (p < 2) schlecht = 1; k[n] = substr($0, 1, p - 1) }
    END { if (!leer || schlecht || n != 4 || k[1] != "object" || k[2] != "type" || k[3] != "tag" || k[4] != "tagger")
            print "nein"; else print "ja" }' "$roh")
  if [[ "$kopf" != ja ]]; then
    GRUND="Kopf des Tags $name unerwartet"
    return 1
  fi
  if [[ "$(sed -n '3s/^tag //p' "$roh")" != "$name" ]]; then
    GRUND="Feld «tag» im Objekt ist «$(sed -n '3s/^tag //p' "$roh" | cut -c1-40)», nicht «$name»"
    return 1
  fi
  TAG_COMMIT=$(sed -n '1s/^object //p' "$roh")
  if [[ "$(sed -n '2s/^type //p' "$roh")" != commit || ! "$TAG_COMMIT" =~ $OID_ERE ||
    "$(pg cat-file -t "$TAG_COMMIT" 2>/dev/null)" != commit ]]; then
    GRUND="$name zeigt nicht auf einen Commit"
    return 1
  fi
  if [[ -n "$soll" && "$TAG_COMMIT" != "$soll" ]]; then
    GRUND="$name zeigt auf $TAG_COMMIT, gebaut werden soll $soll"
    return 1
  fi
  # Signatur: genau eine SSH-Signatur, als letzter Block, BEGIN und END je auf einer eigenen Zeile
  if grep -q -F -e '-----BEGIN PGP' "$roh"; then
    GRUND="$name hat eine OpenPGP-Signatur (nicht erlaubt)"
    return 1
  fi
  if grep -q -F -e '-----BEGIN SIGNED MESSAGE-----' "$roh"; then
    GRUND="$name hat eine X.509-Signatur (nicht erlaubt)"
    return 1
  fi
  anzahl=$(grep -o -F -e "$SIG_BEGIN" "$roh" | wc -l | tr -d ' ')
  if [[ "$anzahl" == 0 ]]; then
    GRUND="$name ist unsigniert"
    return 1
  fi
  letzte=$(awk '{ z[NR] = $0 } END { i = NR; while (i > 0 && z[i] == "") i--; if (i > 0) print z[i] }' "$roh")
  if [[ "$anzahl" != 1 || "$(grep -o -F -e "$SIG_END" "$roh" | wc -l | tr -d ' ')" != 1 || "$letzte" != "$SIG_END" ]] ||
    ! grep -q -x -F -e "$SIG_BEGIN" "$roh"; then
    GRUND="$name hat mehr als eine oder eine unvollständige Signatur"
    return 1
  fi

  # 1. git verify-tag (gehärtet) mit genau der erwarteten Zeile
  if ! pg -c "gpg.ssh.allowedSignersFile=$signers" -c "gpg.ssh.revocationFile=$widerrufen" \
    verify-tag "$TAG_OBJEKT" > "$TMP/verify.git" 2>&1; then
    GRUND="git verify-tag lehnt $name ab: $(grep -v '^$' "$TMP/verify.git" | tail -n 1 | cut -c1-120)"
    return 1
  fi
  erwartet="Good \"git\" signature for $prinzipal with ED25519 key SHA256:"
  fp_git=$(grep -F -e "$erwartet" "$TMP/verify.git" | head -n 1 | sed 's/.* key //')
  if [[ -z "$fp_git" ]]; then
    GRUND="$name ist nicht vom Prinzipal $prinzipal signiert"
    return 1
  fi

  # 2. Unabhängig davon ssh-keygen auf Nutzlast (alles vor der Signatur) und Signatur
  awk -v b="$SIG_BEGIN" '$0 == b { exit } { print }' "$roh" > "$TMP/nutzlast"
  awk -v b="$SIG_BEGIN" '$0 == b { s = 1 } s { print }' "$roh" > "$TMP/signatur"
  if ! env -i PATH=/usr/bin:/bin "$SSH_KEYGEN" -Y verify -f "$signers" -I "$prinzipal" -n git -s "$TMP/signatur" \
    -r "$widerrufen" < "$TMP/nutzlast" > "$TMP/verify.ssh" 2>&1; then
    GRUND="ssh-keygen -Y verify lehnt $name ab: $(grep -v '^$' "$TMP/verify.ssh" | tail -n 1 | cut -c1-120)"
    return 1
  fi
  fp_ssh=$(grep -F -e "$erwartet" "$TMP/verify.ssh" | head -n 1 | sed 's/.* key //')
  if [[ -z "$fp_ssh" || "$fp_ssh" != "$fp_git" ]]; then
    GRUND="git und ssh-keygen sind sich bei $name nicht einig"
    return 1
  fi
  TAG_SCHLUESSEL=$fp_git
  return 0
}

# --- Start -----------------------------------------------------------------------------------------------------

QUELLE=.
SOLL=""
NAME=""
while (( $# > 0 )); do
  case "$1" in
    -h | --hilfe) hilfe; exit 0 ;;
    --quelle | --commit)
      (( $# >= 2 )) || aufruf_fehler "$1 braucht einen Wert"
      if [[ "$1" == --quelle ]]; then QUELLE=$2; else SOLL=$2; fi
      shift 2
      ;;
    -*) aufruf_fehler "unbekannte Option «$1»" ;;
    *)
      [[ -z "$NAME" ]] || aufruf_fehler "nur ein Tag"
      NAME=$1
      shift
      ;;
  esac
done
[[ -n "$NAME" ]] || aufruf_fehler "welcher Tag?"
if [[ -n "$SOLL" && ! "$SOLL" =~ $OID_ERE ]]; then aufruf_fehler "--commit braucht eine volle Commit-ID (40 Zeichen)"; fi

for werkzeug in "$GIT" "$SSH_KEYGEN"; do
  [[ -x "$werkzeug" ]] || ungueltig "$werkzeug fehlt"
done
if [[ ! "$NAME" =~ $VERSION_ERE ]]; then
  ungueltig "«$NAME» ist kein Release-Tag vX.Y.Z oder vX.Y.Z-rcN (ohne führende Nullen)"
fi
REPO=$(cd -- "$QUELLE" 2>/dev/null && pwd -P) || ungueltig "Quelle «$QUELLE» gibt es nicht"
pg rev-parse --git-dir > /dev/null 2>&1 || ungueltig "$REPO ist kein Git-Repo"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zenos-tag-pruefen.XXXXXX") || ungueltig "kein Temp-Ordner"
trap aufraeumen EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Der Anker im Stand: aus dem Commit, auf den der Tag zeigt (nicht aus dem Arbeitsbaum)
COMMIT=$(pg rev-parse --verify --quiet "refs/tags/$NAME^{commit}" 2>/dev/null) || COMMIT=""
[[ "$COMMIT" =~ $OID_ERE ]] || ungueltig "den Tag $NAME gibt es in $REPO nicht (oder er zeigt nicht auf einen Commit)"
anker_lesen "$COMMIT" "$TMP/anker" || ungueltig "Anker im Stand von $NAME unbrauchbar: $GRUND"
SERIE=$(cat "$TMP/anker/serie.wert")

tag_pruefen "$NAME" zenos-release "$TMP/anker/release.signers" "$TMP/anker/widerrufen" "$SOLL" ||
  ungueltig "$GRUND"
OBJEKT=$TAG_OBJEKT
SCHLUESSEL=$TAG_SCHLUESSEL

# Ab Serie 2: der Tag vertrauen/NNNN, mit der Wurzel signiert, auf einem Commit mit genau diesem Anker
if (( SERIE >= 2 )); then
  VERTRAUEN=vertrauen/$(printf '%04d' "$SERIE")
  tag_pruefen "$VERTRAUEN" zenos-wurzel "$TMP/anker/wurzel.signers" "$TMP/anker/widerrufen" ||
    ungueltig "Anker Serie $SERIE ohne gültigen Tag $VERTRAUEN: $GRUND"
  anker_lesen "$TAG_COMMIT" "$TMP/vertrauen" || ungueltig "Anker im Commit von $VERTRAUEN unbrauchbar: $GRUND"
  anker_gleich "$TMP/anker" "$TMP/vertrauen" ||
    ungueltig "Der Anker im Stand von $NAME ist nicht der aus $VERTRAUEN (Serie $SERIE)"
fi

KANAL=stabil
RELEASE=true
case "$NAME" in *-rc*) KANAL=vorschau; RELEASE=false ;; esac
WURZEL_FP=$(fingerabdruck "$(cat "$TMP/anker/wurzel.schluessel")")

meldung "$NAME (${COMMIT:0:12}) ist gültig signiert: $SCHLUESSEL, Anker Serie $SERIE, Kanal $KANAL"
printf 'tag=%s\nversion=%s\nkanal=%s\nrelease=%s\ncommit=%s\nobjekt=%s\nschluessel=%s\nserie=%s\nwurzel=%s\n' \
  "$NAME" "${NAME#v}" "$KANAL" "$RELEASE" "$COMMIT" "$OBJEKT" "$SCHLUESSEL" "$SERIE" "$WURZEL_FP"
exit 0
