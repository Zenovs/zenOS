#!/usr/bin/env python3
"""Einheitentests für «zen energie» (scripts/zen.d/energie.sh): status und aus.

Ohne Sitzung: Jeder Test hat einen eigenen Baum mit einer Kopie von scripts/zen, scripts/lib/gemeinsam.sh und
scripts/zen.d/energie.sh. Daneben stehen Attrappen von «zen lock» (zen.d/lock.sh), zenos-idle und zenos-bildschirm,
dazu falsche systemctl und pgrep in einem PATH, der sonst nur die nötigen Werkzeuge enthält. Alle Attrappen schreiben
ihre Aufrufe der Reihe nach in eine gemeinsame Datei. Geprüft wird vor allem die Leitplanke «dunkel heisst gesperrt»:
ohne bestätigte Sperre weder SIGUSR1 an zenos-idle noch «zenos-bildschirm aus».

  python3 test/einheiten/zen-energie.test.py
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENERGIE = os.path.join(WURZEL, "scripts", "zen.d", "energie.sh")
LOGIK = os.path.join(WURZEL, "shell", "modi", "zustandslogik.js")
RC_XML = os.path.join(WURZEL, "system", "labwc", "rc.xml.in")
WERKZEUGE = ["bash", "python3", "timeout", "sed", "head", "tail", "readlink", "dirname", "cat", "sleep", "id", "find",
             "sort", "env"]

# Attrappe: schreibt {"wer", "argv"} als JSON-Zeile. Verhalten aus Dateien im Testordner:
#   <wer>.exit  Exit-Code (Standard 0)
#   <wer>.aus   Ausgabe auf stdout
# systemctl: <wer>.exit.<unterbefehl> (is-active, show, kill) geht vor <wer>.exit
ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, sys
WER = %r
ORDNER = os.environ["ENERGIE_TEST"]
def datei(name):
    try:
        with open(os.path.join(ORDNER, WER + "." + name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"wer": WER, "argv": sys.argv[1:]}) + "\n")
unter = next((a for a in sys.argv[1:] if not a.startswith("-")), "")
aus = datei("aus." + unter) if WER == "systemctl" else None
aus = aus if aus is not None else datei("aus")
if aus is not None:
    print(aus, end="")
code = datei("exit." + unter) if WER == "systemctl" else None
sys.exit(int(code if code is not None else datei("exit") or 0))
'''

# zen lock als zen.d-Modul: meldet sich und endet mit lock.exit (Standard 0)
LOCK = r'''# hilfe: lock – Attrappe für die Einheitentests
# shellcheck shell=bash
befehl_lock() {
  printf '{"wer": "lock", "argv": []}\n' >> "$ENERGIE_TEST/ereignisse"
  local code=0
  [[ ! -f "$ENERGIE_TEST/lock.exit" ]] || code=$(cat "$ENERGIE_TEST/lock.exit")
  return "$code"
}
'''


class ZenEnergieTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-zen-energie-test.")
        self.skripte = os.path.join(self.wurzel, "scripts")
        self.bin = os.path.join(self.skripte, "bin")
        self.fake = os.path.join(self.wurzel, "fake")
        self.werkzeuge = os.path.join(self.wurzel, "werkzeuge")
        self.lz = os.path.join(self.wurzel, "run")
        self.home = os.path.join(self.wurzel, "home")
        for ordner in (self.bin, os.path.join(self.skripte, "zen.d"), os.path.join(self.skripte, "lib"), self.fake,
                       self.werkzeuge, self.lz, self.home):
            os.makedirs(ordner, exist_ok=True)
        os.chmod(self.lz, 0o700)
        shutil.copy2(os.path.join(WURZEL, "scripts", "zen"), os.path.join(self.skripte, "zen"))
        shutil.copy2(os.path.join(WURZEL, "scripts", "lib", "gemeinsam.sh"), os.path.join(self.skripte, "lib"))
        shutil.copy2(ENERGIE, os.path.join(self.skripte, "zen.d", "energie.sh"))
        with open(os.path.join(self.skripte, "zen.d", "lock.sh"), "w", encoding="utf-8") as f:
            f.write(LOCK)
        self.attrappe(os.path.join(self.bin, "zenos-bildschirm"), "bildschirm")
        self.attrappe(os.path.join(self.bin, "zenos-idle"), "idle")
        self.attrappe(os.path.join(self.bin, "zenos-energie"), "helfer")
        for name in ("systemctl", "pgrep"):
            self.attrappe(os.path.join(self.fake, name), name)
        for name in WERKZEUGE:
            pfad = shutil.which(name)
            self.assertIsNotNone(pfad, name)
            os.symlink(pfad, os.path.join(self.werkzeuge, name))
        # Standard: zenos-idle läuft nicht
        self.verhalten("systemctl", "exit.is-active", "3")

    def tearDown(self):
        shutil.rmtree(self.wurzel, ignore_errors=True)

    def attrappe(self, pfad, wer):
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(ATTRAPPE % wer)
        os.chmod(pfad, 0o755)

    def verhalten(self, wer, art, inhalt):
        with open(os.path.join(self.wurzel, f"{wer}.{art}"), "w", encoding="utf-8") as f:
            f.write(inhalt)

    def vergessen(self, *dateien):
        for datei in dateien:
            pfad = os.path.join(self.wurzel, datei)
            if os.path.exists(pfad):
                os.remove(pfad)

    def zen(self, *argumente):
        umgebung = {
            "PATH": self.fake + os.pathsep + self.werkzeuge,
            "HOME": self.home,
            "XDG_RUNTIME_DIR": self.lz,
            "ENERGIE_TEST": self.wurzel,
            "ZENOS_ENERGIE_PAUSE": "0",
            "LANG": "C.UTF-8",
        }
        lauf = subprocess.run([os.path.join(self.skripte, "zen"), "energie", *argumente], env=umgebung,
                              capture_output=True, text=True, timeout=30)
        return lauf.returncode, lauf.stdout, lauf.stderr

    def ereignisse(self):
        try:
            with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def wer(self):
        return [e["wer"] for e in self.ereignisse()]

    def usr1(self):
        return [e for e in self.ereignisse() if e["wer"] == "systemctl" and "kill" in e["argv"]]

    def bildschirm_aus(self):
        return [e for e in self.ereignisse() if e["wer"] == "bildschirm" and e["argv"] == ["aus"]]

    # --- aus

    def test_ohne_sperre_bleibt_der_bildschirm_an(self):
        for code in ("1", "3"):
            with self.subTest(lock=code):
                self.vergessen("ereignisse")
                self.verhalten("lock", "exit", code)
                self.verhalten("systemctl", "exit.is-active", "0")
                rc, _, fehler = self.zen("aus")
                self.assertEqual(rc, int(code))
                self.assertIn("bleibt an", fehler)
                self.assertEqual(self.wer(), ["lock"])
                self.assertEqual(self.usr1(), [])
                self.assertEqual(self.bildschirm_aus(), [])

    def test_mit_zenos_idle_ueber_usr1(self):
        self.verhalten("systemctl", "exit.is-active", "0")
        self.verhalten("systemctl", "aus.show", "4242\n")
        rc, aus, fehler = self.zen("aus")
        self.assertEqual((rc, fehler), (0, ""))
        self.assertIn("Bildschirm aus", aus)
        reihe = self.wer()
        self.assertEqual(reihe[0], "lock", "zuerst sperren")
        self.assertEqual(self.bildschirm_aus(), [])
        self.assertEqual([e["argv"] for e in self.usr1()],
                         [["--user", "kill", "--kill-whom=main", "--signal=USR1", "zenos-idle.service"]])
        # swayidle als Kind von zenos-idle, und es kann den Bildschirm ausschalten
        pgrep = [e["argv"] for e in self.ereignisse() if e["wer"] == "pgrep"]
        self.assertEqual(len(pgrep), 1)
        self.assertIn("-P", pgrep[0])
        self.assertEqual(pgrep[0][pgrep[0].index("-P") + 1], "4242")
        self.assertTrue(re.search(pgrep[0][-1], "swayidle -w timeout 360 /opt/zenos/scripts/bin/zenos-bildschirm aus"))
        self.assertLess(reihe.index("lock"), reihe.index("pgrep"))

    def test_ohne_zenos_idle_direkt(self):
        rc, aus, fehler = self.zen("aus")
        self.assertEqual((rc, fehler), (0, ""))
        self.assertIn("Eine Taste weckt ihn", aus)
        self.assertEqual(self.usr1(), [])
        reihe = self.wer()
        self.assertEqual(reihe[0], "lock")
        self.assertEqual(len(self.bildschirm_aus()), 1)
        self.assertEqual(reihe[-1], "bildschirm")

    def test_ohne_swayidle_oder_ohne_signal_direkt(self):
        faelle = {
            "pgrep findet nichts": [("pgrep", "exit", "1")],
            "MainPID 0": [("systemctl", "aus.show", "0\n")],
            "kill scheitert": [("systemctl", "exit.kill", "1")],
        }
        for name, verhalten in faelle.items():
            with self.subTest(name):
                self.vergessen("ereignisse", "pgrep.exit", "systemctl.exit.kill")
                self.verhalten("systemctl", "exit.is-active", "0")
                self.verhalten("systemctl", "aus.show", "4242\n")
                for eintrag in verhalten:
                    self.verhalten(*eintrag)
                rc, _, fehler = self.zen("aus")
                self.assertEqual((rc, fehler), (0, ""))
                self.assertEqual(len(self.bildschirm_aus()), 1)
                self.assertEqual(self.wer()[0], "lock")

    def test_bildschirm_scheitert(self):
        self.verhalten("bildschirm", "exit", "1")
        rc, _, fehler = self.zen("aus")
        self.assertEqual(rc, 1)
        self.assertIn("bleibt an", fehler)

    def test_falscher_aufruf(self):
        for argumente in (["foo"], ["aus", "jetzt"], ["status", "x"]):
            with self.subTest(argumente=argumente):
                rc, _, fehler = self.zen(*argumente)
                self.assertEqual(rc, 2)
                self.assertTrue(fehler.startswith("zen: "), fehler)
        self.assertEqual(self.ereignisse(), [])

    # --- status

    def test_status_zeitleiste_aus_zenos_idle(self):
        self.verhalten("idle", "aus", "sperre 7 einstellung\nbildschirm 3 begrenzt\nausschalten 90 einstellung\n"
                                      "ausschaltenwenn immer einstellung\ntaste menue einstellung\n")
        self.verhalten("bildschirm", "aus", "aus\n")
        self.verhalten("helfer", "aus", "nein: tmux läuft\n")
        self.verhalten("helfer", "exit", "1")
        rc, aus, fehler = self.zen("status")
        self.assertEqual((rc, fehler), (0, ""))
        zeilen = aus.splitlines()
        self.assertEqual(zeilen[0], "Ohne Eingabe       gesperrt nach 7 Min. · Bildschirm aus nach 10 Min.")
        self.assertIn("ausserhalb von 1–10, begrenzt", aus)
        self.assertIn("Ausschalten        nach 90 Min. gesperrt, mit 60 s Vorwarnung", zeilen)
        self.assertIn("Zurzeit            nicht möglich: tmux läuft", zeilen)
        self.assertIn("Ein/Aus-Taste      System-Menü (gesperrt: Bildschirm an oder aus)", zeilen)
        self.assertIn("Bildschirm jetzt   aus", zeilen)
        self.assertTrue(any(z.startswith("Bereitschaft       ") for z in zeilen))
        self.assertIn("zen energie aus", aus)
        # Nur lesen: kein Sperren, kein Schalten, kein Ausschalten
        self.assertNotIn("lock", self.wer())
        self.assertEqual([e["argv"] for e in self.ereignisse() if e["wer"] == "bildschirm"], [["status"]])
        self.assertEqual([e["argv"] for e in self.ereignisse() if e["wer"] == "idle"], [["energie"]])
        self.assertEqual([e["argv"] for e in self.ereignisse() if e["wer"] == "helfer"], [["status"]])

    def test_status_ausschalten(self):
        faelle = [
            ("ausschalten 60 standard\nausschaltenwenn akku standard\n", "ja\n",
             ["Ausschalten        nach 60 Min. gesperrt im Akkubetrieb, mit 60 s Vorwarnung · Standard",
              "Zurzeit            möglich, nichts im Weg"]),
            ("ausschalten 240 begrenzt\nausschaltenwenn akku einstellung\n", "ja\n",
             ["Ausschalten        nach 240 Min. gesperrt im Akkubetrieb, mit 60 s Vorwarnung · Wert in "
              "einstellungen.json ausserhalb von 30–240, begrenzt"]),
            ("ausschalten 60 standard\nausschaltenwenn akku ungueltig\n", "",
             ["Ausschalten        nach 60 Min. gesperrt im Akkubetrieb, mit 60 s Vorwarnung · Wert in "
              "einstellungen.json ungültig, es gilt der Standard", "Zurzeit            unbekannt (zenos-energie status)"]),
            ("ausschalten 60 standard\nausschaltenwenn nie einstellung\ntaste ausschalten einstellung\n", "ja\n",
             ["Ausschalten        nie", "Ein/Aus-Taste      ausschalten (logind)"]),
        ]
        for idle, helfer, erwartet in faelle:
            with self.subTest(idle=idle):
                self.vergessen("ereignisse")
                self.verhalten("idle", "aus", "sperre 5 standard\nbildschirm 1 standard\n" + idle)
                self.verhalten("helfer", "aus", helfer)
                rc, aus, _ = self.zen("status")
                self.assertEqual(rc, 0)
                for zeile in erwartet:
                    self.assertIn(zeile, aus.splitlines())
                if "nie" in idle:
                    self.assertFalse(any(z.startswith("Zurzeit") for z in aus.splitlines()))
                    self.assertEqual([e for e in self.ereignisse() if e["wer"] == "helfer"], [])

    def test_status_ohne_sitzung_und_standard(self):
        self.verhalten("idle", "exit", "1")
        self.verhalten("bildschirm", "exit", "3")
        os.remove(os.path.join(self.bin, "zenos-energie"))
        rc, aus, _ = self.zen()
        self.assertEqual(rc, 0)
        self.assertIn("gesperrt nach 5 Min. · Bildschirm aus nach 6 Min.", aus)
        self.assertIn("Bildschirm jetzt   keine laufende Sitzung", aus)
        self.assertIn("Zurzeit            unbekannt (zenos-energie fehlt)", aus)
        self.assertIn("Ein/Aus-Taste      sperren und Bildschirm aus (gesperrt: Bildschirm an oder aus) · Standard", aus)

    # --- Abgleich

    def test_hoechstdauer_wie_leitplanke(self):
        with open(LOGIK, encoding="utf-8") as f:
            js = re.search(r"sperreTrotzHemmerMinuten:\s*(\d+)", f.read())
        with open(ENERGIE, encoding="utf-8") as f:
            sh = re.search(r"^_ENERGIE_HEMMER_MINUTEN=(\d+)$", f.read(), re.M)
        self.assertIsNotNone(js)
        self.assertIsNotNone(sh)
        self.assertEqual(js.group(1), sh.group(1))

    def test_tastenkuerzel_ruft_zen_energie_aus(self):
        with open(RC_XML, encoding="utf-8") as f:
            xml = f.read()
        treffer = re.search(r'<keybind key="W-S-l">\s*<action name="Execute" command="@@ZEN@@ energie aus" />', xml)
        self.assertIsNotNone(treffer)


if __name__ == "__main__":
    unittest.main()
