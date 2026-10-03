#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-argon (Kurve, Hysterese, Pulse, I2C-Protokoll, Status, Beenden) und den
Hook system/systemd/system-shutdown/zenos-argon (Abschaltsignal beim Ausschalten).

Läuft ohne Hardware und ohne Abhängigkeiten ausser python3 und bash: python3 test/einheiten/argon.test.py
"""

import enum
import errno
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
import types
import unittest

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
            self.assertEqual(daten["luefter"], {"vorhanden": True, "prozent": 30})
            self.assertEqual(daten["akku"], {"vorhanden": False})
            self.assertRegex(daten["zeit"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$")
            self.assertEqual(stat.S_IMODE(os.stat(pfad).st_mode), 0o644)
            self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(pfad)).st_mode) & 0o022, 0)
            status.write(A.argon_v3_report(None, None))
            with open(pfad, encoding="utf-8") as f:
                daten = json.load(f)
            self.assertEqual((daten["temperatur"], daten["luefter"]),
                             ({"cpu": None}, {"vorhanden": True, "prozent": None}))
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


if __name__ == "__main__":
    unittest.main(verbosity=1)
