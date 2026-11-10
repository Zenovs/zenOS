#!/usr/bin/env bash
# Läuft in der Bauumgebung (gestartet von mkosi/bauen.sh): holt die Quellen, die zenOS selbst baut, prüft sie und
# startet danach mkosi mit allen übergebenen Argumenten.
#
# Quickshell 0.3.1 gibt es in Debian 13 nicht (dort erst 0.2.1 in «forky»). Gebaut wird genau der Commit des Tags
# v0.3.1 wie in zenOS 0.1. Die Quelle liegt im Docker-Volume zenos-bau-pakete unter /var/cache/zenos/quellen und
# wird vor jedem Bau geprüft: Commit, keine Änderungen, keine fremden Dateien.
set -euo pipefail

quellen=/var/cache/zenos/quellen
version=0.3.1
commit=1a4716cde794a59928d9d9fc15f2afc7a95de360
ziel=$quellen/quickshell-$commit

fehler() { echo "bauen-innen: $*" >&2; exit 1; }

mkdir -p "$quellen" /var/cache/zenos/bau /var/cache/zenos/arbeit
if [[ ! -d "$ziel" ]]; then
	arbeit=$(mktemp -d "$quellen/.quickshell.XXXXXX")
	for url in https://git.outfoxxed.me/quickshell/quickshell https://github.com/quickshell-mirror/quickshell; do
		if git -c advice.detachedHead=false clone --quiet --depth 1 --single-branch --branch "v$version" -- "$url" \
			"$arbeit/quelle" 2>"$arbeit/klonen.log"; then
			echo "bauen-innen: Quickshell v$version von $url"
			break
		fi
		echo "bauen-innen: nicht erreichbar: $url" >&2
		rm -rf "$arbeit/quelle"
	done
	[[ -d "$arbeit/quelle" ]] || fehler "Quickshell-Quelle nicht erreichbar ($(tail -n 1 "$arbeit/klonen.log"))"
	mv "$arbeit/quelle" "$ziel"
	rm -rf "$arbeit"
fi

ist=$(git -C "$ziel" rev-parse --verify 'HEAD^{commit}')
[[ "$ist" == "$commit" ]] || fehler "Quickshell v$version zeigt auf $ist statt auf $commit – Quelle nicht vertrauenswürdig"
[[ -z "$(git -C "$ziel" status --porcelain --ignored)" ]] || fehler "Quickshell-Quelle verändert: $ziel"

exec mkosi "$@"
