#!/usr/bin/env bash
# Erster Start auf einer grossen NVMe-SSD wie im Argon (QEMU, 500 GB, NVMe statt virtio): Die Einrichtung muss
# erscheinen (Frage nach der Tastaturbelegung), ohne dass systemd auf Partitionen wartet und aufgibt.
#
# Anlass (13.11.2026, erster Start am Argon): systemd-repart sperrte die Platte, während udev die Partitionen noch
# erfasste; udev verwarf die Ereignisse, /dev/disk/by-partlabel/… entstand nie, der Start endete im Notfallmodus. Mit
# der kleinen virtio-Platte des Haupttests fällt das nicht auf. Der Fehler hing vom Zufall ab, deshalb mehrere Starts.
#
#   mkosi/test/grosse-platte.sh [ANZAHL]    (Vorgabe 3; vorher: mkosi/bauen.sh qemu)
set -uo pipefail

if [[ "${ZENOS_IM_CONTAINER:-}" != 1 ]]; then
	hier=$(cd "$(dirname "$0")/.." && pwd)
	image="$hier/ausgabe/qemu/zenos_$(cat "$hier/mkosi.version").raw"
	[[ -f "$image" ]] || { echo "Kein Image unter $image. Zuerst: mkosi/bauen.sh qemu" >&2; exit 2; }
	exec docker --context "${ZENOS_DOCKER_KONTEXT:-colima-zenos}" run --rm -v "$hier/ausgabe/qemu:/qemu:ro" \
		-v "$hier/test:/test:ro" -e ZENOS_IM_CONTAINER=1 -e ZENOS_IMAGE="$(basename "$image")" zenos-bau:1 \
		bash /test/grosse-platte.sh "${1:-3}"
fi

anzahl=${1:-3}
fehler=0
for ((lauf = 1; lauf <= anzahl; lauf++)); do
	w=$(mktemp -d)
	cp /usr/share/AAVMF/AAVMF_VARS.fd "$w/vars.fd" 2>/dev/null || cp /usr/share/AAVMF/AAVMF_VARS.no-secboot.fd "$w/vars.fd"
	qemu-img create -q -f qcow2 -F raw -b "/qemu/$ZENOS_IMAGE" "$w/platte.qcow2" 500G
	python3 - "$w" <<'PY'
import sys, time, pexpect
w = sys.argv[1]
vm = pexpect.spawn("qemu-system-aarch64", [
    "-M", "virt", "-cpu", "max", "-smp", "4", "-m", "3072", "-nographic", "-nodefaults",
    "-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd",
    "-drive", f"if=pflash,format=raw,file={w}/vars.fd",
    "-drive", f"if=none,id=d,file={w}/platte.qcow2,format=qcow2", "-device", "nvme,serial=zenos,drive=d",
    "-device", "virtio-rng-pci", "-serial", "mon:stdio"], encoding="utf-8", codec_errors="replace", timeout=900)
# Frist mit der monotonen Uhr in kurzen Schritten: pexpect misst mit der Uhrzeit, und die springt in der Bau-VM (etwa
# wenn der Mac schläft); dann käme die Zeitüberschreitung zu früh.
beginn = time.monotonic()
ausgabe = ""
while True:
    i = vm.expect(["Nummer: ", "Timed out waiting for device", "emergency mode", pexpect.TIMEOUT, pexpect.EOF], timeout=10)
    # vor dem ersten Treffer enthält before alles seit dem Start
    ausgabe = vm.before if isinstance(vm.before, str) else ausgabe
    if i != 3 or time.monotonic() - beginn > 900:
        break
dauer = int(time.monotonic() - beginn)
vm.terminate(force=True)
if i == 0:
    # Zeno muss sehen, was passiert (daten-anlegen schreibt auf /dev/console), und die Notfall-Partition muss geleert sein
    fehlt = [t for t in ("Der Speicher wird vorbereitet", "Speicher vorbereitet.") if t not in ausgabe]
    warnung = "Notfall-Partition ist nicht erschienen" in ausgabe
    if not fehlt and not warnung:
        print(f"  ok      Einrichtung erscheint nach {dauer} s, Meldungen zum Speicher auf der Konsole")
        sys.exit(0)
    print(f"  FEHLER  Einrichtung nach {dauer} s, aber Meldung fehlt: {fehlt}, Warnung zur Notfall-Partition: {warnung}")
    sys.exit(1)
print(f"  FEHLER  nach {dauer} s: {['', 'Zeitüberschreitung beim Warten auf ein Gerät', 'Notfallmodus', 'nichts nach 15 Minuten', 'QEMU beendet'][i]}")
import re
for zeile in re.sub(r"\x1b\[[0-9;:?]*[A-Za-z]", "", ausgabe).replace("\r", "").splitlines()[-15:]:
    print(f"          {zeile[:160]}")
sys.exit(1)
PY
	(($? == 0)) || fehler=$((fehler + 1))
	rm -rf "$w"
done
echo
if ((fehler == 0)); then echo "--- Alle Prüfungen bestanden"; else echo "--- $fehler Befunde"; fi
exit $((fehler > 0))
