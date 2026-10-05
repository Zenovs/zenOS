#!/usr/bin/env python3
"""Einheitentests für den Argon ONE UP in scripts/bin/zenos-argon: Akku-Messchip CW2217 (Profil prüfen und laden
wie Argons argononeupd.py, Grenzen und Pausen beim Schreiben, Plausibilität, Entprellung, Lesefehler), Lüfter vom
Kernel (Suche nach Namen in /sys), Statusdatei und ein ganzer Dienstlauf mit ZENOS_ARGON_TESTWURZEL.

Läuft ohne Hardware und ohne Abhängigkeiten ausser python3: python3 test/einheiten/akku.test.py
"""

import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-argon")
_loader = importlib.machinery.SourceFileLoader("zenos_argon_akku", PROGRAMM)
_spec = importlib.util.spec_from_loader("zenos_argon_akku", _loader)
A = importlib.util.module_from_spec(_spec)
_loader.exec_module(A)

PROFIL = A.ARGON_UP_PROFILE
CM5 = "Raspberry Pi Compute Module 5 Lite Rev 1.0"


def stille():
    return A.Log(journal=False, stream=io.StringIO())


class Uhr:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class FalscherMesschip:
    """CW2217 im Test: Register wie im Datenblatt, dazu 0xA7 (bereit, sobald aktiv). Jedes Lesen, Schreiben und
    jede Pause steht in «protokoll», damit die genaue Reihenfolge geprüft werden kann."""

    def __init__(self, aktiv=False, flag=False, profil=None, soc=87, strom_hoch=0x01, bereit=True):
        self.reg = dict.fromkeys(range(256), 0)
        self.reg[0x00] = 0xA0
        self.reg[0x08] = 0x00 if aktiv else 0xF0
        self.reg[0x0B] = 0x80 if flag else 0x14
        for i, wert in enumerate(profil if profil is not None else bytes(80)):
            self.reg[0x10 + i] = wert
        self.reg[0x04] = soc
        self.reg[0x0E] = strom_hoch
        self.bereit = bereit
        self.protokoll = []
        self.fehler = False

    def _pruefen(self, adresse):
        if adresse != A.GAUGE_ADDRESS or self.fehler:
            raise OSError(121, "Remote I/O error")

    def read_byte_data(self, adresse, register):
        self._pruefen(adresse)
        if register == A.REG_ICSTATE:
            return 0x0C if self.bereit and self.reg[0x08] == 0 else 0x00
        return self.reg[register]

    def write_byte_data(self, adresse, register, wert):
        self._pruefen(adresse)
        self.protokoll.append(("w", register, wert))
        self.reg[register] = wert

    def pause(self, sekunden):
        self.protokoll.append(("pause", sekunden))

    def geschrieben(self):
        return [(r, w) for art, r, w in (e for e in self.protokoll if e[0] == "w")]


def messchip(**kwargs):
    chip = FalscherMesschip(**kwargs)
    return chip, A.BatteryGauge(chip, sleep=chip.pause)


ARGON_FOLGE = (
    [("w", 0x08, 0x30), ("pause", 0.5), ("w", 0x08, 0xF0), ("pause", 0.5)]
    + [("w", 0x10 + i, v) for i, v in enumerate(PROFIL)]
    + [("w", 0x0B, 0x80), ("pause", 0.5), ("w", 0x0A, 0x00), ("pause", 0.5),
       ("w", 0x08, 0x30), ("pause", 0.5), ("w", 0x08, 0x00), ("pause", 0.5)]
)


class Profil(unittest.TestCase):
    def test_profil_wie_bei_argon(self):
        self.assertEqual(len(PROFIL), 80)
        self.assertEqual((PROFIL[0], PROFIL[8], PROFIL[66], PROFIL[79]), (0x32, 0xA8, 0x64, 0xFA))
        self.assertEqual(A.REG_PROFILE + len(PROFIL) - 1, 0x5F)

    def test_pruefen_nur_lesend(self):
        faelle = (
            (dict(aktiv=False, flag=True, profil=PROFIL), "schlaeft"),
            (dict(aktiv=True, flag=False, profil=PROFIL), "ohne-profil"),
            (dict(aktiv=True, flag=True, profil=bytes(80)), "anderes-profil"),
            (dict(aktiv=True, flag=True, profil=PROFIL), "ok"),
        )
        for argumente, erwartet in faelle:
            chip, gauge = messchip(**argumente)
            self.assertEqual(gauge.check(), erwartet, argumente)
            self.assertEqual(chip.geschrieben(), [], argumente)

    def test_laden_genau_wie_argon(self):
        chip, gauge = messchip(aktiv=False)
        bereit, zustand = gauge.load_profile()
        self.assertEqual((bereit, zustand), (True, "ok"))
        ohne_lesen = [e for e in chip.protokoll if e[0] != "r"]
        self.assertEqual(ohne_lesen, ARGON_FOLGE)
        self.assertEqual(bytes(chip.reg[0x10 + i] for i in range(80)), PROFIL)
        self.assertEqual((chip.reg[0x08], chip.reg[0x0B], chip.reg[0x0A]), (0x00, 0x80, 0x00))

    def test_aktivieren_ohne_bereit_dreimal(self):
        chip, gauge = messchip(aktiv=False, bereit=False)
        self.assertFalse(gauge.restart())
        self.assertEqual(chip.geschrieben(), [(0x08, 0x30), (0x08, 0x00)] * 3)
        self.assertEqual([e[1] for e in chip.protokoll if e[0] == "pause"].count(1), 15)

    def test_aktivieren_bricht_beim_beenden_ab(self):
        chip, gauge = messchip(aktiv=False, bereit=False)
        gauge.stop.set()
        self.assertFalse(gauge.restart())
        self.assertEqual(chip.geschrieben(), [(0x08, 0x30), (0x08, 0x00)])

    def test_stromrichtung(self):
        for hoch, entlaedt in ((0x00, False), (0x01, False), (0x7F, False), (0x80, True), (0xFF, True)):
            chip, gauge = messchip(aktiv=True, strom_hoch=hoch)
            self.assertEqual(gauge.read_discharging(), entlaedt, hex(hoch))


class Entprellen(unittest.TestCase):
    def test_erster_wert_sofort_dann_drei_gleiche(self):
        d = A.Debounce(3)
        self.assertFalse(d.update(True))
        self.assertTrue(d.value)
        self.assertFalse(d.update(False))
        self.assertTrue(d.pending)
        self.assertFalse(d.update(False))
        self.assertTrue(d.update(False))
        self.assertFalse(d.value)
        self.assertFalse(d.pending)

    def test_ausreisser_zaehlt_nicht(self):
        d = A.Debounce(3)
        d.update(True)
        for wert in (False, False, True, False, False, True):
            d.update(wert)
        self.assertTrue(d.value)
        self.assertFalse(d.pending)


class Waechter(unittest.TestCase):
    def waechter(self, nur_lesen=False, freigabe=None, **kwargs):
        self.uhr = Uhr()
        self.chip, gauge = messchip(**kwargs)
        self.log = stille()
        return A.BatteryMonitor(gauge, self.log, clock=self.uhr, read_only=nur_lesen, released=freigabe)

    def schritt(self, w, sekunden=15):
        self.uhr.t += sekunden
        return w.tick()

    def logtext(self):
        return self.log.stream.getvalue()

    def test_alles_stimmt_nichts_geschrieben(self):
        w = self.waechter(aktiv=True, flag=True, profil=PROFIL, soc=87, strom_hoch=0x01)
        self.assertEqual(self.schritt(w), {"vorhanden": True, "prozent": 87, "laedt": True, "zustand": "ok"})
        self.schritt(w)
        self.assertEqual(self.chip.geschrieben(), [])
        self.assertIn("nichts geschrieben", self.logtext())

    def test_schlafender_chip_wird_einmal_geladen(self):
        w = self.waechter(aktiv=False, soc=54, strom_hoch=0x90)
        self.assertEqual(self.schritt(w), {"vorhanden": True, "prozent": 54, "laedt": False, "zustand": "ok"})
        anzahl = len(self.chip.geschrieben())
        self.assertEqual(anzahl, 2 + 80 + 2 + 2)
        for _ in range(10):
            self.schritt(w)
        self.assertEqual(len(self.chip.geschrieben()), anzahl)
        self.assertIn("schläft: lade Argons Akkuprofil", self.logtext())
        self.assertIn("Akkuprofil geladen, der Messchip misst", self.logtext())

    def test_anderes_profil_wird_ersetzt(self):
        w = self.waechter(aktiv=True, flag=True, profil=bytes(range(80)))
        self.schritt(w)
        self.assertEqual(bytes(self.chip.reg[0x10 + i] for i in range(80)), PROFIL)

    def test_fehlschlag_mit_wachsender_pause_und_grenze(self):
        w = self.waechter(aktiv=False, bereit=False)
        # Der Chip übernimmt das Profil nicht (z. B. Schreibschutz): nach dem Laden wieder leer
        original = self.chip.write_byte_data

        def vergessen(adresse, register, wert):
            original(adresse, register, wert)
            if register == A.REG_CONTROL and wert == A.CONTROL_ACTIVE:
                self.chip.reg[0x0B] = 0x14

        self.chip.write_byte_data = vergessen
        versuche = []
        for _ in range(4 * 60 * 2):  # zwei Stunden in 15-s-Schritten
            vorher = len(self.chip.geschrieben())
            snapshot = self.schritt(w)
            if len(self.chip.geschrieben()) > vorher:
                versuche.append(self.uhr.t - 1000.0)
        self.assertEqual(snapshot["zustand"], "fehler")
        self.assertIsNone(snapshot["prozent"])
        # 15 s, dann frühestens 30 s, 60 s später; danach Grenze 3 pro Stunde
        self.assertEqual(versuche[:3], [15.0, 45.0, 105.0])
        for i in range(len(versuche)):
            in_einer_stunde = [t for t in versuche if versuche[i] <= t < versuche[i] + 3600]
            self.assertLessEqual(len(in_einer_stunde), 3)
        self.assertLessEqual(len(versuche), 6)
        self.assertEqual(self.logtext().count("schon 3-mal geschrieben"), 1)

    def test_nur_lesen_wenn_argon_software_aktiv(self):
        w = self.waechter(nur_lesen=True, aktiv=False)
        for _ in range(5):
            snapshot = self.schritt(w)
        self.assertEqual(self.chip.geschrieben(), [])
        self.assertEqual(snapshot["zustand"], "fehler")
        self.assertEqual(self.logtext().count("schreibt nichts in den Chip"), 1)

    def test_ohne_freigabe_nur_lesen_bis_sie_kommt(self):
        freigegeben = [False]
        w = self.waechter(freigabe=lambda: freigegeben[0], aktiv=False, soc=61, strom_hoch=0x90)
        for _ in range(5):
            snapshot = self.schritt(w)
        self.assertEqual(self.chip.geschrieben(), [])
        self.assertEqual(snapshot, {"vorhanden": True, "prozent": None, "laedt": None, "zustand": "freigabe"})
        self.assertEqual(self.logtext().count("erst nach der Freigabe (zen akku freigeben)"), 1)
        # Freigabe kommt (zen akku freigeben): im nächsten Takt geladen, ohne Neustart des Dienstes
        freigegeben[0] = True
        snapshot = self.schritt(w)
        self.assertEqual(len(self.chip.geschrieben()), 86)
        self.assertEqual(snapshot["zustand"], "ok")
        self.assertEqual(snapshot["prozent"], 61)
        self.assertIn("Freigabe für das Akkuprofil ist da", self.logtext())

    def test_ohne_freigabe_aktiver_chip_wird_gelesen(self):
        # Hat der Chip Argons Profil schon (z. B. von Argons Software), braucht es keine Freigabe
        w = self.waechter(freigabe=lambda: False, aktiv=True, flag=True, profil=PROFIL, soc=73)
        self.assertEqual(self.schritt(w)["prozent"], 73)
        self.assertEqual(self.chip.geschrieben(), [])

    def test_lesefehler_kurz_ueberbrueckt(self):
        w = self.waechter(aktiv=True, flag=True, profil=PROFIL, soc=70)
        self.schritt(w)
        self.chip.fehler = True
        self.assertEqual(self.schritt(w)["prozent"], 70)
        self.assertEqual(self.schritt(w)["zustand"], "ok")
        snapshot = self.schritt(w)
        self.assertEqual((snapshot["zustand"], snapshot["prozent"], snapshot["laedt"]), ("fehler", None, None))
        self.schritt(w)
        self.assertEqual(self.logtext().count("antwortet nicht"), 1)
        self.chip.fehler = False
        self.assertEqual(self.schritt(w)["prozent"], 70)
        self.assertIn("antwortet wieder", self.logtext())
        self.assertEqual(self.chip.geschrieben(), [])

    def test_zuruecksetzen_im_betrieb_laedt_neu(self):
        w = self.waechter(aktiv=True, flag=True, profil=PROFIL, soc=40)
        self.schritt(w)
        self.chip.reg[0x08] = 0xF0  # z. B. nach einem Spannungseinbruch
        self.chip.reg[0x0B] = 0x14
        self.assertEqual(self.schritt(w)["prozent"], 40)
        self.assertIn("zurückgesetzt?", self.logtext())
        self.assertEqual(len(self.chip.geschrieben()), 86)

    def test_plausibilitaet(self):
        w = self.waechter(aktiv=True, flag=True, profil=PROFIL, soc=0)
        self.assertEqual(self.schritt(w)["zustand"], "unbekannt")  # gleich nach dem Aktivieren
        for _ in range(9):
            self.schritt(w)
        self.assertEqual(self.logtext().count("seit 2 Minuten 0 %"), 1)
        self.chip.reg[0x04] = 102
        self.assertEqual(self.schritt(w)["prozent"], 100)
        self.chip.reg[0x04] = 255
        self.assertEqual(self.schritt(w)["prozent"], 100)
        self.assertIn("Unplausibler Ladestand 255", self.logtext())

    def test_sprung_braucht_zweite_messung(self):
        w = self.waechter(aktiv=True, flag=True, profil=PROFIL, soc=80)
        self.schritt(w)
        self.chip.reg[0x04] = 30
        self.assertEqual(self.schritt(w)["prozent"], 80)
        self.assertTrue(w.pending)
        self.chip.reg[0x04] = 31
        self.assertEqual(self.schritt(w, 5)["prozent"], 31)
        self.assertFalse(w.pending)
        # einzelner Ausreisser: kommt nie durch
        self.chip.reg[0x04] = 90
        self.assertEqual(self.schritt(w)["prozent"], 31)
        self.chip.reg[0x04] = 30
        self.assertEqual(self.schritt(w, 5)["prozent"], 30)

    def test_laden_entprellt(self):
        w = self.waechter(aktiv=True, flag=True, profil=PROFIL, soc=60, strom_hoch=0xF0)
        self.assertFalse(self.schritt(w)["laedt"])
        self.chip.reg[0x0E] = 0x02
        self.assertFalse(self.schritt(w)["laedt"])
        self.assertTrue(w.pending)
        self.assertFalse(self.schritt(w, 5)["laedt"])
        self.assertTrue(self.schritt(w, 5)["laedt"])
        self.assertIn("Netzteil angeschlossen, Akku 60 %", self.logtext())
        self.chip.reg[0x0E] = 0xFF
        self.schritt(w)
        self.chip.reg[0x0E] = 0x00  # Wackler: zählt neu
        self.schritt(w, 5)
        self.chip.reg[0x0E] = 0xFF
        self.schritt(w, 5)
        self.assertTrue(self.schritt(w, 5)["laedt"])
        self.assertFalse(self.schritt(w, 5)["laedt"])
        self.assertIn("Akkubetrieb, Akku 60 %", self.logtext())


def sysfs_anlegen(wurzel, luefter=True, drehzahl=True, stufe=2):
    hwmon = os.path.join(wurzel, "class", "hwmon")
    thermal = os.path.join(wurzel, "class", "thermal")
    for ordner, name in ((os.path.join(hwmon, "hwmon0"), "cpu_thermal"), (os.path.join(hwmon, "hwmon10"), "rp1_adc")):
        os.makedirs(ordner)
        with open(os.path.join(ordner, "name"), "w", encoding="utf-8") as f:
            f.write(name + "\n")
    os.makedirs(os.path.join(thermal, "thermal_zone0"))
    with open(os.path.join(thermal, "thermal_zone0", "temp"), "w", encoding="utf-8") as f:
        f.write("41234\n")
    if not luefter:
        return
    ordner = os.path.join(hwmon, "hwmon3")
    os.makedirs(ordner)
    werte = {"name": "pwmfan", "pwm1": "125"}
    if drehzahl:
        werte["fan1_input"] = "3120"
    for datei, wert in werte.items():
        with open(os.path.join(ordner, datei), "w", encoding="utf-8") as f:
            f.write(wert + "\n")
    ordner = os.path.join(thermal, "cooling_device1")
    os.makedirs(ordner)
    for datei, wert in (("type", "pwm-fan"), ("cur_state", str(stufe)), ("max_state", "4")):
        with open(os.path.join(ordner, datei), "w", encoding="utf-8") as f:
            f.write(wert + "\n")
    ordner = os.path.join(thermal, "cooling_device0")
    os.makedirs(ordner)
    with open(os.path.join(ordner, "type"), "w", encoding="utf-8") as f:
        f.write("thermal-cpufreq-0\n")


class Kernelluefter(unittest.TestCase):
    def test_nach_namen_gefunden(self):
        with tempfile.TemporaryDirectory() as wurzel:
            sysfs_anlegen(wurzel, stufe=2)
            log = stille()
            luefter = A.KernelFan(wurzel, log, clock=Uhr())
            self.assertEqual(luefter.read(), {"vorhanden": True, "stufe": 2, "stufen": 4, "upm": 3120})
            self.assertTrue(luefter.hwmon.endswith("hwmon3"))
            self.assertTrue(luefter.cooling.endswith("cooling_device1"))
            luefter.read()
            self.assertEqual(log.stream.getvalue().count("Kernel-Treiber pwm-fan"), 1)

    def test_ohne_drehzahlgeber(self):
        with tempfile.TemporaryDirectory() as wurzel:
            sysfs_anlegen(wurzel, drehzahl=False, stufe=0)
            self.assertEqual(A.KernelFan(wurzel, stille(), clock=Uhr()).read(),
                             {"vorhanden": True, "stufe": 0, "stufen": 4, "upm": None})

    def test_ohne_luefter_und_spaeter_neu_gesucht(self):
        with tempfile.TemporaryDirectory() as wurzel:
            sysfs_anlegen(wurzel, luefter=False)
            uhr = Uhr()
            luefter = A.KernelFan(wurzel, stille(), clock=uhr)
            self.assertEqual(luefter.read()["vorhanden"], False)
            # Treiber kommt später (Modul geladen): erst nach der Wartezeit neu gesucht
            ordner = os.path.join(wurzel, "class", "thermal", "cooling_device7")
            os.makedirs(ordner)
            for datei, wert in (("type", "pwm-fan"), ("cur_state", "1"), ("max_state", "4")):
                with open(os.path.join(ordner, datei), "w", encoding="utf-8") as f:
                    f.write(wert)
            uhr.t += 10
            self.assertEqual(luefter.read()["vorhanden"], False)
            uhr.t += A.FAN_RESCAN_SECONDS
            self.assertEqual(luefter.read(), {"vorhanden": True, "stufe": 1, "stufen": 4, "upm": None})

    def test_unplausible_werte(self):
        with tempfile.TemporaryDirectory() as wurzel:
            sysfs_anlegen(wurzel)
            with open(os.path.join(wurzel, "class", "thermal", "cooling_device1", "cur_state"), "w") as f:
                f.write("9\n")
            with open(os.path.join(wurzel, "class", "hwmon", "hwmon3", "fan1_input"), "w") as f:
                f.write("-5\n")
            self.assertEqual(A.KernelFan(wurzel, stille(), clock=Uhr()).read(),
                             {"vorhanden": True, "stufe": None, "stufen": None, "upm": None})


class FalscherStatus:
    def __init__(self):
        self.geschrieben = []
        self.entfernt = False

    def write(self, daten, now=None):
        self.geschrieben.append(daten)
        return True

    def remove(self):
        self.entfernt = True


class Warten(threading.Event):
    """Stop-Ereignis, das die Wartezeiten nur notiert."""

    def __init__(self):
        super().__init__()
        self.zeiten = []

    def wait(self, timeout=None):
        self.zeiten.append(timeout)
        return self.is_set()


class Dienst(unittest.TestCase):
    def test_takt_und_statusdatei(self):
        with tempfile.TemporaryDirectory() as wurzel:
            sysfs_anlegen(wurzel, stufe=0)
            chip, gauge = messchip(aktiv=True, flag=True, profil=PROFIL, soc=87, strom_hoch=0x00)
            uhr = Uhr()
            monitor = A.BatteryMonitor(gauge, stille(), clock=uhr)
            status = FalscherStatus()
            daemon = A.UpDaemon(monitor, A.KernelFan(wurzel, stille(), clock=uhr), stille(), status,
                                lambda: 41.26)
            daemon.stop = Warten()
            folge = iter([0x00, 0xF0, 0xF0, 0xF0, 0xF0])
            original = monitor.tick

            def tick():
                chip.reg[0x0E] = next(folge)
                uhr.t += 15
                return original()

            monitor.tick = tick
            daemon.run(15.0, rounds=5)
            self.assertEqual(status.geschrieben[0], {
                "geraet": "argon-one-up",
                "akku": {"vorhanden": True, "prozent": 87, "laedt": True, "zustand": "ok"},
                "luefter": {"vorhanden": True, "stufe": 0, "stufen": 4, "upm": 3120},
                "temperatur": {"cpu": 41.3},
            })
            # nach dem ersten Entladen-Wert öfter messen, bis drei gleiche da sind
            self.assertEqual(daemon.stop.zeiten, [15.0, 5.0, 5.0, 15.0])
            self.assertEqual([d["akku"]["laedt"] for d in status.geschrieben], [True, True, True, False, False])
            self.assertTrue(status.entfernt)
            self.assertEqual(chip.geschrieben(), [])


def testwurzel_anlegen(wurzel, chip=None, modell=CM5, argon_dienst=False, freigabe=False):
    os.makedirs(os.path.join(wurzel, "proc", "device-tree"))
    with open(os.path.join(wurzel, "proc", "device-tree", "model"), "wb") as f:
        f.write(modell.encode() + b"\0")
    os.makedirs(os.path.join(wurzel, "dev"))
    open(os.path.join(wurzel, "dev", "i2c-1"), "w").close()
    os.makedirs(os.path.join(wurzel, "i2c-1"))
    if chip is not None:
        with open(os.path.join(wurzel, "i2c-1", "0x64.json"), "w", encoding="utf-8") as f:
            json.dump(chip, f)
    sysfs_anlegen(os.path.join(wurzel, "sys"), stufe=2)
    if freigabe:
        os.makedirs(os.path.join(wurzel, "etc", "xdg", "zenos"))
        open(os.path.join(wurzel, "etc", "xdg", "zenos", "argon-akkuprofil"), "w").close()
    if argon_dienst:
        ordner = os.path.join(wurzel, "etc", "systemd", "system", "multi-user.target.wants")
        os.makedirs(ordner)
        os.symlink("/lib/systemd/system/argononeupd.service", os.path.join(ordner, "argononeupd.service"))


# Messchip wie auf Zenos Gerät gelesen: Chip-ID 0xA0, schläft (0xF0), kein Profil (0x0B = 0x14)
SCHLAFENDER_CHIP = {"0x00": 0xA0, "0x08": 0xF0, "0x0b": 0x14, "0x04": 87, "0x0e": 0x00, "0xa7": 0x0C}


class Testwurzel(unittest.TestCase):
    def lauf(self, wurzel, *argumente):
        umgebung = dict(os.environ, ZENOS_ARGON_TESTWURZEL=wurzel, PYTHONDONTWRITEBYTECODE="1")
        umgebung.pop("JOURNAL_STREAM", None)
        return subprocess.run([sys.executable, "-I", PROGRAMM, *argumente], env=umgebung, capture_output=True,
                              text=True, timeout=60, check=False)

    def protokoll(self, wurzel):
        try:
            with open(os.path.join(wurzel, "i2c-1", "protokoll"), encoding="utf-8") as f:
                return f.read().split("\n")[:-1]
        except FileNotFoundError:
            return []

    def test_pruefen_schreibt_nie(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, SCHLAFENDER_CHIP)
            ergebnis = self.lauf(wurzel, "--pruefen")
            self.assertEqual(ergebnis.returncode, 0, ergebnis.stdout + ergebnis.stderr)
            self.assertIn("Akku-Messchip CW2217 an 0x64 (Chip-ID 0xa0", ergebnis.stdout)
            self.assertIn("Messchip schläft (Register 0x08 = 0xf0); Argons Akkuprofil kommt erst nach «zen akku "
                          "freigeben»", ergebnis.stdout)
            self.assertIn("Akkuprofil schreiben: nicht freigegeben", ergebnis.stdout)
            self.assertIn("Stufe 2 von 4 · 3120 U/min", ergebnis.stdout)
            self.assertIn("CPU 41,2 °C", ergebnis.stdout)
            self.assertEqual(self.protokoll(wurzel), [])

    def test_dienst_ohne_freigabe_schreibt_nie(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, SCHLAFENDER_CHIP)
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "3", "--intervall", "0.05")
            self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
            self.assertIn("erst nach der Freigabe (zen akku freigeben)", ergebnis.stderr)
            self.assertEqual(self.protokoll(wurzel), [])

    def test_dienst_laedt_profil_und_schreibt_status(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, SCHLAFENDER_CHIP, freigabe=True)
            status = os.path.join(wurzel, "run", "zenos", "geraet.json")
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "2", "--intervall", "0.05", "--status-datei", status)
            self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
            erwartet = (["0x64 0x08 0x30", "0x64 0x08 0xf0"]
                        + [f"0x64 0x{0x10 + i:02x} 0x{v:02x}" for i, v in enumerate(PROFIL)]
                        + ["0x64 0x0b 0x80", "0x64 0x0a 0x00", "0x64 0x08 0x30", "0x64 0x08 0x00"])
            self.assertEqual(self.protokoll(wurzel), erwartet)
            self.assertIn("Argon ONE UP erkannt (Raspberry Pi Compute Module 5 Lite Rev 1.0)", ergebnis.stderr)
            self.assertIn("Akku 87 %, lädt", ergebnis.stderr)
            self.assertFalse(os.path.exists(status))  # beim Beenden entfernt
            # zweiter Start: Chip aktiv mit Argons Profil, nichts mehr geschrieben
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "1", "--status-datei", status)
            self.assertIn("nichts geschrieben", ergebnis.stderr)
            self.assertEqual(len(self.protokoll(wurzel)), len(erwartet))

    def test_statusdatei_im_lauf(self):
        with tempfile.TemporaryDirectory() as wurzel:
            chip = dict(SCHLAFENDER_CHIP, **{"0x08": 0x00, "0x0b": 0x80, "0x0e": 0x9C, "0x04": 9})
            chip.update({f"0x{0x10 + i:02x}": v for i, v in enumerate(PROFIL)})
            testwurzel_anlegen(wurzel, chip)
            status = FalscherStatus()
            with mock.patch.dict(os.environ, {"ZENOS_ARGON_TESTWURZEL": wurzel}), \
                    mock.patch.object(A, "StatusFile", lambda pfad, log: status):
                optionen = A.parse_args(["--durchlaeufe", "1"])
                bus = A.open_bus(stille())
                self.assertIsInstance(bus, A.FileBus)
                self.assertEqual(A.run_up_service(optionen, stille(), CM5, bus, Warten()), 0)
            daten = status.geschrieben[0]
            # 9 % im Akkubetrieb: kein Ausschalten (erst bei 3 %, test/einheiten/argon.test.py)
            self.assertEqual(daten["akku"], {"vorhanden": True, "prozent": 9, "laedt": False, "zustand": "ok",
                                             "ausschaltenUm": None})
            # In der Testwurzel gibt es keine GPIO-Chips: kein Deckel (ohne die echten Leitungen anzufassen)
            self.assertEqual(daten["deckel"], {"vorhanden": False})
            # Ohne Regler in der Zone (Attrappe ohne policy) nicht einstellbar, der Kernel regelt allein
            self.assertEqual(daten["luefter"], {"vorhanden": True, "stufe": 2, "stufen": 4, "upm": 3120, "modus": "auto",
                                                "mindeststufe": None, "steuerbar": False})
            self.assertEqual(daten["temperatur"], {"cpu": 41.2})
            self.assertEqual(self.protokoll(wurzel), [])

    def test_ohne_messchip_nichts_zu_tun(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, None)
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "1")
            self.assertEqual(ergebnis.returncode, 0)
            self.assertIn("Kein Argon ONE UP", ergebnis.stderr)
            ergebnis = self.lauf(wurzel, "--pruefen")
            self.assertEqual(ergebnis.returncode, 1)
            self.assertIn("Keine Antwort an 0x64", ergebnis.stdout)

    def test_fremder_chip_an_0x64(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, {"0x00": 0x12})
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "1")
            self.assertIn("Chip-ID 0x12", ergebnis.stderr)
            self.assertEqual(self.protokoll(wurzel), [])

    def test_anderes_geraet(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, SCHLAFENDER_CHIP, modell="Raspberry Pi 4 Model B Rev 1.5")
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "1")
            self.assertEqual(ergebnis.returncode, 0)
            self.assertIn("Weder Raspberry Pi 5 noch Compute Module 5", ergebnis.stderr)
            self.assertEqual(self.protokoll(wurzel), [])

    def test_argon_software_aktiv_nur_lesen(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, SCHLAFENDER_CHIP, argon_dienst=True)
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "2", "--intervall", "0.05")
            self.assertIn("liest den Akku nur", ergebnis.stderr)
            self.assertEqual(self.protokoll(wurzel), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
