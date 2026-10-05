#!/usr/bin/env python3
"""Einheitentests für scripts/module/12-vertrauen.sh: Wann kommt der Vertrauensanker aus system/vertrauen auf das
Gerät?

Prüfung von Schritt 4, Befund 7: Ein leerer Anker wurde automatisch aus dem Repo gefüllt, sobald system/vertrauen
Schlüssel hatte, auch aus einem Stand, der ungeprüft kam (dev mit «ja»). Jetzt füllt ihn das Modul nur im Image;
sonst nennt es den Weg von Hand («sudo zen kanal anker»).

Das Modul läuft in bash mit Attrappen für die Hilfsfunktionen von install.sh, gegen einen Anker-Ordner im Temp-Ordner
und mit dem echten zenos-kanal (anker --pruefen). Wegwerf-Schlüssel entstehen zur Laufzeit. Ohne Root, ohne Netz.

  python3 test/einheiten/kanal-vertrauen.test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODUL = os.path.join(WURZEL, "scripts", "module", "12-vertrauen.sh")
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-kanal")
BASH = shutil.which("bash")
SSH_KEYGEN = shutil.which("ssh-keygen")

RAHMEN = r'''
set -u
ordner_sicherstellen() { mkdir -p -- "$1"; }
datei_installieren() { cp -- "$1" "$2"; }
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
aenderung() { printf 'aenderung: %s\n' "$*"; }
abbruch() { printf 'abbruch: %s\n' "$*"; exit 1; }
source "$MODUL"
_VERTRAUEN_ZIEL=$ZIEL
_vertrauen_rechte() { :; }
modul_system
'''


@unittest.skipUnless(BASH and SSH_KEYGEN and os.access("/usr/bin/python3", os.X_OK), "bash, ssh-keygen oder python3")
class Vertrauen(unittest.TestCase):
    def setUp(self):
        self.ordner = tempfile.mkdtemp(prefix="zenos-vertrauen-test.")
        self.addCleanup(shutil.rmtree, self.ordner, True)
        self.code = os.path.join(self.ordner, "opt-zenos")
        os.makedirs(os.path.join(self.code, "scripts", "bin"))
        shutil.copy(PROGRAMM, os.path.join(self.code, "scripts", "bin", "zenos-kanal"))
        self.quelle = os.path.join(self.code, "system", "vertrauen")
        self.ziel = os.path.join(self.ordner, "etc-zenos", "vertrauen")
        os.makedirs(os.path.dirname(self.ziel))
        schluessel = {}
        for name in ("rel", "wur"):
            pfad = os.path.join(self.ordner, name)
            subprocess.run([SSH_KEYGEN, "-q", "-t", "ed25519", "-N", "", "-C", "", "-f", pfad], check=True)
            with open(pfad + ".pub", encoding="utf-8") as f:
                schluessel[name] = " ".join(f.read().split()[:2])
        self.voll = {
            "release": f'zenos-release namespaces="git" {schluessel["rel"]}\n',
            "wurzel": f'zenos-wurzel namespaces="git" {schluessel["wur"]}\n',
            "widerrufen": "# keine\n",
            "serie": "1\n",
        }
        self.leer = {name: "# noch ohne Schlüssel\n" for name in self.voll}

    def anker(self, ordner, texte):
        os.makedirs(ordner, exist_ok=True)
        for name, text in texte.items():
            with open(os.path.join(ordner, name), "w", encoding="utf-8") as f:
                f.write(text)

    def modul(self, image=False):
        env = {"PATH": "/usr/bin:/bin", "MODUL": MODUL, "ZIEL": self.ziel, "ZENOS_CODE": self.code, "SUDO": "",
               "ZENOS_IMAGE": "1" if image else "0", "LC_ALL": "C.UTF-8"}
        r = subprocess.run([BASH, "-c", RAHMEN], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout

    def zustand(self):
        r = subprocess.run(["/usr/bin/python3", "-I", PROGRAMM, "anker", "--pruefen", self.ziel],
                           capture_output=True, text=True, check=False)
        return r.stdout.split(":")[0]

    def test_leerer_anker_bleibt_leer(self):
        """Angriff (Befund 7): Ein Stand mit Schlüsseln, ungeprüft per «ja» installiert, füllte den leeren Anker."""
        self.anker(self.ziel, self.leer)
        self.anker(self.quelle, self.voll)
        aus = self.modul()
        self.assertEqual(self.zustand(), "leer")
        self.assertIn("sudo zen kanal anker", aus)
        self.assertNotIn("aenderung", aus)

    def test_fehlender_anker_ohne_image(self):
        self.anker(self.quelle, self.voll)
        aus = self.modul()
        self.assertTrue(os.path.isdir(self.ziel))
        self.assertEqual(self.zustand(), "leer")
        self.assertIn("sudo zen kanal anker", aus)

    def test_im_image_aus_dem_repo(self):
        self.anker(self.quelle, self.voll)
        self.modul(image=True)
        self.assertEqual(self.zustand(), "vollständig")
        shutil.rmtree(self.ziel)
        self.anker(self.ziel, self.leer)
        self.modul(image=True)
        self.assertEqual(self.zustand(), "vollständig")

    def test_repo_ohne_schluessel(self):
        self.anker(self.quelle, self.leer)
        self.modul()
        self.assertEqual(self.zustand(), "leer")
        aus = self.modul()
        self.assertIn("noch ohne Schlüssel", aus)

    def test_vorhandener_anker_bleibt(self):
        self.anker(self.ziel, self.voll)
        anders = dict(self.voll, serie="2\n")
        self.anker(self.quelle, anders)
        self.modul(image=True)
        with open(os.path.join(self.ziel, "serie"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "1\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
