#!/usr/bin/env python3
"""Einheitentests für Bluetooth: das Modul scripts/module/36-bluetooth.sh (Dienst nach der ersten Installation
starten, sonst nichts anfassen), die Prüfung scripts/doctor.d/41-bluetooth.sh (nur Anzahlen, nie Namen oder
Adressen) und die Paketliste scripts/pakete/bluetooth.txt. Die Logik des Menüs testet bluetooth.test.mjs.

Ohne Bluetooth-Hardware: /sys/class/bluetooth und /sys/class/rfkill liegen in einem Testordner, systemctl,
bluetoothctl und dpkg-query sind Attrappen in einem eigenen PATH.

  python3 test/einheiten/bluetooth.test.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODUL = os.path.join(WURZEL, "scripts", "module", "36-bluetooth.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "41-bluetooth.sh")
PAKETE = os.path.join(WURZEL, "scripts", "pakete", "bluetooth.txt")
LINUX = sys.platform.startswith("linux")

# Attrappe: schreibt ihre Argumente als JSON-Zeile. Verhalten aus Dateien im Testordner:
#   systemctl: aktiv (is-active → 0), aktiviert.wert (is-enabled), seit.wert (show … ActiveEnterTimestampMonotonic),
#              start.fehler (start → 1), zustand.wert (is-active ohne --quiet)
#   bluetoothctl: show.aus, paired.aus, connected.aus
#   dpkg-query: bluez.status (Standard «install ok installed»), bluez.fehlt
ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, sys
WER = %r
ORDNER = os.environ["BT_TEST"]
argv = sys.argv[1:]
def datei(name):
    try:
        with open(os.path.join(ORDNER, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps([WER] + argv) + "\n")
if WER == "systemctl":
    if argv[:2] == ["--quiet", "is-active"]:
        sys.exit(0 if datei("aktiv") is not None else 3)
    if argv[:1] == ["is-active"]:
        zustand = (datei("zustand.wert") or ("active" if datei("aktiv") is not None else "inactive")).strip()
        print(zustand)
        sys.exit(0 if zustand == "active" else 3)
    if argv[:1] == ["is-enabled"]:
        wert = (datei("aktiviert.wert") or "enabled").strip()
        print(wert)
        sys.exit(0 if wert == "enabled" else 1)
    if argv[:1] == ["show"]:
        print((datei("seit.wert") or "0").strip())
        sys.exit(0)
    if argv[:1] == ["start"]:
        sys.exit(1 if datei("start.fehler") is not None else 0)
    sys.exit(0)
if WER == "bluetoothctl":
    if argv[:1] == ["show"]:
        sys.stdout.write(datei("show.aus") or "")
    elif argv[:2] == ["devices", "Paired"]:
        sys.stdout.write(datei("paired.aus") or "")
    elif argv[:2] == ["devices", "Connected"]:
        sys.stdout.write(datei("connected.aus") or "")
    sys.exit(0)
if WER == "dpkg-query":
    if datei("bluez.fehlt") is not None:
        sys.exit(1)
    sys.stdout.write((datei("bluez.status") or "install ok installed").strip())
    sys.exit(0)
sys.exit(0)
'''

MODUL_TEIL = r"""
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
aenderung() { printf 'aenderung: %s\n' "$*"; }
pakete_sicherstellen() { printf 'pakete: %s\n' "$*"; }
set -Eeuo pipefail
trap 'echo "ABBRUCH $?" >&2' ERR
source "$1"
_BLUETOOTH_SYS=$BT_TEST/sys/class/bluetooth
modul_system
"""

DOCTOR_TEIL = r"""
abschnitt() { printf '== %s\n' "$*"; }
ok() { printf 'ok|%s\n' "$*"; }
hinweis() { printf 'hinweis|%s\n' "$*"; }
warnung() { printf 'warnung|%s\n' "$*"; }
fehler() { printf 'fehler|%s\n' "$*"; }
source "$1"
_bluetooth_sys=$BT_TEST/sys/class/bluetooth
_bluetooth_rfkill_sys=$BT_TEST/sys/class/rfkill
pruefe_bluetooth
"""

SHOW_AN = "Controller 00:00:5E:00:53:01 (public)\n\tPowered: yes\n\tDiscoverable: no\n\tPairable: no\n"


def schreiben(pfad, inhalt=""):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as datei:
        datei.write(inhalt)


class Fall(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-bluetooth.")
        self.fake = os.path.join(self.w, "fake")
        os.makedirs(self.fake)
        for name in ("systemctl", "bluetoothctl", "dpkg-query"):
            pfad = os.path.join(self.fake, name)
            schreiben(pfad, ATTRAPPE % name)
            os.chmod(pfad, 0o755)
        self.umgebung = {"PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"), "BT_TEST": self.w,
                         "LANG": "C.UTF-8", "SUDO": "", "ZENOS_SYSTEMD": "1", "ZENOS_IMAGE": "0"}

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def setzen(self, name, inhalt=""):
        schreiben(os.path.join(self.w, name), inhalt)

    def adapter(self):
        os.makedirs(os.path.join(self.w, "sys", "class", "bluetooth", "hci0"))

    def rfkill(self, soft, hard):
        r = os.path.join(self.w, "sys", "class", "rfkill", "rfkill0")
        schreiben(os.path.join(r, "type"), "bluetooth\n")
        schreiben(os.path.join(r, "soft"), f"{soft}\n")
        schreiben(os.path.join(r, "hard"), f"{hard}\n")

    def lauf(self, teil, skript, **umgebung):
        ergebnis = subprocess.run(["bash", "-c", teil, "test", skript], capture_output=True, text=True,
                                  env={**self.umgebung, **umgebung}, check=False, timeout=60)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        try:
            with open(os.path.join(self.w, "ereignisse"), encoding="utf-8") as datei:
                ereignisse = [" ".join(json.loads(z)) for z in datei]
        except OSError:
            ereignisse = []
        return ergebnis.stdout, ereignisse


@unittest.skipUnless(LINUX, "nur unter Linux (bash 4+)")
class ModulTest(Fall):
    def starts(self, ereignisse):
        return [e for e in ereignisse if e.startswith("systemctl start")]

    def test_nach_der_installation_starten(self):
        self.adapter()
        aus, ereignisse = self.lauf(MODUL_TEIL, MODUL)
        self.assertIn("pakete: bluez", aus)
        self.assertEqual(self.starts(ereignisse), ["systemctl start bluetooth.service"])
        self.assertIn("aenderung: bluetooth.service gestartet", aus)

    def test_laeuft_schon(self):
        self.adapter()
        self.setzen("aktiv")
        aus, ereignisse = self.lauf(MODUL_TEIL, MODUL)
        self.assertEqual(self.starts(ereignisse), [])
        self.assertNotIn("aenderung", aus)

    def test_bewusst_gestoppt_deaktiviert_maskiert(self):
        self.adapter()
        for name, inhalt in (("seit.wert", "123456789"), ("aktiviert.wert", "disabled"), ("aktiviert.wert", "masked")):
            for alt in ("seit.wert", "aktiviert.wert", "ereignisse"):
                if os.path.exists(os.path.join(self.w, alt)):
                    os.unlink(os.path.join(self.w, alt))
            self.setzen(name, inhalt)
            aus, ereignisse = self.lauf(MODUL_TEIL, MODUL)
            self.assertEqual(self.starts(ereignisse), [], f"{name}={inhalt}")
            self.assertNotIn("aenderung", aus)

    def test_ohne_adapter_ohne_systemd_im_image(self):
        _, ereignisse = self.lauf(MODUL_TEIL, MODUL)
        self.assertEqual(ereignisse, [], "ohne Bluetooth im Gerät fragt es systemd gar nicht")
        self.adapter()
        for umgebung in ({"ZENOS_SYSTEMD": "0"}, {"ZENOS_IMAGE": "1"}):
            aus, ereignisse = self.lauf(MODUL_TEIL, MODUL, **umgebung)
            self.assertEqual(ereignisse, [], umgebung)
            self.assertIn("pakete: bluez", aus)

    def test_start_scheitert_nur_mit_warnung(self):
        self.adapter()
        self.setzen("start.fehler")
        aus, _ = self.lauf(MODUL_TEIL, MODUL)
        self.assertIn("warnung: bluetooth.service liess sich nicht starten", aus)
        self.assertNotIn("aenderung", aus)


@unittest.skipUnless(LINUX, "nur unter Linux (bash 4+)")
class DoctorTest(Fall):
    def zeilen(self):
        aus, _ = self.lauf(DOCTOR_TEIL, DOCTOR)
        return [z for z in aus.splitlines() if not z.startswith("== ")]

    def test_kein_bluetooth(self):
        self.assertEqual(self.zeilen(), ["hinweis|Kein Bluetooth im Gerät"])

    def test_bluez_fehlt(self):
        self.adapter()
        self.setzen("bluez.fehlt")
        self.assertEqual(self.zeilen(), ["fehler|bluez fehlt: Das System-Menü kann Bluetooth nicht bedienen (install.sh)"])

    def test_dienst_aus_und_gesperrt(self):
        self.adapter()
        self.rfkill(1, 0)
        self.assertEqual(self.zeilen(), ["warnung|bluetooth.service ist «inactive» (sudo systemctl start bluetooth)",
                                         "warnung|Bluetooth ist per rfkill gesperrt (rfkill unblock bluetooth)"])

    def test_alles_in_ordnung_nur_anzahlen(self):
        self.adapter()
        self.rfkill(0, 0)
        self.setzen("aktiv")
        self.setzen("show.aus", SHOW_AN)
        self.setzen("paired.aus", "Device 00:00:5E:00:53:10 Maus von Beispiel\nDevice 00:00:5E:00:53:11 Kopfhörer\n")
        self.setzen("connected.aus", "Device 00:00:5E:00:53:10 Maus von Beispiel\n")
        zeilen = self.zeilen()
        self.assertEqual(zeilen, ["ok|bluetooth.service läuft", "ok|Adapter an (aus- und einschalten im System-Menü)",
                                  "ok|Für andere nicht sichtbar", "hinweis|Gekoppelt: 2, verbunden: 1"])
        text = "\n".join(zeilen)
        for geheim in ("00:00:5E", "Maus von Beispiel", "Kopfhörer"):
            self.assertNotIn(geheim, text)

    def test_aus_sichtbar_hart_gesperrt(self):
        self.adapter()
        self.rfkill(0, 1)
        self.setzen("aktiv")
        self.setzen("show.aus", SHOW_AN.replace("Powered: yes", "Powered: no").replace("Discoverable: no",
                                                                                      "Discoverable: yes"))
        self.assertEqual(self.zeilen(), ["ok|bluetooth.service läuft",
                                         "warnung|Bluetooth ist hart gesperrt (rfkill, Schalter oder Firmware)",
                                         "hinweis|Adapter aus (einschalten im System-Menü › Bluetooth)",
                                         "warnung|Der Rechner ist für andere sichtbar (bluetoothctl discoverable off)",
                                         "hinweis|Gekoppelt: 0, verbunden: 0"])

    def test_bluez_antwortet_nicht(self):
        self.adapter()
        self.setzen("aktiv")
        self.assertEqual(self.zeilen(), ["ok|bluetooth.service läuft", "warnung|BlueZ antwortet nicht (bluetoothctl show)"])


class PaketeTest(unittest.TestCase):
    def test_nur_bluez(self):
        with open(PAKETE, encoding="utf-8") as datei:
            pakete = [z.split("#", 1)[0].strip() for z in datei]
        self.assertEqual([p for p in pakete if p], ["bluez"])


if __name__ == "__main__":
    unittest.main()
