#!/usr/bin/env python3
"""Angriffs- und Starttest für zenOS 1.0 in QEMU (Profil qemu).

Startet das Image in einer virtuellen Maschine, bedient den ersten Start über die serielle Konsole wie ein Mensch
(Tastatur, Passwort für die Daten, Wiederherstellungsschlüssel, Konto) und prüft danach am laufenden System, was die
Leitplanken versprechen. Dann die Oberfläche auf dem virtuellen Bildschirm: Anmelden am Login (Tastatur über QEMU),
Leiste, Sperren und Entsperren mit PAM, Befehlsfeld, hell und dunkel, jeweils mit Bildschirmfoto. Zuletzt ein zweiter
Start: Die Einrichtung darf nicht wiederkommen, das Passwort muss gelten.

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


def anmelden(vm: pexpect.spawn) -> None:
    vm.expect(r"login: ")
    vm.sendline(KONTO)
    vm.expect(r"[Pp]assword: ")
    vm.sendline(KONTO_PASSWORT)
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

    gefunden = befehl(vm, "for p in sudo su ssh sshd apt dpkg gcc make Xwayland pkexec; do "
                          "[ -x \"$(command -v $p)\" ] && [ -u \"$(command -v $p)\" -o $p != su ] && echo $p; done").split()
    pruefe(not gefunden, f"kein Paketmanager, kein SSH, kein sudo, kein Compiler ({gefunden})")

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
    shell = warten_bis(vm, "systemctl --user is-active zenos-shell.service", "active", 600)
    pruefe(shell.endswith("active") and "inactive" not in shell, f"nach dem Login läuft die Oberfläche ({shell})")
    if not shell.endswith("active") or "inactive" in shell:
        protokolle(vm, "Sitzung")
        foto(vm, "01d-ohne-sitzung")
        return
    leiste = warten_bis(vm, "/usr/lib/zenos/ipc leiste status 2>&1", "zu", 600)
    pruefe(leiste == "zu", f"die Leiste antwortet ({leiste})")
    idle = befehl(vm, "systemctl --user is-active zenos-idle.service").strip()
    pruefe(idle == "active", f"die automatische Sperre läuft ({idle})")
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
    while not (UPDATE / "SHA256SUMS").is_file() and time.monotonic() < ende:
        time.sleep(20)
    if not (UPDATE / "SHA256SUMS").is_file():
        pruefe(False, f"zweiter Stand unter {UPDATE} bereit")
        return ""
    print("\n--- Update", flush=True)
    neu = next(n.split("_")[1] for n in os.listdir(UPDATE) if n.endswith(".root.raw.xz"))
    server = subprocess.Popen([sys.executable, "-m", "http.server", "8080", "--bind", "127.0.0.1",
                               "--directory", str(UPDATE)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        # Zuerst, solange noch kein Stand wartet: Die serielle Konsole ist keine Sitzung am Gerät, polkit lässt
        # zenos-update.service von dort nicht starten (sofort, ohne nach einem Passwort zu fragen)
        seriell = befehl(vm, "timeout 60 zen update 2>&1")
        pruefe("liess sich nicht starten" in seriell and "Password" not in seriell,
               "zen update von der seriellen Konsole (keine Sitzung am Gerät) abgelehnt, ohne Passwortfrage")
        # Wie im Terminal der Sitzung (kitty läuft in der Benutzerinstanz)
        ausgabe = befehl(vm, "systemd-run --user --quiet --wait --pipe --collect zen update 2>&1")
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
    return neu


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
    vm.expect(r"(?i)passphrase.*for disk.*:")
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

    # Die serielle Konsole ist keine Sitzung am Gerät. Neu starten ginge von dort nur als Admin, und den gibt es
    # nicht (root ist gesperrt). Am Gerät selbst darf die angemeldete Person neu starten.
    antwort = befehl(vm, "systemctl reboot --no-ask-password 2>&1")
    pruefe(re.search(r"(?i)authentication required|access denied|not authorized", antwort) is not None,
           "ohne Sitzung am Gerät kein Neustart (kein Admin)")

    print("\n--- Zweiter Start", flush=True)
    monitor(vm, "system_reset")
    index = vm.expect([r"(?i)passphrase.*for disk.*:", "Nummer: "])
    pruefe(index == 0, "die Einrichtung kommt nicht wieder; der Start fragt nur nach dem Passwort")
    vm.sendline(DATEN_PASSWORT)
    anmelden(vm)
    pruefe("Read-only file system" in befehl(vm, "touch /etc/zenos-test 2>&1"), "System nach dem Neustart unverändert")
    pruefe(KONTO in befehl(vm, "id -un"), "das Konto ist nach dem Neustart noch da")
    if neu:
        # QEMU startet über systemd-boot weiter den alten Stand (kein Bootloader von Raspberry Pi, kein Probestart):
        # Das Update gilt als ausgeschaltet statt neu gestartet und wartet auf einen weiteren Neustart.
        pruefe("wartet auf einen Neustart" in befehl(vm, "zen status"), "nach dem Neustart ohne Probe wartet das Update weiter")
    monitor(vm, "quit")
    vm.expect(pexpect.EOF)

    print(f"\n--- {'Alle Prüfungen bestanden' if not befunde else f'{len(befunde)} Befunde'}", flush=True)
    for befund in befunde:
        print(f"  - {befund}")
    return 0 if not befunde else 1


if __name__ == "__main__":
    sys.exit(main())
