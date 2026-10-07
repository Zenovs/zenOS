#!/usr/bin/env python3
"""Einheitentests für «zen update» (scripts/zen.d/update.sh): zwei Schritte (zenOS-Kanal, dann Ubuntu-Basis), die
Optionen --ja, --nur-zenos und --nur-basis, wann der Basis-Schritt läuft, die Meldung je Schritt, der Exit (0 nur, wenn
jeder gelaufene Schritt gelang, sonst der schwerere) und die Benutzerteile am Ende.

update.sh läuft in bash mit Attrappen: python3 (gibt den Aufruf weiter an eine Datei und endet mit dem Exit, den der
Test für zenos-kanal bzw. zenos-basis vorgibt) und install.sh --nur-benutzer. Die Programme selbst prüfen
kanal-*.test.py und basis-*.test.py. Als root lässt update.sh die Benutzerteile aus (wie auf dem Gerät mit sudo zen
update ohne Benutzer); der Test erwartet das dann ebenso. Ohne Netz.

  python3 test/einheiten/zen-update.test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UPDATE = os.path.join(WURZEL, "scripts", "zen.d", "update.sh")
BASH = shutil.which("bash")

RAHMEN = r'''
set -euo pipefail
zen_fehler() { printf 'zen: %s\n' "$*" >&2; }
zen_warnung() { printf 'zen: Warnung: %s\n' "$*" >&2; }
zen_hinweis() { printf '%s\n' "$*"; }
SUDO=""
ZENOS_CODE=$W/opt
source "$UPDATE"
_UPDATE_PROGRAMM=$W/libexec/zenos-kanal
_UPDATE_BASIS=$W/libexec/zenos-basis
_UPDATE_PYTHON=$W/python3
befehl_update "$@"
'''

# python3 -I PROGRAMM ARG…: Aufruf merken, Exit aus $W/exit.<programm>
PYTHON = r'''#!/bin/sh
name=$(basename "$2")
shift 2
printf '%s %s\n' "$name" "$*" >> "$W/aufrufe"
printf 'Ausgabe von %s\n' "$name"
code=0
[ ! -f "$W/exit.$name" ] || code=$(cat "$W/exit.$name")
exit "$code"
'''

INSTALL = r'''#!/bin/sh
printf 'install.sh %s\n' "$*" >> "$W/aufrufe"
'''


def schreiben(pfad, text, modus=0o644):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(pfad, modus)


@unittest.skipUnless(BASH, "bash fehlt")
class ZenUpdate(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zen-update.")
        self.addCleanup(shutil.rmtree, self.w, True)
        schreiben(os.path.join(self.w, "python3"), PYTHON, 0o755)
        schreiben(os.path.join(self.w, "opt", "scripts", "install.sh"), INSTALL, 0o755)
        for name in ("zenos-kanal", "zenos-basis"):
            schreiben(os.path.join(self.w, "libexec", name), "")
        self.benutzer = ["install.sh --nur-benutzer"] if os.geteuid() != 0 else []

    def exits(self, kanal=0, basis=0):
        schreiben(os.path.join(self.w, "exit.zenos-kanal"), str(kanal))
        schreiben(os.path.join(self.w, "exit.zenos-basis"), str(basis))

    def update(self, *argumente):
        r = subprocess.run([BASH, "-c", RAHMEN, "zen", *argumente], capture_output=True, text=True, check=False,
                           timeout=30, env={"PATH": "/usr/bin:/bin", "W": self.w, "UPDATE": UPDATE})
        try:
            with open(os.path.join(self.w, "aufrufe"), encoding="utf-8") as f:
                aufrufe = f.read().splitlines()
            os.unlink(os.path.join(self.w, "aufrufe"))
        except FileNotFoundError:
            aufrufe = []
        return r.returncode, aufrufe, r.stdout + r.stderr

    def test_beide_schritte(self):
        code, aufrufe, aus = self.update()
        self.assertEqual(code, 0, aus)
        self.assertEqual(aufrufe, ["zenos-kanal update", "zenos-basis update", *self.benutzer])
        zeilen = aus.splitlines()
        for zeile in ("== Schritt 1 von 2: zenOS-Kanal", "zenOS-Kanal: gelungen.", "== Schritt 2 von 2: Ubuntu-Basis",
                      "Ubuntu-Basis: gelungen."):
            self.assertIn(zeile, zeilen)
        self.assertLess(zeilen.index("zenOS-Kanal: gelungen."), zeilen.index("== Schritt 2 von 2: Ubuntu-Basis"))

    def test_ja_nur_fuer_die_basis(self):
        code, aufrufe, aus = self.update("--ja")
        self.assertEqual(code, 0, aus)
        self.assertEqual(aufrufe, ["zenos-kanal update", "zenos-basis update --ja", *self.benutzer],
                         "das «ja» des Kanals ersetzt --ja nie")

    def test_nur_zenos_und_nur_basis(self):
        code, aufrufe, aus = self.update("--nur-zenos")
        self.assertEqual((code, aufrufe), (0, ["zenos-kanal update", *self.benutzer]), aus)
        self.assertNotIn("Schritt", aus)
        self.assertIn("zenOS-Kanal: gelungen.", aus)
        code, aufrufe, aus = self.update("--nur-basis", "--ja")
        self.assertEqual((code, aufrufe), (0, ["zenos-basis update --ja", *self.benutzer]), aus)
        self.assertNotIn("Schritt", aus)
        self.exits(kanal=10)
        code, aufrufe, aus = self.update("--nur-zenos")
        self.assertEqual((code, aufrufe), (10, ["zenos-kanal update"]), aus)
        self.assertIn("zenOS-Kanal: nicht gelungen – wartet (Exit 10).", aus)

    def test_falsche_aufrufe(self):
        for argumente, text in ((("--nur-zenos", "--nur-basis"), "schliessen sich aus"),
                                (("--ja", "--nur-zenos"), "--ja gilt nur für den Basis-Schritt"),
                                (("ja",), "nicht «ja»"), (("--JA",), "kennt nur"), (("--nur-zenos", "x"), "kennt nur")):
            with self.subTest(argumente=argumente):
                code, aufrufe, aus = self.update(*argumente)
                self.assertEqual((code, aufrufe), (2, []), aus)
                self.assertIn(text, aus)

    def test_exit_ist_der_schwerere(self):
        faelle = (((0, 0), 0), ((10, 0), 10), ((0, 10), 10), ((75, 0), 75), ((75, 10), 10), ((3, 75), 3),
                  ((10, 3), 3), ((1, 3), 1), ((3, 1), 1), ((4, 0), 4), ((4, 5), 5), ((0, 5), 5), ((4, 1), 4),
                  ((0, 1), 1), ((0, 75), 75), ((0, 42), 42), ((10, 42), 42))
        for (kanal, basis), erwartet in faelle:
            with self.subTest(kanal=kanal, basis=basis):
                self.exits(kanal, basis)
                code, aufrufe, aus = self.update()
                self.assertEqual(code, erwartet, aus)
                self.assertEqual(aufrufe[:2], ["zenos-kanal update", "zenos-basis update"],
                                 "die Basis läuft auch nach «nichts neu», «nein» oder «läuft schon»")
                gelungen = "gelungen." if basis == 0 else "nicht gelungen"
                self.assertIn(f"Ubuntu-Basis: {gelungen}", aus)

    def test_kanal_kaputt_ueberspringt_die_basis(self):
        self.exits(kanal=5)
        code, aufrufe, aus = self.update("--ja")
        self.assertEqual((code, aufrufe), (5, ["zenos-kanal update"]), aus)
        self.assertIn("zenOS-Kanal: nicht gelungen – kaputt (Exit 5).", aus)
        self.assertIn("Ubuntu-Basis: übersprungen – der zenOS-Kanal ist kaputt", aus)

    def test_abgebrochen(self):
        self.exits(kanal=130)
        code, aufrufe, aus = self.update()
        self.assertEqual((code, aufrufe), (130, ["zenos-kanal update"]), aus)
        self.assertIn("Ubuntu-Basis: nicht begonnen (abgebrochen).", aus)
        self.exits(kanal=0, basis=130)
        code, aufrufe, aus = self.update()
        self.assertEqual(code, 130, aus)
        self.assertEqual(aufrufe[:2], ["zenos-kanal update", "zenos-basis update"])

    def test_benutzerteile(self):
        """Nach einer Installation oder einem Rückweg des Kanals (0, 4) oder einem gelungenen Basis-Schritt."""
        for (kanal, basis), mit in (((0, 10), True), ((4, 10), True), ((10, 0), True), ((10, 10), False),
                                    ((3, 1), False), ((5, 0), False), ((75, 75), False)):
            with self.subTest(kanal=kanal, basis=basis):
                self.exits(kanal, basis)
                _, aufrufe, aus = self.update()
                self.assertEqual("install.sh --nur-benutzer" in aufrufe, mit and os.geteuid() != 0, aus)
        self.exits(0, 0)
        _, aufrufe, _ = self.update("--nur-basis")
        self.assertEqual(aufrufe, ["zenos-basis update", *self.benutzer])

    def test_programm_fehlt(self):
        os.unlink(os.path.join(self.w, "libexec", "zenos-kanal"))
        code, aufrufe, aus = self.update()
        self.assertEqual(code, 1, aus)
        self.assertEqual(aufrufe[:1], ["zenos-basis update"], "die Basis läuft trotzdem")
        self.assertIn("zenos-kanal fehlt", aus)
        os.unlink(os.path.join(self.w, "libexec", "zenos-basis"))
        code, aufrufe, aus = self.update("--nur-basis")
        self.assertEqual((code, aufrufe), (1, []), aus)
        self.assertIn("richtet install.sh ein (Modul 71-basis)", aus)

    def test_hilfe(self):
        with open(UPDATE, encoding="utf-8") as f:
            kopf = f.read().split("# shellcheck", 1)[0]
        self.assertIn("# hilfe: update [--ja] [--nur-zenos|--nur-basis] – ", kopf)
        for wort in ("--ja", "--nur-zenos", "--nur-basis", "Exit:"):
            self.assertIn(wort, kopf)


if __name__ == "__main__":
    unittest.main(verbosity=1)
