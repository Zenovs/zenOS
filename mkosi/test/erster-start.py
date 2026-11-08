#!/usr/bin/env python3
"""Angriffs- und Starttest für zenOS 1.0 in QEMU (Profil qemu).

Startet das Image in einer virtuellen Maschine, bedient den ersten Start über die serielle Konsole wie ein Mensch
(Tastatur, Passwort für die Daten, Wiederherstellungsschlüssel, Konto) und prüft danach am laufenden System, was die
Leitplanken versprechen. Dann ein zweiter Start: Die Einrichtung darf nicht wiederkommen, das Passwort muss gelten.

Läuft in der Bauumgebung (mkosi/test/starten.sh). Die Passwörter hier sind nur für diese Wegwerf-Maschine.
"""

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pexpect

DATEN_PASSWORT = "pruefung-nur-fuer-qemu-daten"
KONTO = "pruefer"
KONTO_PASSWORT = "pruefung-nur-fuer-qemu-konto"
FIRMWARE = "/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd"
VARIABLEN = "/usr/share/AAVMF/AAVMF_VARS.fd"
WIEDERHERSTELLUNG = re.compile(r"[cbdefghijklnrtuv]{8}(?:-[cbdefghijklnrtuv]{8}){7}")
ANFANG, ENDE = "ZENOS-PRUEFUNG-ANFANG", "ZENOS-PRUEFUNG-ENDE"

befunde: list[str] = []


def pruefe(bedingung: bool, text: str) -> None:
    print(("  ok    " if bedingung else "  FEHLER ") + text, flush=True)
    if not bedingung:
        befunde.append(text)


def starte(arbeit: Path) -> pexpect.spawn:
    befehl = [
        "qemu-system-aarch64", "-M", "virt", "-cpu", "max", "-smp", "4", "-m", "3072", "-nographic",
        "-drive", f"if=pflash,format=raw,readonly=on,file={FIRMWARE}",
        "-drive", f"if=pflash,format=raw,file={arbeit / 'variablen.fd'}",
        "-drive", f"file={arbeit / 'platte.qcow2'},if=virtio,format=qcow2",
        "-device", "virtio-rng-pci",
        "-netdev", "user,id=netz", "-device", "virtio-net-pci,netdev=netz,romfile=",
        "-serial", "mon:stdio",
    ]
    return pexpect.spawn(befehl[0], befehl[1:], encoding="utf-8", codec_errors="replace", timeout=900,
                         logfile=sys.stdout, dimensions=(50, 200))


def anmelden(vm: pexpect.spawn) -> None:
    vm.expect(r"login: ")
    vm.sendline(KONTO)
    vm.expect(r"[Pp]assword: ")
    vm.sendline(KONTO_PASSWORT)
    vm.expect(r"\$ ")


def befehl(vm: pexpect.spawn, zeilen: str) -> str:
    vm.sendline(f"echo {ANFANG}; {zeilen}; echo {ENDE}")
    vm.expect(f"\r\n{ANFANG}\r\n")
    vm.expect(f"\r\n{ENDE}\r\n")
    return vm.before.replace("\r", "")


def pruefe_system(vm: pexpect.spawn) -> None:
    print("\n--- Prüfung am laufenden System", flush=True)
    wurzel = befehl(vm, "findmnt -no SOURCE,OPTIONS /")
    pruefe("/dev/mapper/root" in wurzel and re.search(r"\bro\b", wurzel) is not None,
           f"/ ist das geprüfte System und schreibgeschützt ({wurzel.strip()})")
    pruefe("roothash=" in befehl(vm, "cat /proc/cmdline"), "Wurzel-Hash steht in der Befehlszeile")
    var = befehl(vm, "findmnt -no SOURCE,OPTIONS /var")
    pruefe("/dev/mapper/daten" in var and all(o in var for o in ("noexec", "nosuid", "nodev")),
           f"/var liegt verschlüsselt und ohne Ausführrecht ({var.strip()})")
    home = befehl(vm, "findmnt -no OPTIONS /home")
    pruefe("noexec" in home, f"/home ohne Ausführrecht ({home.strip()})")
    for pfad in ("/etc/zenos-test", "/usr/zenos-test"):
        pruefe("Read-only file system" in befehl(vm, f"touch {pfad} 2>&1"), f"{pfad} lässt sich nicht anlegen")

    lauscht = [z for z in befehl(vm, "ss -Hltnu").splitlines() if z.strip()]
    fremd = [z for z in lauscht if not re.search(r"\s(127\.0\.0\.5[34]|\[::1\]|127\.0\.0\.1):\d+\s", z)]
    pruefe(not fremd, "kein Dienst nimmt Verbindungen von aussen an" + (f": {fremd}" if fremd else ""))

    werte = befehl(vm, "sysctl -n kernel.io_uring_disabled kernel.kptr_restrict kernel.unprivileged_bpf_disabled "
                       "kernel.yama.ptrace_scope kernel.kexec_load_disabled 2>&1").split()
    pruefe(werte[:5] == ["2", "2", "1", "2", "1"], f"Kernel-Härtung wirkt (io_uring, kptr, bpf, ptrace, kexec: {werte})")

    erlaubt = {"/usr/lib/polkit-1/polkit-agent-helper-1", "/usr/sbin/unix_chkpwd"}
    erhoeht = set(befehl(vm, "find / -xdev -type f -perm /6000 2>/dev/null").split())
    pruefe(erhoeht <= erlaubt, f"setuid/setgid nur auf der Liste ({sorted(erhoeht)})")

    gefunden = befehl(vm, "for p in sudo su ssh sshd apt dpkg gcc make Xwayland pkexec; do "
                          "[ -x \"$(command -v $p)\" ] && [ -u \"$(command -v $p)\" -o $p != su ] && echo $p; done").split()
    pruefe(not gefunden, f"kein Paketmanager, kein SSH, kein sudo, kein Compiler ({gefunden})")

    for dienst in ("nftables", "chrony", "NetworkManager", "systemd-resolved", "greetd"):
        zustand = befehl(vm, f"systemctl is-active {dienst}.service").strip()
        pruefe(zustand == "active", f"{dienst} läuft ({zustand})")
    laufend = set(befehl(vm, "systemctl --no-legend --plain list-units --type=service --state=running "
                             "| awk '{print $1}'").split())
    print(f"  laufende Dienste: {' '.join(sorted(laufend))}", flush=True)


def main() -> int:
    image = Path(sys.argv[1])
    arbeit = Path(tempfile.mkdtemp(prefix="zenos-test-"))
    shutil.copy(VARIABLEN, arbeit / "variablen.fd")
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw", "-b", str(image.resolve()),
                    str(arbeit / "platte.qcow2"), "20G"], check=True)

    print("--- Erster Start", flush=True)
    vm = starte(arbeit)
    vm.expect("Nummer: ")
    vm.sendline("7")  # USA
    vm.expect("Testeingabe")
    vm.sendline("")
    for _ in range(2):  # neues Passwort und Wiederholung
        vm.expect(r"(?i)passphrase.*:")
        vm.sendline(DATEN_PASSWORT)
    vm.expect("Bereit\\? Enter")
    vm.sendline("")
    vm.expect(WIEDERHERSTELLUNG)
    pruefe(True, "Wiederherstellungsschlüssel wird angezeigt")
    vm.expect("Aufgeschrieben\\? Enter")
    vm.sendline("")
    vm.expect(r"(?i)passphrase for disk.*:")
    vm.sendline(DATEN_PASSWORT)
    vm.expect(r"(?i)user name")
    vm.sendline(KONTO)
    for _ in range(2):
        vm.expect(r"(?i)password")
        vm.sendline(KONTO_PASSWORT)
    anmelden(vm)
    pruefe_system(vm)
    vm.sendline("systemctl reboot")

    print("\n--- Zweiter Start", flush=True)
    index = vm.expect([r"(?i)passphrase for disk.*:", "Nummer: "])
    pruefe(index == 0, "die Einrichtung kommt nicht wieder; der Start fragt nur nach dem Passwort")
    vm.sendline(DATEN_PASSWORT)
    anmelden(vm)
    pruefe("Read-only file system" in befehl(vm, "touch /etc/zenos-test 2>&1"), "System nach dem Neustart unverändert")
    vm.sendline("systemctl poweroff")
    vm.expect(pexpect.EOF)

    print(f"\n--- {'Alle Prüfungen bestanden' if not befunde else f'{len(befunde)} Befunde'}", flush=True)
    for befund in befunde:
        print(f"  - {befund}")
    return 0 if not befunde else 1


if __name__ == "__main__":
    sys.exit(main())
