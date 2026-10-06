#!/usr/bin/env python3
"""Einheitentest für die Prüfung «sudo ohne Passwort» in zen doctor (scripts/doctor.d/00-basis.sh,
_basis_sudo_passwort).

Befund sich-03/inst-01: Legt der Raspberry Pi Imager (bis 2.0.10 oder mit «passwordlessSudo») den Benutzer an,
schreibt cloud-init eine eigene sudo-Regel ohne Passwort. zen doctor prüfte nur die Regel aus dem Bau und zeigte
sonst ✓. Jetzt fragt es «sudo -n -k true» (nur erkennen, nichts ändern) und warnt, wenn das ohne Passwort geht.
Ein falsches sudo im PATH schreibt seine Argumente auf und endet, wie der Test es vorgibt. Als root sagt die Prüfung
nichts (root braucht kein Passwort für sudo). Ohne Netz, ohne echtes sudo:

  python3 test/einheiten/doctor-sudo.test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "00-basis.sh")

# Ausgaben von zen doctor als Liste «art: text»
DOCTOR_TEIL = r"""
abschnitt() { :; }
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$1"
_basis_sudo_passwort
"""

SUDO_ATTRAPPE = """#!/bin/sh
printf '%s\\n' "$*" >> "$SUDO_TEST/aufrufe"
exit "$(cat "$SUDO_TEST/exit")"
"""


@unittest.skipUnless(shutil.which("bash"), "bash fehlt")
class SudoOhnePasswort(unittest.TestCase):
    def setUp(self):
        self.ordner = tempfile.mkdtemp(prefix="zenos-doctor-sudo-test.")
        self.addCleanup(shutil.rmtree, self.ordner, ignore_errors=True)
        sudo = os.path.join(self.ordner, "sudo")
        with open(sudo, "w", encoding="utf-8") as f:
            f.write(SUDO_ATTRAPPE)
        os.chmod(sudo, 0o755)

    def doctor(self, exit_code):
        with open(os.path.join(self.ordner, "exit"), "w", encoding="utf-8") as f:
            f.write(f"{exit_code}\n")
        umgebung = {"PATH": self.ordner + os.pathsep + "/usr/bin:/bin", "SUDO_TEST": self.ordner, "LANG": "C.UTF-8"}
        lauf = subprocess.run(["bash", "-c", DOCTOR_TEIL, "test", DOCTOR], capture_output=True, text=True,
                              env=umgebung, timeout=30, check=False)
        self.assertEqual((lauf.returncode, lauf.stderr), (0, ""))
        return [z for z in lauf.stdout.splitlines() if z.strip()]

    def aufrufe(self):
        try:
            with open(os.path.join(self.ordner, "aufrufe"), encoding="utf-8") as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    @unittest.skipIf(os.geteuid() == 0, "als root sagt die Prüfung nichts (eigener Test)")
    def test_ohne_passwort_warnt(self):
        ausgabe = self.doctor(0)
        self.assertEqual(len(ausgabe), 1)
        self.assertTrue(ausgabe[0].startswith("warnung: sudo geht ohne Passwort"), ausgabe)
        self.assertIn("90-cloud-init-users", ausgabe[0])
        self.assertEqual(self.aufrufe(), ["-n -k true"], "nur erkennen: nie ohne -n, nie mit gemerkter Anmeldung")

    @unittest.skipIf(os.geteuid() == 0, "als root sagt die Prüfung nichts (eigener Test)")
    def test_mit_passwort_ok(self):
        self.assertEqual(self.doctor(1), ["ok: sudo nur mit Passwort"])
        self.assertEqual(self.aufrufe(), ["-n -k true"])

    @unittest.skipUnless(os.geteuid() == 0, "nur als root")
    def test_als_root_nichts(self):
        self.assertEqual(self.doctor(0), [])
        self.assertEqual(self.aufrufe(), [], "als root fragt die Prüfung sudo nicht")


if __name__ == "__main__":
    unittest.main(verbosity=1)
