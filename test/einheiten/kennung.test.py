#!/usr/bin/env python3
"""Einheitentests für die Systemkennung zenOS: scripts/bin/zenos-kennung (Erzeugen der os-release aus der Ubuntu-
Fassung, Texte für Konsole, /etc/legal und Begrüssung, Aufruf), der apt-Hook system/apt/60zenos-kennung und ein ganzer
Durchlauf einrichten → erneuern → ubuntu → einrichten in einer Testwurzel (--wurzel).

Ohne Netz und ohne das System anzufassen. Der Durchlauf braucht dpkg-divert, dpkg-statoverride und Root-Rechte
(dpkg-statoverride --update setzt den Besitzer root); er läuft im Testcontainer als root und in CI, auf dem Mac und als
normaler Benutzer wird er übersprungen. Erzeugen, Texte und Aufruf laufen überall.
  python3 test/einheiten/kennung.test.py
"""

import importlib.machinery
import importlib.util
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

# Kein __pycache__ neben scripts/bin/zenos-kennung
sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-kennung")
HOOK = os.path.join(WURZEL, "system", "apt", "60zenos-kennung")
MODUL = os.path.join(WURZEL, "scripts", "module", "72-kennung.sh")
_loader = importlib.machinery.SourceFileLoader("zenos_kennung", PROGRAMM)
K = importlib.util.module_from_spec(importlib.util.spec_from_loader("zenos_kennung", _loader))
_loader.exec_module(K)

# Wie im Image von Ubuntu 26.04.1 für den Raspberry Pi (/usr/lib/os-release aus base-files 14ubuntu6.2)
UBUNTU_2604 = """PRETTY_NAME="Ubuntu 26.04.1 LTS"
NAME="Ubuntu"
VERSION_ID="26.04"
VERSION="26.04.1 LTS (Resolute Raccoon)"
VERSION_CODENAME=resolute
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=resolute
LOGO=ubuntu-logo
"""
# Eine spätere Punktversion und ein Release-Upgrade (anderer Codename), wie dpkg sie nach os-release.ubuntu schreibt
UBUNTU_26042 = UBUNTU_2604.replace("26.04.1", "26.04.2")
UBUNTU_2804 = (UBUNTU_2604.replace("26.04.1", "28.04").replace('"26.04"', '"28.04"')
               .replace("resolute", "zukunft").replace("Resolute Raccoon", "Zukunft"))
ISSUE_UBUNTU = "Ubuntu 26.04.1 LTS \\n \\l\n\n"
LEGAL_UBUNTU = """
The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

"""


def werte(text):
    """os-release so gelesen wie von der Shell (shlex), Schlüssel → Wert."""
    ergebnis = {}
    for zeile in text.splitlines():
        if "=" in zeile and not zeile.startswith("#"):
            schluessel, roh = zeile.split("=", 1)
            teile = shlex.split(roh)
            ergebnis[schluessel] = teile[0] if teile else ""
    return ergebnis


class Erzeugen(unittest.TestCase):
    def setUp(self):
        self.text = K.generate(K.parse_os_release(UBUNTU_2604), "0.1.0")
        self.werte = werte(self.text)

    def test_kennung_zenos_wie_ein_ableger(self):
        self.assertEqual(self.werte["ID"], "zenos")
        self.assertEqual(self.werte["ID_LIKE"], "ubuntu debian")
        self.assertEqual(self.werte["NAME"], "zenOS")
        # lsb_release macht aus NAME die Distributor ID; NAME klein muss gleich ID sein, sonst «Zenos»
        self.assertEqual(self.werte["NAME"].lower(), self.werte["ID"])
        self.assertEqual(self.werte["PRETTY_NAME"], "zenOS 0.1.0")
        self.assertEqual(self.werte["ZENOS_VERSION"], "0.1.0")
        self.assertEqual(self.werte["LOGO"], "zenos")

    def test_ubuntu_werte_uebernommen(self):
        self.assertEqual(self.werte["VERSION_ID"], "26.04")
        self.assertEqual(self.werte["VERSION_CODENAME"], "resolute")
        self.assertEqual(self.werte["UBUNTU_CODENAME"], "resolute")
        self.assertEqual(self.werte["VERSION"], "0.1.0 (basiert auf Ubuntu 26.04.1 LTS)")

    def test_codenamen_ohne_anfuehrungszeichen(self):
        # update-notifier (apt_check.py) liest UBUNTU_CODENAME per regulärem Ausdruck bis zum Zeilenende
        self.assertIn("\nUBUNTU_CODENAME=resolute\n", self.text)
        self.assertIn("\nVERSION_CODENAME=resolute\n", self.text)

    def test_ubuntu_codename_nur_einmal(self):
        self.assertEqual(self.text.count("UBUNTU_CODENAME"), 1)

    def test_kein_ubuntu_im_namen(self):
        for schluessel in ("NAME", "PRETTY_NAME", "ID", "LOGO"):
            self.assertNotIn("ubuntu", self.werte[schluessel].lower(), schluessel)

    def test_keine_support_adressen(self):
        for schluessel in ("BUG_REPORT_URL", "SUPPORT_URL", "PRIVACY_POLICY_URL"):
            self.assertNotIn(schluessel, self.werte)
        self.assertEqual(self.werte["HOME_URL"], "https://github.com/Zenovs/zenOS")
        self.assertTrue(self.werte["DOCUMENTATION_URL"].startswith("https://github.com/Zenovs/zenOS/"))

    def test_idempotent(self):
        self.assertEqual(K.generate(K.parse_os_release(UBUNTU_2604), "0.1.0"), self.text)
        # Eingelesen und wieder ausgegeben bleibt alles gleich (Parser und Anführungszeichen passen zusammen)
        self.assertEqual(K.parse_os_release(self.text), self.werte)

    def test_quelle_muss_ubuntu_sein(self):
        # Nie aus der eigenen Fassung erzeugen (etwa wenn die Umlenkung fehlt)
        with self.assertRaises(K.Error):
            K.generate(K.parse_os_release(self.text), "0.1.0")

    def test_codename_in_anfuehrungszeichen_wird_ohne_geschrieben(self):
        quelle = UBUNTU_2604.replace("UBUNTU_CODENAME=resolute", 'UBUNTU_CODENAME="resolute"')
        self.assertIn("\nUBUNTU_CODENAME=resolute\n", K.generate(K.parse_os_release(quelle), "0.1.0"))

    def test_ohne_ubuntu_codename_aus_version_codename(self):
        quelle = UBUNTU_2604.replace("UBUNTU_CODENAME=resolute\n", "")
        self.assertIn("\nUBUNTU_CODENAME=resolute\n", K.generate(K.parse_os_release(quelle), "0.1.0"))

    def test_release_upgrade(self):
        text = K.generate(K.parse_os_release(UBUNTU_2804), "0.2.0")
        self.assertEqual(werte(text)["VERSION_CODENAME"], "zukunft")
        self.assertEqual(werte(text)["UBUNTU_CODENAME"], "zukunft")
        self.assertEqual(werte(text)["VERSION_ID"], "28.04")

    def test_ungewoehnlicher_codename_abgelehnt(self):
        for codename in ("res olute", "resolute;true", "", "$(id)"):
            quelle = UBUNTU_2604.replace("VERSION_CODENAME=resolute", f"VERSION_CODENAME={shlex.quote(codename)}")
            quelle = quelle.replace("UBUNTU_CODENAME=resolute", f"UBUNTU_CODENAME={shlex.quote(codename)}")
            with self.assertRaises(K.Error, msg=codename):
                K.generate(K.parse_os_release(quelle), "0.1.0")

    def test_zeichen_aus_der_ubuntu_fassung_maskiert(self):
        quelle = UBUNTU_2604.replace('PRETTY_NAME="Ubuntu 26.04.1 LTS"', 'PRETTY_NAME="Ubuntu \\"26\\" $HOME `x`"')
        text = K.generate(K.parse_os_release(quelle), "0.1.0")
        # shlex kennt \$ und \` in "…" nicht wie die Shell, deshalb hier der Parser des Programms
        self.assertEqual(K.parse_os_release(text)["VERSION"], '0.1.0 (basiert auf Ubuntu "26" $HOME `x`)')
        # Auch die Shell (motd, lsb_release) liest es wörtlich
        if shutil.which("sh"):
            with tempfile.NamedTemporaryFile("w", suffix=".os-release", delete=False, encoding="utf-8") as f:
                f.write(text)
            try:
                aus = subprocess.run(["sh", "-c", '. "$1"; printf %s "$VERSION"', "sh", f.name],
                                     capture_output=True, text=True, timeout=30, check=True)
                self.assertEqual(aus.stdout, '0.1.0 (basiert auf Ubuntu "26" $HOME `x`)')
            finally:
                os.unlink(f.name)

    def test_ohne_version(self):
        text = K.generate(K.parse_os_release(UBUNTU_2604), "")
        self.assertEqual(werte(text)["PRETTY_NAME"], "zenOS")
        self.assertEqual(werte(text)["VERSION"], "(basiert auf Ubuntu 26.04.1 LTS)")
        self.assertNotIn("ZENOS_VERSION", text)

    def test_version_aus_git_describe(self):
        self.assertEqual(K.normalize_version("v0.1.0-rc2-18-gabc1234-dirty\n"), "0.1.0-rc2-18-gabc1234")
        self.assertEqual(K.normalize_version("v0.1.0"), "0.1.0")
        self.assertEqual(K.normalize_version("abc1234"), "abc1234")
        for unbrauchbar in ("", "unbekannt", "0.1 beta", "0.1\"", "$(id)", "ubuntu1", "-x"):
            self.assertEqual(K.normalize_version(unbrauchbar), "", unbrauchbar)


class Texte(unittest.TestCase):
    def test_issue_mit_platzhalter(self):
        # agetty setzt \S (PRETTY_NAME) ein; die Datei bleibt bei einer neuen Version gleich
        self.assertEqual(K.ISSUE_TEXT, "\\S \\n \\l\n\n")

    def test_legal(self):
        self.assertIn("zenOS basiert auf Ubuntu", K.LEGAL_TEXT)
        self.assertIn("nicht mit\nCanonical verbunden", K.LEGAL_TEXT)
        self.assertIn("/usr/share/doc/*/copyright", K.LEGAL_TEXT)
        self.assertIn("OHNE JEDE GEWÄHRLEISTUNG", K.LEGAL_TEXT)
        self.assertNotIn("offiziell", K.LEGAL_TEXT.lower())
        self.assertTrue(all(len(z) <= 80 for z in K.LEGAL_TEXT.splitlines()))

    def test_motd_skript(self):
        self.assertTrue(K.MOTD_TEXT.startswith("#!/bin/sh\n"))
        self.assertIn(K.MOTD_MARK, K.MOTD_TEXT)
        self.assertNotIn("Welcome to Ubuntu", K.MOTD_TEXT)
        if shutil.which("sh"):
            subprocess.run(["sh", "-n"], input=K.MOTD_TEXT, text=True, timeout=30, check=True)
            aus = subprocess.run(["sh", "-s"], input=K.MOTD_TEXT, capture_output=True, text=True, timeout=30,
                                 check=True)
            zeilen = aus.stdout.splitlines()
            self.assertEqual(len(zeilen), 2, aus.stdout)
            self.assertRegex(zeilen[0], r"^.+ · Basis .+ · Kernel .+$")
            self.assertEqual(zeilen[1], "Hilfe: zen hilfe · Zustand: zen doctor")
        if shutil.which("shellcheck"):
            aus = subprocess.run(["shellcheck", "-s", "sh", "-"], input=K.MOTD_TEXT, capture_output=True, text=True,
                                 timeout=60, check=False)
            self.assertEqual(aus.returncode, 0, aus.stdout)

    def test_stillgelegte_skripte(self):
        # 50-motd-news legt 70-sicherheit still (Netz), die übrigen Ubuntu-Skripte (Updates, Neustart) bleiben
        self.assertEqual(set(K.MOTD_OFF), {"00-header", "10-help-text", "91-contract-ua-esm-status",
                                           "91-release-upgrade"})


class Hook(unittest.TestCase):
    def test_hook_laesst_apt_nie_scheitern(self):
        with open(HOOK, encoding="utf-8") as f:
            text = f.read()
        befehle = re.findall(r'DPkg::Post-Invoke\s*\{\s*"([^"]*)"\s*;\s*\}\s*;', text)
        self.assertEqual(len(befehle), 1, text)
        befehl = befehle[0]
        self.assertTrue(befehl.startswith("[ ! -x /usr/local/sbin/zenos-kennung ] || "), befehl)
        self.assertIn("/usr/local/sbin/zenos-kennung erneuern", befehl)
        self.assertTrue(befehl.endswith("|| true"), befehl)
        if shutil.which("sh"):
            # Ohne Programm und mit einem scheiternden Programm: Exit 0
            subprocess.run(["sh", "-n", "-c", befehl], timeout=30, check=True)

    def test_modul_installiert_root_kopie(self):
        with open(MODUL, encoding="utf-8") as f:
            text = f.read()
        self.assertIn("_KENNUNG_PROGRAMM=/usr/local/sbin/zenos-kennung", text)
        self.assertIn('scripts/bin/zenos-kennung" "$_KENNUNG_PROGRAMM" 0755 root:root', text)
        self.assertIn("LSB_OS_RELEASE=$neu", text)


class Aufruf(unittest.TestCase):
    def lauf(self, *argumente, **kw):
        return subprocess.run([sys.executable, PROGRAMM, *argumente], capture_output=True, text=True, timeout=60,
                              check=False, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"), **kw)

    def test_hilfe(self):
        aus = self.lauf("--hilfe")
        self.assertEqual(aus.returncode, 0)
        self.assertIn("zenos-kennung einrichten", aus.stdout)

    def test_ohne_unterbefehl(self):
        self.assertEqual(self.lauf().returncode, 2)

    def test_unbekannt(self):
        self.assertEqual(self.lauf("umbenennen").returncode, 2)
        self.assertEqual(self.lauf("einrichten", "--jetzt").returncode, 2)
        self.assertEqual(self.lauf("ubuntu", "--irgendwas").returncode, 2)

    def test_erzeugen(self):
        with tempfile.TemporaryDirectory() as tmp:
            quelle = os.path.join(tmp, "os-release.ubuntu")
            with open(quelle, "w", encoding="utf-8") as f:
                f.write(UBUNTU_2604)
            aus = self.lauf("erzeugen", "--ubuntu", quelle, "--version", "v0.1.0-rc2-18-gabc1234-dirty")
            self.assertEqual(aus.returncode, 0, aus.stderr)
            self.assertEqual(aus.stdout, K.generate(K.parse_os_release(UBUNTU_2604), "0.1.0-rc2-18-gabc1234"))
            # Aus der zenOS-Fassung nie
            andere = os.path.join(tmp, "os-release.zenos")
            with open(andere, "w", encoding="utf-8") as f:
                f.write(aus.stdout)
            aus = self.lauf("erzeugen", "--ubuntu", andere)
            self.assertEqual(aus.returncode, 1)
            self.assertEqual(aus.stdout, "")

    @unittest.skipIf(os.geteuid() == 0, "läuft als root")
    def test_ohne_root_verweigert(self):
        with tempfile.TemporaryDirectory() as tmp:
            for befehl in ("einrichten", "erneuern", "ubuntu"):
                aus = self.lauf("--wurzel", tmp, befehl)
                self.assertEqual(aus.returncode, 1, befehl)
                self.assertIn("Root-Rechte", aus.stderr)
            self.assertEqual(os.listdir(tmp), [])


DPKG = all(shutil.which(p) for p in ("dpkg-divert", "dpkg-statoverride"))


@unittest.skipUnless(DPKG and os.geteuid() == 0, "braucht dpkg-divert, dpkg-statoverride und Root-Rechte")
class Durchlauf(unittest.TestCase):
    """einrichten, erneuern, ubuntu und wieder einrichten in einer Testwurzel, wie auf dem Pi."""

    MOTD = ("00-header", "10-help-text", "50-motd-news", "90-updates-available", "91-contract-ua-esm-status",
            "91-release-upgrade", "98-reboot-required")

    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-kennung-test.")
        self.datei("/usr/lib/os-release", UBUNTU_2604)
        self.datei("/etc/issue", ISSUE_UBUNTU)
        os.symlink("../usr/lib/os-release", self.p("/etc/os-release"))
        self.datei("/etc/legal", LEGAL_UBUNTU)
        for name in self.MOTD:
            self.datei(f"/etc/update-motd.d/{name}", f"#!/bin/sh\necho {name}\n", 0o755)
        self.datei("/usr/share/python-apt/templates/ubuntu.info", "Suite: resolute\n")
        self.datei("/usr/share/python-apt/templates/ubuntu.mirrors", "http://ports.example.invalid/\n")
        self.datei("/usr/share/distro-info/ubuntu.csv", "version,codename,series\n")
        os.makedirs(self.p("/var/lib/update-notifier"))
        os.makedirs(self.p("/var/lib/dpkg"))
        self.datei("/etc/apt/apt.conf.d/51zenos-ubuntu-quellen", "// Test\n")
        self.datei("/usr/local/share/zenos/version", "0.1.0-rc2-18-gabc1234\n")
        self.vorher = {pfad: self.lesen(pfad) for pfad in ("/usr/lib/os-release", "/etc/issue", "/etc/legal")}

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def p(self, pfad):
        return os.path.join(self.w, pfad.lstrip("/"))

    def datei(self, pfad, inhalt, modus=0o644):
        os.makedirs(os.path.dirname(self.p(pfad)), exist_ok=True)
        with open(self.p(pfad), "w", encoding="utf-8") as f:
            f.write(inhalt)
        os.chmod(self.p(pfad), modus)

    def lesen(self, pfad):
        with open(self.p(pfad), encoding="utf-8") as f:
            return f.read()

    def modus(self, pfad):
        return stat.S_IMODE(os.stat(self.p(pfad)).st_mode)

    def lauf(self, *argumente):
        return subprocess.run([sys.executable, PROGRAMM, "--wurzel", self.w, *argumente], capture_output=True,
                              text=True, timeout=120, check=False, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))

    def dpkg(self, *argumente):
        return subprocess.run(list(argumente[:1]) + ["--root", self.w] + list(argumente[1:]), capture_output=True,
                              text=True, timeout=60, check=False).stdout

    def geaendert(self, aus):
        return [z for z in aus.stdout.splitlines() if z.startswith("geändert: ")]

    def test_ganzer_durchlauf(self):
        self.assertEqual(self.lauf("pruefen").returncode, 1)

        aus = self.lauf("einrichten")
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)
        self.assertTrue(self.geaendert(aus))
        werte_neu = werte(self.lesen("/usr/lib/os-release"))
        self.assertEqual(werte_neu["PRETTY_NAME"], "zenOS 0.1.0-rc2-18-gabc1234")
        self.assertEqual(werte_neu["ID"], "zenos")
        self.assertEqual(self.lesen("/usr/lib/os-release.ubuntu"), UBUNTU_2604)
        self.assertEqual(os.readlink(self.p("/etc/os-release")), "../usr/lib/os-release")
        self.assertEqual(self.lesen("/etc/issue"), K.ISSUE_TEXT)
        self.assertEqual(self.lesen("/etc/issue.ubuntu"), ISSUE_UBUNTU)
        self.assertEqual(self.lesen("/etc/legal"), K.LEGAL_TEXT)
        umlenkungen = self.dpkg("dpkg-divert", "--list")
        for pfad in ("/usr/lib/os-release", "/etc/issue", "/etc/legal"):
            self.assertIn(f"local diversion of {pfad} to {pfad}.ubuntu", umlenkungen)
        overrides = self.dpkg("dpkg-statoverride", "--list")
        for name in K.MOTD_OFF:
            self.assertIn(f"root root 644 /etc/update-motd.d/{name}", overrides)
            self.assertEqual(self.modus(f"/etc/update-motd.d/{name}"), 0o644)
        for name in ("50-motd-news", "90-updates-available", "98-reboot-required"):
            self.assertEqual(self.modus(f"/etc/update-motd.d/{name}"), 0o755, name)
            self.assertNotIn(name, overrides)
        self.assertEqual(self.lesen("/etc/update-motd.d/00-zenos"), K.MOTD_TEXT)
        self.assertEqual(self.modus("/etc/update-motd.d/00-zenos"), 0o755)
        self.assertTrue(os.path.isfile(self.p("/var/lib/update-notifier/hide-esm-in-motd")))
        self.assertEqual(os.readlink(self.p("/usr/share/python-apt/templates/zenos.info")), "ubuntu.info")
        self.assertEqual(os.readlink(self.p("/usr/share/python-apt/templates/zenos.mirrors")), "ubuntu.mirrors")
        self.assertEqual(os.readlink(self.p("/usr/share/distro-info/zenos.csv")), "ubuntu.csv")

        # Zweiter Lauf: nichts mehr zu tun
        aus = self.lauf("einrichten")
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertEqual(self.geaendert(aus), [])
        aus = self.lauf("pruefen")
        self.assertEqual(aus.returncode, 0, aus.stdout)
        self.assertEqual(aus.stdout.strip(),
                         "eingerichtet: zenOS 0.1.0-rc2-18-gabc1234 · Basis Ubuntu 26.04.1 LTS")
        self.assertEqual(self.geaendert(self.lauf("erneuern")), [])

        # base-files mit neuer Punktversion (dpkg schreibt in die umgelenkte Fassung): erneuern zieht nach
        self.datei("/usr/lib/os-release.ubuntu", UBUNTU_26042)
        self.assertEqual(self.lauf("pruefen").returncode, 1)
        aus = self.lauf("erneuern")
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertEqual(len(self.geaendert(aus)), 1)
        self.assertIn("basiert auf Ubuntu 26.04.2 LTS", self.lesen("/usr/lib/os-release"))
        self.assertEqual(self.geaendert(self.lauf("erneuern")), [])
        # Release-Upgrade: der Codename folgt
        self.datei("/usr/lib/os-release.ubuntu", UBUNTU_2804)
        self.lauf("erneuern")
        self.assertEqual(werte(self.lesen("/usr/lib/os-release"))["VERSION_CODENAME"], "zukunft")
        self.datei("/usr/lib/os-release.ubuntu", UBUNTU_2604)
        self.lauf("erneuern")
        # Neue Version von zenOS: einrichten (install.sh) schreibt nur os-release neu
        self.datei("/usr/local/share/zenos/version", "0.1.0\n")
        aus = self.lauf("einrichten")
        self.assertEqual(self.geaendert(aus), ["geändert: /usr/lib/os-release"])

        # Rückweg: alles wie bei Ubuntu, Byte für Byte, und der Merker hält install.sh davon ab, wieder umzustellen
        aus = self.lauf("ubuntu")
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)
        for pfad, inhalt in self.vorher.items():
            self.assertEqual(self.lesen(pfad), inhalt, pfad)
            self.assertFalse(os.path.lexists(self.p(pfad + ".ubuntu")), pfad)
        self.assertEqual(self.dpkg("dpkg-divert", "--list").strip(), "")
        self.assertEqual(self.dpkg("dpkg-statoverride", "--list").strip(), "")
        for name in self.MOTD:
            self.assertEqual(self.modus(f"/etc/update-motd.d/{name}"), 0o755, name)
        self.assertFalse(os.path.lexists(self.p("/etc/update-motd.d/00-zenos")))
        self.assertFalse(os.path.lexists(self.p("/var/lib/update-notifier/hide-esm-in-motd")))
        self.assertFalse(os.path.lexists(self.p("/usr/share/python-apt/templates/zenos.info")))
        self.assertFalse(os.path.lexists(self.p("/usr/share/distro-info/zenos.csv")))
        self.assertIn("kennung=ubuntu", self.lesen("/var/lib/zenos/kennung"))
        aus = self.lauf("pruefen")
        self.assertEqual(aus.returncode, 3, aus.stdout)
        self.assertEqual(self.geaendert(self.lauf("erneuern")), [])
        self.assertEqual(self.geaendert(self.lauf("ubuntu")), [])

        # Wieder einrichten: der Merker verschwindet
        aus = self.lauf("einrichten")
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertFalse(os.path.exists(self.p("/var/lib/zenos/kennung")))
        self.assertEqual(self.lauf("pruefen").returncode, 0)

    def test_ubuntu_ohne_merker(self):
        self.lauf("einrichten")
        aus = self.lauf("ubuntu", "--ohne-merker")
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertFalse(os.path.exists(self.p("/var/lib/zenos/kennung")))
        self.assertEqual(self.lesen("/usr/lib/os-release"), UBUNTU_2604)
        self.assertEqual(self.lauf("pruefen").returncode, 1)

    def test_ohne_datei_51_verweigert(self):
        os.unlink(self.p("/etc/apt/apt.conf.d/51zenos-ubuntu-quellen"))
        aus = self.lauf("einrichten")
        self.assertEqual(aus.returncode, 1)
        self.assertIn("51zenos-ubuntu-quellen", aus.stderr)
        self.assertEqual(self.lesen("/usr/lib/os-release"), UBUNTU_2604)
        self.assertEqual(self.dpkg("dpkg-divert", "--list").strip(), "")

    def test_unterbrochener_rueckweg(self):
        # Umlenkung schon weg, die zenOS-Fassung noch da, die Ubuntu-Fassung daneben: einrichten behält sie
        self.lauf("einrichten")
        self.dpkg("dpkg-divert", "--local", "--no-rename", "--remove", "/etc/issue")
        aus = self.lauf("einrichten")
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertEqual(self.lesen("/etc/issue.ubuntu"), ISSUE_UBUNTU)
        self.assertEqual(self.lesen("/etc/issue"), K.ISSUE_TEXT)
        # … und ubuntu stellt auch ohne Umlenkung die Ubuntu-Fassung zurück
        self.dpkg("dpkg-divert", "--local", "--no-rename", "--remove", "/etc/legal")
        self.lauf("ubuntu")
        self.assertEqual(self.lesen("/etc/legal"), LEGAL_UBUNTU)
        self.assertFalse(os.path.lexists(self.p("/etc/legal.ubuntu")))

    def test_fremder_statoverride_bleibt(self):
        self.dpkg("dpkg-statoverride", "--add", "root", "root", "0700", "/etc/update-motd.d/10-help-text")
        self.lauf("einrichten")
        self.assertIn("root root 700 /etc/update-motd.d/10-help-text", self.dpkg("dpkg-statoverride", "--list"))
        self.lauf("ubuntu")
        self.assertIn("root root 700 /etc/update-motd.d/10-help-text", self.dpkg("dpkg-statoverride", "--list"))

    def test_ohne_update_notifier_und_python_apt(self):
        shutil.rmtree(self.p("/var/lib/update-notifier"))
        shutil.rmtree(self.p("/usr/share/python-apt"))
        aus = self.lauf("einrichten")
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertFalse(os.path.exists(self.p("/var/lib/update-notifier")))
        self.assertFalse(os.path.exists(self.p("/usr/share/python-apt")))
        self.assertEqual(self.lauf("pruefen").returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
