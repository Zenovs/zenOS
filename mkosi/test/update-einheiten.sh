#!/usr/bin/env bash
# Einheitentest für /usr/lib/zenos/update: Probestart vorbereiten, festschreiben (autoboot.txt), gescheiterte
# Probestarts. Läuft in der Bauumgebung ohne Gerät: ZENOS_UPDATE_TESTWURZEL legt alle Orte des Programms (Gerätebaum
# des Bootloaders, Partitionen, autoboot.txt, Marker) in einen Testordner.
#
#   mkosi/test/update-einheiten.sh          (auf dem Mac: startet sich selbst in der Bauumgebung)
set -uo pipefail

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	hier=$(cd "$(dirname "$0")/.." && pwd)
	exec docker --context "${ZENOS_DOCKER_KONTEXT:-colima-zenos}" run --rm -v "$hier:/zenos/mkosi:ro" \
		-e ZENOS_IM_CONTAINER=1 zenos-bau:1 bash /zenos/mkosi/test/update-einheiten.sh
fi

programm=/zenos/mkosi/mkosi.extra/usr/lib/zenos/update
fehler=0

pruefe() { # BEDINGUNG-EXIT TEXT
	if [[ "$1" == 0 ]]; then
		printf '  ok      %s\n' "$2"
	else
		printf '  FEHLER  %s\n' "$2"
		fehler=$((fehler + 1))
	fi
}

zahl() { printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' 0 0 0 "$1")"; }

autoboot() { printf '[all]\ntryboot_a_b=1\nboot_partition=%s\n[tryboot]\nboot_partition=%s\n' "$1" "$2"; }

# Gerät nachbilden: läuft VERSION von Startpartition PARTITION, tryboot TRYBOOT, autoboot.txt mit FEST/PROBE
geraet() { # VERSION PARTITION TRYBOOT FEST PROBE
	w=$(mktemp -d)
	mkdir -p "$w/usr/lib" "$w/proc/device-tree/chosen/bootloader" "$w/dev/disk/by-partlabel/zenos-start.inhalt" \
		"$w/run/systemd"
	printf 'ID=debian\nIMAGE_VERSION=%s\n' "$1" >"$w/usr/lib/os-release"
	zahl "$3" >"$w/proc/device-tree/chosen/bootloader/tryboot"
	zahl "$2" >"$w/proc/device-tree/chosen/bootloader/partition"
	autoboot "$4" "$5" >"$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt"
	printf '%s' "$w"
}

partition() { # WURZEL BEZEICHNUNG NUMMER
	printf '%s\n' "$3" >"$1/dev/disk/by-partlabel/$2.nummer"
}

laeuft() { # WURZEL FUNKTION [LOGIN-EXIT]
	(
		export ZENOS_UPDATE_TESTWURZEL=$1 ZENOS_UPDATE_TEST_LOGIN=${3:-0}
		# shellcheck source=/dev/null
		source "$programm"
		sleep() { :; }
		"$2"
	) >/dev/null 2>&1
}

echo "--- Probestart vorbereiten"
w=$(geraet 0.9.1 2 0 2 3)
partition "$w" zenos_0.9.1 5
partition "$w" zenos_0.9.2 7
partition "$w" zenos-start_0.9.1 2
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
(
	export ZENOS_UPDATE_TESTWURZEL=$w
	source "$programm"
	mkdir -p "$laufzeit"
	probe_vorbereiten 0.9.2
) >/dev/null 2>&1
pruefe $? "Probestart für 0.9.2 vorbereitet"
[[ "$(cat "$w/run/systemd/reboot-param" 2>/dev/null)" == "0 tryboot" ]]
pruefe $? "Neustart mit «0 tryboot»"
[[ "$(cat "$w/var/lib/zenos/update/probe" 2>/dev/null)" == "0.9.2 bereit" ]]
pruefe $? "Marker «0.9.2 bereit»"
[[ -e "$w/run/zenos/update/neustart" ]]
pruefe $? "Marker für die Leiste (neustart)"
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 2 3)" ]]
pruefe $? "autoboot.txt bleibt beim Vorbereiten unverändert"

echo "--- Vorbereiten verweigert, wenn autoboot.txt nicht zum laufenden Start passt"
w=$(geraet 0.9.1 2 0 3 2)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
(
	export ZENOS_UPDATE_TESTWURZEL=$w
	source "$programm"
	mkdir -p "$laufzeit"
	probe_vorbereiten 0.9.2
) >/dev/null 2>&1
[[ $? != 0 && ! -e "$w/run/systemd/reboot-param" ]]
pruefe $? "kein Probestart bei unpassender autoboot.txt"

echo "--- Probestart gelingt: festschreiben"
w=$(geraet 0.9.2 3 1 2 3)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
groesse_vorher=$(wc -c <"$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")
laeuft "$w" pruefen
pruefe $? "pruefen meldet Erfolg"
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 3 2)" ]]
pruefe $? "autoboot.txt: 3 fest, 2 zur Probe"
[[ "$(wc -c <"$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$groesse_vorher" ]]
pruefe $? "autoboot.txt behält die Länge (an Ort und Stelle)"
[[ ! -e "$w/var/lib/zenos/update/probe" ]]
pruefe $? "Marker entfernt"
grep -q "ist jetzt fest" "$w/run/zenos/update/hinweis"
pruefe $? "Hinweis «ist jetzt fest»"

echo "--- Probestart, aber der Login läuft nicht: nicht festschreiben"
w=$(geraet 0.9.2 3 1 2 3)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen 1
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 2 3)" ]]
pruefe $? "autoboot.txt unverändert"
[[ "$(cat "$w/var/lib/zenos/update/probe")" == "0.9.2 probiert" ]]
pruefe $? "Marker «probiert»: der nächste normale Start hält den Fehlschlag fest"

echo "--- Probestart von der falschen Partition: nicht festschreiben"
w=$(geraet 0.9.2 2 1 2 3)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 2 3)" ]]
pruefe $? "autoboot.txt unverändert"

echo "--- Normaler Start nach «bereit» (ausgeschaltet statt neu gestartet): noch ein Versuch"
w=$(geraet 0.9.1 2 0 2 3)
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 bereit\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen
[[ "$(cat "$w/var/lib/zenos/update/probe")" == "0.9.2 bereit-2" && "$(cat "$w/run/systemd/reboot-param")" == "0 tryboot" ]]
pruefe $? "Marker «bereit-2», Neustart wieder mit tryboot"

echo "--- Normaler Start nach «bereit-2» oder «probiert»: gescheitert"
for zustand in bereit-2 probiert; do
	w=$(geraet 0.9.1 2 0 2 3)
	mkdir -p "$w/var/lib/zenos/update"
	printf '0.9.2 %s\n' "$zustand" >"$w/var/lib/zenos/update/probe"
	laeuft "$w" pruefen
	[[ "$(cat "$w/var/lib/zenos/update/fehlgeschlagen")" == 0.9.2 && ! -e "$w/var/lib/zenos/update/probe" ]]
	pruefe $? "nach «$zustand»: 0.9.2 gilt als gescheitert und kommt nicht nochmals"
done

echo "--- Ein zweites Festschreiben ändert nichts"
w=$(geraet 0.9.2 3 1 3 2)
partition "$w" zenos-start_0.9.2 3
mkdir -p "$w/var/lib/zenos/update"
printf '0.9.2 probiert\n' >"$w/var/lib/zenos/update/probe"
laeuft "$w" pruefen
[[ "$(cat "$w/dev/disk/by-partlabel/zenos-start.inhalt/autoboot.txt")" == "$(autoboot 3 2)" ]]
pruefe $? "autoboot.txt bleibt 3 fest, 2 zur Probe"

# --- Laden und prüfen: Signatur (SSH), Liste, Prüfsummen --------------------------------------------------------
# Wegwerf-Schlüssel nur für diesen Test. Der Server ist ein Ordner, die Quelle eine file://-Adresse.
schluessel=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -C test -f "$schluessel/a"
ssh-keygen -q -t ed25519 -N '' -C fremd -f "$schluessel/fremd"
u1=11111111-2222-3333-4444-555555555555
u2=66666666-7777-8888-9999-000000000000

server_stand() { # VERSION → Ordner mit den Dateien eines Stands und SHA256SUMS
	local s
	s=$(mktemp -d)
	printf 'system %s\n' "$1" | xz >"$s/zenos_${1}_$u1.root.raw.xz"
	printf 'verity %s\n' "$1" | xz >"$s/zenos_${1}_$u2.root-verity.raw.xz"
	printf 'start %s\n' "$1" | xz >"$s/zenos_$1.start.raw.xz"
	printf 'ganz %s\n' "$1" | xz >"$s/zenos_$1.raw.xz"
	(cd "$s" && sha256sum -- *.xz >SHA256SUMS)
	printf '%s' "$s"
}

signieren() { # ORDNER [SCHLUESSEL] [NAMESPACE]
	rm -f "$1/SHA256SUMS.sig"
	ssh-keygen -q -Y sign -f "${2:-$schluessel/a}" -n "${3:-argon-update}" "$1/SHA256SUMS" 2>/dev/null
}

geraet_update() { # SERVER → Wurzel eines Geräts mit 0.9.1, das dem Schlüssel a traut
	local w
	w=$(geraet 0.9.1 2 0 2 3)
	mkdir -p "$w/usr/lib/zenos" "$w/var/lib/zenos/update" "$w/run/zenos/update"
	printf 'file://%s/\n' "$1" >"$w/usr/lib/zenos/update-quelle"
	printf 'argon-update namespaces="argon-update" %s\n' "$(cut -d' ' -f1,2 "$schluessel/a.pub")" \
		>"$w/usr/lib/zenos/update-signierer"
	printf '%s' "$w"
}

laden_pruefen() { # WURZEL → Version auf stdout, Exit 0 nur wenn alles stimmt
	(
		export ZENOS_UPDATE_TESTWURZEL=$1
		# shellcheck source=/dev/null
		source "$programm"
		install -d -m 0700 "$laden"
		holen SHA256SUMS "$laden/SHA256SUMS" 65536 && holen SHA256SUMS.sig "$laden/SHA256SUMS.sig" 65536 &&
			signatur_pruefen "$laden" && neu=$(liste_version "$laden/SHA256SUMS") && dateien_laden "$laden" &&
			printf '%s' "$neu"
	) 2>/dev/null
}

echo "--- Laden: gültig signierter Stand"
s=$(server_stand 0.9.2)
signieren "$s"
w=$(geraet_update "$s")
v=$(laden_pruefen "$w")
pruefe $? "Signatur, Liste und Prüfsummen in Ordnung"
[[ "$v" == 0.9.2 ]]
pruefe $? "Version aus der signierten Liste: 0.9.2"
l=$w/var/lib/zenos/update/laden
[[ -f "$l/zenos_0.9.2_$u1.root.raw.xz" && -f "$l/zenos_0.9.2_$u2.root-verity.raw.xz" && -f "$l/zenos_0.9.2.start.raw.xz" ]]
pruefe $? "System, Prüfsummen und Startpartition geladen"
[[ ! -e "$l/zenos_0.9.2.raw.xz" ]]
pruefe $? "das ganze Image (für eine leere SSD) wird nicht geladen"
grep -q "Signatur gültig" "$w/run/zenos/update/protokoll"
pruefe $? "Protokoll: «Signatur gültig»"

echo "--- Laden: verweigert"
s=$(server_stand 0.9.2)
signieren "$s"
sed -i "1s/^[0-9a-f]*/$(printf '%064d' 0)/" "$s/SHA256SUMS"
laden_pruefen "$(geraet_update "$s")" >/dev/null
pruefe $((!$?)) "Liste nach dem Signieren verändert"

s=$(server_stand 0.9.2)
signieren "$s" "$schluessel/fremd"
laden_pruefen "$(geraet_update "$s")" >/dev/null
pruefe $((!$?)) "signiert mit einem fremden Schlüssel"

s=$(server_stand 0.9.2)
signieren "$s" "$schluessel/a" git
laden_pruefen "$(geraet_update "$s")" >/dev/null
pruefe $((!$?)) "richtiger Schlüssel, aber für etwas anderes signiert (Namespace git)"

s=$(server_stand 0.9.2)
laden_pruefen "$(geraet_update "$s")" >/dev/null
pruefe $((!$?)) "ohne Signatur"

s=$(server_stand 0.9.2)
signieren "$s"
w=$(geraet_update "$s")
: >"$w/usr/lib/zenos/update-signierer"
laden_pruefen "$w" >/dev/null
pruefe $((!$?)) "Gerät ohne erlaubten Schlüssel (Entwicklungsbau) nimmt nichts an"

s=$(server_stand 0.9.2)
signieren "$s"
printf 'fremd\n' | xz >"$s/zenos_0.9.2_$u1.root.raw.xz"
laden_pruefen "$(geraet_update "$s")" >/dev/null
pruefe $((!$?)) "System nach dem Signieren ausgetauscht (Prüfsumme)"

s=$(server_stand 0.9.2)
signieren "$s"
w=$(geraet_update "$s")
printf 'ftp://%s/\n' "$s" >"$w/usr/lib/zenos/update-quelle"
laden_pruefen "$w" >/dev/null
pruefe $((!$?)) "Quelle mit fremdem Protokoll"

s=$(server_stand 0.9.2)
head -c 70000 /dev/zero | tr '\0' a >>"$s/SHA256SUMS"
signieren "$s"
w=$(geraet_update "$s")
! laden_pruefen "$w" >/dev/null && grep -qiE "maximum (allowed )?file size" "$w/run/zenos/update/protokoll"
pruefe $? "Liste grösser als 64 KiB wird nicht ganz geladen"

echo "--- Liste: nur die Dateien eines Stands"
liste() { # ZEILEN… → Exit von liste_version
	local d
	d=$(mktemp)
	printf '%s\n' "$@" >"$d"
	(
		export ZENOS_UPDATE_TESTWURZEL=/nicht-da
		# shellcheck source=/dev/null
		source "$programm"
		liste_version "$d"
	)
}
h=$(printf '%064d' 0)
r="$h  zenos_0.9.2_$u1.root.raw.xz"
p="$h  zenos_0.9.2_$u2.root-verity.raw.xz"
[[ "$(liste "$r" "$p" "$h  zenos_0.9.2.start.raw.xz" "$h  zenos_0.9.2.raw.xz")" == 0.9.2 ]]
pruefe $? "Argon: System, Prüfsummen, Start, ganzes Image"
[[ "$(liste "$r" "$p")" == 0.9.2 ]]
pruefe $? "QEMU: System und Prüfsummen"
liste "$r" >/dev/null
pruefe $((!$?)) "Prüfsummen fehlen"
liste "$r" "$p" "$h  zenos_0.9.3_$u1.root.raw.xz" >/dev/null
pruefe $((!$?)) "zwei Versionen"
liste "$r" "$r" "$p" >/dev/null
pruefe $((!$?)) "System doppelt"
liste "$r" "$p" "$h  ../zenos_0.9.2.start.raw.xz" >/dev/null
pruefe $((!$?)) "Pfad statt Name"
liste "$r" "$p" "$h  zenos_0.9.2_$u1.root.raw.xz.sh" >/dev/null
pruefe $((!$?)) "fremde Endung"
liste "$(printf 'A%063d' 0)  zenos_0.9.2_$u1.root.raw.xz" "$p" >/dev/null
pruefe $((!$?)) "Grossbuchstaben im Hash"
liste "$h *zenos_0.9.2_$u1.root.raw.xz" "$p" >/dev/null
pruefe $((!$?)) "Binärmodus («*»)"
liste "$r" "$p" "" >/dev/null
pruefe $((!$?)) "leere Zeile"

echo "--- Flags der Signatur: Berührung und PIN"
# Signatur im Format von OpenSSH nachbauen (PROTOCOL.sshsig); ssh-keygen prüft hier nichts, nur die Flags zählen
sk_signatur() { # FLAGS-HEX [TYP] [kurz|lang]
	python3 - "$@" <<'PY'
import base64, struct, sys
flags = int(sys.argv[1], 16)
typ = (sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else "sk-ssh-ed25519@openssh.com").encode()
art = sys.argv[3] if len(sys.argv) > 3 else ""
s = lambda b: struct.pack(">I", len(b)) + b
sig = s(typ) + s(bytes(64))
if typ.startswith(b"sk-"):
    sig += bytes([flags]) + struct.pack(">I", 7)
blob = b"SSHSIG" + struct.pack(">I", 1) + s(b"schluessel") + s(b"argon-update") + s(b"") + s(b"sha512") + s(sig)
if art == "kurz":
    blob = blob[:-1]
if art == "lang":
    blob += b"\0"
b = base64.b64encode(blob).decode()
print("-----BEGIN SSH SIGNATURE-----")
for i in range(0, len(b), 70):
    print(b[i:i + 70])
print("-----END SSH SIGNATURE-----")
PY
}
flags_ok() { # SIGNATURDATEI
	(
		export ZENOS_UPDATE_TESTWURZEL=$fw
		# shellcheck source=/dev/null
		source "$programm"
		signatur_flags "$1"
	) >/dev/null 2>&1
}
fw=$(mktemp -d)
mkdir -p "$fw/run/zenos/update"
d=$(mktemp -d)
sk_signatur 05 >"$d/beides"
flags_ok "$d/beides"
pruefe $? "FIDO-Signatur mit Berührung und PIN"
sk_signatur 01 >"$d/ohne-pin"
flags_ok "$d/ohne-pin"
pruefe $((!$?)) "FIDO-Signatur ohne PIN"
sk_signatur 04 >"$d/ohne-beruehrung"
flags_ok "$d/ohne-beruehrung"
pruefe $((!$?)) "FIDO-Signatur ohne Berührung"
sk_signatur 00 >"$d/ohne"
flags_ok "$d/ohne"
pruefe $((!$?)) "FIDO-Signatur ohne beides"
sk_signatur 05 "" kurz >"$d/kurz"
flags_ok "$d/kurz"
pruefe $((!$?)) "abgeschnittene Signatur"
sk_signatur 05 "" lang >"$d/lang"
flags_ok "$d/lang"
pruefe $((!$?)) "Signatur mit angehängten Bytes"
sk_signatur 05 sk-ecdsa-sha2-nistp256@openssh.com >"$d/ecdsa"
flags_ok "$d/ecdsa"
pruefe $? "auch andere FIDO-Typen: Flags zählen"
printf 'kein Base64\n' >"$d/kaputt"
flags_ok "$d/kaputt"
pruefe $((!$?)) "keine Signatur"
printf 'Probe\n' >"$d/probe"
ssh-keygen -q -Y sign -f "$schluessel/a" -n argon-update "$d/probe" 2>/dev/null
flags_ok "$d/probe.sig"
pruefe $? "Signatur eines Schlüssels ohne FIDO (nur im Test-Image erlaubt) hat keine Flags"

echo
if ((fehler == 0)); then echo "--- Alle Prüfungen bestanden"; else echo "--- $fehler Befunde"; fi
exit $((fehler > 0))
