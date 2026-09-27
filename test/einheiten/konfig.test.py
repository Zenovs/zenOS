#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-konfig (Schema, Prüfungen über das Schema hinaus, Schreiben, Meldungen).

Läuft mit einem leeren Test-HOME, braucht python3-jsonschema: python3 test/einheiten/konfig.test.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KONFIG = os.path.join(WURZEL, "scripts", "bin", "zenos-konfig")
VORLAGEN_RASTER = os.path.join(WURZEL, "config", "vorlagen", "raster")


def raster(*bereiche, **mehr):
    daten = {"name": "Test", "bereiche": [dict(zip(("id", "x", "y", "b", "h"), b)) for b in bereiche]}
    daten.update(mehr)
    return daten


class KonfigTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="zenos-konfig-test.")
        self.umgebung = {"HOME": self.home, "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C.UTF-8"}

    def tearDown(self):
        shutil.rmtree(self.home, ignore_errors=True)

    def aufruf(self, *args, eingabe=None):
        ergebnis = subprocess.run([KONFIG, *args], input=None if eingabe is None else json.dumps(eingabe),
                                  capture_output=True, text=True, env=self.umgebung, timeout=30, check=False)
        return ergebnis.returncode, ergebnis.stdout, ergebnis.stderr

    def pfad(self, *teile):
        return os.path.join(self.home, ".config", "zenos", *teile)

    # --- Raster: was das Schema nicht kann

    def test_vorlagen_sind_gueltig(self):
        for name in sorted(os.listdir(VORLAGEN_RASTER)):
            with open(os.path.join(VORLAGEN_RASTER, name), encoding="utf-8") as f:
                daten = json.load(f)
            code, _, fehler = self.aufruf("schreibe", "raster", name[:-5], eingabe=daten)
            self.assertEqual(code, 0, f"{name}: {fehler}")

    def test_rand_genau_100_ist_erlaubt(self):
        code, _, fehler = self.aufruf("schreibe", "raster", "rand", eingabe=raster(("a", 0, 0, 50, 100), ("b", 50, 0, 50, 100)))
        self.assertEqual(code, 0, fehler)

    def test_x_plus_b_ueber_100(self):
        code, _, fehler = self.aufruf("schreibe", "raster", "breit", eingabe=raster(("a", 0, 0, 50, 100), ("b", 60, 0, 50, 100)))
        self.assertEqual(code, 1)
        self.assertIn("bereiche/1 – x + b grösser als 100", fehler)
        self.assertFalse(os.path.exists(self.pfad("raster", "breit.json")))

    def test_y_plus_h_ueber_100(self):
        code, _, fehler = self.aufruf("schreibe", "raster", "hoch", eingabe=raster(("a", 0, 30, 100, 71)))
        self.assertEqual(code, 1)
        self.assertIn("bereiche/0 – y + h grösser als 100", fehler)
        self.assertNotIn("x + b", fehler)

    def test_doppelte_bereich_id(self):
        code, _, fehler = self.aufruf("schreibe", "raster", "doppelt", eingabe=raster(("links", 0, 0, 50, 100), ("links", 50, 0, 50, 100)))
        self.assertEqual(code, 1)
        self.assertIn("bereiche/1/id – doppelt", fehler)

    def test_schemafehler_und_zusatzpruefung_zusammen(self):
        # b fehlt beim ersten Bereich (Schema), der zweite ragt hinaus (Zusatz); beides wird gemeldet
        daten = raster(("a", 0, 0, 50, 100), ("b", 90, 0, 20, 100))
        del daten["bereiche"][0]["b"]
        code, _, fehler = self.aufruf("schreibe", "raster", "beides", eingabe=daten)
        self.assertEqual(code, 1)
        self.assertIn("Pflichtfeld fehlt: b", fehler)
        self.assertIn("bereiche/1 – x + b grösser als 100", fehler)

    def test_aendere_prueft_das_ergebnis(self):
        self.assertEqual(self.aufruf("schreibe", "raster", "zwei", eingabe=raster(("a", 0, 0, 50, 100), ("b", 50, 0, 50, 100)))[0], 0)
        code, _, fehler = self.aufruf("aendere", "raster", "zwei", eingabe={"bereiche": [{"id": "a", "x": 10, "y": 0, "b": 95, "h": 100}]})
        self.assertEqual(code, 1)
        self.assertIn("x + b", fehler)
        with open(self.pfad("raster", "zwei.json"), encoding="utf-8") as f:
            self.assertEqual(len(json.load(f)["bereiche"]), 2)

    def test_pruefe_findet_handbearbeitete_datei(self):
        os.makedirs(self.pfad("raster"))
        with open(self.pfad("raster", "hand.json"), "w", encoding="utf-8") as f:
            json.dump(raster(("a", 0, 0, 50, 100), ("a", 50, 0, 60, 100)), f)
        code, ausgabe, _ = self.aufruf("pruefe", "--json")
        self.assertEqual(code, 1)
        bericht = json.loads(ausgabe)
        self.assertEqual(bericht["arten"]["raster"], {"anzahl": 1, "ungueltig": 1, "ohneSchema": False})
        code, ausgabe, _ = self.aufruf("pruefe")
        self.assertIn("raster/hand.json: bereiche/1 – x + b grösser als 100", ausgabe)
        self.assertIn("raster/hand.json: bereiche/1/id – doppelt", ausgabe)

    # --- Bildschirme

    def test_doppelter_profilname(self):
        daten = {"profile": [{"name": "Geheim Eins", "ausgaenge": ["HDMI-A-1"]}, {"name": "Geheim Eins", "ausgaenge": ["*"]}]}
        code, _, fehler = self.aufruf("schreibe", "bildschirme", eingabe=daten)
        self.assertEqual(code, 1)
        self.assertIn("profile/1/name – doppelt", fehler)
        # Meldungen nennen nie Inhalte
        self.assertNotIn("Geheim", fehler)

    def test_verschiedene_profilnamen(self):
        daten = {"profile": [{"name": "Eins", "ausgaenge": ["HDMI-A-1"]}, {"name": "Zwei", "ausgaenge": ["*"]}]}
        self.assertEqual(self.aufruf("schreibe", "bildschirme", eingabe=daten)[0], 0)

    # --- Modi, Schreiben, Aufruf

    def test_unbekannter_akzent(self):
        code, _, fehler = self.aufruf("schreibe", "modi", "arbeit", eingabe={"name": "Arbeit", "akzent": "pink"})
        self.assertEqual(code, 1)
        self.assertIn("akzent", fehler)

    def test_schreiben_nur_bei_aenderung_und_id_aus_dateiname(self):
        daten = {"name": "Arbeit", "akzent": "salbei", "id": "anders"}
        self.assertEqual(self.aufruf("schreibe", "modi", "arbeit", eingabe=daten)[0], 0)
        datei = self.pfad("modi", "arbeit.json")
        with open(datei, encoding="utf-8") as f:
            self.assertNotIn("id", json.load(f))
        os.utime(datei, (1, 1))
        self.assertEqual(self.aufruf("schreibe", "modi", "arbeit", eingabe=daten)[0], 0)
        self.assertEqual(os.stat(datei).st_mtime, 1)
        self.assertEqual(os.stat(self.pfad()).st_mode & 0o777, 0o700)
        code, ausgabe, _ = self.aufruf("liste", "modi")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(ausgabe), [{"name": "Arbeit", "akzent": "salbei", "id": "arbeit"}])

    def test_aendere_laufzeit_null_entfernt(self):
        self.assertEqual(self.aufruf("aendere", "laufzeit", eingabe={"modus": "arbeit", "raster": "voll"})[0], 0)
        self.assertEqual(self.aufruf("aendere", "laufzeit", eingabe={"modus": None})[0], 0)
        code, ausgabe, _ = self.aufruf("lese", "laufzeit")
        self.assertEqual((code, json.loads(ausgabe)), (0, {"raster": "voll"}))

    def test_ungueltige_ids(self):
        for eintrag_id in ("../weg", "Gross", "a_b", "-a", ""):
            code, _, _ = self.aufruf("schreibe", "raster", eintrag_id, eingabe=raster(("a", 0, 0, 100, 100)))
            self.assertEqual(code, 2, eintrag_id)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".config", "weg.json")))


if __name__ == "__main__":
    unittest.main(verbosity=1)
