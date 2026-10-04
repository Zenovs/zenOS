#!/usr/bin/env python3
"""Einheitentests: Erlaubt unattended-upgrades die Ubuntu-Sicherheitsquelle, auch wenn /etc/os-release eine andere
Kennung als Ubuntu meldet? Prüft system/apt/51zenos-ubuntu-quellen und scripts/bin/zenos-sicherheitsquelle.

Ohne Root, ohne Netz und ohne die Paketlisten des Systems: Jeder Fall baut im Temp-Ordner einen eigenen apt-Zustand
(APT_CONFIG mit eigenem apt.conf.d, eigener sources.list, Paketlisten für «Ubuntu resolute» und «Ubuntu
resolute-security», leerer dpkg-Status) und eine eigene os-release, die lsb_release über LSB_OS_RELEASE liest. Geprüft
wird mit /usr/bin/unattended-upgrade selbst und mit der Vorgabe 50unattended-upgrades des Pakets. Ohne
unattended-upgrades oder lsb_release (z. B. auf dem Mac) laufen nur die Prüfungen der Datei und des Aufrufs.

  python3 test/einheiten/sicherheitsquelle.test.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATEI_51 = os.path.join(WURZEL, "system", "apt", "51zenos-ubuntu-quellen")
DATEI_52 = os.path.join(WURZEL, "system", "apt", "52zenos-unattended")
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-sicherheitsquelle")
UU = "/usr/bin/unattended-upgrade"
VORGABE_50 = "/etc/apt/apt.conf.d/50unattended-upgrades"

OS_RELEASE_UBUNTU = """PRETTY_NAME="Ubuntu 26.04 LTS"
NAME="Ubuntu"
VERSION_ID="26.04"
VERSION="26.04 LTS (Resolute Raccoon)"
VERSION_CODENAME=resolute
ID=ubuntu
ID_LIKE=debian
UBUNTU_CODENAME=resolute
"""

# Eine andere Kennung wie für eine spätere Umbenennung: ID und NAME anders, die Codenamen bleiben die von Ubuntu
OS_RELEASE_ANDERE = """PRETTY_NAME="zenOS 0.1"
NAME="zenOS"
VERSION_ID="0.1"
VERSION="0.1 (basiert auf Ubuntu 26.04 LTS)"
VERSION_CODENAME=resolute
ID=zenos
ID_LIKE="ubuntu debian"
UBUNTU_CODENAME=resolute
"""

SERVER = "http://ports.example.invalid/ubuntu-ports"
LISTEN_PRAEFIX = "ports.example.invalid_ubuntu-ports_dists_"

RELEASE = """Origin: Ubuntu
Label: Ubuntu
Suite: {suite}
Version: 26.04
Codename: resolute
Date: Sat, 03 Oct 2026 00:00:00 UTC
Architectures: arm64
Components: main
Description: Ubuntu Resolute 26.04
"""

PACKAGES = """Package: zenos-testpaket
Architecture: arm64
Version: {version}
Priority: optional
Section: misc
Filename: pool/main/z/zenos-testpaket/zenos-testpaket_{version}_arm64.deb
Size: 1000
Description: Testpaket ohne Inhalt
"""


def hat_lsb_os_release():
    """lsb_release da und wertet LSB_OS_RELEASE aus (wie das Shell-Skript von Ubuntu 26.04)?"""
    if not shutil.which("lsb_release"):
        return False
    with tempfile.NamedTemporaryFile("w", suffix=".os-release", delete=False, encoding="utf-8") as f:
        f.write('NAME="Probe"\nID=probe\n')
        pfad = f.name
    try:
        aus = subprocess.run(["lsb_release", "-is"], env=dict(os.environ, LSB_OS_RELEASE=pfad), capture_output=True,
                             text=True, timeout=30, check=False)
        return aus.stdout.strip() == "Probe"
    finally:
        os.unlink(pfad)


def hat_python_apt():
    aus = subprocess.run([sys.executable, "-c", "import apt_pkg"], capture_output=True, timeout=30, check=False)
    return aus.returncode == 0


UMGEBUNG = os.path.isfile(UU) and os.path.isfile(VORGABE_50) and hat_lsb_os_release() and hat_python_apt()
GRUND = "unattended-upgrades, python3-apt oder lsb_release mit LSB_OS_RELEASE fehlt"


class Apt:
    """Eigener apt-Zustand im Temp-Ordner (APT_CONFIG) und eigene os-release."""

    def __init__(self, ordner, teile, os_release, suites=("resolute", "resolute-security")):
        self.ordner = ordner
        parts = os.path.join(ordner, "apt.conf.d")
        listen = os.path.join(ordner, "lists")
        for pfad in (parts, listen, os.path.join(listen, "partial"), os.path.join(ordner, "sources.list.d"),
                     os.path.join(ordner, "preferences.d"), os.path.join(ordner, "cache")):
            os.makedirs(pfad, exist_ok=True)
        for quelle, name in teile:
            shutil.copyfile(quelle, os.path.join(parts, name))
        with open(os.path.join(ordner, "status"), "w", encoding="utf-8"):
            pass
        with open(os.path.join(ordner, "sources.list"), "w", encoding="utf-8") as f:
            for suite in suites:
                f.write(f"deb {SERVER} {suite} main\n")
        for nummer, suite in enumerate(suites, start=1):
            with open(os.path.join(listen, f"{LISTEN_PRAEFIX}{suite}_Release"), "w", encoding="utf-8") as f:
                f.write(RELEASE.format(suite=suite))
            name = f"{LISTEN_PRAEFIX}{suite}_main_binary-arm64_Packages"
            with open(os.path.join(listen, name), "w", encoding="utf-8") as f:
                f.write(PACKAGES.format(version=f"1.{nummer}"))
        self.konfig = os.path.join(ordner, "apt.conf")
        with open(self.konfig, "w", encoding="utf-8") as f:
            f.write(f"""Dir::Etc::parts "{parts}";
Dir::Etc::main "{ordner}/fehlt.conf";
Dir::Etc::sourcelist "{ordner}/sources.list";
Dir::Etc::sourceparts "{ordner}/sources.list.d";
Dir::Etc::preferences "{ordner}/preferences";
Dir::Etc::preferencesparts "{ordner}/preferences.d";
Dir::State::lists "{listen}/";
Dir::State::status "{ordner}/status";
Dir::Cache "{ordner}/cache/";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
APT::Architecture "arm64";
APT::Architectures {{ "arm64"; }};
""")
        self.os_release = os.path.join(ordner, "os-release")
        with open(self.os_release, "w", encoding="utf-8") as f:
            f.write(os_release)

    def umgebung(self):
        return dict(os.environ, APT_CONFIG=self.konfig, LSB_OS_RELEASE=self.os_release, PYTHONDONTWRITEBYTECODE="1")

    def programm(self, *argumente):
        return subprocess.run([sys.executable, PROGRAMM, *argumente], env=self.umgebung(), capture_output=True,
                              text=True, timeout=60, check=False)

    def unattended_upgrade(self):
        """distro_id, distro_codename, erlaubte Quellen und DevRelease, wie unattended-upgrade sie sieht."""
        code = f"""
import contextlib, importlib.machinery, importlib.util, io, json, sys
sys.dont_write_bytecode = True
l = importlib.machinery.SourceFileLoader("uu", {UU!r})
uu = importlib.util.module_from_spec(importlib.util.spec_from_loader("uu", l))
with contextlib.redirect_stdout(io.StringIO()):
    l.exec_module(uu)
print(json.dumps([uu.get_distro_id(), uu.get_distro_codename(), uu.get_allowed_origins(),
                  uu.apt_pkg.config.find("Unattended-Upgrade::DevRelease")]))
"""
        aus = subprocess.run([sys.executable, "-c", code], env=self.umgebung(), capture_output=True, text=True,
                             timeout=60, check=True)
        return json.loads(aus.stdout.strip().splitlines()[-1])


class Datei51(unittest.TestCase):
    """Die Datei selbst: feste Origins, DevRelease, keine Platzhalter für distro_id."""

    @classmethod
    def setUpClass(cls):
        with open(DATEI_51, encoding="utf-8") as f:
            cls.text = f.read()
        # apt-Kommentare («//» bis zum Zeilenende) weg, dann nur noch die Einträge
        cls.ohne_kommentare = re.sub(r"//[^\n]*", "", cls.text)

    def test_feste_ubuntu_origins(self):
        eintraege = re.findall(r'"([^"]*)"\s*;', self.ohne_kommentare)
        self.assertEqual(eintraege[:4], [
            "Ubuntu:${distro_codename}",
            "Ubuntu:${distro_codename}-security",
            "UbuntuESMApps:${distro_codename}-apps-security",
            "UbuntuESM:${distro_codename}-infra-security",
        ])
        self.assertIn("Unattended-Upgrade::Allowed-Origins {", self.ohne_kommentare)
        self.assertNotIn("${distro_id}", self.ohne_kommentare)

    def test_devrelease_aus(self):
        self.assertRegex(self.ohne_kommentare, r'Unattended-Upgrade::DevRelease\s+"false"\s*;')

    def test_nur_ascii_ausserhalb_der_kommentare(self):
        self.assertTrue(self.ohne_kommentare.isascii())


class Aufruf(unittest.TestCase):
    def lauf(self, *argumente):
        return subprocess.run([sys.executable, PROGRAMM, *argumente], capture_output=True, text=True, timeout=60,
                              check=False, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))

    def test_hilfe(self):
        aus = self.lauf("--hilfe")
        self.assertEqual(aus.returncode, 0)
        self.assertIn("Exit: 0 erlaubt", aus.stdout)

    def test_unbekanntes_argument(self):
        aus = self.lauf("--irgendwas")
        self.assertEqual(aus.returncode, 2)
        self.assertIn("unbekannte Argumente", aus.stderr)

    @unittest.skipIf(os.path.exists(UU), "unattended-upgrades ist installiert")
    def test_ohne_unattended_upgrades_nicht_pruefbar(self):
        aus = self.lauf()
        self.assertEqual(aus.returncode, 2)
        self.assertEqual(aus.stdout.strip(), f"nicht prüfbar: unattended-upgrades fehlt ({UU})")


@unittest.skipUnless(UMGEBUNG, GRUND)
class Sicherheitsquelle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="zenos-sicherheitsquelle-test.")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def apt(self, *namen, os_release=OS_RELEASE_ANDERE, suites=("resolute", "resolute-security")):
        quellen = {"50": (VORGABE_50, "50unattended-upgrades"), "51": (DATEI_51, "51zenos-ubuntu-quellen"),
                   "52": (DATEI_52, "52zenos-unattended")}
        return Apt(self.tmp, [quellen[n] for n in namen], os_release, suites)

    def test_ubuntu_ohne_51_erlaubt(self):
        aus = self.apt("50", "52", os_release=OS_RELEASE_UBUNTU).programm()
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)
        self.assertEqual(aus.stdout.strip(),
                         "erlaubt: Ubuntu resolute-security (distro_id=Ubuntu, distro_codename=resolute)")

    def test_andere_kennung_ohne_51_zeigt_die_luecke(self):
        apt = self.apt("50", "52")
        distro_id, codename, erlaubt, _ = apt.unattended_upgrade()
        self.assertEqual((distro_id, codename), ("zenOS", "resolute"))
        self.assertIn("o=zenOS,a=resolute-security", erlaubt)
        self.assertFalse([e for e in erlaubt if e.startswith("o=Ubuntu")], erlaubt)
        aus = apt.programm()
        self.assertEqual(aus.returncode, 1, aus.stdout + aus.stderr)
        self.assertTrue(aus.stdout.startswith("nicht erlaubt: Ubuntu resolute-security (distro_id=zenOS"),
                        aus.stdout)

    def test_andere_kennung_mit_51_erlaubt(self):
        apt = self.apt("50", "51", "52")
        distro_id, codename, erlaubt, devrelease = apt.unattended_upgrade()
        self.assertEqual((distro_id, codename), ("zenOS", "resolute"))
        for eintrag in ("o=Ubuntu,a=resolute", "o=Ubuntu,a=resolute-security",
                        "o=UbuntuESMApps,a=resolute-apps-security", "o=UbuntuESM,a=resolute-infra-security"):
            self.assertIn(eintrag, erlaubt)
        # Die Herstellerquellen aus 52 bleiben
        self.assertIn("origin=Google LLC,label=Google,site=dl.google.com", erlaubt)
        self.assertEqual(devrelease, "false")
        aus = apt.programm()
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)
        self.assertEqual(aus.stdout.strip(),
                         "erlaubt: Ubuntu resolute-security (distro_id=zenOS, distro_codename=resolute)")

    def test_ubuntu_mit_51_erlaubt(self):
        aus = self.apt("50", "51", "52", os_release=OS_RELEASE_UBUNTU).programm()
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)

    def test_nur_51_reicht(self):
        # Auch ohne die Vorgabe des Pakets (etwa wenn 50unattended-upgrades einmal anders aussieht)
        apt = self.apt("51")
        # Nur der eigene apt.conf.d zählt, nicht der des Systems: genau die vier Einträge aus 51
        self.assertEqual(apt.unattended_upgrade()[2], [
            "o=Ubuntu,a=resolute", "o=Ubuntu,a=resolute-security", "o=UbuntuESMApps,a=resolute-apps-security",
            "o=UbuntuESM,a=resolute-infra-security"])
        aus = apt.programm()
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)

    def test_ohne_paketliste_nicht_pruefbar(self):
        aus = self.apt("50", "51", suites=("resolute",)).programm()
        self.assertEqual(aus.returncode, 2, aus.stdout + aus.stderr)
        self.assertEqual(aus.stdout.strip(), "nicht prüfbar: keine Paketliste für Ubuntu resolute-security (apt update?)")

    def test_codename_aus_den_paketlisten(self):
        # os-release ohne UBUNTU_CODENAME: der Codename kommt aus der einzigen Ubuntu-Sicherheitsquelle
        ohne = OS_RELEASE_ANDERE.replace("UBUNTU_CODENAME=resolute\n", "")
        aus = self.apt("50", "51", os_release=ohne).programm()
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)
        self.assertIn("Ubuntu resolute-security", aus.stdout)

    def test_anderer_codename_faellt_auf(self):
        # Hiesse VERSION_CODENAME einmal anders, passte ${distro_codename} auch in 51 nicht mehr
        anders = OS_RELEASE_ANDERE.replace("VERSION_CODENAME=resolute", "VERSION_CODENAME=zenos")
        aus = self.apt("50", "51", os_release=anders).programm()
        self.assertEqual(aus.returncode, 1, aus.stdout + aus.stderr)

    def test_eine_zeile_ohne_stderr(self):
        aus = self.apt("50", "51", "52").programm()
        self.assertEqual(len(aus.stdout.strip().splitlines()), 1, aus.stdout)
        self.assertEqual(aus.stderr, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
