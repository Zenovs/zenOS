#!/usr/bin/env bash
# Prüft Zenos Signatur eines Updates so, wie der Argon sie prüft: mit dem Code von /usr/lib/zenos/update (eingelesen,
# nicht nachgebaut) und den öffentlichen Schlüsseln aus mkosi/schluessel/argon-allowed-signers. Prüft nur, signiert nie.
#
#   mkosi/signatur-pruefen.sh [version]   Stand unter mkosi/ausgabe/veroeffentlichung/argon/<version>/ (Vorgabe:
#                                         mkosi/mkosi.version): Signatur mit Berührung und PIN, Liste, alle Prüfsummen
#   mkosi/signatur-pruefen.sh probe       Probe unter mkosi/ausgabe/signatur-probe/ (docs/signieren.md, Test der
#                                         Schlüssel vor dem ersten Bau): nur die Signatur mit Berührung und PIN
set -euo pipefail

hier=$(cd "$(dirname "$0")" && pwd)

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	ziel=${1:-$(cat "$hier/mkosi.version")}
	if [[ "$ziel" == probe ]]; then
		ordner=$hier/ausgabe/signatur-probe
	else
		[[ "$ziel" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Aufruf: mkosi/signatur-pruefen.sh [version|probe]" >&2; exit 2; }
		ordner=$hier/ausgabe/veroeffentlichung/argon/$ziel
	fi
	[[ -f "$ordner/SHA256SUMS" && -f "$ordner/SHA256SUMS.sig" ]] || {
		echo "Unter ${ordner#"$hier/"} fehlen SHA256SUMS oder SHA256SUMS.sig." >&2
		exit 1
	}
	[[ -f "$hier/schluessel/argon-allowed-signers" ]] || {
		echo "mkosi/schluessel/argon-allowed-signers fehlt (Zenos öffentliche Schlüssel, docs/signieren.md)." >&2
		exit 1
	}
	exec docker --context "${ZENOS_DOCKER_KONTEXT:-colima-zenos}" run --rm \
		-v "$hier:/zenos/mkosi:ro" -v "$ordner:/stand:ro" \
		-e ZENOS_IM_CONTAINER=1 -e ZENOS_ART="$([[ "$ziel" == probe ]] && echo probe || echo stand)" \
		zenos-bau:1 bash /zenos/mkosi/signatur-pruefen.sh
fi

# --- in der Bauumgebung ---------------------------------------------------------------------------------------
# Wie auf dem Argon: von openssh-client nur ssh-keygen, ohne die Hilfsprogramme (mkosi.conf, RemoveFiles). Der
# Container ist ein Wegwerf-Container (--rm).
rm -rf /usr/lib/openssh
wurzel=$(mktemp -d)
mkdir -p "$wurzel/usr/lib/zenos" "$wurzel/run/zenos/update"
# Dieselbe Prüfung wie mkosi.finalize: nur FIDO2-Schlüssel für argon-update
muster='^argon-update namespaces="argon-update" sk-ssh-ed25519@openssh\.com AAAA[A-Za-z0-9+/]+=*( [^[:space:]].*)?$'
grep -Ev '^[[:space:]]*(#|$)' /zenos/mkosi/schluessel/argon-allowed-signers >"$wurzel/usr/lib/zenos/update-signierer"
while IFS= read -r zeile; do
	[[ "$zeile" =~ $muster ]] || { echo "argon-allowed-signers: kein FIDO2-Schlüssel für argon-update: ${zeile:0:50}…" >&2; exit 1; }
done <"$wurzel/usr/lib/zenos/update-signierer"

export ZENOS_UPDATE_TESTWURZEL=$wurzel
# shellcheck source=/dev/null
source /zenos/mkosi/mkosi.extra/usr/lib/zenos/update
set +e

if ! signatur_pruefen /stand 2>/dev/null; then
	echo "UNGÜLTIG: $(tail -n 1 "$protokoll")"
	exit 1
fi
echo "$(tail -n 1 "$protokoll")"
echo "Berührung und PIN: ja"
[[ "${ZENOS_ART:-}" == probe ]] && { echo "Probe in Ordnung."; exit 0; }

if ! version=$(liste_version /stand/SHA256SUMS); then
	echo "UNGÜLTIG: SHA256SUMS passt nicht zum Muster eines Stands"
	exit 1
fi
cd /stand
if ! sha256sum --quiet --strict -c SHA256SUMS; then
	echo "UNGÜLTIG: eine Datei passt nicht zu SHA256SUMS"
	exit 1
fi
echo "Stand $version: Signatur, Liste und alle Prüfsummen in Ordnung. Bereit zum Veröffentlichen (nach Zenos Ja)."
