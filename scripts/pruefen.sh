#!/usr/bin/env bash
# pruefen.sh – Selbsttest des Repos. Läuft unter Linux (Testcontainer, Pi, CI), nicht auf dem Mac-Host.
#
#   scripts/pruefen.sh [--ausfuehrlich] [teil …]
#   Teile: shellcheck python json hex shc namen qmllint gitleaks (ohne Angabe: alle)
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
#   lassen den Test nicht scheitern (Liste mit --ausfuehrlich). Fehlt qmllint, wird übersprungen.
# Teil gitleaks: «gitleaks detect --redact» über den Git-Verlauf und über eine Kopie des Arbeitsstands
#   (--no-git), Syntax von gitleaks 8.16. Gefundene Geheimnisse erscheinen nur geschwärzt.
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
ALLE_TEILE=(shellcheck python json hex shc namen qmllint gitleaks)
for arg in "$@"; do
  case "$arg" in
    --ausfuehrlich | -v) AUSFUEHRLICH=1 ;;
    -h | --hilfe | --help)
      sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    shellcheck | python | json | hex | shc | namen | qmllint | gitleaks) TEILE+=("$arg") ;;
    *) printf 'pruefen.sh: unbekannter Teil «%s» (%s)\n' "$arg" "${ALLE_TEILE[*]}" >&2; exit 2 ;;
  esac
done
(( ${#TEILE[@]} > 0 )) || TEILE=("${ALLE_TEILE[@]}")

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zenos-pruefen.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

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
  for f in /usr/local/lib/qt6/qml /usr/lib/qt6/qml /usr/lib/*/qt6/qml; do
    [[ -d "$f" ]] && pfade+=(-I "$f")
  done
  "$qmllint" "${pfade[@]}" --uncreatable-type disable --json "$TMP/qmllint.json" -- "${qml[@]}" > /dev/null 2>&1
  if [[ ! -s "$TMP/qmllint.json" ]]; then
    fehler "qmllint · keine Ausgabe von $qmllint"
    return
  fi
  local rc=0
  python3 - "$TMP/qmllint.json" "$TMP/qml/qs" "$AUSFUEHRLICH" > "$TMP/qmllint" <<'PY' || rc=$?
import json
import os
import sys

bericht = json.load(open(sys.argv[1], encoding="utf-8"))
wurzel = sys.argv[2]
ausfuehrlich = sys.argv[3] == "1"
fehler = []
warnungen = {}
details = []
for datei in bericht.get("files", []):
    name = "shell/" + os.path.relpath(datei.get("filename", "?"), wurzel)
    for w in datei.get("warnings", []):
        art = w.get("type", "")
        kennung = w.get("id", "")
        text = f"{name}:{w.get('line', '?')}:{w.get('column', '?')}: {w.get('message', '')} [{kennung or art}]"
        if art in ("critical", "error") or kennung == "syntax":
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
print(f"# {len(bericht.get('files', []))} {len(fehler)} {sum(warnungen.values())}")
sys.exit(1 if fehler else 0)
PY
  local zeile anzahl_qml n_fehler n_warn
  zeile=$(grep '^# ' "$TMP/qmllint" | tail -n 1)
  read -r _ anzahl_qml n_fehler n_warn <<< "$zeile"
  if (( rc == 0 )); then
    ok "qmllint · $(dateien "${anzahl_qml:-0}") ohne Syntaxfehler, ${n_warn:-0} Warnungen"
  else
    fehler "qmllint · ${n_fehler:-?} Fehler"
    grep '^F ' "$TMP/qmllint" | cut -c3- | details
  fi
  if (( AUSFUEHRLICH )); then
    grep '^D ' "$TMP/qmllint" | cut -c3- | details
  elif [[ "${n_warn:-0}" != 0 ]]; then
    grep '^W ' "$TMP/qmllint" | cut -c3- | details
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
