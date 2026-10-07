#!/usr/bin/env bash
# release-signieren.sh – signiert ein Release oder eine neue Serie des Vertrauensankers mit einem Schlüssel aus
# 1Password und pusht den Tag nach Rückfrage.
#
#   scripts/release-signieren.sh vX.Y.Z           Release (Kanal stabil) mit dem Schlüssel «zenOS Release»
#   scripts/release-signieren.sh vX.Y.Z-rcN       Vorabversion (Kanal vorschau), ebenso
#   scripts/release-signieren.sh --vertrauen      Tag vertrauen/NNNN für die Serie aus system/vertrauen/serie,
#                                                 mit dem Schlüssel «zenOS Wurzel»
#
# Läuft auf dem Mac (bash 3.2) in einem eigenen Terminal-Tab, in dem Claude Code nicht läuft. Danach 1Password
# sperren. Signiert wird über op-ssh-sign von 1Password mit Touch ID; ein privater Schlüssel liegt nie in einer Datei.
# Welcher öffentliche Schlüssel signiert, steht im Anker system/vertrauen des Stands, der signiert wird.
#
# Vor dem Signieren prüft das Skript:
#   - Arbeitsbaum sauber, HEAD auf origin (nach «git fetch»), der Tag neu (lokal und auf origin)
#   - Release: Version höher als jede auf origin (vX.Y.Z-rcN < vX.Y.Z), HEAD baut auf dem letzten Release auf,
#     die Prüfung (pruefen.yml) per gh grün (läuft sie noch, wartet es höchstens 25 Min.), der Anker vollständig und
#     unverändert oder mit Tag vertrauen/NNNN
#   - Vertrauen: Serie genau eins höher als die letzte, Wurzel gleich, Widerrufe nur dazu
# Es zeigt die Commits seit dem letzten Release und gesondert die Änderungen an sensiblen Pfaden
# (scripts/lib/sensible-pfade). Signiert wird erst nach «ja», danach prüft «git verify-tag» den Tag gegen den Anker.
# Gepusht wird nur der Tag und erst nach einem zweiten «ja».
#
# Nur für Tests: ZENOS_TEST_SIGNIERPROGRAMM=<programm> signiert mit diesem Programm statt mit op-ssh-sign, etwa
# ssh-keygen mit einem Wegwerf-Schlüssel im ssh-agent. Das Skript sagt das dann deutlich. ZENOS_TEST_CI_PAUSE=0
# wartet nicht zwischen den Abfragen der CI.
#
# Exit 0: signiert (gepusht oder bewusst nur lokal); 1: Prüfung gescheitert oder abgebrochen, es bleibt kein neuer
# Tag liegen (nur wenn das Pushen scheitert, bleibt der geprüfte Tag lokal); 2: Aufruf falsch.

set -uo pipefail
export LC_ALL=C

VERSION_ERE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'
VERTRAUEN_ERE='^vertrauen/[0-9]{4}$'
ED25519_ERE='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}'
OP_SSH_SIGN_MAC=/Applications/1Password.app/Contents/MacOS/op-ssh-sign
OP_SSH_SIGN_LINUX=/opt/1Password/op-ssh-sign
GRUPPEN="firewall netz boot anmeldung vertrauen"

hilfe() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

meldung() { printf '%s\n' "$*"; }
warnung() { printf 'Warnung: %s\n' "$*"; }

TMP=""
TAG_UNGEPRUEFT=""

# Läuft über «trap … EXIT»
# shellcheck disable=SC2329
aufraeumen() {
  # Ein erzeugter, aber (noch) nicht geprüfter Tag bleibt nie liegen
  if [[ -n "$TAG_UNGEPRUEFT" ]]; then
    git -C "$WURZEL" tag -d "$TAG_UNGEPRUEFT" >/dev/null 2>&1 &&
      printf 'release-signieren: Tag %s wieder gelöscht.\n' "$TAG_UNGEPRUEFT" >&2
    TAG_UNGEPRUEFT=""
  fi
  if [[ -n "$TMP" && -d "$TMP" ]]; then rm -rf "$TMP"; fi
}

abbruch() {
  printf 'release-signieren: %s\n' "$*" >&2
  printf 'release-signieren: Nichts signiert, nichts gepusht.\n' >&2
  exit 1
}

# frage TEXT → liest eine Antwort nach ANTWORT; 1 bei Dateiende
frage() {
  ANTWORT=""
  printf '%s ' "$1"
  if ! IFS= read -r ANTWORT; then
    printf '\n'
    return 1
  fi
  return 0
}

# Ohne Pager: Die Liste der Commits soll im Terminal stehen, nicht in less, das unter LC_ALL=C Umlaute als <C3><BC>
# zeigt und auf «q» wartet
g() { git --no-pager -C "$WURZEL" "$@"; }

# Git zum Prüfen von Signaturen: nur SSH mit ssh-keygen, OpenPGP und X.509 schlagen immer fehl (sonst nähme
# verify-tag auch eine PGP-Signatur aus einem fremden Schlüsselbund an)
pruef_git() {
  g -c gpg.ssh.program=ssh-keygen -c gpg.openpgp.program=false -c gpg.x509.program=false "$@"
}

kurz() { g rev-parse --short "$1"; }

# fingerabdruck «ssh-ed25519 AAAA…» → SHA256:…
fingerabdruck() {
  local fp
  fp=$(printf '%s\n' "$1" | ssh-keygen -lf - 2>/dev/null | cut -d' ' -f2)
  printf '%s' "${fp:-(unlesbar)}"
}

# --- Version ---------------------------------------------------------------------------------------------------

# version_schluessel vX.Y.Z[-rcN] → «X Y Z N»; ohne -rc ist N grösser als jede rc-Nummer
version_schluessel() {
  local v=${1#v} rc=999999999 a b c
  case "$v" in
    *-rc*) rc=${v##*-rc}; v=${v%-rc*} ;;
  esac
  IFS=. read -r a b c <<< "$v"
  printf '%s %s %s %s\n' "$a" "$b" "$c" "$rc"
}

# version_hoeher A B → 0, wenn A höher ist als B
version_hoeher() {
  local a1 a2 a3 a4 b1 b2 b3 b4
  read -r a1 a2 a3 a4 <<< "$(version_schluessel "$1")"
  read -r b1 b2 b3 b4 <<< "$(version_schluessel "$2")"
  if (( a1 != b1 )); then (( a1 > b1 )); return; fi
  if (( a2 != b2 )); then (( a2 > b2 )); return; fi
  if (( a3 != b3 )); then (( a3 > b3 )); return; fi
  (( a4 > b4 ))
}

# --- Anker -----------------------------------------------------------------------------------------------------

# anker_lesen REV ZIEL – liest system/vertrauen aus REV nach ZIEL: Rohdateien release, wurzel, widerrufen, serie;
# *.zeilen ohne Kommentare; release.schluessel, wurzel.schluessel und widerrufen.schluessel (je «ssh-ed25519 …»,
# sortiert) und serie.wert. 0: vollständig und stimmig; 1: sonst, Grund in ANKER_GRUND.
anker_lesen() {
  local rev=$1 ziel=$2 name
  ANKER_GRUND=""
  rm -rf "$ziel"
  mkdir -p "$ziel"
  for name in release wurzel widerrufen serie; do
    if ! g cat-file -e "$rev:system/vertrauen/$name" 2>/dev/null; then
      ANKER_GRUND="system/vertrauen/$name fehlt"
      return 1
    fi
    g cat-file blob "$rev:system/vertrauen/$name" > "$ziel/$name" || { ANKER_GRUND="$name nicht lesbar"; return 1; }
    grep -v -E '^[[:space:]]*(#|$)' "$ziel/$name" > "$ziel/$name.zeilen" || true
  done
  # Jede Zeile streng im erwarteten Format, sonst nichts (keine Optionen wie cert-authority, keine anderen Typen)
  if grep -v -E "^zenos-release namespaces=\"git\" $ED25519_ERE\$" "$ziel/release.zeilen" > "$ziel/fehl"; then
    ANKER_GRUND="system/vertrauen/release hat eine ungültige Zeile: $(head -n 1 "$ziel/fehl" | cut -c1-60)"
    return 1
  fi
  if grep -v -E "^zenos-wurzel namespaces=\"git\" $ED25519_ERE\$" "$ziel/wurzel.zeilen" > "$ziel/fehl"; then
    ANKER_GRUND="system/vertrauen/wurzel hat eine ungültige Zeile: $(head -n 1 "$ziel/fehl" | cut -c1-60)"
    return 1
  fi
  if grep -v -E "^$ED25519_ERE\$" "$ziel/widerrufen.zeilen" > "$ziel/fehl"; then
    ANKER_GRUND="system/vertrauen/widerrufen hat eine ungültige Zeile: $(head -n 1 "$ziel/fehl" | cut -c1-60)"
    return 1
  fi
  if [[ ! -s "$ziel/release.zeilen" ]]; then
    ANKER_GRUND="system/vertrauen/release enthält keinen Schlüssel"
    return 1
  fi
  if [[ "$(wc -l < "$ziel/wurzel.zeilen" | tr -d ' ')" != 1 ]]; then
    ANKER_GRUND="system/vertrauen/wurzel muss genau einen Schlüssel enthalten"
    return 1
  fi
  if [[ "$(wc -l < "$ziel/serie.zeilen" | tr -d ' ')" != 1 ]] ||
    ! grep -q -E '^[1-9][0-9]{0,3}$' "$ziel/serie.zeilen"; then
    ANKER_GRUND="system/vertrauen/serie enthält keine Zahl von 1 bis 9999"
    return 1
  fi
  tr -d ' ' < "$ziel/serie.zeilen" > "$ziel/serie.wert"
  cut -d' ' -f3- "$ziel/release.zeilen" | sort -u > "$ziel/release.schluessel"
  cut -d' ' -f3- "$ziel/wurzel.zeilen" | sort -u > "$ziel/wurzel.schluessel"
  sort -u "$ziel/widerrufen.zeilen" > "$ziel/widerrufen.schluessel"
  if [[ -n "$(comm -12 "$ziel/wurzel.schluessel" "$ziel/release.schluessel")" ]]; then
    ANKER_GRUND="Wurzel- und Release-Schlüssel müssen verschieden sein"
    return 1
  fi
  if [[ -n "$(comm -12 "$ziel/release.schluessel" "$ziel/widerrufen.schluessel")" ]]; then
    ANKER_GRUND="ein Release-Schlüssel steht auch in widerrufen"
    return 1
  fi
  if [[ -n "$(comm -12 "$ziel/wurzel.schluessel" "$ziel/widerrufen.schluessel")" ]]; then
    ANKER_GRUND="der Wurzel-Schlüssel steht in widerrufen"
    return 1
  fi
  return 0
}

# anker_gleich A B → 0, wenn zwei gelesene Anker dieselben Schlüssel und dieselbe Serie haben (Kommentare zählen nicht)
anker_gleich() {
  local name
  for name in release.schluessel wurzel.schluessel widerrufen.schluessel serie.wert; do
    cmp -s "$1/$name" "$2/$name" || return 1
  done
}

# schluessel_zeigen DATEI EINZUG – jeder Schlüssel mit Fingerabdruck
schluessel_zeigen() {
  local k
  if [[ ! -s "$1" ]]; then
    printf '%skeine\n' "$2"
    return
  fi
  while IFS= read -r k; do
    printf '%s%s\n' "$2" "$(fingerabdruck "$k")"
  done < "$1"
}

# --- Tags ------------------------------------------------------------------------------------------------------

# tag_pruefen OID NAME SIGNERS WIDERRUFEN PRINZIPAL [COMMIT] – 0, wenn OID ein annotierter Tag mit Namen NAME
# auf einen Commit (gegebenenfalls genau COMMIT) ist, genau eine SSH-Signatur trägt und verify-tag ihn gegen
# SIGNERS und WIDERRUFEN für PRINZIPAL annimmt. Sonst 1, Grund in TAG_GRUND.
tag_pruefen() {
  local oid=$1 name=$2 signers=$3 widerrufen=$4 prinzipal=$5 commit=${6:-} feld anzahl
  TAG_GRUND=""
  if [[ "$(g cat-file -t "$oid" 2>/dev/null)" != tag ]]; then
    TAG_GRUND="kein annotierter Tag"
    return 1
  fi
  g cat-file tag "$oid" > "$TMP/tag-roh" 2>/dev/null || { TAG_GRUND="Tag nicht lesbar"; return 1; }
  awk 'NF == 0 { exit } { print }' "$TMP/tag-roh" > "$TMP/tag-kopf"
  feld=$(sed -n 's/^tag //p' "$TMP/tag-kopf")
  if [[ "$feld" != "$name" ]]; then
    TAG_GRUND="Feld «tag» im Objekt ist «$feld», nicht «$name»"
    return 1
  fi
  if [[ "$(sed -n 's/^type //p' "$TMP/tag-kopf")" != commit ]]; then
    TAG_GRUND="zeigt nicht auf einen Commit"
    return 1
  fi
  if [[ -n "$commit" && "$(sed -n 's/^object //p' "$TMP/tag-kopf")" != "$commit" ]]; then
    TAG_GRUND="zeigt nicht auf $commit"
    return 1
  fi
  anzahl=$(grep -c -e '-----BEGIN SSH SIGNATURE-----' "$TMP/tag-roh" || true)
  if [[ "$anzahl" != 1 ]] || grep -q -e '-----BEGIN PGP' "$TMP/tag-roh"; then
    TAG_GRUND="keine eindeutige SSH-Signatur"
    return 1
  fi
  if ! pruef_git -c "gpg.ssh.allowedSignersFile=$signers" -c "gpg.ssh.revocationFile=$widerrufen" \
    verify-tag --raw "$oid" > "$TMP/verify" 2>&1; then
    TAG_GRUND="Signatur passt nicht zum Anker oder ist widerrufen ($(grep -v '^$' "$TMP/verify" | tail -n 1))"
    return 1
  fi
  if ! grep -q -F "for $prinzipal with" "$TMP/verify"; then
    TAG_GRUND="nicht vom Prinzipal $prinzipal signiert"
    return 1
  fi
  return 0
}

# remote_oid NAME → Objekt-ID des Tags auf origin (leer, wenn es ihn dort nicht gibt)
remote_oid() {
  awk -v ref="refs/tags/$1" '$2 == ref { print $1 }' "$TMP/remote-tags"
}

# lokal_oid NAME → Objekt-ID des lokalen Tags (leer, wenn es ihn nicht gibt)
lokal_oid() {
  g rev-parse -q --verify "refs/tags/$1" 2>/dev/null || true
}

# --- Gemeinsame Prüfungen --------------------------------------------------------------------------------------

signierprogramm_waehlen() {
  if [[ -n "${ZENOS_TEST_SIGNIERPROGRAMM:-}" ]]; then
    PROGRAMM=$ZENOS_TEST_SIGNIERPROGRAMM
    meldung ""
    meldung "  TESTMODUS: signiert mit «$PROGRAMM» statt mit 1Password (ZENOS_TEST_SIGNIERPROGRAMM)."
    meldung ""
    return
  fi
  if [[ -x "$OP_SSH_SIGN_MAC" ]]; then
    PROGRAMM=$OP_SSH_SIGN_MAC
  elif [[ -x "$OP_SSH_SIGN_LINUX" ]]; then
    PROGRAMM=$OP_SSH_SIGN_LINUX
  else
    abbruch "op-ssh-sign von 1Password fehlt ($OP_SSH_SIGN_MAC). 1Password installieren und unter Einstellungen › Entwickler den SSH-Agent einschalten."
  fi
}

werkzeuge_pruefen() {
  local w
  for w in git ssh-keygen awk comm cmp; do
    command -v "$w" >/dev/null 2>&1 || abbruch "$w fehlt."
  done
}

stand_pruefen() {
  if [[ -n "$(g status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    abbruch "Der Arbeitsbaum ist nicht sauber (git status). Erst committen und pushen oder verwerfen."
  fi
  HEAD_OID=$(g rev-parse --verify -q 'HEAD^{commit}') || abbruch "Kein Commit in HEAD."

  meldung "Hole den Stand von origin …"
  g remote get-url origin >/dev/null 2>&1 || abbruch "Es gibt kein Remote «origin»."
  g fetch --quiet --no-tags origin || abbruch "git fetch origin ist fehlgeschlagen."
  g ls-remote --tags --refs origin > "$TMP/remote-tags" || abbruch "git ls-remote origin ist fehlgeschlagen."
  # Tags von origin dazu, ohne lokale zu überschreiben (ein verschobener Tag wird abgelehnt, siehe unten)
  g fetch --quiet --no-tags origin 'refs/tags/*:refs/tags/*' > /dev/null 2>&1 || true

  g for-each-ref --contains "$HEAD_OID" --format='%(refname:short)' refs/remotes/origin/ > "$TMP/enthalten"
  if [[ ! -s "$TMP/enthalten" ]]; then
    abbruch "HEAD ($(kurz "$HEAD_OID")) ist nicht auf origin. Erst pushen, dann signieren."
  fi

  # Tags, die lokal anders aussehen als auf origin
  local oid ref name lokal
  : > "$TMP/abweichend"
  while read -r oid ref; do
    name=${ref#refs/tags/}
    lokal=$(lokal_oid "$name")
    if [[ "$lokal" != "$oid" ]]; then printf '%s\n' "$name" >> "$TMP/abweichend"; fi
  done < "$TMP/remote-tags"
}

# abweichung_pruefen NAME – bricht ab, wenn der Tag lokal fehlt oder anders ist als auf origin
abweichung_pruefen() {
  if grep -q -x -F "$1" "$TMP/abweichend"; then
    abbruch "Der Tag $1 ist lokal anders als auf origin (oder fehlt). Übernehmen mit: git fetch --force origin refs/tags/$1:refs/tags/$1"
  fi
}

abweichungen_melden() {
  if [[ -s "$TMP/abweichend" ]]; then
    warnung "Diese Tags sind lokal anders als auf origin (oder fehlen lokal): $(tr '\n' ' ' < "$TMP/abweichend")"
  fi
}

tag_neu_pruefen() {
  if [[ -n "$(remote_oid "$1")" ]]; then
    abbruch "Den Tag $1 gibt es auf origin schon. Ein Tag wird nie verschoben, nimm einen neuen Namen."
  fi
  if [[ -n "$(lokal_oid "$1")" ]]; then
    abbruch "Den Tag $1 gibt es lokal schon (nicht auf origin). Verwerfen mit: git tag -d $1"
  fi
}

# Stand von pruefen.yml für HEAD als «status conclusion» (ohne Leerzeichen am Ende); 1, wenn gh nicht antwortet
ci_stand() {
  local stand
  stand=$(cd "$WURZEL" && gh run list --commit "$HEAD_OID" --workflow pruefen.yml --limit 1 \
    --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"' 2>/dev/null) || return 1
  # Ein laufender Lauf hat noch keine conclusion: «in_progress »
  printf '%s' "$stand" | sed 's/[[:space:]]*$//'
}

# Signiert wird nur auf einem Stand, für den pruefen.yml grün ist (ANLEITUNG G6): Ein gepushter Tag lässt sich nicht
# mehr verschieben, und Geräte auf vorschau nehmen ihn sofort. Läuft die Prüfung noch oder ist sie eben erst gepusht
# und noch nicht zu sehen, wartet das Skript (höchstens CI_VERSUCHE-mal CI_PAUSE s, 25 Min.; der Lauf hat ein
# Zeitlimit von 20 Min.). Rot oder nach der Wartezeit nicht fertig: Abbruch. Ist sie nicht prüfbar (gh fehlt, kein
# Zugriff), geht es nur mit bewusst getipptem «ohne Prüfung» weiter.
CI_VERSUCHE=75
CI_PAUSE=20
# Nur für Tests: ZENOS_TEST_CI_PAUSE=0 wartet nicht zwischen den Abfragen
if [[ "${ZENOS_TEST_CI_PAUSE:-}" =~ ^[0-9]+$ ]]; then CI_PAUSE=$ZENOS_TEST_CI_PAUSE; fi

ci_ohne_pruefung() { # GRUND
  warnung "CI nicht geprüft: $1."
  if ! frage "Ohne grüne Prüfung signieren? Geräte auf vorschau nähmen den Tag sofort. Tippe «ohne Prüfung»:" ||
    [[ "$ANTWORT" != "ohne Prüfung" ]]; then
    abbruch "Ohne grüne Prüfung (pruefen.yml) wird nicht signiert."
  fi
  warnung "Signiert ohne geprüfte CI (bewusst bestätigt)."
}

ci_pruefen() {
  local stand versuch=1
  if ! command -v gh >/dev/null 2>&1; then
    ci_ohne_pruefung "gh fehlt"
    return
  fi
  while :; do
    stand=$(ci_stand) || { ci_ohne_pruefung "gh hat keinen Zugriff (gh auth status)"; return; }
    case "$stand" in
      "completed success")
        meldung "CI: pruefen.yml ist grün für $(kurz "$HEAD_OID")."
        return
        ;;
      completed*) abbruch "Die Prüfung pruefen.yml ist für $(kurz "$HEAD_OID") nicht grün (${stand#completed }). Erst beheben." ;;
    esac
    if (( versuch >= CI_VERSUCHE )); then
      case "$stand" in
        "" | null*) abbruch "Für $(kurz "$HEAD_OID") gibt es keinen Lauf von pruefen.yml (gepusht?). Erst wenn er grün ist." ;;
        *) abbruch "pruefen.yml ist für $(kurz "$HEAD_OID") nach $(( CI_VERSUCHE * CI_PAUSE / 60 )) Min. nicht fertig ($stand). Später noch einmal." ;;
      esac
    fi
    if (( versuch == 1 )); then
      case "$stand" in
        "" | null*) meldung "CI: Für $(kurz "$HEAD_OID") gibt es noch keinen Lauf von pruefen.yml, warte (Ctrl+C bricht ab) …" ;;
        *) meldung "CI: pruefen.yml läuft noch für $(kurz "$HEAD_OID") ($stand), warte (Ctrl+C bricht ab) …" ;;
      esac
    fi
    versuch=$(( versuch + 1 ))
    sleep "$CI_PAUSE"
  done
}

# --- Anzeige ---------------------------------------------------------------------------------------------------

gruppe_titel() {
  case "$1" in
    firewall) printf 'Firewall · Rückfrage am Gerät' ;;
    netz) printf 'Netz · Rückfrage am Gerät' ;;
    boot) printf 'Boot · Rückfrage am Gerät' ;;
    anmeldung) printf 'Anmeldung und Rechte' ;;
    vertrauen) printf 'Vertrauen und Updates' ;;
    *) printf '%s' "$1" ;;
  esac
}

# sensible_liste REV… → «GRUPPE PFAD» aus scripts/lib/sensible-pfade aller REVs, vereinigt; dazu fest der Anker,
# das Skript und die Liste selbst
sensible_liste() {
  local rev
  {
    printf 'vertrauen system/vertrauen/\nvertrauen scripts/release-signieren.sh\nvertrauen scripts/lib/sensible-pfade\n'
    for rev in "$@"; do
      g cat-file blob "$rev:scripts/lib/sensible-pfade" 2>/dev/null || true
    done
  } | grep -v -E '^[[:space:]]*(#|$)' | awk 'NF == 2 { print $1 " " $2 }' | sort -u
}

# sensibel_zeigen BASIS – Änderungen an sensiblen Pfaden von BASIS nach HEAD, je Gruppe
sensibel_zeigen() {
  local basis=$1 gruppe pfad zeilen=0
  local -a pfade
  shift
  sensible_liste "$@" > "$TMP/sensibel"
  ALLE_SENSIBLEN=0
  : > "$TMP/sensibel-pfade"
  for gruppe in $GRUPPEN; do
    pfade=()
    while read -r _ pfad; do
      pfade+=("$pfad")
      printf '%s\n' "$pfad" >> "$TMP/sensibel-pfade"
    done < <(grep "^$gruppe " "$TMP/sensibel")
    if (( ${#pfade[@]} == 0 )); then continue; fi
    g diff --numstat --no-renames "$basis" "$HEAD_OID" -- "${pfade[@]}" > "$TMP/numstat" || true
    if [[ -s "$TMP/numstat" ]]; then
      meldung "  $(gruppe_titel "$gruppe")"
      awk -F '\t' '{ printf "      %s  (+%s −%s)\n", $3, $1, $2 }' "$TMP/numstat"
      zeilen=$((zeilen + 1))
    fi
  done
  if (( zeilen == 0 )); then
    meldung "  keine"
  fi
  ALLE_SENSIBLEN=$zeilen
}

# diff_sensibel BASIS – der ganze Diff der sensiblen Pfade
diff_sensibel() {
  local -a pfade=()
  local pfad
  while IFS= read -r pfad; do pfade+=("$pfad"); done < <(sort -u "$TMP/sensibel-pfade")
  if (( ${#pfade[@]} > 0 )); then
    g diff "$1" "$HEAD_OID" -- "${pfade[@]}"
  fi
}

# --- Signieren, prüfen, pushen ---------------------------------------------------------------------------------

# signieren NAME SCHLUESSEL NACHRICHT – erzeugt den signierten Tag auf HEAD
signieren() {
  local name=$1 schluessel=$2 nachricht=$3
  meldung ""
  meldung "Signiere $name mit $(fingerabdruck "$schluessel") …"
  TAG_UNGEPRUEFT=$name
  if ! g -c gpg.format=ssh -c "gpg.ssh.program=$PROGRAMM" -c "user.signingkey=key::$schluessel" \
    tag -s -m "$nachricht" "$name" "$HEAD_OID"; then
    if [[ -z "$(lokal_oid "$name")" ]]; then TAG_UNGEPRUEFT=""; fi
    abbruch "Signieren ist fehlgeschlagen. Ist der Schlüssel in 1Password und für den SSH-Agent freigegeben?"
  fi
}

# nach_signieren_pruefen NAME SIGNERS WIDERRUFEN PRINZIPAL – prüft den eben erzeugten Tag; sonst weg damit
nach_signieren_pruefen() {
  local oid
  oid=$(lokal_oid "$1")
  if ! tag_pruefen "$oid" "$1" "$2" "$3" "$4" "$HEAD_OID"; then
    abbruch "Der neue Tag $1 besteht die Prüfung nicht: $TAG_GRUND"
  fi
  TAG_UNGEPRUEFT=""
  meldung "Geprüft: $1 ist gültig signiert ($(grep -o 'SHA256:[A-Za-z0-9+/=]*' "$TMP/verify" | head -n 1))."
}

pushen() {
  local name=$1 oid remote
  oid=$(lokal_oid "$name")
  meldung ""
  if ! frage "Tag $name jetzt nach origin pushen? Tippe «ja»:" || [[ "$ANTWORT" != ja ]]; then
    meldung "Nicht gepusht. Der Tag bleibt lokal."
    meldung "  Später pushen:  git push origin refs/tags/$name"
    meldung "  Verwerfen:      git tag -d $name"
    return 0
  fi
  if ! g push --no-follow-tags origin "refs/tags/$name:refs/tags/$name"; then
    printf 'release-signieren: Pushen ist fehlgeschlagen. Der Tag bleibt lokal (git push origin refs/tags/%s).\n' \
      "$name" >&2
    exit 1
  fi
  remote=$(g ls-remote --refs origin "refs/tags/$name" | awk -v ref="refs/tags/$name" '$2 == ref { print $1 }')
  if [[ "$remote" != "$oid" ]]; then
    printf 'release-signieren: Auf origin zeigt %s nicht auf den neuen Tag (%s).\n' "$name" "${remote:-fehlt}" >&2
    exit 1
  fi
  meldung "Gepusht: $name ist auf origin."
}

bestaetigen_signieren() {
  local basis=$1
  while :; do
    meldung ""
    if (( ALLE_SENSIBLEN > 0 )); then
      frage "Durchgesehen? «ja» signiert, «d» zeigt den Diff der sensiblen Pfade, Enter bricht ab:" || ANTWORT=""
    else
      frage "Durchgesehen? «ja» signiert, Enter bricht ab:" || ANTWORT=""
    fi
    case "$ANTWORT" in
      ja) return 0 ;;
      d) if (( ALLE_SENSIBLEN > 0 )); then diff_sensibel "$basis"; else return 1; fi ;;
      *) return 1 ;;
    esac
  done
}

# --- Release ---------------------------------------------------------------------------------------------------

release() {
  local tag=$1 letztes="" v basis basis_text anzahl serie name oid sig_text kanal
  if [[ ! "$tag" =~ $VERSION_ERE ]]; then
    meldung "Ungültiger Name «$tag». Erlaubt: vX.Y.Z oder vX.Y.Z-rcN (ohne führende Nullen)." >&2
    exit 2
  fi
  kanal=stabil
  case "$tag" in *-rc*) kanal=vorschau ;; esac

  signierprogramm_waehlen
  stand_pruefen
  tag_neu_pruefen "$tag"

  if ! anker_lesen "$HEAD_OID" "$TMP/neu"; then
    abbruch "Anker unvollständig: $ANKER_GRUND. Ohne Schlüssel in system/vertrauen gibt es kein signiertes Release."
  fi

  # Das höchste Release auf origin
  while IFS= read -r v; do
    if [[ -z "$letztes" ]] || version_hoeher "$v" "$letztes"; then letztes=$v; fi
  done < <(awk '{ sub("^refs/tags/", "", $2); print $2 }' "$TMP/remote-tags" | grep -E "$VERSION_ERE" || true)

  if [[ -n "$letztes" ]]; then
    abweichung_pruefen "$letztes"
    if ! version_hoeher "$tag" "$letztes"; then
      abbruch "$tag ist nicht höher als das letzte Release $letztes."
    fi
    if ! g merge-base --is-ancestor "refs/tags/$letztes^{commit}" "$HEAD_OID"; then
      abbruch "HEAD baut nicht auf $letztes auf. Ein Release kommt immer nach dem letzten, nie daneben."
    fi
  fi
  abweichungen_melden
  ci_pruefen

  # Anker: gegenüber dem letzten Release nur mit höherer Serie verändert, und dann mit Tag vertrauen/NNNN
  serie=$(cat "$TMP/neu/serie.wert")
  if [[ -n "$letztes" ]] && anker_lesen "refs/tags/$letztes^{commit}" "$TMP/alt"; then
    if ! cmp -s "$TMP/alt/wurzel.schluessel" "$TMP/neu/wurzel.schluessel"; then
      abbruch "Die Wurzel hat sich seit $letztes geändert. Die Wurzel ändert sich nie über ein Release."
    fi
    if (( serie < $(cat "$TMP/alt/serie.wert") )); then
      abbruch "Die Serie des Ankers ist kleiner als in $letztes."
    fi
    if (( serie == $(cat "$TMP/alt/serie.wert") )) && ! anker_gleich "$TMP/alt" "$TMP/neu"; then
      abbruch "Der Anker hat sich seit $letztes geändert, ohne neue Serie. Ein neuer Anker braucht eine höhere Serie und den Tag vertrauen/NNNN (--vertrauen)."
    fi
    ANKER_TEXT="wie in $letztes"
    if (( serie > $(cat "$TMP/alt/serie.wert") )); then ANKER_TEXT="neue Serie $serie seit $letztes"; fi
  else
    ANKER_TEXT="ERSTER ANKER in einem signierten Release: Fingerabdrücke mit 1Password vergleichen"
  fi
  if (( serie >= 2 )); then
    name=vertrauen/$(printf '%04d' "$serie")
    oid=$(remote_oid "$name")
    if [[ -z "$oid" ]]; then
      abbruch "Der Anker hat Serie $serie, aber den Tag $name gibt es auf origin nicht. Zuerst: scripts/release-signieren.sh --vertrauen"
    fi
    abweichung_pruefen "$name"
    if ! tag_pruefen "$oid" "$name" "$TMP/neu/wurzel" "$TMP/neu/widerrufen" zenos-wurzel; then
      abbruch "Der Tag $name ist ungültig: $TAG_GRUND"
    fi
    if ! anker_lesen "$oid^{commit}" "$TMP/tag" || ! anker_gleich "$TMP/tag" "$TMP/neu"; then
      abbruch "Der Anker in HEAD passt nicht zum Tag $name."
    fi
  fi

  # Übersicht
  meldung ""
  meldung "Release $tag (Kanal $kanal) auf $(kurz "$HEAD_OID") · $(g log -1 --format=%s "$HEAD_OID")"
  if [[ -n "$letztes" ]]; then
    sig_text="unsigniert"
    if grep -q -e '-----BEGIN SSH SIGNATURE-----' < <(g cat-file tag "refs/tags/$letztes" 2>/dev/null); then
      if tag_pruefen "$(lokal_oid "$letztes")" "$letztes" "$TMP/neu/release" "$TMP/neu/widerrufen" zenos-release; then
        sig_text="gültig signiert"
      else
        sig_text="signiert, aber nicht gültig für diesen Anker"
      fi
    fi
    meldung "Letztes Release: $letztes ($sig_text)"
    basis=$(g rev-parse "refs/tags/$letztes^{commit}")
    basis_text="seit $letztes"
    anzahl=$(g rev-list --count "$basis..$HEAD_OID")
  else
    meldung "Letztes Release: keines (erstes Release)"
    basis=$(g hash-object -t tree /dev/null)
    basis_text="seit Beginn"
    anzahl=$(g rev-list --count "$HEAD_OID")
  fi
  meldung "Anker: Serie $serie, $ANKER_TEXT"
  meldung "  Release-Schlüssel:"
  schluessel_zeigen "$TMP/neu/release.schluessel" "      "
  meldung "  Wurzel:"
  schluessel_zeigen "$TMP/neu/wurzel.schluessel" "      "
  meldung "  Widerrufen:"
  schluessel_zeigen "$TMP/neu/widerrufen.schluessel" "      "
  meldung ""
  if (( anzahl == 0 )); then
    meldung "Commits $basis_text: keine (gleicher Stand wie $letztes)"
  elif [[ -n "$letztes" ]]; then
    meldung "Commits $basis_text ($anzahl):"
    g log --no-decorate --format='  %h  %s' "$basis..$HEAD_OID"
  else
    meldung "Commits $basis_text ($anzahl, die neuesten 30):"
    g log --no-decorate --format='  %h  %s' -n 30 "$HEAD_OID"
  fi
  meldung ""
  meldung "Sensible Pfade $basis_text:"
  if [[ -n "$letztes" ]]; then
    sensibel_zeigen "$basis" "$HEAD_OID" "refs/tags/$letztes^{commit}"
  else
    sensibel_zeigen "$basis" "$HEAD_OID"
  fi

  bestaetigen_signieren "$basis" || abbruch "Abgebrochen."
  signieren "$tag" "$(head -n 1 "$TMP/neu/release.zeilen" | cut -d' ' -f3-)" "zenOS $tag"
  nach_signieren_pruefen "$tag" "$TMP/neu/release" "$TMP/neu/widerrufen" zenos-release
  pushen "$tag"
}

# --- Vertrauen -------------------------------------------------------------------------------------------------

vertrauen() {
  local serie name hoechste=0 n vorher vorher_text bump="" basis c wert nachricht

  signierprogramm_waehlen
  stand_pruefen

  if ! anker_lesen "$HEAD_OID" "$TMP/neu"; then
    abbruch "Anker unvollständig: $ANKER_GRUND."
  fi
  serie=$(cat "$TMP/neu/serie.wert")
  if (( serie < 2 )); then
    abbruch "Serie 1 ist der erste Anker und braucht keinen Tag. Für einen neuen Anker release oder widerrufen ändern und die Serie um 1 erhöhen."
  fi
  name=vertrauen/$(printf '%04d' "$serie")
  tag_neu_pruefen "$name"

  # Höchste Serie auf origin
  while IFS= read -r n; do
    n=${n#vertrauen/}
    n=$((10#$n))
    if (( n > hoechste )); then hoechste=$n; fi
  done < <(awk '{ sub("^refs/tags/", "", $2); print $2 }' "$TMP/remote-tags" | grep -E "$VERTRAUEN_ERE" || true)

  # Der Anker, den die Geräte heute haben: der letzte Tag vertrauen/NNNN oder, vor dem ersten, Serie 1 aus dem
  # Verlauf (der Stand vor dem Commit, der die Serie zuletzt geändert hat)
  if (( hoechste >= 2 )); then
    vorher=vertrauen/$(printf '%04d' "$hoechste")
    abweichung_pruefen "$vorher"
    if ! tag_pruefen "$(remote_oid "$vorher")" "$vorher" "$TMP/neu/wurzel" "$TMP/neu/widerrufen" zenos-wurzel; then
      abbruch "Der letzte Tag $vorher ist ungültig: $TAG_GRUND"
    fi
    vorher_text="Tag $vorher"
    if ! anker_lesen "refs/tags/$vorher^{commit}" "$TMP/alt"; then
      abbruch "Der Anker in $vorher ist unvollständig: $ANKER_GRUND"
    fi
    basis=$(g rev-parse "refs/tags/$vorher^{commit}")
  else
    # Der jüngste Commit, der die Serie auf den heutigen Wert gesetzt hat (spätere Commits ändern dort höchstens
    # Kommentare); sein Vorgänger trägt den Anker davor
    while IFS= read -r c; do
      wert=$(g cat-file blob "$c^:system/vertrauen/serie" 2>/dev/null | grep -v -E '^[[:space:]]*(#|$)' | tr -d ' ')
      if [[ "$wert" != "$serie" ]]; then
        bump=$c
        break
      fi
    done < <(g rev-list "$HEAD_OID" -- system/vertrauen/serie)
    ANKER_GRUND=""
    if [[ -z "$bump" ]] || ! anker_lesen "$bump^" "$TMP/alt"; then
      abbruch "Den Anker vor der Erhöhung der Serie finde ich nicht im Verlauf${ANKER_GRUND:+ ($ANKER_GRUND)}."
    fi
    vorher_text="Stand vor $(kurz "$bump")"
    basis=$(g rev-parse "$bump^")
  fi
  if (( $(cat "$TMP/alt/serie.wert") != serie - 1 )); then
    abbruch "Die Serie muss genau um 1 steigen: vorher $(cat "$TMP/alt/serie.wert") ($vorher_text), jetzt $serie."
  fi
  if (( hoechste >= serie )); then
    abbruch "Auf origin gibt es schon vertrauen/$(printf '%04d' "$hoechste")."
  fi
  if ! cmp -s "$TMP/alt/wurzel.schluessel" "$TMP/neu/wurzel.schluessel"; then
    abbruch "Die Wurzel ist anders als vorher ($vorher_text). Die Wurzel ändert sich nie über das Netz."
  fi
  if [[ -n "$(comm -23 "$TMP/alt/widerrufen.schluessel" "$TMP/neu/widerrufen.schluessel")" ]]; then
    abbruch "Aus widerrufen fehlt ein Schlüssel, der vorher ($vorher_text) widerrufen war. Die Liste wächst nur."
  fi
  if cmp -s "$TMP/alt/release.schluessel" "$TMP/neu/release.schluessel" &&
    cmp -s "$TMP/alt/widerrufen.schluessel" "$TMP/neu/widerrufen.schluessel"; then
    abbruch "Der Anker ändert nichts an release oder widerrufen. Eine neue Serie lohnt sich nur mit einer Änderung."
  fi
  abweichungen_melden

  comm -13 "$TMP/alt/release.schluessel" "$TMP/neu/release.schluessel" > "$TMP/dazu"
  comm -23 "$TMP/alt/release.schluessel" "$TMP/neu/release.schluessel" > "$TMP/weg"
  comm -13 "$TMP/alt/widerrufen.schluessel" "$TMP/neu/widerrufen.schluessel" > "$TMP/widerruf-neu"

  meldung ""
  meldung "Vertrauensanker Serie $serie als $name auf $(kurz "$HEAD_OID") · $(g log -1 --format=%s "$HEAD_OID")"
  meldung "Vorher: Serie $(cat "$TMP/alt/serie.wert") ($vorher_text)"
  meldung "  Wurzel (bleibt):"
  schluessel_zeigen "$TMP/neu/wurzel.schluessel" "      "
  meldung "  Release-Schlüssel neu:"
  schluessel_zeigen "$TMP/dazu" "      "
  meldung "  Release-Schlüssel entfernt:"
  schluessel_zeigen "$TMP/weg" "      "
  meldung "  Neu widerrufen:"
  schluessel_zeigen "$TMP/widerruf-neu" "      "
  meldung "  Release-Schlüssel danach:"
  schluessel_zeigen "$TMP/neu/release.schluessel" "      "
  meldung ""
  meldung "Sensible Pfade seit dem vorigen Anker:"
  sensibel_zeigen "$basis" "$HEAD_OID"

  bestaetigen_signieren "$basis" || abbruch "Abgebrochen."
  nachricht=$(
    printf 'zenOS Vertrauensanker Serie %s\n\nrelease:\n' "$serie"
    schluessel_zeigen "$TMP/neu/release.schluessel" "  "
    printf 'widerrufen:\n'
    schluessel_zeigen "$TMP/neu/widerrufen.schluessel" "  "
  )
  signieren "$name" "$(cat "$TMP/neu/wurzel.schluessel")" "$nachricht"
  # Geprüft wie auf dem Gerät: gegen die Wurzel und die Widerrufe von vorher
  nach_signieren_pruefen "$name" "$TMP/neu/wurzel" "$TMP/alt/widerrufen" zenos-wurzel
  pushen "$name"
}

# --- Start -----------------------------------------------------------------------------------------------------

if (( $# != 1 )); then
  hilfe >&2
  exit 2
fi
case "$1" in
  -h | --hilfe) hilfe; exit 0 ;;
esac

WURZEL=$(cd -- "$(dirname -- "$0")/.." && pwd -P) || exit 1
if [[ "$(git -C "$WURZEL" rev-parse --show-toplevel 2>/dev/null)" != "$WURZEL" ]]; then
  printf 'release-signieren: %s ist kein git-Repo.\n' "$WURZEL" >&2
  exit 1
fi
werkzeuge_pruefen
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zenos-signieren.XXXXXX") || exit 1
trap aufraeumen EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

case "$1" in
  --vertrauen) vertrauen ;;
  -*) hilfe >&2; exit 2 ;;
  *) release "$1" ;;
esac
exit 0
