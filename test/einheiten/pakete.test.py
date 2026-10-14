#!/usr/bin/env python3
"""Einheitentests für die Paketlisten unter scripts/pakete/: die Zeile «# architektur: …» (pakete_liste_gilt in
scripts/lib/gemeinsam.sh) und dieselbe Regel im Abschnitt «Pakete» von zen doctor (scripts/doctor.d/20-sitzung.sh).

Ohne apt und ohne root: Ein falsches dpkg im PATH meldet die Architektur, die der Test vorgibt.

  python3 test/einheiten/pakete.test.py
"""

import os
import re
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEMEINSAM = os.path.join(WURZEL, "scripts", "lib", "gemeinsam.sh")
PAKETE = os.path.join(WURZEL, "scripts", "pakete")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "20-sitzung.sh")

GILT = r"""
set -Eeuo pipefail
source "$1"
if pakete_liste_gilt "$2"; then echo ja; else echo nein; fi
"""


class Architektur(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = os.path.join(self.tmp.name, "bin")
        os.mkdir(self.bin)

    def dpkg(self, arch):
        pfad = os.path.join(self.bin, "dpkg")
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(f'#!/bin/sh\n[ "$1" = --print-architecture ] && echo {arch}\n')
        os.chmod(pfad, 0o755)

    def liste(self, inhalt):
        pfad = os.path.join(self.tmp.name, "liste.txt")
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(inhalt)
        return pfad

    def gilt(self, arch, inhalt):
        self.dpkg(arch)
        env = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"])
        r = subprocess.run(["bash", "-c", GILT, "gilt", GEMEINSAM, self.liste(inhalt)], capture_output=True,
                           text=True, timeout=30, check=False, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip() == "ja"

    def test_ohne_zeile_ueberall(self):
        self.assertTrue(self.gilt("amd64", "# Kommentar\nlabwc\n"))
        self.assertTrue(self.gilt("arm64", "labwc\n"))

    def test_nur_genannte_architektur(self):
        inhalt = "# Lüfter\n# architektur: arm64\npython3-smbus\n"
        self.assertTrue(self.gilt("arm64", inhalt))
        self.assertFalse(self.gilt("amd64", inhalt))

    def test_mehrere_architekturen(self):
        inhalt = "#architektur:  arm64 amd64\npaket\n"
        self.assertTrue(self.gilt("amd64", inhalt))
        self.assertFalse(self.gilt("riscv64", inhalt))

    def test_kein_teilwort(self):
        # «arm64» darf nicht auf «arm» oder «armhf» passen
        self.assertFalse(self.gilt("arm", "# architektur: arm64\n"))

    def test_argon_nur_auf_arm64(self):
        with open(os.path.join(PAKETE, "argon.txt"), encoding="utf-8") as f:
            inhalt = f.read()
        self.assertTrue(self.gilt("arm64", inhalt))
        self.assertFalse(self.gilt("amd64", inhalt))

    def test_doctor_kennt_die_zeile(self):
        # zen doctor lädt gemeinsam.sh nicht; die Regel steht dort ein zweites Mal
        with open(DOCTOR, encoding="utf-8") as f:
            text = f.read()
        self.assertIn("architektur:", text)
        self.assertIn("dpkg --print-architecture", text)

    def test_nur_bekannte_architekturen(self):
        for name in sorted(os.listdir(PAKETE)):
            with open(os.path.join(PAKETE, name), encoding="utf-8") as f:
                for zeile in f:
                    m = re.match(r"^#\s*architektur:\s*(.*)$", zeile)
                    if m:
                        for arch in m.group(1).split():
                            self.assertIn(arch, ("arm64", "amd64"), name)


if __name__ == "__main__":
    unittest.main()
