#!/usr/bin/env python3
"""Angriffs- und Starttest für zenOS 1.0 in QEMU (Profil qemu).

Startet das Image in einer virtuellen Maschine, bedient den ersten Start über die serielle Konsole wie ein Mensch
(Tastatur, Passwort für die Daten, Wiederherstellungsschlüssel, Konto) und prüft danach am laufenden System, was die
Leitplanken versprechen. Dann die Oberfläche auf dem virtuellen Bildschirm: Anmelden am Login (Tastatur über QEMU),
Leiste, Sperren und Entsperren mit PAM, Befehlsfeld, hell und dunkel, jeweils mit Bildschirmfoto. Dann das
Notfall-Passwort (BAUAUFTRAG.md, Bauauftrag 2): beim ersten Start gesetzt, mit zen notfall geändert, entfernt und
wieder gesetzt; ein falsches Passwort und der Wiederherstellungsschlüssel beim zweiten Start, das echte Passwort beim
dritten. Zuletzt, weil es die Maschine zerstört: Start mit dem Notfall-Passwort (Attrappe im Arbeitsspeicher, Platte von
aussen geprüft) und ein Start danach, bei dem kein Passwort mehr stimmt.

Läuft in der Bauumgebung (mkosi/test/starten.sh). Die Passwörter hier sind nur für diese Wegwerf-Maschine. Die
Bildschirmfotos landen in $ZENOS_TEST_BILDER (mkosi/ausgabe/test/).
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pexpect

DATEN_PASSWORT = "pruefung-nur-fuer-qemu-daten"
KONTO = "pruefer"
KONTO_PASSWORT = "pruefung-nur-fuer-qemu-konto"
NOTFALL_PASSWORT = "notfall-nur-fuer-qemu"
NOTFALL_PASSWORT_2 = "notfall-zwei-nur-fuer-qemu"
# Frage von /usr/lib/zenos/entsperren (Passwort-Agent von systemd auf der Konsole)
DATEN_FRAGE = r"Passwort f.r deine Daten:"
# Läuft die Oberfläche? Genau «active» («inactive» und «activating» enthalten das Wort auch)
AKTIV_SHELL = "systemctl --user is-active zenos-shell.service | grep -qx active && echo shell-laeuft || echo noch-nicht"
FIRMWARE = "/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd"
VARIABLEN = "/usr/share/AAVMF/AAVMF_VARS.fd"
WIEDERHERSTELLUNG = re.compile(r"[cbdefghijklnrtuv]{8}(?:-[cbdefghijklnrtuv]{8}){7}")
ANFANG, ENDE = "ZENOS-PRUEFUNG-ANFANG", "ZENOS-PRUEFUNG-ENDE"
BILDER = Path(os.environ.get("ZENOS_TEST_BILDER", "/tmp/zenos-test-bilder"))
# Ordner mit einem zweiten Stand (SHA256SUMS und Dateien von mkosi/veroeffentlichen.sh qemu): dann auch der Update-Test
UPDATE = Path(os.environ.get("ZENOS_TEST_UPDATE", "/nicht-vorhanden"))
QS = "/usr/share/zenos/shell/shell.qml"

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
        # Bildschirm, Tastatur und Maus für die Oberfläche (Bildschirmfotos über den Monitor, Tasten über sendkey)
        "-device", "virtio-gpu-pci,xres=1280,yres=800", "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
        "-netdev", "user,id=netz", "-device", "virtio-net-pci,netdev=netz,romfile=",
        "-serial", "mon:stdio",
    ]
    return pexpect.spawn(befehl[0], befehl[1:], encoding="utf-8", codec_errors="replace", timeout=900,
                         logfile=sys.stdout, dimensions=(50, 200))


def monitor(vm: pexpect.spawn, kommando: str) -> None:
    """Befehl an den QEMU-Monitor (Strg-A c wechselt zwischen Konsole und Monitor)."""
    vm.send("\x01c")
    vm.expect(r"\(qemu\) ")
    vm.sendline(kommando)
    if kommando != "quit":
        vm.send("\x01c")


# Zeichen → QEMU-Tastencode (US-Belegung, die der Test beim ersten Start wählt)
TASTEN = {"-": "minus", ".": "dot", " ": "spc", "_": "shift-minus"}


def tippen(vm: pexpect.spawn, text: str, enter: bool = True) -> None:
    """Text über die virtuelle Tastatur tippen (alles in einem Besuch im Monitor)."""
    vm.send("\x01c")
    vm.expect(r"\(qemu\) ")
    codes = []
    for zeichen in text:
        if zeichen.isalnum() and zeichen.isascii():
            codes.append(f"shift-{zeichen.lower()}" if zeichen.isupper() else zeichen)
        else:
            codes.append(TASTEN[zeichen])
    if enter:
        codes.append("ret")
    for code in codes:
        vm.sendline(f"sendkey {code}")
        vm.expect(r"\(qemu\) ")
        time.sleep(0.15)
    vm.send("\x01c")


def taste(vm: pexpect.spawn, code: str) -> None:
    """Eine Taste oder Tastenkombination, z. B. meta_l-spc."""
    vm.send("\x01c")
    vm.expect(r"\(qemu\) ")
    vm.sendline(f"sendkey {code}")
    vm.expect(r"\(qemu\) ")
    vm.send("\x01c")


def foto(vm: pexpect.spawn, name: str) -> None:
    """Bildschirmfoto des virtuellen Bildschirms nach $ZENOS_TEST_BILDER/<name>.png."""
    BILDER.mkdir(parents=True, exist_ok=True)
    vm.send("\x01c")
    vm.expect(r"\(qemu\) ")
    vm.sendline(f"screendump {BILDER / (name + '.png')} -f png")
    vm.expect(r"\(qemu\) ")
    vm.send("\x01c")
    print(f"  Bild  {name}.png", flush=True)


def warten_bis(vm: pexpect.spawn, zeilen: str, erwartet: str, sekunden: int) -> str:
    """Befehl wiederholen, bis die Ausgabe «erwartet» enthält (oder die Zeit um ist); gibt die letzte Ausgabe zurück."""
    ende = time.monotonic() + sekunden
    while True:
        ausgabe = befehl(vm, zeilen).strip()
        if erwartet in ausgabe or time.monotonic() > ende:
            return ausgabe
        time.sleep(5)


def anmelden(vm: pexpect.spawn, passwort: str = KONTO_PASSWORT, warten: bool = True) -> None:
    if warten:
        vm.expect(r"login: ")
    vm.sendline(KONTO)
    vm.expect(r"[Pp]assword: ")
    vm.sendline(passwort)
    vm.expect(r"\$ ")


def befehl(vm: pexpect.spawn, zeilen: str) -> str:
    vm.sendline(f"echo {ANFANG}; {zeilen}; echo {ENDE}")
    # Über die serielle Leitung und das pty enden Zeilen mit \r\r\n; vor der ersten Ausgabe schaltet bash mit
    # ESC[?2004l das Einfügen in Klammern ab und beginnt die Zeile mit \r.
    # Ist die Ausgabe leer, hat die Anfangsmarke das Zeilenende vor der Endmarke schon verbraucht (^).
    vm.expect(f"[\r\n]{ANFANG}\r*\n")
    vm.expect(f"(?:^|[\r\n]){ENDE}\r*\n")
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

    teile = befehl(vm, "lsblk -bnr -o PARTLABEL,SIZE /dev/vda")
    groessen = dict(z.split()[:2] for z in teile.splitlines() if len(z.split()) >= 2)
    version_a = befehl(vm, ". /usr/lib/os-release; echo $IMAGE_VERSION").strip()
    pruefe(groessen.get(f"zenos_{version_a}") == str(6 * 1024**3),
           f"System A ist beim ersten Start auf 6 GB gewachsen ({groessen.get('zenos_' + version_a)})")
    leer = [z for z in teile.splitlines() if z.split()[:1] == ["_empty"]]
    pruefe(len(leer) == 2 and all(z.split()[1] == str(6 * 1024**3) or z.split()[1] == str(128 * 1024**2) for z in leer),
           f"B-Hälfte (System 6 GB und Prüfsummen 128 MB) ist angelegt ({leer})")

    lauscht = [z for z in befehl(vm, "ss -Hltnu").splitlines() if z.strip()]
    # Erlaubt ist nur Lokales: der Resolver von systemd (127.0.0.53/54, auch als «%lo» angegeben) und ::1.
    fremd = [z for z in lauscht if not re.search(r"\s(127\.0\.0\.5[34]|\[::1\]|127\.0\.0\.1)(%lo)?:\d+\s", z)]
    pruefe(not fremd, "kein Dienst nimmt Verbindungen von aussen an" + (f": {fremd}" if fremd else ""))

    # sysctl liegt unter /usr/sbin, ausserhalb des Pfads eines Benutzers; die Werte stehen auch in /proc/sys.
    werte = befehl(vm, "cat /proc/sys/kernel/io_uring_disabled /proc/sys/kernel/kptr_restrict "
                       "/proc/sys/kernel/unprivileged_bpf_disabled /proc/sys/kernel/yama/ptrace_scope "
                       "/proc/sys/kernel/kexec_load_disabled 2>&1").split()
    pruefe(werte[:5] == ["2", "2", "1", "2", "1"], f"Kernel-Härtung wirkt (io_uring, kptr, bpf, ptrace, kexec: {werte})")

    erlaubt = {"/usr/lib/polkit-1/polkit-agent-helper-1", "/usr/sbin/unix_chkpwd"}
    erhoeht = set(befehl(vm, "find / -xdev -type f -perm /6000 2>/dev/null").split())
    pruefe(erhoeht <= erlaubt, f"setuid/setgid nur auf der Liste ({sorted(erhoeht)})")

    gefunden = befehl(vm, "for p in sudo su ssh sshd scp sftp ssh-agent ssh-add ssh-keyscan apt dpkg gcc make Xwayland "
                          "pkexec; do [ -x \"$(command -v $p)\" ] && [ -u \"$(command -v $p)\" -o $p != su ] && echo $p; "
                          "done").split()
    pruefe(not gefunden, f"kein Paketmanager, kein SSH, kein sudo, kein Compiler ({gefunden})")

    # Updates: nur über /usr/lib/zenos/update, nur mit der Signatur aus update-signierer (hier der Wegwerf-Schlüssel)
    signierer = befehl(vm, "grep -c '^argon-update namespaces=\"argon-update\" ' /usr/lib/zenos/update-signierer; "
                           "command -v ssh-keygen curl | wc -l; ls /usr/lib/systemd/systemd-pull 2>&1 | grep -c 'No such'; "
                           "grep -h '^Type=\\|^Path=/' /usr/lib/sysupdate.d/*.transfer | sort -u").split()
    pruefe(signierer[:3] == ["1", "2", "1"] and signierer[3:] == ["Path=/var/lib/zenos/update/quelle", "Type=partition",
                                                                  "Type=regular-file"],
           f"Updates: ein erlaubter Schlüssel, ssh-keygen und curl da, kein systemd-pull, sysupdate liest nur die "
           f"geprüfte Kopie ({' '.join(signierer)})")

    for dienst in ("nftables", "chrony", "NetworkManager", "systemd-resolved", "greetd"):
        zustand = befehl(vm, f"systemctl is-active {dienst}.service").strip()
        pruefe(zustand == "active", f"{dienst} läuft ({zustand})")
    laufend = set(befehl(vm, "systemctl --no-legend --plain list-units --type=service --state=running "
                             "| awk '{print $1}'").split())
    print(f"  laufende Dienste: {' '.join(sorted(laufend))}", flush=True)


def protokolle(vm: pexpect.spawn, warum: str) -> None:
    """Bei einem Fehler: was Login, Sitzung und Oberfläche ins Journal geschrieben haben."""
    print(f"\n  Protokolle ({warum}):", flush=True)
    for zeilen in ("journalctl -b --no-pager -o cat -u greetd.service | tail -n 30",
                   "journalctl -b --no-pager -o short-monotonic -t zenos-greeter -t labwc | tail -n 60",
                   "systemctl --user --no-pager status zenos-shell.service zenos-idle.service 2>&1 | tail -n 30",
                   "journalctl -b --no-pager -o short-monotonic --user -u zenos-shell.service | tail -n 60"):
        print("\n".join("    " + z for z in befehl(vm, zeilen).splitlines()), flush=True)


def pruefe_schluessel(vm: pexpect.spawn) -> None:
    """Bauauftrag 4, soweit es ohne Schlüssel geht: Werkzeuge, PAM-Kette, Zugriff für Chromium, zen schluessel."""
    print("\n--- Hardware-Schlüssel (ohne Gerät)", flush=True)
    fehlend = befehl(vm, "for b in fido2-token fido2-cred fido2-assert pamu2fcfg; do command -v $b >/dev/null || "
                         "echo $b; done; ls /usr/lib/*/security/pam_u2f.so >/dev/null 2>&1 || echo pam_u2f").split()
    pruefe(fehlend == [], f"FIDO2-Werkzeuge und pam_u2f im Image ({' '.join(fehlend) or 'alle da'})")
    ketten = befehl(vm, "for d in greetd zenos-sperre swaylock; do grep -Eq '^auth[[:space:]]+include[[:space:]]+"
                        "zenos-schluessel$' /etc/pam.d/$d && echo $d; done").split()
    pruefe(ketten == ["greetd", "zenos-sperre", "swaylock"], f"Login, Sperre und Notfall-Sperre verlangen den Schlüssel ({' '.join(ketten)})")
    u2f = befehl(vm, "grep -c '^auth.*required.*pam_u2f.so.*authfile=/var/lib/zenos/schluessel/u2f' /etc/pam.d/zenos-schluessel").strip()
    pruefe(u2f == "1", "pam_u2f mit der Liste unter /var/lib/zenos/schluessel")
    regeln = befehl(vm, "grep -l 'fido_id' /usr/lib/udev/rules.d/*.rules | head -1; "
                        "grep -h 'ID_SECURITY_TOKEN' /usr/lib/udev/rules.d/*.rules | grep -c uaccess").split()
    pruefe(len(regeln) == 2 and regeln[1] != "0", f"FIDO2-Schlüssel gehören der Sitzung am Gerät (udev uaccess, für Chromium) ({' '.join(regeln)})")
    liste = befehl(vm, "stat -c '%U %a' /var/lib/zenos/schluessel").strip()
    pruefe(liste == "root 755", f"die Liste der Schlüssel schreibt nur root ({liste})")
    seriell = befehl(vm, "zen schluessel status 2>&1")
    pruefe("nur an diesem Ger" in seriell, "zen schluessel von der seriellen Konsole abgelehnt")
    status = befehl(vm, "systemd-run --user --quiet --wait --pipe --collect zen schluessel status 2>&1")
    pruefe("Daten: 0" in status, f"zen schluessel status aus der Sitzung ({status.strip().splitlines()[0] if status.strip() else ''})")


def pruefe_oberflaeche(vm: pexpect.spawn) -> None:
    print("\n--- Oberfläche", flush=True)
    # Der Login (Quickshell unter labwc, Benutzer _greetd) läuft auf dem virtuellen Bildschirm
    login = warten_bis(vm, "pgrep -u _greetd -x quickshell >/dev/null && echo login-laeuft", "login-laeuft", 900)
    pruefe("login-laeuft" in login, "der Login von zenOS läuft (Quickshell als _greetd)")
    if "login-laeuft" not in login:
        protokolle(vm, "Login")
    time.sleep(25)  # Software-Rendering in QEMU ohne Beschleunigung: Zeit bis zum ersten Bild
    foto(vm, "01-login")

    # Anmelden wie ein Mensch: Das einzige Konto ist vorgewählt, das Passwortfeld hat den Fokus. Getippt wird vor Ablauf
    # der Minute, nach der der Login den Bildschirm ausschaltet (dann weckte die erste Taste nur).
    tippen(vm, KONTO_PASSWORT, enter=False)
    time.sleep(10)
    foto(vm, "01b-passwort-getippt")
    taste(vm, "ret")
    time.sleep(30)
    foto(vm, "01c-nach-enter")
    shell = warten_bis(vm, AKTIV_SHELL, "shell-laeuft", 600)
    pruefe(shell == "shell-laeuft", f"nach dem Login läuft die Oberfläche ({shell})")
    if shell != "shell-laeuft":
        protokolle(vm, "Sitzung")
        foto(vm, "01d-ohne-sitzung")
        return
    leiste = warten_bis(vm, "/usr/lib/zenos/ipc leiste status 2>&1", "zu", 600)
    pruefe(leiste == "zu", f"die Leiste antwortet ({leiste})")
    idle = befehl(vm, "systemctl --user is-active zenos-idle.service").strip()
    pruefe(idle == "active", f"die automatische Sperre läuft ({idle})")
    downloads = befehl(vm, 'readlink "$HOME/Downloads"; echo "$XDG_RUNTIME_DIR/zenos/downloads"; '
                           'findmnt -no FSTYPE -T "$XDG_RUNTIME_DIR"').split()
    pruefe(len(downloads) == 3 and downloads[0] == downloads[1] and downloads[2] == "tmpfs",
           f"Downloads liegen nur im Arbeitsspeicher ({' '.join(downloads)})")
    time.sleep(45)
    foto(vm, "02-sitzung-hell")

    # Apps in der Sitzung: Chromium (nur Wayland, ohne X) und kitty, gestartet wie aus dem Befehlsfeld
    befehl(vm, "systemd-run --user --quiet --collect --unit=test-chromium chromium --no-first-run about:blank")
    browser = warten_bis(vm, "pgrep -u $(id -u) -x chromium >/dev/null && echo browser-laeuft", "browser-laeuft", 300)
    pruefe("browser-laeuft" in browser, "Chromium startet in der Sitzung (Wayland)")
    time.sleep(90)
    foto(vm, "02b-chromium")
    befehl(vm, "systemctl --user stop test-chromium.service")
    befehl(vm, "systemd-run --user --quiet --collect --unit=test-kitty kitty")
    terminal = warten_bis(vm, "pgrep -u $(id -u) -x kitty >/dev/null && echo kitty-laeuft", "kitty-laeuft", 300)
    pruefe("kitty-laeuft" in terminal, "kitty startet in der Sitzung")
    time.sleep(45)
    foto(vm, "02c-kitty")
    befehl(vm, "systemctl --user stop test-kitty.service")

    # Befehlsfeld mit den Apps
    apps = befehl(vm, "/usr/lib/zenos/ipc befehlsfeld apps 2>&1").strip()
    pruefe(apps == "", f"das Befehlsfeld öffnet die Apps ({apps or 'ok'})")
    time.sleep(30)
    foto(vm, "03-apps")
    befehl(vm, "/usr/lib/zenos/ipc befehlsfeld schliessen")

    # Dunkel
    befehl(vm, "/usr/lib/zenos/ipc thema setzen dunkel")
    time.sleep(30)
    foto(vm, "04-sitzung-dunkel")
    befehl(vm, "/usr/lib/zenos/ipc leiste menue system")
    time.sleep(30)
    foto(vm, "05-systemmenue")
    befehl(vm, "/usr/lib/zenos/ipc leiste schliessen")

    # Sperren und mit dem Passwort über PAM entsperren
    befehl(vm, "/usr/lib/zenos/sperren")
    gesperrt = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "gesperrt", 120)
    pruefe(gesperrt == "gesperrt", f"Sperren über die Oberfläche (ext-session-lock) ({gesperrt})")
    time.sleep(30)
    foto(vm, "06-sperre")
    # Shift weckt einen dunklen Bildschirm (die Wecktaste geht nie ins Feld) und tippt sonst nichts
    taste(vm, "shift")
    time.sleep(5)
    tippen(vm, KONTO_PASSWORT)
    offen = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "offen", 120)
    pruefe(offen == "offen", f"Entsperren mit dem Passwort (PAM, systemd-homed) ({offen})")
    time.sleep(20)
    foto(vm, "07-entsperrt")

    # Deckel: QEMU hat keinen. Geprüft werden die Einstellung von logind und der Weg, den das Zuklappen auf dem Argon
    # nimmt: logind schickt «Lock» an die grafische Sitzung, swayidle ruft /usr/lib/zenos/sperren (wie die Ein/Aus-Taste).
    # Das Overlay selbst prüft mkosi/test/startpartitionen.sh am Image für den Argon.
    deckel = befehl(vm, "for e in HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked; do "
                        "busctl get-property org.freedesktop.login1 /org/freedesktop/login1 "
                        "org.freedesktop.login1.Manager $e; done").split()
    pruefe(deckel == ["s", '"lock"'] * 3, f"Zuklappen sperrt immer, auch am Netzteil und mit Bildschirm ({' '.join(deckel)})")
    befehl(vm, 'for s in $(loginctl show-user "$(id -u)" -p Sessions --value); do '
               '[ "$(loginctl show-session "$s" -p Type --value)" = wayland ] && loginctl lock-session "$s"; done')
    gesperrt = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "gesperrt", 120)
    pruefe(gesperrt == "gesperrt", f"logind sperrt die Sitzung (Weg des Deckels) ({gesperrt})")
    taste(vm, "shift")
    time.sleep(5)
    tippen(vm, KONTO_PASSWORT)
    offen = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "offen", 120)
    pruefe(offen == "offen", f"nach dem Deckel wieder entsperrt ({offen})")

    # Erinnerung an Updates: Der Zeitgeber läuft, das Konto darf fragen, ob die Uhr über NTS gestellt ist, zen status
    # nennt den Paketstand, und eine Erinnerung mit vorgestellter Uhr (Pakete 20 Tage alt) nimmt der Mitteilungsserver
    # der Oberfläche an
    zeitgeber = befehl(vm, "systemctl --user is-active zenos-erinnerung.timer").strip()
    pruefe(zeitgeber == "active", f"die Erinnerung an Updates ist eingeplant ({zeitgeber})")
    uhr = befehl(vm, "timedatectl show -p NTPSynchronized --value 2>&1").strip()
    pruefe(uhr in ("yes", "no"), f"timedatectl meldet, ob die Uhr gestellt ist ({uhr})")
    stand = [z for z in befehl(vm, "zen status").splitlines() if z.startswith("Pakete vom ")]
    pruefe(len(stand) == 1, f"zen status nennt den Paketstand ({stand[0] if stand else 'fehlt'})")
    erinnert = befehl(vm, "w=$(mktemp -d) && mkdir -p $w/usr/lib/zenos && cp /usr/lib/zenos/paketstand $w/usr/lib/zenos/ "
                          "&& j=$(( $(date -u -d $(cat $w/usr/lib/zenos/paketstand) +%s) + 20 * 86400 )) "
                          "&& systemd-run --user --quiet --wait --pipe --collect -E ZENOS_ERINNERUNG_TESTWURZEL=$w "
                          "-E ZENOS_ERINNERUNG_JETZT=$j -E XDG_STATE_HOME=$w/zustand /usr/lib/zenos/erinnerung 2>&1; "
                          "echo rc=$?")
    pruefe("erinnert: Pakete 20 Tage alt" in erinnert and "rc=0" in erinnert,
           "die Erinnerung kommt als Mitteilung bei der Oberfläche an" + ("" if "rc=0" in erinnert else f" ({erinnert.strip()})"))
    # Gesammelt käme sie zur vollen Stunde; für das Bild jetzt zustellen (die Sammelkarte steht 10 s), dann die Zentrale
    befehl(vm, "/usr/lib/zenos/ipc mitteilungen zustellen")
    time.sleep(4)
    foto(vm, "07b-erinnerung")
    zustand = befehl(vm, "/usr/lib/zenos/ipc mitteilungen status")
    wartend = re.search(r'"wartend":(\d+)', zustand)
    zugestellt = re.search(r'"zugestellt":(\d+)', zustand)
    pruefe(wartend is not None and zugestellt is not None and wartend.group(1) == "0" and int(zugestellt.group(1)) >= 1,
           f"die Erinnerung ist zugestellt ({zustand.strip()[:120]})")
    befehl(vm, "/usr/lib/zenos/ipc mitteilungen oeffnen")
    time.sleep(15)
    foto(vm, "07c-zentrale")
    befehl(vm, "/usr/lib/zenos/ipc mitteilungen schliessen")

    # Was die Oberfläche (zenos-shell.service) ins Journal schreibt; das Prüfkonto liest es (systemd-journal)
    protokoll = befehl(vm, "journalctl -b --no-pager -o cat _SYSTEMD_USER_UNIT=zenos-shell.service "
                           "| grep -viE 'inotify_add_watch|EGL|dri2' | grep -iE 'error|warn|fail|not' | tail -n 40")
    print("  Meldungen der Oberfläche (Auszug):\n" + "\n".join("    " + z for z in protokoll.splitlines()), flush=True)


def pruefe_update(vm: pexpect.spawn) -> str:
    """zen update gegen den Testserver: lädt den zweiten Stand und schreibt ihn in die B-Hälfte."""
    if str(UPDATE) == "/nicht-vorhanden":
        print("\n--- Update (übersprungen: kein zweiter Stand)", flush=True)
        return ""
    ende = time.monotonic() + 3600
    # Die Signatur entsteht zuletzt (mkosi/veroeffentlichen.sh qemu): erst dann ist der zweite Stand fertig
    while not (UPDATE / "SHA256SUMS.sig").is_file() and time.monotonic() < ende:
        time.sleep(20)
    if not (UPDATE / "SHA256SUMS").is_file() or not (UPDATE / "SHA256SUMS.sig").is_file():
        pruefe(False, f"zweiter Stand unter {UPDATE} bereit und signiert (mkosi/veroeffentlichen.sh qemu)")
        return ""
    print("\n--- Update", flush=True)
    neu = next(n.split("_")[1] for n in os.listdir(UPDATE) if n.endswith(".root.raw.xz"))
    # Der Testserver liefert einen Ordner mit Verweisen auf den zweiten Stand; für die Angriffe wird er verändert.
    angebot = Path(tempfile.mkdtemp(prefix="zenos-update-"))

    def anbieten(liste: bytes | None = None, signatur: bool = True, tausch: dict[str, str] | None = None) -> None:
        for alt in angebot.iterdir():
            alt.unlink()
        for name in os.listdir(UPDATE):
            if name == "SHA256SUMS" and liste is not None:
                (angebot / name).write_bytes(liste)
            elif name == "SHA256SUMS.sig" and not signatur:
                continue
            else:
                (angebot / name).symlink_to(UPDATE / (tausch or {}).get(name, name))

    def nichts_installiert() -> bool:
        return f"zenos_{neu}" not in befehl(vm, "lsblk -nr -o PARTLABEL /dev/vda").split()

    def zen_update() -> str:
        # Wie im Terminal der Sitzung (kitty läuft in der Benutzerinstanz)
        return befehl(vm, "systemd-run --user --quiet --wait --pipe --collect zen update 2>&1")

    anbieten()
    server = subprocess.Popen([sys.executable, "-m", "http.server", "8080", "--bind", "127.0.0.1",
                               "--directory", str(angebot)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        # Zuerst, solange noch kein Stand wartet: Die serielle Konsole ist keine Sitzung am Gerät, polkit lässt
        # zenos-update.service von dort nicht starten (sofort, ohne nach einem Passwort zu fragen)
        seriell = befehl(vm, "timeout 60 zen update 2>&1")
        pruefe("liess sich nicht starten" in seriell and "Password" not in seriell,
               "zen update von der seriellen Konsole (keine Sitzung am Gerät) abgelehnt, ohne Passwortfrage")

        # Angriffe auf den Update-Weg: Keiner darf etwas schreiben (Leitplanke: nur, was zenOS signiert hat)
        echt = (UPDATE / "SHA256SUMS").read_bytes()
        anbieten(liste=re.sub(rb"^[0-9a-f]{64}", b"0" * 64, echt, count=1))
        ausgabe = zen_update()
        pruefe("Signatur des Updates stimmt nicht" in ausgabe and nichts_installiert(),
               "Liste nach dem Signieren verändert: abgelehnt, nichts geschrieben")
        anbieten(signatur=False)
        ausgabe = zen_update()
        pruefe("kein signierter Stand" in ausgabe and nichts_installiert(),
               "Stand ohne Signatur: abgelehnt, nichts geschrieben")
        system = next(n for n in os.listdir(UPDATE) if n.endswith(".root.raw.xz"))
        verity = next(n for n in os.listdir(UPDATE) if n.endswith(".root-verity.raw.xz"))
        anbieten(tausch={system: verity})
        ausgabe = zen_update()
        pruefe("Prüfsumme" in ausgabe and nichts_installiert(),
               "System nach dem Signieren ausgetauscht: abgelehnt, nichts geschrieben")

        anbieten()
        ausgabe = zen_update()
        print("\n".join("    " + z for z in ausgabe.splitlines()[-12:]), flush=True)
        pruefe(f"Neuer Stand {neu} ist installiert" in ausgabe, f"zen update installiert {neu} ohne Admin")
        teile = befehl(vm, "lsblk -nr -o PARTLABEL /dev/vda").split()
        pruefe(f"zenos_{neu}" in teile and f"zenos_{neu}_verity" in teile,
               f"{neu} liegt in der B-Hälfte (System und Prüfsummen)")
        pruefe("wartet auf den Neustart" in befehl(vm, "zen status"), "zen status meldet den wartenden Neustart")
        time.sleep(40)
        foto(vm, "08-update-neustart")
        nochmal = befehl(vm, "systemd-run --user --quiet --wait --pipe --collect zen update 2>&1")
        pruefe("wartet auf den Neustart" in nochmal, "ein zweites zen update lädt nicht nochmals")
    finally:
        server.terminate()
        shutil.rmtree(angebot, ignore_errors=True)
    return neu


def zen_notfall(vm: pexpect.spawn, aktion: str, *eingaben: str) -> str:
    """zen notfall wie im Terminal der Sitzung (Benutzerinstanz); die Passwörter kommen über stdin."""
    zeilen = "".join(f"{e}\\n" for e in eingaben)
    return befehl(vm, f"printf '{zeilen}' | systemd-run --user --quiet --wait --pipe --collect zen notfall {aktion} 2>&1")


def pruefe_notfall_befehl(vm: pexpect.spawn) -> None:
    """zen notfall: nur aus der Sitzung am Gerät, jede Änderung mit dem Passwort der Daten, nichts im Journal."""
    print("\n--- zen notfall", flush=True)
    seriell = befehl(vm, "zen notfall status 2>&1")
    pruefe("nur an diesem Ger" in seriell, "zen notfall von der seriellen Konsole (keine Sitzung am Gerät) abgelehnt")
    status = zen_notfall(vm, "status")
    pruefe("ist gesetzt" in status, f"das Notfall-Passwort vom ersten Start ist gesetzt ({status.strip()})")
    falsch = zen_notfall(vm, "aendern", "falsches-daten-passwort", NOTFALL_PASSWORT_2, NOTFALL_PASSWORT_2)
    pruefe("stimmt nicht" in falsch, "ändern mit einem falschen Passwort der Daten wird abgelehnt")
    gleich = zen_notfall(vm, "aendern", DATEN_PASSWORT, DATEN_PASSWORT, DATEN_PASSWORT)
    pruefe("Nimm ein anderes" in gleich, "ein Notfall-Passwort, das die Daten öffnet, wird abgelehnt")
    geaendert = zen_notfall(vm, "aendern", DATEN_PASSWORT, NOTFALL_PASSWORT_2, NOTFALL_PASSWORT_2)
    pruefe("Notfall-Passwort gesetzt" in geaendert, f"Notfall-Passwort ändern ({geaendert.strip()})")
    entfernt = zen_notfall(vm, "entfernen", DATEN_PASSWORT)
    leer = zen_notfall(vm, "status")
    pruefe("entfernt" in entfernt and "Kein Notfall-Passwort" in leer, f"Notfall-Passwort entfernen ({leer.strip()})")
    gesetzt = zen_notfall(vm, "setzen", DATEN_PASSWORT, NOTFALL_PASSWORT, NOTFALL_PASSWORT)
    wieder = zen_notfall(vm, "status")
    pruefe("Notfall-Passwort gesetzt" in gesetzt and "ist gesetzt" in wieder, "Notfall-Passwort wieder setzen")
    muster = f"-e '{NOTFALL_PASSWORT}' -e '{NOTFALL_PASSWORT_2}' -e '{DATEN_PASSWORT}' -e 'zenos-notfall@'"
    journal = befehl(vm, f"journalctl -b --no-pager -o cat | grep -c {muster}")
    pruefe(journal.strip() == "0", f"nichts davon im Journal (Treffer: {journal.strip()})")
    if journal.strip() != "0":
        print(befehl(vm, f"journalctl -b --no-pager -o short-monotonic | grep {muster} | head -n 6"), flush=True)
    # Erkennungszeichen der echten Daten: Nach dem Notfall darf es nicht mehr da sein. sync: Der Test startet die
    # Maschine danach hart neu.
    befehl(vm, "touch ~/echte-daten && sync")


def warten_auf_aus(vm: pexpect.spawn, sekunden: int) -> tuple[bool, int]:
    """Wartet, bis die Maschine sich ausschaltet (QEMU endet). Gibt zurück, ob sie aus ist, und nach wie vielen Sekunden.
    In kurzen Schritten mit der monotonen Uhr: pexpect misst seine Wartezeit mit der Uhrzeit, und die Uhr der Bau-VM
    kann springen (einmal endete das Warten so nach 293 statt 420 Sekunden)."""
    anfang = time.monotonic()
    while time.monotonic() - anfang < sekunden:
        try:
            vm.expect(pexpect.EOF, timeout=10)
            return True, int(time.monotonic() - anfang)
        except pexpect.TIMEOUT:
            continue
    return False, int(time.monotonic() - anfang)


def pruefe_ausschalten(vm: pexpect.spawn) -> bool:
    """Bauauftrag 3: gesperrt (mit Inhibitor), eine Minute vorher der Hinweis, Entsperren setzt zurück, wieder gesperrt
    schaltet zenOS aus. Im Test-Image nach 5 Minuten statt 30. True, wenn die Maschine danach aus ist."""
    print("\n--- Ausschalten nach langer Sperre", flush=True)
    nach = int(befehl(vm, "cat /usr/lib/zenos/ausschalten-test-nach 2>/dev/null || echo 1800").strip() or "1800")
    aktiv = befehl(vm, "systemctl is-active zenos-ausschalten.service").strip()
    pruefe(aktiv == "active", f"der Wächter läuft ({aktiv}, Grenze im Test-Image {nach} s)")
    befehl(vm, "systemd-run --user --quiet --collect --unit=test-hemmer systemd-inhibit --what=shutdown:idle "
               "--mode=block --who=Test --why=Test sleep 3600")
    hemmer = warten_bis(vm, "systemd-inhibit --list --no-legend | grep -q Test && echo hemmer-da || echo noch-nicht",
                        "hemmer-da", 60)
    pruefe(hemmer == "hemmer-da", f"ein Programm hält einen Inhibitor gegen das Ausschalten ({hemmer})")
    gesperrt_frage = 'loginctl show-session "$(loginctl show-user "$(id -u)" -p Display --value)" -p LockedHint --value'
    befehl(vm, "/usr/lib/zenos/sperren")
    hinweis = warten_bis(vm, gesperrt_frage, "yes", 60)
    pruefe(hinweis == "yes", f"die Sperre meldet sich bei logind (LockedHint {hinweis})")
    vorher = warten_bis(vm, "test -s /run/zenos-ausschalten/um && echo hinweis-da || echo noch-nicht", "hinweis-da",
                        nach + 60)
    pruefe(vorher == "hinweis-da", "eine Minute vorher steht der Zeitpunkt für die Sperre bereit")
    taste(vm, "shift")  # Bildschirm an, ohne etwas ins Feld zu tippen
    time.sleep(8)
    foto(vm, "10-ausschalten-hinweis")
    tippen(vm, KONTO_PASSWORT)
    offen = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "offen", 60)
    weg = warten_bis(vm, "test -e /run/zenos-ausschalten/um && echo noch-da || echo weg", "weg", 40)
    nicht_gesperrt = befehl(vm, gesperrt_frage).strip()
    pruefe(offen == "offen" and weg == "weg" and nicht_gesperrt == "no",
           f"Entsperren setzt die Zeit zurück ({offen}, Hinweis {weg}, LockedHint {nicht_gesperrt})")
    befehl(vm, "/usr/lib/zenos/sperren")
    aus, dauer = warten_auf_aus(vm, nach + 120)
    pruefe(aus and dauer >= nach - 30, f"gesperrt nach {nach} s ausgeschaltet, trotz Inhibitor ({dauer} s)")
    return aus


def pruefe_attrappe(vm: pexpect.spawn) -> None:
    """Nach dem Notfall-Passwort: angemeldetes leeres Konto unter dem Namen, /var im Arbeitsspeicher, Sperre mit dem
    Notfall-Passwort, kein Update, keine Erinnerung."""
    print("\n--- Attrappe nach dem Notfall-Passwort", flush=True)
    pruefe(KONTO in befehl(vm, "id -un"), "dasselbe Konto, angemeldet mit dem Notfall-Passwort")
    pruefe("fehlt" in befehl(vm, "test -e ~/echte-daten && echo da || echo fehlt"), "von den echten Daten ist nichts da")
    quelle = befehl(vm, 'findmnt -no SOURCE /var; '
                        'ls --color=never "/sys/block/$(basename "$(readlink -f /dev/mapper/daten)")/slaves"').split()
    pruefe(len(quelle) == 2 and quelle[0] == "/dev/mapper/daten" and quelle[1].startswith(("zram", "loop")),
           f"/var liegt im Arbeitsspeicher ({' '.join(quelle)})")
    shell = warten_bis(vm, AKTIV_SHELL, "shell-laeuft", 600)
    pruefe(shell == "shell-laeuft", f"die Sitzung ist von selbst angemeldet ({shell})")
    leiste = warten_bis(vm, "/usr/lib/zenos/ipc leiste status 2>&1", "zu", 600)
    pruefe(leiste == "zu", f"Leiste wie gewohnt ({leiste})")
    print("    Sitzungen: " + " | ".join(befehl(vm, "loginctl list-sessions --no-legend").splitlines()), flush=True)
    time.sleep(45)
    foto(vm, "09-attrappe")
    befehl(vm, "/usr/lib/zenos/sperren")
    gesperrt = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "gesperrt", 120)
    taste(vm, "shift")
    time.sleep(5)
    tippen(vm, NOTFALL_PASSWORT)
    offen = warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "offen", 120)
    pruefe(gesperrt == "gesperrt" and offen == "offen", f"die Sperre entsperrt mit dem Notfall-Passwort ({gesperrt}, {offen})")
    update = befehl(vm, "systemd-run --user --quiet --wait --pipe --collect zen update 2>&1")
    pruefe("ist aktuell" in update, f"zen update lädt nichts und sieht normal aus ({update.strip()})")
    jetzt = int(time.time()) + 30 * 86400
    erinnerung = befehl(vm, f"ZENOS_ERINNERUNG_JETZT={jetzt} /usr/lib/zenos/erinnerung 2>&1; echo rc=$?")
    pruefe("erinnert" not in erinnerung and "rc=0" in erinnerung, "keine Erinnerung an Updates")
    waechter = befehl(vm, "systemctl is-active zenos-ausschalten.service").strip()
    pruefe(waechter == "active", f"auch hier schaltet zenOS nach langer Sperre aus ({waechter})")


def partitionen(roh: Path) -> dict[str, tuple[int, int]]:
    """GPT eines rohen Abbilds: Name → (Anfang, Grösse) in Bytes."""
    import struct
    teile = {}
    with open(roh, "rb") as f:
        f.seek(512)
        kopf = f.read(92)
        anfang, anzahl, groesse = struct.unpack_from("<QII", kopf, 72)
        f.seek(anfang * 512)
        for _ in range(anzahl):
            eintrag = f.read(groesse)
            if eintrag[:16] == b"\0" * 16:
                continue
            erster, letzter = struct.unpack_from("<QQ", eintrag, 32)
            name = eintrag[56:128].decode("utf-16-le").rstrip("\0")
            teile[name] = (erster * 512, (letzter - erster + 1) * 512)
    return teile


def pruefe_platte_nach_notfall(arbeit: Path) -> None:
    """Von aussen (ausgeschaltete Maschine): keine Schlüsselplätze mehr in den Daten, Notfall-Partition genullt."""
    print("\n--- Platte nach dem Notfall (von aussen)", flush=True)
    roh = arbeit / "platte.raw"
    subprocess.run(["qemu-img", "convert", "-O", "raw", str(arbeit / "platte.qcow2"), str(roh)], check=True)
    try:
        teile = partitionen(roh)
        if "zenos-daten" not in teile or "zenos-notfall" not in teile:
            pruefe(False, f"Daten- und Notfall-Partition gefunden ({', '.join(teile)})")
            return
        kopf = arbeit / "daten-kopf.img"
        with open(roh, "rb") as f, open(kopf, "wb") as k:
            f.seek(teile["zenos-daten"][0])
            k.write(f.read(16 * 1048576))
        dump = subprocess.run(["cryptsetup", "luksDump", str(kopf)], capture_output=True, text=True).stdout
        plaetze = re.findall(r"(?m)^  [0-9]+: luks2", dump.split("Tokens:")[0])
        pruefe("LUKS header information" in dump and not plaetze,
               f"luksDump der Daten: Kopf da, keine Schlüsselplätze ({len(plaetze)})")
        with open(roh, "rb") as f:
            f.seek(teile["zenos-notfall"][0])
            inhalt = f.read(teile["zenos-notfall"][1])
        pruefe(len(inhalt) > 0 and inhalt.count(0) == len(inhalt), "die Notfall-Partition ist ganz genullt")
    finally:
        roh.unlink(missing_ok=True)


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
    vm.expect(r"Neues Passwort f.r deine Daten:")
    vm.sendline(DATEN_PASSWORT)
    vm.expect("Noch einmal:")
    vm.sendline(DATEN_PASSWORT)
    # QEMU hat keinen Hardware-Schlüssel: Nur das Test-Image legt dann einen Platz mit dem Passwort allein an
    vm.expect("Test-Image ohne Hardware-Schl")
    pruefe(True, "ohne Schlüssel nur im Test-Image ein Platz mit dem Passwort allein")
    vm.expect("Bereit\\? Enter")
    vm.sendline("")
    vm.expect(WIEDERHERSTELLUNG)
    wiederherstellung = vm.match.group(0)
    pruefe(True, "Wiederherstellungsschlüssel wird angezeigt")
    vm.expect("Aufgeschrieben\\? Enter")
    vm.sendline("")
    # Notfall-Passwort: Eines, das die Daten öffnet (hier das Passwort selbst), wird abgelehnt
    vm.expect(r"Notfall-Passwort \(Enter = keins\):")
    vm.sendline(DATEN_PASSWORT)
    vm.expect("Noch einmal:")
    vm.sendline(DATEN_PASSWORT)
    vm.expect(r"Das .ffnet deine Daten")
    pruefe(True, "ein Notfall-Passwort gleich dem Passwort der Daten wird abgelehnt")
    vm.expect(r"Notfall-Passwort \(Enter = keins\):")
    vm.sendline(NOTFALL_PASSWORT)
    vm.expect("Noch einmal:")
    vm.sendline(NOTFALL_PASSWORT)
    vm.expect("Notfall-Passwort gesetzt")
    pruefe(True, "Notfall-Passwort beim ersten Start gesetzt")
    vm.expect(DATEN_FRAGE)
    vm.sendline(DATEN_PASSWORT)
    # homectl firstboot wartet zuerst auf eine Taste, damit die Meldungen davor lesbar bleiben.
    if vm.expect([r"(?i)press any key", r"(?i)user name"]) == 0:
        vm.send("\r")
        vm.expect(r"(?i)user name")
    vm.sendline(KONTO)
    # homectl fragt nach Zusatzgruppen, dann zweimal nach dem Passwort. Nur das Prüfkonto dieser Wegwerf-Maschine
    # bekommt systemd-journal, damit der Test bei einem Fehler die Protokolle zeigen kann; kein Admin, kein wheel.
    gruppe_gesetzt = False
    while True:
        frage = vm.expect([r"(?i)auxiliary group", r"(?i)shell", r"(?i)password", r"login: "])
        if frage == 0 and not gruppe_gesetzt:
            vm.sendline("systemd-journal")
            gruppe_gesetzt = True
        elif frage in (0, 1):
            vm.sendline("")
        elif frage == 2:
            vm.sendline(KONTO_PASSWORT)
        else:
            break
    vm.sendline(KONTO)
    vm.expect(r"[Pp]assword: ")
    vm.sendline(KONTO_PASSWORT)
    vm.expect(r"\$ ")
    pruefe_system(vm)

    pruefe_oberflaeche(vm)
    neu = pruefe_update(vm)
    pruefe_notfall_befehl(vm)
    pruefe_schluessel(vm)

    # Die serielle Konsole ist keine Sitzung am Gerät. Neu starten ginge von dort nur als Admin, und den gibt es
    # nicht (root ist gesperrt). Am Gerät selbst darf die angemeldete Person neu starten.
    antwort = befehl(vm, "systemctl reboot --no-ask-password 2>&1")
    pruefe(re.search(r"(?i)authentication required|access denied|not authorized", antwort) is not None,
           "ohne Sitzung am Gerät kein Neustart (kein Admin)")

    aus = pruefe_ausschalten(vm)

    print("\n--- Zweiter Start: falsches Passwort, dann der Wiederherstellungsschlüssel", flush=True)
    if aus:
        vm = starte(arbeit)
    else:
        monitor(vm, "system_reset")
    index = vm.expect([DATEN_FRAGE, "Nummer: "])
    pruefe(index == 0, "die Einrichtung kommt nicht wieder; der Start fragt nur nach dem Passwort")
    vm.sendline("falsches-passwort-nur-fuer-qemu")
    vm.expect("stimmt nicht")
    vm.expect(DATEN_FRAGE)
    pruefe(True, "falsches Passwort: «stimmt nicht», die Frage kommt wieder")
    vm.sendline(wiederherstellung.upper().replace("-", ""))
    anmelden(vm)
    pruefe(KONTO in befehl(vm, "id -un") and "da" == befehl(vm, "test -e ~/echte-daten && echo da").strip(),
           "Wiederherstellungsschlüssel (gross, ohne Bindestriche) öffnet die Daten; nichts gelöscht")
    pruefe("Read-only file system" in befehl(vm, "touch /etc/zenos-test 2>&1"), "System nach dem Neustart unverändert")
    if neu:
        # QEMU startet über systemd-boot weiter den alten Stand (kein Bootloader von Raspberry Pi, kein Probestart):
        # Das Update gilt als ausgeschaltet statt neu gestartet und wartet auf einen weiteren Neustart.
        pruefe("wartet auf einen Neustart" in befehl(vm, "zen status"), "nach dem Neustart ohne Probe wartet das Update weiter")

    print("\n--- Dritter Start: das echte Passwort", flush=True)
    monitor(vm, "system_reset")
    vm.expect(DATEN_FRAGE)
    vm.sendline(DATEN_PASSWORT)
    anmelden(vm)
    pruefe(KONTO in befehl(vm, "id -un"), "das Konto ist nach dem Neustart noch da")
    # Am Login nach dem Entsperren der Daten, ohne Anmeldung am Bildschirm (nur die serielle Konsole): aus
    nach = int(befehl(vm, "cat /usr/lib/zenos/ausschalten-test-nach 2>/dev/null || echo 1800").strip() or "1800")
    aus, dauer = warten_auf_aus(vm, nach + 180)
    pruefe(aus, f"am Login ohne Anmeldung nach {nach} s ausgeschaltet ({dauer} s nach den Prüfungen)")

    # Zuletzt, weil es die Maschine zerstört
    print("\n--- Vierter Start: das Notfall-Passwort", flush=True)
    if aus:
        vm = starte(arbeit)
    else:
        monitor(vm, "system_reset")
    vm.expect(DATEN_FRAGE)
    vm.sendline(NOTFALL_PASSWORT)
    index = vm.expect(["stimmt nicht", r"login: "])
    pruefe(index == 1, "mit dem Notfall-Passwort läuft der Start weiter wie mit dem echten")
    if index == 1:
        anmelden(vm, NOTFALL_PASSWORT, warten=False)
        pruefe_attrappe(vm)
    monitor(vm, "quit")
    vm.expect(pexpect.EOF)
    pruefe_platte_nach_notfall(arbeit)

    print("\n--- Fünfter Start: nach dem Notfall stimmt kein Passwort mehr", flush=True)
    vm = starte(arbeit)
    vm.expect(DATEN_FRAGE)
    for name, passwort in (("echtes Passwort", DATEN_PASSWORT), ("Notfall-Passwort", NOTFALL_PASSWORT),
                           ("Wiederherstellungsschlüssel", wiederherstellung)):
        vm.sendline(passwort)
        index = vm.expect(["stimmt nicht", r"login: "])
        pruefe(index == 0, f"{name}: «stimmt nicht»")
        if index != 0:
            break
        vm.expect(DATEN_FRAGE)
    monitor(vm, "quit")
    vm.expect(pexpect.EOF)

    print(f"\n--- {'Alle Prüfungen bestanden' if not befunde else f'{len(befunde)} Befunde'}", flush=True)
    for befund in befunde:
        print(f"  - {befund}")
    return 0 if not befunde else 1


if __name__ == "__main__":
    sys.exit(main())
