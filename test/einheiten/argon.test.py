#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-argon (Kurve, Hysterese, Pulse, I2C-Protokoll, Status, Beenden, beim Argon ONE
UP Deckel an GPIO27 und Ausschalten bei leerem Akku), den Hook system/systemd/system-shutdown/zenos-argon
(Abschaltsignal beim Ausschalten) und den Deckel-Teil von scripts/doctor.d/80-argon.sh.

Läuft ohne Hardware und ohne Abhängigkeiten ausser python3 und bash (jq für den doctor-Teil):
python3 test/einheiten/argon.test.py
"""

import datetime
import enum
import errno
import fcntl
import importlib.machinery
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
import re
import shutil
import types
import unittest
from unittest import mock

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_loader = importlib.machinery.SourceFileLoader("zenos_argon", os.path.join(WURZEL, "scripts", "bin", "zenos-argon"))
_spec = importlib.util.spec_from_loader("zenos_argon", _loader)
A = importlib.util.module_from_spec(_spec)
_loader.exec_module(A)

KURVE = A.DEFAULT_CURVE


def stille():
    return A.Log(journal=False, stream=io.StringIO())


class Uhr:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class FalscherBus:
    """Argon-Platine im Test. mit_register: Firmware mit Register 0x80 (V3), sonst nur einzelne Bytes."""

    def __init__(self, mit_register=True, vorhanden=True, start=0):
        self.mit_register = mit_register
        self.vorhanden = vorhanden
        self.register = start
        self.schreiben = []  # ("byte" | "register" | "quick", Wert)
        self.fehler = False

    def _pruefen(self, adresse):
        if adresse != A.ARGON_ADDRESS or not self.vorhanden or self.fehler:
            raise OSError(121, "Remote I/O error")

    def read_byte(self, adresse):
        self._pruefen(adresse)
        return 0

    def write_quick(self, adresse):
        self._pruefen(adresse)
        self.schreiben.append(("quick", None))

    def read_byte_data(self, adresse, register):
        self._pruefen(adresse)
        if not self.mit_register:
            return 0x1A  # alte Firmware: immer derselbe Wert
        return self.register

    def write_byte_data(self, adresse, register, wert):
        self._pruefen(adresse)
        self.schreiben.append(("register", wert))
        if self.mit_register and register == A.REG_DUTY_CYCLE:
            self.register = wert

    def write_byte(self, adresse, wert):
        self._pruefen(adresse)
        self.schreiben.append(("byte", wert))


class FalscherLuefter:
    def __init__(self):
        self.werte = []
        self.fehler = False

    def set_speed(self, wert):
        if self.fehler:
            raise OSError(121, "Remote I/O error")
        self.werte.append(wert)


class FalscherStatus:
    def __init__(self):
        self.geschrieben = []
        self.entfernt = False

    def write(self, daten, now=None):
        self.daten = daten
        self.geschrieben.append((daten["temperatur"]["cpu"], daten["luefter"]["prozent"]))
        return True

    def remove(self):
        self.entfernt = True


class Kurve(unittest.TestCase):
    def test_stufen_wie_im_original(self):
        erwartet = {0: 0, 40: 0, 54.9: 0, 55: 30, 57: 30, 59.9: 30, 60: 55, 64.9: 55, 65: 100, 75: 100}
        for temperatur, luefter in erwartet.items():
            self.assertEqual(A.fan_speed(temperatur, KURVE), luefter, temperatur)

    def test_mindestens_25_prozent_ausser_aus(self):
        kurve = ((40.0, 10), (50.0, 0), (60.0, 24))
        self.assertEqual(A.fan_speed(45, kurve), 25)
        self.assertEqual(A.fan_speed(62, kurve), 25)
        self.assertEqual(A.fan_speed(30, kurve), 0)

    def test_ab_80_grad_immer_voll(self):
        leise = ((50.0, 30),)
        self.assertEqual(A.fan_speed(79.9, leise), 30)
        self.assertEqual(A.fan_speed(80, leise), 100)
        self.assertEqual(A.fan_speed(95, ((50.0, 0),)), 100)

    def test_unsortierte_kurve(self):
        self.assertEqual(A.fan_speed(61, ((65.0, 100), (55.0, 30), (60.0, 55))), 55)


class Hysterese(unittest.TestCase):
    def setUp(self):
        self.regler = A.FanController(A.Config())
        self.uhr = Uhr()

    def schritt(self, temperatur, sekunden=5):
        self.uhr.t += sekunden
        return self.regler.update(temperatur, self.uhr())

    def test_erster_wert_sofort(self):
        self.assertEqual(self.schritt(50), 0)
        self.assertIsNone(self.schritt(50))

    def test_schneller_sofort(self):
        self.schritt(50)
        self.assertEqual(self.schritt(56), 30)
        self.assertEqual(self.schritt(66), 100)
        self.assertIsNone(self.schritt(70))

    def test_langsamer_erst_unter_der_hysterese(self):
        self.schritt(61)  # 55 %
        # 58 °C: Kurve sagt 30 %, aber 58 + 3 = 61 liegt noch in der Stufe → bleibt
        for _ in range(20):
            self.assertIsNone(self.schritt(58))
        self.assertEqual(self.regler.speed, 55)

    def test_langsamer_nach_30_sekunden(self):
        self.schritt(61)
        self.assertIsNone(self.schritt(56.9, 0))  # 56,9 + 3 < 60: Absenken vorgemerkt
        self.assertIsNone(self.schritt(56.9, 29))
        self.assertEqual(self.schritt(56.9, 1), 30)

    def test_verzoegerung_beginnt_neu(self):
        self.schritt(61)
        self.schritt(56, 0)
        self.schritt(56, 20)
        self.assertIsNone(self.schritt(58, 5))  # zurück im Band: Zähler weg
        self.assertIsNone(self.schritt(56, 5))
        self.assertIsNone(self.schritt(56, 25))
        self.assertEqual(self.schritt(56, 5), 30)

    def test_absenken_auf_den_wert_mit_hysterese(self):
        self.schritt(70)  # 100 %
        self.schritt(50, 0)
        self.assertEqual(self.schritt(50, 30), 0)  # 50 + 3 < 55 → aus

    def test_absenken_um_eine_stufe(self):
        self.schritt(70)
        self.schritt(59, 0)  # 59 + 3 = 62 → 55 %
        self.assertEqual(self.schritt(59, 30), 55)

    def test_steigen_waehrend_verzoegerung(self):
        self.schritt(61)
        self.schritt(56, 0)
        self.assertEqual(self.schritt(66, 10), 100)
        self.assertIsNone(self.regler._lower_since)

    def test_ohne_hysterese_und_verzoegerung(self):
        regler = A.FanController(A.Config(hysteresis=0, delay=0))
        self.assertEqual(regler.update(61, 0), 55)
        self.assertEqual(regler.update(59.9, 1), 30)
        self.assertEqual(regler.update(54.9, 2), 0)

    def test_unbekannte_temperatur_heisst_voll(self):
        self.schritt(50)
        self.assertEqual(self.schritt(None), 100)
        self.assertIsNone(self.schritt(None))
        # wieder lesbar: normal absenken (mit Verzögerung)
        self.assertIsNone(self.schritt(50, 0))
        self.assertEqual(self.schritt(50, 30), 0)

    def test_vergessen_setzt_neu(self):
        self.schritt(61)
        self.regler.forget()
        self.assertEqual(self.schritt(61), 55)


class Konfiguration(unittest.TestCase):
    def test_standard(self):
        config, fehler, hinweise = A.validate_config({})
        self.assertEqual((fehler, hinweise), ([], []))
        self.assertEqual(config.curve, ((55.0, 30), (60.0, 55), (65.0, 100)))
        self.assertEqual((config.hysteresis, config.delay), (3.0, 30.0))

    def test_eigene_kurve(self):
        daten = {"kurve": [{"temperatur": 70, "luefter": 100}, {"temperatur": 50, "luefter": 40.0}],
                 "hysterese": 2.5, "absenkenNachSekunden": 0}
        config, fehler, _ = A.validate_config(daten)
        self.assertEqual(fehler, [])
        self.assertEqual(config.curve, ((50.0, 40), (70.0, 100)))
        self.assertEqual((config.hysteresis, config.delay), (2.5, 0.0))

    def test_unbekannte_schluessel_nur_hinweis(self):
        config, fehler, hinweise = A.validate_config({"luefterkurve": [], "kurve": [{"temperatur": 50,
                                                                                       "luefter": 30, "x": 1}]})
        self.assertEqual(fehler, [])
        self.assertEqual(len(hinweise), 2)
        self.assertIsNotNone(config)

    def test_ungueltig(self):
        faelle = [
            [],
            {"kurve": []},
            {"kurve": {"55": 30}},
            {"kurve": [{"temperatur": 55}]},
            {"kurve": [{"temperatur": "55", "luefter": 30}]},
            {"kurve": [{"temperatur": 55, "luefter": 30.5}]},
            {"kurve": [{"temperatur": 55, "luefter": 130}]},
            {"kurve": [{"temperatur": -5, "luefter": 30}]},
            {"kurve": [{"temperatur": True, "luefter": 30}]},
            {"kurve": [{"temperatur": 55, "luefter": 30}, {"temperatur": 55, "luefter": 40}]},
            {"kurve": [{"temperatur": 55, "luefter": 60}, {"temperatur": 65, "luefter": 30}]},
            {"kurve": [{"temperatur": 50 + i, "luefter": 30} for i in range(11)]},
            {"hysterese": 11},
            {"hysterese": "3"},
            {"absenkenNachSekunden": -1},
            {"absenkenNachSekunden": float("nan")},
        ]
        for daten in faelle:
            config, fehler, _ = A.validate_config(daten)
            self.assertIsNone(config, daten)
            self.assertTrue(fehler, daten)

    def test_datei(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "argon.json")
            config, fehler, _, eigen = A.load_config(pfad)
            self.assertEqual((fehler, eigen), ([], False))
            with open(pfad, "w", encoding="utf-8") as f:
                f.write("{kaputt")
            config, fehler, _, eigen = A.load_config(pfad)
            self.assertTrue(fehler)
            self.assertTrue(eigen)
            self.assertEqual(config.curve, A.Config().curve)

    def test_beschreibung(self):
        self.assertEqual(A.Config().describe(),
                         "55 °C → 30 % · 60 °C → 55 % · 65 °C → 100 % · Hysterese 3 °C · absenken nach 30 s")
        self.assertIn("2,5 °C", A.Config(hysteresis=2.5).describe())


class Pulse(unittest.TestCase):
    def test_nennwerte_des_originals(self):
        for ms in (20, 25, 30):
            self.assertEqual(A.classify_pulse(ms), "neustart", ms)
        for ms in (40, 45, 50):
            self.assertEqual(A.classify_pulse(ms), "ausschalten", ms)

    def test_grenzen(self):
        erwartet = {0: None, 5: None, 14.9: None, 15: "neustart", 34.9: "neustart", 35: "ausschalten",
                    54.9: "ausschalten", 55: None, 65: None, 100: None, 3000: None}
        for ms, aktion in erwartet.items():
            self.assertEqual(A.classify_pulse(ms), aktion, ms)

    def test_flanken_paaren(self):
        erkenner = A.PulseDetector()
        self.assertIsNone(erkenner.edge(False, 1_000))  # fallend ohne steigend
        self.assertIsNone(erkenner.edge(True, 10_000_000))
        self.assertAlmostEqual(erkenner.edge(False, 35_000_000), 25.0)
        self.assertIsNone(erkenner.edge(False, 40_000_000))
        # zweimal steigend: die neuere zählt
        erkenner.edge(True, 100_000_000)
        erkenner.edge(True, 200_000_000)
        self.assertAlmostEqual(erkenner.edge(False, 245_000_000), 45.0)


class I2C(unittest.TestCase):
    def test_register_erkannt_und_wiederhergestellt(self):
        bus = FalscherBus(mit_register=True, start=40)
        luefter = A.ArgonFan(bus, sleep=lambda s: None)
        self.assertTrue(luefter.detect_register())
        self.assertEqual(bus.schreiben, [("register", 41), ("register", 40)])
        luefter.set_speed(55)
        self.assertEqual(bus.schreiben[-1], ("register", 55))
        self.assertEqual(bus.register, 55)

    def test_probewert_unter_100(self):
        bus = FalscherBus(mit_register=True, start=99)
        A.ArgonFan(bus, sleep=lambda s: None).detect_register()
        self.assertEqual(bus.schreiben[0], ("register", 98))

    def test_alte_firmware_einzelnes_byte(self):
        bus = FalscherBus(mit_register=False)
        luefter = A.ArgonFan(bus, sleep=lambda s: None)
        self.assertFalse(luefter.detect_register())
        luefter.set_speed(30)
        self.assertEqual(bus.schreiben[-1], ("byte", 30))

    def test_werte_begrenzt(self):
        bus = FalscherBus(mit_register=False)
        luefter = A.ArgonFan(bus, sleep=lambda s: None)
        luefter.set_speed(130)
        luefter.set_speed(-5)
        self.assertEqual(bus.schreiben, [("byte", 100), ("byte", 0)])

    def test_pause_nach_jedem_schreiben(self):
        pausen = []
        luefter = A.ArgonFan(FalscherBus(mit_register=False), sleep=pausen.append)
        luefter.set_speed(30)
        self.assertEqual(pausen, [1.0])

    def test_vorhanden(self):
        self.assertTrue(A.ArgonFan(FalscherBus()).present())
        self.assertFalse(A.ArgonFan(FalscherBus(vorhanden=False)).present())

        class NurQuick(FalscherBus):
            def read_byte(self, adresse):
                raise OSError(5, "I/O error")

        bus = NurQuick()
        self.assertTrue(A.ArgonFan(bus).present())
        self.assertEqual(bus.schreiben, [("quick", None)])

    def test_anlaufhilfe_nur_aus_dem_stillstand(self):
        luefter = FalscherLuefter()
        A.apply_speed(luefter, 30, None)
        A.apply_speed(luefter, 55, 30)
        A.apply_speed(luefter, 30, 55)
        A.apply_speed(luefter, 0, 30)
        A.apply_speed(luefter, 55, 0)
        A.apply_speed(luefter, 100, 0)
        self.assertEqual(luefter.werte, [100, 30, 55, 30, 0, 100, 55, 100])


class Dienst(unittest.TestCase):
    def dienst(self, temperaturen, herunterfahren=False, konfig="/gibt/es/nicht.json"):
        self.uhr = Uhr()
        self.luefter = FalscherLuefter()
        self.status = FalscherStatus()
        self.aufrufe = []
        folge = iter(temperaturen)

        def ausfuehren(befehl, **kwargs):
            self.aufrufe.append(befehl)
            return subprocess.CompletedProcess(befehl, 0)

        return A.Daemon(self.luefter, stille(), self.status, konfig, lambda: next(folge), clock=self.uhr,
                        runner=ausfuehren, stopping=lambda: herunterfahren)

    def test_takt_setzt_und_meldet(self):
        d = self.dienst([50, 61, 61])
        d.tick()
        d.tick()
        d.tick()
        self.assertEqual(self.luefter.werte, [0, 100, 55])
        self.assertEqual(self.status.geschrieben, [(50, 0), (61, 55), (61, 55)])

    def test_i2c_fehler_wird_wiederholt(self):
        d = self.dienst([61, 61, 61])
        self.luefter.fehler = True
        d.tick()
        self.assertEqual(self.status.geschrieben[-1], (61, None))
        d.tick()
        self.luefter.fehler = False
        d.tick()
        self.assertEqual(self.luefter.werte, [100, 55])
        self.assertEqual(self.status.geschrieben[-1], (61, 55))

    def test_beenden_im_betrieb_voll(self):
        d = self.dienst([50])
        d.run(0, rounds=1)
        self.assertEqual(self.luefter.werte, [0, 100])
        self.assertTrue(self.status.entfernt)

    def test_beenden_beim_herunterfahren_aus(self):
        d = self.dienst([61], herunterfahren=True)
        d.run(0, rounds=1)
        self.assertEqual(self.luefter.werte[-1], 0)

    def test_knopf_neustart_und_ausschalten(self):
        d = self.dienst([])
        d.on_pulse(25)
        self.assertEqual(self.aufrufe, [["systemctl", "reboot"]])
        d.on_pulse(45)  # schon ausgelöst: nichts mehr
        self.assertEqual(len(self.aufrufe), 1)
        d = self.dienst([])
        d.on_pulse(62)
        d.on_pulse(8)
        self.assertEqual(self.aufrufe, [])
        d.on_pulse(45)
        self.assertEqual(self.aufrufe, [["systemctl", "poweroff"]])

    def test_knopf_fehlschlag_erlaubt_neuen_versuch(self):
        d = self.dienst([])
        aufrufe = []

        def scheitern(befehl, **kwargs):
            aufrufe.append(befehl)
            return subprocess.CompletedProcess(befehl, 1)

        d.runner = scheitern
        d.on_pulse(25)
        d.on_pulse(25)
        self.assertEqual(len(aufrufe), 2)

    def test_simulation_fuehrt_nichts_aus(self):
        d = self.dienst([])
        d.simulate = True
        d.on_pulse(25)
        d.on_pulse(45)
        self.assertEqual(self.aufrufe, [])

    def test_konfiguration_wird_neu_gelesen(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "argon.json")
            d = self.dienst([58, 58], konfig=pfad)
            d.tick()
            self.assertEqual(self.luefter.werte, [100, 30])
            with open(pfad, "w", encoding="utf-8") as f:
                json.dump({"kurve": [{"temperatur": 50, "luefter": 80}]}, f)
            d.tick()
            self.assertEqual(self.luefter.werte[-1], 80)

    def test_herunterfahren_erkennen(self):
        def laeuft(zustand):
            return lambda befehl, **kwargs: subprocess.CompletedProcess(befehl, 0, stdout=zustand + "\n")

        self.assertTrue(A.system_stopping(laeuft("stopping")))
        self.assertFalse(A.system_stopping(laeuft("running")))
        self.assertFalse(A.system_stopping(laeuft("degraded")))

        def fehlt(befehl, **kwargs):
            raise FileNotFoundError(befehl[0])

        self.assertFalse(A.system_stopping(fehlt))


class Statusdatei(unittest.TestCase):
    def test_atomar_und_lesbar(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "zenos", "geraet.json")
            status = A.StatusFile(pfad, stille())
            self.assertTrue(status.write(A.argon_v3_report(46.64, 30)))
            with open(pfad, encoding="utf-8") as f:
                daten = json.load(f)
            self.assertEqual(daten["version"], 1)
            self.assertEqual(daten["geraet"], "argon-one-v3")
            self.assertEqual(daten["temperatur"], {"cpu": 46.6})
            self.assertEqual(daten["luefter"], {"vorhanden": True, "prozent": 30, "modus": "auto", "mindeststufe": None,
                                                "steuerbar": False})
            self.assertEqual(daten["akku"], {"vorhanden": False})
            self.assertRegex(daten["zeit"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$")
            self.assertEqual(stat.S_IMODE(os.stat(pfad).st_mode), 0o644)
            self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(pfad)).st_mode) & 0o022, 0)
            status.write(A.argon_v3_report(None, None))
            with open(pfad, encoding="utf-8") as f:
                daten = json.load(f)
            self.assertEqual((daten["temperatur"], daten["luefter"]["prozent"]), ({"cpu": None}, None))
            self.assertEqual(os.listdir(os.path.dirname(pfad)), ["geraet.json"])
            status.remove()
            self.assertFalse(os.path.exists(pfad))

    def test_nicht_schreibbar(self):
        log = A.Log(journal=False, stream=io.StringIO())
        status = A.StatusFile("/proc/gibt-es-nicht/geraet.json", log)
        self.assertFalse(status.write(A.argon_v3_report(50, 0)))
        self.assertFalse(status.write(A.argon_v3_report(50, 0)))
        self.assertEqual(log.stream.getvalue().count("lässt sich nicht schreiben"), 1)


class Gpio(unittest.TestCase):
    def falsches_gpiod(self, chips):
        class Info:
            def __init__(self, label):
                self.label = label

        class Chip:
            def __init__(self, pfad):
                self.pfad = pfad

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def get_info(self):
                return Info(chips[self.pfad][0])

            def line_offset_from_id(self, name):
                zeilen = chips[self.pfad][1]
                if name not in zeilen:
                    raise FileNotFoundError(2, "No such file or directory")
                return zeilen.index(name)

        class Modul:
            @staticmethod
            def is_gpiochip_device(pfad):
                return pfad in chips

        Modul.Chip = Chip
        return Modul

    def test_rp1_hat_vorrang(self):
        chips = {
            "/dev/gpiochip0": ("gpio-brcmstb@107d508500", ["-", "2712_BOOT_CS_N"]),
            "/dev/gpiochip4": ("pinctrl-rp1", ["ID_SDA", "ID_SCL", "GPIO2", "GPIO3", "GPIO4"]),
            "/dev/gpiochip10": ("anderer", ["GPIO4"]),
        }
        gpiod = self.falsches_gpiod(chips)
        self.assertEqual(A.find_button_line(gpiod, sorted(chips) + ["/dev/gpiochip9"]),
                         ("/dev/gpiochip4", 4, "pinctrl-rp1"))

    def test_ohne_rp1_der_erste_treffer(self):
        chips = {"/dev/gpiochip10": ("b", ["GPIO4"]), "/dev/gpiochip2": ("a", ["x", "GPIO4"])}
        gpiod = self.falsches_gpiod(chips)
        self.assertEqual(A.find_button_line(gpiod, sorted(chips)), ("/dev/gpiochip2", 1, "a"))

    def test_keine_zeile(self):
        gpiod = self.falsches_gpiod({"/dev/gpiochip0": ("ARMH0061:00", ["a", "b"])})
        self.assertIsNone(A.find_button_line(gpiod, ["/dev/gpiochip0"]))
        self.assertIsNone(A.find_button_line(gpiod, []))


class SofortStop(threading.Event):
    """Stop-Ereignis, dessen Warten nicht blockiert (Wiederholungen ohne 10 s Pause)."""

    def wait(self, timeout=None):
        return self.is_set()


class Knopf(unittest.TestCase):
    def setUp(self):
        self.vorher = {name: sys.modules.get(name) for name in ("gpiod", "gpiod.line")}
        self.finden = A.find_button_line
        A.find_button_line = lambda gpiod: ("/dev/gpiochip0", 4, "pinctrl-rp1")

    def tearDown(self):
        A.find_button_line = self.finden
        for name, modul in self.vorher.items():
            if modul is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = modul

    def falsches_gpiod(self, stop, runden, fehler=None):
        line = types.ModuleType("gpiod.line")

        class Direction(enum.Enum):
            INPUT = 2

        class Edge(enum.Enum):
            BOTH = 4

        class Typ(enum.Enum):
            RISING_EDGE = 1
            FALLING_EDGE = 2

        line.Direction, line.Edge = Direction, Edge
        gpiod = types.ModuleType("gpiod")
        gpiod.line = line
        gpiod.EdgeEvent = types.SimpleNamespace(Type=Typ)
        gpiod.LineSettings = lambda **einstellungen: einstellungen
        self.anfragen = []
        offen = list(runden)

        class Anfrage:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def wait_edge_events(self, timeout):
                if not offen:
                    stop.set()
                    return False
                return True

            def read_edge_events(self):
                return [types.SimpleNamespace(event_type=Typ.RISING_EDGE if steigend else Typ.FALLING_EDGE,
                                              timestamp_ns=ns) for steigend, ns in offen.pop(0)]

        def request_lines(pfad, consumer, config):
            self.anfragen.append((pfad, consumer, config))
            if fehler is not None:
                raise fehler
            return Anfrage()

        gpiod.request_lines = request_lines
        sys.modules["gpiod"] = gpiod
        sys.modules["gpiod.line"] = line
        return Edge

    def test_flanken_werden_zu_pulsen(self):
        stop = SofortStop()
        edge = self.falsches_gpiod(stop, [[(True, 1_000_000), (False, 26_000_000)],
                                          [(False, 30_000_000), (True, 100_000_000)],
                                          [(False, 145_500_000)]])
        pulse = []
        A.ButtonWatcher(stop, pulse.append, stille()).run()
        self.assertEqual(pulse, [25.0, 45.5])
        pfad, consumer, config = self.anfragen[0]
        self.assertEqual((pfad, consumer), ("/dev/gpiochip0", "zenos-argon"))
        self.assertEqual(config[4]["edge_detection"], edge.BOTH)

    def test_belegte_zeile(self):
        stop = SofortStop()
        self.falsches_gpiod(stop, [], fehler=OSError(errno.EBUSY, "Device or resource busy"))
        log = stille()
        A.ButtonWatcher(stop, lambda ms: None, log).run()
        self.assertEqual(len(self.anfragen), 1)
        self.assertIn("schon belegt", log.stream.getvalue())

    def test_andere_fehler_dreimal(self):
        stop = SofortStop()
        self.falsches_gpiod(stop, [], fehler=OSError(errno.EIO, "I/O error"))
        log = stille()
        A.ButtonWatcher(stop, lambda ms: None, log).run()
        self.assertEqual(len(self.anfragen), 3)
        self.assertIn("aufgegeben", log.stream.getvalue())

    def test_unerwarteter_fehler_beendet_nur_den_knopf(self):
        stop = SofortStop()
        self.falsches_gpiod(stop, [], fehler=RuntimeError("kaputt"))
        log = stille()
        A.ButtonWatcher(stop, lambda ms: None, log).run()
        self.assertIn("unerwarteter Fehler", log.stream.getvalue())


class Aufruf(unittest.TestCase):
    def test_optionen(self):
        o = A.parse_args(["--simulieren", "--temperatur", "61,5", "--puls", "25", "--puls", "45",
                          "--intervall", "0.2", "--durchlaeufe", "3", "--status-datei", "/srv/x.json"])
        self.assertEqual((o["mode"], o["temperatur"], o["pulse"], o["intervall"], o["durchlaeufe"], o["status"]),
                         ("simulation", 61.5, [25.0, 45.0], 0.2, 3, "/srv/x.json"))
        self.assertEqual(A.parse_args([])["mode"], "dienst")
        # ohne --intervall entscheidet das Gerät (V3 5 s, UP 15 s)
        self.assertIsNone(A.parse_args([])["intervall"])

    def test_falsche_aufrufe(self):
        for argv in (["--temperatur", "50"], ["--simulieren", "--temperatur"], ["--intervall", "0"],
                     ["--simulieren", "--pruefen"], ["--gibt-es-nicht"], ["--durchlaeufe", "x"],
                     ["--simulieren", "--temperatur", "50", "--temperatur-datei", "/x"]):
            with self.assertRaises(A.UsageError, msg=argv):
                A.parse_args(argv)

    def test_temperatur_datei(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "t")
            for inhalt, wert in (("58.5\n", 58.5), ("61500", 61.5), ("57,2", 57.2), ("warm", None), ("", None)):
                with open(pfad, "w", encoding="utf-8") as f:
                    f.write(inhalt)
                self.assertEqual(A.read_temperature_file(pfad), wert, inhalt)
            self.assertIsNone(A.read_temperature_file(os.path.join(ordner, "fehlt")))

    def test_pi5_erkennen(self):
        self.assertTrue(A.is_pi5("Raspberry Pi 5 Model B Rev 1.0"))
        self.assertFalse(A.is_pi5("Raspberry Pi 4 Model B Rev 1.5"))
        self.assertFalse(A.is_pi5("Raspberry Pi Compute Module 5 Lite Rev 1.0"))
        self.assertFalse(A.is_pi5(""))

    def test_cm5_erkennen(self):
        self.assertTrue(A.is_cm5("Raspberry Pi Compute Module 5 Lite Rev 1.0"))
        self.assertTrue(A.is_cm5("Raspberry Pi Compute Module 5 Rev 1.0"))
        self.assertFalse(A.is_cm5("Raspberry Pi Compute Module 4 Rev 1.1"))
        self.assertFalse(A.is_cm5("Raspberry Pi 5 Model B Rev 1.0"))


# --- Hook für systemd-shutdown (system/systemd/system-shutdown/zenos-argon) ---

HOOK = os.path.join(WURZEL, "system", "systemd", "system-shutdown", "zenos-argon")
PI5 = "Raspberry Pi 5 Model B Rev 1.1"

# Nachgebaute i2cget/i2cset (Aufrufe wie i2c-tools 4.4) und sleep. Zustand im Ordner i2c der Testwurzel:
# «art» register | register-ohne-byte | byte | stumm | schreibfehler, Register als reg-<hex>, jeder Aufruf
# in «protokoll».
FALSCHE_WERKZEUGE = r'''
import os, sys
D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "i2c")
name, args = os.path.basename(sys.argv[0]), sys.argv[1:]
with open(os.path.join(D, "protokoll"), "a", encoding="utf-8") as f:
    f.write(" ".join([name] + args) + "\n")
if name == "sleep":
    sys.exit(0)
with open(os.path.join(D, "art"), encoding="utf-8") as f:
    art = f.read().strip()

def fehler(text):
    print("Error: " + text, file=sys.stderr)
    sys.exit(1)

def register(nummer):
    try:
        with open(os.path.join(D, "reg-%02x" % nummer), encoding="utf-8") as f:
            return int(f.read())
    except OSError:
        return 0

if args[:3] != ["-y", "1", "0x1a"]:
    fehler("unerwarteter Aufruf")
rest = args[3:]
if art == "stumm":
    fehler("Read failed")
if name == "i2cget":
    if not rest:
        if art == "register-ohne-byte":
            fehler("Read failed")
        print("0x5a")
    elif len(rest) == 2 and rest[1] == "b":
        print("0x%02x" % (0 if art == "byte" else register(int(rest[0], 16))))
    else:
        fehler("unerwarteter Aufruf")
elif name == "i2cset":
    if art == "schreibfehler":
        fehler("Write failed")
    if len(rest) == 3 and rest[2] == "b":
        if art != "byte":
            with open(os.path.join(D, "reg-%02x" % int(rest[0], 16)), "w", encoding="utf-8") as f:
                f.write(str(int(rest[1], 0)))
    elif not (len(rest) == 2 and rest[1] == "c"):
        fehler("unerwarteter Aufruf")
'''

ERKENNEN = ["i2cget -y 1 0x1a", "i2cget -y 1 0x1a 0x80 b"]


def pruefen_mit_register(alt, probe):
    """Protokoll wie argonregister_checksupport + signalpoweroff im Original (nach jedem Schreiben 1 s)."""
    return ["i2cget -y 1 0x1a 0x80 b", f"i2cset -y 1 0x1a 0x80 {probe} b", "sleep 1",
            "i2cget -y 1 0x1a 0x80 b", f"i2cset -y 1 0x1a 0x80 {alt} b", "sleep 1",
            "i2cset -y 1 0x1a 0x86 1 b", "sleep 1"]


class Abschaltsignal(unittest.TestCase):
    """Hook mit Testwurzel: Pi-Modell, /dev/i2c-1, PID 1 und die i2c-tools sind nachgebaut."""

    def setUp(self):
        self._ordner = tempfile.TemporaryDirectory()
        self.w = self._ordner.name
        self.einrichten()

    def tearDown(self):
        self._ordner.cleanup()

    def pfad(self, *teile):
        return os.path.join(self.w, *teile)

    def schreiben(self, inhalt, *teile):
        pfad = self.pfad(*teile)
        os.makedirs(os.path.dirname(pfad), exist_ok=True)
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(inhalt)
        return pfad

    def einrichten(self, art="register", register=0, modell=PI5, i2c=True, pid1="systemd-shutdow",
                   dienst=True, original=False, werkzeuge=True):
        self.schreiben(art + "\n", "i2c", "art")
        self.schreiben("", "i2c", "protokoll")
        self.schreiben(str(register), "i2c", "reg-80")
        if pid1 is not None:
            self.schreiben(pid1 + "\n", "proc", "1", "comm")
        if modell is not None:
            self.schreiben(modell + "\0", "sys", "firmware", "devicetree", "base", "model")
        if i2c:
            os.makedirs(self.pfad("dev"), exist_ok=True)
            os.symlink("/dev/null", self.pfad("dev", "i2c-1"))
        if dienst:
            self.schreiben("", "etc", "systemd", "system", "multi-user.target.wants", "zenos-argon.service")
        if original:
            self.schreiben("#!/bin/bash\n", "usr", "lib", "systemd", "system-shutdown", "argon-shutdown.sh")
        namen = ("i2cget", "i2cset", "sleep") if werkzeuge else ("sleep",)
        for name in namen:
            pfad = self.schreiben(f"#!{sys.executable}\n{FALSCHE_WERKZEUGE}", "bin", name)
            os.chmod(pfad, 0o755)

    def neu(self, **einstellungen):
        self._ordner.cleanup()
        self._ordner = tempfile.TemporaryDirectory()
        self.w = self._ordner.name
        self.einrichten(**einstellungen)

    def hook(self, *argumente, wurzel=None):
        umgebung = {"ZENOS_ARGON_TESTWURZEL": self.w if wurzel is None else wurzel}
        ergebnis = subprocess.run(["/bin/bash", HOOK, *argumente], env=umgebung, capture_output=True,
                                  text=True, encoding="utf-8", timeout=30, check=False)
        with open(self.pfad("i2c", "protokoll"), encoding="utf-8") as f:
            protokoll = f.read().splitlines()
        return ergebnis.returncode, ergebnis.stdout, ergebnis.stderr, protokoll

    def register80(self):
        with open(self.pfad("i2c", "reg-80"), encoding="utf-8") as f:
            return int(f.read())

    def test_ausschalten_mit_register(self):
        for aktion in ("poweroff", "halt"):
            with self.subTest(aktion):
                self.neu()
                code, aus, err, protokoll = self.hook(aktion)
                self.assertEqual(protokoll, ERKENNEN[:1] + pruefen_mit_register(0, 1))
                self.assertEqual(aus, "zenos-argon: Abschaltsignal an den Argon ONE (Register 0x86)\n")
                self.assertEqual((code, err), (0, ""))
                self.assertEqual(self.register80(), 0)

    def test_neustart_sendet_nichts(self):
        for aktion in ("reboot", "kexec", "unbekannt"):
            with self.subTest(aktion):
                self.assertEqual(self.hook(aktion), (0, "", "", []))

    def test_luefterregister_wiederhergestellt(self):
        # wie im Original: alt + 1, ab 100 dann 98; zurück höchstens auf 100
        for alt, probe, danach in ((42, 43, 42), (99, 98, 99), (255, 98, 100)):
            with self.subTest(alt=alt):
                self.neu(register=alt)
                code, _, _, protokoll = self.hook("poweroff")
                self.assertEqual(code, 0)
                self.assertEqual(protokoll, ERKENNEN[:1] + pruefen_mit_register(danach, probe))
                self.assertEqual(self.register80(), danach)

    def test_antwort_nur_ueber_register(self):
        self.neu(art="register-ohne-byte", register=30)
        code, aus, _, protokoll = self.hook("poweroff")
        self.assertEqual(protokoll, ERKENNEN + pruefen_mit_register(30, 31))
        self.assertIn("Register 0x86", aus)
        self.assertEqual(code, 0)

    def test_firmware_ohne_register(self):
        self.neu(art="byte")
        code, aus, err, protokoll = self.hook("halt")
        self.assertEqual(protokoll, ERKENNEN + ["i2cset -y 1 0x1a 0x80 1 b", "sleep 1", "i2cget -y 1 0x1a 0x80 b",
                                                "i2cset -y 1 0x1a 0xff c", "sleep 1"])
        self.assertEqual(aus, "zenos-argon: Abschaltsignal an den Argon ONE (Byte 0xFF)\n")
        self.assertEqual((code, err), (0, ""))

    def test_kein_geraet_an_0x1a(self):
        self.neu(art="stumm")
        self.assertEqual(self.hook("poweroff"), (0, "", "", ERKENNEN))

    def test_schreibfehler(self):
        self.neu(art="schreibfehler")
        code, aus, err, protokoll = self.hook("poweroff")
        self.assertEqual(protokoll, ERKENNEN + ["i2cset -y 1 0x1a 0x80 1 b", "i2cset -y 1 0x1a 0xff c"])
        self.assertIn("Byte 0xFF", aus)
        self.assertEqual((code, err), (1, "zenos-argon: Das Abschaltsignal liess sich nicht senden.\n"))

    def test_still_ohne_voraussetzung(self):
        faelle = {
            "ohne /dev/i2c-1": {"i2c": False},
            "ohne Gerätebaum": {"modell": None},
            "Pi 4": {"modell": "Raspberry Pi 4 Model B Rev 1.5"},
            "Dienst nicht aktiviert": {"dienst": False},
            "Originalskript": {"original": True},
            "ohne i2c-tools": {"werkzeuge": False},
        }
        for name, einstellungen in faelle.items():
            for aktion in ("poweroff", "halt", "reboot"):
                with self.subTest(name, aktion=aktion):
                    self.neu(**einstellungen)
                    self.assertEqual(self.hook(aktion), (0, "", "", []))

    def test_nie_im_laufenden_system(self):
        for pid1 in ("systemd", None):
            with self.subTest(pid1=pid1):
                self.neu(pid1=pid1)
                code, aus, err, protokoll = self.hook("poweroff")
                self.assertEqual((code, aus, protokoll), (1, "", []))
                self.assertIn("nur beim Herunterfahren", err)
                self.assertIn("--simulieren poweroff", err)
                self.assertEqual(self.hook("reboot"), (0, "", "", []))

    def test_simulieren_liest_nur(self):
        for pid1 in ("systemd", "systemd-shutdow"):
            with self.subTest(pid1=pid1):
                self.neu(register=42, pid1=pid1)
                code, aus, err, protokoll = self.hook("--simulieren", "poweroff")
                self.assertEqual(protokoll, ERKENNEN)
                self.assertEqual((code, err), (0, ""))
                zeilen = aus.splitlines()
                self.assertEqual(zeilen[0], "Argon ONE antwortet an 0x1a, Register 0x80 (Lüfter) = 42.")
                self.assertIn("Register 0x86 = 1", zeilen[1])
                self.assertEqual(zeilen[-1], "Simulation: Es wurde nichts gesendet.")
                self.assertEqual(self.register80(), 42)

    def test_simulieren_erklaert(self):
        faelle = (
            ({}, ("--simulieren", "reboot"), "Bei «reboot» bekommt die Platine kein Abschaltsignal."),
            ({"art": "stumm"}, ("--simulieren", "poweroff"), "Kein Gerät antwortet an 0x1a."),
            ({"i2c": False}, ("--simulieren", "poweroff"), "I2C-Bus 1 fehlt ({w}/dev/i2c-1)."),
            ({"modell": None}, ("--simulieren", "halt"), "Kein Raspberry Pi 5 (kein Gerätebaum)."),
            ({"dienst": False}, ("--simulieren", "poweroff"), "zenos-argon.service ist nicht aktiviert."),
            ({"original": True}, ("--simulieren", "poweroff"),
             "Das Argon-Originalskript sendet selbst ({w}/usr/lib/systemd/system-shutdown/argon-shutdown.sh)."),
            ({"werkzeuge": False}, ("--simulieren", "poweroff"), "i2cget oder i2cset fehlt (Paket i2c-tools)."),
        )
        for einstellungen, argumente, grund in faelle:
            with self.subTest(grund):
                self.neu(**einstellungen)
                code, aus, err, protokoll = self.hook(*argumente)
                self.assertEqual((code, err), (0, ""))
                self.assertEqual(aus, "Nichts zu tun: " + grund.format(w=self.w) + "\n")
                self.assertNotIn("i2cset", "\n".join(protokoll))

    def test_simulieren_ohne_zugriff(self):
        if os.geteuid() == 0:
            self.skipTest("als root ist jedes Gerät zugänglich")
        gesperrt = None
        for name in sorted(os.listdir("/dev")):
            pfad = os.path.join("/dev", name)
            try:
                if stat.S_ISCHR(os.stat(pfad).st_mode) and not os.access(pfad, os.R_OK | os.W_OK):
                    gesperrt = pfad
                    break
            except OSError:
                continue
        if gesperrt is None:
            self.skipTest("kein gesperrtes Zeichengerät in /dev")
        self.neu(i2c=False)
        os.makedirs(self.pfad("dev"))
        os.symlink(gesperrt, self.pfad("dev", "i2c-1"))
        code, aus, _, protokoll = self.hook("--simulieren", "poweroff")
        self.assertEqual((code, protokoll), (0, []))
        self.assertEqual(aus, f"Nichts zu tun: Kein Zugriff auf {self.w}/dev/i2c-1 (mit sudo aufrufen).\n")

    def test_aufruf(self):
        for argumente in ((), ("poweroff", "halt"), ("--simulieren",), ("--simulieren", "halt", "x")):
            with self.subTest(argumente=argumente):
                code, aus, err, protokoll = self.hook(*argumente)
                self.assertEqual((code, aus, protokoll), (2, "", []))
                self.assertEqual(err, "Aufruf: zenos-argon [--simulieren] poweroff|halt|reboot|kexec\n")

    def test_testwurzel_muss_eigener_ordner_sein(self):
        for wurzel in ("/", "relativ", os.path.join(self.w, "fehlt")):
            with self.subTest(wurzel=wurzel):
                code, aus, err, protokoll = self.hook("poweroff", wurzel=wurzel)
                self.assertEqual((code, aus, protokoll), (2, "", []))
                self.assertIn("ZENOS_ARGON_TESTWURZEL", err)


# --- Deckel des Argon ONE UP (GPIO27) -------------------------------------------

DECKEL_CHIPS = {
    # wie am Gerät: RP1 an /dev/gpiochip0, «GPIO27» ist Zeile 27; der brcmstb-Chip hat keine solche Leitung
    "/dev/gpiochip0": ("pinctrl-rp1", ["ID_SDA", "ID_SCL"] + [f"GPIO{n}" for n in range(2, 28)]),
    "/dev/gpiochip10": ("gpio-brcmstb@107d508500", ["-", "2712_BOOT_CS_N", "PWR_GPIO"]),
}


def falsches_gpiod(test, chips=None, drehbuch=(), pegel=1, fehler=None, belegt=None):
    """python3-libgpiod (v2) im Test, eingesetzt als sys.modules["gpiod"]. drehbuch: Schritte für wait_edge_events:
    ("flanke", pegel) neue Flanke, ("ruhe",) keine Flanke, ("still", pegel) neuer Pegel ohne Flanke (verpasst). Ist
    es leer, endet der Lauf (stop). pegel: Pegel vor dem ersten Schritt. Die Anfrage kennt nur Lesen: Ein Aufruf zum
    Schreiben (set_value, reconfigure_lines …) gäbe einen AttributeError. Aufrufe stehen in test.anfragen."""
    chips = DECKEL_CHIPS if chips is None else chips
    line = types.ModuleType("gpiod.line")

    class Direction(enum.Enum):
        AS_IS = 1
        INPUT = 2
        OUTPUT = 3

    class Edge(enum.Enum):
        NONE = 1
        RISING = 2
        FALLING = 3
        BOTH = 4

    class Bias(enum.Enum):
        AS_IS = 1
        UNKNOWN = 2
        DISABLED = 3
        PULL_UP = 4
        PULL_DOWN = 5

    class Value(enum.Enum):
        INACTIVE = 0
        ACTIVE = 1

    line.Direction, line.Edge, line.Bias, line.Value = Direction, Edge, Bias, Value
    gpiod = types.ModuleType("gpiod")
    gpiod.line = line
    gpiod.LineSettings = lambda **einstellungen: einstellungen
    gpiod.is_gpiochip_device = lambda pfad: pfad in chips
    test.anfragen = []
    test.schritte = list(drehbuch)

    class Chip:
        def __init__(self, pfad):
            self.pfad = pfad

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get_info(self):
            return types.SimpleNamespace(label=chips[self.pfad][0])

        def line_offset_from_id(self, name):
            if name not in chips[self.pfad][1]:
                raise FileNotFoundError(2, "No such file or directory")
            return chips[self.pfad][1].index(name)

        def get_line_info(self, offset):
            return types.SimpleNamespace(used=belegt is not None, consumer=belegt)

    class Anfrage:
        def __init__(self):
            self.pegel = pegel
            self.wartend = 0
            self.freigegeben = False
            self.gelesen = 0

        def __enter__(self):
            return self

        def __exit__(self, *args):
            self.freigegeben = True
            return False

        def wait_edge_events(self, timeout):
            if not test.schritte:
                test.stop.set()
                return False
            schritt = test.schritte.pop(0)
            if schritt[0] == "flanke":
                self.pegel = schritt[1]
                self.wartend += 1
                return True
            if schritt[0] == "still":
                self.pegel = schritt[1]
            return False

        def read_edge_events(self):
            anzahl, self.wartend = self.wartend, 0
            return [object()] * anzahl

        def get_value(self, offset):
            self.gelesen += 1
            return Value.ACTIVE if self.pegel else Value.INACTIVE

    def request_lines(pfad, consumer, config):
        anfrage = Anfrage()
        test.anfragen.append((pfad, consumer, config, anfrage))
        if fehler is not None:
            raise fehler
        return anfrage

    gpiod.Chip = Chip
    gpiod.request_lines = request_lines
    sys.modules["gpiod"] = gpiod
    sys.modules["gpiod.line"] = line
    return line


class ModuleZurueck(unittest.TestCase):
    """Stellt gpiod in sys.modules und A.gpio_devices nach jedem Test wieder her."""

    def setUp(self):
        self.vorher = {name: sys.modules.get(name) for name in ("gpiod", "gpiod.line")}
        self.geraete = A.gpio_devices
        A.gpio_devices = lambda: sorted(DECKEL_CHIPS)
        self.stop = SofortStop()

    def tearDown(self):
        A.gpio_devices = self.geraete
        for name, modul in self.vorher.items():
            if modul is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = modul


class Deckel(ModuleZurueck):
    def lauf(self, **kwargs):
        line = falsches_gpiod(self, **kwargs)
        self.zeiten = iter(f"2026-10-05T22:40:0{n}.000+02:00" for n in range(10))
        self.lid = A.Lid(now=lambda: next(self.zeiten))
        self.gemeldet = []
        self.log = stille()
        A.LidWatcher(self.stop, self.lid, lambda: self.gemeldet.append(self.lid.report()), self.log).run()
        return line

    def logtext(self):
        return self.log.stream.getvalue()

    def test_nach_namen_gefunden_rp1_zuerst(self):
        line = falsches_gpiod(self)
        gpiod = sys.modules["gpiod"]
        self.assertIsNotNone(line)
        self.assertEqual(A.find_lid_line(gpiod), ("/dev/gpiochip0", 27, "pinctrl-rp1"))
        chips = {"/dev/gpiochip4": ("anderer", ["GPIO27"]), "/dev/gpiochip0": ("pinctrl-rp1", ["x"] * 3 + ["GPIO27"])}
        falsches_gpiod(self, chips=chips)
        self.assertEqual(A.find_lid_line(sys.modules["gpiod"], sorted(chips)), ("/dev/gpiochip0", 3, "pinctrl-rp1"))
        # Der Power-Button des V3 sucht weiter GPIO4
        self.assertEqual(A.find_button_line(gpiod), ("/dev/gpiochip0", 4, "pinctrl-rp1"))

    def test_nur_lesend_mit_pull_up_und_beiden_flanken(self):
        line = self.lauf(drehbuch=[("ruhe",)])
        pfad, consumer, config, anfrage = self.anfragen[0]
        self.assertEqual((pfad, consumer, list(config)), ("/dev/gpiochip0", "zenos-argon", [27]))
        self.assertEqual(config[27], {"direction": line.Direction.INPUT, "edge_detection": line.Edge.BOTH,
                                      "bias": line.Bias.PULL_UP})
        # Beim Beenden freigegeben, nie etwas geschrieben (die Attrappe kennt kein Schreiben)
        self.assertTrue(anfrage.freigegeben)
        self.assertNotIn("unerwarteter Fehler", self.logtext())
        self.assertEqual(len(self.anfragen), 1)

    def test_zu_und_offen(self):
        self.lauf(pegel=1, drehbuch=[("ruhe",), ("flanke", 0), ("ruhe",), ("flanke", 1), ("ruhe",)])
        self.assertEqual(self.gemeldet, [
            # Pegel beim Start: ohne Zeit (kein Wechsel, die Oberfläche sperrt deshalb nicht)
            {"vorhanden": True, "zu": False, "seit": None},
            {"vorhanden": True, "zu": True, "seit": "2026-10-05T22:40:00.000+02:00"},
            {"vorhanden": True, "zu": False, "seit": "2026-10-05T22:40:01.000+02:00"},
            # Ende des Laufs: kein Deckel mehr
            {"vorhanden": False},
        ])
        self.assertIn("Deckel an GPIO27 (/dev/gpiochip0, pinctrl-rp1, Zeile 27)", self.logtext())
        self.assertIn("Deckel beim Start offen", self.logtext())
        self.assertIn("Deckel zu", self.logtext())

    def test_zu_beim_start(self):
        self.lauf(pegel=0, drehbuch=[("ruhe",)])
        self.assertEqual(self.gemeldet[0], {"vorhanden": True, "zu": True, "seit": None})

    def test_prellen_zaehlt_erst_nach_100_ms_ruhe(self):
        self.lauf(pegel=1, drehbuch=[("ruhe",),
                                      # zuklappen mit Prellen: ein Wechsel
                                      ("flanke", 0), ("flanke", 1), ("flanke", 0), ("flanke", 0), ("ruhe",),
                                      # Störung, die beim alten Pegel endet: kein Wechsel
                                      ("flanke", 1), ("flanke", 0), ("ruhe",),
                                      ("ruhe",)])
        self.assertEqual([g.get("zu") for g in self.gemeldet], [False, True, None])

    def test_verpasste_flanke_faellt_nach_einer_sekunde_auf(self):
        self.lauf(pegel=1, drehbuch=[("ruhe",), ("still", 0), ("ruhe",)])
        self.assertEqual([g.get("zu") for g in self.gemeldet], [False, True, None])

    def test_leitung_fehlt(self):
        falsches_gpiod(self, chips={"/dev/gpiochip10": DECKEL_CHIPS["/dev/gpiochip10"]})
        A.gpio_devices = lambda: ["/dev/gpiochip10"]
        lid = A.Lid()
        log = stille()
        gemeldet = []
        A.LidWatcher(self.stop, lid, lambda: gemeldet.append(1), log).run()
        self.assertEqual((self.anfragen, gemeldet, lid.report()), ([], [], {"vorhanden": False}))
        self.assertIn("GPIO27 nicht gefunden: kein Deckel", log.stream.getvalue())

    def test_leitung_belegt(self):
        self.lauf(fehler=OSError(errno.EBUSY, "Device or resource busy"))
        self.assertEqual(len(self.anfragen), 1)
        self.assertIn("schon belegt (läuft Argons Software argononeupd?)", self.logtext())
        self.assertEqual(self.lid.report(), {"vorhanden": False})

    def test_andere_fehler_dreimal(self):
        self.lauf(fehler=OSError(errno.EIO, "I/O error"))
        self.assertEqual(len(self.anfragen), 3)
        self.assertIn("Deckel aufgegeben", self.logtext())

    def test_ohne_libgpiod(self):
        sys.modules["gpiod"] = None  # import gpiod scheitert
        log = stille()
        A.LidWatcher(self.stop, A.Lid(), lambda: None, log).run()
        self.assertIn("python3-libgpiod fehlt", log.stream.getvalue())

    def test_unerwarteter_fehler_beendet_nur_den_deckel(self):
        self.lauf(fehler=RuntimeError("kaputt"))
        self.assertIn("Deckel: unerwarteter Fehler", self.logtext())
        self.assertEqual(self.lid.report(), {"vorhanden": False})

    def test_testwurzel_ohne_echte_chips(self):
        A.gpio_devices = self.geraete
        with tempfile.TemporaryDirectory() as wurzel:
            os.makedirs(os.path.join(wurzel, "dev"))
            open(os.path.join(wurzel, "dev", "i2c-1"), "w").close()
            with mock.patch.dict(os.environ, {"ZENOS_ARGON_TESTWURZEL": wurzel}):
                self.assertEqual(A.gpio_devices(), [])
                open(os.path.join(wurzel, "dev", "gpiochip0"), "w").close()
                self.assertEqual(A.gpio_devices(), [os.path.join(wurzel, "dev", "gpiochip0")])


class FalscherStatusUp:
    def __init__(self):
        self.geschrieben = []
        self.entfernt = False

    def write(self, daten, now=None):
        self.geschrieben.append(json.loads(json.dumps(daten)))
        return True

    def remove(self):
        self.entfernt = True


class FalscherKernelLuefter:
    def read(self):
        return {"vorhanden": True, "stufe": 1, "stufen": 4, "upm": 2000}


class FalscherMonitor:
    pending = False
    sample = None
    percent = 50
    charging = types.SimpleNamespace(value=True)

    def tick(self):
        return {"vorhanden": True, "prozent": 50, "laedt": True, "zustand": "ok"}


class DeckelInDerStatusdatei(unittest.TestCase):
    def test_sofort_geschrieben_nach_dem_ersten_takt(self):
        lid = A.Lid(now=lambda: "2026-10-05T22:40:00.000+02:00")
        status = FalscherStatusUp()
        daemon = A.UpDaemon(FalscherMonitor(), FalscherKernelLuefter(), stille(), status, lambda: 41.0, lid=lid)
        # Vor dem ersten Takt schreibt der Deckel nichts (es fehlen Akku und Lüfter)
        lid.set(False, changed=False)
        daemon.lid_changed()
        self.assertEqual(status.geschrieben, [])
        daemon.tick()
        self.assertEqual(status.geschrieben[-1]["deckel"], {"vorhanden": True, "zu": False, "seit": None})
        lid.set(True, changed=True)
        daemon.lid_changed()
        self.assertEqual(len(status.geschrieben), 2)
        self.assertEqual(status.geschrieben[-1]["deckel"], {"vorhanden": True, "zu": True,
                                                            "seit": "2026-10-05T22:40:00.000+02:00"})
        # Akku, Lüfter und Temperatur bleiben die des letzten Takts
        self.assertEqual(status.geschrieben[-1]["akku"], status.geschrieben[0]["akku"])
        self.assertEqual(status.geschrieben[-1]["temperatur"], {"cpu": 41.0})

    def test_beenden_wartet_auf_den_deckel_und_entfernt_die_datei(self):
        status = FalscherStatusUp()
        daemon = A.UpDaemon(FalscherMonitor(), FalscherKernelLuefter(), stille(), status, lambda: 41.0, lid=A.Lid())
        daemon.stop = Warten()
        ende = threading.Event()

        class Faden:
            def is_alive(self):
                return True

            def join(self, timeout):
                ende.set()

        daemon.lid_watcher = Faden()
        daemon.run(15.0, rounds=1)
        self.assertTrue(ende.is_set())
        self.assertTrue(status.entfernt)
        # Danach schreibt der Deckel nichts mehr
        daemon.lid_changed()
        self.assertEqual(len(status.geschrieben), 1)


# --- Ausschalten bei leerem Akku --------------------------------------------------

class FalscherMesschip:
    """CW2217 im Test, aktiv mit Argons Profil: Ladestand (0x04) und Stromrichtung (0x0E) frei setzbar."""

    def __init__(self, soc=5, entlaedt=True):
        self.reg = dict.fromkeys(range(256), 0)
        self.reg[0x00], self.reg[0x08], self.reg[0x0B] = 0xA0, 0x00, 0x80
        for i, wert in enumerate(A.ARGON_UP_PROFILE):
            self.reg[0x10 + i] = wert
        self.reg[0x04] = soc
        self.reg[0x0E] = 0xF0 if entlaedt else 0x01
        self.fehler = False
        self.geschrieben = []

    def read_byte_data(self, adresse, register):
        if adresse != A.GAUGE_ADDRESS or self.fehler:
            raise OSError(121, "Remote I/O error")
        return self.reg[register]

    def write_byte_data(self, adresse, register, wert):
        self.geschrieben.append((register, wert))


class Warten(threading.Event):
    """Stop-Ereignis, das die Wartezeiten nur notiert."""

    def __init__(self):
        super().__init__()
        self.zeiten = []

    def wait(self, timeout=None):
        self.zeiten.append(timeout)
        return self.is_set()


WAND = datetime.datetime(2026, 10, 5, 22, 40, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=2)))


class AkkuLeer(unittest.TestCase):
    def setUp(self):
        self.uhr = Uhr()
        self.chip = FalscherMesschip()
        self.log = stille()
        self.monitor = A.BatteryMonitor(A.BatteryGauge(self.chip, sleep=lambda s: None), self.log, clock=self.uhr)
        self.aufrufe = []
        self.belegt = ""
        self.rc = 0
        self.meldungen = []
        self.kritisch = A.CriticalBattery(self.log, clock=self.uhr,
                                          wall=lambda: WAND + datetime.timedelta(seconds=self.uhr.t - 1000),
                                          busy=lambda: self.belegt, runner=self.runner,
                                          notify=lambda text: self.meldungen.append(text) or True)
        self.messen(5)  # erster Wert: 5 % im Akkubetrieb

    def runner(self, argv, **kwargs):
        self.aufrufe.append((argv, kwargs))
        return types.SimpleNamespace(returncode=self.rc, stderr="Fehler\n" if self.rc else "")

    def messen(self, soc=None, entlaedt=True, sekunden=15, fehler=False):
        if soc is not None:
            self.chip.reg[0x04] = soc
        self.chip.reg[0x0E] = 0xF0 if entlaedt else 0x01
        self.chip.fehler = fehler
        self.uhr.t += sekunden
        self.monitor.tick()
        self.kritisch.update(self.monitor)
        return self.kritisch.report()

    def um(self, sekunden_ab_start):
        return (WAND + datetime.timedelta(seconds=sekunden_ab_start)).isoformat(timespec="seconds")

    def logtext(self):
        return self.log.stream.getvalue()

    def bis_zur_vorwarnung(self):
        self.assertIsNone(self.messen(3))
        self.assertIsNone(self.messen(3))
        bericht = self.messen(3)
        self.assertEqual(bericht, self.um(self.uhr.t - 1000 + 60))
        return self.uhr.t

    def test_vier_prozent_nie(self):
        for _ in range(40):
            self.assertIsNone(self.messen(4))
        self.assertEqual(self.aufrufe, [])
        self.assertFalse(self.kritisch.active)

    def test_drei_messungen_dann_60_s_vorwarnung_dann_aus(self):
        start = self.bis_zur_vorwarnung()
        self.assertTrue(self.kritisch.active)
        # 5 % beim Start, dann dreimal 3 % im Abstand von 15 s: Vorwarnung um 22:41:00, aus um 22:42:00
        self.assertIn("zenOS schaltet um 22:42:00 kontrolliert aus, nur das Netzteil bricht ab", self.logtext())
        # Eine Messung mit 4 % während der Vorwarnung bricht nicht ab (nur das Netzteil)
        self.messen(4, sekunden=5)
        while self.uhr.t + 5 < start + 60:
            self.messen(3, sekunden=5)
        self.assertEqual(self.aufrufe, [])
        self.messen(3, sekunden=5)
        self.assertEqual(self.uhr.t - start, 60)
        self.assertEqual(len(self.aufrufe), 1)
        argv, kwargs = self.aufrufe[0]
        self.assertEqual(argv, ["systemctl", "poweroff"])
        self.assertIs(kwargs["stdin"], subprocess.DEVNULL)
        # Nur einmal
        for _ in range(5):
            self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)
        self.assertEqual(self.chip.geschrieben, [])

    def test_prellen_braucht_drei_hintereinander(self):
        for soc in (3, 3, 4, 3, 3):
            self.assertIsNone(self.messen(soc))
        self.assertIsNotNone(self.messen(3))

    def test_lesefehler_setzt_zurueck(self):
        self.assertIsNone(self.messen(3))
        self.assertIsNone(self.messen(3))
        self.assertIsNone(self.messen(fehler=True))
        self.assertIsNone(self.messen(3))
        self.assertIsNone(self.messen(3))
        self.assertIsNotNone(self.messen(3))

    def test_laden_nie(self):
        for _ in range(10):
            self.assertIsNone(self.messen(2, entlaedt=False))
        self.assertEqual(self.aufrufe, [])

    def test_entladen_erst_nach_der_entprellung(self):
        # Netzteil dran, dann ausgesteckt: «lädt nicht» gilt erst nach drei gleichen Messungen (BatteryMonitor)
        for _ in range(3):
            self.messen(3, entlaedt=False)
        self.assertIsNone(self.messen(3))
        self.assertIsNone(self.messen(3))
        self.assertIsNone(self.messen(3))  # jetzt sicher im Akkubetrieb: erste Messung zählt
        self.assertIsNone(self.messen(3))
        self.assertIsNotNone(self.messen(3))

    def test_netzteil_mitten_in_der_vorwarnung(self):
        self.bis_zur_vorwarnung()
        self.messen(3, sekunden=5)
        # Eine einzige Messung «lädt» bricht ab, auch vor der Entprellung
        self.assertIsNone(self.messen(3, entlaedt=False, sekunden=5))
        self.assertFalse(self.kritisch.active)
        self.assertIn("abgebrochen: Netzteil angeschlossen", self.logtext())
        for _ in range(30):
            self.messen(3, entlaedt=False, sekunden=5)
        self.assertEqual(self.aufrufe, [])

    def test_unsicherer_messwert_bricht_ab_und_beginnt_von_vorn(self):
        self.bis_zur_vorwarnung()
        self.assertIsNone(self.messen(fehler=True, sekunden=5))
        self.assertIn("abgebrochen: Messwert unsicher", self.logtext())
        start = self.bis_zur_vorwarnung()
        while self.uhr.t - start < 60:
            self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)

    def test_null_prozent_am_ende_des_akkus_zaehlt(self):
        # Der CW2217 springt von 4 % direkt auf 0 % (echtes Ende): Das zählt als leer, die Vorwarnung beginnt
        self.messen(4)
        self.assertIsNone(self.messen(0))
        self.assertIsNone(self.messen(0))
        start = self.uhr.t + 15
        self.assertIsNotNone(self.messen(0))
        self.assertEqual(self.monitor.percent, 0)
        # 0 % während der Vorwarnung bricht nicht ab (nur das Netzteil)
        while self.uhr.t - start < 60:
            self.assertTrue(self.kritisch.active)
            self.messen(0, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)
        self.assertNotIn("abgebrochen", self.logtext())

    def test_null_prozent_mitten_in_der_vorwarnung(self):
        start = self.bis_zur_vorwarnung()
        self.messen(0, sekunden=5)
        self.assertTrue(self.kritisch.active)
        while self.uhr.t - start < 60:
            self.messen(0, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)

    def test_null_prozent_ohne_gueltigen_wert_davor_zaehlt_nie(self):
        # Kurz nach dem Aktivieren meldet der Chip 0 %, bis er den ersten Wert hat: kein Messwert
        monitor = A.BatteryMonitor(A.BatteryGauge(self.chip, sleep=lambda s: None), self.log, clock=self.uhr)
        kritisch = A.CriticalBattery(self.log, clock=self.uhr, busy=lambda: "", runner=self.runner,
                                     notify=lambda text: True)
        self.chip.reg[0x04] = 0
        for _ in range(20):
            self.uhr.t += 15
            monitor.tick()
            kritisch.update(monitor)
            self.assertIsNone(monitor.sample)
            self.assertIsNone(monitor.percent)
        self.assertFalse(kritisch.active)
        # Nach einem hohen Wert ist 0 % unplausibel (ein Sprung von 50 auf 0): ebenso kein Messwert
        self.chip.reg[0x04] = 50
        self.uhr.t += 15
        monitor.tick()
        self.chip.reg[0x04] = 0
        for _ in range(5):
            self.uhr.t += 15
            monitor.tick()
            kritisch.update(monitor)
            self.assertIsNone(monitor.sample)
        self.assertEqual(monitor.percent, 50)
        self.assertFalse(kritisch.active)
        self.assertEqual(self.aufrufe, [])

    def test_akku_erholt_sich_bricht_ab(self):
        self.bis_zur_vorwarnung()
        # Eine einzelne höhere Messung bricht nicht ab (die nächste ist wieder 3 %)
        self.messen(9, sekunden=5)
        self.messen(3, sekunden=5)
        self.messen(9, sekunden=5)
        self.assertTrue(self.kritisch.active)
        # Zwei sichere Messungen hintereinander ab 6 %: Ende der Vorwarnung
        self.assertIsNone(self.messen(6, sekunden=5))
        self.assertFalse(self.kritisch.active)
        self.assertIn("abgebrochen: Akku wieder bei 6 %", self.logtext())
        for _ in range(20):
            self.messen(6, sekunden=5)
        self.assertEqual(self.aufrufe, [])
        # Unter 6 % (5 %, 4 %) gilt nicht als erholt
        start = self.bis_zur_vorwarnung()
        while self.uhr.t - start < 60:
            self.messen(5, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)

    def test_meldung_an_alle_terminals(self):
        self.bis_zur_vorwarnung()
        self.assertEqual(self.meldungen, ["zenOS: Akku fast leer (3 %). zenOS schaltet um 22:42 kontrolliert aus. "
                                          "Netzteil anschliessen bricht ab."])
        self.messen(3, entlaedt=False, sekunden=5)
        self.assertEqual(self.meldungen[-1], "zenOS: Ausschalten bei leerem Akku abgebrochen (Netzteil angeschlossen).")
        # Mit Wartezeit (dpkg): auch die späteste Uhrzeit
        start = self.bis_zur_vorwarnung()
        self.belegt = "dpkg läuft"
        while self.uhr.t - start < 60:
            self.messen(3, sekunden=5)
        self.assertTrue(self.meldungen[-1].startswith("zenOS: Akku leer, aber dpkg läuft. zenOS schaltet spätestens um "))

    def test_meldung_scheitert_haelt_nichts_auf(self):
        def kaputt(text):
            raise OSError("kein wall")

        self.kritisch.notify = kaputt
        start = self.bis_zur_vorwarnung()
        while self.uhr.t - start < 60:
            self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)
        self.assertIn("Meldung an die Terminals fehlgeschlagen", self.logtext())

    def test_wall_mit_argumentliste_und_stdin(self):
        aufrufe = []

        def runner(argv, **kwargs):
            aufrufe.append((argv, kwargs))
            return types.SimpleNamespace(returncode=0)

        self.assertTrue(A.wall_message("zenOS: Text; $(nicht ausführen)", runner=runner))
        self.assertEqual(len(aufrufe), 1)
        argv, kwargs = aufrufe[0]
        self.assertEqual(argv, ["wall"])
        self.assertEqual(kwargs["input"], "zenOS: Text; $(nicht ausführen)\n")
        self.assertNotIn("shell", kwargs)
        # In der Testwurzel nie
        with tempfile.TemporaryDirectory() as wurzel, mock.patch.dict(os.environ, {"ZENOS_ARGON_TESTWURZEL": wurzel}):
            self.assertIsNone(A.wall_message("x", runner=runner))
        self.assertEqual(len(aufrufe), 1)

    def test_dpkg_wartet_hoechstens_5_min(self):
        start = self.bis_zur_vorwarnung()
        self.belegt = "dpkg läuft"
        while self.uhr.t - start < 60:
            self.messen(3, sekunden=5)
        self.assertEqual(self.aufrufe, [])
        # Die Uhrzeit zeigt nun die späteste
        self.assertEqual(self.kritisch.report(), self.um(start - 1000 + 60 + 300))
        self.assertIn("dpkg läuft: zenOS wartet damit, spätestens bis 22:47:00", self.logtext())
        while self.uhr.t - start < 60 + 300:
            self.assertEqual(self.aufrufe, [])
            self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)
        self.assertIn("wartet nicht länger als 5 Min.", self.logtext())

    def test_installation_fertig_dann_sofort(self):
        start = self.bis_zur_vorwarnung()
        self.belegt = "install.sh läuft"
        while self.uhr.t - start < 120:
            self.messen(3, sekunden=5)
        self.assertEqual(self.aufrufe, [])
        self.belegt = ""
        self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 1)

    def test_fehlschlag_neuer_versuch_im_naechsten_takt(self):
        start = self.bis_zur_vorwarnung()
        self.rc = 1
        while self.uhr.t - start < 60:
            self.messen(3, sekunden=5)
        self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 2)
        self.assertEqual(self.logtext().count("systemctl poweroff ist fehlgeschlagen"), 1)
        self.rc = 0
        self.messen(3, sekunden=5)
        self.messen(3, sekunden=5)
        self.assertEqual(len(self.aufrufe), 3)

    def test_testwurzel_schaltet_nie_aus(self):
        with tempfile.TemporaryDirectory() as wurzel, mock.patch.dict(os.environ, {"ZENOS_ARGON_TESTWURZEL": wurzel}):
            start = self.bis_zur_vorwarnung()
            while self.uhr.t - start < 60:
                self.messen(3, sekunden=5)
        self.assertEqual(self.aufrufe, [])
        self.assertIn("Testwurzel: hier schaltete zenOS aus", self.logtext())

    def test_statusdatei_und_takt(self):
        status = FalscherStatusUp()
        daemon = A.UpDaemon(self.monitor, FalscherKernelLuefter(), stille(), status, lambda: 40.0,
                            critical=self.kritisch)
        daemon.stop = Warten()
        original = self.monitor.tick

        def tick():
            self.chip.reg[0x04] = 3
            self.uhr.t += 5
            return original()

        self.monitor.tick = tick
        daemon.run(15.0, rounds=5)
        akku = [d["akku"] for d in status.geschrieben]
        self.assertEqual([a["ausschaltenUm"] is not None for a in akku], [False, False, True, True, True])
        self.assertEqual(akku[2]["prozent"], 3)
        # Ohne Vorwarnung alle 15 s, während der Vorwarnung alle 5 s
        self.assertEqual(daemon.stop.zeiten, [15.0, 15.0, 5.0, 5.0])
        self.assertNotIn("deckel", status.geschrieben[0])

    def test_abgleich_mit_den_leitplanken(self):
        with open(os.path.join(WURZEL, "shell", "modi", "zustandslogik.js"), encoding="utf-8") as f:
            logik = f.read()
        self.assertEqual(A.CRITICAL_PERCENT, int(re.search(r"akkuAusschaltenProzent: (\d+)", logik).group(1)))
        self.assertEqual(A.CRITICAL_WARNING_SECONDS, int(re.search(r"vorwarnungSekunden: (\d+)", logik).group(1)))


class WaechterBeimAusschalten(unittest.TestCase):
    def test_installation(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "zenos-install.lock")
            self.assertFalse(A.install_running(pfad))
            open(pfad, "w").close()
            self.assertFalse(A.install_running(pfad))
            with open(pfad) as gehalten:
                fcntl.flock(gehalten, fcntl.LOCK_EX)
                self.assertTrue(A.install_running(pfad))
            self.assertFalse(A.install_running(pfad))
            # Fremder Verweis statt der Datei: nicht prüfbar, gilt als belegt (dann höchstens 5 Min. warten)
            os.unlink(pfad)
            os.symlink(os.path.join(ordner, "woanders"), pfad)
            self.assertTrue(A.install_running(pfad))

    def test_dpkg(self):
        with tempfile.TemporaryDirectory() as proc:
            for pid, name in (("1", "systemd"), ("77", "bash"), ("self", "x")):
                os.makedirs(os.path.join(proc, pid))
                with open(os.path.join(proc, pid, "comm"), "w") as f:
                    f.write(name + "\n")
            os.makedirs(os.path.join(proc, "88"))  # Prozess eben beendet: kein comm
            self.assertFalse(A.process_running("dpkg", proc))
            os.makedirs(os.path.join(proc, "4242"))
            with open(os.path.join(proc, "4242", "comm"), "w") as f:
                f.write("dpkg\n")
            self.assertTrue(A.process_running("dpkg", proc))
            self.assertFalse(A.process_running("dpk", proc))
            self.assertTrue(A.process_running("dpkg", os.path.join(proc, "fehlt")))


# --- Deckel in --pruefen und zen doctor -------------------------------------------

class DeckelPruefen(ModuleZurueck):
    def zeilen(self, status=None, **kwargs):
        falsches_gpiod(self, **kwargs)
        ausgabe = []
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "geraet.json")
            if status is not None:
                with open(pfad, "w", encoding="utf-8") as f:
                    json.dump(status, f)
            A._check_lid(lambda zeichen, text: ausgabe.append(f"{zeichen} {text}"), pfad)
        return ausgabe

    def test_frei_kurz_gelesen_und_freigegeben(self):
        for pegel, text in ((1, "Pegel 1 = offen"), (0, "Pegel 0 = zu")):
            with self.subTest(pegel=pegel):
                ausgabe = self.zeilen(pegel=pegel)
                self.assertEqual(len(ausgabe), 1)
                self.assertTrue(ausgabe[0].startswith("✓ Deckel an GPIO27 = /dev/gpiochip0 (pinctrl-rp1), Zeile 27: "
                                                      + text), ausgabe[0])
                _pfad, consumer, config, anfrage = self.anfragen[0]
                line = sys.modules["gpiod.line"]
                self.assertEqual((consumer, config[27]), ("zenos-argon-pruefen", {"direction": line.Direction.INPUT,
                                                                                    "bias": line.Bias.PULL_UP}))
                self.assertTrue(anfrage.freigegeben)

    def test_vom_dienst_belegt(self):
        ausgabe = self.zeilen(belegt="zenos-argon", status={"version": 1, "deckel": {"vorhanden": True, "zu": True,
                                                                                    "seit": None}})
        self.assertEqual(ausgabe, ["✓ Deckel an GPIO27 = /dev/gpiochip0 (pinctrl-rp1), Zeile 27, überwacht von "
                                   "zenos-argon: zu (Pegel 0)"])
        self.assertEqual(self.anfragen, [])

    def test_fremd_belegt_oder_fehlt(self):
        self.assertTrue(self.zeilen(belegt="argon")[0].startswith("✗ "))
        self.assertEqual(self.anfragen, [])
        A.gpio_devices = lambda: []
        self.assertEqual(self.zeilen(), ["· Kein Deckel: GPIO-Leitung GPIO27 nicht gefunden"])


DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "80-argon.sh")
DOCTOR_DECKEL = r"""
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$1"
_argon_deckel "$2"
"""


@unittest.skipUnless(shutil.which("jq") and shutil.which("bash"), "braucht jq und bash")
class DoctorDeckel(unittest.TestCase):
    def doctor(self, daten):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "geraet.json")
            with open(pfad, "w", encoding="utf-8") as f:
                json.dump(dict({"version": 1}, **daten), f)
            ergebnis = subprocess.run(["bash", "-c", DOCTOR_DECKEL, "test", DOCTOR, pfad], capture_output=True,
                                      text=True, timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        return ergebnis.stdout.splitlines()

    def test_deckel(self):
        self.assertEqual(self.doctor({"deckel": {"vorhanden": True, "zu": False, "seit": None}}),
                         ["ok: Deckel offen (GPIO27): Zuklappen sperrt und schaltet den Bildschirm aus"])
        self.assertEqual(self.doctor({"deckel": {"vorhanden": True, "zu": True, "seit": "2026-10-05T22:40:00.000+02:00"}})[0],
                         "ok: Deckel zu (GPIO27): Zuklappen sperrt und schaltet den Bildschirm aus")
        self.assertTrue(self.doctor({"deckel": {"vorhanden": False}})[0].startswith("hinweis: Kein Deckel erkannt"))
        self.assertTrue(self.doctor({})[0].startswith("hinweis: zenos-argon meldet keinen Deckel"))

    def test_ausschalten_bei_leerem_akku(self):
        zeilen = self.doctor({"deckel": {"vorhanden": False},
                              "akku": {"vorhanden": True, "prozent": 3, "laedt": False, "zustand": "ok",
                                       "ausschaltenUm": "2026-10-05T22:41:05+02:00"}})
        self.assertEqual(zeilen[-1], "warnung: Akku fast leer: zenOS schaltet um 22:41 aus (Netzteil anschliessen "
                                     "bricht ab)")
        zeilen = self.doctor({"akku": {"vorhanden": True, "prozent": 30, "ausschaltenUm": None}})
        self.assertEqual(len(zeilen), 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
