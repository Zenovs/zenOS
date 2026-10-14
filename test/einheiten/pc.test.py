#!/usr/bin/env python3
"""Einheitentests für den Abschnitt «PC: Systemplatte und Start» von zen doctor (scripts/doctor.d/74-pc.sh).

Ohne root und ohne das System anzufassen: Jeder Test baut einen kleinen sysfs-Baum (_PC_SYS), dazu falsche dpkg und
findmnt im PATH. Geprüft wird LVM auf LUKS wie beim Ubuntu-Installer, eine Platte ohne Verschlüsselung, Secure Boot an
und aus, Start im BIOS-Modus und dass der Abschnitt auf dem Pi (arm64) schweigt.

  python3 test/einheiten/pc.test.py
"""

import os
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "74-pc.sh")
EFIVAR = "firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"

LAUF = r"""
set -uo pipefail
abschnitt() { printf 'abschnitt %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
hinweis() { printf 'hinweis %s\n' "$*"; }
warnung() { printf 'warnung %s\n' "$*"; }
fehler() { printf 'fehler %s\n' "$*"; }
source "$1"
_PC_SYS=$2
pruefe_pc
"""


class Pc(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sys = os.path.join(self.tmp.name, "sys")
        self.bin = os.path.join(self.tmp.name, "bin")
        os.makedirs(self.bin)
        self.programm("dpkg", 'echo "${ARCH:-amd64}"')
        self.programm("findmnt", 'echo " ${WURZEL_NUMMER:-252:1}"')

    def programm(self, name, zeile):
        pfad = os.path.join(self.bin, name)
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(f"#!/bin/sh\n{zeile}\n")
        os.chmod(pfad, 0o755)

    def datei(self, pfad, inhalt, binaer=False):
        voll = os.path.join(self.sys, pfad)
        os.makedirs(os.path.dirname(voll), exist_ok=True)
        with open(voll, "wb" if binaer else "w", **({} if binaer else {"encoding": "utf-8"})) as f:
            f.write(inhalt)

    def geraet(self, nummer, dm_uuid=None, unter=()):
        self.datei(f"dev/block/{nummer}/dev", nummer + "\n")
        if dm_uuid is not None:
            self.datei(f"dev/block/{nummer}/dm/uuid", dm_uuid + "\n")
        os.makedirs(os.path.join(self.sys, f"dev/block/{nummer}/slaves"), exist_ok=True)
        for n in unter:
            # wie in sysfs: slaves/<name> zeigt auf das Gerät, darin die Datei dev
            os.symlink(os.path.join(self.sys, f"dev/block/{n}"),
                       os.path.join(self.sys, f"dev/block/{nummer}/slaves/{n.replace(':', '_')}"))

    def secure_boot(self, wert):
        self.datei(EFIVAR, bytes([6, 0, 0, 0, wert]), binaer=True)

    def lauf(self, **env):
        umgebung = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"], **env)
        r = subprocess.run(["bash", "-c", LAUF, "pc", DOCTOR, self.sys], capture_output=True, text=True, timeout=30,
                           check=False, env=umgebung)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def test_lvm_auf_luks_und_secure_boot(self):
        # Ubuntu-Installer: Partition 259:2 → dm-crypt 252:0 → LVM 252:1 (Wurzel)
        self.geraet("259:2")
        self.geraet("252:0", "CRYPT-LUKS2-0123456789abcdef-dm_crypt-0", ["259:2"])
        self.geraet("252:1", "LVM-abcdef", ["252:0"])
        self.secure_boot(1)
        aus = self.lauf()
        self.assertIn("ok Systemplatte verschlüsselt (LUKS)", aus)
        self.assertIn("ok Secure Boot an", aus)
        self.assertNotIn("warnung", aus)

    def test_ohne_verschluesselung_secure_boot_aus(self):
        self.geraet("259:2")
        self.secure_boot(0)
        aus = self.lauf(WURZEL_NUMMER="259:2")
        self.assertIn("warnung Systemplatte nicht verschlüsselt", aus)
        self.assertIn("warnung Secure Boot ist aus", aus)
        self.assertNotIn("259", aus.replace("WURZEL", ""))

    def test_bios(self):
        self.geraet("259:2")
        aus = self.lauf(WURZEL_NUMMER="259:2")
        self.assertIn("warnung Start ohne UEFI", aus)

    def test_unbekannt(self):
        os.makedirs(os.path.join(self.sys, "firmware", "efi"))
        aus = self.lauf(WURZEL_NUMMER="0:31")
        self.assertIn("hinweis Verschlüsselung der Systemplatte nicht feststellbar", aus)
        self.assertIn("hinweis Secure Boot nicht feststellbar", aus)

    def test_pi_schweigt(self):
        self.assertEqual(self.lauf(ARCH="arm64"), "")


if __name__ == "__main__":
    unittest.main()
