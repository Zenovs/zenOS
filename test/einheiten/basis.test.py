#!/usr/bin/env python3
"""Einheitentests für die Sperre des Ubuntu-Basiswechsels: scripts/module/71-basis.sh (Prompt=never per Drop-in, alter
Hinweis auf eine neue Version geleert) und die Prüfung in zen doctor (scripts/doctor.d/71-ubuntu.sh).

Modul und Prüfung laufen in bash mit Attrappen für die Hilfsfunktionen von install.sh bzw. zen doctor, gegen Ordner im
Temp-Ordner. Die Reihenfolge, in der der Release-Upgrader liest (release-upgrades, danach release-upgrades.d/*.cfg in
Namensreihenfolge, der letzte Wert zählt), bildet der Test mit configparser nach wie MetaRelease.py; dass das Programm
selbst den Drop-in liest, ist im Container geprüft (docs/module/kennung.md). Ohne Root, ohne Netz.

  python3 test/einheiten/basis.test.py
"""

import configparser
import glob
import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODUL = os.path.join(WURZEL, "scripts", "module", "71-basis.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "71-ubuntu.sh")
DROPIN = os.path.join(WURZEL, "system", "update-manager", "zenos.cfg")
BASH = shutil.which("bash")

MODUL_RAHMEN = r'''
set -u
datei_installieren() {
  mkdir -p -- "$(dirname -- "$2")"
  if [[ -f "$2" ]] && cmp -s -- "$1" "$2"; then return 0; fi
  cp -- "$1" "$2"
  printf 'aenderung: %s\n' "$2"
}
datei_schreiben() { local t; t=$(mktemp); cat > "$t"; datei_installieren "$t" "$1"; rm -f -- "$t"; }
aenderung() { printf 'aenderung: %s\n' "$*"; }
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
source "$MODUL"
_BASIS_DROPIN=$ZIEL/etc/update-manager/release-upgrades.d/zenos.cfg
_BASIS_HINWEIS=$ZIEL/var/lib/ubuntu-release-upgrader/release-upgrade-available
modul_system
'''

DOCTOR_RAHMEN = r'''
set -u
abschnitt() { printf 'abschnitt: %s\n' "$*"; }
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$DOCTOR"
_UBUNTU_ORDNER=$ZIEL/etc/update-manager
pruefe_ubuntu
'''

UBUNTU_RELEASE_UPGRADES = """# Default behavior for the release upgrader.

[DEFAULT]
# Default prompting and upgrade behavior, valid options:
#  never  - Never check for, or allow upgrading to, a new release.
Prompt=lts
"""

UBUNTU_ADVANTAGE = """[Sources]
Pockets=security,updates,proposed,backports,infra-security,infra-updates,apps-security,apps-updates
[Distro]
PostInstallScripts=./xorg_fix_proprietary.py
"""


def schreiben(pfad, text):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(text)


def prompt_wie_metarelease(ordner):
    """Prompt wie MetaReleaseCore: release-upgrades, dann release-upgrades.d/*.cfg sortiert, der letzte Wert zählt."""
    dateien = [os.path.join(ordner, "release-upgrades")] if os.path.exists(os.path.join(ordner, "release-upgrades")) \
        else []
    dateien += sorted(glob.glob(os.path.join(ordner, "release-upgrades.d", "*.cfg")))
    prompt = None
    for datei in dateien:
        parser = configparser.ConfigParser()
        parser.read(datei)
        if parser.has_option("DEFAULT", "Prompt"):
            wert = parser.get("DEFAULT", "Prompt").lower()
            prompt = "never" if wert in ("never", "no") else "lts" if wert == "lts" else "normal"
    return prompt


@unittest.skipUnless(BASH, "bash fehlt")
class Modul(unittest.TestCase):
    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-basis-test.")
        self.addCleanup(shutil.rmtree, self.ziel, True)
        self.dropin = os.path.join(self.ziel, "etc", "update-manager", "release-upgrades.d", "zenos.cfg")
        self.hinweis = os.path.join(self.ziel, "var", "lib", "ubuntu-release-upgrader", "release-upgrade-available")

    def lauf(self):
        r = subprocess.run([BASH, "-c", MODUL_RAHMEN], capture_output=True, text=True, check=False,
                           env={"PATH": "/usr/bin:/bin", "MODUL": MODUL, "ZIEL": self.ziel, "ZENOS_CODE": WURZEL})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return [z for z in r.stdout.splitlines() if z.startswith("aenderung: ")]

    def test_dropin_einmal(self):
        self.assertEqual(self.lauf(), [f"aenderung: {self.dropin}"])
        with open(self.dropin, encoding="utf-8") as a, open(DROPIN, encoding="utf-8") as b:
            self.assertEqual(a.read(), b.read())
        self.assertEqual(self.lauf(), [], "zweiter Lauf: 0 Änderungen")
        self.assertFalse(os.path.exists(self.hinweis), "kein Hinweis angelegt, wo keiner war")

    def test_dropin_gewinnt_wie_metarelease(self):
        ordner = os.path.join(self.ziel, "etc", "update-manager")
        schreiben(os.path.join(ordner, "release-upgrades"), UBUNTU_RELEASE_UPGRADES)
        schreiben(os.path.join(ordner, "release-upgrades.d", "ubuntu-advantage-upgrades.cfg"), UBUNTU_ADVANTAGE)
        self.assertEqual(prompt_wie_metarelease(ordner), "lts")
        self.lauf()
        self.assertEqual(prompt_wie_metarelease(ordner), "never")
        with open(os.path.join(ordner, "release-upgrades"), encoding="utf-8") as f:
            self.assertEqual(f.read(), UBUNTU_RELEASE_UPGRADES, "die Conffile bleibt unberührt")

    def test_dropin_nur_ascii(self):
        """Der Release-Upgrader liest mit der Kodierung der Umgebung (configparser.read ohne encoding)."""
        with open(DROPIN, "rb") as f:
            inhalt = f.read()
        self.assertTrue(all(32 <= b < 127 or b == 10 for b in inhalt), "nur druckbares ASCII")
        parser = configparser.ConfigParser()
        parser.read_string(inhalt.decode("ascii"))
        self.assertEqual(parser.get("DEFAULT", "Prompt"), "never")

    def test_alter_hinweis_wird_geleert(self):
        schreiben(self.hinweis, "New release '28.04 LTS' available.\nRun 'do-release-upgrade' to upgrade to it.\n")
        self.assertIn(f"aenderung: {self.hinweis}", self.lauf())
        self.assertEqual(os.path.getsize(self.hinweis), 0)
        self.assertEqual(self.lauf(), [], "zweiter Lauf: 0 Änderungen")

    def test_leerer_hinweis_bleibt(self):
        schreiben(self.hinweis, "")
        self.lauf()
        self.assertEqual(self.lauf(), [])
        self.assertEqual(os.path.getsize(self.hinweis), 0)


@unittest.skipUnless(BASH, "bash fehlt")
class Doctor(unittest.TestCase):
    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-basis-doctor.")
        self.addCleanup(shutil.rmtree, self.ziel, True)
        self.ordner = os.path.join(self.ziel, "etc", "update-manager")
        self.dropin = os.path.join(self.ordner, "release-upgrades.d", "zenos.cfg")

    def doctor(self):
        r = subprocess.run([BASH, "-c", DOCTOR_RAHMEN], capture_output=True, text=True, check=False,
                           env={"PATH": "/usr/bin:/bin", "DOCTOR": DOCTOR, "ZIEL": self.ziel})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        zeilen = [z for z in r.stdout.splitlines() if not z.startswith("abschnitt: ")]
        self.assertEqual(len(zeilen), 1, r.stdout)
        return zeilen[0]

    def mit_dropin(self):
        os.makedirs(os.path.dirname(self.dropin), exist_ok=True)
        shutil.copy(DROPIN, self.dropin)

    def test_ohne_alles(self):
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «normal», nicht «never»"), zeile)
        self.assertIn("fehlt, install.sh legt ihn an", zeile)

    def test_wie_auf_dem_geraet(self):
        schreiben(os.path.join(self.ordner, "release-upgrades"), UBUNTU_RELEASE_UPGRADES)
        schreiben(os.path.join(self.ordner, "release-upgrades.d", "ubuntu-advantage-upgrades.cfg"), UBUNTU_ADVANTAGE)
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «lts»"), zeile)
        self.mit_dropin()
        self.assertEqual(self.doctor(), f"ok: Kein Wechsel der Ubuntu-Hauptversion: Prompt=never ({self.dropin})")

    def test_spaetere_datei_gewinnt(self):
        self.mit_dropin()
        schreiben(os.path.join(self.ordner, "release-upgrades.d", "zz-eigen.cfg"), "[DEFAULT]\nprompt = Normal\n")
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «normal»"), zeile)
        self.assertIn("zz-eigen.cfg gilt nach", zeile)
        self.assertEqual(prompt_wie_metarelease(self.ordner), "normal", "dasselbe wie der Release-Upgrader")

    def test_dropin_veraendert(self):
        schreiben(os.path.join(self.ordner, "release-upgrades"), UBUNTU_RELEASE_UPGRADES)
        schreiben(self.dropin, "[DEFAULT]\n# Prompt=never\n")
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «lts»"), zeile)
        self.assertIn("weicht ab, install.sh stellt ihn wieder her", zeile)

    def test_schreibweisen(self):
        faelle = (("[DEFAULT]\nPrompt=never\n", "ok"), ("[DEFAULT]\nPROMPT: No\n", "ok"),
                  ("[DEFAULT]\nprompt =  never  \n", "ok"), ("[Sources]\nPrompt=never\n", "warnung"),
                  ("[DEFAULT]\nPrompt=lts\n", "warnung"), ("[DEFAULT]\nPrompt=never\nPrompt=lts\n", "warnung"))
        for text, erwartet in faelle:
            with self.subTest(text=text):
                schreiben(self.dropin, text)
                self.assertTrue(self.doctor().startswith(erwartet + ": "), text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
