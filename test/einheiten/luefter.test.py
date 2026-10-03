#!/usr/bin/env python3
"""Einheitentests für «Lüfter einstellen»: Lüfterwunsch (/var/lib/zenos/luefter) und Mindeststufe in
scripts/bin/zenos-argon (Stufe aus der Temperatur mit Hysterese wie step_wise, Leitplanken, Übernehmen und Zurückgeben
der Thermal-Zone, verwaister user_space, Sicherung --luefter-kernel, Argon ONE V3), dazu der Helfer
scripts/bin/zenos-luefter (nur Aufrufe, die nichts ändern), die polkit-Aktion und die Unit.

Ohne Hardware und ohne Root-Rechte: /sys ist eine Attrappe im Temp-Ordner (ZENOS_ARGON_TESTWURZEL bzw. Pfade direkt).
  python3 test/einheiten/luefter.test.py
"""

import importlib.machinery
import importlib.util
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET

# Kein __pycache__ neben scripts/bin/zenos-argon, auch ohne pruefen.sh
sys.dont_write_bytecode = True

WURZEL =os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-argon")
HELFER = os.path.join(WURZEL, "scripts", "bin", "zenos-luefter")
POLICY = os.path.join(WURZEL, "system", "polkit", "org.zenos.luefter.policy")
UNIT = os.path.join(WURZEL, "system", "systemd", "system", "zenos-argon.service")
_loader = importlib.machinery.SourceFileLoader("zenos_argon_luefter", PROGRAMM)
_spec = importlib.util.spec_from_loader("zenos_argon_luefter", _loader)
A = importlib.util.module_from_spec(_spec)
_loader.exec_module(A)

CM5 = "Raspberry Pi Compute Module 5 Lite Rev 1.0"
# Wie am Gerät gelesen: vier aktive Trip-Punkte mit 5 °C Hysterese, kritisch bei 110 °C
TRIPS = (("active", 50000, 5000), ("active", 60000, 5000), ("active", 67500, 5000), ("active", 75000, 5000),
         ("critical", 110000, 0))


def stille():
    return A.Log(journal=False, stream=io.StringIO())


class Uhr:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


def schreiben(pfad, inhalt):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(inhalt)


def lesen(pfad):
    with open(pfad, encoding="utf-8") as f:
        return f.read().strip()


def sysfs_anlegen(sysfs, policy="step_wise", stufe=0, temperatur=45000, trips=TRIPS,
                  verfuegbar="user_space step_wise bang_bang fair_share", binden=True):
    """/sys mit pwm-fan (hwmon3, cooling_device1) an thermal_zone0, wie am Compute Module 5."""
    hwmon = os.path.join(sysfs, "class", "hwmon", "hwmon3")
    for datei, wert in (("name", "pwmfan"), ("pwm1", "125"), ("fan1_input", "3120")):
        schreiben(os.path.join(hwmon, datei), wert + "\n")
    thermal = os.path.join(sysfs, "class", "thermal")
    schreiben(os.path.join(thermal, "cooling_device0", "type"), "thermal-cpufreq-0\n")
    kuehler = os.path.join(thermal, "cooling_device1")
    for datei, wert in (("type", "pwm-fan"), ("cur_state", str(stufe)), ("max_state", "4")):
        schreiben(os.path.join(kuehler, datei), wert + "\n")
    zone = os.path.join(thermal, "thermal_zone0")
    for datei, wert in (("type", "cpu-thermal"), ("temp", str(temperatur)), ("policy", policy),
                        ("available_policies", verfuegbar)):
        schreiben(os.path.join(zone, datei), wert + "\n")
    for index, (art, grad, hyst) in enumerate(trips):
        schreiben(os.path.join(zone, f"trip_point_{index}_type"), art + "\n")
        schreiben(os.path.join(zone, f"trip_point_{index}_temp"), f"{grad}\n")
        schreiben(os.path.join(zone, f"trip_point_{index}_hyst"), f"{hyst}\n")
    if binden:
        for index in range(4):
            os.symlink("../cooling_device1", os.path.join(zone, f"cdev{index}"))
            schreiben(os.path.join(zone, f"cdev{index}_trip_point"), f"{index}\n")
    return zone, kuehler


class Stufe(unittest.TestCase):
    """AutoStage rechnet nach, was step_wise wählen würde."""

    def test_steigen_und_fallen_mit_hysterese(self):
        auto = A.AutoStage(A.FALLBACK_TRIPS)
        folge = [(40, 0), (49.9, 0), (50, 1), (59.9, 1), (60, 2), (67.5, 3), (75, 4), (90, 4),
                 # Fallen: Stufe 4 hält bis unter 70 °C, Stufe 3 bis unter 62,5 °C
                 (70, 4), (69.9, 3), (62.5, 3), (62.4, 2), (55.1, 2), (54.9, 1), (45, 1), (44.9, 0)]
        for temperatur, erwartet in folge:
            self.assertEqual(auto.update(temperatur), erwartet, temperatur)

    def test_ausgangsstufe_fuer_die_hysterese(self):
        # Der Kernel hat Stufe 2: bei 57 °C bleibt sie (über 55 °C), bei 54 °C fällt sie auf 1
        self.assertEqual(A.AutoStage(A.FALLBACK_TRIPS, 2).update(57), 2)
        self.assertEqual(A.AutoStage(A.FALLBACK_TRIPS, 2).update(54), 1)
        self.assertEqual(A.AutoStage(A.FALLBACK_TRIPS, 0).update(57), 1)
        # Eine zu hohe Ausgangsstufe korrigiert die erste Messung
        self.assertEqual(A.AutoStage(A.FALLBACK_TRIPS, 4).update(30), 0)

    def test_leitplanken(self):
        ziel = A.kernel_fan_target
        self.assertEqual(ziel(40, 0, 2, 4), 2)        # Mindeststufe
        self.assertEqual(ziel(68, 3, 2, 4), 3)        # nie weniger als automatisch
        self.assertEqual(ziel(79.9, 0, 1, 4), 1)
        self.assertEqual(ziel(80, 0, 1, 4), 4)        # ab 80 °C voll
        self.assertEqual(ziel(None, 0, 1, 4), 4)      # ohne Temperatur voll
        self.assertEqual(ziel(40, 0, 4, 3), 3)        # höchstens max_state
        self.assertEqual(ziel(70, 6, 1, 4), 4)


class Wunsch(unittest.TestCase):
    def test_gueltig(self):
        faelle = {
            "modus=auto\n": ("auto", None),
            "# zenOS\nmodus=mindest\nstufe=2\nseit=2026-10-03T10:00:00+02:00\n": ("mindest", 2),
            "modus = mindest\nstufe = 4\n": ("mindest", 4),
            "modus=mindest\nstufe=1\nmodus=auto\n": ("auto", None),  # der letzte gilt
            "stufe=3\nmodus=mindest\n": ("mindest", 3),
        }
        for text, erwartet in faelle.items():
            modus, stufe, fehler = A.parse_fan_wish(text)
            self.assertEqual((modus, stufe), erwartet, text)
            self.assertIsNone(fehler, text)

    def test_ungueltig_heisst_auto(self):
        for text in ("", "# nur Kommentar\n", "modus=leise\n", "modus=mindest\n", "modus=mindest\nstufe=0\n",
                     "modus=mindest\nstufe=5\n", "modus=mindest\nstufe=2.5\n", "modus=mindest\nstufe=-1\n",
                     "modus=mindest\nstufe=zwei\n", "mindest 2\n", "modus=MINDEST\nstufe=2\n"):
            modus, stufe, fehler = A.parse_fan_wish(text)
            self.assertEqual((modus, stufe), ("auto", None), text)
            self.assertTrue(fehler, text)

    def test_datei(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "luefter")
            self.assertEqual(A.read_fan_wish(pfad), ("auto", None, None))
            with open(pfad, "wb") as f:
                f.write(b"modus=mindest\nstufe=\xff\n")
            self.assertEqual(A.read_fan_wish(pfad)[:2], ("auto", None))
            with open(pfad, "wb") as f:
                f.write(b"modus=mindest\nstufe=2\n" + b"#" * 5000)
            self.assertIn("grösser", A.read_fan_wish(pfad)[2])
            os.remove(pfad)
            os.mkdir(pfad)
            self.assertIn("nicht lesbar", A.read_fan_wish(pfad)[2])

    def test_aenderung_wirkt_ohne_neustart(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "luefter")
            log = stille()
            wunsch = A.FanWish(pfad, log)
            self.assertFalse(wunsch.refresh())  # fehlt: auto, wie vorher
            self.assertEqual((wunsch.mode, wunsch.minimum), ("auto", 0))
            schreiben(pfad, "modus=mindest\nstufe=3\n")
            self.assertTrue(wunsch.refresh())
            self.assertEqual((wunsch.mode, wunsch.stage, wunsch.minimum), ("mindest", 3, 3))
            self.assertFalse(wunsch.refresh())  # unverändert: nicht neu gelesen
            schreiben(pfad, "modus=leise\n")
            self.assertTrue(wunsch.refresh())
            self.assertEqual(wunsch.mode, "auto")
            schreiben(pfad, "modus=laut\n")
            wunsch.refresh()
            self.assertEqual(log.stream.getvalue().count("es gilt «automatisch»"), 1)  # Dauerfehler nur einmal
            schreiben(pfad, "modus=mindest\nstufe=1\n")
            self.assertTrue(wunsch.refresh())
            self.assertIn("wieder gültig", log.stream.getvalue())


class Zone(unittest.TestCase):
    def test_trip_punkte_aus_sysfs(self):
        with tempfile.TemporaryDirectory() as sysfs:
            zone, _ = sysfs_anlegen(sysfs)
            self.assertEqual(A.read_trips(zone), A.FALLBACK_TRIPS)
            self.assertEqual(A.describe_trips(A.read_trips(zone)), "50 / 60 / 67,5 / 75 °C, Hysterese 5 °C")
            self.assertIsNone(A.zone_problem(zone))

    def test_andere_trip_punkte_gelten(self):
        with tempfile.TemporaryDirectory() as sysfs:
            zone, _ = sysfs_anlegen(sysfs, trips=(("active", 45000, 3000), ("critical", 110000, 0),
                                                  ("active", 55000, 3000)))
            self.assertEqual(A.read_trips(zone), ((45.0, 3.0), (55.0, 3.0)))

    def test_unplausible_trip_punkte(self):
        for trips in ((("critical", 110000, 0),), (("active", 150000, 0),), (("active", 50000, 30000),),
                      (("active", 50000, 0), ("active", 50000, 0))):
            with tempfile.TemporaryDirectory() as sysfs:
                zone, _ = sysfs_anlegen(sysfs, trips=trips)
                self.assertIsNone(A.read_trips(zone), trips)

    def test_zone_ueber_cdev_gefunden(self):
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs)
            thermal = os.path.join(sysfs, "class", "thermal")
            schreiben(os.path.join(thermal, "thermal_zone1", "type"), "andere\n")
            self.assertEqual(A.find_fan_zones(thermal, kuehler), [zone])
            self.assertEqual(A.fan_zone(thermal, kuehler), zone)

    def test_rueckfall_auf_thermal_zone0(self):
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs, binden=False)
            thermal = os.path.join(sysfs, "class", "thermal")
            self.assertEqual(A.find_fan_zones(thermal, kuehler), [])
            self.assertEqual(A.fan_zone(thermal, kuehler), zone)

    def test_nicht_einstellbar(self):
        faelle = (
            (dict(verfuegbar="step_wise bang_bang"), "user_space"),
            (dict(trips=TRIPS + (("passive", 85000, 2000),)), "drosselt"),
        )
        for argumente, grund in faelle:
            with tempfile.TemporaryDirectory() as sysfs:
                zone, _ = sysfs_anlegen(sysfs, **argumente)
                self.assertIn(grund, A.zone_problem(zone))

    def test_zone_muss_zum_luefter_passen(self):
        # Nur eine Zone, die genau so am Lüfter hängt, wie AutoStage nachrechnet (je aktiver Trip-Punkt eine Stufe,
        # kein anderer Kühler): Unter user_space regelte der Kernel an ihr sonst auch anderes nicht mehr.
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs)
            self.assertIsNone(A.zone_problem(zone, kuehler))
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs, binden=False)
            self.assertIn("nicht mit dem Lüfter verbunden", A.zone_problem(zone, kuehler))
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs)
            os.symlink("../cooling_device0", os.path.join(zone, "cdev4"))
            schreiben(os.path.join(zone, "cdev4_trip_point"), "3\n")
            self.assertIn("anderer Kühler", A.zone_problem(zone, kuehler))
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs, trips=(("active", 50000, 5000), ("active", 60000, 5000),
                                                        ("critical", 110000, 0)))
            self.assertIn("passen nicht zusammen", A.zone_problem(zone, kuehler))
        with tempfile.TemporaryDirectory() as sysfs:
            zone, kuehler = sysfs_anlegen(sysfs)
            os.remove(os.path.join(zone, "cdev3"))
            self.assertIn("passen nicht zusammen", A.zone_problem(zone, kuehler))
        with tempfile.TemporaryDirectory() as sysfs:
            # Wie am Gerät: auch der kritische Trip-Punkt hängt am Lüfter (Stufe 4), das stört nicht
            zone, kuehler = sysfs_anlegen(sysfs)
            os.symlink("../cooling_device1", os.path.join(zone, "cdev4"))
            schreiben(os.path.join(zone, "cdev4_trip_point"), "4\n")
            self.assertIsNone(A.zone_problem(zone, kuehler))


class Steuerung(unittest.TestCase):
    """KernelFanControl gegen eine /sys-Attrappe."""

    def setUp(self):
        self._ordner = tempfile.TemporaryDirectory()
        self.ordner = self._ordner.name
        self.sysfs = os.path.join(self.ordner, "sys")
        self.zone, self.kuehler = sysfs_anlegen(self.sysfs)
        self.wunsch_pfad = os.path.join(self.ordner, "luefter")
        self.uhr = Uhr()
        self.log = stille()

    def tearDown(self):
        self._ordner.cleanup()

    def steuerung(self):
        luefter = A.KernelFan(self.sysfs, self.log, clock=self.uhr)
        wunsch = A.FanWish(self.wunsch_pfad, self.log)
        return A.KernelFanControl(luefter, wunsch, self.log, os.path.join(self.sysfs, "class", "thermal"),
                                  clock=self.uhr)

    def wunsch(self, inhalt):
        schreiben(self.wunsch_pfad, inhalt)

    def temperatur(self, grad):
        schreiben(os.path.join(self.zone, "temp"), f"{int(grad * 1000)}\n")

    def policy(self):
        return lesen(os.path.join(self.zone, "policy"))

    def stufe(self):
        return int(lesen(os.path.join(self.kuehler, "cur_state")))

    def takt(self, sekunden=2):
        self.uhr.t += sekunden
        return self.s.tick()

    def test_auto_schreibt_nichts(self):
        self.s = self.steuerung()
        self.s.start()
        vorher = os.stat(os.path.join(self.zone, "policy")).st_mtime_ns
        for _ in range(3):
            self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 0))
        self.assertEqual(os.stat(os.path.join(self.zone, "policy")).st_mtime_ns, vorher)
        self.assertEqual(self.s.report(), {"modus": "auto", "mindeststufe": None, "steuerbar": True})

    def test_mindeststufe_und_temperatur(self):
        self.s = self.steuerung()
        self.s.start()
        self.temperatur(40)
        self.wunsch("modus=mindest\nstufe=2\n")
        self.assertTrue(self.takt())  # neuer Wunsch: Statusdatei sofort
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 2))
        self.assertEqual(self.s.report(), {"modus": "mindest", "mindeststufe": 2, "steuerbar": True})
        self.assertFalse(self.takt())
        folge = [(55, 2), (61, 2), (68, 3), (64, 3), (62, 2), (76, 4), (72, 4), (69, 3), (50, 2), (30, 2)]
        for grad, erwartet in folge:
            self.temperatur(grad)
            self.takt()
            self.assertEqual(self.stufe(), erwartet, grad)
        self.assertIn("Lüfter: Mindeststufe 2, zenos-argon regelt (thermal_zone0: Regler user_space, Trip-Punkte "
                      "50 / 60 / 67,5 / 75 °C, Hysterese 5 °C)", self.log.stream.getvalue())

    def test_neue_stufe_gleich_in_die_statusdatei(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=1\n")
        self.temperatur(40)
        self.assertTrue(self.takt())
        self.temperatur(45)
        self.assertFalse(self.takt())  # Stufe bleibt 1
        self.temperatur(61)
        self.assertTrue(self.takt())  # Stufe 2: sofort schreiben, nicht erst nach 15 s
        self.assertFalse(self.takt())

    def test_ab_80_grad_voll(self):
        # Trip-Punkte, die erst sehr spät greifen: Die Leitplanke bei 80 °C hängt nicht von ihnen ab
        self._ordner.cleanup()
        self._ordner = tempfile.TemporaryDirectory()
        self.ordner = self._ordner.name
        self.sysfs = os.path.join(self.ordner, "sys")
        self.zone, self.kuehler = sysfs_anlegen(self.sysfs, trips=(("active", 85000, 5000), ("active", 90000, 5000),
                                                                   ("active", 95000, 5000), ("active", 99000, 5000),
                                                                   ("critical", 110000, 0)))
        self.wunsch_pfad = os.path.join(self.ordner, "luefter")
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=1\n")
        self.temperatur(79.9)
        self.takt()
        self.assertEqual(self.stufe(), 1)
        self.temperatur(80)
        self.takt()
        self.assertEqual(self.stufe(), 4)

    def test_temperatur_nicht_lesbar_heisst_voll(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=1\n")
        self.temperatur(40)
        self.takt()
        self.assertEqual(self.stufe(), 1)
        schreiben(os.path.join(self.zone, "temp"), "kaputt\n")
        self.takt()
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 4))
        self.assertEqual(self.log.stream.getvalue().count("sicherheitshalber auf voller Stufe"), 1)
        self.temperatur(40)
        self.takt()
        self.assertEqual(self.stufe(), 1)

    def test_zurueck_auf_auto_setzt_die_stufe_des_kernels(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=4\n")
        self.temperatur(52)
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 4))
        self.wunsch("modus=auto\n")
        self.assertTrue(self.takt())
        # step_wise hätte bei 52 °C Stufe 1; ohne diesen Schritt bliebe Stufe 4 bis zum nächsten Trip-Wechsel stehen
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 1))
        self.assertIn("wieder automatisch", self.log.stream.getvalue())
        self.takt()
        self.assertEqual(self.policy(), "step_wise")

    def test_beenden_gibt_dem_kernel_zurueck(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=3\n")
        self.temperatur(66)  # Kernel: Stufe 2
        self.takt()
        self.assertEqual(self.stufe(), 3)
        self.s.release()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 2))
        self.assertIn("der Dienst endet", self.log.stream.getvalue())

    def test_beenden_ohne_uebernahme_schreibt_nichts(self):
        self.s = self.steuerung()
        self.s.start()
        self.takt()
        self.s.release()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 0))

    def test_verwaister_user_space_beim_start(self):
        self._ordner.cleanup()
        self._ordner = tempfile.TemporaryDirectory()
        self.ordner = self._ordner.name
        self.sysfs = os.path.join(self.ordner, "sys")
        self.zone, self.kuehler = sysfs_anlegen(self.sysfs, policy="user_space", stufe=4, temperatur=57000)
        self.wunsch_pfad = os.path.join(self.ordner, "luefter")
        self.s = self.steuerung()
        self.s.start()
        # Ohne eigene Hysterese die höchste Stufe, die der Kernel bei 57 °C haben könnte (Trip 50 °C hält bis 45 °C,
        # Trip 60 °C bis 55 °C): 2
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 2))
        self.assertIn("stand noch auf dem Regler user_space", self.log.stream.getvalue())

    def test_verwaister_user_space_mit_mindeststufe(self):
        self._ordner.cleanup()
        self._ordner = tempfile.TemporaryDirectory()
        self.ordner = self._ordner.name
        self.sysfs = os.path.join(self.ordner, "sys")
        self.zone, self.kuehler = sysfs_anlegen(self.sysfs, policy="user_space", stufe=1, temperatur=40000)
        self.wunsch_pfad = os.path.join(self.ordner, "luefter")
        self.wunsch("modus=mindest\nstufe=3\n")
        self.s = self.steuerung()
        self.s.start()
        self.assertEqual(self.policy(), "step_wise")
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 3))

    def test_schreibfehler_gibt_dem_kernel_zurueck(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=2\n")
        self.temperatur(40)
        self.takt()
        self.assertEqual(self.policy(), "user_space")
        # cur_state lässt sich nicht mehr schreiben (ein Ordner scheitert auch für root)
        cur = os.path.join(self.kuehler, "cur_state")
        os.remove(cur)
        os.mkdir(cur)
        self.temperatur(70)
        self.takt()
        self.assertEqual(self.policy(), "step_wise")
        self.assertIn("lässt sich nicht einstellen", self.log.stream.getvalue())
        # Pause: kein neuer Versuch vor 60 s, der Kernel regelt
        os.rmdir(cur)
        schreiben(cur, "3\n")
        self.takt(10)
        self.assertEqual(self.policy(), "step_wise")
        self.takt(A.FAN_RETRY_SECONDS)
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 3))
        self.assertIn("lässt sich wieder einstellen", self.log.stream.getvalue())

    def test_regler_von_hand_umgestellt(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=2\n")
        self.temperatur(40)
        self.takt()
        schreiben(os.path.join(self.zone, "policy"), "step_wise\n")
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 2))

    def test_regler_von_hand_umgestellt_auch_beim_neu_lesen_der_trip_punkte(self):
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=2\n")
        self.temperatur(40)
        self.takt()
        schreiben(os.path.join(self.zone, "policy"), "step_wise\n")
        schreiben(os.path.join(self.kuehler, "cur_state"), "0\n")
        # Genau der Takt, in dem die Trip-Punkte neu gelesen werden (jede Minute)
        self.takt(A.FAN_RESCAN_SECONDS)
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 2))

    def test_zone_ohne_verweis_auf_den_luefter_wird_nicht_uebernommen(self):
        self._ordner.cleanup()
        self._ordner = tempfile.TemporaryDirectory()
        self.ordner = self._ordner.name
        self.sysfs = os.path.join(self.ordner, "sys")
        self.zone, self.kuehler = sysfs_anlegen(self.sysfs, binden=False)
        self.wunsch_pfad = os.path.join(self.ordner, "luefter")
        self.wunsch("modus=mindest\nstufe=2\n")
        self.s = self.steuerung()
        self.s.start()
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 0))
        self.assertFalse(self.s.report()["steuerbar"])
        self.assertIn("nicht mit dem Lüfter verbunden", self.log.stream.getvalue())

    def test_passive_zone_wird_nicht_uebernommen(self):
        self._ordner.cleanup()
        self._ordner = tempfile.TemporaryDirectory()
        self.ordner = self._ordner.name
        self.sysfs = os.path.join(self.ordner, "sys")
        self.zone, self.kuehler = sysfs_anlegen(self.sysfs, trips=TRIPS + (("passive", 85000, 2000),))
        self.wunsch_pfad = os.path.join(self.ordner, "luefter")
        self.wunsch("modus=mindest\nstufe=2\n")
        self.s = self.steuerung()
        self.s.start()
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 0))
        self.assertEqual(self.s.report(), {"modus": "mindest", "mindeststufe": 2, "steuerbar": False})
        self.assertIn("nicht einstellbar", self.log.stream.getvalue())

    def test_ohne_zone_nicht_steuerbar(self):
        os.remove(os.path.join(self.zone, "policy"))
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=2\n")
        self.s.start()
        self.takt()
        self.assertEqual(self.stufe(), 0)
        self.assertFalse(self.s.report()["steuerbar"])

    def test_trip_punkte_fehlen_rueckfall(self):
        for index in range(len(TRIPS)):
            os.remove(os.path.join(self.zone, f"trip_point_{index}_temp"))
        self.s = self.steuerung()
        self.wunsch("modus=mindest\nstufe=1\n")
        self.temperatur(68)
        self.takt()
        self.assertEqual(self.stufe(), 3)  # mit den bekannten Werten 50/60/67,5/75 °C
        self.assertIn("fehlen oder sind unplausibel", self.log.stream.getvalue())

    # --- Rückgabe gegen einen Nachbau von step_wise ---

    def kernel(self, *temperaturen):
        """Der Kernel misst nacheinander diese Temperaturen (Takt der Zone); gibt die Stufen danach zurück."""
        stufen = []
        for grad in temperaturen:
            self.temperatur(grad)
            neu = self.step_wise.messen(grad, self.policy(), self.stufe())
            schreiben(os.path.join(self.kuehler, "cur_state"), f"{neu}\n")
            stufen.append(neu)
        return stufen

    def test_rueckgabe_nie_unter_die_ziele_des_kernels(self):
        # Übernommen bei 70 °C (der Kernel hat Stufe 3), abgekühlt mit Mindeststufe 1, dann «auto». step_wise hat
        # noch seine Ziele von 70 °C; stünde der Lüfter jetzt auf 0 und stiege die Temperatur ohne Zwischentief, bliebe
        # er bis 75 °C leiser als automatisch.
        self.step_wise = StepWise(A.FALLBACK_TRIPS)
        self.s = self.steuerung()
        self.s.start()
        self.assertEqual(self.kernel(45, 52, 61, 68, 70), [0, 1, 2, 3, 3])
        self.wunsch("modus=mindest\nstufe=1\n")
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("user_space", 3))
        for grad in (66, 60, 52, 44, 40):
            self.kernel(grad)
            self.takt()
        self.assertEqual(self.stufe(), 1)
        self.wunsch("modus=auto\n")
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 3))
        self.assertIn("Lüfter Stufe 3 bei 40 °C (Stufe beim Übernehmen;", self.log.stream.getvalue())
        self.assertIn("(thermal_zone0: Regler step_wise; Wunsch «automatisch»)", self.log.stream.getvalue())
        # Steigt die Temperatur gleich danach stetig, nie weniger als automatisch
        auto = A.AutoStage(A.FALLBACK_TRIPS)
        for grad in (41, 45, 50, 55, 60, 64, 68, 72, 76):
            self.assertGreaterEqual(self.kernel(grad)[0], auto.update(grad), grad)

    def test_nach_der_rueckgabe_regelt_der_kernel_herunter(self):
        self.step_wise = StepWise(A.FALLBACK_TRIPS)
        self.s = self.steuerung()
        self.s.start()
        self.kernel(45, 52, 61, 68, 70)
        self.wunsch("modus=mindest\nstufe=1\n")
        self.takt()
        for grad in (66, 60, 52, 44, 40):
            self.kernel(grad)
            self.takt()
        self.wunsch("modus=auto\n")
        self.takt()
        # Die erste fallende Messung bringt den Kernel auf die Stufe, die zur Temperatur gehört
        self.assertEqual(self.kernel(40.2, 39.9), [3, 0])

    def test_rueckgabe_nach_kuehlem_uebernehmen(self):
        self.step_wise = StepWise(A.FALLBACK_TRIPS)
        self.s = self.steuerung()
        self.s.start()
        self.kernel(40, 41)
        self.wunsch("modus=mindest\nstufe=2\n")
        self.takt()
        self.kernel(52)
        self.takt()
        self.assertEqual(self.stufe(), 2)
        self.wunsch("modus=auto\n")
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 1))
        auto = A.AutoStage(A.FALLBACK_TRIPS, 1)
        for grad in (53, 58, 61, 66, 68, 74, 76):
            self.assertGreaterEqual(self.kernel(grad)[0], auto.update(grad), grad)

    def test_rueckgabe_ohne_temperatur_nicht_unter_die_ziele(self):
        self.step_wise = StepWise(A.FALLBACK_TRIPS)
        self.s = self.steuerung()
        self.s.start()
        self.kernel(52, 61, 68)
        self.wunsch("modus=mindest\nstufe=1\n")
        self.takt()
        self.kernel(40)
        self.takt()
        self.assertEqual(self.stufe(), 1)
        schreiben(os.path.join(self.zone, "temp"), "kaputt\n")
        self.wunsch("modus=auto\n")
        self.takt()
        self.assertEqual((self.policy(), self.stufe()), ("step_wise", 3))


class StepWise:
    """Nachbau des Kernel-Reglers step_wise (drivers/thermal/gov_step_wise.c und thermal_core.c, Linux 6.x) für einen
    Lüfter mit je einer Stufe pro aktivem Trip-Punkt (lower = upper = N wie im Gerätebaum des Compute Module 5):
    - Schwelle je Trip-Punkt: erreicht ab seiner Temperatur, dann gilt Temperatur − Hysterese, bis sie unterschritten
      ist (der Kern führt das auch unter user_space nach);
    - Ziel je Trip-Punkt nur unter step_wise und nur mit Trend: über der Schwelle und steigend oder fallend → N, unter
      der Schwelle und fallend → kein Ziel, sonst bleibt es; cur_state = höchstes Ziel, aber nur, wenn sich ein Ziel
      geändert hat."""

    def __init__(self, trips):
        self.trips = trips
        self.reached = [False] * len(trips)
        self.targets = [None] * len(trips)
        self.initialized = [False] * len(trips)
        self.last = None

    def messen(self, grad, policy, stufe):
        for i, (trip, hyst) in enumerate(self.trips):
            if not self.reached[i] and grad >= trip:
                self.reached[i] = True
            elif self.reached[i] and grad < trip - hyst:
                self.reached[i] = False
        trend = 0 if self.last is None or grad == self.last else (1 if grad > self.last else -1)
        self.last = grad
        if policy != "step_wise":
            return stufe
        geaendert = False
        for i, throttle in enumerate(self.reached):
            alt = self.targets[i]
            if not self.initialized[i]:
                neu = i + 1 if throttle else None
            elif throttle and trend != 0:
                neu = i + 1
            elif not throttle and trend < 0:
                neu = None
            else:
                neu = alt
            self.targets[i] = neu
            if self.initialized[i] and neu == alt:
                continue
            self.initialized[i] = True
            geaendert = True
        if not geaendert:
            return stufe
        return max((t for t in self.targets if t is not None), default=0)


class FalscherStatus:
    def __init__(self):
        self.geschrieben = []
        self.entfernt = False

    def write(self, daten, now=None):
        self.geschrieben.append(json.loads(json.dumps(daten)))
        return True

    def remove(self):
        self.entfernt = True


class FalscherMonitor:
    pending = False

    def tick(self):
        return {"vorhanden": True, "prozent": 80, "laedt": True, "zustand": "ok"}

    def snapshot(self):
        return self.tick()


class Takt(threading.Event):
    """Stop-Ereignis, das Wartezeiten notiert und die Uhr weiterdreht; ruft nach n Wartezeiten eine Aktion."""

    def __init__(self, uhr, aktionen):
        super().__init__()
        self.uhr = uhr
        self.zeiten = []
        self.aktionen = aktionen

    def wait(self, timeout=None):
        self.zeiten.append(round(timeout, 3))
        self.uhr.t += timeout
        aktion = self.aktionen.get(len(self.zeiten))
        if aktion:
            aktion()
        return self.is_set()


class Dienst(unittest.TestCase):
    def test_takt_von_2_sekunden_und_status_sofort(self):
        with tempfile.TemporaryDirectory() as ordner:
            sysfs = os.path.join(ordner, "sys")
            zone, kuehler = sysfs_anlegen(sysfs, temperatur=40000)
            pfad = os.path.join(ordner, "luefter")
            uhr = Uhr()
            log = stille()
            luefter = A.KernelFan(sysfs, log, clock=uhr)
            steuerung = A.KernelFanControl(luefter, A.FanWish(pfad, log), log,
                                           os.path.join(sysfs, "class", "thermal"), clock=uhr)
            status = FalscherStatus()
            dienst = A.UpDaemon(FalscherMonitor(), luefter, log, status, lambda: 40.0, control=steuerung)
            dienst.stop = Takt(uhr, {3: lambda: schreiben(pfad, "modus=mindest\nstufe=2\n")})
            dienst.run(15.0, rounds=2)
            # 15 s in acht Schritten (höchstens 2 s), nach dem dritten der neue Wunsch: sofort in die Statusdatei
            self.assertEqual(dienst.stop.zeiten, [1.875] * 8)
            self.assertEqual(len(status.geschrieben), 3)
            self.assertEqual(status.geschrieben[0]["luefter"],
                             {"vorhanden": True, "stufe": 0, "stufen": 4, "upm": 3120, "modus": "auto",
                              "mindeststufe": None, "steuerbar": True})
            self.assertEqual(status.geschrieben[1]["luefter"]["stufe"], 2)
            self.assertEqual(status.geschrieben[1]["luefter"]["modus"], "mindest")
            self.assertEqual(status.geschrieben[1]["akku"]["prozent"], 80)
            # Ende: der Kernel regelt wieder, Statusdatei weg
            self.assertEqual(lesen(os.path.join(zone, "policy")), "step_wise")
            self.assertTrue(status.entfernt)

    def test_programmfehler_stoppt_den_akku_nicht(self):
        with tempfile.TemporaryDirectory() as ordner:
            sysfs = os.path.join(ordner, "sys")
            zone, _ = sysfs_anlegen(sysfs)
            pfad = os.path.join(ordner, "luefter")
            schreiben(pfad, "modus=mindest\nstufe=2\n")
            uhr = Uhr()
            log = stille()
            luefter = A.KernelFan(sysfs, log, clock=uhr)
            steuerung = A.KernelFanControl(luefter, A.FanWish(pfad, log), log,
                                           os.path.join(sysfs, "class", "thermal"), clock=uhr)
            steuerung.tick()
            self.assertEqual(lesen(os.path.join(zone, "policy")), "user_space")
            steuerung.auto = None  # AttributeError im nächsten Takt
            uhr.t += 2
            steuerung.tick()
            self.assertEqual(lesen(os.path.join(zone, "policy")), "step_wise")

    def test_pause_beim_akkuprofil_regelt_weiter(self):
        # Akkuprofil laden dauert bis etwa 20 s; in jeder Pause regelt der Dienst den Lüfter weiter
        with tempfile.TemporaryDirectory() as ordner:
            sysfs = os.path.join(ordner, "sys")
            zone, kuehler = sysfs_anlegen(sysfs, temperatur=40000)
            pfad = os.path.join(ordner, "luefter")
            schreiben(pfad, "modus=mindest\nstufe=1\n")
            uhr = Uhr()
            log = stille()
            luefter = A.KernelFan(sysfs, log, clock=uhr)
            steuerung = A.KernelFanControl(luefter, A.FanWish(pfad, log), log,
                                           os.path.join(sysfs, "class", "thermal"), clock=uhr)
            status = FalscherStatus()
            dienst = A.UpDaemon(FalscherMonitor(), luefter, log, status, lambda: 40.0, control=steuerung)
            dienst.tick()
            self.assertEqual(lesen(os.path.join(kuehler, "cur_state")), "1")
            schreiben(os.path.join(zone, "temp"), "70000\n")
            uhr.t += 2
            dienst.pause(0)
            self.assertEqual(lesen(os.path.join(kuehler, "cur_state")), "3")
            self.assertEqual(status.geschrieben[-1]["luefter"]["stufe"], 3)

    def test_lebenszeichen_fuer_den_watchdog(self):
        with tempfile.TemporaryDirectory() as ordner:
            adresse = os.path.join(ordner, "notify")
            empfaenger = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            empfaenger.bind(adresse)
            empfaenger.settimeout(2)
            alt = os.environ.get("NOTIFY_SOCKET")
            os.environ["NOTIFY_SOCKET"] = adresse
            try:
                sysfs = os.path.join(ordner, "sys")
                sysfs_anlegen(sysfs, temperatur=40000)
                uhr = Uhr()
                log = stille()
                luefter = A.KernelFan(sysfs, log, clock=uhr)
                steuerung = A.KernelFanControl(luefter, A.FanWish(os.path.join(ordner, "luefter"), log), log,
                                               os.path.join(sysfs, "class", "thermal"), clock=uhr)
                dienst = A.UpDaemon(FalscherMonitor(), luefter, log, FalscherStatus(), lambda: 40.0,
                                    control=steuerung)
                dienst.stop = Takt(uhr, {})
                dienst.run(15.0, rounds=2)
                # ein Lebenszeichen je Takt und je Schritt des Wartens (höchstens 2 s auseinander)
                empfangen = []
                empfaenger.setblocking(False)
                while True:
                    try:
                        empfangen.append(empfaenger.recv(64))
                    except BlockingIOError:
                        break
                self.assertEqual(empfangen, [b"WATCHDOG=1"] * (2 + 8))
            finally:
                empfaenger.close()
                if alt is None:
                    os.environ.pop("NOTIFY_SOCKET", None)
                else:
                    os.environ["NOTIFY_SOCKET"] = alt
        # Ohne NOTIFY_SOCKET geschieht nichts
        A.watchdog_ping()


def testwurzel_anlegen(wurzel, policy="step_wise", wunsch=None):
    os.makedirs(os.path.join(wurzel, "proc", "device-tree"))
    with open(os.path.join(wurzel, "proc", "device-tree", "model"), "wb") as f:
        f.write(CM5.encode() + b"\0")
    os.makedirs(os.path.join(wurzel, "dev"))
    open(os.path.join(wurzel, "dev", "i2c-1"), "w").close()
    chip = {"0x00": 0xA0, "0x08": 0x00, "0x0b": 0x80, "0x04": 87, "0x0e": 0x00, "0xa7": 0x0C}
    chip.update({f"0x{0x10 + i:02x}": v for i, v in enumerate(A.ARGON_UP_PROFILE)})
    schreiben(os.path.join(wurzel, "i2c-1", "0x64.json"), json.dumps(chip))
    sysfs_anlegen(os.path.join(wurzel, "sys"), policy=policy, stufe=1, temperatur=52000)
    if wunsch is not None:
        schreiben(os.path.join(wurzel, "var", "lib", "zenos", "luefter"), wunsch)
    return os.path.join(wurzel, "sys", "class", "thermal")


class Programm(unittest.TestCase):
    def lauf(self, wurzel, *argumente):
        umgebung = dict(os.environ, ZENOS_ARGON_TESTWURZEL=wurzel, PYTHONDONTWRITEBYTECODE="1")
        umgebung.pop("JOURNAL_STREAM", None)
        umgebung.pop("NOTIFY_SOCKET", None)
        return subprocess.run([sys.executable, "-I", PROGRAMM, *argumente], env=umgebung, capture_output=True,
                              text=True, timeout=60, check=False)

    def test_dienst_mit_mindeststufe(self):
        with tempfile.TemporaryDirectory() as wurzel:
            thermal = testwurzel_anlegen(wurzel, wunsch="modus=mindest\nstufe=3\n")
            status = os.path.join(wurzel, "run", "zenos", "geraet.json")
            beobachtet = []

            def beobachten():
                # Während des Laufs: Statusdatei und Regler ansehen
                for _ in range(200):
                    try:
                        with open(status, encoding="utf-8") as f:
                            beobachtet.append((json.load(f)["luefter"], lesen(os.path.join(thermal, "thermal_zone0",
                                                                                            "policy"))))
                        return
                    except (OSError, ValueError):
                        threading.Event().wait(0.02)

            faden = threading.Thread(target=beobachten)
            faden.start()
            ergebnis = self.lauf(wurzel, "--durchlaeufe", "3", "--intervall", "0.3", "--status-datei", status)
            faden.join()
            self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
            self.assertIn("Lüfterwunsch: Mindeststufe 3", ergebnis.stderr)
            self.assertIn("Lüfter: Mindeststufe 3, zenos-argon regelt", ergebnis.stderr)
            self.assertIn("wieder automatisch, der Kernel regelt", ergebnis.stderr)
            luefter, policy = beobachtet[0]
            self.assertEqual((luefter["modus"], luefter["mindeststufe"], luefter["steuerbar"], luefter["stufe"]),
                             ("mindest", 3, True, 3))
            self.assertEqual(policy, "user_space")
            # nach dem Ende: Kernel regelt, Stufe wie step_wise bei 52 °C
            self.assertEqual(lesen(os.path.join(thermal, "thermal_zone0", "policy")), "step_wise")
            self.assertEqual(lesen(os.path.join(thermal, "cooling_device1", "cur_state")), "1")
            # Der Akku-Messchip wurde nicht beschrieben
            self.assertFalse(os.path.exists(os.path.join(wurzel, "i2c-1", "protokoll")))

    def test_sicherung_luefter_kernel(self):
        with tempfile.TemporaryDirectory() as wurzel:
            thermal = testwurzel_anlegen(wurzel, policy="user_space")
            ergebnis = self.lauf(wurzel, "--luefter-kernel")
            self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
            self.assertEqual(lesen(os.path.join(thermal, "thermal_zone0", "policy")), "step_wise")
            self.assertIn("wieder step_wise", ergebnis.stderr)
            # Schon step_wise: nichts geschrieben, nichts gemeldet; die Stufe bleibt, wie sie ist
            vorher = os.stat(os.path.join(thermal, "thermal_zone0", "policy")).st_mtime_ns
            ergebnis = self.lauf(wurzel, "--luefter-kernel")
            self.assertEqual((ergebnis.returncode, ergebnis.stderr), (0, ""))
            self.assertEqual(os.stat(os.path.join(thermal, "thermal_zone0", "policy")).st_mtime_ns, vorher)
            self.assertEqual(lesen(os.path.join(thermal, "cooling_device1", "cur_state")), "1")

    def test_sicherung_ohne_luefter(self):
        with tempfile.TemporaryDirectory() as wurzel:
            ergebnis = self.lauf(wurzel, "--luefter-kernel")
            self.assertEqual((ergebnis.returncode, ergebnis.stderr), (0, ""))

    def test_pruefen_zeigt_wunsch_und_regler(self):
        with tempfile.TemporaryDirectory() as wurzel:
            testwurzel_anlegen(wurzel, wunsch="modus=mindest\nstufe=2\n")
            ergebnis = self.lauf(wurzel, "--pruefen")
            self.assertIn("Lüfterwunsch: Mindeststufe 2", ergebnis.stdout)
            self.assertIn("Trip-Punkte von thermal_zone0: 50 / 60 / 67,5 / 75 °C, Hysterese 5 °C", ergebnis.stdout)
            self.assertIn("Regler step_wise; die Mindeststufe übernimmt der Dienst", ergebnis.stdout)
            self.assertFalse(os.path.exists(os.path.join(wurzel, "i2c-1", "protokoll")))

    def test_aufruf_schliesst_sich_aus(self):
        ergebnis = subprocess.run([sys.executable, "-I", PROGRAMM, "--pruefen", "--luefter-kernel"],
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 2)


class ArgonV3(unittest.TestCase):
    def test_mindeststufe_hebt_die_kurve_an(self):
        regler = A.FanController(A.Config(), minimum=A.FAN_STAGE_PERCENT[2])
        uhr = Uhr()
        self.assertEqual(regler.update(40, uhr()), 50)
        self.assertEqual(regler.update(61, uhr()), 55)
        self.assertEqual(regler.update(66, uhr()), 100)
        uhr.t += 100
        self.assertIsNone(regler.update(40, uhr()))  # langsamer erst nach der Verzögerung
        uhr.t += 100
        self.assertEqual(regler.update(40, uhr()), 50)  # nie unter die Mindeststufe
        uhr.t += 100
        self.assertIsNone(regler.update(20, uhr()))
        self.assertEqual(regler.speed, 50)

    def test_ab_80_grad_voll_auch_mit_mindeststufe(self):
        regler = A.FanController(A.Config(((50.0, 0),), 3, 30), minimum=A.FAN_STAGE_PERCENT[1])
        self.assertEqual(regler.update(79, 0), 30)
        self.assertEqual(regler.update(80, 5), 100)

    def test_stufen_in_prozent(self):
        self.assertEqual(A.FAN_STAGE_PERCENT, (0, 30, 50, 70, 100))

    def test_dienst_liest_den_wunsch(self):
        with tempfile.TemporaryDirectory() as ordner:
            pfad = os.path.join(ordner, "luefter")
            werte = []

            class Luefter:
                def set_speed(self, wert):
                    werte.append(wert)

            status = FalscherStatus()
            log = stille()
            temperaturen = iter([45, 45, 45, 45])
            dienst = A.Daemon(Luefter(), log, status, "/gibt/es/nicht.json", lambda: next(temperaturen),
                              clock=Uhr(), stopping=lambda: False, wish=A.FanWish(pfad, log))
            dienst.tick()
            self.assertEqual(werte, [0])
            self.assertEqual(status.geschrieben[-1]["luefter"],
                             {"vorhanden": True, "prozent": 0, "modus": "auto", "mindeststufe": None,
                              "steuerbar": True})
            schreiben(pfad, "modus=mindest\nstufe=3\n")
            dienst.tick()
            self.assertEqual(werte[-1], 70)
            self.assertEqual(status.geschrieben[-1]["luefter"]["modus"], "mindest")
            self.assertIn("Lüfter 70 % bei 45 °C (Mindeststufe 3)", log.stream.getvalue())


class Helfer(unittest.TestCase):
    def lauf(self, *argumente):
        return subprocess.run([HELFER, *argumente], capture_output=True, text=True, timeout=30, check=False,
                              env={"PATH": "/usr/bin:/bin"})

    def test_ausfuehrbar(self):
        self.assertTrue(os.access(HELFER, os.X_OK))

    def test_falsche_aufrufe(self):
        for argumente in ((), ("0",), ("5",), ("aus",), ("Auto",), (" 1",), ("1", "2"), ("--hilfe",), ("1;id",),
                          ("",), ("mindest",), ("02",)):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("zenos-luefter:", e.stderr)
                self.assertEqual(e.stdout, "")

    @unittest.skipIf(os.geteuid() == 0, "als root würde der Helfer den Wunsch wirklich schreiben")
    def test_setzen_nur_als_root(self):
        for wahl in ("auto", "1", "2", "3", "4"):
            with self.subTest(wahl=wahl):
                e = self.lauf(wahl)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("nur als root", e.stderr)

    def test_status_ohne_rechte(self):
        e = self.lauf("status")
        self.assertEqual(e.returncode, 0, e.stderr)
        self.assertRegex(e.stdout, r"^Lüfter: (automatisch|Mindeststufe [1-4])")


class Policy(unittest.TestCase):
    """polkit: eine Aktion ohne Passwort, nur in der aktiven Sitzung am Gerät, nur für den Helfer."""

    def test_aktion(self):
        baum = ET.parse(POLICY)
        aktionen = baum.getroot().findall("action")
        self.assertEqual([a.get("id") for a in aktionen], ["org.zenos.luefter.setzen"])
        a = aktionen[0]
        notizen = {n.get("key"): n.text for n in a.findall("annotate")}
        self.assertEqual(notizen, {"org.freedesktop.policykit.exec.path": "/opt/zenos/scripts/bin/zenos-luefter"})
        vorgaben = a.find("defaults")
        self.assertEqual((vorgaben.find("allow_any").text, vorgaben.find("allow_inactive").text,
                          vorgaben.find("allow_active").text), ("no", "no", "yes"))
        self.assertTrue(a.find("message").text.strip())


class Unit(unittest.TestCase):
    def test_sicherung_und_rechte(self):
        zeilen = [z.strip() for z in lesen(UNIT).splitlines()]
        self.assertIn("ExecStopPost=/usr/bin/python3 -I /opt/zenos/scripts/bin/zenos-argon --luefter-kernel", zeilen)
        self.assertIn("ReadWritePaths=-/sys/devices/virtual/thermal", zeilen)
        self.assertIn("ProtectKernelTunables=yes", zeilen)
        # Hängt der Dienst, beendet systemd ihn; ExecStopPost gibt den Lüfter dann dem Kernel zurück
        self.assertIn("WatchdogSec=30", zeilen)
        self.assertIn("NotifyAccess=main", zeilen)


if __name__ == "__main__":
    unittest.main(verbosity=1)
