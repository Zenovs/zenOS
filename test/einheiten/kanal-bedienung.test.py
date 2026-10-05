#!/usr/bin/env python3
"""Einheitentests für die Bedienung des Kanals aus den Einstellungen (System › Updates): «Jetzt installieren»
(zenos-kanal jetzt), «Zustimmen …» (zenos-kanal zustimmen OBJEKT), der Zeitpunkt automatischer Updates
(zenos-kanal zeitpunkt, /etc/xdg/zenos/kanal-zeitpunkt), dazu der pkexec-Helfer scripts/bin/zenos-kanal-bedienen
(nur Aufrufe, die nichts ändern), die polkit-Aktionen und die Units.

Baut auf test/einheiten/kanal-installieren.test.py auf (Server, Gerät, Wegwerf-Schlüssel, Attrappen für install.sh,
die Units laufen im Prozess). Ohne Root, ohne Netz; als root ändert der Helfer-Test nichts am System.

  python3 test/einheiten/kanal-bedienung.test.py
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True

_HIER = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("kanal_installieren", os.path.join(_HIER, "kanal-installieren.test.py"))
_spec = importlib.util.spec_from_loader("kanal_installieren", _loader)
I = importlib.util.module_from_spec(_spec)
_loader.exec_module(I)
B = I.B
K = I.K
WURZEL = I.WURZEL

HELFER = os.path.join(WURZEL, "scripts", "bin", "zenos-kanal-bedienen")
POLICY = os.path.join(WURZEL, "system", "polkit", "org.zenos.kanal.policy")
UNITS = os.path.join(WURZEL, "system", "systemd", "system")
MODUL = os.path.join(WURZEL, "scripts", "module", "14-kanal.sh")


def setUpModule():
    I.setUpModule()


def tearDownModule():
    I.tearDownModule()


def lesen(pfad):
    with open(pfad, encoding="utf-8") as f:
        return f.read()


class ZeitpunktLesen(unittest.TestCase):
    """parse_schedule: dieselben Fälle wie shell/dienste/kanal.js (zeitpunktLesen), aus kanal-zeitpunkt.json."""

    def setUp(self):
        with open(os.path.join(_HIER, "kanal-zeitpunkt.json"), encoding="utf-8") as f:
            self.faelle = json.load(f)

    def test_gueltig(self):
        for fall in self.faelle["gueltig"]:
            with self.subTest(text=fall["text"]):
                erwartet = {k: v for k, v in fall.items() if k in ("art", "von", "bis")}
                self.assertEqual(K.parse_schedule(fall["text"]), (erwartet, None))

    def test_ungueltig_heisst_sperre(self):
        for text in ["", *self.faelle["ungueltig"]]:
            with self.subTest(text=text):
                zeitpunkt, problem = K.parse_schedule(text)
                self.assertEqual(zeitpunkt, {"art": "sperre"})
                self.assertTrue(problem)

    def test_fenster_grenzen(self):
        self.assertIsNone(K.window_problem("02:00", "03:00"), "genau eine Stunde")
        self.assertIsNone(K.window_problem("23:30", "00:30"))
        self.assertIn("mindestens 60 Minuten", K.window_problem("23:30", "00:29"))
        self.assertIn("HH:MM", K.window_problem("2:00", "05:00"))
        self.assertIn("HH:MM", K.window_problem(None, "05:00"))
        self.assertEqual(K.clock_minutes("23:59"), 1439)
        self.assertIsNone(K.clock_minutes("٠٢:٠٠"), "nur ASCII-Ziffern")


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Zeitpunkt(B.Basis):
    def setUp(self):
        super().setUp()
        for name, wert in (("SCHEDULE_FILE", self.pfad("etc", "xdg", "zenos", "kanal-zeitpunkt")),
                           ("LOGGER", self.pfad("gibt-es-nicht", "logger"))):
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)

    def befehl(self, *argumente):
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.cmd_schedule(list(argumente))
        self.ausgabe = aus.getvalue()
        return rc

    def test_ohne_datei_sperre(self):
        self.assertEqual(K.read_schedule(), ({"art": "sperre"}, None))
        self.assertEqual(self.befehl(), 0)
        self.assertIn("Zeitpunkt: sperre · nur gesperrt oder ohne Anmeldung", self.ausgabe)

    def test_setzen_und_lesen(self):
        self.assertEqual(self.befehl("fenster", "22:00", "06:00"), 0, self.ausgabe)
        self.assertEqual(K.read_schedule(), ({"art": "fenster", "von": "22:00", "bis": "06:00"}, None))
        text = lesen(K.SCHEDULE_FILE)
        self.assertRegex(text, r"(?m)^zeitpunkt=fenster\nvon=22:00\nbis=06:00\nseit=\d{4}-\d\d-\d\dT[\d:]+Z$")
        self.assertEqual(os.stat(K.SCHEDULE_FILE).st_mode & 0o777, 0o644)
        self.assertEqual(self.befehl("fenster", "22:00", "06:00"), 0)
        self.assertIn("schon zwischen 22:00 und 06:00", self.ausgabe)
        for wahl in ("hand", "jederzeit", "sperre"):
            self.assertEqual(self.befehl(wahl), 0, self.ausgabe)
            self.assertEqual(K.read_schedule(), ({"art": wahl}, None))
            self.assertNotIn("von=", lesen(K.SCHEDULE_FILE))
        self.assertEqual(self.befehl(), 0)
        self.assertIn("Zeitpunkt: sperre", self.ausgabe)

    def test_falsche_aufrufe(self):
        for argumente in (("nachts",), ("Sperre",), ("sperre", "x"), ("fenster",), ("fenster", "02:00"),
                          ("fenster", "2:00", "05:00"), ("fenster", "02:00", "02:30"), ("fenster", "02:00", "02:00"),
                          ("fenster", "02:00", "05:00", "x"), ("hand", "02:00", "05:00"), ("--hilfe",),
                          ("fenster", "02:00;id", "05:00")):
            with self.subTest(argumente=argumente):
                self.assertEqual(self.befehl(*argumente), 2, self.ausgabe)
                self.assertFalse(os.path.exists(K.SCHEDULE_FILE))

    def test_nur_root_setzt(self):
        self.addCleanup(setattr, K, "TRUSTED_UIDS", K.TRUSTED_UIDS)
        K.TRUSTED_UIDS = (0,) if os.geteuid() != 0 else (12345,)
        self.assertEqual(self.befehl("hand"), 2)
        self.assertIn("nur als root", self.ausgabe)
        self.assertFalse(os.path.exists(K.SCHEDULE_FILE))

    def test_unsicherer_ordner(self):
        ordner = os.path.dirname(K.SCHEDULE_FILE)
        os.chmod(ordner, 0o777)
        self.addCleanup(os.chmod, ordner, 0o755)
        self.assertEqual(self.befehl("hand"), 3)
        self.assertIn("für andere schreibbar", self.ausgabe)
        self.assertFalse(os.path.exists(K.SCHEDULE_FILE))

    def test_unsichere_oder_kaputte_datei_heisst_sperre(self):
        with open(K.SCHEDULE_FILE, "w", encoding="utf-8") as f:
            f.write("zeitpunkt=jederzeit\n")
        os.chmod(K.SCHEDULE_FILE, 0o666)
        zeitpunkt, hinweis = K.read_schedule()
        self.assertEqual(zeitpunkt, {"art": "sperre"})
        self.assertIn("für andere schreibbar", hinweis)
        os.chmod(K.SCHEDULE_FILE, 0o644)
        with open(K.SCHEDULE_FILE, "w", encoding="utf-8") as f:
            f.write("zeitpunkt=fenster\nvon=03:00\n")
        zeitpunkt, hinweis = K.read_schedule()
        self.assertEqual(zeitpunkt, {"art": "sperre"})
        self.assertIn("es gilt «sperre»", hinweis)

    def test_status_zeigt_zeitpunkt(self):
        self.befehl("fenster", "02:00", "05:00")
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            K.cmd_status([])
        self.assertRegex(aus.getvalue(), r"(?m)^Zeitpunkt +zwischen 02:00 und 05:00$")


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Bedienung(I.Geraet):
    """jetzt und zustimmen: dieselben Abläufe wie zen update, ohne Terminal."""

    def setUp(self):
        super().setUp()
        self.folgen = []
        echt = self.unit

        def unit(schluessel, follow=False):
            self.folgen.append((schluessel, follow))
            return echt(schluessel, follow)

        K.start_unit = unit

    def bedienen(self, befehl, *argumente):
        self.protokoll = []
        self.folgen = []
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = befehl(list(argumente))
        self.ausgabe = aus.getvalue() + "".join(p[2] for p in self.protokoll)
        return rc

    def rueckfrage_bereit(self):
        """v0.1.0-rc4 installiert, v0.1.0-rc5 signiert und ändert das Netz: Zustand «zustimmung»."""
        self.signiert_installiert("v0.1.0-rc4")
        neu = self.commit("netz", {"scripts/module/35-netzwerk.sh": "# neu\n"})
        objekt = self.signieren("v0.1.0-rc5")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"], stand["bereit"]["objekt"]), (10, "zustimmung", objekt))
        return neu, objekt

    def test_jetzt_installiert_signiert_ohne_frage(self):
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        neu = self.git("rev-parse", "HEAD")
        self.assertEqual(self.bedienen(K.cmd_now), 0, self.ausgabe)
        self.assertEqual((self.fragen, self.kopf()), ([], neu))
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert")
        self.assertIn(("holen", False), self.folgen, "jetzt holt wie zen update")
        self.assertIn(("installieren", False), self.folgen, "ohne Terminal folgt es dem Journal nicht")
        self.assertEqual(self.folgen[-1], ("pruefen", False), "danach ist der Stand neu geprüft")
        self.assertEqual(self.zustand("stand.json")["zustand"], "aktuell")

    def test_jetzt_laesst_rueckfrage_liegen(self):
        self.rueckfrage_bereit()
        vorher = self.kopf()
        self.assertEqual(self.bedienen(K.cmd_now), 10, self.ausgabe)
        self.assertIn("Das braucht deine Zustimmung", self.ausgabe)
        self.assertEqual((self.fragen, self.kopf()), ([], vorher))
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))

    def test_jetzt_auf_dev_unsigniert_nichts(self):
        self.kanal("dev")
        self.ohne_anker()
        self.commit("neu")
        self.assertEqual(self.bedienen(K.cmd_now), 10, self.ausgabe)
        self.assertEqual((self.fragen, self.kopf(), self.laeufe()), ([], self.basis, []))

    def test_zustimmen_gilt_fuer_das_gezeigte_objekt(self):
        neu, objekt = self.rueckfrage_bereit()
        self.assertEqual(self.bedienen(K.cmd_consent, objekt), 0, self.ausgabe)
        self.assertEqual((self.fragen, self.kopf()), ([], neu))
        self.assertNotIn(("holen", False), self.folgen, "zustimmen holt nicht neu: es gilt der gezeigte Stand")
        gut = self.zustand("gut.json")
        self.assertEqual((gut["tag"], gut["signiert"], gut["freigabe"]), ("v0.1.0-rc5", True, "ja"))
        self.assertEqual(self.hoechste(), "v0.1.0-rc5")

    def test_zustimmen_fuer_ein_anderes_objekt_nichts(self):
        _, objekt = self.rueckfrage_bereit()
        vorher = self.kopf()
        anderes = ("0" if objekt[0] != "0" else "1") + objekt[1:]
        self.assertEqual(self.bedienen(K.cmd_consent, anderes), 10, self.ausgabe)
        self.assertIn("braucht eine neue Zustimmung", self.ausgabe)
        self.assertEqual((self.kopf(), self.fragen), (vorher, []))
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))

    def test_zustimmen_nie_fuer_unsigniertes(self):
        # dev ohne Anker: Das «ja» aus den Einstellungen ersetzt das Terminal nicht, auch für genau diesen Commit
        self.kanal("dev")
        self.ohne_anker()
        neu = self.commit("neu")
        self.lauf()
        self.assertEqual(self.bedienen(K.cmd_consent, neu), 3, self.ausgabe)
        self.assertIn("nicht gültig signiert", self.ausgabe)
        self.assertEqual((self.kopf(), self.laeufe()), (self.basis, []))
        # Ein unsignierter Tag auf vorschau ebenso (rollback geht über die Einstellungen ohnehin nicht)
        self.kanal("vorschau")
        self.anker()
        self.unsigniert("v0.1.0-rc4")
        self.lauf()
        self.assertEqual(self.bedienen(K.cmd_consent, self.git("rev-parse", "refs/tags/v0.1.0-rc4")), 0)
        self.assertEqual(self.kopf(), self.basis, "kein gültiges Ziel: nichts installiert")

    def test_falsche_aufrufe(self):
        for befehl, argumente in ((K.cmd_now, ["x"]), (K.cmd_consent, []), (K.cmd_consent, ["abc"]),
                                  (K.cmd_consent, ["A" * 40]), (K.cmd_consent, ["0" * 40, "x"])):
            with self.subTest(argumente=argumente):
                self.assertEqual(self.bedienen(befehl, *argumente), 2)
        self.assertEqual(self.laeufe(), [])

    def test_wunsch_nur_signiert(self):
        pfad = os.path.join(K.STATE_DIR, "wunsch.json")
        K.write_wish("update", ja="0" * 40, only_signed=True)
        self.assertTrue(K.take_wish(K.now())["nur_signiert"])
        K.write_wish("update", ja="0" * 40)
        self.assertFalse(K.take_wish(K.now())["nur_signiert"])
        for wert, erwartet in (("ja", True), (None, True), (False, False)):
            K.write_wish("update")
            daten = json.loads(lesen(pfad))
            daten["nur_signiert"] = wert
            K.write_json(pfad, daten)
            self.assertIs(K.take_wish(K.now())["nur_signiert"], erwartet, wert)
        K.write_wish("update")
        daten = json.loads(lesen(pfad))
        del daten["nur_signiert"]
        K.write_json(pfad, daten)
        self.assertIs(K.take_wish(K.now())["nur_signiert"], False, "Wunsch von zen update (älteres Format)")

    def test_hilfe_nennt_die_neuen_befehle(self):
        for befehl in ("jetzt", "zustimmen", "zeitpunkt"):
            self.assertRegex(K.__doc__, re.compile(rf"^  zenos-kanal {befehl}\b", re.M))


class Helfer(unittest.TestCase):
    """scripts/bin/zenos-kanal-bedienen: nur feste Wörter; als root ändert dieser Test nichts (nur falsche Aufrufe)."""

    def lauf(self, *argumente):
        return subprocess.run([HELFER, *argumente], capture_output=True, text=True, timeout=30, check=False,
                              env={"PATH": "/usr/bin:/bin"})

    def test_ausfuehrbar(self):
        self.assertTrue(os.access(HELFER, os.X_OK))

    def test_falsche_aufrufe(self):
        for argumente in ((), ("pruefen", "x"), ("installieren", "jetzt"), ("Pruefen",), ("update",), ("status",),
                          ("zustimmen",), ("zustimmen", "abc"), ("zustimmen", "A" * 40), ("zustimmen", "0" * 41),
                          ("zustimmen", "0" * 40, "x"), ("zustimmen", "0" * 39 + ";"), ("zeitpunkt",),
                          ("zeitpunkt", "nachts"), ("zeitpunkt", "sperre", "x"), ("zeitpunkt", "fenster"),
                          ("zeitpunkt", "fenster", "02:00"), ("zeitpunkt", "fenster", "2:00", "05:00"),
                          ("zeitpunkt", "fenster", "02:00", "24:00"), ("zeitpunkt", "fenster", "02:00", "05:00", "x"),
                          ("zeitpunkt", "fenster", "02:00;id", "05:00"), ("zeitpunkt", "hand", "02:00", "05:00"),
                          ("--hilfe",), ("pruefen;id",), ("",)):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("zenos-kanal-bedienen:", e.stderr)
                self.assertEqual(e.stdout, "")

    @unittest.skipIf(os.geteuid() == 0, "als root würde der Helfer wirklich prüfen, installieren oder setzen")
    def test_nur_als_root(self):
        for argumente in (("pruefen",), ("installieren",), ("zustimmen", "0" * 40), ("zeitpunkt", "sperre"),
                          ("zeitpunkt", "fenster", "22:00", "06:00"), ("zeitpunkt", "hand"), ("zeitpunkt", "jederzeit")):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("nur als root", e.stderr)

    def test_startet_nur_mit_argumentlisten(self):
        text = lesen(HELFER)
        self.assertNotRegex(text, r"\b(eval|sh -c|bash -c)\b")
        self.assertIn('/usr/bin/python3 -I "$_programm" zeitpunkt "$@"', text)
        self.assertIn('_unit "zenos-kanal-zustimmen@$2.service"', text)
        self.assertIn('systemctl reset-failed -- "$unit"', text)


class Policy(unittest.TestCase):
    """polkit: prüfen, jetzt installieren und Zeitpunkt ohne Passwort, zustimmen jedes Mal mit Passwort; alles nur in
    der aktiven Sitzung am Gerät und nur für den Helfer mit genau diesem ersten Argument."""

    def test_aktionen(self):
        aktionen = ET.parse(POLICY).getroot().findall("action")
        erwartet = {"org.zenos.kanal.pruefen": ("pruefen", "yes"), "org.zenos.kanal.installieren": ("installieren", "yes"),
                    "org.zenos.kanal.zeitpunkt": ("zeitpunkt", "yes"),
                    "org.zenos.kanal.zustimmen": ("zustimmen", "auth_admin")}
        self.assertEqual(sorted(a.get("id") for a in aktionen), sorted(erwartet))
        for a in aktionen:
            argv1, aktiv = erwartet[a.get("id")]
            notizen = {n.get("key"): n.text for n in a.findall("annotate")}
            self.assertEqual(notizen, {"org.freedesktop.policykit.exec.path": "/opt/zenos/scripts/bin/zenos-kanal-bedienen",
                                       "org.freedesktop.policykit.exec.argv1": argv1})
            vorgaben = a.find("defaults")
            self.assertEqual((vorgaben.find("allow_any").text, vorgaben.find("allow_inactive").text,
                              vorgaben.find("allow_active").text), ("no", "no", aktiv))
            self.assertTrue(a.find("message").text.strip())


class Units(unittest.TestCase):
    def zeilen(self, name):
        return [z.strip() for z in lesen(os.path.join(UNITS, name)).splitlines()]

    def test_jetzt_und_zustimmen(self):
        jetzt = self.zeilen("zenos-kanal-jetzt.service")
        self.assertIn("ExecStart=/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal jetzt", jetzt)
        zustimmen = self.zeilen("zenos-kanal-zustimmen@.service")
        self.assertIn("ExecStart=/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal zustimmen %i", zustimmen)
        for zeilen in (jetzt, zustimmen):
            self.assertIn("Type=oneshot", zeilen)
            # Ohne SuccessExitStatus: Sonst räumte systemd die erfolgreich beendete Unit weg, und der Helfer läse
            # ExecMainStatus 0 statt 10 (im Ende-zu-Ende-Test so passiert)
            self.assertFalse(any(z.startswith("SuccessExitStatus=") for z in zeilen))
            self.assertIn("RuntimeDirectory=zenos-sperre", zeilen)
            self.assertIn("RuntimeDirectoryPreserve=yes", zeilen)
            self.assertIn("StateDirectory=zenos/kanal", zeilen)
            self.assertIn("PrivateNetwork=yes", zeilen)
            self.assertFalse(any(z.startswith("[Install]") for z in zeilen), "statisch: nur über den Helfer")

    def test_modul_und_doctor(self):
        modul = lesen(MODUL)
        for name in ("zenos-kanal-jetzt.service", "zenos-kanal-zustimmen@.service", "org.zenos.kanal.policy"):
            self.assertIn(name, modul)
        doctor = lesen(os.path.join(WURZEL, "scripts", "doctor.d", "15-kanal.sh"))
        self.assertIn("zenos-kanal-zustimmen@.service", doctor)


if __name__ == "__main__":
    unittest.main(verbosity=1)
