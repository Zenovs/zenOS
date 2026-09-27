#!/usr/bin/env bash
# pruefen.sh – Selbsttest des Repos. Läuft unter Linux (Testcontainer, Pi, CI), nicht auf dem Mac-Host.
#
#   scripts/pruefen.sh [--ausfuehrlich] [teil …]
#   Teile: shellcheck python json hex shc namen qmllint gitleaks start (ohne Angabe: alle)
#
# Geprüft werden alle Dateien des Arbeitsstands, die Git nicht ignoriert (versioniert oder neu).
#
# Teil shellcheck: jede Datei mit Endung .sh oder mit sh/bash-Shebang (install.sh, lib, module, zen, zen.d,
#   doctor.d, bin, test/container, .githooks, image …), mit -x und --source-path=SCRIPTDIR.
#   Gesourcte Teile (scripts/lib, scripts/module, scripts/zen.d, scripts/doctor.d) nutzen Variablen
#   und Funktionen von install.sh bzw. zen; dort sind SC2034 und SC2154 abgeschaltet.
# Teil python: python3 -m py_compile für jede Datei mit python-Shebang oder Endung .py (Cache im Temp-Ordner).
# Teil json: Syntax (auch doppelte Schlüssel) für alle *.json, dann Schema nach Namenskonvention:
#   config/schema/*.schema.json          selbst ein gültiges JSON-Schema (check_schema)
#   shell/theme/tokens.json              → config/schema/tokens.schema.json
#   config/vorlagen/<art>/<name>.json    → config/schema/<einzahl>.schema.json
#                                          (zustaende → zustand, modi → modus, sonst <art>)
#   config/vorlagen/<name>.json          → config/schema/<name>.schema.json
#   config/beispiele/<art>.<name>.json   → config/schema/<art>.schema.json
#   Fehlt das Schema, wird nur die Syntax geprüft (Hinweis).
# Teil hex: in shell/**/*.qml und *.js ausser shell/theme/Theme.qml keine Hex-Farben («#rgb», «#rgba»,
#   «#rrggbb», «#aarrggbb» als String, #rrggbb/#aarrggbb auch ungequotet), keine Farbnamen-Literale
#   (SVG-Farbnamen als String, «transparent» ist erlaubt) und kein Qt.rgba/Qt.hsla/Qt.hsva.
# Teil shc: in shell/ kein ["sh", "-c"] (auch bash, dash, zsh, fish, -lc …); in scripts/ kein eval, kein
#   «sh -c»/«bash -c» mit Variablen, in Python kein shell=True, os.system, os.popen.
#   Kommentarzeilen zählen nicht; pruefen.sh selbst ist ausgenommen (enthält die Muster).
# Teil namen: Dateinamen nur ASCII; install.sh, zen, pruefen.sh, scripts/bin/*, test/container/*.sh und
#   .githooks/* ausführbar.
# Teil qmllint: Quickshell erzeugt die qmldir-Dateien der qs.*-Module erst zur Laufzeit. pruefen.sh baut sie
#   im Temp-Ordner nach (qs.<ordner>, Singletons über «pragma Singleton», «//@ pragma Internal»),
#   kopiert shell/ dorthin und prüft die Kopien mit -I <temp> -I /usr/local/lib/qt6/qml (so sieht qmllint
#   auch Typen im eigenen Ordner wie Quickshell). Die Meldungen nennen wieder die Pfade unter shell/.
#   «uncreatable-type» ist abgeschaltet (Quickshell-Fenstertypen erscheinen fälschlich so).
#   Fehler: Syntaxfehler und andere kritische Meldungen. Alle anderen Befunde sind Warnungen und
#   lassen den Test nicht scheitern (Liste mit --ausfuehrlich). Vier bekannte Fehlalarme aus Quickshells
#   Typdaten (FileView.adapter, Process.onExited, Notification.actions, PanelWindow.margins) bleiben immer
#   Warnungen und werden getrennt gezählt. Ohne Quickshell-Module (z. B. in CI) zählen nur Syntaxfehler.
#   Fehlt qmllint, wird übersprungen.
# Teil gitleaks: «gitleaks detect --redact» über den Git-Verlauf und über eine Kopie des Arbeitsstands
#   (--no-git), Syntax von gitleaks 8.16. Gefundene Geheimnisse erscheinen nur geschwärzt.
# Teil start: startet jede Einstiegsdatei (shell/shell.qml, dazu jede kleingeschriebene .qml-Datei unter shell/
#   mit «ShellRoot», z. B. greeter.qml) mit Quickshell in labwc ohne Bildschirm und wertet das Protokoll aus.
#   Die Testsitzung ist abgeschottet: eigenes HOME, eigene XDG-Ordner und eigener Sitzungsbus ohne Dienste im
#   Temp-Ordner, ZENOS_CODE zeigt auf dieses Repo. In shell.qml folgt ein Rundgang über IPC (Thema hin und
#   zurück, Befehlsfeld, Zentrale, Umschalter, jede Einstellungen-Seite, Einrichtung, Hinweis,
#   Bildschirmfreigabe, zuletzt die Sperre).
#   Fehler: kein «Configuration Loaded» im Zeitlimit, Absturz, ERROR-Zeilen, «Type … unavailable», «is not a
#   type», ReferenceError/TypeError, «Cannot assign», «Binding loop», Warnungen aus Dateien unter shell/,
#   console.warn/console.error, ein gescheiterter IPC-Aufruf und eine Sperre, die nicht «gesperrt» meldet.
#   Ausnahmen stehen begründet in START_BEKANNT. Ohne labwc, quickshell oder dbus-run-session wird
#   übersprungen (kein Fehler).
#
# Exit 0, wenn alles sauber ist, sonst 1. Fehlende Pflichtwerkzeuge (shellcheck, python3 mit jsonschema,
# gitleaks) zählen als Fehler.

# Die Teile werden über "pruefe_$teil" aufgerufen.
# shellcheck disable=SC2329

set -uo pipefail
export LC_ALL=C.UTF-8

WURZEL=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd -P)
cd -- "$WURZEL" || exit 1

AUSFUEHRLICH=0
TEILE=()
ALLE_TEILE=(shellcheck python json hex shc namen qmllint gitleaks start)
for arg in "$@"; do
  case "$arg" in
    --ausfuehrlich | -v) AUSFUEHRLICH=1 ;;
    -h | --hilfe | --help)
      sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    shellcheck | python | json | hex | shc | namen | qmllint | gitleaks | start) TEILE+=("$arg") ;;
    *) printf 'pruefen.sh: unbekannter Teil «%s» (%s)\n' "$arg" "${ALLE_TEILE[*]}" >&2; exit 2 ;;
  esac
done
(( ${#TEILE[@]} > 0 )) || TEILE=("${ALLE_TEILE[@]}")

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zenos-pruefen.XXXXXX")
START_GRUPPE=""
START_QS=""
START_QS_GRUPPE=""
aufraeumen() {
  # eine noch laufende Testsitzung (Teil start) beenden: Quickshell mit seinen Kindprozessen und die
  # Prozessgruppe um labwc
  if [[ -n "$START_QS" ]]; then kill -KILL "$START_QS" 2>/dev/null || true; fi
  if [[ -n "$START_QS_GRUPPE" ]]; then kill -KILL -- "-$START_QS_GRUPPE" 2>/dev/null || true; fi
  if [[ -n "$START_GRUPPE" ]]; then kill -KILL -- "-$START_GRUPPE" 2>/dev/null || true; fi
  rm -rf -- "$TMP"
}
trap aufraeumen EXIT
trap 'exit 130' INT TERM

TEILE_MIT_FEHLERN=0
FEHLER_LISTE=()

ok() { printf '  ✓ %s\n' "$*"; }
hinweis() { printf '  · %s\n' "$*"; }
fehler() {
  printf '  ✗ %s\n' "$*"
  TEILE_MIT_FEHLERN=$((TEILE_MIT_FEHLERN + 1))
  FEHLER_LISTE+=("$1")
}
details() { sed 's/^/      /'; }
dateien() { if (( $1 == 1 )); then printf '1 Datei'; else printf '%s Dateien' "$1"; fi; }
anzahl() { if (( $1 == 1 )); then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi; }

# Alle nicht ignorierten, vorhandenen Dateien (NUL-getrennt) nach $TMP/dateien
if git -C "$WURZEL" rev-parse --git-dir >/dev/null 2>&1; then
  IST_GIT=1
  git -C "$WURZEL" ls-files -z --cached --others --exclude-standard | sort -zu > "$TMP/alle"
else
  IST_GIT=0
  find . -path ./.git -prune -o \( -type f -o -type l \) -print0 | sed -z 's|^\./||' | sort -z > "$TMP/alle"
fi
DATEIEN=()
while IFS= read -r -d '' f; do
  [[ -f "$f" || -L "$f" ]] && DATEIEN+=("$f")
done < "$TMP/alle"

# Dateien mit Endung oder Shebang
ist_shell() {
  [[ "$1" == *.sh ]] && return 0
  [[ -f "$1" && ! -L "$1" ]] || return 1
  head -n 1 -- "$1" 2>/dev/null | grep -qE '^#!.*[/ ](ba|da)?sh([[:space:]]|$)'
}
ist_python() {
  [[ "$1" == *.py ]] && return 0
  [[ -f "$1" && ! -L "$1" ]] || return 1
  head -n 1 -- "$1" 2>/dev/null | grep -qE '^#!.*python3?([[:space:]]|$)'
}

# --- shellcheck ------------------------------------------------------------

pruefe_shellcheck() {
  if ! command -v shellcheck >/dev/null; then fehler "shellcheck fehlt (apt install shellcheck)"; return; fi
  local f
  local -a normal=() teile=()
  for f in "${DATEIEN[@]}"; do
    ist_shell "$f" || continue
    case "$f" in
      scripts/lib/* | scripts/module/* | scripts/zen.d/* | scripts/doctor.d/*) teile+=("$f") ;;
      *) normal+=("$f") ;;
    esac
  done
  local anzahl=$(( ${#normal[@]} + ${#teile[@]} )) rc=0
  : > "$TMP/shellcheck"
  if (( ${#normal[@]} > 0 )); then
    shellcheck -x --source-path=SCRIPTDIR -f gcc -- "${normal[@]}" >> "$TMP/shellcheck" 2>&1 || rc=1
  fi
  if (( ${#teile[@]} > 0 )); then
    shellcheck -x --source-path=SCRIPTDIR -f gcc -e SC2034,SC2154 -- "${teile[@]}" >> "$TMP/shellcheck" 2>&1 || rc=1
  fi
  if (( rc == 0 )); then
    ok "shellcheck · $(dateien "$anzahl")"
  else
    fehler "shellcheck · $(wc -l < "$TMP/shellcheck" | tr -d ' ') Befunde in $(dateien "$anzahl")"
    details < "$TMP/shellcheck"
  fi
}

# --- python ----------------------------------------------------------------

pruefe_python() {
  local f anzahl=0 rc=0
  : > "$TMP/python"
  for f in "${DATEIEN[@]}"; do
    ist_python "$f" || continue
    anzahl=$((anzahl + 1))
    PYTHONPYCACHEPREFIX="$TMP/pycache" python3 -m py_compile "$f" >> "$TMP/python" 2>&1 || rc=1
  done
  if (( anzahl == 0 )); then
    hinweis "python · keine Python-Skripte"
  elif (( rc == 0 )); then
    ok "python · $(dateien "$anzahl") kompiliert"
  else
    fehler "python · Syntaxfehler"
    details < "$TMP/python"
  fi
}

# --- json ------------------------------------------------------------------

pruefe_json() {
  if ! python3 -c 'import jsonschema' 2>/dev/null; then
    fehler "json · python3-jsonschema fehlt (apt install python3-jsonschema)"
    return
  fi
  local f
  : > "$TMP/json-liste"
  for f in "${DATEIEN[@]}"; do
    [[ "$f" == *.json ]] && printf '%s\0' "$f" >> "$TMP/json-liste"
  done
  local rc=0
  python3 - "$TMP/json-liste" > "$TMP/json" 2>&1 <<'PY' || rc=$?
import json
import os
import sys

import jsonschema

EINZAHL = {"zustaende": "zustand", "modi": "modus"}


def schema_fuer(pfad):
    teile = pfad.split("/")
    name = teile[-1]
    if pfad == "shell/theme/tokens.json":
        return "config/schema/tokens.schema.json"
    if teile[:2] == ["config", "vorlagen"]:
        if len(teile) == 4:
            return f"config/schema/{EINZAHL.get(teile[2], teile[2])}.schema.json"
        if len(teile) == 3:
            return f"config/schema/{name[:-len('.json')]}.schema.json"
    if teile[:2] == ["config", "beispiele"] and len(teile) == 3:
        return f"config/schema/{name.split('.')[0]}.schema.json"
    return None


def ohne_doppelte(paare):
    gesehen = {}
    for schluessel, wert in paare:
        if schluessel in gesehen:
            raise ValueError(f"doppelter Schlüssel «{schluessel}»")
        gesehen[schluessel] = wert
    return gesehen


def laden(pfad):
    with open(pfad, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=ohne_doppelte)


with open(sys.argv[1], "rb") as f:
    dateien = [p.decode() for p in f.read().split(b"\0") if p]

fehler = 0
geprueft = 0
ohne_schema = []
for pfad in dateien:
    try:
        daten = laden(pfad)
    except (OSError, ValueError) as e:
        print(f"{pfad}: {e}")
        fehler += 1
        continue
    if pfad.startswith("config/schema/") and pfad.endswith(".schema.json"):
        try:
            jsonschema.validators.validator_for(daten).check_schema(daten)
            geprueft += 1
        except jsonschema.exceptions.SchemaError as e:
            print(f"{pfad}: ungültiges JSON-Schema: {e.message}")
            fehler += 1
        continue
    schema_pfad = schema_fuer(pfad)
    if schema_pfad is None:
        continue
    if not os.path.exists(schema_pfad):
        ohne_schema.append(f"{pfad} (erwartet {schema_pfad})")
        continue
    try:
        schema = laden(schema_pfad)
    except (OSError, ValueError):
        continue  # das Schema selbst meldet seine eigene Zeile
    klasse = jsonschema.validators.validator_for(schema)
    try:
        klasse.check_schema(schema)
    except jsonschema.exceptions.SchemaError:
        continue
    pruefer = getattr(klasse, "FORMAT_CHECKER", None) or jsonschema.FormatChecker()
    befunde = sorted(klasse(schema, format_checker=pruefer).iter_errors(daten),
                     key=lambda e: [str(p) for p in e.absolute_path])
    for e in befunde:
        ort = "/".join(str(p) for p in e.absolute_path) or "(Wurzel)"
        print(f"{pfad}: {ort}: {e.message}  [{schema_pfad}]")
    fehler += len(befunde)
    geprueft += 1

print(f"#zusammenfassung {len(dateien)} {geprueft} {fehler}")
for z in ohne_schema:
    print(f"#ohne-schema {z}")
sys.exit(1 if fehler else 0)
PY
  local zusammenfassung anzahl_json geprueft
  zusammenfassung=$(grep '^#zusammenfassung ' "$TMP/json" | tail -n 1)
  read -r _ anzahl_json geprueft _ <<< "$zusammenfassung"
  if (( rc == 0 )); then
    ok "json · $(dateien "${anzahl_json:-0}") gültig, ${geprueft:-0} davon gegen ein Schema"
  else
    fehler "json · Fehler"
    grep -v '^#' "$TMP/json" | details
  fi
  grep '^#ohne-schema ' "$TMP/json" | sed 's/^#ohne-schema /ohne Schema, nur Syntax: /' | while IFS= read -r z; do
    hinweis "$z"
  done
}

# --- Hex- und Farbregel ----------------------------------------------------

FARBNAMEN='aliceblue|antiquewhite|aqua|aquamarine|azure|beige|bisque|black|blanchedalmond|blue|blueviolet|brown|burlywood|cadetblue|chartreuse|chocolate|coral|cornflowerblue|cornsilk|crimson|cyan|darkblue|darkcyan|darkgoldenrod|darkgray|darkgreen|darkgrey|darkkhaki|darkmagenta|darkolivegreen|darkorange|darkorchid|darkred|darksalmon|darkseagreen|darkslateblue|darkslategray|darkslategrey|darkturquoise|darkviolet|deeppink|deepskyblue|dimgray|dimgrey|dodgerblue|firebrick|floralwhite|forestgreen|fuchsia|gainsboro|ghostwhite|gold|goldenrod|gray|grey|green|greenyellow|honeydew|hotpink|indianred|indigo|ivory|khaki|lavender|lavenderblush|lawngreen|lemonchiffon|lightblue|lightcoral|lightcyan|lightgoldenrodyellow|lightgray|lightgreen|lightgrey|lightpink|lightsalmon|lightseagreen|lightskyblue|lightslategray|lightslategrey|lightsteelblue|lightyellow|lime|limegreen|linen|magenta|maroon|mediumaquamarine|mediumblue|mediumorchid|mediumpurple|mediumseagreen|mediumslateblue|mediumspringgreen|mediumturquoise|mediumvioletred|midnightblue|mintcream|mistyrose|moccasin|navajowhite|navy|oldlace|olive|olivedrab|orange|orangered|orchid|palegoldenrod|palegreen|paleturquoise|palevioletred|papayawhip|peachpuff|peru|pink|plum|powderblue|purple|red|rosybrown|royalblue|saddlebrown|salmon|sandybrown|seagreen|seashell|sienna|silver|skyblue|slateblue|slategray|slategrey|snow|springgreen|steelblue|tan|teal|thistle|tomato|turquoise|violet|wheat|white|whitesmoke|yellow|yellowgreen'

# Befunde aus grep -n (datei:zeile:text) ohne Kommentarzeilen
ohne_kommentare() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|#|\*)'; }

pruefe_hex() {
  local f
  local -a qml=()
  for f in "${DATEIEN[@]}"; do
    case "$f" in
      shell/theme/Theme.qml) ;;
      shell/*.qml | shell/*.js) qml+=("$f") ;;
    esac
  done
  if (( ${#qml[@]} == 0 )); then hinweis "hex · keine QML-Dateien"; return; fi
  local hex='[0-9A-Fa-f]'
  {
    grep -nHE "\"#($hex{3}|$hex{4}|$hex{6}|$hex{8})\"|'#($hex{3}|$hex{4}|$hex{6}|$hex{8})'" -- "${qml[@]}"
    grep -nHE "#$hex{6}($hex{2})?\b" -- "${qml[@]}" | grep -vE "[\"']#$hex{6}($hex{2})?[\"']"
    grep -nHiE "\"($FARBNAMEN)\"|'($FARBNAMEN)'" -- "${qml[@]}"
    grep -nHE "Qt\.(rgba|hsla|hsva)[[:space:]]*\(" -- "${qml[@]}"
  } 2>/dev/null | sort -u > "$TMP/hex"
  if [[ -s "$TMP/hex" ]]; then
    fehler "hex · Farbwerte ausserhalb von Theme.qml (Farben immer über Theme.<name>)"
    details < "$TMP/hex"
  else
    ok "hex · $(dateien "${#qml[@]}") (QML/JS) ohne Farbwerte"
  fi
}

# --- sh-c-Regel ------------------------------------------------------------

pruefe_shc() {
  local f
  local -a shell=() skripte=() python=()
  for f in "${DATEIEN[@]}"; do
    case "$f" in
      shell/*.qml | shell/*.js) shell+=("$f") ;;
      scripts/pruefen.sh) ;;
      scripts/*)
        if ist_python "$f"; then python+=("$f"); elif ist_shell "$f"; then skripte+=("$f"); fi
        ;;
    esac
  done
  : > "$TMP/shc"
  if (( ${#shell[@]} > 0 )); then
    grep -nHE "[\"'](/usr)?(/bin/)?(ba|da|z|fi)?sh[\"'][[:space:]]*,[[:space:]]*[\"']-[A-Za-z]*c[A-Za-z]*[\"']" \
      -- "${shell[@]}" 2>/dev/null | ohne_kommentare >> "$TMP/shc"
  fi
  if (( ${#skripte[@]} > 0 )); then
    grep -nHE '(^|[;&|({[:space:]])eval([[:space:]]|$)' -- "${skripte[@]}" 2>/dev/null | ohne_kommentare >> "$TMP/shc"
    grep -nHE '(^|[^[:alnum:]_-])(ba|da|z|fi)?sh[[:space:]]+-[A-Za-z]*c([[:space:]]|$).*\$' -- "${skripte[@]}" 2>/dev/null |
      ohne_kommentare >> "$TMP/shc"
  fi
  if (( ${#python[@]} > 0 )); then
    grep -nHE 'shell[[:space:]]*=[[:space:]]*True|os\.system[[:space:]]*\(|os\.popen[[:space:]]*\(' -- "${python[@]}" 2>/dev/null |
      ohne_kommentare >> "$TMP/shc"
  fi
  if [[ -s "$TMP/shc" ]]; then
    fehler "shc · Prozesse über eine Shell statt mit Argumentliste"
    details < "$TMP/shc"
  else
    ok "shc · keine Shell-Aufrufe mit Eingaben ($(dateien $(( ${#shell[@]} + ${#skripte[@]} + ${#python[@]} ))))"
  fi
}

# --- Namen und Rechte ------------------------------------------------------

pruefe_namen() {
  local f
  : > "$TMP/namen"
  for f in "${DATEIEN[@]}"; do
    if LC_ALL=C grep -q '[^ -~]' <<< "$f"; then printf 'Dateiname nicht ASCII: %s\n' "$f" >> "$TMP/namen"; fi
    case "$f" in
      scripts/install.sh | scripts/zen | scripts/pruefen.sh | scripts/bin/* | test/container/*.sh | .githooks/*)
        [[ -L "$f" || -x "$f" ]] || printf 'nicht ausführbar: %s\n' "$f" >> "$TMP/namen"
        ;;
    esac
  done
  if [[ -s "$TMP/namen" ]]; then
    fehler "namen · Dateinamen oder Rechte"
    details < "$TMP/namen"
  else
    ok "namen · $(dateien "${#DATEIEN[@]}"), Namen ASCII, Skripte ausführbar"
  fi
}

# --- qmllint ---------------------------------------------------------------

qmllint_finden() {
  local k
  for k in "$(command -v qmllint 2>/dev/null)" /usr/lib/qt6/bin/qmllint /usr/lib/*/qt6/bin/qmllint; do
    [[ -n "$k" && -x "$k" ]] && { printf '%s' "$k"; return 0; }
  done
  return 1
}

# Baut qs.*-Module wie Quickshell: jeder Ordner unter shell/ ist ein Modul qs.<pfad> (Kopie mit qmldir)
qs_module_bauen() {
  local ziel=$1 ordner rel modul datei name kopf
  while IFS= read -r -d '' ordner; do
    rel=${ordner#shell}
    rel=${rel#/}
    [[ -z "$rel" || "$rel" =~ ^[A-Za-z0-9_/]+$ ]] || continue
    mkdir -p -- "$ziel/qs/$rel"
    modul="qs"
    [[ -z "$rel" ]] || modul="qs.${rel//\//.}"
    {
      printf 'module %s\n' "$modul"
      for datei in "$ordner"/[A-Z]*.qml; do
        [[ -f "$datei" ]] || continue
        name=$(basename -- "$datei" .qml)
        kopf=$(awk '/\{/ { exit } { print }' "$datei")
        if grep -qx '[[:space:]]*//@ pragma Internal[[:space:]]*' <<< "$kopf"; then printf 'internal '; fi
        if grep -qx '[[:space:]]*pragma Singleton[[:space:]]*' <<< "$kopf"; then printf 'singleton '; fi
        printf '%s 1.0 %s.qml\n' "$name" "$name"
      done
    } > "$ziel/qs/$rel/qmldir"
    for datei in "$ordner"/*; do
      [[ -f "$datei" && "$(basename -- "$datei")" != qmldir ]] || continue
      cp -- "$datei" "$ziel/qs/$rel/"
    done
  done < <(find shell -type d -print0 2>/dev/null)
}

pruefe_qmllint() {
  local qmllint f
  local -a qml=() pfade=()
  for f in "${DATEIEN[@]}"; do [[ "$f" == shell/*.qml ]] && qml+=("$TMP/qml/qs/${f#shell/}"); done
  if (( ${#qml[@]} == 0 )); then hinweis "qmllint · keine QML-Dateien"; return; fi
  if ! qmllint=$(qmllint_finden); then hinweis "qmllint · übersprungen (qmllint fehlt; Paket qt6-declarative-dev-tools)"; return; fi

  qs_module_bauen "$TMP/qml"
  pfade=(-I "$TMP/qml")
  local mit_quickshell=0
  for f in /usr/local/lib/qt6/qml /usr/lib/qt6/qml /usr/lib/*/qt6/qml; do
    [[ -d "$f" ]] || continue
    pfade+=(-I "$f")
    [[ -f "$f/Quickshell/qmldir" ]] && mit_quickshell=1
  done
  "$qmllint" "${pfade[@]}" --uncreatable-type disable --json "$TMP/qmllint.json" -- "${qml[@]}" > /dev/null 2>&1
  if [[ ! -s "$TMP/qmllint.json" ]]; then
    fehler "qmllint · keine Ausgabe von $qmllint"
    return
  fi
  local rc=0
  python3 - "$TMP/qmllint.json" "$TMP/qml/qs" "$AUSFUEHRLICH" "$mit_quickshell" > "$TMP/qmllint" <<'PY' || rc=$?
import json
import os
import re
import sys

bericht = json.load(open(sys.argv[1], encoding="utf-8"))
wurzel = sys.argv[2]
ausfuehrlich = sys.argv[3] == "1"
mit_quickshell = sys.argv[4] == "1"

# Bekannte Fehlalarme aus Quickshells Typdaten (v0.3.1). Sie bleiben Warnungen, auch wenn qmllint sie
# schärfer einstuft, und werden getrennt gezählt. Zur Laufzeit funktioniert alles davon.
BEKANNT = [
    # FileView { adapter: JsonAdapter {} }: der Typ der Eigenschaft adapter fehlt
    re.compile(r'No type found for property "adapter"'),
    # Process { onExited: (exitCode, exitStatus) => … }: QProcess::ExitStatus ist nicht exportiert
    re.compile(r"Type QProcess::ExitStatus of parameter exitStatus\b"),
    # Notification.actions: die Liste der NotificationAction-Objekte ist nicht deklarativ exportiert
    re.compile(r'Type "QList<qs::service::notifications::NotificationAction\*>"'),
]
# PanelWindow.margins: gruppierte Eigenschaft ohne Typdaten. qmllint meldet die Gruppe und jede Kante darin
# (auch in der Blockform «margins { top: … }», deshalb bis sechs Zeilen danach).
MARGINS = re.compile(r"unknown grouped property scope margins\.|Type margins is used but it is not resolved")
KANTE = re.compile(r'Could not find property "(top|bottom|left|right)"')

fehler = []
warnungen = {}
details = []
bekannt = 0
for datei in bericht.get("files", []):
    name = "shell/" + os.path.relpath(datei.get("filename", "?"), wurzel)
    liste = datei.get("warnings", [])
    margins = [w.get("line") or 0 for w in liste if MARGINS.search(w.get("message", ""))]
    for w in liste:
        art = w.get("type", "")
        kennung = w.get("id", "")
        meldung = w.get("message", "")
        zeile = w.get("line") or 0
        text = f"{name}:{w.get('line', '?')}:{w.get('column', '?')}: {meldung} [{kennung or art}]"
        if (any(m.search(meldung) for m in BEKANNT) or MARGINS.search(meldung)
                or (KANTE.search(meldung) and any(0 <= zeile - m <= 6 for m in margins))):
            bekannt += 1
            details.append(text + " (bekannter Fehlalarm)")
        elif kennung == "syntax" or (mit_quickshell and art in ("critical", "error")):
            fehler.append(text)
        else:
            warnungen[name] = warnungen.get(name, 0) + 1
            details.append(text)
for z in fehler:
    print("F " + z)
for name, anzahl in sorted(warnungen.items()):
    print(f"W {name}: {anzahl} Warnung{'en' if anzahl != 1 else ''}")
if ausfuehrlich:
    for z in details:
        print("D " + z)
print(f"# {len(bericht.get('files', []))} {len(fehler)} {sum(warnungen.values())} {bekannt}")
sys.exit(1 if fehler else 0)
PY
  local zeile anzahl_qml n_fehler n_warn n_bekannt zusatz=""
  zeile=$(grep '^# ' "$TMP/qmllint" | tail -n 1)
  read -r _ anzahl_qml n_fehler n_warn n_bekannt <<< "$zeile"
  if (( mit_quickshell )); then
    [[ "${n_bekannt:-0}" == 0 ]] || zusatz=", dazu ${n_bekannt} bekannte Fehlalarme aus Quickshells Typdaten"
  else
    zusatz=" (ohne Quickshell-Module: nur Syntaxfehler zählen)"
  fi
  if (( rc == 0 )); then
    ok "qmllint · $(dateien "${anzahl_qml:-0}") ohne Fehler, ${n_warn:-0} Warnungen${zusatz}"
  else
    fehler "qmllint · ${n_fehler:-?} Fehler${zusatz}"
    grep '^F ' "$TMP/qmllint" | cut -c3- | details
  fi
  if (( AUSFUEHRLICH )); then
    grep '^D ' "$TMP/qmllint" | cut -c3- | details
  elif [[ "${n_warn:-0}" != 0 ]]; then
    # ohne Quickshell-Module sind fast alle Warnungen Folgefehler der fehlenden Typen: nur die Summe
    (( mit_quickshell )) && grep '^W ' "$TMP/qmllint" | cut -c3- | details
    printf '      (Einzelheiten: scripts/pruefen.sh --ausfuehrlich qmllint)\n'
  fi
}

# --- gitleaks --------------------------------------------------------------

pruefe_gitleaks() {
  if ! command -v gitleaks >/dev/null; then fehler "gitleaks fehlt (apt install gitleaks)"; return; fi
  local rc=0 f
  : > "$TMP/gitleaks"
  if (( IST_GIT )); then
    gitleaks detect --source "$WURZEL" --redact --no-banner -v --log-level warn \
      --report-path "$TMP/gitleaks-verlauf.json" >> "$TMP/gitleaks" 2>&1 || rc=1
  fi
  # Arbeitsstand ohne ignorierte Dateien (keine Caches, keine Build-Ordner)
  mkdir -p -- "$TMP/baum"
  : > "$TMP/baum-liste"
  for f in "${DATEIEN[@]}"; do printf '%s\0' "$f" >> "$TMP/baum-liste"; done
  tar -c -f - -C "$WURZEL" --null --no-recursion --files-from="$TMP/baum-liste" 2>/dev/null | tar -x -f - -C "$TMP/baum"
  gitleaks detect --no-git --source "$TMP/baum" --redact --no-banner -v --log-level warn \
    --report-path "$TMP/gitleaks-baum.json" >> "$TMP/gitleaks" 2>&1 || rc=1
  if (( rc == 0 )); then
    if (( IST_GIT )); then ok "gitleaks · Verlauf und Arbeitsstand sauber"; else ok "gitleaks · Arbeitsstand sauber"; fi
  else
    fehler "gitleaks · mögliche Geheimnisse gefunden (geschwärzt)"
    sed -e "s|$TMP/baum/||g" -e 's/\x1b\[[0-9;]*m//g' "$TMP/gitleaks" | details
  fi
}

# --- start -----------------------------------------------------------------

START_ZEITLIMIT=90 # Sekunden bis «Configuration Loaded» (Pi mit leerem QML-Cache: wenige Sekunden)

# Bekannte harmlose Meldungen (Python-Regex auf eine Protokollzeile). Nur mit Begründung ergänzen.
START_BEKANNT=(
  # Qt meldet die App-ID beim Desktop-Portal an. Der Sitzungsbus der Testsitzung hat kein Portal, in einer
  # echten Sitzung ist die Verbindung oft schon registriert. Ohne Folgen für die Oberfläche.
  '^\s*WARN qt\.qpa\.services: Failed to register with host portal'
)

# Rundgang über IPC in shell/shell.qml (Ziele und Funktionen aus BAUPLAN 6). Jeder Aufruf muss gelingen.
START_RUNDGANG=(
  "thema wechseln"
  "thema wechseln"
  "befehlsfeld oeffnen"
  "befehlsfeld werkzeuge"
  "befehlsfeld schliessen"
  "mitteilungen zentrale"
  "mitteilungen zentrale"
  "modus waehlen"
  "zustand waehlen"
  "einstellungen oeffnen modi"
  "einstellungen oeffnen zustand"
  "einstellungen oeffnen raster"
  "einstellungen oeffnen bildschirme"
  "einstellungen oeffnen webapps"
  "einstellungen oeffnen apps"
  "einstellungen oeffnen allgemein"
  "einstellungen oeffnen system"
  "einrichtung oeffnen"
  "hinweis zeigen Prüfung"
  # Bildschirmfreigabe mit offener Zentrale (Leitplanke: Inhalte verborgen), danach zurück
  "freigabe gestartet"
  "mitteilungen zentrale"
  "mitteilungen zentrale"
  "freigabe beendet"
)

# lebt PID – läuft der Prozess (und ist kein Zombie)?
start_lebt() {
  local stat
  stat=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
  [[ -n "$stat" && "$stat" != Z* ]]
}

# Prozessgruppe von Quickshell: labwc startet es in einer eigenen Sitzung, seine Kindprozesse (Process in
# QML) bleiben in dieser Gruppe. Nie die eigene Gruppe oder die um labwc.
start_qs_gruppe() {
  local gruppe eigene
  gruppe=$(ps -o pgid= -p "$1" 2>/dev/null | tr -d '[:space:]')
  eigene=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d '[:space:]')
  [[ "$gruppe" =~ ^[0-9]+$ ]] && (( gruppe > 1 )) || return 0
  [[ "$gruppe" != "$eigene" && "$gruppe" != "$START_GRUPPE" ]] && printf '%s' "$gruppe"
  return 0
}

# Wartet, bis das Protokoll 2 s lang nicht mehr wächst (mindestens $2 s, höchstens 20 s)
start_ruhe() {
  local datei=$1 mindestens=${2:-2} groesse alt=-1 still=0 i
  for (( i = 1; i <= 40; i++ )); do
    sleep 0.5
    groesse=$(stat -c %s -- "$datei" 2>/dev/null || echo 0)
    if [[ "$groesse" == "$alt" ]]; then still=$((still + 1)); else still=0; alt=$groesse; fi
    if (( i >= mindestens * 2 && still >= 4 )); then return 0; fi
  done
}

# IPC-Aufruf in die Testsitzung (Ordner, Ziel, Funktion, Argumente). Quickshell v0.3.1 endet auch bei
# Fehlern mit Exit 0 und schreibt die Meldung auf stdout; deshalb zählt zusätzlich die Ausgabe.
# Rückgabe 0 ok, 1 Fehler, 2 keine Antwort in 15 s.
start_ipc() {
  local o=$1 rc=0
  shift
  env HOME="$o/home" XDG_RUNTIME_DIR="$o/lz" XDG_CONFIG_HOME="$o/home/.config" XDG_CACHE_HOME="$o/home/.cache" \
    XDG_DATA_HOME="$o/home/.local/share" XDG_STATE_HOME="$o/home/.local/state" NO_COLOR=1 \
    timeout 15 quickshell ipc --pid "$(cat "$o/quickshell.pid")" call "$@" > "$o/ipc" 2>&1 || rc=$?
  if (( rc == 124 )); then
    printf 'keine Antwort nach 15 s' > "$o/ipc"
    return 2
  fi
  if (( rc != 0 )) ||
    grep -qE '^(Target|Function) not found\.|arguments provided|Unable to parse argument|Not ready to accept|Socket Error|No running instance' \
      "$o/ipc"; then
    return 1
  fi
  return 0
}

# Einstiegsdateien: shell/shell.qml zuerst, dann jede kleingeschriebene .qml-Datei mit ShellRoot
start_einstiege() {
  local f
  [[ -f shell/shell.qml ]] && printf '%s\n' shell/shell.qml
  for f in "${DATEIEN[@]}"; do
    [[ "$f" == shell/*.qml && "$f" != shell/shell.qml && -f "$f" ]] || continue
    [[ "$(basename -- "$f")" == [a-z]* ]] || continue
    grep -qE '^ShellRoot[[:space:]]*\{' -- "$f" && printf '%s\n' "$f"
  done
}

# Startet eine Einstiegsdatei in einer abgeschotteten Testsitzung und schreibt den Bericht nach $o/bericht.
# Rückgabe 0 ohne Befund, sonst 1.
start_lauf() {
  local datei=$1 o=$2 befund=0 geladen=0 qs_pid="" ende
  mkdir -p -- "$o/home/.config" "$o/home/.cache" "$o/home/.local/share" "$o/home/.local/state" "$o/lz" "$o/labwc"
  chmod 0700 -- "$o/lz"
  : > "$o/bericht"
  : > "$o/quickshell.log"

  # Eigener Sitzungsbus ohne Dienstdateien: nichts wird nachgestartet, nichts erreicht die echte Sitzung
  # (z. B. übernimmt der Mitteilungsdienst der Testshell nie den Namen der laufenden Shell).
  local bus_ordner=/tmp
  [[ "$o" =~ ^[A-Za-z0-9/._-]+$ ]] && bus_ordner=$o
  cat > "$o/bus.conf" <<XML
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$bus_ordner</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
XML

  # Startbefehl in labwc (ohne Shell: labwc zerlegt -s nur in Argumente)
  cat > "$o/innen.sh" <<'SH'
#!/usr/bin/env bash
o=$ZENOS_START_ORDNER
if command -v wlr-randr >/dev/null 2>&1; then
  ausgang=$(wlr-randr 2>/dev/null | awk 'NR == 1 { print $1 }')
  wlr-randr --output "${ausgang:-HEADLESS-1}" --custom-mode 1440x900 >/dev/null 2>&1 || true
fi
printf '%s\n' "$$" > "$o/quickshell.pid"
exec quickshell --no-color -p "$ZENOS_START_SHELL" > "$o/quickshell.log" 2>&1 < /dev/null
SH
  chmod 0755 -- "$o/innen.sh"
  local innen_arg="'${o//\'/\'\\\'\'}/innen.sh'"

  # PipeWire der Sitzung mitbenutzen, falls erreichbar (die Leiste liest die Lautstärke; die Testshell
  # ändert nichts daran). Sonst ist die Meldung über den fehlenden PipeWire-Kontext erwartet.
  local pipewire=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  local -a bekannt=("${START_BEKANNT[@]}")
  if [[ ! -S "$pipewire/pipewire-0" ]]; then
    pipewire=""
    bekannt+=('^\s*ERROR quickshell\.service\.pipewire\.loop: Failed to connect pipewire context')
  fi

  (
    cd -- "$o/home" || exit 1
    # Nichts aus einer laufenden Sitzung übernehmen
    unset WAYLAND_DISPLAY DISPLAY LABWC_PID SWAYSOCK DBUS_SESSION_BUS_ADDRESS QT_QPA_PLATFORMTHEME \
      QS_CONFIG_PATH QS_CONFIG_NAME QS_MANIFEST XDG_SESSION_ID XDG_SEAT XDG_VTNR no_proxy NO_PROXY
    # HTTP(S) ins Leere: Abfragen der Testshell (z. B. GitHub-Releases in der Einrichtung) scheitern sofort
    export http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 \
      HTTPS_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 all_proxy=http://127.0.0.1:9
    export HOME="$o/home" XDG_CONFIG_HOME="$o/home/.config" XDG_CACHE_HOME="$o/home/.cache" \
      XDG_DATA_HOME="$o/home/.local/share" XDG_STATE_HOME="$o/home/.local/state" XDG_RUNTIME_DIR="$o/lz" \
      WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
      QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software XDG_CURRENT_DESKTOP=labwc:wlroots \
      XDG_SESSION_TYPE=wayland NO_COLOR=1 ZENOS_CODE="$WURZEL" \
      ZENOS_START_SHELL="$WURZEL/$datei" ZENOS_START_ORDNER="$o"
    if [[ -n "$pipewire" ]]; then export PIPEWIRE_RUNTIME_DIR="$pipewire"; else unset PIPEWIRE_RUNTIME_DIR; fi
    exec setsid dbus-run-session --config-file="$o/bus.conf" -- \
      labwc -C "$o/labwc" -s "$innen_arg" > "$o/labwc.log" 2>&1 < /dev/null
  ) &
  START_GRUPPE=$!

  ende=$((SECONDS + START_ZEITLIMIT))
  while (( SECONDS < ende )); do
    if grep -q 'Configuration Loaded' "$o/quickshell.log" 2>/dev/null; then geladen=1; break; fi
    start_lebt "$START_GRUPPE" || break
    if [[ -s "$o/quickshell.pid" ]]; then
      qs_pid=$(cat "$o/quickshell.pid")
      START_QS=$qs_pid
      [[ -n "$START_QS_GRUPPE" ]] || START_QS_GRUPPE=$(start_qs_gruppe "$qs_pid")
      start_lebt "$qs_pid" || break
    fi
    sleep 0.5
  done
  if [[ -s "$o/quickshell.pid" ]]; then
    qs_pid=$(cat "$o/quickshell.pid")
    START_QS=$qs_pid
    [[ -n "$START_QS_GRUPPE" ]] || START_QS_GRUPPE=$(start_qs_gruppe "$qs_pid")
  fi

  if (( ! geladen )); then
    befund=1
    if [[ -z "$qs_pid" ]]; then
      printf 'Quickshell wurde nicht gestartet. labwc meldet:\n' >> "$o/bericht"
      tail -n 15 "$o/labwc.log" | sed 's/^/  /' >> "$o/bericht"
    elif start_lebt "$qs_pid"; then
      printf 'Kein «Configuration Loaded» nach %s s.\n' "$START_ZEITLIMIT" >> "$o/bericht"
    else
      printf 'Quickshell hat sich vor «Configuration Loaded» beendet.\n' >> "$o/bericht"
    fi
  else
    start_ruhe "$o/quickshell.log" 3
    if [[ "$datei" == shell/shell.qml ]]; then
      local aufruf n=0 antwort=1
      local -a teile
      for aufruf in "${START_RUNDGANG[@]}"; do
        read -r -a teile <<< "$aufruf"
        n=$((n + 1))
        start_ipc "$o" "${teile[@]}"
        case $? in
          0) ;;
          2)
            befund=1 antwort=0
            printf 'IPC «%s»: keine Antwort nach 15 s, Rundgang abgebrochen.\n' "$aufruf" >> "$o/bericht"
            break
            ;;
          *)
            befund=1
            printf 'IPC «%s» gescheitert: %s\n' "$aufruf" "$(tr '\n' ' ' < "$o/ipc")" >> "$o/bericht"
            ;;
        esac
        sleep 0.4
      done
      # Sperre zuletzt. Läuft 1Password, würde zenos-1password-sperren es mitsperren: dann auslassen.
      if (( antwort )) && pgrep -u "$(id -u)" -x 1password > /dev/null 2>&1; then
        printf '#ausgelassen Sperre nicht geprüft: 1Password läuft und würde mitgesperrt.\n' >> "$o/bericht"
      elif (( antwort )); then
        n=$((n + 1))
        if ! start_ipc "$o" sperre sperren; then
          befund=1
          printf 'IPC «sperre sperren» gescheitert: %s\n' "$(tr '\n' ' ' < "$o/ipc")" >> "$o/bericht"
        else
          local status="" i
          for (( i = 0; i < 20; i++ )); do
            sleep 0.5
            start_ipc "$o" sperre status && status=$(tr -d '[:space:]' < "$o/ipc")
            [[ "$status" == gesperrt ]] && break
          done
          if [[ "$status" != gesperrt ]]; then
            befund=1
            printf 'Sperre meldet nach 10 s «%s» statt «gesperrt».\n' "${status:-keine Antwort}" >> "$o/bericht"
          fi
        fi
      fi
      printf '#rundgang %s\n' "$n" >> "$o/bericht"
      start_ruhe "$o/quickshell.log" 2
    fi
    if ! start_lebt "$qs_pid"; then
      befund=1
      printf 'Quickshell hat sich nach dem Laden beendet.\n' >> "$o/bericht"
    fi
  fi

  # Ausgewertet wird der Stand vor dem Beenden (Meldungen beim Abbau der Objekte zählen nicht)
  cp -- "$o/quickshell.log" "$o/auswertung.log"

  # Testsitzung beenden: erst Quickshell (labwc startet es in einer eigenen Sitzung), dann was von seinen
  # Kindprozessen übrig ist (etwa nach einem Hänger mit SIGKILL), zuletzt die Prozessgruppe um labwc (Bus,
  # labwc, dessen Kindprozesse)
  if [[ -n "$qs_pid" ]]; then
    kill -TERM "$qs_pid" 2>/dev/null
    for (( ende = 0; ende < 20; ende++ )); do
      start_lebt "$qs_pid" || break
      sleep 0.25
    done
    kill -KILL "$qs_pid" 2>/dev/null
  fi
  if [[ -n "$START_QS_GRUPPE" ]] && kill -TERM -- "-$START_QS_GRUPPE" 2>/dev/null; then
    sleep 0.5
    kill -KILL -- "-$START_QS_GRUPPE" 2>/dev/null
  fi
  kill -TERM -- "-$START_GRUPPE" 2>/dev/null || kill -TERM "$START_GRUPPE" 2>/dev/null
  for (( ende = 0; ende < 20; ende++ )); do
    start_lebt "$START_GRUPPE" || break
    sleep 0.25
  done
  kill -KILL -- "-$START_GRUPPE" 2>/dev/null
  wait "$START_GRUPPE" 2>/dev/null
  START_GRUPPE=""
  START_QS=""
  START_QS_GRUPPE=""

  # Protokoll auswerten
  local wurzel_shell
  wurzel_shell=$(cd -- "$WURZEL/shell" && pwd -P)
  python3 - "$o/auswertung.log" "$wurzel_shell" "$WURZEL/shell" "${bekannt[@]}" >> "$o/bericht" <<'PY' || befund=1
import re
import sys

protokoll = sys.argv[1]
wurzeln = sorted({sys.argv[2], sys.argv[3]})  # shell/ echt und wie übergeben (Symlinks)
bekannt = [re.compile(r) for r in sys.argv[4:]]

KOPF = re.compile(r"^\s*(DEBUG|INFO|WARN|ERROR|FATAL)(?: ([^\s:]+))?: ")
KRITISCH = re.compile(
    r"Type \S+ unavailable|Failed to load configuration|is not a type|\b(Reference|Type|Syntax|Range)Error\b"
    r"|Cannot assign|Binding loop|is not installed|Unable to assign|qs-blackhole")
AUS_SHELL = re.compile(r"(?<![\w/.])@[\w./-]+\.(?:qml|m?js)\b|qs:@/qs/|"
                       + "|".join(re.escape(w + "/") for w in wurzeln))

meldungen = []
with open(protokoll, encoding="utf-8", errors="replace") as f:
    for zeile in f:
        zeile = re.sub(r"\x1b\[[0-9;]*m", "", zeile.rstrip("\n"))
        kopf = KOPF.match(zeile)
        if kopf or not meldungen:
            meldungen.append({"stufe": kopf.group(1) if kopf else "", "art": (kopf.group(2) or "") if kopf else "",
                              "zeilen": [zeile]})
        elif zeile.strip():
            meldungen[-1]["zeilen"].append(zeile)

fehler = hinweise = anzahl_bekannt = 0
for m in meldungen:
    text = "\n".join(m["zeilen"])
    if not text.strip():
        continue
    if any(b.search(z) for b in bekannt for z in m["zeilen"]):
        anzahl_bekannt += 1
        print("#bekannt " + m["zeilen"][0].strip())
        continue
    if (m["stufe"] in ("ERROR", "FATAL") or KRITISCH.search(text)
            or (m["stufe"] == "WARN" and (m["art"] in ("qml", "js") or AUS_SHELL.search(text)))):
        fehler += 1
        for z in m["zeilen"]:
            print(z.strip())
    elif m["stufe"] == "WARN":
        hinweise += 1
        for z in m["zeilen"]:
            print("#hinweis " + z.strip())
print(f"#zaehler {fehler} {hinweise} {anzahl_bekannt}")
sys.exit(1 if fehler else 0)
PY
  return "$befund"
}

pruefe_start() {
  local k
  local -a fehlt=()
  for k in labwc quickshell dbus-run-session python3 setsid timeout ps; do
    command -v "$k" > /dev/null 2>&1 || fehlt+=("$k")
  done
  if (( ${#fehlt[@]} > 0 )); then
    local verb=fehlt
    (( ${#fehlt[@]} == 1 )) || verb=fehlen
    hinweis "start · übersprungen ($(IFS=,; printf '%s' "${fehlt[*]}" | sed 's/,/, /g') $verb; läuft im Testcontainer oder auf dem Pi)"
    return
  fi
  local -a einstiege=()
  local datei
  while IFS= read -r datei; do einstiege+=("$datei"); done < <(start_einstiege)
  if (( ${#einstiege[@]} == 0 )); then hinweis "start · keine Einstiegsdatei (shell/shell.qml fehlt)"; return; fi

  local o kennung n_befund=0 rundgang="" zaehler n_hinweise=0 n_bekannt=0 f h b zeile
  : > "$TMP/start-bericht"
  : > "$TMP/start-ausgelassen"
  for datei in "${einstiege[@]}"; do
    kennung=${datei#shell/}
    kennung=${kennung%.qml}
    o="$TMP/start/${kennung//\//-}"
    if start_lauf "$datei" "$o"; then
      printf '%s: ohne Befund\n' "$datei" >> "$TMP/start-bericht"
    else
      n_befund=$((n_befund + 1))
      printf '%s:\n' "$datei" >> "$TMP/start-bericht"
      grep -v '^#' "$o/bericht" | sed 's/^/  /' >> "$TMP/start-bericht"
    fi
    zaehler=$(grep '^#zaehler ' "$o/bericht" | tail -n 1)
    read -r _ f h b <<< "$zaehler"
    n_hinweise=$((n_hinweise + ${h:-0}))
    n_bekannt=$((n_bekannt + ${b:-0}))
    if grep -q '^#rundgang ' "$o/bericht"; then
      rundgang=", Rundgang mit $(grep '^#rundgang ' "$o/bericht" | tail -n 1 | cut -d' ' -f2) IPC-Aufrufen"
    fi
    { grep '^#hinweis ' "$o/bericht" | sed "s|^#hinweis |$datei: |"; } >> "$TMP/start-hinweise"
    { grep '^#bekannt ' "$o/bericht" | sed "s|^#bekannt |$datei: bekannt: |"; } >> "$TMP/start-bekannt"
    grep '^#ausgelassen ' "$o/bericht" | cut -d' ' -f2- >> "$TMP/start-ausgelassen"
  done

  local namen="${einstiege[*]#shell/}"
  if (( n_befund == 0 )); then
    ok "start · ${namen// /, } geladen${rundgang}, Protokolle ohne Befund"
  else
    fehler "start · $n_befund von ${#einstiege[@]} Einstiegen mit Befund"
    details < "$TMP/start-bericht"
  fi
  while IFS= read -r zeile; do hinweis "start · $zeile"; done < "$TMP/start-ausgelassen"
  if (( AUSFUEHRLICH )); then
    cat -- "$TMP/start-hinweise" "$TMP/start-bekannt" 2>/dev/null | details
  elif (( n_hinweise > 0 || n_bekannt > 0 )); then
    local -a teile=()
    (( n_hinweise == 0 )) || teile+=("$(anzahl "$n_hinweise" 'weitere Warnung' 'weitere Warnungen') von Qt/Quickshell")
    (( n_bekannt == 0 )) || teile+=("$(anzahl "$n_bekannt" 'bekannte harmlose Meldung' 'bekannte harmlose Meldungen')")
    printf '      (%s; Einzelheiten: scripts/pruefen.sh --ausfuehrlich start)\n' "$(IFS=,; printf '%s' "${teile[*]}" | sed 's/,/, /g')"
  fi
}

# --- Ablauf ----------------------------------------------------------------

printf 'zenOS prüfen · %s im Arbeitsstand\n' "$(dateien "${#DATEIEN[@]}")"
for teil in "${TEILE[@]}"; do
  "pruefe_$teil"
done
printf '\n'
if (( TEILE_MIT_FEHLERN == 0 )); then
  printf 'Alles sauber.\n'
  exit 0
fi
printf 'Fehler in: %s\n' "${FEHLER_LISTE[*]%% ·*}"
exit 1
