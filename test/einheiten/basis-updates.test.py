#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-basis (Paket-Updates der Ubuntu-Basis): Auswertung von «apt-get -s full-upgrade»
mit Fixtures (ohne und mit Kernel, Entfernungen, Sicherheit, geschützte Pakete, Herstellerquellen), Hash der Liste,
pruefen, installieren (Sperren, Auftrag, Zustimmung, policy-rc.d nur gegen greetd, install.sh danach, Gesundheit, Log,
Neustart nach einer neuen greetd-Version) und status. Dazu die Zeile «Pakete» von zen version.

Das Programm wird als Modul geladen; die Tests legen alle Pfade in einen Temp-Ordner und ersetzen apt-get, apt-mark,
dpkg, dpkg-query, install.sh und zen durch Attrappen (Python-Skripte). Die Attrappe von apt-get führt DPkg::Pre-Invoke
und DPkg::Post-Invoke wie apt mit /bin/sh aus und fragt die eingesetzte policy-rc.d. systemd gibt es im Test nicht
(kein Inhibitor, keine Sitzungen). Zeiten sind eingefroren. Ohne Root, ohne Netz; als root ebenso.

  python3 test/einheiten/basis-updates.test.py
"""

import contextlib
import datetime
import fcntl
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-basis")
AUFRAEUMEN = os.path.join(WURZEL, "scripts", "lib", "aufraeumen.sh")
GEMEINSAM = os.path.join(WURZEL, "scripts", "lib", "gemeinsam.sh")
VERSION = os.path.join(WURZEL, "scripts", "zen.d", "version.sh")
BASH = shutil.which("bash")
SH = "/bin/sh"

_loader = importlib.machinery.SourceFileLoader("zenos_basis", PROGRAMM)
_spec = importlib.util.spec_from_loader("zenos_basis", _loader)
B = importlib.util.module_from_spec(_spec)
_loader.exec_module(B)
ORIGINAL = {k: getattr(B, k) for k in dir(B) if k.isupper()}
ORIGINAL_NOW = B.now

JETZT = datetime.datetime(2026, 10, 7, 10, 0, 0, tzinfo=datetime.timezone.utc)

KOPF = """Reading package lists...
Building dependency tree...
Reading state information...
Calculating upgrade...
"""

# Wie auf 26.04 im Container (gekürzt), dazu eine Herstellerquelle mit Leerzeichen in der Herkunft
SIM_OHNE_KERNEL = KOPF + """The following upgrades have been deferred due to phasing:
  openssh-client openssh-server
The following packages will be upgraded:
  example-tool glycin-loaders libheif1 libssl3t64 openssl sudo
6 upgraded, 0 newly installed, 0 to remove and 2 not upgraded.
Inst libssl3t64 [3.5.5-1ubuntu3.5] (3.5.5-1ubuntu3.7 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
Conf libssl3t64 (3.5.5-1ubuntu3.7 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
Inst sudo [1.9.17p2-1ubuntu3.1] (1.9.17p2-1ubuntu3.2 Ubuntu:26.04/resolute-security [arm64])
Inst openssl [3.5.5-1ubuntu3.5] (3.5.5-1ubuntu3.7 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
Inst libheif1 [1.21.2-3ubuntu0.5] (1.21.2-3ubuntu0.6 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64]) [libheif-plugin-aomdec:arm64 ]
Inst glycin-loaders [2.1.1+ds-0ubuntu1] (2.1.5+ds-0ubuntu0.2 Ubuntu:26.04/resolute-updates [arm64])
Inst example-tool [1.0-1] (1.1-1 Example Vendor LLC:1.0/stable [arm64]) []
Conf sudo (1.9.17p2-1ubuntu3.2 Ubuntu:26.04/resolute-security [arm64])
Conf openssl (3.5.5-1ubuntu3.7 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
"""

SIM_MIT_KERNEL = KOPF + """The following NEW packages will be installed:
  linux-image-7.0.0-1012-raspi linux-modules-7.0.0-1012-raspi
Inst linux-modules-7.0.0-1012-raspi (7.0.0-1012.12 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
Inst linux-image-7.0.0-1012-raspi (7.0.0-1012.12 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
Inst linux-raspi [7.0.0-1010.10] (7.0.0-1012.12 Ubuntu:26.04/resolute-updates [arm64])
Inst linux-firmware-raspi [9-0ubuntu1] (9-0ubuntu1.1 Ubuntu:26.04/resolute-updates [arm64])
Inst flash-kernel [3.110ubuntu2] (3.110ubuntu2.1 Ubuntu:26.04/resolute-updates [all])
Inst libc6 [2.42-0ubuntu3] (2.42-0ubuntu3.1 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
Inst libc6:armhf [2.42-0ubuntu3] (2.42-0ubuntu3.1 Ubuntu:26.04/resolute-updates [armhf])
Inst linux-libc-dev [7.0.0-34.34] (7.0.0-38.38 Ubuntu:26.04/resolute-updates [arm64])
Conf libc6 (2.42-0ubuntu3.1 Ubuntu:26.04/resolute-updates, Ubuntu:26.04/resolute-security [arm64])
"""

SIM_ENTFERNUNG = KOPF + """The following packages will be REMOVED:
  libalt1
Remv libalt1 [1.0-1]
Inst libalt1t64 (1.0-1.1 Ubuntu:26.04/resolute-updates [arm64])
Inst sudo [1.9.17p2-1ubuntu3.1] (1.9.17p2-1ubuntu3.2 Ubuntu:26.04/resolute-security [arm64])
"""

SIM_GESCHUETZT = KOPF + """Remv ubuntu-minimal [1.539]
Purg eigenes-werkzeug [2.0]
Remv libfrei1 [1.0]
Inst sudo [1.9.17p2-1ubuntu3.1] (1.9.17p2-1ubuntu3.2 Ubuntu:26.04/resolute-security [arm64])
"""

SIM_GREETD = KOPF + """Inst greetd [0.10.3-5] (0.10.3-5ubuntu0.1 Ubuntu:26.04/resolute-updates [arm64])
"""

SIM_LEER = KOPF + "0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.\n"

STAND_VORHER = {"libssl3t64": "3.5.5-1ubuntu3.5", "sudo": "1.9.17p2-1ubuntu3.1", "openssl": "3.5.5-1ubuntu3.5",
                "libheif1": "1.21.2-3ubuntu0.5", "glycin-loaders": "2.1.1+ds-0ubuntu1", "example-tool": "1.0-1",
                "greetd": "0.10.3-5", "bash": "5.3-1"}
STAND_NACHHER = {**STAND_VORHER, "libssl3t64": "3.5.5-1ubuntu3.7", "sudo": "1.9.17p2-1ubuntu3.2",
                 "openssl": "3.5.5-1ubuntu3.7", "libheif1": "1.21.2-3ubuntu0.6", "glycin-loaders": "2.1.5+ds-0ubuntu0.2",
                 "example-tool": "1.1-1"}

# Attrappen. W ist der Temp-Ordner des Tests.
APT_GET = r'''
import json, os, shutil, subprocess, sys
args = sys.argv[1:]
def lies(name, vorgabe=""):
    try:
        with open(os.path.join(W, "apt", name), encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return vorgabe
with open(os.path.join(W, "apt", "aufrufe"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"args": args, "env": {k: os.environ.get(k) for k in
                        ("DEBIAN_FRONTEND", "NEEDRESTART_MODE", "NEEDRESTART_SUSPEND", "LC_ALL", "PATH")}}) + "\n")
if "update" in args:
    sys.exit(int(lies("update.exit", "0")))
if "-s" in args:
    gelaufen = os.path.exists(os.path.join(W, "apt", "gelaufen"))
    sys.stdout.write(lies("sim-nachher.txt") if gelaufen and lies("sim-nachher.txt") else lies("sim.txt"))
    sys.exit(int(lies("sim.exit", "0")))
if "full-upgrade" in args:
    optionen = [args[i + 1] for i, a in enumerate(args) if a == "-o"]
    vor = [o.split("::=", 1)[1] for o in optionen if o.startswith("DPkg::Pre-Invoke::=")]
    nach = [o.split("::=", 1)[1] for o in optionen if o.startswith("DPkg::Post-Invoke::=")]
    for befehl in vor:
        subprocess.run(["/bin/sh", "-c", befehl], check=True)
    ergebnis = {}
    if os.path.exists(POLICY):
        for fall in (["greetd.service", "restart"], ["--quiet", "greetd", "restart"], ["ssh.service", "restart"],
                     ["--quiet", "NetworkManager", "restart"]):
            ergebnis[" ".join(fall)] = subprocess.run([POLICY] + fall).returncode
    with open(os.path.join(W, "apt", "policy.json"), "w", encoding="utf-8") as f:
        json.dump(ergebnis, f)
    if os.path.exists(os.path.join(W, "apt", "nachher.txt")):
        shutil.copy(os.path.join(W, "apt", "nachher.txt"), os.path.join(W, "dpkg-zustand.txt"))
    if os.path.exists(os.path.join(W, "apt", "doctor-nachher")):
        shutil.copy(os.path.join(W, "apt", "doctor-nachher"), os.path.join(W, "doctor-fehler"))
    open(os.path.join(W, "apt", "gelaufen"), "w").close()
    for befehl in nach:
        subprocess.run(["/bin/sh", "-c", befehl], check=False)
    sys.exit(int(lies("full.exit", "0")))
sys.exit(99)
'''

APT_MARK = r'''
import os, sys
if sys.argv[1:] != ["showmanual"]:
    sys.exit(2)
try:
    with open(os.path.join(W, "apt", "manuell.txt"), encoding="utf-8") as f:
        sys.stdout.write(f.read())
except FileNotFoundError:
    pass
sys.exit(int(open(os.path.join(W, "apt", "mark.exit")).read()) if os.path.exists(os.path.join(W, "apt", "mark.exit")) else 0)
'''

DPKG_QUERY = r'''
import os, sys
with open(os.path.join(W, "dpkg-zustand.txt"), encoding="utf-8") as f:
    for zeile in f:
        teile = zeile.split()
        if len(teile) == 2:
            print(f"{teile[0]}\t{teile[1]}\tinstalled")
'''

DPKG = r'''
import json, os, subprocess, sys
if sys.argv[1:] == ["--print-architecture"]:
    print("arm64")
    sys.exit(0)
with open(os.path.join(W, "dpkg-aufrufe"), "a", encoding="utf-8") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[-2:] == ["--configure", "-a"]:
    # Was gilt beim Nachholen: die policy-rc.d (wie invoke-rc.d sie fragt) und ob apt schon lief
    ergebnis = {"vor_apt": not os.path.exists(os.path.join(W, "apt", "aufrufe")), "policy": None}
    if os.path.exists(POLICY):
        ergebnis["policy"] = {" ".join(fall): subprocess.run([POLICY] + fall).returncode
                              for fall in (["greetd.service", "restart"], ["ssh.service", "restart"])}
    with open(os.path.join(W, "dpkg-nachholen.json"), "w", encoding="utf-8") as f:
        json.dump(ergebnis, f)
    if not os.path.exists(os.path.join(W, "dpkg-bleibt-unterbrochen")):
        ordner = os.path.join(W, "var", "lib", "dpkg", "updates")
        for name in os.listdir(ordner):
            os.unlink(os.path.join(ordner, name))
'''

INSTALL = r'''
import json, os, sys
with open(os.path.join(W, "install-aufrufe"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"args": sys.argv[1:], "lauf": os.environ.get("ZENOS_KANAL_LAUF"),
                        "ergebnis": os.environ.get("ZENOS_KANAL_ERGEBNIS")}) + "\n")
ergebnis = os.environ.get("ZENOS_KANAL_ERGEBNIS")
if ergebnis:
    with open(ergebnis, "w", encoding="utf-8") as f:
        f.write("== Beginn 2026-10-07 12:00:00 · normal · zenOS-Installation\n")
        if not os.path.exists(os.path.join(W, "install-ohne-ende")):
            f.write("== Ende 2026-10-07 12:01:00 · normal · ok · 0 Änderungen · 0 Warnungen\n")
code = os.path.join(W, "install.exit")
sys.exit(int(open(code).read()) if os.path.exists(code) else 0)
'''

ZEN = r'''
import os, sys
if sys.argv[1:] != ["doctor", "--kurz"]:
    sys.exit(2)
datei = os.path.join(W, "doctor-fehler")
n = open(datei).read().strip() if os.path.exists(datei) else "0"
print(f"{n} Fehler · 1 Warnung · 2 Hinweise")
sys.exit(1 if n != "0" else 0)
'''


def schreiben(pfad, text, modus=0o644):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(pfad, modus)


def setUpModule():
    os.umask(0o022)


class Umgebung(unittest.TestCase):
    """Temp-Ordner mit allen Pfaden des Programms und den Attrappen."""

    def setUp(self):
        self.w = os.path.realpath(tempfile.mkdtemp(prefix="zenos-basis-updates."))
        os.chmod(self.w, 0o755)
        self.addCleanup(shutil.rmtree, self.w, True)
        self.addCleanup(self.zuruecksetzen)
        w = self.w
        pfade = {
            "PATH_CHECK_TOP": w, "TRUSTED_UIDS": (0, os.getuid()),
            "CODE_DIR": f"{w}/opt/zenos", "STATE_DIR": f"{w}/var/lib/zenos/basis",
            "CHANNEL_STATE_DIR": f"{w}/var/lib/zenos/kanal", "RUNTIME_DIR": f"{w}/run/zenos-basis",
            "LOCK_FILE": f"{w}/run/zenos-sperre/kanal.lock", "HAND_MARK": f"{w}/run/zenos-sperre/hand",
            "LOG_FILE": f"{w}/var/log/zenos/basis.log", "REBOOT_FILE": f"{w}/run/reboot-required",
            "REBOOT_PKGS": f"{w}/run/reboot-required.pkgs", "POLICY_FILE": f"{w}/usr/sbin/policy-rc.d",
            "DPKG_STATUS": f"{w}/var/lib/dpkg/status", "DPKG_UPDATES": f"{w}/var/lib/dpkg/updates",
            "APT_LOCKS": (f"{w}/var/lib/apt/lists/lock", f"{w}/var/cache/apt/archives/lock",
                          f"{w}/var/lib/dpkg/lock-frontend", f"{w}/var/lib/dpkg/lock"),
            "DPKG_LOCKS": (f"{w}/var/lib/dpkg/lock-frontend", f"{w}/var/lib/dpkg/lock"),
            "SYSTEMD_RUN_DIR": f"{w}/run/systemd/system", "PROC": f"{w}/proc", "BOOT_ID": f"{w}/boot_id",
            "APT_GET": f"{w}/bin/apt-get", "APT_MARK": f"{w}/bin/apt-mark", "DPKG": f"{w}/bin/dpkg",
            "DPKG_QUERY": f"{w}/bin/dpkg-query", "QUICKSHELL": f"{w}/usr/local/bin/quickshell",
            "LOGGER": f"{w}/bin/logger-fehlt", "APT_WAIT": 0, "APT_POLL": 0,
        }
        for name, wert in pfade.items():
            setattr(B, name, wert)
        B.now = lambda: JETZT
        for ordner in ("var/lib/zenos/kanal", "var/lib/dpkg/updates", "var/lib/apt/lists", "var/cache/apt/archives",
                       "usr/sbin", "run", "apt", "proc", "bin"):
            os.makedirs(os.path.join(w, ordner), exist_ok=True)
        # -S: ohne site-packages, die Attrappen starten so schneller
        kopf = f"#!{sys.executable} -S\nW = {w!r}\nPOLICY = {B.POLICY_FILE!r}\n"
        for pfad, text in ((B.APT_GET, APT_GET), (B.APT_MARK, APT_MARK), (B.DPKG_QUERY, DPKG_QUERY), (B.DPKG, DPKG),
                           (f"{B.CODE_DIR}/scripts/install.sh", INSTALL), (f"{B.CODE_DIR}/scripts/zen", ZEN)):
            schreiben(pfad, kopf + text, 0o755)
        schreiben(f"{B.CODE_DIR}/scripts/pakete/basis.txt", "# zenOS-Pakete\ngreetd labwc   # Login\nkitty\n")
        schreiben(f"{w}/apt/manuell.txt", "bash\neigenes-werkzeug\nlinux-raspi\n")
        self.paketstand(STAND_VORHER)
        schreiben(B.DPKG_STATUS, "")
        os.utime(B.DPKG_STATUS, (JETZT.timestamp() - 3600, JETZT.timestamp() - 3600))
        self.sim(SIM_OHNE_KERNEL)

    @staticmethod
    def zuruecksetzen():
        for name, wert in ORIGINAL.items():
            setattr(B, name, wert)
        B.now = ORIGINAL_NOW

    # --- Helfer ---

    def sim(self, text, nachher=None):
        schreiben(f"{self.w}/apt/sim.txt", text)
        if nachher is not None:
            schreiben(f"{self.w}/apt/sim-nachher.txt", nachher)

    def paketstand(self, stand, datei="dpkg-zustand.txt"):
        schreiben(f"{self.w}/{datei}" if datei == "dpkg-zustand.txt" else f"{self.w}/apt/{datei}",
                  "".join(f"{k} {v}\n" for k, v in sorted(stand.items())))

    def setze(self, name, text):
        schreiben(f"{self.w}/{name}", text)

    def apt_aufrufe(self):
        try:
            with open(f"{self.w}/apt/aufrufe", encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def install_aufrufe(self):
        try:
            with open(f"{self.w}/install-aufrufe", encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def json(self, name):
        with open(B.state_path(name), encoding="utf-8") as f:
            return json.load(f)

    def lauf(self, befehl, argv):
        """Befehl im Prozess, Ausgabe (auch der Kindprozesse) gesammelt: (Exit, Text)."""
        sys.stdout.flush()
        sys.stderr.flush()
        with tempfile.TemporaryFile() as f:
            gesichert = os.dup(1), os.dup(2)
            os.dup2(f.fileno(), 1)
            os.dup2(f.fileno(), 2)
            try:
                code = befehl(argv)
            finally:
                sys.stdout.flush()
                sys.stderr.flush()
                os.dup2(gesichert[0], 1)
                os.dup2(gesichert[1], 2)
                os.close(gesichert[0])
                os.close(gesichert[1])
            f.seek(0)
            return code, f.read().decode("utf-8", "replace")

    def pruefen(self):
        return self.lauf(B.cmd_check, [])

    def auftrag(self, liste=None, zustimmung=False, von="zen update"):
        os.makedirs(B.STATE_DIR, exist_ok=True)
        B.write_order(liste or self.json(B.STAND)["liste"], zustimmung, von)

    def installieren(self, argv=()):
        return self.lauf(B.cmd_install, list(argv))


class Auswertung(Umgebung):
    def auswerten(self, text, geschuetzt=()):
        return B.evaluate(text, set(geschuetzt) | set(B.PROTECTED), "2026-10-07T09:00:00Z")

    def test_ohne_kernel(self):
        s = self.auswerten(SIM_OHNE_KERNEL)
        self.assertEqual((s["ergebnis"], s["anzahl"], s["sicherheit"]), ("bereit", 6, 4))
        self.assertEqual((s["heikel"], s["entfernen"], s["geschuetzt"], s["neustart"]), ([], [], [], False))
        pakete = {p["name"]: p for p in s["pakete"]}
        self.assertEqual(pakete["sudo"]["tasche"], "resolute-security")
        self.assertEqual(pakete["libssl3t64"]["tasche"], "resolute-security", "Sicherheit geht vor -updates")
        self.assertEqual((pakete["glycin-loaders"]["tasche"], pakete["glycin-loaders"]["sicherheit"]),
                         ("resolute-updates", False))
        self.assertEqual((pakete["libheif1"]["alt"], pakete["libheif1"]["neu"]),
                         ("1.21.2-3ubuntu0.5", "1.21.2-3ubuntu0.6"))
        self.assertEqual((pakete["example-tool"]["herkunft"], pakete["example-tool"]["tasche"]),
                         ("Example Vendor LLC", "stable"))
        self.assertEqual(pakete["sudo"]["herkunft"], "Ubuntu")
        self.assertNotIn("openssh-server", pakete, "gestaffelte Updates (Phasing) bleiben draussen")
        self.assertRegex(s["liste"], r"^[0-9a-f]{40}$")
        self.assertIn("6 Updates (4 Sicherheit) bereit", s["grund"])
        zeilen = "\n".join(B.stand_lines(s))
        self.assertIn("Kernel, Firmware, Bootloader: nein", zeilen)
        self.assertIn("Auch aus Herstellerquellen: Example Vendor LLC", zeilen)

    def test_mit_kernel(self):
        s = self.auswerten(SIM_MIT_KERNEL)
        self.assertEqual(s["ergebnis"], "zustimmung")
        self.assertEqual(s["heikel"], ["flash-kernel", "linux-firmware-raspi", "linux-image-7.0.0-1012-raspi",
                                       "linux-modules-7.0.0-1012-raspi", "linux-raspi"])
        pakete = {p["name"]: p for p in s["pakete"]}
        self.assertFalse(pakete["linux-libc-dev"]["heikel"], "Header zum Kompilieren sind kein Kernel")
        self.assertIsNone(pakete["linux-image-7.0.0-1012-raspi"]["alt"], "neu installiert")
        self.assertEqual(pakete["libc6:armhf"]["arch"], "armhf")
        self.assertTrue(s["neustart"])
        self.assertIn("libc6", s["neustart_wegen"])
        self.assertIn("libc6:armhf", s["neustart_wegen"])
        self.assertNotIn("linux-libc-dev", s["neustart_wegen"])
        self.assertEqual(s["sicherheit"], 3)
        self.assertIn("Kernel, Firmware oder Bootloader", s["grund"])
        self.assertIn("(3 Sicherheit, Kernel/Firmware/Bootloader)", B.count_text(s))

    def test_entfernung_braucht_zustimmung(self):
        s = self.auswerten(SIM_ENTFERNUNG)
        self.assertEqual((s["ergebnis"], s["entfernen"], s["geschuetzt"]), ("zustimmung", ["libalt1"], []))
        self.assertIn("Entfernungen (libalt1)", s["grund"])
        self.assertEqual(B.count_text(s), "2 Updates (1 Sicherheit, 1 Entfernung)")

    def test_geschuetzt_sperrt(self):
        s = self.auswerten(SIM_GESCHUETZT, {"eigenes-werkzeug"})
        self.assertEqual(s["ergebnis"], "gesperrt")
        self.assertEqual(s["geschuetzt"], ["eigenes-werkzeug", "ubuntu-minimal"])
        self.assertEqual(s["entfernen"], ["eigenes-werkzeug", "libfrei1", "ubuntu-minimal"])
        self.assertIn("auch nicht mit Zustimmung", s["grund"])

    def test_greetd_heisst_neustart(self):
        s = self.auswerten(SIM_GREETD)
        self.assertEqual((s["ergebnis"], s["neustart_wegen"]), ("bereit", ["greetd"]))

    def test_aktuell(self):
        s = self.auswerten(SIM_LEER)
        self.assertEqual((s["ergebnis"], s["anzahl"], s["grund"]), ("aktuell", 0, "Die Ubuntu-Basis ist aktuell."))
        self.assertEqual(B.count_text(s), "keine Updates")
        self.assertEqual(s["liste"], B.list_hash([], []))

    def test_hash(self):
        a = self.auswerten(SIM_OHNE_KERNEL)["liste"]
        zeilen = SIM_OHNE_KERNEL.split("\n")
        umgestellt = "\n".join(zeilen[:9] + list(reversed(zeilen[9:])))
        self.assertEqual(self.auswerten(umgestellt)["liste"], a, "Reihenfolge zählt nicht")
        anders = SIM_OHNE_KERNEL.replace("1.9.17p2-1ubuntu3.2 Ubuntu", "1.9.17p2-1ubuntu3.3 Ubuntu", 1)
        self.assertNotEqual(self.auswerten(anders)["liste"], a, "eine andere Version ist eine andere Liste")
        mehr = SIM_OHNE_KERNEL + "Remv libalt1 [1.0-1]\n"
        self.assertNotEqual(self.auswerten(mehr)["liste"], a, "eine Entfernung ändert die Liste")

    def test_unverstaendliche_zeile(self):
        for zeile in ("Inst kaputt", "Inst sudo [1] (2 Ubuntu:26.04/resolute-security)", "Remv KAPUTT [1]"):
            with self.subTest(zeile=zeile), self.assertRaises(B.Failure):
                B.parse_simulation(KOPF + zeile + "\n")

    def test_heikel(self):
        ja = ("linux-raspi", "linux-image-7.0.0-1012-raspi", "linux-modules-extra-7.0.0-1012-raspi",
              "linux-headers-7.0.0-1012-raspi", "linux-firmware", "linux-firmware-raspi", "flash-kernel", "piboot-try",
              "rpi-eeprom", "u-boot-rpi", "grub-efi-arm64", "shim-signed", "linux-generic", "linux-image-generic",
              "linux-raspi:arm64")
        nein = ("linux-libc-dev", "linux-headers-7.0.0-1012", "libc6", "firmware-sof-signed", "raspi-config", "sudo")
        for name in ja:
            self.assertTrue(B.is_heikel(name), name)
        for name in nein:
            self.assertFalse(B.is_heikel(name), name)

    def test_zenos_pakete(self):
        self.assertEqual(B.zenos_packages(), {"greetd", "labwc", "kitty"})
        schutz = B.protected_packages()
        self.assertTrue({"greetd", "bash", "eigenes-werkzeug", "ubuntu-minimal"} <= schutz)
        self.setze("apt/mark.exit", "1")
        with self.assertRaises(B.Failure):
            B.protected_packages()

    @unittest.skipUnless(BASH, "bash fehlt")
    def test_schutzliste_wie_aufraeumen(self):
        r = subprocess.run([BASH, "-c", 'source "$1"; _aufraeumen_geschuetzt', "-", AUFRAEUMEN], capture_output=True,
                           text=True, check=True, env={"PATH": "/usr/bin:/bin"})
        self.assertEqual(sorted(r.stdout.split()), sorted(B.PROTECTED))

    def test_markierungen_wie_gemeinsam(self):
        with open(GEMEINSAM, encoding="utf-8") as f:
            text = f.read()
        self.assertIn(f"_ZENOS_POLICY_MARKE='{B.INSTALL_POLICY_MARK}'\n", text)
        self.assertIn(f"_ZENOS_POLICY_MARKE_BASIS='{B.POLICY_MARK}'\n", text)

    def test_policy_haelt_nur_greetd_ab(self):
        pfad = f"{self.w}/policy-rc.d"
        schreiben(pfad, B.POLICY_TEXT, 0o755)
        for argumente, erwartet in ((["greetd.service", "restart"], 101), (["--quiet", "greetd", "restart"], 101),
                                    (["greetd", "stop"], 101), (["ssh.service", "restart"], 0),
                                    (["--quiet", "NetworkManager", "try-restart"], 0), ([], 0)):
            with self.subTest(argumente=argumente):
                self.assertEqual(subprocess.run([pfad] + argumente, check=False).returncode, erwartet)
        with open(pfad, encoding="utf-8") as f:
            self.assertEqual(f.read().split("\n")[1], B.POLICY_MARK)


class Pruefen(Umgebung):
    def test_ablauf(self):
        code, aus = self.pruefen()
        self.assertEqual(code, 0, aus)
        s = self.json(B.STAND)
        self.assertEqual((s["ergebnis"], s["anzahl"], s["geprueft"], s["fehler"]),
                         ("bereit", 6, "2026-10-07T10:00:00Z", None))
        aufrufe = [a["args"] for a in self.apt_aufrufe()]
        self.assertEqual(aufrufe, [["-q", "update"], ["-s", "-o", "APT::Get::AutomaticRemove=false", "full-upgrade"]])
        self.assertEqual(self.apt_aufrufe()[1]["env"]["LC_ALL"], "C", "ausgewertet wird ohne Übersetzung")
        self.assertEqual(self.apt_aufrufe()[0]["env"]["DEBIAN_FRONTEND"], "noninteractive")
        self.assertIn("Ubuntu-Basis: 6 Updates (4 Sicherheit) bereit.", aus)
        self.assertEqual(os.stat(B.state_path(B.STAND)).st_mode & 0o777, 0o644)
        self.assertEqual(os.stat(B.STATE_DIR).st_mode & 0o777, 0o755)
        self.assertFalse(os.path.exists(f"{self.w}/apt/gelaufen"), "prüfen installiert nichts")

    def test_update_scheitert(self):
        self.pruefen()
        self.setze("apt/update.exit", "100")
        B.now = lambda: JETZT + datetime.timedelta(hours=3)
        code, aus = self.pruefen()
        self.assertEqual(code, 1, aus)
        s = self.json(B.STAND)
        self.assertEqual(s["ergebnis"], "fehler")
        self.assertIn("apt-get update endete mit Exit 100", s["fehler"])
        self.assertEqual(s["geprueft"], "2026-10-07T10:00:00Z", "die letzte gelungene Prüfung bleibt stehen")

    def test_auswertung_scheitert(self):
        self.setze("apt/sim.exit", "100")
        code, _ = self.pruefen()
        self.assertEqual(code, 1)
        s = self.json(B.STAND)
        self.assertEqual((s["ergebnis"], s["liste"]), ("fehler", None))

    def test_gesperrt(self):
        self.sim(SIM_GESCHUETZT)
        code, aus = self.pruefen()
        self.assertEqual(code, 3, aus)
        self.assertEqual(self.json(B.STAND)["geschuetzt"], ["eigenes-werkzeug", "ubuntu-minimal"])

    def test_sperre_belegt(self):
        os.makedirs(os.path.dirname(B.LOCK_FILE), mode=0o700, exist_ok=True)
        with open(B.LOCK_FILE, "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            code, aus = self.pruefen()
        self.assertEqual(code, 75)
        self.assertIn("läuft gerade", aus)
        self.assertEqual(self.apt_aufrufe(), [])

    def test_install_von_hand(self):
        os.makedirs(os.path.dirname(B.HAND_MARK), mode=0o700, exist_ok=True)
        schreiben(B.HAND_MARK, "4242\n")
        schreiben(f"{B.PROC}/4242/cmdline", "bash\0/home/x/zenOS/scripts/install.sh\0")
        code, aus = self.pruefen()
        self.assertEqual(code, 75)
        self.assertIn("PID 4242", aus)
        os.unlink(f"{B.PROC}/4242/cmdline")
        self.assertEqual(self.pruefen()[0], 0, "ein Vermerk ohne laufenden Prozess hält nichts auf")

    def test_wartet_auf_anderen_paketvorgang(self):
        belegt = [["apt-daily-upgrade.service"], ["/var/lib/dpkg/lock-frontend"], []]
        with mock.patch.object(B, "apt_busy", lambda: belegt.pop(0)), \
                mock.patch.object(B.time, "sleep", lambda s: None), \
                mock.patch.object(B, "APT_WAIT", 1200):
            code, aus = self.pruefen()
        self.assertEqual(code, 0, aus)
        self.assertIn("Warte auf einen anderen Paketvorgang: apt-daily-upgrade.service", aus)
        self.assertIn("Der andere Paketvorgang ist fertig", aus)
        # Bleibt er belegt: nach der Frist Exit 75, ohne apt
        with mock.patch.object(B, "apt_busy", lambda: ["/var/lib/dpkg/lock"]):
            code, aus = self.pruefen()
        self.assertEqual(code, 75)
        self.assertIn("läuft noch immer ein anderer Paketvorgang", aus)

    def nachholen(self):
        with open(f"{self.w}/dpkg-nachholen.json", encoding="utf-8") as f:
            return json.load(f)

    def test_dpkg_unterbrochen_wird_zuerst_nachgeholt(self):
        """Nach einem Abbruch mitten in dpkg sähe apt-get -s den halb konfigurierten Stand als «aktuell»: Die Prüfung
        holt «dpkg --configure -a» vor apt-get update nach, mit der policy-rc.d der Basis (greetd nicht neu)."""
        schreiben(f"{B.DPKG_UPDATES}/0000", "")
        code, aus = self.pruefen()
        self.assertEqual(code, 0, aus)
        with open(f"{self.w}/dpkg-aufrufe", encoding="utf-8") as f:
            self.assertEqual(f.read(), "--force-confdef --force-confold --configure -a\n")
        self.assertEqual(self.nachholen(), {"vor_apt": True, "policy": {"greetd.service restart": 101,
                                                                         "ssh.service restart": 0}})
        self.assertIn("dpkg wurde unterbrochen: dpkg --configure -a", aus)
        self.assertEqual(os.listdir(B.DPKG_UPDATES), [])
        self.assertFalse(os.path.lexists(B.POLICY_FILE), "die policy-rc.d ist danach weg")
        self.assertEqual([a["args"][-1] for a in self.apt_aufrufe()], ["update", "full-upgrade"])
        self.assertEqual(self.json(B.STAND)["ergebnis"], "bereit")

    def test_rest_einer_policy_und_fremde_policy(self):
        """Der Rest des abgebrochenen Laufs (policy-rc.d der Basis oder von install.sh) wird beim Nachholen ersetzt und
        danach entfernt; eine fremde bleibt und gilt."""
        for rest in (B.POLICY_TEXT, f"#!/bin/sh\n{B.INSTALL_POLICY_MARK}\nexit 101\n"):
            with self.subTest(rest=rest.split("\n")[1]):
                schreiben(B.POLICY_FILE, rest, 0o755)
                schreiben(f"{B.DPKG_UPDATES}/0000", "")
                self.assertEqual(self.pruefen()[0], 0)
                self.assertEqual(self.nachholen()["policy"]["ssh.service restart"], 0, "die eigene galt")
                self.assertFalse(os.path.lexists(B.POLICY_FILE))
        fremd = "#!/bin/sh\n# fremd\nexit 101\n"
        schreiben(B.POLICY_FILE, fremd, 0o755)
        schreiben(f"{B.DPKG_UPDATES}/0000", "")
        self.assertEqual(self.pruefen()[0], 0)
        self.assertEqual(self.nachholen()["policy"], {"greetd.service restart": 101, "ssh.service restart": 101})
        with open(B.POLICY_FILE, encoding="utf-8") as f:
            self.assertEqual(f.read(), fremd, "eine fremde policy-rc.d bleibt")

    def test_dpkg_bleibt_unterbrochen(self):
        self.pruefen()
        schreiben(f"{B.DPKG_UPDATES}/0000", "")
        self.setze("dpkg-bleibt-unterbrochen", "")
        os.unlink(f"{self.w}/apt/aufrufe")
        B.now = lambda: JETZT + datetime.timedelta(hours=3)
        code, aus = self.pruefen()
        self.assertEqual(code, 1, aus)
        s = self.json(B.STAND)
        self.assertEqual((s["ergebnis"], s["liste"], s["geprueft"]), ("fehler", None, "2026-10-07T10:00:00Z"))
        self.assertIn("dpkg ist unterbrochen", s["grund"])
        self.assertIn("sudo dpkg --configure -a", aus)
        self.assertEqual(self.apt_aufrufe(), [], "ohne apt-get update und Auswertung")

    def test_sperre_von_apt_erkannt(self):
        sperre = B.APT_LOCKS[2]
        schreiben(sperre, "")
        self.assertFalse(B.lock_held(sperre))
        halter = subprocess.Popen([sys.executable, "-c", "import fcntl, sys\nf = open(sys.argv[1], 'r+')\n"
                                   "fcntl.lockf(f, fcntl.LOCK_EX)\nprint('ja', flush=True)\nsys.stdin.read()", sperre],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(halter.stdout.readline().strip(), "ja")
            self.assertTrue(B.lock_held(sperre))
            self.assertEqual(B.apt_busy(), [sperre])
        finally:
            halter.stdin.close()
            halter.wait(10)
            halter.stdout.close()
        self.assertFalse(B.lock_held(sperre))

    @unittest.skipIf(os.geteuid() == 0, "als root erlaubt")
    def test_nur_root(self):
        B.TRUSTED_UIDS = (0,)
        self.assertEqual(self.pruefen()[0], 2)
        self.assertEqual(self.installieren()[0], 2)


class Installieren(Umgebung):
    def bereit(self, sim=SIM_OHNE_KERNEL, nachher=STAND_NACHHER, sim_nachher=SIM_LEER):
        self.sim(sim, sim_nachher)
        self.paketstand(nachher, "nachher.txt")
        code, aus = self.pruefen()
        self.assertIn(code, (0, 3), aus)
        os.unlink(f"{self.w}/apt/aufrufe")

    def full_upgrade_aufrufe(self):
        return [a for a in self.apt_aufrufe() if "full-upgrade" in a["args"] and "-s" not in a["args"]]

    def test_ablauf(self):
        self.bereit()
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        aufruf = self.full_upgrade_aufrufe()
        self.assertEqual(len(aufruf), 1)
        args = aufruf[0]["args"]
        for teil in ("-y", "Dpkg::Options::=--force-confdef", "Dpkg::Options::=--force-confold",
                     "APT::Get::AutomaticRemove=false", "DPkg::Lock::Timeout=300"):
            self.assertIn(teil, args)
        self.assertNotIn("autoremove", args)
        self.assertEqual(args[-1], "full-upgrade")
        self.assertEqual({k: aufruf[0]["env"][k] for k in ("DEBIAN_FRONTEND", "NEEDRESTART_MODE",
                                                           "NEEDRESTART_SUSPEND")},
                         {"DEBIAN_FRONTEND": "noninteractive", "NEEDRESTART_MODE": "l", "NEEDRESTART_SUSPEND": "1"})
        # Vor dem Installieren neu ausgewertet, ohne neues apt-get update
        self.assertNotIn(["-q", "update"], [a["args"] for a in self.apt_aufrufe()])
        # policy-rc.d während dpkg: nur greetd verboten, danach wieder weg
        with open(f"{self.w}/apt/policy.json", encoding="utf-8") as f:
            self.assertEqual(json.load(f), {"greetd.service restart": 101, "--quiet greetd restart": 101,
                                            "ssh.service restart": 0, "--quiet NetworkManager restart": 0})
        self.assertFalse(os.path.lexists(B.POLICY_FILE))
        # install.sh aus /opt/zenos, als Lauf des Kanals mit eigenem Ergebnis
        self.assertEqual(self.install_aufrufe(), [{"args": ["--ruhig"], "lauf": "1",
                                                   "ergebnis": B.state_path("install-ergebnis")}])
        letzte = self.json(B.LAST)
        self.assertEqual((letzte["ergebnis"], letzte["anzahl"], letzte["geaendert"], letzte["von"]),
                         ("installiert", 6, 6, "zen update"))
        self.assertEqual((letzte["probleme"], letzte["mehr"], letzte["neustart"]), ([], [], False))
        self.assertIn("6 Pakete aktualisiert, gesund.", letzte["grund"])
        # Danach neu ausgewertet (ohne Netz): nichts mehr offen
        self.assertEqual(self.json(B.STAND)["ergebnis"], "aktuell")
        self.assertFalse(os.path.exists(B.state_path(B.ORDER)), "der Auftrag ist verbraucht")
        self.assertFalse(os.path.exists(B.RUNTIME_DIR), "ohne Unit: Laufzeitordner wieder weg")
        with open(B.LOG_FILE, encoding="utf-8") as f:
            log = f.read()
        self.assertIn("· 6 Updates (4 Sicherheit) · von zen update", log)
        self.assertIn("-- Paketstand vorher (dpkg-query, 8 Pakete)\nbash 5.3-1\n", log)
        self.assertIn("sudo 1.9.17p2-1ubuntu3.1 → 1.9.17p2-1ubuntu3.2", log)
        self.assertIn("-- install.sh: Exit 0", log)
        self.assertRegex(log, r"== Ende .* · installiert\n$")
        self.assertEqual(os.stat(B.LOG_FILE).st_mode & 0o777, 0o640)
        self.assertIn("Ergebnis: installiert", aus)

    def test_von_hand_mit_liste(self):
        self.bereit()
        liste = self.json(B.STAND)["liste"]
        self.assertEqual(self.installieren(["--liste", "0" * 40])[0], 3, "nicht die Liste der Prüfung")
        code, aus = self.installieren(["--liste", liste])
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.json(B.LAST)["von"], "hand")
        for falsch in (["--liste"], ["--liste", "xyz"], ["--zustimmung"], ["--liste", liste, "--ja"]):
            self.assertEqual(self.installieren(falsch)[0], 2, falsch)

    def test_liste_hat_sich_geaendert(self):
        self.bereit()
        alt = self.json(B.STAND)["liste"]
        self.auftrag()
        self.sim(SIM_OHNE_KERNEL.replace("1.9.17p2-1ubuntu3.2 Ubuntu", "1.9.17p2-1ubuntu3.3 Ubuntu", 1))
        code, aus = self.installieren()
        self.assertEqual(code, 3, aus)
        self.assertIn("Seit der Prüfung hat sich die Liste geändert", aus)
        self.assertEqual(self.full_upgrade_aufrufe(), [])
        self.assertNotEqual(self.json(B.STAND)["liste"], alt, "stand.json zeigt die neue Liste")
        self.assertFalse(os.path.exists(B.state_path(B.LAST)), "eine Ablehnung schreibt keine letzte.json")

    def test_ohne_auftrag(self):
        self.bereit()
        code, aus = self.installieren()
        self.assertEqual(code, 3)
        self.assertIn("Kein Auftrag", aus)

    def test_auftrag_zu_alt_oder_kaputt(self):
        self.bereit()
        self.auftrag()
        B.now = lambda: JETZT + datetime.timedelta(minutes=61)
        code, aus = self.installieren()
        self.assertEqual(code, 3)
        self.assertIn("älter als eine Stunde", aus)
        B.now = lambda: JETZT
        schreiben(B.state_path(B.ORDER), json.dumps({"liste": "a" * 40, "zustimmung": "ja", "von": "zen update",
                                                     "zeit": "2026-10-07T10:00:00Z"}))
        self.assertEqual(self.installieren()[0], 3)
        self.assertFalse(os.path.exists(B.state_path(B.ORDER)))
        with self.assertRaises(B.Failure):
            B.write_order("a" * 40, False, "irgendwer")

    def test_heikel_nur_mit_zustimmung(self):
        # dpkg-query nennt Multi-Arch-Pakete mit Architektur («libc6:arm64»), apt die eigene nicht
        vorher = {"linux-raspi": "7.0.0-1010.10", "linux-firmware-raspi": "9-0ubuntu1", "flash-kernel": "3.110ubuntu2",
                  "libc6:arm64": "2.42-0ubuntu3", "libc6:armhf": "2.42-0ubuntu3", "linux-libc-dev": "7.0.0-34.34"}
        self.paketstand(vorher)
        nachher = {**vorher, "linux-raspi": "7.0.0-1012.12", "linux-image-7.0.0-1012-raspi": "7.0.0-1012.12",
                   "linux-modules-7.0.0-1012-raspi": "7.0.0-1012.12", "linux-firmware-raspi": "9-0ubuntu1.1",
                   "flash-kernel": "3.110ubuntu2.1", "libc6:arm64": "2.42-0ubuntu3.1", "libc6:armhf": "2.42-0ubuntu3.1",
                   "linux-libc-dev": "7.0.0-38.38"}
        self.bereit(SIM_MIT_KERNEL, nachher)
        self.assertEqual(self.json(B.STAND)["ergebnis"], "zustimmung")
        self.auftrag(zustimmung=False, von="automatik")
        code, aus = self.installieren()
        self.assertEqual(code, 10, aus)
        self.assertIn("braucht eine Zustimmung", aus)
        self.assertEqual(self.full_upgrade_aufrufe(), [])
        self.assertFalse(os.path.exists(B.state_path(B.LAST)))
        self.auftrag(zustimmung=True, von="einstellungen")
        schreiben(B.REBOOT_FILE, "*** System restart required ***\n")
        schreiben(B.REBOOT_PKGS, "linux-image-7.0.0-1012-raspi\n")
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        letzte = self.json(B.LAST)
        self.assertEqual((letzte["zustimmung"], letzte["neustart"], letzte["neustart_wegen"]),
                         (True, True, ["linux-image-7.0.0-1012-raspi"]))
        self.assertEqual((letzte["geaendert"], letzte["mehr"]), (8, []), "libc6:arm64 ist libc6")
        self.assertIn("Neustart nötig", letzte["grund"])
        self.assertEqual(letzte["heikel"], ["flash-kernel", "linux-firmware-raspi", "linux-image-7.0.0-1012-raspi",
                                            "linux-modules-7.0.0-1012-raspi", "linux-raspi"])

    def test_entfernung_nur_mit_zustimmung(self):
        self.paketstand({"libalt1": "1.0-1", "sudo": "1.9.17p2-1ubuntu3.1"})
        self.bereit(SIM_ENTFERNUNG, {"libalt1t64": "1.0-1.1", "sudo": "1.9.17p2-1ubuntu3.2"})
        self.auftrag()
        self.assertEqual(self.installieren()[0], 10)
        self.auftrag(zustimmung=True)
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        letzte = self.json(B.LAST)
        self.assertEqual((letzte["entfernt"], letzte["mehr"]), (["libalt1"], []))
        with open(B.LOG_FILE, encoding="utf-8") as f:
            self.assertIn("libalt1 1.0-1 → (entfernt)", f.read())

    def test_geschuetzt_nie(self):
        self.bereit(SIM_GESCHUETZT)
        self.auftrag(zustimmung=True)
        code, aus = self.installieren()
        self.assertEqual(code, 3, aus)
        self.assertIn("geschützte Pakete", aus)
        self.assertEqual(self.full_upgrade_aufrufe(), [])

    def test_nichts_zu_tun(self):
        self.bereit(SIM_LEER, STAND_VORHER)
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        self.assertIn("Nichts zu installieren", aus)
        self.assertEqual(self.full_upgrade_aufrufe(), [])
        self.assertFalse(os.path.exists(B.state_path(B.LAST)))

    def test_kanal_unterbrochen_oder_kaputt(self):
        self.bereit()
        schreiben(f"{B.CHANNEL_STATE_DIR}/laeuft.json", "{}")
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 10)
        self.assertIn("Kanals ist unterbrochen", aus)
        os.unlink(f"{B.CHANNEL_STATE_DIR}/laeuft.json")
        schreiben(f"{B.CHANNEL_STATE_DIR}/letzte.json", json.dumps({"ergebnis": "kaputt"}))
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 10)
        self.assertIn("meldet «kaputt»", aus)
        self.assertEqual(self.full_upgrade_aufrufe(), [])

    def test_apt_scheitert(self):
        self.bereit()
        self.setze("apt/full.exit", "100")
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 1, aus)
        letzte = self.json(B.LAST)
        self.assertEqual(letzte["ergebnis"], "fehler")
        self.assertIn("apt-get full-upgrade endete mit Exit 100; nichts zurückgerollt", letzte["grund"])
        self.assertEqual(self.install_aufrufe(), [], "ohne gelungenes apt kein install.sh")
        self.assertFalse(os.path.lexists(B.POLICY_FILE), "die policy-rc.d ist auch nach einem Fehler weg")

    def test_install_sh_scheitert(self):
        self.bereit()
        self.setze("install.exit", "1")
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 5, aus)
        letzte = self.json(B.LAST)
        self.assertEqual(letzte["ergebnis"], "kaputt")
        self.assertIn("install.sh endete mit Exit 1", letzte["probleme"])
        self.assertIn("Nichts zurückgerollt", letzte["grund"])

    def test_install_sh_ohne_ende(self):
        self.bereit()
        self.setze("install-ohne-ende", "")
        self.auftrag()
        self.assertEqual(self.installieren()[0], 5)
        self.assertIn("im Ergebnis von install.sh fehlt «== Ende … ok»", self.json(B.LAST)["probleme"])

    def test_doctor_nur_schlechter_zaehlt(self):
        self.setze("doctor-fehler", "2")
        self.bereit()
        self.auftrag()
        self.assertEqual(self.installieren()[0], 0, "zwei Fehler schon vorher: kein Problem des Updates")
        # Ein zweites Update, nach dem zen doctor einen Fehler mehr meldet
        os.unlink(f"{self.w}/apt/gelaufen")
        self.paketstand(STAND_VORHER)
        self.setze("apt/doctor-nachher", "3")
        self.bereit()
        self.auftrag()
        self.assertEqual(self.installieren()[0], 5)
        self.assertIn("zen doctor meldet 3 Fehler statt 2 (sudo zen doctor)", self.json(B.LAST)["probleme"])

    def test_quickshell_nur_schlechter_zaehlt(self):
        self.bereit()
        schreiben(B.QUICKSHELL, "#!/bin/sh\nexit 1\n", 0o755)
        self.auftrag()
        self.assertEqual(self.installieren()[0], 0, "schon vorher kaputt")
        baseline = {"quickshell_exit": 0, "greetd_ausgefallen": None, "ausgefallen": None, "doctor_fehler": None}
        self.assertEqual(B.health_problems(baseline, None), ["quickshell --version endet mit Exit 1"])

    def test_neu_ausgefallene_units(self):
        with mock.patch.object(B, "failed_units", lambda: ["a.service", "b.service"]):
            baseline = {"ausgefallen": ["a.service"]}
            self.assertEqual(B.health_problems(baseline, None), ["neu ausgefallen: b.service (systemctl --failed)"])
            self.assertEqual(B.health_problems({"ausgefallen": ["a.service", "b.service"]}, None), [])

    def test_greetd_neu_heisst_neustart(self):
        self.bereit(SIM_GREETD, {**STAND_VORHER, "greetd": "0.10.3-5ubuntu0.1"})
        schreiben(B.REBOOT_PKGS, "libc6\n")
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        with open(B.REBOOT_FILE, encoding="utf-8") as f:
            self.assertEqual(f.read(), "*** System restart required ***\n")
        with open(B.REBOOT_PKGS, encoding="utf-8") as f:
            self.assertEqual(f.read(), "libc6\ngreetd\n")
        letzte = self.json(B.LAST)
        self.assertEqual((letzte["neustart"], letzte["neustart_wegen"]), (True, ["greetd", "libc6"]))
        self.assertTrue(any("greetd" in h for h in letzte["hinweise"]))
        B.mark_reboot("greetd")
        with open(B.REBOOT_PKGS, encoding="utf-8") as f:
            self.assertEqual(f.read(), "libc6\ngreetd\n", "nur einmal eingetragen")

    def test_mehr_als_die_liste(self):
        self.bereit(nachher={**STAND_NACHHER, "neues-paket": "1.0"})
        self.auftrag()
        self.assertEqual(self.installieren()[0], 0)
        letzte = self.json(B.LAST)
        self.assertEqual(letzte["mehr"], ["neues-paket"])
        self.assertTrue(any("mehr als die angezeigte Liste" in h for h in letzte["hinweise"]))

    def test_dpkg_unterbrochen(self):
        self.bereit()
        schreiben(f"{B.DPKG_UPDATES}/0001", "")
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        with open(f"{self.w}/dpkg-aufrufe", encoding="utf-8") as f:
            self.assertEqual(f.read(), "--force-confdef --force-confold --configure -a\n")
        # Bleibt dpkg unterbrochen: kein apt, keine letzte.json
        os.unlink(f"{self.w}/apt/gelaufen")
        os.unlink(B.state_path(B.LAST))
        self.paketstand(STAND_VORHER)
        self.bereit()
        schreiben(f"{B.DPKG_UPDATES}/0002", "")
        self.setze("dpkg-bleibt-unterbrochen", "")
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 1)
        self.assertIn("sudo dpkg --configure -a", aus)
        self.assertEqual(self.full_upgrade_aufrufe(), [])
        self.assertFalse(os.path.exists(B.state_path(B.LAST)))

    def test_stopp_vor_apt(self):
        self.bereit()
        run_ = B.Installation({"liste": self.json(B.STAND)["liste"], "zustimmung": False, "von": "hand"})
        run_.stop_requested = True
        code, _ = self.lauf(lambda _: run_.run(), [])
        self.assertEqual(code, 10)
        self.assertEqual(self.full_upgrade_aufrufe(), [])
        self.assertFalse(run_.attempted)

    def test_fremde_und_alte_policy(self):
        self.bereit()
        schreiben(B.POLICY_FILE, "#!/bin/sh\n# fremd\nexit 0\n", 0o755)
        self.auftrag()
        code, aus = self.installieren()
        self.assertEqual(code, 0, aus)
        with open(B.POLICY_FILE, encoding="utf-8") as f:
            self.assertEqual(f.read(), "#!/bin/sh\n# fremd\nexit 0\n", "eine fremde policy-rc.d bleibt")
        self.assertTrue(any("gehört nicht zenOS" in h for h in self.json(B.LAST)["hinweise"]))
        for rest in (B.POLICY_TEXT, f"#!/bin/sh\n{B.INSTALL_POLICY_MARK}\nexit 101\n"):
            with self.subTest(rest=rest.split("\n")[1]):
                os.unlink(f"{self.w}/apt/gelaufen")
                self.paketstand(STAND_VORHER)
                self.bereit()
                schreiben(B.POLICY_FILE, rest, 0o755)
                self.auftrag()
                self.assertEqual(self.installieren()[0], 0)
                with open(f"{self.w}/apt/policy.json", encoding="utf-8") as f:
                    self.assertEqual(json.load(f)["ssh.service restart"], 0, "der Rest galt nicht mehr")
                self.assertFalse(os.path.lexists(B.POLICY_FILE))

    def test_sperre_belegt(self):
        self.bereit()
        self.auftrag()
        with open(B.LOCK_FILE, "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            self.assertEqual(self.installieren()[0], 75)
        self.assertTrue(os.path.exists(B.state_path(B.ORDER)), "der Auftrag bleibt für den nächsten Versuch")

    def test_unter_der_unit(self):
        """Mit RuntimeDirectory (Unit) bleibt der Ordner; der Marker der Übernahme besteht nur während apt und
        install.sh."""
        self.bereit()
        os.makedirs(B.RUNTIME_DIR)
        marker = os.path.join(B.RUNTIME_DIR, "uebernahme")
        gesehen = []
        echt = B.run_visible

        def beobachten(argv, env, timeout=None, cwd="/"):
            gesehen.append(os.path.exists(marker))
            return echt(argv, env, timeout, cwd)

        self.auftrag()
        with mock.patch.object(B, "run_visible", beobachten):
            self.assertEqual(self.installieren()[0], 0)
        self.assertEqual(gesehen, [True, True], "apt und install.sh mit Marker")
        self.assertTrue(os.path.isdir(B.RUNTIME_DIR))
        self.assertFalse(os.path.exists(marker))
        self.assertEqual(os.listdir(B.RUNTIME_DIR), [], "auch der Ordner der policy-rc.d ist weg")


class Status(Umgebung):
    def kurz(self):
        return self.lauf(B.cmd_status, ["--kurz"])[1].strip()

    def test_zustaende(self):
        self.assertEqual(self.kurz(), "ungeprueft noch nie geprüft")
        self.pruefen()
        self.assertEqual(self.kurz(), "bereit 6 Updates (4 Sicherheit)")
        self.sim(SIM_MIT_KERNEL)
        self.pruefen()
        self.assertEqual(self.kurz(), "zustimmung 8 Updates (3 Sicherheit, Kernel/Firmware/Bootloader)")
        self.sim(SIM_GESCHUETZT)
        self.pruefen()
        self.assertEqual(self.kurz(), "gesperrt 1 Update (1 Sicherheit, 3 Entfernungen), gesperrt: "
                                      "eigenes-werkzeug, ubuntu-minimal ginge weg")
        self.sim(SIM_LEER)
        self.pruefen()
        self.assertEqual(self.kurz(), "aktuell aktuell")
        self.setze("apt/update.exit", "100")
        self.pruefen()
        self.assertTrue(self.kurz().startswith("fehler Prüfung gescheitert: apt-get update endete mit Exit 100"))
        os.makedirs(B.RUNTIME_DIR)
        schreiben(os.path.join(B.RUNTIME_DIR, "uebernahme"), "x\n")
        self.assertEqual(self.kurz(), "laeuft Basis-Update läuft")

    def test_veraltet(self):
        self.pruefen()
        zeit = JETZT.timestamp()
        os.utime(B.DPKG_STATUS, (zeit + 60, zeit + 60))
        self.assertTrue(self.kurz().startswith("veraltet 6 Updates (4 Sicherheit) (Stand "))
        self.assertTrue(self.kurz().endswith(", seither Paketänderungen)"))
        os.utime(B.DPKG_STATUS, (zeit - 60, zeit - 60))
        self.assertEqual(self.kurz(), "bereit 6 Updates (4 Sicherheit)")

    def test_installation_und_json(self):
        self.assertEqual(self.lauf(B.cmd_status, ["--installation"])[1].strip(),
                         "keine noch kein Basis-Update über zenOS")
        self.pruefen()
        self.paketstand(STAND_NACHHER, "nachher.txt")
        self.sim(SIM_OHNE_KERNEL, SIM_LEER)
        self.auftrag()
        self.assertEqual(self.installieren()[0], 0)
        zeile = self.lauf(B.cmd_status, ["--installation"])[1].strip()
        self.assertRegex(zeile, r"^installiert [0-9-]{10} [0-9:]{5}: 6 Pakete aktualisiert, gesund\.$")
        schreiben(B.REBOOT_FILE, "*** System restart required ***\n")
        schreiben(B.REBOOT_PKGS, "linux-image-x\nlibc6\nlibc6\n")
        daten = json.loads(self.lauf(B.cmd_status, ["--json"])[1])
        self.assertEqual((daten["zustand"], daten["laeuft"]), ("aktuell", False))
        self.assertEqual(daten["neustart"], {"noetig": True, "pakete": ["libc6", "linux-image-x"]})
        self.assertEqual(daten["letzte"]["ergebnis"], "installiert")
        text = self.lauf(B.cmd_status, [])[1]
        self.assertIn("Neustart     nötig (libc6, linux-image-x)", text)
        self.assertIn("Installation installiert ", text)
        self.assertEqual(self.lauf(B.cmd_status, ["--falsch"])[0], 2)

    def test_ohne_rechte_lesbar(self):
        """status braucht kein root; stand.json und letzte.json sind für alle lesbar."""
        self.pruefen()
        for name in (B.STAND,):
            self.assertEqual(os.stat(B.state_path(name)).st_mode & 0o004, 0o004)
        B.TRUSTED_UIDS = (0, os.getuid())
        self.assertEqual(self.lauf(B.cmd_status, ["--kurz"])[0], 0)


@unittest.skipUnless(BASH, "bash fehlt")
class ZenVersion(unittest.TestCase):
    """Die Zeile «Pakete» von zen version: Spaltenbreite 12, Text aus «zenos-basis status --kurz», dazu der Neustart."""

    def zeile(self, kurz, neustart):
        with tempfile.TemporaryDirectory() as w:
            programm = os.path.join(w, "zenos-basis")
            schreiben(programm, "")
            python = os.path.join(w, "python3")
            schreiben(python, f"#!/bin/sh\nprintf '%s\\n' {kurz!r}\n", 0o755)
            neustart_datei = os.path.join(w, "reboot-required")
            if neustart:
                schreiben(neustart_datei, "*** System restart required ***\n")
            rahmen = (f'source "$1"; _VERSION_BASIS={programm!r}; _VERSION_PYTHON={python!r}; '
                      f'_VERSION_NEUSTART={neustart_datei!r}; printf "%-12s %s\\n" Pakete "$(_version_pakete)"')
            r = subprocess.run([BASH, "-c", rahmen, "-", VERSION], capture_output=True, text=True, check=True,
                               env={"PATH": "/usr/bin:/bin"})
            return r.stdout

    def test_zeile(self):
        self.assertEqual(self.zeile("bereit 12 Updates (3 Sicherheit)", True),
                         "Pakete       12 Updates (3 Sicherheit) · Neustart nötig\n")
        self.assertEqual(self.zeile("aktuell aktuell", False), "Pakete       aktuell\n")
        self.assertEqual(self.zeile("ungeprueft noch nie geprüft", False), "Pakete       noch nie geprüft\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
