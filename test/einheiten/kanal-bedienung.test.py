#!/usr/bin/env python3
"""Einheitentests für die Bedienung des Kanals aus den Einstellungen (System › Updates): «Jetzt installieren»
(zenos-kanal jetzt ZIEL), «Zustimmen …» (zenos-kanal zustimmen OBJEKT), der Zeitpunkt automatischer Updates
(zenos-kanal zeitpunkt, /etc/xdg/zenos/kanal-zeitpunkt), dazu der pkexec-Helfer scripts/bin/zenos-kanal-bedienen
(nur Aufrufe, die nichts ändern; auch die Wörter der Ubuntu-Basis basis-pruefen, basis-installieren und
basis-installieren-zustimmen), die polkit-Aktionen und die Units. Was zenos-basis jetzt und zustimmen tun, prüft
test/einheiten/basis-automatik.test.py.

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
        self.assertRegex(text, r"(?m)^zeitpunkt=fenster\nvon=22:00\nbis=06:00\nseit=\d{4}-\d\d-\d\dT[\d:]+Z\n"
                               r"ueber=(root|(pkexec|sudo), uid \d+)$")
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

    def test_ungueltige_datei_wird_ersetzt(self):
        """Die Datei ist ungültig (es gilt «sperre»): Auch die Wahl «sperre» schreibt sie neu (sonst bliebe der Hinweis
        «Datei ungültig» stehen, und ein Klick auf «Bei Sperre» täte nichts)."""
        with open(K.SCHEDULE_FILE, "w", encoding="utf-8") as f:
            f.write("zeitpunkt=fenster\nvon=02:00\nbis=02:30\n")
        self.assertEqual(K.read_schedule()[0], {"art": "sperre"})
        self.assertIsNotNone(K.read_schedule()[1])
        self.assertEqual(self.befehl("sperre"), 0, self.ausgabe)
        self.assertNotIn("schon", self.ausgabe)
        self.assertEqual(K.read_schedule(), ({"art": "sperre"}, None))

    def test_weg_steht_in_der_datei(self):
        alt = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(alt)))
        os.environ.pop("SUDO_UID", None)
        os.environ["PKEXEC_UID"] = "1000"
        self.assertEqual(self.befehl("hand"), 0, self.ausgabe)
        self.assertIn("\nueber=pkexec, uid 1000\n", lesen(K.SCHEDULE_FILE))
        os.environ["PKEXEC_UID"] = "1000;x"
        self.assertEqual(self.befehl("jederzeit"), 0, self.ausgabe)
        self.assertIn("\nueber=root\n", lesen(K.SCHEDULE_FILE), "nur eine Zahl gilt als uid")

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
        objekt = self.signieren("v0.1.0-rc4")
        neu = self.git("rev-parse", "HEAD")
        _, stand = self.lauf()
        self.assertEqual(stand["bereit"]["objekt"], objekt)
        self.assertEqual(self.bedienen(K.cmd_now, objekt), 0, self.ausgabe)
        self.assertEqual((self.fragen, self.kopf()), ([], neu))
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert")
        self.assertNotIn(("holen", False), self.folgen, "jetzt holt nicht neu: es gilt der gezeigte, geprüfte Stand")
        self.assertIn(("installieren", False), self.folgen, "ohne Terminal folgt es dem Journal nicht")
        self.assertEqual(self.folgen[-1], ("pruefen", False), "danach ist der Stand neu geprüft")
        self.assertEqual(self.zustand("stand.json")["zustand"], "aktuell")

    def test_jetzt_nur_der_angezeigte_stand(self):
        """Zwischen Anzeige und Klick kam rc5 dazu (etwa durch die Automatik geholt): Der Knopf galt rc4, nichts."""
        self.commit("neu")
        objekt = self.signieren("v0.1.0-rc4")
        self.lauf()
        vorher = self.kopf()
        self.commit("noch neuer")
        self.signieren("v0.1.0-rc5")
        self.lauf()
        self.assertEqual(self.bedienen(K.cmd_now, objekt), 10, self.ausgabe)
        self.assertIn("Angezeigt war", self.ausgabe)
        self.assertEqual((self.kopf(), self.laeufe()), (vorher, []))
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))
        self.assertEqual(self.zustand("stand.json")["wunsch"]["ergebnis"], "wartet")

    def test_jetzt_mit_gesperrter_hoeherer_version(self):
        """rc6 ist nach einer gescheiterten Installation gesperrt, rc5 ist bereit: Knopf und zen update nehmen rc5
        (wie die Anzeige), nicht die gesperrte höhere Version."""
        self.signiert_installiert("v0.1.0-rc4")
        rc5 = self.commit("stand rc5")
        objekt = self.signieren("v0.1.0-rc5", ref=rc5)
        rc6 = self.commit("stand rc6")
        self.signieren("v0.1.0-rc6", ref=rc6)
        K.lock_target({"version": "v0.1.0-rc6", "commit": rc6}, "Test: gescheitert")
        _, stand = self.lauf()
        self.assertEqual((stand["zustand"], stand["bereit"]["version"]), ("bereit", "v0.1.0-rc5"))
        self.assertEqual(self.bedienen(K.cmd_now, objekt), 0, self.ausgabe)
        self.assertEqual((self.kopf(), self.fragen), (rc5, []))
        self.assertEqual(self.zustand("letzte.json")["ziel"]["tag"], "v0.1.0-rc5")

    def test_zen_update_mit_gesperrter_hoeherer_version(self):
        """Wie die Anzeige: zen update installiert die bereite rc5 ohne Frage, statt nach der gesperrten rc6 zu fragen.
        Die gesperrte Version noch einmal versuchen geht bewusst mit zen rollback und «ja»."""
        self.signiert_installiert("v0.1.0-rc4")
        rc5 = self.commit("stand rc5")
        self.signieren("v0.1.0-rc5", ref=rc5)
        rc6 = self.commit("stand rc6")
        self.signieren("v0.1.0-rc6", ref=rc6)
        K.lock_target({"version": "v0.1.0-rc6", "commit": rc6}, "Test: gescheitert")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual((self.kopf(), self.fragen), (rc5, []))
        self.antworten = ["ja"]
        self.assertEqual(self.zen("rollback", "v0.1.0-rc6"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), rc6)
        self.assertIn("v0.1.0-rc6 ist gesperrt", self.ausgabe)

    def test_jetzt_laesst_rueckfrage_liegen(self):
        _, objekt = self.rueckfrage_bereit()
        vorher = self.kopf()
        self.assertEqual(self.bedienen(K.cmd_now, objekt), 10, self.ausgabe)
        self.assertIn("Das braucht deine Zustimmung", self.ausgabe)
        self.assertEqual((self.fragen, self.kopf()), ([], vorher))
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))

    def test_jetzt_auf_dev_unsigniert_nichts(self):
        self.kanal("dev")
        self.ohne_anker()
        neu = self.commit("neu")
        self.lauf()
        self.assertEqual(self.bedienen(K.cmd_now, neu), 10, self.ausgabe)
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
        for befehl, argumente in ((K.cmd_now, []), (K.cmd_now, ["x"]), (K.cmd_now, ["A" * 40]),
                                  (K.cmd_now, ["0" * 40, "x"]), (K.cmd_consent, []), (K.cmd_consent, ["abc"]),
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
        for argumente in ((), ("pruefen", "x"), ("installieren",), ("installieren", "jetzt"), ("installieren", "A" * 40),
                          ("installieren", "0" * 40, "x"), ("Pruefen",), ("update",), ("status",),
                          ("zustimmen",), ("zustimmen", "abc"), ("zustimmen", "A" * 40), ("zustimmen", "0" * 41),
                          ("zustimmen", "0" * 40, "x"), ("zustimmen", "0" * 39 + ";"), ("zeitpunkt",),
                          ("zeitpunkt", "nachts"), ("zeitpunkt", "sperre", "x"), ("zeitpunkt", "fenster"),
                          ("zeitpunkt", "fenster", "02:00"), ("zeitpunkt", "fenster", "2:00", "05:00"),
                          ("zeitpunkt", "fenster", "02:00", "24:00"), ("zeitpunkt", "fenster", "02:00", "05:00", "x"),
                          ("zeitpunkt", "fenster", "02:00;id", "05:00"), ("zeitpunkt", "hand", "02:00", "05:00"),
                          ("--hilfe",), ("pruefen;id",), ("",), ("basis-pruefen", "x"), ("basis-pruefen", "0" * 40),
                          ("basis-installieren",), ("basis-installieren", "A" * 40), ("basis-installieren", "0" * 39),
                          ("basis-installieren", "0" * 41), ("basis-installieren", "0" * 40, "x"),
                          ("basis-installieren", "0" * 39 + ";"), ("basis-installieren", "--zustimmung"),
                          ("basis-installieren-zustimmen",), ("basis-installieren-zustimmen", "g" * 40),
                          ("basis-installieren-zustimmen", "0" * 40, "--zustimmung"), ("basis",), ("basis-jetzt",),
                          ("basis-zustimmen", "0" * 40), ("basis-update",), ("Basis-pruefen",),
                          ("basis-automatik", "lauf")):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("zenos-kanal-bedienen:", e.stderr)
                self.assertEqual(e.stdout, "")

    @unittest.skipIf(os.geteuid() == 0, "als root würde der Helfer wirklich prüfen, installieren oder setzen")
    def test_nur_als_root(self):
        for argumente in (("pruefen",), ("installieren", "0" * 40), ("zustimmen", "0" * 40), ("zeitpunkt", "sperre"),
                          ("zeitpunkt", "fenster", "22:00", "06:00"), ("zeitpunkt", "hand"), ("zeitpunkt", "jederzeit"),
                          ("basis-pruefen",), ("basis-installieren", "0" * 40),
                          ("basis-installieren-zustimmen", "0" * 40)):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("nur als root", e.stderr)

    def test_startet_nur_mit_argumentlisten(self):
        text = lesen(HELFER)
        self.assertNotRegex(text, r"\b(eval|sh -c|bash -c)\b")
        self.assertIn('/usr/bin/python3 -I "$_programm" zeitpunkt "$@"', text)
        self.assertIn('_unit "zenos-kanal-zustimmen@$2.service"', text)
        self.assertIn('_unit "zenos-kanal-jetzt@$2.service"', text)
        self.assertIn('systemctl reset-failed -- "$unit"', text)
        # Ubuntu-Basis: prüfen über die Unit; installieren über zenos-basis (Auftrag genau für diesen Hash, dann die
        # Unit), mit Zustimmung nur über das eigene Wort (eigene polkit-Aktion mit Passwort)
        self.assertIn("_basis=/usr/local/libexec/zenos/zenos-basis", text)
        self.assertIn("_unit zenos-basis-pruefen.service", text)
        self.assertIn('/usr/bin/python3 -I "$_basis" jetzt "$2"', text)
        self.assertIn('/usr/bin/python3 -I "$_basis" zustimmen "$2"', text)
        self.assertEqual(text.count('"$_basis" zustimmen'), 1)
        teil = text.split("  basis-installieren)\n")[-1].split(";;")[0]
        self.assertNotIn("zustimmen", teil, "basis-installieren gibt nie eine Zustimmung")


class Policy(unittest.TestCase):
    """polkit: prüfen, jetzt installieren und Zeitpunkt ohne Passwort, zustimmen jedes Mal mit Passwort; für die
    Ubuntu-Basis prüfen und installieren (ohne Kernel, Firmware, Bootloader, Entfernungen) ohne Passwort, mit Zustimmung
    jedes Mal mit Passwort; alles nur in der aktiven Sitzung am Gerät und nur für den Helfer mit genau diesem ersten
    Argument."""

    def test_aktionen(self):
        aktionen = ET.parse(POLICY).getroot().findall("action")
        erwartet = {"org.zenos.kanal.pruefen": ("pruefen", "yes"), "org.zenos.kanal.installieren": ("installieren", "yes"),
                    "org.zenos.kanal.zeitpunkt": ("zeitpunkt", "yes"),
                    "org.zenos.kanal.zustimmen": ("zustimmen", "auth_admin"),
                    "org.zenos.kanal.basis-pruefen": ("basis-pruefen", "yes"),
                    "org.zenos.kanal.basis-installieren": ("basis-installieren", "yes"),
                    "org.zenos.kanal.basis-zustimmen": ("basis-installieren-zustimmen", "auth_admin")}
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

    def test_helfer_kennt_genau_diese_woerter(self):
        """Jedes erste Argument der Policy nimmt der Helfer an, und umgekehrt (sonst fiele eines auf
        org.freedesktop.policykit.exec mit Administrator-Passwort, oder eine Aktion bliebe ohne Helfer)."""
        woerter = {n.text for a in ET.parse(POLICY).getroot().findall("action") for n in a.findall("annotate")
                   if n.get("key") == "org.freedesktop.policykit.exec.argv1"}
        text = lesen(HELFER)
        teil = text.split('case "$1" in', 1)[1].split("esac\n\nif (( EUID != 0 ))", 1)[0]
        im_helfer = set()
        for zeile in teil.splitlines():
            m = re.fullmatch(r"  ([a-z|\- ]+)\)", zeile)
            if m:
                im_helfer |= {w.strip() for w in m.group(1).split("|")}
        self.assertEqual(im_helfer, woerter)


class Units(unittest.TestCase):
    def zeilen(self, name):
        return [z.strip() for z in lesen(os.path.join(UNITS, name)).splitlines()]

    def test_jetzt_und_zustimmen(self):
        jetzt = self.zeilen("zenos-kanal-jetzt@.service")
        self.assertIn("ExecStart=/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal jetzt %i", jetzt)
        self.assertFalse(os.path.exists(os.path.join(UNITS, "zenos-kanal-jetzt.service")))
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
        for name in ("zenos-kanal-jetzt@.service", "zenos-kanal-zustimmen@.service", "org.zenos.kanal.policy"):
            self.assertIn(name, modul)
        self.assertIn("datei_entfernen /etc/systemd/system/zenos-kanal-jetzt.service", modul,
                      "die frühere Unit ohne Instanz fliegt weg")
        doctor = lesen(os.path.join(WURZEL, "scripts", "doctor.d", "15-kanal.sh"))
        self.assertIn("zenos-kanal-zustimmen@.service", doctor)
        self.assertIn("zenos-kanal-jetzt@.service", doctor)


if __name__ == "__main__":
    unittest.main(verbosity=1)
