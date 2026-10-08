#!/usr/bin/env python3
"""Einheitentests für «zen install» (scripts/zen.d/install.sh): Fenster in der Sitzung, Ansicht als Text mit «ja» und
sudo, --liste und --status, falsche Aufrufe.

Ohne Sitzung und ohne Rechte: Jeder Test hat einen eigenen Baum mit einer Kopie von scripts/zen, scripts/lib/gemeinsam.sh
und scripts/zen.d/install.sh. Daneben stehen Attrappen von zenos-installer und zenos-installer-bedienen und ein falsches
sudo in einem PATH, der sonst nur die nötigen Werkzeuge enthält. Alle Attrappen schreiben ihre Aufrufe der Reihe nach
in eine gemeinsame Datei. Die Bestätigung «ja» kommt über ein Pseudo-Terminal (ohne Terminal fragt zen install nicht).

  python3 test/einheiten/zen-install.test.py
"""

import json
import os
import pty
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INSTALL = os.path.join(WURZEL, "scripts", "zen.d", "install.sh")
WERKZEUGE = ["bash", "python3", "realpath", "dirname", "readlink", "cat", "sed", "head", "id", "find", "sort", "env"]
SHA = "3f" * 32
PLAN = "a1" * 20

# Attrappe: schreibt {"wer", "argv"} als JSON-Zeile. Verhalten aus Dateien im Testordner:
#   <wer>.exit.<unterbefehl>, <wer>.exit   Exit-Code (Standard 0)
#   <wer>.aus.<unterbefehl>                Ausgabe auf stdout
# zenos-installer status --json: mit <wer>.letzte (Grund) ein frisches letzte.json zu SHA, sonst ohne letzte
# sudo: führt den Rest der Befehlszeile aus
ATTRAPPE = r'''#!/usr/bin/env python3
import datetime, json, os, sys
WER = %r
ORDNER = os.environ["INSTALL_TEST"]
def datei(name):
    try:
        with open(os.path.join(ORDNER, WER + "." + name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"wer": WER, "argv": sys.argv[1:]}) + "\n")
if WER == "sudo":
    os.execv(sys.argv[1], sys.argv[1:])
unter = sys.argv[1] if len(sys.argv) > 1 else ""
if WER == "installer" and sys.argv[1:] == ["status", "--json"]:
    grund = datei("letzte")
    letzte = None
    if grund is not None:
        ende = datetime.datetime.now(datetime.timezone.utc).strftime("%%Y-%%m-%%dT%%H:%%M:%%SZ")
        letzte = {"version": 1, "art": "installieren", "ergebnis": "installiert", "grund": grund,
                  "sha256": datei("letzte.sha") or %r, "ende": ende}
    print(json.dumps({"version": 1, "laeuft": [], "letzte": letzte, "anzahl": 0, "ablage": 0}))
aus = datei("aus." + unter)
if aus is not None:
    print(aus, end="")
code = datei("exit." + unter)
sys.exit(int(code if code is not None else datei("exit") or 0))
'''

ANSICHT = """Beispiel 1.0 (beispiel, arm64)
  Datei        beispiel.deb (1,0 kB)
  · Startet Systemdienste: beispiel.service.
Ergebnis: Beispiel 1.0 ist bereit zum Installieren.
"""


@unittest.skipUnless(os.path.exists("/proc/self") and shutil.which("realpath"),
                     "nur unter Linux (bash 5, realpath), etwa im Testcontainer oder in der CI")
class ZenInstallTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = os.path.realpath(tempfile.mkdtemp(prefix="zenos-zen-install-test."))
        self.addCleanup(shutil.rmtree, self.wurzel, True)
        self.skripte = os.path.join(self.wurzel, "scripts")
        self.bin = os.path.join(self.skripte, "bin")
        self.fake = os.path.join(self.wurzel, "fake")
        self.werkzeuge = os.path.join(self.wurzel, "werkzeuge")
        self.downloads = os.path.join(self.wurzel, "home", "Downloads")
        for ordner in (self.bin, os.path.join(self.skripte, "zen.d"), os.path.join(self.skripte, "lib"), self.fake,
                       self.werkzeuge, self.downloads):
            os.makedirs(ordner, exist_ok=True)
        shutil.copy2(os.path.join(WURZEL, "scripts", "zen"), os.path.join(self.skripte, "zen"))
        shutil.copy2(os.path.join(WURZEL, "scripts", "lib", "gemeinsam.sh"), os.path.join(self.skripte, "lib"))
        shutil.copy2(INSTALL, os.path.join(self.skripte, "zen.d", "install.sh"))
        self.attrappe(os.path.join(self.bin, "zenos-installer"), "installer")
        self.attrappe(os.path.join(self.bin, "zenos-installer-bedienen"), "helfer")
        self.attrappe(os.path.join(self.fake, "sudo"), "sudo")
        for name in WERKZEUGE:
            pfad = shutil.which(name)
            self.assertIsNotNone(pfad, name)
            os.symlink(pfad, os.path.join(self.werkzeuge, name))
        self.deb = os.path.join(self.downloads, "beispiel 1.0.deb")
        with open(self.deb, "wb") as f:
            f.write(b"!<arch>\n")
        self.verhalten("installer", "aus.ansehen", ANSICHT + f"auftrag {SHA} {PLAN}\n")

    def attrappe(self, pfad, wer):
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(ATTRAPPE % (wer, SHA))
        os.chmod(pfad, 0o755)

    def verhalten(self, wer, art, inhalt):
        with open(os.path.join(self.wurzel, f"{wer}.{art}"), "w", encoding="utf-8") as f:
            f.write(inhalt)

    def zen(self, *argumente, sitzung=False, eingabe=None, cwd=None, mehr=None):
        """zen install …; eingabe: Text über ein Pseudo-Terminal (sonst kein Terminal); mehr: weitere Umgebung."""
        umgebung = {"PATH": self.fake + os.pathsep + self.werkzeuge, "HOME": os.path.join(self.wurzel, "home"),
                    "INSTALL_TEST": self.wurzel, "LANG": "C.UTF-8", **(mehr or {})}
        if sitzung:
            umgebung["WAYLAND_DISPLAY"] = "wayland-1"
        befehl = [os.path.join(self.skripte, "zen"), "install", *argumente]
        if eingabe is None:
            lauf = subprocess.run(befehl, env=umgebung, capture_output=True, text=True, timeout=30,
                                  stdin=subprocess.DEVNULL, cwd=cwd or self.wurzel)
            return lauf.returncode, lauf.stdout, lauf.stderr
        haupt, neben = pty.openpty()
        try:
            os.write(haupt, eingabe.encode())
            lauf = subprocess.run(befehl, env=umgebung, capture_output=True, text=True, timeout=30, stdin=neben,
                                  cwd=cwd or self.wurzel)
        finally:
            os.close(neben)
            os.close(haupt)
        return lauf.returncode, lauf.stdout, lauf.stderr

    def ereignisse(self):
        try:
            with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def aufrufe(self, wer):
        return [e["argv"] for e in self.ereignisse() if e["wer"] == wer]

    # --- Sitzung

    def test_in_der_sitzung_das_fenster(self):
        rc, aus, fehler = self.zen("Downloads/beispiel 1.0.deb", sitzung=True, cwd=os.path.join(self.wurzel, "home"))
        self.assertEqual((rc, fehler), (0, ""))
        self.assertEqual(aus, "Der zen Installer ist offen.\n")
        self.assertEqual(self.aufrufe("installer"), [["oeffnen", self.deb]], "der echte, absolute Pfad")
        self.assertEqual(self.aufrufe("helfer"), [])

    def test_fenster_geht_nicht_auf(self):
        self.verhalten("installer", "exit.oeffnen", "1")
        rc, aus, _ = self.zen(self.deb, sitzung=True)
        self.assertEqual(rc, 1)
        self.assertIn("zen install --text", aus)
        self.assertEqual(self.aufrufe("helfer"), [])

    # --- Text

    def test_text_mit_ja(self):
        self.verhalten("installer", "letzte", "Beispiel 1.0 ist installiert.")
        for sitzung, argumente in ((False, [self.deb]), (True, ["--text", self.deb]), (True, [self.deb, "--text"])):
            with self.subTest(sitzung=sitzung, argumente=argumente):
                if os.path.exists(os.path.join(self.wurzel, "ereignisse")):
                    os.remove(os.path.join(self.wurzel, "ereignisse"))
                rc, aus, fehler = self.zen(*argumente, sitzung=sitzung, eingabe="ja\n")
                self.assertEqual(rc, 0, fehler)
                self.assertIn(ANSICHT, aus)
                self.assertNotIn("auftrag", aus)
                self.assertIn("«ja»", fehler)
                self.assertTrue(aus.rstrip().endswith("Beispiel 1.0 ist installiert."), aus)
                self.assertEqual(self.aufrufe("installer")[0], ["ansehen", self.deb, "--auftrag"])
                helfer = os.path.join(self.bin, "zenos-installer-bedienen")
                if os.geteuid() != 0:
                    self.assertEqual(self.aufrufe("sudo"), [[helfer, "installieren", self.deb, SHA, PLAN]])
                self.assertEqual(self.aufrufe("helfer"), [["installieren", self.deb, SHA, PLAN]])

    def test_text_ohne_ja_ohne_terminal_nichts(self):
        rc, aus, _ = self.zen(self.deb, eingabe="nein\n")
        self.assertEqual(rc, 1)
        self.assertIn("Abgebrochen. Nichts installiert.", aus)
        rc, _, fehler = self.zen(self.deb)
        self.assertEqual(rc, 1)
        self.assertIn("kein Terminal", fehler)
        self.assertEqual(self.aufrufe("helfer"), [])
        self.assertEqual(self.aufrufe("sudo"), [])

    def test_abgelehnt_und_schon_installiert(self):
        self.verhalten("installer", "aus.ansehen", "Ergebnis: Das Paket ist für amd64, dieser Rechner braucht arm64.\n")
        self.verhalten("installer", "exit.ansehen", "3")
        rc, aus, fehler = self.zen(self.deb, eingabe="ja\n")
        self.assertEqual(rc, 3)
        self.assertIn("amd64", aus)
        self.assertNotIn("«ja»", fehler)
        self.verhalten("installer", "aus.ansehen", "Ergebnis: Beispiel 1.0 ist schon installiert.\n")
        self.verhalten("installer", "exit.ansehen", "0")
        rc, aus, fehler = self.zen(self.deb, eingabe="ja\n")
        self.assertEqual(rc, 0)
        self.assertNotIn("«ja»", fehler)
        self.assertEqual(self.aufrufe("helfer"), [])

    def test_helfer_scheitert(self):
        self.verhalten("helfer", "exit.installieren", "1")
        self.verhalten("installer", "letzte", "Die Installation ist gescheitert (apt-get Exit 100).")
        rc, _, fehler = self.zen(self.deb, eingabe="ja\n")
        self.assertEqual(rc, 1)
        self.assertIn("zen: Die Installation ist gescheitert (apt-get Exit 100).", fehler)
        # letzte.json einer anderen Datei zählt nicht
        self.verhalten("installer", "letzte.sha", "00" * 32)
        rc, _, fehler = self.zen(self.deb, eingabe="ja\n")
        self.assertEqual(rc, 1)
        self.assertNotIn("apt-get Exit 100", fehler)
        self.verhalten("helfer", "exit.installieren", "75")
        rc, _, fehler = self.zen(self.deb, eingabe="ja\n")
        self.assertEqual(rc, 75)
        self.assertIn("später noch einmal", fehler)

    def test_nicht_mit_sudo(self):
        """«sudo zen install DATEI»: Das Ansehen liefe als root und hielte Zenos eigene Datei für fremd (Befund B1).
        zen install bricht deshalb mit einem klaren Hinweis ab; es fragt selbst nach dem Passwort. Als root ohne sudo
        (etwa die CI) und als Benutzer mit SUDO_USER in der Umgebung geht es wie sonst."""
        sudo = {"SUDO_USER": "beispiel", "SUDO_UID": "1000"}
        rc, aus, fehler = self.zen(self.deb, eingabe="ja\n", mehr=sudo)
        if os.geteuid() == 0:
            self.assertEqual(rc, 2, aus)
            self.assertIn("zen: zen install läuft ohne sudo und fragt selbst nach dem Passwort: zen install ", fehler)
            self.assertEqual(self.ereignisse(), [])
        else:
            self.assertEqual(rc, 0, fehler)
            self.assertEqual(self.aufrufe("helfer"), [["installieren", self.deb, SHA, PLAN]])
        # Liste und Status gehen auch mit sudo
        for argument in ("--liste", "--status"):
            rc, _, fehler = self.zen(argument, mehr=sudo)
            self.assertEqual(rc, 0, fehler)

    # --- Liste, Status, falsche Aufrufe

    def test_liste_und_status(self):
        self.verhalten("installer", "aus.liste", "Beispiel  beispiel  1.0\n")
        rc, aus, _ = self.zen("--liste")
        self.assertEqual((rc, aus), (0, "Beispiel  beispiel  1.0\n"))
        rc, _, _ = self.zen("--status")
        self.assertEqual(rc, 0)
        self.assertEqual(self.aufrufe("installer"), [["liste"], ["status"]])

    def test_falsche_aufrufe(self):
        anders = os.path.join(self.downloads, "x.zip")
        with open(anders, "w", encoding="utf-8") as f:
            f.write("x")
        for argumente in ((), ("--liste", self.deb), ("--status", "--liste"), ("--x", self.deb), (self.deb, self.deb),
                          (anders,), (os.path.join(self.downloads, "fehlt.deb"),), ("--text",)):
            with self.subTest(argumente=argumente):
                rc, _, fehler = self.zen(*argumente, sitzung=True)
                self.assertEqual(rc, 2, fehler)
                self.assertTrue(fehler.startswith("zen: "), fehler)
        self.assertEqual(self.ereignisse(), [])


if __name__ == "__main__":
    unittest.main()
