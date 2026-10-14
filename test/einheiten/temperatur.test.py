#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-temperatur: welcher Fühler die Temperatur der CPU für die Leiste liefert.

Jeder Test baut einen kleinen Baum unter ORDNER/sys nach (--wurzel), wie auf dem Pi 5, einem Intel- und einem AMD-PC.

  python3 test/einheiten/temperatur.test.py
"""

import os
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-temperatur")


class Temperatur(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.w = self.tmp.name

    def datei(self, pfad, inhalt):
        voll = os.path.join(self.w, pfad.lstrip("/"))
        os.makedirs(os.path.dirname(voll), exist_ok=True)
        with open(voll, "w", encoding="utf-8") as f:
            f.write(inhalt + "\n")

    def zone(self, n, typ, temp="45000"):
        self.datei(f"/sys/class/thermal/thermal_zone{n}/type", typ)
        if temp is not None:
            self.datei(f"/sys/class/thermal/thermal_zone{n}/temp", temp)

    def hwmon(self, n, name, temp="47000"):
        self.datei(f"/sys/class/hwmon/hwmon{n}/name", name)
        if temp is not None:
            self.datei(f"/sys/class/hwmon/hwmon{n}/temp1_input", temp)

    def lauf(self, *argumente):
        return subprocess.run([PROGRAMM, *(argumente or ("--wurzel", self.w))], capture_output=True, text=True,
                              timeout=30, check=False)

    def pfad(self):
        r = self.lauf()
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip()

    def test_pi(self):
        self.zone(0, "cpu-thermal")
        self.assertEqual(self.pfad(), "/sys/class/thermal/thermal_zone0/temp")

    def test_intel_paket_statt_mainboard(self):
        # Wie auf einem Intel-PC: thermal_zone0 ist die ACPI-Zone des Mainboards
        self.zone(0, "acpitz")
        self.zone(1, "x86_pkg_temp")
        self.zone(2, "iwlwifi_1")
        self.hwmon(0, "acpitz")
        self.hwmon(3, "coretemp")
        self.assertEqual(self.pfad(), "/sys/class/thermal/thermal_zone1/temp")

    def test_intel_nur_coretemp(self):
        self.zone(0, "acpitz")
        self.hwmon(0, "acpitz")
        self.hwmon(2, "nvme")
        self.hwmon(3, "coretemp")
        self.assertEqual(self.pfad(), "/sys/class/hwmon/hwmon3/temp1_input")

    def test_amd(self):
        self.zone(0, "acpitz")
        self.hwmon(1, "nvme")
        self.hwmon(2, "k10temp")
        self.assertEqual(self.pfad(), "/sys/class/hwmon/hwmon2/temp1_input")

    def test_fuehler_ohne_wert_zaehlt_nicht(self):
        self.zone(0, "acpitz")
        self.zone(1, "x86_pkg_temp", temp=None)
        self.hwmon(3, "coretemp", temp="")
        self.assertEqual(self.pfad(), "/sys/class/thermal/thermal_zone0/temp")

    def test_rueckfall_thermal_zone0(self):
        self.zone(0, "soc-thermal")
        self.assertEqual(self.pfad(), "/sys/class/thermal/thermal_zone0/temp")

    def test_ohne_fuehler(self):
        os.makedirs(os.path.join(self.w, "sys", "class"))
        r = self.lauf()
        self.assertEqual((r.returncode, r.stdout), (1, ""))

    def test_falscher_aufruf(self):
        for argumente in (("--wurzel",), ("--anders", self.w), ("--wurzel", self.w, "mehr")):
            self.assertEqual(self.lauf(*argumente).returncode, 2, argumente)


if __name__ == "__main__":
    unittest.main()
