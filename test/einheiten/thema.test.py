#!/usr/bin/env python3
"""Einheitentests für die labwc-Werte von scripts/bin/zenos-thema (themerc-override).

Lädt das Programm als Modul und prüft nur die erzeugten Texte; schreibt nichts und schickt kein Signal:
python3 test/einheiten/thema.test.py
"""

import importlib.machinery
import importlib.util
import json
import os
import re
import sys
import unittest

# Kein __pycache__ neben scripts/bin/zenos-thema (das Programm wird als Modul geladen)
sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
THEMA = os.path.join(WURZEL, "scripts", "bin", "zenos-thema")


def thema_laden():
    lader = importlib.machinery.SourceFileLoader("zenos_thema", THEMA)
    spec = importlib.util.spec_from_loader("zenos_thema", lader)
    modul = importlib.util.module_from_spec(spec)
    lader.exec_module(modul)
    return modul


def werte(text):
    """themerc-override → {schlüssel: wert} (Kommentare ausgelassen)."""
    ergebnis = {}
    for zeile in text.splitlines():
        if zeile.startswith("#") or not zeile.strip():
            continue
        schluessel, wert = zeile.split(":", 1)
        ergebnis[schluessel.strip()] = wert.strip()
    return ergebnis


class ThemaLabwcTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.thema = thema_laden()
        cls.tokens = cls.thema.load_tokens()

    def test_fensterwechsler_gross_und_aus_den_tokens(self):
        """Alt+Tab: so breit wie das Befehlsfeld, Abstände aus der Reihe, Symbol 40 px, Rahmen 2 px."""
        abstand = self.tokens["abstand"]
        for modus in ("hell", "dunkel"):
            w = werte(self.thema.labwc_themerc(self.tokens, modus, self.tokens["farben"]["standardAkzent"]))
            klassisch = "osd.window-switcher.style-classic."
            self.assertEqual(w[klassisch + "width"], str(self.tokens["befehlsfeld"]["breite"]), modus)
            self.assertEqual(w[klassisch + "padding"], str(abstand[1]), modus)
            self.assertEqual(w[klassisch + "item.padding.x"], str(abstand[2]), modus)
            self.assertEqual(w[klassisch + "item.padding.y"], str(abstand[1]), modus)
            self.assertEqual(w[klassisch + "item.icon.size"], "40", modus)
            self.assertEqual(w[klassisch + "item.active.border.width"], "2", modus)
            # Farben nur aus den Tokens: Fläche, Rahmen, Auswahl und Akzent des Erscheinungsbilds
            farben = self.tokens["farben"][modus]
            self.assertEqual(w["osd.bg.color"], farben["flaeche"].lower(), modus)
            self.assertEqual(w["osd.border.color"], farben["linie2"].lower(), modus)
            self.assertEqual(w[klassisch + "item.active.bg.color"], farben["flaeche2"].lower(), modus)
            akzent = self.tokens["farben"]["akzente"][self.tokens["farben"]["standardAkzent"]][modus]
            self.assertEqual(w[klassisch + "item.active.border.color"], akzent.lower(), modus)

    def test_jede_zeile_ist_schluessel_und_wert(self):
        text = self.thema.labwc_themerc(self.tokens, "hell", self.tokens["farben"]["standardAkzent"])
        for zeile in text.splitlines():
            if zeile.startswith("#"):
                continue
            self.assertRegex(zeile, r"^[a-z0-9.-]+: \S.*$")
        schluessel = [z.split(":", 1)[0] for z in text.splitlines() if not z.startswith("#")]
        self.assertEqual(len(schluessel), len(set(schluessel)), "doppelte Schlüssel")

    def test_fehlende_abstaende_fallen_auf_die_vorgabe(self):
        tokens = json.loads(json.dumps(self.tokens))
        del tokens["abstand"]
        del tokens["befehlsfeld"]
        w = dict(self.thema.switcher_sizes(tokens))
        self.assertEqual(w["osd.window-switcher.style-classic.width"], "720")
        self.assertEqual(w["osd.window-switcher.style-classic.padding"], "8")
        self.assertTrue(all(re.fullmatch(r"\d+", v) for v in w.values()))


if __name__ == "__main__":
    unittest.main(verbosity=1)
