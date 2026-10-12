#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-dock (Docks und Bildschirm über USB), die udev-Regel
system/udev/73-zenos-dock.rules, die Einheit system/systemd/user/zenos-dock.service, das Modul
scripts/module/84-dock.sh und den Teil «Befunde» von scripts/doctor.d/84-dock.sh.

Ohne Hardware: Jeder Test baut sich einen eigenen /sys- und /proc-Baum (ZENOS_DOCK_TESTWURZEL), einmal wie am Argon ONE
UP (Compute Module 5: nur HDMI, ein i-tec-Dock mit Billboard von Fresco Logic, LAN über r8152), einmal wie an einem
x86-Rechner mit DisplayPort. notify-send und busctl sind Attrappen in einem eigenen PATH.

  python3 test/einheiten/dock.test.py
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-dock")
REGEL = os.path.join(WURZEL, "system", "udev", "73-zenos-dock.rules")
EINHEIT = os.path.join(WURZEL, "system", "systemd", "user", "zenos-dock.service")
SITZUNG = os.path.join(WURZEL, "system", "systemd", "user", "zenos-sitzung.target")
MODUL = os.path.join(WURZEL, "scripts", "module", "84-dock.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "84-dock.sh")
LINUX = sys.platform.startswith("linux")

_loader = importlib.machinery.SourceFileLoader("zenos_dock", PROGRAMM)
_spec = importlib.util.spec_from_loader("zenos_dock", _loader)
D = importlib.util.module_from_spec(_spec)
_loader.exec_module(D)

# BOS-Deskriptor des Billboards im i-tec C31TRIPLEDOCKPDPRO2 (Fresco Logic 1d5c:7102), am Argon ONE UP ausgelesen:
# USB-2.0-Erweiterung, Container-ID aus Nullen, Billboard 1.1 mit einem Alt Mode, SVID 0 und «erfolgreich» (0b11)
BOS_ITEC = bytes.fromhex(
    "050f500003" "07100206000000" "14100400" + "00" * 16
    + "30100d0401000000" + "03" + "00" * 31 + "10010000" + "00000000")
# Dasselbe mit SVID ff01 (DisplayPort)
BOS_DP = BOS_ITEC[:-4] + bytes.fromhex("01ff0000")


def schreiben(pfad, inhalt):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    modus = "wb" if isinstance(inhalt, bytes) else "w"
    with open(pfad, modus) as datei:
        datei.write(inhalt)


def lesen(pfad):
    with open(pfad, encoding="utf-8") as datei:
        return datei.read()


def ohne_kommentare(text):
    return [z.strip() for z in text.splitlines() if z.strip() and not z.strip().startswith("#")]


class Baum:
    """Ein /sys- und /proc-Baum unter einem Testordner."""

    def __init__(self, wurzel):
        self.w = wurzel
        self.usb = os.path.join(wurzel, "sys", "bus", "usb", "devices")
        os.makedirs(self.usb)
        os.makedirs(os.path.join(wurzel, "sys", "class", "drm"))
        os.makedirs(os.path.join(wurzel, "proc"))
        # Root-Hub und seine Schnittstelle zählen nie
        self.geraet("usb1", "1d6b", "0002", klasse="09", produkt="DWC OTG Controller")
        self.schnittstelle("1-0:1.0", "09", "hub")

    def treiber(self, name):
        pfad = os.path.join(self.w, "sys", "bus", "usb", "drivers", name)
        os.makedirs(pfad, exist_ok=True)
        return pfad

    def geraet(self, port, vid, pid, klasse="00", hersteller="", produkt="", bos=b""):
        d = os.path.join(self.usb, port)
        for name, wert in (("idVendor", vid), ("idProduct", pid), ("bDeviceClass", klasse),
                           ("manufacturer", hersteller), ("product", produkt)):
            if wert:
                schreiben(os.path.join(d, name), wert + "\n")
        if bos:
            schreiben(os.path.join(d, "bos_descriptors"), bos)

    def schnittstelle(self, name, klasse, treiber=None):
        d = os.path.join(self.usb, name)
        schreiben(os.path.join(d, "bInterfaceClass"), klasse + "\n")
        if treiber:
            os.symlink(self.treiber(treiber), os.path.join(d, "driver"))

    def ausgang(self, karte, name, verbunden, treiber="vc4-drm"):
        drm = os.path.join(self.w, "sys", "class", "drm")
        schreiben(os.path.join(drm, f"{karte}-{name}", "status"), "connected\n" if verbunden else "disconnected\n")
        geraet = os.path.join(drm, karte, "device")
        if not os.path.exists(geraet):
            os.makedirs(geraet)
            ziel = os.path.join(self.w, "sys", "bus", "platform", "drivers", treiber)
            os.makedirs(ziel, exist_ok=True)
            os.symlink(ziel, os.path.join(geraet, "driver"))

    def netz(self, name, geraetepfad, treiber, kabel):
        ziel = os.path.join(self.w, "sys", "devices", *geraetepfad.split("/"))
        os.makedirs(ziel, exist_ok=True)
        if treiber:
            os.symlink(self.treiber(treiber), os.path.join(ziel, "driver"))
        netz = os.path.join(self.w, "sys", "class", "net", name)
        os.makedirs(netz)
        os.symlink(ziel, os.path.join(netz, "device"))
        if kabel is not None:
            schreiben(os.path.join(netz, "carrier"), "1\n" if kabel else "0\n")

    def modul(self, name):
        os.makedirs(os.path.join(self.w, "sys", "module", name))

    def prozess(self, pid, comm):
        schreiben(os.path.join(self.w, "proc", str(pid), "comm"), comm + "\n")

    def argon_one_up(self):
        """Wie am Gerät: eingebauter Hub, Kamera, Tastatur, dahinter das i-tec-Dock mit Billboard und LAN."""
        self.geraet("1-1", "1a86", "809e", klasse="09", produkt="USB2.0 HUB")
        self.schnittstelle("1-1:1.0", "09", "hub")
        self.geraet("1-1.4", "11cc", "2812", klasse="ef", hersteller="SunplusIT Inc", produkt="PC Camera")
        self.schnittstelle("1-1.4:1.0", "0e", "uvcvideo")
        self.geraet("1-1.2", "05e3", "0610", klasse="09", hersteller="GenesysLogic", produkt="USB2.1 Hub")
        self.geraet("1-1.2.4.1.2", "1d5c", "7102", klasse="11", hersteller="Fresco Logic, Inc",
                    produkt="Generic Billboard Device", bos=BOS_ITEC)
        self.schnittstelle("1-1.2.4.1.2:1.0", "11")
        self.geraet("1-1.2.4.4", "0bda", "8153", hersteller="Realtek", produkt="USB 10/100/1000 LAN")
        self.schnittstelle("1-1.2.4.4:1.0", "ff", "r8152")
        self.ausgang("card1", "HDMI-A-1", False)
        self.ausgang("card1", "HDMI-A-2", True)
        self.ausgang("card1", "Writeback-1", False)
        self.netz("enx0200005e0001", "platform/axi/1000480000.usb/usb1/1-1/1-1.2/1-1.2.4/1-1.2.4.4/1-1.2.4.4:1.0",
                  "r8152", True)
        self.netz("wlan0", "platform/axi/1000fff000.mmc/mmc_host/mmc1/mmc1:0001/mmc1:0001:1", "brcmfmac", True)


class Fall(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-dock.")
        self.baum = Baum(os.path.join(self.w, "wurzel"))
        self.home = os.path.join(self.w, "home")
        os.makedirs(self.home)
        self.fake = os.path.join(self.w, "fake")
        os.makedirs(self.fake)
        for name, text in (("notify-send", NOTIFY), ("busctl", BUSCTL)):
            pfad = os.path.join(self.fake, name)
            schreiben(pfad, text)
            os.chmod(pfad, 0o755)

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def lauf(self, *argv, erwartet=0):
        umgebung = {"PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"), "HOME": self.home,
                    "LANG": "C.UTF-8", "ZENOS_DOCK_TESTWURZEL": self.baum.w, "DOCK_TEST": self.w}
        ergebnis = subprocess.run([sys.executable, "-I", PROGRAMM, *argv], capture_output=True, text=True,
                                  env=umgebung, timeout=60, check=False)
        self.assertEqual(ergebnis.returncode, erwartet, ergebnis.stderr)
        return ergebnis

    def zeilen(self):
        aus = self.lauf("pruefen").stdout
        zeilen = [tuple(z.split("\t", 1)) for z in aus.splitlines()]
        for zeile in zeilen:
            self.assertEqual(len(zeile), 2, aus)
            self.assertIn(zeile[0], ("ok", "hinweis", "warnung", "fehler"))
        return zeilen

    def mitteilungen(self):
        try:
            with open(os.path.join(self.w, "notify"), encoding="utf-8") as datei:
                return [json.loads(z) for z in datei]
        except OSError:
            return []

    def gemerkt(self):
        pfad = os.path.join(self.home, ".local", "state", "zenos", "dock-meldungen.json")
        with open(pfad, encoding="utf-8") as datei:
            return json.load(datei)


# notify-send: schreibt seine Argumente als JSON-Zeile; Exit aus notify.exit (Standard 0)
NOTIFY = r'''#!/usr/bin/env python3
import json, os, sys
ordner = os.environ["DOCK_TEST"]
with open(os.path.join(ordner, "notify"), "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
try:
    sys.exit(int(open(os.path.join(ordner, "notify.exit")).read()))
except OSError:
    sys.exit(0)
'''

# busctl: Der Mitteilungsdienst ist da
BUSCTL = r'''#!/usr/bin/env python3
print("b true")
'''


class BillboardTest(unittest.TestCase):
    def test_itec_dock_ohne_svid(self):
        self.assertEqual(D.billboard_modes(BOS_ITEC), [])

    def test_displayport(self):
        self.assertEqual(D.billboard_modes(BOS_DP), [0xFF01])
        self.assertEqual(D.mode_text([0xFF01]), " (DisplayPort)")
        self.assertEqual(D.mode_text([0xFF01, 0x8087]), " (DisplayPort und Thunderbolt)")
        self.assertEqual(D.mode_text([0x1234]), " (SVID 1234)")

    def test_billboard_1_0_ohne_versionsangabe(self):
        # 40 Byte vor der Liste: ohne bcdVersion, bAdditionalFailureInfo und bReserved
        faehigkeit = bytes([44, 0x10, 0x0D, 0, 1, 0, 0, 0]) + b"\x03" + b"\x00" * 31 + bytes.fromhex("01ff0000")
        bos = bytes([5, 0x0F, 5 + len(faehigkeit), 0, 1]) + faehigkeit
        self.assertEqual(D.billboard_modes(bos), [0xFF01])

    def test_kaputt_oder_fremd(self):
        for bos in (b"", b"\x05\x0f", BOS_ITEC[:40], bytes([5, 0x0F, 80, 0, 3, 0, 0x10, 0x0D]),
                    bytes.fromhex("050f0c000107100206000000")):
            self.assertEqual(D.billboard_modes(bos), [], bos.hex())
        # Länge passt nicht zur Zahl der Alt Modes
        falsch = bytearray(BOS_ITEC)
        falsch[0x24] = 3
        self.assertEqual(D.billboard_modes(bytes(falsch)), [])

    def test_texte_aus_dem_geraet(self):
        self.assertEqual(D.clean("USB 2.0 Hub            "), "USB 2.0 Hub")
        self.assertEqual(D.clean("a\x00b\nc\x7f"), "a b c")
        self.assertEqual(len(D.clean("x" * 200)), D.TEXT_LIMIT)
        self.assertEqual(D.clean(None), "")


class ArgonOneUpTest(Fall):
    """Compute Module 5 im Argon ONE UP: kein DisplayPort, auch nicht an USB-C."""

    def setUp(self):
        super().setUp()
        self.baum.argon_one_up()

    def test_bericht(self):
        zeilen = self.zeilen()
        self.assertEqual(zeilen[0], ("ok", "Bildausgänge: HDMI-A-1 frei, HDMI-A-2 verbunden · kein DisplayPort, "
                                           "auch nicht über USB-C"))
        self.assertEqual(zeilen[1][0], "hinweis")
        self.assertTrue(zeilen[1][1].startswith("USB-C-Dock (Billboard 1d5c:7102, Fresco Logic, Inc, Generic "
                                                "Billboard Device): will das Bild über USB-C, dieser Rechner hat "
                                                "keinen DisplayPort-Ausgang"), zeilen[1][1])
        self.assertTrue(zeilen[1][1].endswith("Bildschirm an HDMI anschliessen (frei: HDMI-A-1)"))
        self.assertIn(("ok", "Netzwerk über USB (r8152): Kabel steckt"), zeilen)
        self.assertEqual(len(zeilen), 3, zeilen)

    def test_keine_netzwerknamen_und_adressen(self):
        aus = self.lauf("pruefen").stdout
        self.assertNotIn("enx", aus)
        self.assertNotIn("0200005e", aus)
        self.assertNotIn("wlan0", aus)

    def test_melden_einmal(self):
        self.lauf("melden", "--warten", "0")
        mitteilungen = self.mitteilungen()
        self.assertEqual(mitteilungen, [[
            "--app-name=zenOS", "--icon=zenos", "--urgency=normal", "--category=device", "--",
            "Dock: kein Bild über USB-C",
            "Dieser Rechner gibt über USB-C kein Bild aus, daran ändert auch ein Treiber nichts. Schliess den "
            "Bildschirm an HDMI an. USB und Netzwerk am Dock gehen weiter."]])
        gemerkt = self.gemerkt()
        self.assertEqual(gemerkt["version"], 1)
        self.assertEqual(list(gemerkt["gemeldet"]), ["billboard:1d5c:7102:kein-dp"])
        ordner = os.path.join(self.home, ".local", "state", "zenos")
        self.assertEqual(os.stat(os.path.join(ordner, "dock-meldungen.json")).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.join(ordner, "dock-meldungen.lock")).st_mode & 0o777, 0o600)
        # Zweiter Lauf (nächstes Einstecken, nächstes Anmelden): nichts Neues
        self.lauf("melden", "--warten", "0")
        self.assertEqual(len(self.mitteilungen()), 1)
        self.assertIn(("hinweis", "Schon gemeldet: 1 Befund (neu melden: zenos-dock vergessen)"), self.zeilen())

    def test_nicht_zugestellt_bleibt_offen(self):
        schreiben(os.path.join(self.w, "notify.exit"), "1")
        self.lauf("melden", "--warten", "0")
        self.assertEqual(len(self.mitteilungen()), 1)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".local", "state", "zenos", "dock-meldungen.json")))
        os.unlink(os.path.join(self.w, "notify.exit"))
        self.lauf("melden", "--warten", "0")
        self.assertEqual(len(self.mitteilungen()), 2)
        self.assertIn("billboard:1d5c:7102:kein-dp", self.gemerkt()["gemeldet"])

    def test_vergessen(self):
        self.assertEqual(self.lauf("vergessen").stdout.strip(), "Nichts gemerkt")
        self.lauf("melden", "--warten", "0")
        self.assertIn("gelöscht", self.lauf("vergessen").stdout)
        self.lauf("melden", "--warten", "0")
        self.assertEqual(len(self.mitteilungen()), 2)

    def test_kaputter_merker_gilt_als_leer(self):
        schreiben(os.path.join(self.home, ".local", "state", "zenos", "dock-meldungen.json"), "{kaputt")
        self.lauf("melden", "--warten", "0")
        self.assertEqual(len(self.mitteilungen()), 1)
        self.assertEqual(list(self.gemerkt()["gemeldet"]), ["billboard:1d5c:7102:kein-dp"])

    def test_billboard_als_schnittstelle(self):
        shutil.rmtree(os.path.join(self.baum.usb, "1-1.2.4.1.2"))
        shutil.rmtree(os.path.join(self.baum.usb, "1-1.2.4.1.2:1.0"))
        self.baum.geraet("1-1.2.3", "2109", "0103", klasse="ef", produkt="USB-C Hub")
        self.baum.schnittstelle("1-1.2.3:1.0", "11")
        zeilen = self.zeilen()
        self.assertTrue(zeilen[1][1].startswith("USB-C-Dock (Billboard 2109:0103, USB-C Hub)"), zeilen)


class X86Test(Fall):
    """Ein Rechner mit DisplayPort an USB-C: Dann entscheidet, ob ein DisplayPort-Bildschirm verbunden ist."""

    def setUp(self):
        super().setUp()
        self.baum.ausgang("card0", "eDP-1", True, treiber="i915")
        self.baum.ausgang("card0", "HDMI-A-1", False, treiber="i915")
        self.baum.ausgang("card0", "DP-1", False, treiber="i915")
        self.baum.ausgang("card0", "DP-2", False, treiber="i915")
        self.baum.geraet("3-2", "1d5c", "7102", klasse="11", hersteller="Fresco Logic, Inc", bos=BOS_DP)

    def test_buchse_ohne_bild(self):
        zeilen = self.zeilen()
        self.assertEqual(zeilen[0], ("ok", "Bildausgänge: DP-1 frei, DP-2 frei, HDMI-A-1 frei, eDP-1 verbunden"))
        self.assertEqual(zeilen[1][0], "warnung")
        self.assertIn("will das Bild über USB-C (DisplayPort), die Buchse liefert ihm keins", zeilen[1][1])
        self.lauf("melden", "--warten", "0")
        self.assertEqual(self.mitteilungen()[0][5], "Dock: kein Bild an dieser Buchse")
        self.assertEqual(list(self.gemerkt()["gemeldet"]), ["billboard:1d5c:7102:buchse"])

    def test_bild_da(self):
        self.baum.ausgang("card0", "DP-3", True, treiber="i915")
        zeilen = self.zeilen()
        self.assertEqual(zeilen[1][0], "ok")
        self.assertTrue(zeilen[1][1].endswith("ein DisplayPort-Bildschirm ist verbunden"))
        self.lauf("melden", "--warten", "0")
        self.assertEqual(self.mitteilungen(), [])

    def test_edp_zaehlt_nicht_als_displayport(self):
        for name in ("DP-1", "DP-2"):
            shutil.rmtree(os.path.join(self.baum.w, "sys", "class", "drm", f"card0-{name}"))
        zeilen = self.zeilen()
        self.assertIn("kein DisplayPort", zeilen[0][1])
        self.assertIn("keinen DisplayPort-Ausgang", zeilen[1][1])


class DisplayLinkTest(Fall):
    def setUp(self):
        super().setUp()
        self.baum.ausgang("card1", "HDMI-A-1", False)
        self.baum.geraet("2-1", "17e9", "6006", klasse="ef", hersteller="DisplayLink", produkt="USB3.0 Dock")

    def test_ohne_treiber(self):
        self.baum.schnittstelle("2-1:1.0", "ff")
        zeilen = self.zeilen()
        self.assertEqual(zeilen[1][0], "hinweis")
        self.assertIn("DisplayLink-Gerät (17e9:6006, DisplayLink, USB3.0 Dock): kein Treiber", zeilen[1][1])
        self.lauf("melden", "--warten", "0")
        self.assertEqual(self.mitteilungen()[0][5:], [
            "DisplayLink-Gerät erkannt",
            "Für ein Bild braucht dieses Gerät den DisplayLink-Treiber von Synaptics. zenOS liefert ihn nicht mit "
            "und hat ihn unter labwc noch nicht geprüft. Mehr mit zen doctor."])

    def test_kernel_treiber_udl(self):
        self.baum.schnittstelle("2-1:1.0", "ff", "udl")
        zeilen = self.zeilen()
        self.assertEqual(zeilen[1], ("ok", "DisplayLink-Gerät (17e9:6006, DisplayLink, USB3.0 Dock): Kernel-Treiber udl"))
        self.lauf("melden", "--warten", "0")
        self.assertEqual(self.mitteilungen(), [])

    def test_treiber_von_synaptics(self):
        self.baum.schnittstelle("2-1:1.0", "ff", "usbfs")
        self.baum.modul("evdi")
        self.baum.prozess(4242, "DisplayLinkMana")
        zeilen = self.zeilen()
        self.assertEqual(zeilen[1][0], "hinweis")
        self.assertIn("DisplayLink-Treiber läuft (evdi, DisplayLinkManager), unter labwc ungetestet", zeilen[1][1])
        self.lauf("melden", "--warten", "0")
        self.assertEqual(self.mitteilungen(), [])

    def test_evdi_allein_reicht_nicht(self):
        self.baum.schnittstelle("2-1:1.0", "ff")
        self.baum.modul("evdi")
        self.assertIn("kein Treiber", self.zeilen()[1][1])


class OhneDockTest(Fall):
    def test_nichts_angeschlossen(self):
        self.baum.ausgang("card1", "HDMI-A-1", True)
        self.assertEqual(self.zeilen(), [
            ("ok", "Bildausgänge: HDMI-A-1 verbunden · kein DisplayPort, auch nicht über USB-C"),
            ("ok", "Kein USB-C-Dock mit Billboard und kein DisplayLink-Gerät angeschlossen")])
        self.lauf("melden", "--warten", "0")
        self.assertEqual(self.mitteilungen(), [])
        self.assertFalse(os.path.exists(os.path.join(self.home, ".local", "state")))

    def test_ohne_bildausgaenge(self):
        self.assertEqual(self.zeilen()[0], ("hinweis", "Keine Bildausgänge unter /sys/class/drm"))


class AufrufTest(Fall):
    def test_falsche_aufrufe(self):
        for argv in ((), ("los",), ("melden", "--warten"), ("melden", "--warten", "x"), ("melden", "--warten", "61"),
                     ("pruefen", "--warten", "1"), ("melden", "--sofort")):
            ergebnis = self.lauf(*argv, erwartet=2)
            self.assertIn("Aufruf: zenos-dock", ergebnis.stderr)

    def test_hilfe(self):
        self.assertIn("zenos-dock melden", self.lauf("--hilfe").stdout)


class MerkerTest(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-dock-merker.")
        self.pfad = os.path.join(self.w, "dock-meldungen.json")

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def test_hoechstens_fuenfzig_die_neuesten(self):
        gesehen = {f"billboard:0000:{n:04x}:kein-dp": f"2026-10-{1 + n // 24:02d}T{n % 24:02d}:00:00+02:00"
                   for n in range(60)}
        D.save_state(self.pfad, gesehen)
        geladen = D.load_state(self.pfad)
        self.assertEqual(len(geladen), D.STATE_LIMIT)
        self.assertNotIn("billboard:0000:0000:kein-dp", geladen)
        self.assertIn("billboard:0000:003b:kein-dp", geladen)

    def test_fremde_inhalte(self):
        for inhalt in ("[]", '{"version": 2, "gemeldet": {"a": "b"}}', '{"version": 1, "gemeldet": []}',
                       '{"version": 1, "gemeldet": {"a": 1}}'):
            schreiben(self.pfad, inhalt)
            self.assertEqual(D.load_state(self.pfad), {}, inhalt)


class MitteilungsdienstTest(unittest.TestCase):
    def test_wartet_bis_er_da_ist(self):
        antworten = iter([False, False, True])
        with mock.patch.object(D, "server_ready", lambda: next(antworten)), mock.patch.object(D.time, "sleep"):
            self.assertTrue(D.wait_for_server(60))

    def test_gibt_auf(self):
        uhr = iter(range(0, 1000, 10))
        with mock.patch.object(D, "server_ready", lambda: False), mock.patch.object(D.time, "sleep"), \
                mock.patch.object(D.time, "monotonic", lambda: next(uhr)):
            self.assertFalse(D.wait_for_server(60))

    def test_ohne_dienst_keine_mitteilung(self):
        befund = {"key": "billboard:1d5c:7102:kein-dp", "title": "t", "message": "m", "text": "x"}
        w = tempfile.mkdtemp(prefix="zenos-dock-dienst.")
        self.addCleanup(shutil.rmtree, w, True)
        gesendet = []
        with mock.patch.dict(os.environ, {"HOME": w}), mock.patch.object(D, "current_findings", lambda: [befund]), \
                mock.patch.object(D, "wait_for_server", lambda sekunden: False), \
                mock.patch.object(D, "notify", gesendet.append):
            with contextlib.redirect_stderr(io.StringIO()) as fehler:
                self.assertEqual(D.run_report(0, D.Log(journal=False)), 0)
        self.assertIn("Mitteilungsdienst nicht erreichbar", fehler.getvalue())
        self.assertEqual(gesendet, [])
        self.assertFalse(os.path.exists(os.path.join(w, ".local", "state", "zenos", "dock-meldungen.json")))


# --- udev-Regel, Einheit -----------------------------------------------------


def regel_anwenden(eigenschaften):
    """Die udev-Regel für ein Gerät durchspielen (nur die Formen, die 73-zenos-dock.rules nutzt): Schlüssel wie
    «ACTION», «ENV{DEVTYPE}», «ATTR{bDeviceClass}». Gibt die Zuweisungen zurück oder None."""
    zeilen = ohne_kommentare(lesen(REGEL))
    i = 0
    while i < len(zeilen):
        teile = [t.strip() for t in zeilen[i].split(",")]
        if teile[0].startswith("LABEL="):
            i += 1
            continue
        bedingungen = [t for t in teile if re.match(r'^[A-Z]+(\{[A-Za-z_]+\})?(==|!=)"', t)]
        zuweisungen = [t for t in teile if t not in bedingungen]
        passt = True
        for b in bedingungen:
            schluessel, op, muster = re.match(r'^([A-Z]+(?:\{[A-Za-z_]+\})?)(==|!=)"(.*)"$', b).groups()
            treffer = eigenschaften.get(schluessel, "") == muster
            passt = passt and (treffer if op == "==" else not treffer)
        if not passt:
            i += 1
            continue
        ziel = [z for z in zuweisungen if z.startswith("GOTO=")]
        if ziel:
            label = "LABEL=" + ziel[0].split("=", 1)[1]
            i = next(j for j, z in enumerate(zeilen) if z == label)
            continue
        return zuweisungen
    return None


class RegelTest(unittest.TestCase):
    BILLBOARD = {"ACTION": "add", "SUBSYSTEM": "usb", "ENV{DEVTYPE}": "usb_device", "ATTR{bDeviceClass}": "11",
                 "ATTR{idVendor}": "1d5c"}
    MARKE = ['TAG+="systemd"', 'ENV{SYSTEMD_USER_WANTS}+="zenos-dock.service"']

    def test_billboard_und_displaylink(self):
        faelle = {
            "Billboard": self.BILLBOARD,
            "DisplayLink": {**self.BILLBOARD, "ATTR{bDeviceClass}": "ef", "ATTR{idVendor}": "17e9"},
            "Billboard als Schnittstelle": {"ACTION": "add", "SUBSYSTEM": "usb", "ENV{DEVTYPE}": "usb_interface",
                                            "ATTR{bInterfaceClass}": "11"},
        }
        for name, geraet in faelle.items():
            for aktion in ("add", "change", "bind"):
                self.assertEqual(regel_anwenden({**geraet, "ACTION": aktion}), self.MARKE, f"{name} {aktion}")

    def test_alles_andere_bleibt(self):
        faelle = {
            "Hub": {**self.BILLBOARD, "ATTR{bDeviceClass}": "09", "ATTR{idVendor}": "05e3"},
            "Netzwerk": {**self.BILLBOARD, "ATTR{bDeviceClass}": "00", "ATTR{idVendor}": "0bda"},
            "Entfernen": {**self.BILLBOARD, "ACTION": "remove"},
            "anderes Subsystem": {**self.BILLBOARD, "SUBSYSTEM": "input"},
            "Schnittstelle eines Hubs": {"ACTION": "add", "SUBSYSTEM": "usb", "ENV{DEVTYPE}": "usb_interface",
                                         "ATTR{bInterfaceClass}": "09"},
            "Klasse 11 an einer Schnittstelle als Gerät": {"ACTION": "add", "SUBSYSTEM": "usb",
                                                            "ENV{DEVTYPE}": "usb_interface",
                                                            "ATTR{bDeviceClass}": "11"},
        }
        for name, geraet in faelle.items():
            self.assertIsNone(regel_anwenden(geraet), name)

    def test_nur_markieren(self):
        text = "\n".join(ohne_kommentare(lesen(REGEL)))
        for verboten in ("MODE=", "GROUP=", "OWNER=", "RUN", "PROGRAM", "IMPORT", "uaccess", "SYSTEMD_WANTS",
                         "DRIVER", "ATTR{authorized}"):
            self.assertNotIn(verboten, text, verboten)


class EinheitTest(unittest.TestCase):
    def setUp(self):
        self.text = lesen(EINHEIT)
        self.zeilen = ohne_kommentare(self.text)

    def test_kurz_als_benutzer(self):
        for zeile in ("Type=oneshot", "ExecStart=/opt/zenos/scripts/bin/zenos-dock melden", "PartOf=zenos-sitzung.target",
                      "ConditionUser=!@system", "ConditionEnvironment=WAYLAND_DISPLAY",
                      "ConditionFileIsExecutable=/opt/zenos/scripts/bin/zenos-dock"):
            self.assertIn(zeile, self.zeilen)
        self.assertNotIn("[Install]", self.zeilen, "kein [Install]: udev und die Sitzung starten ihn")

    def test_regel_und_sitzung_nennen_sie(self):
        name = os.path.basename(EINHEIT)
        self.assertIn(f'ENV{{SYSTEMD_USER_WANTS}}+="{name}"', lesen(REGEL))
        wants = [z for z in ohne_kommentare(lesen(SITZUNG)) if z.startswith("Wants=") and "zenos-shell" in z]
        self.assertEqual(len(wants), 1)
        self.assertIn(name, wants[0].split("=", 1)[1].split())

    def test_frist_reicht_fuer_den_ganzen_lauf(self):
        # Einstecken abwarten, auf den Mitteilungsdienst warten, zwei Mitteilungen (Billboard und DisplayLink)
        frist = int(re.search(r"^TimeoutStartSec=(\d+)$", self.text, re.M).group(1))
        self.assertGreater(frist, D.WAIT_DEFAULT + D.SERVER_WAIT + 2 * D.COMMAND_TIMEOUT)


# --- Modul 84-dock und zen doctor --------------------------------------------

# Attrappe für udevadm: schreibt die Argumente als JSON-Zeile; «control --ping» geht nur mit der Datei «udev»,
# «trigger» scheitert mit der Datei «trigger.fehler»
UDEVADM = r'''#!/usr/bin/env python3
import json, os, sys
ordner = os.environ["MODUL_TEST"]
with open(os.path.join(ordner, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps(["udevadm"] + sys.argv[1:]) + "\n")
if sys.argv[1:3] == ["control", "--ping"]:
    sys.exit(0 if os.path.exists(os.path.join(ordner, "udev")) else 1)
if sys.argv[1:2] == ["trigger"] and os.path.exists(os.path.join(ordner, "trigger.fehler")):
    sys.exit(1)
sys.exit(0)
'''

MODUL_TEIL = r"""
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
_Z=0
aenderung() { _Z=$((_Z + 1)); printf 'aenderung: %s\n' "$*"; }
zenos_anzahl() { printf '%s' "$_Z"; }
befehl_vorhanden() { command -v -- "$1" > /dev/null 2>&1; }
systemd_neu_laden() { printf 'neu laden\n'; }
datei_installieren() { printf 'installieren: %s\n' "$2"; [[ -e "$MODUL_TEST/da.${2//\//_}" ]] || aenderung "$2"; }
set -Eeuo pipefail
trap 'echo "ABBRUCH $?" >&2' ERR
source "$1"
modul_system
"""


@unittest.skipUnless(LINUX, "nur unter Linux (bash 4+)")
class ModulTest(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-dock-modul.")
        self.fake = os.path.join(self.w, "fake")
        os.makedirs(self.fake)
        schreiben(os.path.join(self.fake, "udevadm"), UDEVADM)
        os.chmod(os.path.join(self.fake, "udevadm"), 0o755)
        self.umgebung = {"PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
                         "MODUL_TEST": self.w, "LANG": "C.UTF-8", "SUDO": "", "ZENOS_CODE": WURZEL,
                         "ZENOS_SYSTEMD": "1", "ZENOS_IMAGE": "0"}

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def setzen(self, name):
        schreiben(os.path.join(self.w, name), "")

    def lauf(self, **umgebung):
        ergebnis = subprocess.run(["bash", "-c", MODUL_TEIL, "modul", MODUL], capture_output=True, text=True,
                                  env={**self.umgebung, **umgebung}, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        try:
            with open(os.path.join(self.w, "ereignisse"), encoding="utf-8") as datei:
                ereignisse = [" ".join(json.loads(z)) for z in datei]
        except OSError:
            ereignisse = []
        return ergebnis.stdout, ereignisse

    def test_neue_regel_stoesst_nur_docks_an(self):
        self.setzen("udev")
        aus, ereignisse = self.lauf()
        self.assertIn("installieren: /etc/systemd/user/zenos-dock.service", aus)
        self.assertIn("installieren: /etc/udev/rules.d/73-zenos-dock.rules", aus)
        self.assertIn("neu laden", aus)
        self.assertEqual(ereignisse, [
            "udevadm control --ping",
            "udevadm control --reload",
            "udevadm trigger --action=change --subsystem-match=usb --attr-match=bDeviceClass=11",
            "udevadm trigger --action=change --subsystem-match=usb --attr-match=idVendor=17e9",
            "udevadm trigger --action=change --subsystem-match=usb --attr-match=bInterfaceClass=11",
        ])
        self.assertFalse([e for e in ereignisse if "--action=add" in e])

    def test_regel_unveraendert(self):
        self.setzen("udev")
        self.setzen("da._etc_udev_rules.d_73-zenos-dock.rules")
        aus, ereignisse = self.lauf()
        self.assertEqual(ereignisse, [])
        self.assertNotIn("neu laden", aus)

    def test_ohne_udev_und_im_image(self):
        _, ereignisse = self.lauf()
        self.assertEqual(ereignisse, ["udevadm control --ping"])
        self.setzen("udev")
        os.unlink(os.path.join(self.w, "ereignisse"))
        aus, ereignisse = self.lauf(ZENOS_IMAGE="1")
        self.assertEqual(ereignisse, [])
        self.assertIn("installieren: /etc/udev/rules.d/73-zenos-dock.rules", aus)

    def test_anstossen_scheitert_nur_mit_warnung(self):
        self.setzen("udev")
        self.setzen("trigger.fehler")
        aus, ereignisse = self.lauf()
        self.assertEqual(aus.count("warnung: udevadm trigger"), 3)
        self.assertEqual(len(ereignisse), 5)


DOCTOR_TEIL = r"""
ok() { printf 'ok|%s\n' "$*"; }
hinweis() { printf 'hinweis|%s\n' "$*"; }
warnung() { printf 'warnung|%s\n' "$*"; }
fehler() { printf 'fehler|%s\n' "$*"; }
source "$1"
_dock_code=$2
_dock_befunde
"""


@unittest.skipUnless(LINUX, "nur unter Linux (bash 4+)")
class DoctorTest(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-dock-doctor.")
        self.programm = os.path.join(self.w, "scripts", "bin", "zenos-dock")

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def lauf(self):
        ergebnis = subprocess.run(["bash", "-c", DOCTOR_TEIL, "doctor", DOCTOR, self.w], capture_output=True,
                                  text=True, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        return ergebnis.stdout.splitlines()

    def test_zeilen_werden_zu_befunden(self):
        schreiben(self.programm, "import sys\nprint('ok\\tBildausgänge: HDMI-A-1 frei')\n"
                                 "print('hinweis\\tUSB-C-Dock (…): will das Bild über USB-C')\nprint('quatsch')\n")
        self.assertEqual(self.lauf(), ["ok|Bildausgänge: HDMI-A-1 frei", "hinweis|USB-C-Dock (…): will das Bild über USB-C",
                                       "warnung|zenos-dock pruefen: unerwartete Zeile"])

    def test_programm_fehlt_oder_schweigt(self):
        self.assertEqual(self.lauf(), [f"fehler|{self.programm} fehlt (zen update oder install.sh)"])
        schreiben(self.programm, "")
        self.assertEqual(self.lauf(), [f"fehler|zenos-dock pruefen gibt nichts aus (python3 -I {self.programm} pruefen)"])

    def test_echtes_programm(self):
        os.makedirs(os.path.dirname(self.programm))
        shutil.copy(PROGRAMM, self.programm)
        zeilen = self.lauf()
        self.assertTrue(zeilen, "zenos-dock pruefen gibt am Testrechner etwas aus")
        for zeile in zeilen:
            self.assertRegex(zeile, r"^(ok|hinweis|warnung|fehler)\|")


if __name__ == "__main__":
    unittest.main()
