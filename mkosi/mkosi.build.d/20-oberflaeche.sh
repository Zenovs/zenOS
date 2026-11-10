#!/usr/bin/env bash
# Oberfläche und Schriften von zenOS ins Image (läuft in der Bauumgebung, nicht im Image).
#
#   shell/            → /usr/share/zenos/shell (Quickshell: Sitzung shell.qml, Login greeter.qml)
#   assets/fonts/     → /usr/share/fonts/truetype/zenos (Geist, Geist Mono, Instrument Serif; SIL OFL 1.1)
#
# Kopiert werden nur die Dateien, die Quickshell lädt (QML, JavaScript, JSON, qmldir), keine Doku.
set -euo pipefail

ziel="$DESTDIR/usr/share/zenos/shell"
install -d -m 0755 "$ziel"
(cd "$SRCDIR/shell" && find . -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' -o -name '*.json' -o -name qmldir \) \
	-not -path './.*' -print0) |
	while IFS= read -r -d '' datei; do
		install -D -m 0644 "$SRCDIR/shell/$datei" "$ziel/${datei#./}"
	done
[[ -f "$ziel/shell.qml" && -f "$ziel/greeter.qml" && -f "$ziel/theme/tokens.json" ]] || {
	echo "20-oberflaeche: shell.qml, greeter.qml oder theme/tokens.json fehlt" >&2
	exit 1
}

schriften="$DESTDIR/usr/share/fonts/truetype/zenos"
install -d -m 0755 "$schriften"
install -m 0644 "$SRCDIR"/assets/fonts/*.ttf "$schriften/"
install -D -m 0644 "$SRCDIR/assets/fonts/OFL-Geist.txt" "$DESTDIR/usr/share/licenses/zenos-schriften/OFL-Geist.txt"
install -D -m 0644 "$SRCDIR/assets/fonts/OFL-InstrumentSerif.txt" \
	"$DESTDIR/usr/share/licenses/zenos-schriften/OFL-InstrumentSerif.txt"
echo "20-oberflaeche: $(find "$ziel" -type f | wc -l) Dateien der Oberfläche, $(find "$schriften" -name '*.ttf' | wc -l) Schriften"
