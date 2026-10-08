#!/usr/bin/env python3
"""Einheitentests für die Ablage: Benutzerteil von scripts/module/48-ablage.sh und scripts/doctor.d/48-ablage.sh.

Jeder Test hat ein eigenes Test-HOME. Der Benutzerteil läuft wie in install.sh (gemeinsam.sh, Zähler in ZENOS_TMP),
aber ohne sudo und ohne Systemteil. Linux, nicht als root: python3 test/einheiten/ablage.test.py
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from xml.etree import ElementTree

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODUL = os.path.join(WURZEL, "scripts", "module", "48-ablage.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "48-ablage.sh")
GEMEINSAM = os.path.join(WURZEL, "scripts", "lib", "gemeinsam.sh")
MARKE = "# zenOS: Benutzerordner zeigen auf ~/Ablage (scripts/module/48-ablage.sh)"
ABLAGE = ("DESKTOP", "DOWNLOAD", "DOCUMENTS", "MUSIC", "PICTURES", "VIDEOS")
ABGESCHALTET = ("TEMPLATES", "PUBLICSHARE")
UCA_VORLAGE = os.path.join(WURZEL, "system", "thunar", "uca.xml")
UCA_MARKE = "<!-- zenOS: Thunar-Aktion «Terminal hier öffnen» mit kitty (scripts/module/48-ablage.sh) -->"

BENUTZERTEIL = r"""
set -Eeuo pipefail
source "$1"
source "$2"
modul_benutzer
printf 'AENDERUNGEN=%s\n' "$(zenos_anzahl aenderung)"
printf 'WARNUNGEN=%s\n' "$(zenos_anzahl warnung)"
"""

# Doctor-Funktionen wie in zen.d/doctor.sh, hier als einfache Ausgabe
DOCTOR_TEIL = r"""
abschnitt() { :; }
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$1"
_ablage_ordner
_ablage_user_dirs
_ablage_thunar_aktion
"""


def eintraege(pfad):
    """XDG-Einträge aus user-dirs.dirs als Wörterbuch (NAME → Wert ohne Anführungszeichen)."""
    werte = {}
    with open(pfad, encoding="utf-8") as f:
        for zeile in f:
            zeile = zeile.strip()
            if zeile.startswith("XDG_") and "=" in zeile:
                name, wert = zeile.split("=", 1)
                werte[name[4:-4]] = wert.strip('"')
    return werte


@unittest.skipUnless(sys.platform.startswith("linux"), "nur unter Linux (GNU stat, bash 5)")
@unittest.skipIf(os.geteuid() == 0, "Benutzerteile laufen nie als root")
class AblageTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-ablage-test.")
        self.home = os.path.join(self.wurzel, "home")
        self.tmp = os.path.join(self.wurzel, "tmp")
        os.makedirs(self.home)
        os.makedirs(self.tmp)
        self.umgebung = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": self.home,
            "LANG": "C.UTF-8",
            "SUDO": "",
            "ZENOS_HOME": self.home,
            "ZENOS_BENUTZER": "tester",
            "ZENOS_IMAGE": "0",
            "ZENOS_SYSTEMD": "0",
            "ZENOS_CODE": WURZEL,
            "ZENOS_QUELLE": WURZEL,
            "ZENOS_TMP": self.tmp,
            "ZENOS_PHASE": "benutzer",
            "ZENOS_MODUL": "48-ablage",
        }

    def tearDown(self):
        shutil.rmtree(self.wurzel, ignore_errors=True)

    def pfad(self, *teile):
        return os.path.join(self.home, *teile)

    def benutzerteil(self):
        # Zähler wie in install.sh: eine Datei je Lauf
        with open(os.path.join(self.tmp, "zaehler"), "w", encoding="utf-8"):
            pass
        ergebnis = subprocess.run(["bash", "-c", BENUTZERTEIL, "test", GEMEINSAM, MODUL], env=self.umgebung,
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stdout + ergebnis.stderr)
        zahlen = dict(z.split("=", 1) for z in ergebnis.stdout.splitlines() if z.startswith(("AENDERUNGEN=", "WARNUNGEN=")))
        return int(zahlen["AENDERUNGEN"]), int(zahlen["WARNUNGEN"]), ergebnis.stdout + ergebnis.stderr

    def doctor(self):
        ergebnis = subprocess.run(["bash", "-c", DOCTOR_TEIL, "test", DOCTOR], env=self.umgebung,
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stdout + ergebnis.stderr)
        return ergebnis.stdout

    # --- Ordner

    def test_frisches_home(self):
        aenderungen, warnungen, _ = self.benutzerteil()
        # Ablage, Ablage/Screenshots, user-dirs.dirs, user-dirs.conf, uca.xml
        self.assertEqual((aenderungen, warnungen), (5, 0))
        modus = os.stat(self.pfad("Ablage")).st_mode
        self.assertTrue(stat.S_ISDIR(modus))
        self.assertEqual(stat.S_IMODE(modus), 0o700)
        # Keine Ubuntu-Struktur: nur die Ablage und .config
        self.assertEqual(sorted(os.listdir(self.home)), [".config", "Ablage"])
        self.assertEqual(os.listdir(self.pfad("Ablage")), ["Screenshots"])

    def test_zweiter_lauf_aendert_nichts(self):
        self.benutzerteil()
        self.assertEqual(self.benutzerteil()[:2], (0, 0))

    def test_vorhandene_ablage_bleibt_wie_sie_ist(self):
        os.makedirs(self.pfad("Ablage", "Projekt"))
        os.chmod(self.pfad("Ablage"), 0o755)
        with open(self.pfad("Ablage", "Rechnung.pdf"), "w", encoding="utf-8") as f:
            f.write("Inhalt")
        aenderungen, warnungen, _ = self.benutzerteil()
        self.assertEqual((aenderungen, warnungen), (4, 0))
        self.assertEqual(stat.S_IMODE(os.stat(self.pfad("Ablage")).st_mode), 0o755)
        self.assertEqual(sorted(os.listdir(self.pfad("Ablage"))), ["Projekt", "Rechnung.pdf", "Screenshots"])
        with open(self.pfad("Ablage", "Rechnung.pdf"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "Inhalt")

    def test_verweis_auf_ordner_ist_erlaubt(self):
        ziel = os.path.join(self.wurzel, "sync")
        os.makedirs(ziel)
        os.symlink(ziel, self.pfad("Ablage"))
        aenderungen, warnungen, _ = self.benutzerteil()
        self.assertEqual((aenderungen, warnungen), (4, 0))
        self.assertTrue(os.path.islink(self.pfad("Ablage")))
        self.assertEqual(os.readlink(self.pfad("Ablage")), ziel)
        self.assertIn("ok: Ablage: ~/Ablage ist ein Verweis auf einen Ordner", self.doctor())

    def test_datei_statt_ordner_bleibt_mit_warnung(self):
        with open(self.pfad("Ablage"), "w", encoding="utf-8") as f:
            f.write("keine Ablage")
        aenderungen, warnungen, ausgabe = self.benutzerteil()
        self.assertEqual((aenderungen, warnungen), (3, 1))
        self.assertIn("ist kein Ordner und bleibt unverändert", ausgabe)
        with open(self.pfad("Ablage"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "keine Ablage")

    # --- user-dirs.dirs und user-dirs.conf

    def test_benutzerordner_zeigen_auf_die_ablage(self):
        self.benutzerteil()
        datei = self.pfad(".config", "user-dirs.dirs")
        with open(datei, encoding="utf-8") as f:
            self.assertEqual(f.readline().rstrip("\n"), MARKE)
        werte = eintraege(datei)
        self.assertEqual(set(werte), set(ABLAGE) | set(ABGESCHALTET))
        for name in ABLAGE:
            self.assertEqual(werte[name], "$HOME/Ablage", name)
        for name in ABGESCHALTET:
            self.assertEqual(werte[name], "$HOME/", name)
        with open(self.pfad(".config", "user-dirs.conf"), encoding="utf-8") as f:
            inhalt = f.read().splitlines()
        self.assertEqual(inhalt[0], MARKE)
        self.assertIn("enabled=False", inhalt)

    def test_eigene_user_dirs_bleibt(self):
        os.makedirs(self.pfad(".config"))
        eigen = 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
        with open(self.pfad(".config", "user-dirs.dirs"), "w", encoding="utf-8") as f:
            f.write(eigen)
        aenderungen, warnungen, ausgabe = self.benutzerteil()
        # Ablage, Ablage/Screenshots, user-dirs.conf und uca.xml, nicht user-dirs.dirs
        self.assertEqual((aenderungen, warnungen), (4, 0))
        self.assertIn("user-dirs.dirs stammt nicht von zenOS und bleibt unverändert", ausgabe)
        with open(self.pfad(".config", "user-dirs.dirs"), encoding="utf-8") as f:
            self.assertEqual(f.read(), eigen)
        self.assertIn("hinweis: Eigene user-dirs.dirs, Downloads landen in ~/Downloads", self.doctor())

    def test_eigene_user_dirs_conf_bleibt(self):
        os.makedirs(self.pfad(".config"))
        with open(self.pfad(".config", "user-dirs.conf"), "w", encoding="utf-8") as f:
            f.write("enabled=True\n")
        self.assertEqual(self.benutzerteil()[:2], (4, 0))
        with open(self.pfad(".config", "user-dirs.conf"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "enabled=True\n")

    def test_leerer_alter_screenshot_ordner_verschwindet(self):
        os.makedirs(self.pfad("Bilder", "Screenshots"))
        aenderungen, warnungen, _ = self.benutzerteil()
        # wie frisch, dazu Bilder/Screenshots und Bilder entfernt
        self.assertEqual((aenderungen, warnungen), (7, 0))
        self.assertFalse(os.path.exists(self.pfad("Bilder")))
        self.assertTrue(os.path.isdir(self.pfad("Ablage", "Screenshots")))
        self.assertEqual(self.benutzerteil()[:2], (0, 0))

    def test_alter_screenshot_ordner_mit_bildern_bleibt(self):
        os.makedirs(self.pfad("Bilder", "Screenshots"))
        with open(self.pfad("Bilder", "Screenshots", "alt.png"), "wb") as f:
            f.write(b"png")
        aenderungen, warnungen, ausgabe = self.benutzerteil()
        self.assertEqual((aenderungen, warnungen), (5, 0))
        self.assertTrue(os.path.isfile(self.pfad("Bilder", "Screenshots", "alt.png")))
        self.assertIn("mv ~/Bilder/Screenshots/* ~/Ablage/Screenshots/", ausgabe)

    XDG_VORGABE = (
        "# This file is written by xdg-user-dirs-update\n"
        "# If you want to change or add directories, just edit the line you're\n"
        "# interested in. All local changes will be retained on the next run.\n"
        "# \n"
        'XDG_DESKTOP_DIR="$HOME/Desktop"\n'
        'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
        'XDG_TEMPLATES_DIR="$HOME/Templates"\n'
        'XDG_PUBLICSHARE_DIR="$HOME/Public"\n'
        'XDG_DOCUMENTS_DIR="$HOME/Documents"\n'
        'XDG_MUSIC_DIR="$HOME/Music"\n'
        'XDG_PICTURES_DIR="$HOME/Pictures"\n'
        'XDG_VIDEOS_DIR="$HOME/Videos"\n'
    )
    XDG_ORDNER = ["Desktop", "Downloads", "Templates", "Public", "Documents", "Music", "Pictures", "Videos"]

    def _xdg_vorgabe_anlegen(self, inhalt=None):
        os.makedirs(self.pfad(".config"), exist_ok=True)
        with open(self.pfad(".config", "user-dirs.dirs"), "w", encoding="utf-8") as f:
            f.write(inhalt if inhalt is not None else self.XDG_VORGABE)
        for name in self.XDG_ORDNER:
            os.makedirs(self.pfad(name))

    def test_vorgabe_von_xdg_user_dirs_wird_ersetzt(self):
        self._xdg_vorgabe_anlegen()
        with open(self.pfad("Downloads", "rechnung.pdf"), "w", encoding="utf-8") as f:
            f.write("pdf")
        aenderungen, warnungen, ausgabe = self.benutzerteil()
        self.assertEqual(warnungen, 0, ausgabe)
        werte = eintraege(self.pfad(".config", "user-dirs.dirs"))
        self.assertEqual(werte["DOWNLOAD"], "$HOME/Ablage")
        with open(self.pfad(".config", "user-dirs.dirs.vor-zenos"), encoding="utf-8") as f:
            self.assertEqual(f.read(), self.XDG_VORGABE)
        # Leere Vorgabe-Ordner sind weg, Downloads mit Inhalt bleibt, mit Hinweis
        self.assertEqual(sorted(n for n in os.listdir(self.home) if not n.startswith(".")), ["Ablage", "Downloads"])
        self.assertTrue(os.path.isfile(self.pfad("Downloads", "rechnung.pdf")))
        self.assertIn("mv ~/Downloads/* ~/Ablage/", ausgabe)
        self.assertEqual(self.benutzerteil()[:2], (0, 0))

    def test_geaenderte_xdg_datei_bleibt(self):
        eigen = self.XDG_VORGABE.replace('"$HOME/Documents"', '"$HOME/Projekte"')
        self._xdg_vorgabe_anlegen(eigen)
        aenderungen, warnungen, ausgabe = self.benutzerteil()
        with open(self.pfad(".config", "user-dirs.dirs"), encoding="utf-8") as f:
            self.assertEqual(f.read(), eigen)
        self.assertFalse(os.path.exists(self.pfad(".config", "user-dirs.dirs.vor-zenos")))
        for name in self.XDG_ORDNER:
            self.assertTrue(os.path.isdir(self.pfad(name)), name)
        self.assertIn("user-dirs.dirs stammt nicht von zenOS und bleibt unverändert", ausgabe)

    def test_alte_fassung_von_zenos_wird_erneuert(self):
        os.makedirs(self.pfad(".config"))
        with open(self.pfad(".config", "user-dirs.dirs"), "w", encoding="utf-8") as f:
            f.write(MARKE + '\nXDG_DOWNLOAD_DIR="$HOME/Alt"\n')
        self.benutzerteil()
        self.assertEqual(eintraege(self.pfad(".config", "user-dirs.dirs"))["DOWNLOAD"], "$HOME/Ablage")

    def test_verweis_auf_user_dirs_bleibt(self):
        os.makedirs(self.pfad(".config"))
        dotfiles = os.path.join(self.wurzel, "dotfiles-user-dirs.dirs")
        with open(dotfiles, "w", encoding="utf-8") as f:
            f.write(MARKE + '\nXDG_DOWNLOAD_DIR="$HOME/Ablage"\n')
        os.symlink(dotfiles, self.pfad(".config", "user-dirs.dirs"))
        self.benutzerteil()
        self.assertTrue(os.path.islink(self.pfad(".config", "user-dirs.dirs")))
        with open(dotfiles, encoding="utf-8") as f:
            self.assertEqual(f.read(), MARKE + '\nXDG_DOWNLOAD_DIR="$HOME/Ablage"\n')

    @unittest.skipUnless(shutil.which("xdg-user-dirs-update"), "xdg-user-dirs nicht installiert")
    def test_xdg_user_dirs_update_setzt_nichts_zurueck(self):
        self.benutzerteil()
        with open(self.pfad(".config", "user-dirs.dirs"), encoding="utf-8") as f:
            vorher = f.read()
        # Auch wenn die Ablage bei der Anmeldung gerade fehlt (z. B. ein Verweis ins Leere)
        os.rmdir(self.pfad("Ablage"))
        subprocess.run(["xdg-user-dirs-update"], env=self.umgebung, check=True, timeout=30)
        with open(self.pfad(".config", "user-dirs.dirs"), encoding="utf-8") as f:
            self.assertEqual(f.read(), vorher)
        self.assertEqual(os.listdir(self.home), [".config"])

    # --- Thunar: «Terminal hier öffnen» (~/.config/Thunar/uca.xml)

    def uca(self):
        return self.pfad(".config", "Thunar", "uca.xml")

    def test_uca_vorlage_ist_gueltig(self):
        with open(UCA_VORLAGE, encoding="utf-8") as f:
            inhalt = f.read()
        # Die erste Zeile ist die Marke; ohne XML-Deklaration davor ist ein Kommentar dort gültig
        self.assertEqual(inhalt.splitlines()[0], UCA_MARKE)
        wurzel = ElementTree.fromstring(inhalt)
        self.assertEqual(wurzel.tag, "actions")
        aktionen = wurzel.findall("action")
        self.assertEqual(len(aktionen), 2)
        self.assertEqual(aktionen[0].findtext("command"), "kitty --directory %f")
        self.assertIsNotNone(aktionen[0].find("directories"))
        # «Mit zen Installer öffnen» nur für .deb, derselbe Aufruf wie der Starter zenos-installer.desktop
        self.assertEqual(aktionen[1].findtext("command"), "/opt/zenos/scripts/bin/zenos-installer oeffnen %f")
        self.assertEqual(aktionen[1].findtext("patterns"), "*.deb")
        self.assertIsNotNone(aktionen[1].find("other-files"))
        self.assertIsNone(aktionen[1].find("directories"))
        self.assertEqual(len({a.findtext("unique-id") for a in aktionen}), 2)

    def test_uca_wird_angelegt(self):
        self.benutzerteil()
        with open(self.uca(), encoding="utf-8") as f, open(UCA_VORLAGE, encoding="utf-8") as v:
            self.assertEqual(f.read(), v.read())

    def test_uca_von_thunar_bleibt_ohne_hinweis(self):
        # Thunar schreibt die Datei mit XML-Deklaration neu, sobald du eigene Aktionen anlegst
        os.makedirs(os.path.dirname(self.uca()))
        eigen = '<?xml version="1.0" encoding="UTF-8"?>\n<actions>\n</actions>\n'
        with open(self.uca(), "w", encoding="utf-8") as f:
            f.write(eigen)
        aenderungen, warnungen, ausgabe = self.benutzerteil()
        # Ablage, Ablage/Screenshots, user-dirs.dirs, user-dirs.conf, nicht uca.xml
        self.assertEqual((aenderungen, warnungen), (4, 0))
        self.assertNotIn("uca.xml", ausgabe)
        with open(self.uca(), encoding="utf-8") as f:
            self.assertEqual(f.read(), eigen)

    def test_doctor_erkennt_beispiel_aktion_von_thunar(self):
        # So sieht die Datei aus, wenn Thunar vor zenOS gestartet ist (Kopie der Beispiel-Aktion)
        os.makedirs(os.path.dirname(self.uca()))
        with open(self.uca(), "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n<actions>\n<action>\n'
                    '\t<command>exo-open --working-directory %f --launch TerminalEmulator</command>\n'
                    '</action>\n</actions>\n')
        self.assertIn("hinweis: Thunar: «Terminal hier öffnen» nutzt exo-open", self.doctor())

    def test_alte_uca_von_zenos_wird_erneuert(self):
        os.makedirs(os.path.dirname(self.uca()))
        with open(self.uca(), "w", encoding="utf-8") as f:
            f.write(UCA_MARKE + "\n<actions/>\n")
        self.benutzerteil()
        with open(self.uca(), encoding="utf-8") as f, open(UCA_VORLAGE, encoding="utf-8") as v:
            self.assertEqual(f.read(), v.read())

    # --- zen doctor

    def test_doctor_nach_dem_einrichten(self):
        self.benutzerteil()
        ausgabe = self.doctor()
        self.assertIn("ok: Ablage: ~/Ablage vorhanden (700)", ausgabe)
        self.assertIn("ok: Benutzerordner von zenOS", ausgabe)
        self.assertIn("ok: Thunar: «Terminal hier öffnen» startet kitty", ausgabe)
        self.assertNotIn(self.home, ausgabe)

    def test_doctor_ohne_ablage(self):
        ausgabe = self.doctor()
        self.assertIn("warnung: Ablage: ~/Ablage fehlt", ausgabe)
        self.assertIn("warnung: Benutzerordner: ~/.config/user-dirs.dirs fehlt", ausgabe)
        self.assertIn("hinweis: Thunar: ~/.config/Thunar/uca.xml fehlt", ausgabe)

    def test_doctor_nennt_keinen_absoluten_pfad(self):
        os.makedirs(self.pfad(".config"))
        with open(self.pfad(".config", "user-dirs.dirs"), "w", encoding="utf-8") as f:
            f.write('XDG_DOWNLOAD_DIR="/media/jemand/Downloads"\n')
        ausgabe = self.doctor()
        self.assertIn("hinweis: Eigene user-dirs.dirs, Downloads landen ausserhalb von ~", ausgabe)
        self.assertNotIn("jemand", ausgabe)


if __name__ == "__main__":
    unittest.main()
