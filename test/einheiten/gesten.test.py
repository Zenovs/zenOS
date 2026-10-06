#!/usr/bin/env python3
"""Einheitentests für das Wischen mit drei Fingern: scripts/bin/zenos-gesten (Erkennung, Riegel für die Knoten, Socket,
Prüfung für zen doctor, Aufruf), die Einheit system/systemd/system/zenos-gesten.service, die udev-Regel
system/udev/72-zenos-gesten.rules, system/sysusers/zenos-gesten.conf, das Modul scripts/module/82-gesten.sh (Rückweg,
Image) und den Teil «Geräte» von scripts/doctor.d/82-gesten.sh. Dazu: Nirgends kommt jemand in die Gruppe input.

Ohne Touchpad, ohne libinput und ohne Uhr: Die Erkennung bekommt die Summen, die libinput liefern würde. Socket und
Modul laufen nur unter Linux (bash 4+, Unix-Sockets mit shutdown), als root und als Benutzer.

  python3 test/einheiten/gesten.test.py
"""

import errno
import fnmatch
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import shutil
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

# Kein __pycache__ neben scripts/bin/zenos-gesten, auch ohne pruefen.sh
sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-gesten")
EINHEIT = os.path.join(WURZEL, "system", "systemd", "system", "zenos-gesten.service")
REGEL = os.path.join(WURZEL, "system", "udev", "72-zenos-gesten.rules")
SYSUSERS = os.path.join(WURZEL, "system", "sysusers", "zenos-gesten.conf")
MODUL = os.path.join(WURZEL, "scripts", "module", "82-gesten.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "82-gesten.sh")
QML = os.path.join(WURZEL, "shell", "dienste", "Gesten.qml")
LINUX = os.path.exists("/proc/self")

_loader = importlib.machinery.SourceFileLoader("zenos_gesten", PROGRAMM)
_spec = importlib.util.spec_from_loader("zenos_gesten", _loader)
G = importlib.util.module_from_spec(_spec)
_loader.exec_module(G)


def lesen(pfad):
    with open(pfad, encoding="utf-8") as datei:
        return datei.read()


def ohne_kommentare(text):
    return [z.strip() for z in text.splitlines() if z.strip() and not z.lstrip().startswith("#")]


class StilleLog:
    def __init__(self):
        self.zeilen = []

    def info(self, text):
        self.zeilen.append(("info", text))

    def warning(self, text):
        self.zeilen.append(("warnung", text))

    def error(self, text):
        self.zeilen.append(("fehler", text))


def geste(erkenner, finger, schritte):
    """Eine Geste wie libinput: beginn, Bewegungen (dx, dy), ende. Gibt die ausgelösten Wörter zurück."""
    erkenner.begin(finger)
    woerter = [w for w in (erkenner.update(dx, dy) for dx, dy in schritte) if w]
    erkenner.end()
    return woerter


def gleichmaessig(dx, dy, n=20):
    return [(dx / n, dy / n)] * n


# --- Erkennung ----------------------------------------------------------------


class ErkennungTest(unittest.TestCase):
    def setUp(self):
        self.e = G.SwipeDetector()

    def test_drei_finger_hoch_und_runter(self):
        self.assertEqual(geste(self.e, 3, gleichmaessig(0, -190, 27)), ["oben"])
        self.assertEqual(geste(self.e, 3, gleichmaessig(0, 190, 27)), ["unten"])

    def test_einmal_je_geste(self):
        # 40 Schritte zu je -10: ab -60 ausgelöst, danach nichts mehr, auch nicht in die Gegenrichtung
        schritte = [(0, -10)] * 40 + [(0, 10)] * 40
        self.assertEqual(geste(self.e, 3, schritte), ["oben"])

    def test_genau_an_der_schwelle(self):
        self.assertEqual(geste(self.e, 3, [(0, -30), (0, -29.9)]), [])
        self.assertEqual(geste(self.e, 3, [(0, -30), (0, -30)]), ["oben"])

    def test_seitlich_und_schraeg_loesen_nicht_aus(self):
        self.assertEqual(geste(self.e, 3, gleichmaessig(-190, 0)), [])
        self.assertEqual(geste(self.e, 3, gleichmaessig(190, 0)), [])
        self.assertEqual(geste(self.e, 3, gleichmaessig(140, -140)), [])

    def test_steil_genug(self):
        # senkrecht mindestens doppelt so weit wie seitlich (Fall «6/14 mm» aus der Testreihe)
        self.assertEqual(geste(self.e, 3, gleichmaessig(60, -140)), ["oben"])
        self.assertEqual(geste(self.e, 3, gleichmaessig(40, -80)), ["oben"])
        self.assertEqual(geste(self.e, 3, gleichmaessig(41, -80)), [])

    def test_kurzer_weg(self):
        self.assertEqual(geste(self.e, 3, gleichmaessig(0, -48)), [])

    def test_nur_drei_finger(self):
        for finger in (2, 4, 5):
            self.assertEqual(geste(self.e, finger, gleichmaessig(0, -300)), [], finger)

    def test_wechsel_der_fingerzahl_beginnt_von_vorn(self):
        # libinput beendet die Geste beim Wechsel und beginnt eine neue: Der Weg davor zählt nicht
        self.e.begin(4)
        for dx, dy in gleichmaessig(0, -55, 10):
            self.assertIsNone(self.e.update(dx, dy))
        self.e.end()
        self.assertEqual(geste(self.e, 3, gleichmaessig(0, -40, 10)), [])
        self.assertEqual(geste(self.e, 3, gleichmaessig(0, -60, 10)), ["oben"])

    def test_beginn_ohne_ende(self):
        # Ein neues «beginn» setzt alles zurück, auch ohne «ende» dazwischen
        self.e.begin(3)
        self.e.update(0, -50)
        self.e.begin(3)
        self.assertIsNone(self.e.update(0, -50))
        self.assertEqual(self.e.update(0, -10), "oben")

    def test_ohne_beginn_und_unsinn(self):
        self.assertIsNone(self.e.update(0, -500))
        self.e.begin(3)
        self.assertIsNone(self.e.update(float("nan"), -500))
        self.assertIsNone(self.e.update(0, float("inf")))
        self.assertIsNone(self.e.update(0, -59))
        self.assertEqual(self.e.update(0, -1), "oben")

    def test_ende_gibt_summen(self):
        self.assertIsNone(self.e.end())
        self.e.begin(4)
        self.e.update(3, -20)
        self.e.update(1, -20)
        self.assertEqual(self.e.end(), (4, 4.0, -40.0, None))
        self.e.begin(3)
        self.e.update(0, -70)
        self.assertEqual(self.e.end(), (3, 0.0, -70.0, "oben"))
        self.assertIsNone(self.e.end())

    def test_eigene_schwelle(self):
        e = G.SwipeDetector(threshold=120)
        self.assertEqual(geste(e, 3, gleichmaessig(0, -100)), [])
        self.assertEqual(geste(e, 3, gleichmaessig(0, -130)), ["oben"])

    def test_messzeile_ohne_positionen(self):
        zeile = G.describe_gesture((3, 4.2, -190.4, "oben"), 60)
        self.assertEqual(zeile, "Wischen mit 3 Fingern: seitlich +4, senkrecht -190 (Schwelle 60) · löst aus: oben")
        self.assertIn("löst nichts aus", G.describe_gesture((4, 0, -300, None), 60))


class HandlerTest(unittest.TestCase):
    def test_dienst(self):
        log, gesendet = StilleLog(), []
        h = G.Handler(G.SwipeDetector(), log, send=gesendet.append)
        for ereignis in [("dazu", "event5", True), ("dazu", "event7", False), ("beginn", 3)] + \
                [("bewegung", 0.0, -10.0)] * 10 + [("ende", False), ("beginn", 3)] + \
                [("bewegung", 0.0, 12.0)] * 10 + [("ende", True), ("weg", "event5")]:
            h.handle(ereignis)
        self.assertEqual(gesendet, ["oben", "unten"])
        self.assertEqual(log.zeilen, [("info", "Touchpad event5 dazu"), ("info", "event7 dazu, ohne Gesten (geschlossen)"),
                                      ("info", "event5 weg")])
        self.assertEqual(h.devices, {"event7": False})

    def test_messmodus_schickt_nichts(self):
        log, zeilen = StilleLog(), []
        h = G.Handler(G.SwipeDetector(), log, line=zeilen.append)
        for ereignis in [("beginn", 3)] + [("bewegung", 1.0, -10.0)] * 8 + [("ende", False)]:
            h.handle(ereignis)
        self.assertEqual(zeilen, ["Wischen mit 3 Fingern: seitlich +8, senkrecht -80 (Schwelle 60) · löst aus: oben"])


# --- Riegel: nur Knoten der Gruppe zenos-gesten ------------------------------------


class RiegelTest(unittest.TestCase):
    GID = 985

    def knoten(self, art=stat.S_IFCHR, major=13, minor=67, uid=0, gid=GID, modus=0o640):
        return types.SimpleNamespace(st_mode=art | modus, st_rdev=os.makedev(major, minor), st_uid=uid, st_gid=gid)

    def test_touchpad_der_gruppe(self):
        self.assertTrue(G.node_allowed(self.knoten(), self.GID))

    def test_alles_andere_nicht(self):
        self.assertFalse(G.node_allowed(self.knoten(gid=104), self.GID), "Gruppe input")
        self.assertFalse(G.node_allowed(self.knoten(uid=1000), self.GID), "gehört nicht root")
        self.assertFalse(G.node_allowed(self.knoten(major=4), self.GID), "kein Eingabegerät (tty)")
        self.assertFalse(G.node_allowed(self.knoten(art=stat.S_IFBLK), self.GID), "Blockgerät")
        self.assertFalse(G.node_allowed(self.knoten(art=stat.S_IFREG), self.GID), "Datei")
        self.assertFalse(G.node_allowed(self.knoten(art=stat.S_IFIFO), self.GID), "FIFO")

    @unittest.skipUnless(LINUX, "nur unter Linux")
    def test_rueckruf_lehnt_ab_ohne_ausnahme(self):
        # _open gibt -EACCES für eine gewöhnliche Datei und -ENOENT für einen fehlenden Pfad, nie eine Ausnahme
        t = G.Touchpads.__new__(G.Touchpads)
        t.allowed_gid = os.getegid()
        t.log = StilleLog()
        with tempfile.NamedTemporaryFile() as datei:
            self.assertEqual(t._open(datei.name.encode(), os.O_RDWR, None), -errno.EACCES)
        self.assertEqual(t._open(b"/gibt/es/nicht", os.O_RDWR, None), -errno.ENOENT)
        self.assertEqual(t._open(None, 0, None), -errno.EACCES)


def bits(*nummern):
    return sum(1 << n for n in nummern)


# Fähigkeiten wie vom Kernel (EVIOCGBIT): ein reines Touchpad wie am Gerät, eine Tastatur, ein Touchpad mit Tasten
TOUCHPAD_KEYS = bits(0x110, G.BTN_TOOL_FINGER, 0x148, 0x14A, 0x14D, G.BTN_TOOL_TRIPLETAP, 0x14F)
TOUCHPAD_ABS = bits(0x00, 0x01, G.ABS_MT_SLOT, 0x35, 0x36, 0x37, 0x39)
TASTATUR_KEYS = bits(*range(1, 59))


class FaehigkeitenTest(unittest.TestCase):
    """Zweite Schicht neben der udev-Regel: Was der Kernel über den geöffneten Knoten sagt (Befund: Tastaturen hingen
    nur an der Gruppe des Knotens)."""

    def test_wie_udev_input_id(self):
        # ID_INPUT_KEY in udev: jedes Bit unter BTN_MISC und in den Blöcken KEY_OK…BTN_DPAD_UP, KEY_ALS_TOGGLE…
        # BTN_TRIGGER_HAPPY
        erwartet = [n for n in range(G.KEY_CNT) if n < 0x100 or 0x160 <= n < 0x220 or 0x230 <= n < 0x2C0]
        self.assertEqual([n for n in range(G.KEY_CNT) if G.KEY_MASK >> n & 1], erwartet)
        self.assertEqual((G.BTN_TOOL_FINGER, G.BTN_TOOL_TRIPLETAP, G.ABS_MT_SLOT), (325, 334, 47))

    def test_nur_reines_touchpad(self):
        self.assertTrue(G.touchpad_only(TOUCHPAD_KEYS, TOUCHPAD_ABS))
        faelle = {
            "Tastatur": (TASTATUR_KEYS, 0),
            "Tastatur mit Touchpad-Achsen": (TASTATUR_KEYS | TOUCHPAD_KEYS, TOUCHPAD_ABS),
            "Touchpad mit KEY_A": (TOUCHPAD_KEYS | bits(30), TOUCHPAD_ABS),
            "Touchpad mit Lautstärke": (TOUCHPAD_KEYS | bits(115), TOUCHPAD_ABS),
            "Touchpad mit KEY_RESERVED": (TOUCHPAD_KEYS | bits(0), TOUCHPAD_ABS),
            "hoher Block KEY_OK": (TOUCHPAD_KEYS | bits(0x160), TOUCHPAD_ABS),
            "hoher Block KEY_ALS_TOGGLE": (TOUCHPAD_KEYS | bits(0x230), TOUCHPAD_ABS),
            "ohne Slots": (TOUCHPAD_KEYS, bits(0x00, 0x01)),
            "ohne Finger": (TOUCHPAD_KEYS & ~bits(G.BTN_TOOL_FINGER), TOUCHPAD_ABS),
            "Maus": (bits(0x110, 0x111, 0x112), 0),
            "nichts": (0, 0),
        }
        for name, (tasten, achsen) in faelle.items():
            self.assertFalse(G.touchpad_only(tasten, achsen), name)
        # BTN_* ausserhalb der Tastenblöcke (Steuerkreuz, Joystick) sind keine Tasten
        self.assertTrue(G.touchpad_only(TOUCHPAD_KEYS | bits(0x220, 0x2C0), TOUCHPAD_ABS))

    def test_nur_lesende_anfragen(self):
        # EVIOCGBIT(EV_KEY, 96) und EVIOCGBIT(EV_ABS, 8) wie in linux/input.h
        self.assertEqual(G._ioc_read(0x20 + G.EV_KEY, 96), 0x80604521)
        self.assertEqual(G._ioc_read(0x20 + G.EV_ABS, 8), 0x80084523)
        anfragen = []

        def ioctl(fd, anfrage, puffer, veraendern):
            anfragen.append((fd, anfrage, len(puffer), veraendern))
            breite = struct.calcsize("L")
            wert = TASTATUR_KEYS if anfrage & 0xFF == 0x21 else TOUCHPAD_ABS
            woerter = [(wert >> (8 * breite * i)) & ((1 << 8 * breite) - 1) for i in range(len(puffer) // breite)]
            puffer[:] = struct.pack(f"@{len(woerter)}L", *woerter)
            return len(puffer)

        self.assertEqual(G.read_capabilities(7, ioctl), (TASTATUR_KEYS, TOUCHPAD_ABS))
        self.assertEqual(anfragen, [(7, 0x80604521, 96, True), (7, 0x80084523, 8, True)])
        self.assertTrue(all(a >> 30 == 2 for _, a, _, _ in anfragen), "nur _IOC_READ")

    def test_bitmaske_aus_bytes(self):
        breite = struct.calcsize("L")
        daten = struct.pack(f"@{16 // breite}L", *([0] * (16 // breite - 1) + [1]))
        self.assertEqual(G.bitmask_from_bytes(daten), 1 << (128 - 8 * breite))
        self.assertEqual(G.bitmask_from_bytes(bytes(8)), 0)

    def test_rueckruf_lehnt_tastatur_trotz_gruppe_ab(self):
        t = G.Touchpads.__new__(G.Touchpads)
        t.allowed_gid = os.getegid()
        t.log = StilleLog()
        with tempfile.NamedTemporaryFile() as datei, mock.patch.object(G, "node_allowed", return_value=True):
            with mock.patch.object(G, "read_capabilities", return_value=(TASTATUR_KEYS, 0)):
                self.assertEqual(t._open(datei.name.encode(), 0, None), -errno.EACCES)
            self.assertEqual(len(t.log.zeilen), 1)
            art, text = t.log.zeilen[0]
            self.assertEqual(art, "fehler")
            self.assertTrue(text.startswith(os.path.basename(datei.name) + " abgelehnt: kein reines Touchpad"), text)
            with mock.patch.object(G, "read_capabilities", side_effect=OSError(errno.ENOTTY, "kein evdev")):
                self.assertEqual(t._open(datei.name.encode(), 0, None), -errno.EACCES)
            with mock.patch.object(G, "read_capabilities", return_value=(TOUCHPAD_KEYS, TOUCHPAD_ABS)):
                fd = t._open(datei.name.encode(), 0, None)
            self.assertGreater(fd, 2)
            t._close(fd, None)
        self.assertEqual(len(t.log.zeilen), 1)

    def test_ohne_gesten_wird_geschlossen(self):
        code = lesen(PROGRAMM)
        self.assertIn("libinput_device_config_send_events_set_mode(device, SEND_EVENTS_DISABLED)", code)
        self.assertEqual(G.SEND_EVENTS_DISABLED, 1)


# --- Socket -------------------------------------------------------------------------


@unittest.skipUnless(LINUX, "nur unter Linux (shutdown auf Unix-Sockets wie im Dienst)")
class SocketTest(unittest.TestCase):
    def setUp(self):
        self.ordner = tempfile.mkdtemp(prefix="zg.", dir="/tmp")
        self.pfad = os.path.join(self.ordner, "gesten.sock")
        self.weg = []
        # Hier verbindet der Test selbst (als root oder als Benutzer): seine uid ist erlaubt, je uid bis zu 3
        self.b = G.Broadcaster(self.pfad, max_clients=3, per_uid=3, on_drop=self.weg.append,
                               allow=lambda uid: uid == os.geteuid())
        self.b.open()
        self.klienten = []

    def tearDown(self):
        for k in self.klienten:
            k.close()
        self.b.close()
        shutil.rmtree(self.ordner, ignore_errors=True)

    def klient(self):
        k = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        k.connect(self.pfad)
        k.settimeout(2)
        self.klienten.append(k)
        self.b.accept()
        return k

    def test_rechte_und_bereit(self):
        self.assertEqual(stat.S_IMODE(os.stat(self.pfad).st_mode), 0o666)
        self.assertFalse(os.path.exists(os.path.join(self.ordner, "bereit")))
        self.b.mark_ready()
        bereit = os.path.join(self.ordner, "bereit")
        self.assertEqual(stat.S_IMODE(os.stat(bereit).st_mode), 0o644)
        self.assertEqual(lesen(bereit), f"{os.getpid()}\n")
        self.b.close()
        self.assertFalse(os.path.exists(bereit))
        self.assertFalse(os.path.exists(self.pfad))

    def test_woerter_an_alle(self):
        a, b = self.klient(), self.klient()
        self.assertEqual(self.b.send("oben"), 0)
        self.assertEqual(self.b.send("unten"), 0)
        self.assertEqual(a.recv(64), b"oben\nunten\n")
        self.assertEqual(b.recv(64), b"oben\nunten\n")
        with self.assertRaises(ValueError):
            self.b.send("links")

    def test_klient_kann_nichts_schicken(self):
        a = self.klient()
        with self.assertRaises(BrokenPipeError):
            a.send(b"oben\n", socket.MSG_NOSIGNAL)

    def test_aeltester_derselben_uid_fliegt(self):
        a, b, c = self.klient(), self.klient(), self.klient()
        erster = self.b.clients[0].fileno()
        d = self.klient()
        self.assertEqual(len(self.b.clients), 3)
        self.assertEqual(self.weg, [erster])
        self.assertEqual(a.recv(8), b"", "der älteste ist getrennt")
        self.b.send("oben")
        for k in (b, c, d):
            self.assertEqual(k.recv(8), b"oben\n")

    def test_getrennte_und_volle_fliegen(self):
        a, b = self.klient(), self.klient()
        a.close()
        self.assertEqual(self.b.send("oben"), 1)
        self.assertEqual(len(self.b.clients), 1)
        # b liest nie: Irgendwann ist der Puffer voll, dann fliegt b, statt den Dienst aufzuhalten
        geflogen = 0
        for _ in range(500_000):
            geflogen += self.b.send("unten")
            if geflogen:
                break
        self.assertEqual(geflogen, 1)
        self.assertEqual(self.b.clients, [])

    def test_find_und_drop(self):
        a = self.klient()
        fd = self.b.clients[0].fileno()
        self.assertIs(self.b.find(fd), self.b.clients[0])
        self.b.drop(self.b.clients[0])
        self.assertIsNone(self.b.find(fd))
        self.assertEqual(self.weg, [fd])
        self.assertEqual(a.recv(8), b"")

    def test_uid_vom_kernel(self):
        self.klient()
        self.assertEqual(G.peer_uid(self.b.clients[0]), os.geteuid())
        self.assertEqual(self.b.owners[self.b.clients[0]], os.geteuid())

    def test_fremde_werden_sofort_getrennt(self):
        # Befund: Jeder lokale Benutzer konnte mitlesen und mit 8 Verbindungen die Oberfläche verdrängen
        self.b.allow = lambda uid: False
        a = self.klient()
        self.assertEqual(self.b.clients, [])
        self.assertEqual(a.recv(8), b"", "getrennt, ohne je etwas zu bekommen")
        self.b.allow = lambda uid: (_ for _ in ()).throw(OSError("kaputt"))
        self.assertEqual(self.klient().recv(8), b"", "im Zweifel nicht annehmen")
        self.b.get_uid = lambda conn: (_ for _ in ()).throw(OSError("kaputt"))
        self.b.allow = lambda uid: True
        self.assertEqual(self.klient().recv(8), b"")
        self.assertEqual(self.b.clients, [])

    def test_verdraengen_nur_innerhalb_derselben_uid(self):
        uids = iter([1000, 1000, 2000, 2000, 1000, 2000])
        self.b.per_uid = 2
        self.b.get_uid = lambda conn: next(uids)
        self.b.allow = lambda uid: True
        a, b, c = self.klient(), self.klient(), self.klient()
        self.assertEqual(sorted(self.b.owners.values()), [1000, 1000, 2000])
        # voll: Ein zweiter von 2000 verdrängt niemanden von 1000, er geht selbst
        d = self.klient()
        self.assertEqual(d.recv(8), b"")
        self.assertEqual(len(self.b.clients), 3)
        # ein dritter von 1000 verdrängt den ältesten von 1000
        e = self.klient()
        self.assertEqual(a.recv(8), b"", "der älteste von 1000 ist getrennt")
        self.b.send("oben")
        for k in (b, c, e):
            self.assertEqual(k.recv(8), b"oben\n")
        # 2000 hat nur einen, die Plätze sind voll: Der Neue geht wieder, c bleibt
        f = self.klient()
        self.assertEqual(f.recv(8), b"")
        self.b.send("unten")
        self.assertEqual(c.recv(8), b"unten\n")
        self.assertEqual(sorted(self.b.owners.values()), [1000, 1000, 2000])

    def test_flut_eines_anderen_trifft_die_oberflaeche_nicht(self):
        # Wie im Befund: ein fremder Benutzer verbindet immer wieder; die Oberfläche bekommt jede Geste
        eigene = os.geteuid()
        self.b.max_clients, self.b.per_uid = 8, 2
        oberflaeche = self.klient()
        self.b.get_uid = lambda conn: 65534
        self.b.allow = lambda uid: G.peer_allowed(uid, eigene)
        for _ in range(50):
            self.klient()
        self.assertEqual(len(self.b.clients), 1)
        self.b.send("oben")
        self.assertEqual(oberflaeche.recv(8), b"oben\n")

    def test_alter_socket_wird_ersetzt(self):
        self.b.close()
        with open(self.pfad, "w", encoding="utf-8"):
            pass
        b = G.Broadcaster(self.pfad)
        b.open()
        self.assertTrue(stat.S_ISSOCK(os.stat(self.pfad).st_mode))
        b.close()


class LeserTest(unittest.TestCase):
    """Wer darf die Gesten lesen? Der Benutzer an seat0, sonst gewöhnliche Benutzer, nie Dienste oder nobody."""

    def test_aktiver_benutzer(self):
        self.assertTrue(G.peer_allowed(1000, 1000))
        for uid in (0, 65534, 1001, 999):
            self.assertFalse(G.peer_allowed(uid, 1000), uid)

    def test_niemand_aktiv(self):
        for uid in (1000, 1001, 60000):
            self.assertTrue(G.peer_allowed(uid, None), uid)
        # root, Systemdienste, systemd-homed/DynamicUser (60001 bis 65519), nobody, Container-Bereiche
        for uid in (0, 1, 102, 999, 60001, 61184, 65519, 65534, 524288):
            self.assertFalse(G.peer_allowed(uid, None), uid)

    def test_aktiv_aus_libsystemd(self):
        class Lib:
            def __init__(self, ergebnis, uid=0):
                self.ergebnis, self.uid, self.aufrufe = ergebnis, uid, []

            def sd_seat_get_active(self, sitz, sitzung, zeiger):
                self.aufrufe.append((sitz, sitzung))
                zeiger._obj.value = self.uid
                return self.ergebnis

        lib = Lib(0, 1000)
        self.assertEqual(G.active_seat_uid(lib=lib), 1000)
        self.assertEqual(lib.aufrufe, [(b"seat0", None)])
        self.assertIsNone(G.active_seat_uid(lib=Lib(-errno.ENODATA)), "niemand aktiv")
        self.assertIsNone(G.active_seat_uid(lib=Lib(-errno.ENXIO)), "seat0 unbekannt")
        self.assertIsNone(G.active_seat_uid(lib=object()), "ohne libsystemd")

    def test_dienst_nutzt_die_sitzregel(self):
        b = G.Broadcaster("/gibt/es/nicht")
        self.assertIs(b.allow, G.seat_policy)
        self.assertIs(b.get_uid, G.peer_uid)
        self.assertEqual((b.max_clients, b.per_uid), (8, 2))
        with mock.patch.object(G, "active_seat_uid", return_value=None):
            self.assertTrue(G.seat_policy(1000))
            self.assertFalse(G.seat_policy(65534))
        with mock.patch.object(G, "active_seat_uid", return_value=1001):
            self.assertFalse(G.seat_policy(1000))


# --- Ablauf und Aufruf --------------------------------------------------------------


class AufrufTest(unittest.TestCase):
    def test_optionen(self):
        self.assertEqual(G.parse_args([]), {"mode": "dienst", "socket": G.SOCKET_PATH, "schwelle": 60.0})
        self.assertEqual(G.parse_args(["--messen", "--schwelle", "75"])["schwelle"], 75.0)
        self.assertEqual(G.parse_args(["--pruefen"])["mode"], "pruefen")
        self.assertEqual(G.parse_args(["--socket", "/tmp/x.sock"])["socket"], "/tmp/x.sock")
        for falsch in (["--messen", "--pruefen"], ["--schwelle", "5"], ["--schwelle", "nan"], ["--schwelle", "x"],
                       ["--schwelle"], ["--grab"], ["oben"]):
            with self.assertRaises(G.UsageError, msg=falsch):
                G.parse_args(falsch)

    def test_hilfe_und_falscher_aufruf(self):
        with mock.patch("sys.stdout", new=io.StringIO()) as aus:
            self.assertEqual(G.main(["--hilfe"]), 0)
        self.assertIn("nur lesend", aus.getvalue())
        with mock.patch("sys.stderr", new=io.StringIO()):
            self.assertEqual(G.main(["--unsinn"]), 2)

    def test_nie_als_root(self):
        log = StilleLog()
        with mock.patch.object(G.os, "geteuid", return_value=0):
            self.assertEqual(G.run(G.parse_args([]), log), 1)
            self.assertEqual(G.run(G.parse_args(["--messen"]), log, measure=True), 1)
        self.assertTrue(all(art == "fehler" and "nie als root" in text for art, text in log.zeilen))

    def test_beenden_nur_einmal(self):
        # Ein zweites SIGTERM oder SIGINT während des Aufräumens bricht nicht mit einer Ausnahme ab
        with mock.patch.object(G.signal, "signal") as setzen:
            with self.assertRaises(G.Stop):
                G._stop(G.signal.SIGTERM, None)
        self.assertEqual(sorted(c.args for c in setzen.call_args_list),
                         sorted([(G.signal.SIGTERM, G.signal.SIG_IGN), (G.signal.SIGINT, G.signal.SIG_IGN)]))

    def test_ohne_gruppe(self):
        log = StilleLog()
        with mock.patch.object(G.os, "geteuid", return_value=1000), \
                mock.patch.object(G.grp, "getgrnam", side_effect=KeyError("zenos-gesten")):
            self.assertEqual(G.run(G.parse_args([]), log), 1)
        self.assertIn("Gruppe zenos-gesten fehlt", log.zeilen[0][1])

    def test_kein_grab_kein_schreiben_im_code(self):
        # ioctl nur an einer Stelle und nur lesend (EVIOCGBIT über _ioc_read), also kein EVIOCGRAB; Geräte nur
        # lesend, und von Klienten wird nie gelesen
        code = lesen(PROGRAMM)
        self.assertNotRegex(code, r"0x40044590|EVIOCS|_IOW|_ioc_write")
        self.assertEqual(re.findall(r"\bioctl\(.*", code), ["ioctl(fd, _ioc_read(0x20 + event_type, len(buffer)), buffer, True)"])
        self.assertNotIn("O_RDWR", code)
        self.assertEqual(code.count("os.O_RDONLY"), 1)
        self.assertIn("os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOCTTY)", code)
        self.assertNotRegex(code, r"\.recv(_into|from|msg)?\(|\.read\(conn")

    def test_pfade_passen_zusammen(self):
        qml = lesen(QML)
        self.assertIn(f'pfad: "{G.SOCKET_PATH}"', qml)
        self.assertIn(f'bereitPfad: "{os.path.join(os.path.dirname(G.SOCKET_PATH), "bereit")}"', qml)
        self.assertIn('if (zeile !== "oben" && zeile !== "unten")', qml)
        self.assertEqual(G.WORDS, ("oben", "unten"))


# --- Prüfung für zen doctor ---------------------------------------------------------


TOUCHPAD_TASTEN = "e520 10000 0 0 0 0"  # BTN_LEFT, BTN_TOOL_FINGER … QUINTTAP, BTN_TOUCH (64-Bit-Wörter)


class PruefenTest(unittest.TestCase):
    GID, INPUT = 985, 104

    def geraet(self, name, gid=GID, modus=0o640, tasten=TOUCHPAD_TASTEN, **props):
        props = {k: v for k, v in props.items()}
        return {"name": name, "props": props, "keys": G.parse_bitmask(tasten, 64), "gid": gid, "mode": modus}

    def touchpad(self, name="event5", **weiter):
        return self.geraet(name, ID_INPUT="1", ID_INPUT_TOUCHPAD="1", **weiter)

    def befunde(self, geraete, eigene=(), **weiter):
        return G.evaluate(geraete, self.GID, self.INPUT, set(eigene), **weiter)

    def test_bitmaske(self):
        wert = G.parse_bitmask(TOUCHPAD_TASTEN, 64)
        self.assertTrue(wert >> G.BTN_TOOL_TRIPLETAP & 1)
        self.assertTrue(wert >> 272 & 1)
        self.assertFalse(wert >> 30 & 1)
        self.assertEqual(G.parse_bitmask("1 0", 64), 1 << 64)
        self.assertEqual(G.parse_bitmask("1 0", 32), 1 << 32)
        self.assertEqual(G.parse_bitmask("0", 64), 0)

    def test_alles_gut(self):
        b = self.befunde([self.touchpad()])
        self.assertIn(("ok", "Touchpad event5: nur für zenos-gesten lesbar (0640)"), b)
        self.assertIn(("ok", "Touchpad event5 meldet drei Finger (BTN_TOOL_TRIPLETAP)"), b)
        self.assertIn(("ok", "Diese Sitzung hat keine Rechte an /dev/input (weder input noch zenos-gesten)"), b)
        self.assertEqual([a for a, _ in b], ["ok", "ok", "ok"])

    def test_tastatur_in_der_gruppe_ist_ein_fehler(self):
        tastatur = self.geraet("event2", ID_INPUT="1", ID_INPUT_KEY="1", ID_INPUT_KEYBOARD="1")
        b = self.befunde([tastatur, self.touchpad()])
        self.assertEqual(b[0][0], "fehler")
        self.assertIn("event2 hat Tasten", b[0][1])
        mit_tasten = self.touchpad("event6", ID_INPUT_KEY="1")
        self.assertEqual(self.befunde([mit_tasten])[0][0], "fehler")

    def test_wie_regel_und_modul(self):
        # Befund: «0» galt hier als nicht gesetzt, in Regel und Modul aber als gesetzt (jeder nicht leere Wert)
        for schluessel in ("ID_INPUT_KEY", "ID_INPUT_KEYBOARD"):
            frei = self.touchpad(gid=self.INPUT, modus=0o660, **{schluessel: "0"})
            self.assertEqual(self.befunde([frei])[0][0], "hinweis", schluessel)
            self.assertIn("hat auch Tasten", self.befunde([frei])[0][1])
            self.assertEqual(self.befunde([self.touchpad(**{schluessel: "0"})])[0][0], "fehler", schluessel)
        # Touchpad nur bei genau «1»
        for wert in ("0", "true", "yes", ""):
            b = self.befunde([self.geraet("event5", gid=self.INPUT, modus=0o660, ID_INPUT_TOUCHPAD=wert)])
            self.assertEqual(b[0], ("hinweis", "Kein reines Touchpad: kein Wischen mit drei Fingern, Super+Tab geht "
                                               "immer"), wert)
            self.assertEqual(self.befunde([self.geraet("event5", ID_INPUT_TOUCHPAD=wert)])[0][0], "fehler", wert)
        self.assertIn("ENV{ID_INPUT_TOUCHPAD}!=\"1\"", lesen(REGEL))
        self.assertIn("ENV{ID_INPUT_KEY}==\"?*\"", lesen(REGEL))
        self.assertIn("grep -qx 'ID_INPUT_TOUCHPAD=1'", lesen(MODUL))
        self.assertIn("grep -qE '^ID_INPUT_(KEY|KEYBOARD)=.'", lesen(MODUL))

    def test_tasten_laut_kernel(self):
        # Meldet der Kernel eine Taste, zählt das wie ID_INPUT_KEY, auch wenn udev es (etwa per hwdb) anders sieht
        mit_taste = self.touchpad(tasten="e520 10000 0 0 0 40000000")  # dazu KEY_A (30)
        self.assertEqual(self.befunde([mit_taste])[0][0], "fehler")
        self.assertIn("hat Tasten", self.befunde([mit_taste])[0][1])

    def test_kein_touchpad_in_der_gruppe(self):
        maus = self.geraet("event3", ID_INPUT="1", ID_INPUT_MOUSE="1")
        self.assertEqual(self.befunde([maus])[0], ("fehler", "event3 ist kein Touchpad und gehört trotzdem der Gruppe "
                                                            "zenos-gesten (udev-Regeln prüfen)"))

    def test_touchpad_ohne_regel_oder_mit_falschen_rechten(self):
        self.assertEqual(self.befunde([self.touchpad(gid=self.INPUT, modus=0o660)])[0][0], "warnung")
        self.assertEqual(self.befunde([self.touchpad(modus=0o660)])[0][0], "fehler")
        self.assertEqual(self.befunde([self.touchpad(modus=0o644)])[0][0], "fehler")
        self.assertEqual(self.befunde([self.touchpad(modus=None)])[0][0], "fehler")

    def test_touchpad_mit_tasten_und_ohne_drei_finger(self):
        mit_tasten = self.touchpad("event6", gid=self.INPUT, modus=0o660, ID_INPUT_KEY="1")
        b = self.befunde([mit_tasten])
        self.assertEqual(b[0][0], "hinweis")
        self.assertIn("hat auch Tasten", b[0][1])
        self.assertIn(("hinweis", "Kein reines Touchpad: kein Wischen mit drei Fingern, Super+Tab geht immer"), b)
        zwei = self.touchpad(tasten="2520 10000 0 0 0 0")  # ohne TRIPLETAP und QUADTAP
        self.assertEqual(self.befunde([zwei])[1][0], "hinweis")
        self.assertIn("meldet keine drei Finger", self.befunde([zwei])[1][1])

    def test_sitzung_und_gruppen(self):
        self.assertEqual(self.befunde([], eigene=[1000, self.INPUT])[-1][0], "fehler")
        self.assertIn("Gruppe input", self.befunde([], eigene=[self.INPUT])[-1][1])
        self.assertIn("nur dem Dienst", self.befunde([], eigene=[self.GID])[-1][1])
        b = self.befunde([], group_members=("jemand",), input_members=("jemand",))
        self.assertIn("fehler", [a for a, _ in b])
        self.assertIn("warnung", [a for a, _ in b])
        self.assertNotIn("jemand", json.dumps(b), "keine Benutzernamen im Bericht")
        root = G.evaluate([], self.GID, self.INPUT, None)
        self.assertNotIn("Sitzung", json.dumps(root, ensure_ascii=False))
        ohne = G.evaluate([], None, None, {1000})
        self.assertIn(("hinweis", "Gruppe zenos-gesten gibt es nicht (Gesten aus oder install.sh noch nicht gelaufen)"),
                      ohne)

    def test_einlesen_aus_testwurzel(self):
        with tempfile.TemporaryDirectory() as w:
            def schreiben(pfad, inhalt):
                os.makedirs(os.path.dirname(os.path.join(w, pfad)), exist_ok=True)
                with open(os.path.join(w, pfad), "w", encoding="utf-8") as datei:
                    datei.write(inhalt)
            for nummer, minor, props in ((5, 69, "E:ID_INPUT=1\nE:ID_INPUT_TOUCHPAD=1\n"),
                                         (12, 76, "E:ID_INPUT=1\nE:ID_INPUT_KEY=1\nE:ID_INPUT_KEYBOARD=1\n")):
                schreiben(f"sys/class/input/event{nummer}/dev", f"13:{minor}\n")
                schreiben(f"sys/class/input/event{nummer}/device/capabilities/key", TOUCHPAD_TASTEN + "\n")
                schreiben(f"run/udev/data/c13:{minor}", "S:input/by-path/x\n" + props)
                schreiben(f"dev/input/event{nummer}", "")
                os.chmod(os.path.join(w, f"dev/input/event{nummer}"), 0o640 if nummer == 5 else 0o660)
            os.makedirs(os.path.join(w, "sys/class/input/input3"))
            geraete = G.scan_devices(w)
            self.assertEqual([g["name"] for g in geraete], ["event5", "event12"])
            self.assertEqual(geraete[0]["props"]["ID_INPUT_TOUCHPAD"], "1")
            self.assertEqual(geraete[0]["mode"], 0o640)
            self.assertTrue(geraete[0]["keys"] >> G.BTN_TOOL_TRIPLETAP & 1)
            b = G.evaluate(geraete, os.getegid(), None, set())
            self.assertIn(("ok", "Touchpad event5: nur für zenos-gesten lesbar (0640)"), b)
            self.assertEqual(b[2][0], "fehler", "Tastatur mit der Gruppe des Dienstes")
            # als Programm, wie zen doctor es aufruft: je Zeile «art<TAB>text»
            aus = subprocess.run([sys.executable, "-I", PROGRAMM, "--pruefen"], capture_output=True, text=True,
                                 env={**os.environ, G.TEST_ROOT_VARIABLE: w}, check=True).stdout
            zeilen = [z.split("\t", 1) for z in aus.splitlines()]
            self.assertTrue(all(len(z) == 2 and z[0] in ("ok", "hinweis", "warnung", "fehler") for z in zeilen), aus)
            self.assertIn("Touchpad event5", aus)
        self.assertEqual(G.scan_devices("/gibt/es/nicht"), [])


# --- Einheit, Regel, sysusers -----------------------------------------------------


def einheit_lesen():
    abschnitt, werte = None, {}
    for zeile in ohne_kommentare(lesen(EINHEIT)):
        if zeile.startswith("["):
            abschnitt = zeile.strip("[]")
            werte.setdefault(abschnitt, {})
            continue
        schluessel, _, wert = zeile.partition("=")
        werte[abschnitt].setdefault(schluessel, []).append(wert)
    return werte


class EinheitTest(unittest.TestCase):
    def setUp(self):
        self.e = einheit_lesen()
        self.s = self.e["Service"]

    def eins(self, schluessel):
        self.assertEqual(len(self.s.get(schluessel, [])), 1, schluessel)
        return self.s[schluessel][0]

    def test_benutzer_ohne_rechte(self):
        self.assertEqual(self.eins("User"), "zenos-gesten")
        self.assertEqual(self.eins("Group"), "zenos-gesten")
        for verboten in ("SupplementaryGroups", "DynamicUser", "PermissionsStartOnly"):
            self.assertNotIn(verboten, self.s)
        self.assertEqual(self.eins("CapabilityBoundingSet"), "")
        self.assertEqual(self.eins("AmbientCapabilities"), "")
        self.assertEqual(self.eins("NoNewPrivileges"), "yes")

    def test_geraete_nur_eingabe_nur_lesen(self):
        self.assertEqual(self.eins("DevicePolicy"), "closed")
        self.assertEqual(self.s["DeviceAllow"], ["char-input r"])

    def test_kein_netz(self):
        self.assertEqual(self.eins("RestrictAddressFamilies").split(), ["AF_UNIX", "AF_NETLINK"])
        self.assertEqual(self.eins("IPAddressDeny"), "any")
        # Kein PrivateNetwork: udev meldet neue Geräte nur im Netz-Namensraum des Systems (Touchpad nach dem Aufwachen)
        self.assertNotEqual(self.s.get("PrivateNetwork", ["no"]), ["yes"])
        self.assertIn("Kein PrivateNetwork", lesen(EINHEIT))

    def test_haertung(self):
        for schluessel, wert in (("ProtectSystem", "strict"), ("ProtectHome", "yes"), ("PrivateTmp", "yes"),
                                 ("MemoryDenyWriteExecute", "yes"), ("LockPersonality", "yes"),
                                 ("RestrictNamespaces", "yes"), ("RestrictSUIDSGID", "yes"), ("ProtectClock", "yes"),
                                 ("ProtectKernelTunables", "yes"), ("ProtectKernelModules", "yes"),
                                 ("ProtectControlGroups", "yes"), ("SystemCallArchitectures", "native"),
                                 ("UMask", "0077")):
            self.assertEqual(self.eins(schluessel), wert, schluessel)
        self.assertEqual(self.s["SystemCallFilter"], ["@system-service", "~@privileged @resources"])
        # identity, nicht yes: Mit yes sähe SO_PEERCRED jeden anderen Benutzer als nobody
        self.assertEqual(self.eins("PrivateUsers"), "identity")
        self.assertEqual(self.eins("InaccessiblePaths").split(), ["-/dev/shm", "-/var/log"])

    def test_start_und_ordner(self):
        self.assertEqual(self.eins("ExecStart"), "/usr/bin/python3 -I /opt/zenos/scripts/bin/zenos-gesten")
        self.assertEqual(self.eins("Type"), "notify")
        self.assertEqual(self.eins("RuntimeDirectory"), os.path.basename(os.path.dirname(G.SOCKET_PATH)))
        self.assertEqual(self.eins("RuntimeDirectoryMode"), "0755")
        self.assertEqual(os.path.dirname(G.SOCKET_PATH), "/run/zenos-gesten")
        self.assertEqual(self.e["Unit"]["ConditionPathExists"], ["/opt/zenos/scripts/bin/zenos-gesten"])

    def test_nur_udev_startet_ihn(self):
        self.assertNotIn("Install", self.e, "kein [Install]: Ohne Touchpad läuft der Dienst nie")


def regel_anwenden(eigenschaften):
    """Die udev-Regel für ein Gerät durchspielen (nur die Formen, die 72-zenos-gesten.rules nutzt). Gibt die
    Zuweisungen zurück oder None, wenn sie nichts zuweist."""
    zeilen = ohne_kommentare(lesen(REGEL))
    i = 0
    while i < len(zeilen):
        teile = [t.strip() for t in zeilen[i].split(",")]
        if teile[0].startswith("LABEL="):
            i += 1
            continue
        bedingungen = [t for t in teile if re.match(r'^[A-Z]+(\{[A-Z_]+\})?(==|!=)"', t)]
        zuweisungen = [t for t in teile if t not in bedingungen]
        passt = True
        for b in bedingungen:
            m = re.match(r'^([A-Z]+)(?:\{([A-Z_]+)\})?(==|!=)"(.*)"$', b)
            art, name, op, muster = m.groups()
            wert = eigenschaften.get(name if art == "ENV" else art, "")
            treffer = fnmatch.fnmatchcase(wert, muster) if muster != "?*" else wert != ""
            passt = passt and (treffer if op == "==" else not treffer)
        if not passt:
            i += 1
            continue
        ziel = [z for z in zuweisungen if z.startswith("GOTO=")]
        if ziel:
            label = "LABEL=" + ziel[0].split("=", 1)[1]
            i = next(j for j, z in enumerate(zeilen) if z.startswith(label))
            continue
        return zuweisungen
    return None


class RegelTest(unittest.TestCase):
    TOUCHPAD = {"ACTION": "add", "SUBSYSTEM": "input", "KERNEL": "event5", "ID_INPUT": "1", "ID_INPUT_TOUCHPAD": "1"}

    def test_reines_touchpad(self):
        for aktion in ("add", "change", "bind"):
            self.assertEqual(regel_anwenden({**self.TOUCHPAD, "ACTION": aktion}),
                             ['GROUP="zenos-gesten"', 'MODE="0640"', 'TAG+="systemd"',
                              'ENV{SYSTEMD_WANTS}+="zenos-gesten.service"'])

    def test_alles_andere_bleibt(self):
        faelle = {
            "Tastatur": {"ACTION": "add", "SUBSYSTEM": "input", "KERNEL": "event2", "ID_INPUT_KEY": "1",
                         "ID_INPUT_KEYBOARD": "1"},
            "Touchpad mit Tasten": {**self.TOUCHPAD, "ID_INPUT_KEY": "1"},
            "Touchpad als Tastatur": {**self.TOUCHPAD, "ID_INPUT_KEYBOARD": "1"},
            "Maus": {"ACTION": "add", "SUBSYSTEM": "input", "KERNEL": "event3", "ID_INPUT_MOUSE": "1"},
            "Entfernen": {**self.TOUCHPAD, "ACTION": "remove"},
            "Elternknoten": {**self.TOUCHPAD, "KERNEL": "input12"},
            "mouse-Knoten": {**self.TOUCHPAD, "KERNEL": "mouse1"},
            "anderes Subsystem": {**self.TOUCHPAD, "SUBSYSTEM": "hidraw"},
            "Touchpad 0": {**self.TOUCHPAD, "ID_INPUT_TOUCHPAD": "0"},
        }
        for name, geraet in faelle.items():
            self.assertIsNone(regel_anwenden(geraet), name)

    def test_nie_weiter_als_lesen(self):
        text = "\n".join(ohne_kommentare(lesen(REGEL)))
        for verboten in ("uaccess", "seat", "OWNER=", "RUN", "PROGRAM", "IMPORT", "ACL", "0660", "0666", "0644",
                         'GROUP="input"'):
            self.assertNotIn(verboten, text, verboten)
        self.assertEqual(text.count("MODE="), 1)
        self.assertEqual(text.count("GROUP="), 1)


class SysusersTest(unittest.TestCase):
    def test_gesperrter_benutzer_ohne_gruppen(self):
        zeilen = ohne_kommentare(lesen(SYSUSERS))
        self.assertEqual(len(zeilen), 1)
        teile = re.findall(r'"[^"]*"|\S+', zeilen[0])
        self.assertEqual(teile[:3], ["u!", "zenos-gesten", "-"])
        self.assertEqual(teile[4:], ["-", "-"], "Home und Shell nach Vorgabe (/, nologin)")


class GruppeInputTest(unittest.TestCase):
    """Niemand kommt in die Gruppe input oder zenos-gesten: Wer die Tastatur lesen darf, liest Passwörter mit."""

    MUSTER = [
        r"usermod\b[^\n]*-[a-zA-Z]*G[^\n]*\b(input|zenos-gesten)\b",
        r"gpasswd\b[^\n]*-a\b[^\n]*\b(input|zenos-gesten)\b",
        r"adduser\s+\S+\s+(input|zenos-gesten)\b",
        r"^\s*m!?\s+\S+\s+(input|zenos-gesten)\b",
        r"SupplementaryGroups\s*=[^\n]*\b(input|zenos-gesten)\b",
        r"^\s*Group\s*=\s*input\b",
        r'GROUP\s*=\s*"input"',
        r"setfacl\b[^\n]*/dev/input",
    ]

    def test_nirgends(self):
        befunde = []
        for ordner in ("scripts", "system", "image", "config", "shell"):
            for wurzel, _, dateien in os.walk(os.path.join(WURZEL, ordner)):
                for name in dateien:
                    pfad = os.path.join(wurzel, name)
                    try:
                        text = lesen(pfad)
                    except (UnicodeDecodeError, OSError):
                        continue
                    for muster in self.MUSTER:
                        for treffer in re.finditer(muster, text, re.M):
                            zeile = text[:treffer.start()].count("\n") + 1
                            befunde.append(f"{os.path.relpath(pfad, WURZEL)}:{zeile}: {treffer.group(0)}")
        self.assertEqual(befunde, [])


# --- Modul 82-gesten und zen doctor --------------------------------------------------


ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, sys
WER = %r
ORDNER = os.environ["MODUL_TEST"]
argv = sys.argv[1:]
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps([WER] + argv) + "\n")
def datei(name):
    try:
        with open(os.path.join(ORDNER, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
if WER == "getent":
    eintrag = datei("getent." + argv[0] + "." + argv[1])
    if eintrag is None:
        sys.exit(2)
    print(eintrag, end="")
    sys.exit(0)
if WER == "systemctl" and argv[:2] == ["--quiet", "is-active"]:
    sys.exit(0 if datei("aktiv") is not None else 3)
if WER == "systemctl" and argv[:1] == ["is-active"]:
    zustand = datei("zustand") or ("active" if datei("aktiv") is not None else "inactive")
    print(zustand)
    sys.exit(0 if zustand == "active" else 3)
if WER == "pgrep":
    sys.exit(0 if datei("prozesse") is not None else 1)
if WER == "pkill":
    if argv[0] == "-" + (datei("prozesse") or "TERM").strip():
        os.unlink(os.path.join(ORDNER, "prozesse"))
    sys.exit(0)
if WER in ("userdel", "groupdel") and datei(WER + ".fehler") is not None:
    print(WER + ": user zenos-gesten is currently used by process 4242", file=sys.stderr)
    sys.exit(8)
if WER == "udevadm" and argv[:2] == ["control", "--ping"]:
    sys.exit(0 if datei("udev") is not None else 1)
if WER == "find":
    sys.stdout.write(datei("find.aus") or "")
sys.exit(0)
'''

MODUL_TEIL = r"""
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
_Z=0
aenderung() { _Z=$((_Z + 1)); printf 'aenderung: %s\n' "$*"; }
zenos_anzahl() { printf '%s' "$_Z"; }
modul_geaendert() { (( _Z > 0 )); }
befehl_vorhanden() { command -v -- "$1" > /dev/null 2>&1; }
systemd_neu_laden() { printf 'neu laden\n'; }
datei_installieren() { printf 'installieren: %s\n' "$2"; [[ -e "$MODUL_TEST/da.${2//\//_}" ]] || aenderung "$2"; }
datei_entfernen() {
  if [[ -e "$MODUL_TEST/da.${1//\//_}" ]]; then rm -f "$MODUL_TEST/da.${1//\//_}"; aenderung "entfernt: $1"; fi
}
source "$1"
_GESTEN_AUS=$MODUL_TEST/gesten-aus
shift
# Wie install.sh: Ein Fehler bricht ab
if [[ -n "${STRENG:-}" ]]; then set -Eeuo pipefail; trap 'echo "ABBRUCH $?" >&2' ERR; fi
"$@"
"""


@unittest.skipUnless(LINUX, "nur unter Linux (bash 4+)")
class ModulTest(unittest.TestCase):
    def setUp(self):
        self.w = tempfile.mkdtemp(prefix="zenos-gesten-modul.")
        self.fake = os.path.join(self.w, "fake")
        os.makedirs(self.fake)
        for name in ("getent", "systemctl", "udevadm", "userdel", "groupdel", "systemd-sysusers", "stat", "find",
                     "chgrp", "chmod", "pgrep", "pkill", "sleep"):
            pfad = os.path.join(self.fake, name)
            with open(pfad, "w", encoding="utf-8") as datei:
                datei.write(ATTRAPPE % name)
            os.chmod(pfad, 0o755)
        self.umgebung = {"PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
                         "MODUL_TEST": self.w, "LANG": "C.UTF-8", "SUDO": "", "ZENOS_CODE": WURZEL,
                         "ZENOS_SYSTEMD": "1", "ZENOS_IMAGE": "0"}

    def tearDown(self):
        shutil.rmtree(self.w, ignore_errors=True)

    def setzen(self, name, inhalt=""):
        with open(os.path.join(self.w, name), "w", encoding="utf-8") as datei:
            datei.write(inhalt)

    def da(self, ziel):
        self.setzen("da." + ziel.replace("/", "_"))

    def lauf(self, *befehl, **umgebung):
        ergebnis = subprocess.run(["bash", "-c", MODUL_TEIL, "modul", MODUL, *befehl], capture_output=True,
                                  text=True, env={**self.umgebung, **umgebung}, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        try:
            with open(os.path.join(self.w, "ereignisse"), encoding="utf-8") as datei:
                ereignisse = [json.loads(z) for z in datei]
        except OSError:
            ereignisse = []
        return ergebnis.stdout, ereignisse

    def test_rueckweg_in_der_richtigen_reihenfolge(self):
        for ziel in ("/etc/udev/rules.d/72-zenos-gesten.rules", "/etc/systemd/system/zenos-gesten.service",
                     "/etc/sysusers.d/zenos-gesten.conf"):
            self.da(ziel)
        self.setzen("aktiv")
        self.setzen("udev")
        self.setzen("getent.passwd.zenos-gesten", "zenos-gesten:x:985:985::/:/usr/sbin/nologin\n")
        self.setzen("getent.group.zenos-gesten", "zenos-gesten:x:985:\n")
        self.setzen("gesten-aus")
        self.setzen("find.aus", "/dev/input/event5\0")
        aus, ereignisse = self.lauf("modul_system")
        befehle = [" ".join(e) for e in ereignisse if e[0] != "getent" and e[1:3] != ["--quiet", "is-active"]]
        # Kein «udevadm trigger --action=add»: ein zweites «add» sähe labwc womöglich als weiteres Gerät
        self.assertEqual(befehle, [
            "systemctl is-active zenos-gesten.service",
            "systemctl stop zenos-gesten.service",
            "pgrep -u zenos-gesten",
            "udevadm control --ping",
            "udevadm control --reload",
            "find /dev/input -maxdepth 1 -name event* -group zenos-gesten -print0",
            "chgrp input -- /dev/input/event5",
            "chmod 0660 -- /dev/input/event5",
            "systemctl reset-failed zenos-gesten.service",
            "userdel zenos-gesten",
            "groupdel zenos-gesten",
        ])
        self.assertIn("aenderung: /dev/input/event5 wieder root:input 0660", aus)
        self.assertIn("aenderung: entfernt: /etc/udev/rules.d/72-zenos-gesten.rules", aus)
        self.assertIn("aenderung: entfernt: /etc/sysusers.d/zenos-gesten.conf", aus)
        self.assertIn("aenderung: Benutzer zenos-gesten gelöscht", aus)

    def rueckweg_vorbereiten(self):
        self.setzen("getent.passwd.zenos-gesten", "zenos-gesten:x:985:985::/:/usr/sbin/nologin\n")
        self.setzen("getent.group.zenos-gesten", "zenos-gesten:x:985:\n")
        self.setzen("gesten-aus")

    def test_rueckweg_beendet_den_messmodus(self):
        # Befund: Lief noch ein Prozess als zenos-gesten (Messmodus), scheiterte userdel, und install.sh brach ab
        self.rueckweg_vorbereiten()
        self.setzen("prozesse", "KILL")  # reagiert erst auf SIGKILL
        aus, ereignisse = self.lauf("modul_system", STRENG="1")
        befehle = [" ".join(e) for e in ereignisse if e[0] in ("pgrep", "pkill", "userdel")]
        self.assertEqual(befehle[:2], ["pgrep -u zenos-gesten", "pkill -TERM -u zenos-gesten"])
        self.assertIn("pkill -KILL -u zenos-gesten", befehle)
        self.assertEqual(befehle[-1], "userdel zenos-gesten")
        self.assertLess(befehle.index("pkill -KILL -u zenos-gesten"), befehle.index("userdel zenos-gesten"))
        self.assertIn("aenderung: Prozesse von zenos-gesten beendet", aus)
        self.assertIn("aenderung: Benutzer zenos-gesten gelöscht", aus)

    def test_rueckweg_stoppt_auch_im_neustart(self):
        # auto-restart: is-active meldet «activating», nicht «active»
        self.rueckweg_vorbereiten()
        self.setzen("zustand", "activating")
        aus, ereignisse = self.lauf("modul_system", STRENG="1")
        self.assertIn(["systemctl", "stop", "zenos-gesten.service"], ereignisse)
        self.assertIn("aenderung: Dienst gestoppt: zenos-gesten.service", aus)
        for zustand in ("inactive", "failed"):
            self.setzen("zustand", zustand)
            os.unlink(os.path.join(self.w, "ereignisse"))
            _, ereignisse = self.lauf("modul_system", STRENG="1")
            self.assertNotIn(["systemctl", "stop", "zenos-gesten.service"], ereignisse, zustand)

    def test_rueckweg_bricht_nicht_ab_wenn_userdel_scheitert(self):
        self.rueckweg_vorbereiten()
        self.setzen("userdel.fehler")
        self.setzen("groupdel.fehler")
        ergebnis = subprocess.run(["bash", "-c", MODUL_TEIL, "modul", MODUL, "modul_system"], capture_output=True,
                                  text=True, env={**self.umgebung, "STRENG": "1"}, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        self.assertNotIn("ABBRUCH", ergebnis.stderr)
        self.assertIn("warnung: Benutzer zenos-gesten liess sich nicht löschen", ergebnis.stdout)
        self.assertIn("warnung: Gruppe zenos-gesten liess sich nicht löschen", ergebnis.stdout)
        self.assertNotIn("gelöscht", ergebnis.stdout)

    def test_rueckweg_nicht_im_image(self):
        self.rueckweg_vorbereiten()
        self.setzen("prozesse")
        _, ereignisse = self.lauf("modul_system", ZENOS_IMAGE="1", ZENOS_SYSTEMD="0", STRENG="1")
        self.assertFalse([e for e in ereignisse if e[0] in ("pgrep", "pkill", "systemctl")])

    def test_rueckweg_zweiter_lauf_ohne_aenderung(self):
        self.setzen("gesten-aus")
        aus, ereignisse = self.lauf("modul_system")
        self.assertNotIn("aenderung:", aus)
        self.assertFalse([e for e in ereignisse if e[0] in ("userdel", "groupdel", "udevadm")])

    def test_image_nur_dateien_und_benutzer(self):
        aus, ereignisse = self.lauf("modul_system", ZENOS_IMAGE="1", ZENOS_SYSTEMD="0")
        befehle = [e for e in ereignisse if e[0] != "getent"]
        self.assertEqual(befehle, [["systemd-sysusers", "/etc/sysusers.d/zenos-gesten.conf"]])
        for ziel in ("/etc/sysusers.d/zenos-gesten.conf", "/etc/systemd/system/zenos-gesten.service",
                     "/etc/udev/rules.d/72-zenos-gesten.rules"):
            self.assertIn(f"installieren: {ziel}", aus)

    def test_ohne_udev_und_ohne_touchpad_startet_nichts(self):
        self.setzen("getent.passwd.zenos-gesten", "zenos-gesten:x:985:985::/:/usr/sbin/nologin\n")
        self.setzen("getent.group.zenos-gesten", "zenos-gesten:x:985:\n")
        for ziel in ("/etc/udev/rules.d/72-zenos-gesten.rules", "/etc/systemd/system/zenos-gesten.service",
                     "/etc/sysusers.d/zenos-gesten.conf"):
            self.da(ziel)
        aus, ereignisse = self.lauf("modul_system")
        self.assertNotIn("aenderung:", aus)
        self.assertFalse([e for e in ereignisse if e[0] in ("systemd-sysusers", "userdel")])
        self.assertFalse([e for e in ereignisse if e[0] == "systemctl" and e[1] in ("start", "restart")])

    def test_mitglieder_der_gruppe_warnen(self):
        self.setzen("getent.passwd.zenos-gesten", "zenos-gesten:x:985:985::/:/usr/sbin/nologin\n")
        self.setzen("getent.group.zenos-gesten", "zenos-gesten:x:985:jemand\n")
        aus, _ = self.lauf("_gesten_benutzer")
        self.assertIn("warnung: Die Gruppe zenos-gesten hat Mitglieder", aus)
        self.assertNotIn("jemand", aus)

    def test_nur_erlaubte_funktionen(self):
        namen = re.findall(r"(?m)^([A-Za-z_][A-Za-z0-9_]*)\(\)", lesen(MODUL))
        self.assertTrue(namen)
        self.assertEqual([n for n in namen if n != "modul_system" and not n.startswith("_gesten_")], [])
        self.assertIn('_GESTEN_AUS=/etc/xdg/zenos/gesten-aus', lesen(MODUL))
        self.assertIn('_gesten_aus=/etc/xdg/zenos/gesten-aus', lesen(DOCTOR))


DOCTOR_TEIL = r"""
abschnitt() { :; }
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$1"
_gesten_code=$2
"$3"
"""


@unittest.skipUnless(LINUX, "nur unter Linux (bash 4+)")
class DoctorTest(unittest.TestCase):
    def lauf(self, ausgabe, funktion="_gesten_geraete"):
        with tempfile.TemporaryDirectory() as code:
            os.makedirs(os.path.join(code, "scripts", "bin"))
            programm = os.path.join(code, "scripts", "bin", "zenos-gesten")
            with open(programm, "w", encoding="utf-8") as datei:
                datei.write(f"import sys\nsys.stdout.write({ausgabe!r})\n")
            return subprocess.run(["bash", "-c", DOCTOR_TEIL, "doctor", DOCTOR, code, funktion], capture_output=True,
                                  text=True, check=True).stdout

    def test_zeilen_werden_befunde(self):
        aus = self.lauf("ok\tTouchpad event5: gut\nfehler\tevent2 hat Tasten\nhinweis\tx\nwarnung\ty\nunsinn\tz\n")
        self.assertEqual(aus.splitlines(), ["ok: Touchpad event5: gut", "fehler: event2 hat Tasten", "hinweis: x",
                                            "warnung: y", "warnung: zenos-gesten --pruefen: unerwartete Zeile"])

    def test_ohne_ausgabe(self):
        self.assertTrue(self.lauf("").startswith("fehler: zenos-gesten --pruefen gibt nichts aus"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
