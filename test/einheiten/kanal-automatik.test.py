#!/usr/bin/env python3
"""Einheitentests für die Automatik von scripts/bin/zenos-kanal: Zeitpunkt (sperre, fenster, jederzeit, hand), Uhr
(«erstmals» nur synchronisiert, Wartezeit seit dem Start), «automatik lauf» und «gelegenheit», Notschalter,
Rückstellung nach «zen rollback», Bestätigung nach dem Start und der Weg zurück, dazu Units und Modul.

Baut auf test/einheiten/kanal-installieren.test.py auf (Server, Gerät, Wegwerf-Schlüssel, install.sh als Attrappe, die
Units laufen im Prozess). Sitzungen, Sperre, Uhr und Neustarts sind gestellt: Funktionen des Moduls ersetzt, dazu
Attrappen für loginctl, systemctl, setpriv und zenos-ipc. Ohne Root, ohne Netz. Den echten Ablauf mit systemd, Timern,
einer gestellten Sitzung auf seat0 und echter Sperre prüft test/container/kanal-e2e.sh (Schritt automatik).

  python3 test/einheiten/kanal-automatik.test.py
"""

import contextlib
import datetime
import importlib.machinery
import importlib.util
import io
import json
import os
import pwd
import re
import shutil
import sys
import tempfile
import threading
import time
import unittest

sys.dont_write_bytecode = True

_HIER = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("kanal_installieren", os.path.join(_HIER, "kanal-installieren.test.py"))
_spec = importlib.util.spec_from_loader("kanal_installieren", _loader)
I = importlib.util.module_from_spec(_spec)
_loader.exec_module(I)
B = I.B
K = I.K
WURZEL = I.WURZEL

UNITS = os.path.join(WURZEL, "system", "systemd", "system")
MODUL = os.path.join(WURZEL, "scripts", "module", "14-kanal.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "15-kanal.sh")
ZEN_KANAL = os.path.join(WURZEL, "scripts", "zen.d", "kanal.sh")

SETPRIV_ATTRAPPE = """#!/bin/sh
# Attrappe für setpriv (Test): Optionen bis «--» überspringen, dann den Befehl ausführen (ohne Wechsel des Benutzers)
printf '%s\\n' "$*" >> "$XDG_RUNTIME_DIR/setpriv-aufrufe"
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done
shift
exec "$@"
"""

IPC_ATTRAPPE = """#!/bin/sh
# Attrappe für zenos-ipc (Test): «sperre status» antwortet aus $XDG_RUNTIME_DIR/ipc-antwort, sonst keine Oberfläche
if [ "$1 $2" = "sperre status" ] && [ -f "$XDG_RUNTIME_DIR/ipc-antwort" ]; then
  printf 'qt.qpa: Hinweis von Quickshell\\n'
  cat "$XDG_RUNTIME_DIR/ipc-antwort"
  exit 0
fi
echo "zenos-ipc: keine laufende Oberfläche" >&2
exit 2
"""

# loginctl, systemctl, timedatectl: Ausgabe und Exit aus Dateien im Ordner ORDNER (<wer>.<unterbefehl>[.<arg>].aus
# bzw. .exit); zenos-kanal startet sie mit leerer Umgebung, der Ordner steht deshalb fest im Skript
BEFEHL_ATTRAPPE = """#!/bin/sh
wer=$(basename "$0")
ordner=ORDNER
printf '%s\\n' "$*" >> "$ordner/$wer.aufrufe"
unter=""
for a in "$@"; do case "$a" in -*) ;; *) if [ -z "$unter" ]; then unter=$a; else arg=$a; break; fi ;; esac; done
for name in "$wer.$unter.$arg" "$wer.$unter"; do
  if [ -f "$ordner/$name.aus" ] || [ -f "$ordner/$name.exit" ]; then
    [ -f "$ordner/$name.aus" ] && cat "$ordner/$name.aus"
    [ -f "$ordner/$name.exit" ] && exit "$(cat "$ordner/$name.exit")"
    exit 0
  fi
done
exit 0
"""


def setUpModule():
    I.setUpModule()


def tearDownModule():
    I.tearDownModule()


def lesen(pfad):
    with open(pfad, encoding="utf-8") as f:
        return f.read()


def schreiben(pfad, text, modus=0o644):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(pfad, modus)


class Fenster(unittest.TestCase):
    def test_im_fenster_auch_ueber_mitternacht(self):
        nacht = {"art": "fenster", "von": "22:00", "bis": "04:00"}
        frueh = {"art": "fenster", "von": "02:00", "bis": "05:00"}
        faelle = [(nacht, "23:30", True), (nacht, "22:00", True), (nacht, "00:00", True), (nacht, "03:59", True),
                  (nacht, "04:00", False), (nacht, "21:59", False), (nacht, "12:00", False),
                  (frueh, "02:00", True), (frueh, "04:59", True), (frueh, "05:00", False), (frueh, "01:59", False),
                  (frueh, "23:00", False)]
        for zeitpunkt, uhr, erwartet in faelle:
            with self.subTest(fenster=f"{zeitpunkt['von']}–{zeitpunkt['bis']}", uhr=uhr):
                stunde, minute = (int(x) for x in uhr.split(":"))
                moment = datetime.datetime(2026, 10, 5, stunde, minute)
                self.assertIs(K.in_window(zeitpunkt, moment), erwartet)
        self.assertFalse(K.in_window({"art": "fenster", "von": "2:00", "bis": "05:00"}, datetime.datetime(2026, 1, 1,
                                                                                                         3, 0)))


class Ruhe(unittest.TestCase):
    """quiet_now und die Sperre: Sitzungen, Marker, Bestätigung der Oberfläche, mit Attrappen statt logind."""

    def setUp(self):
        self.ordner = os.path.realpath(tempfile.mkdtemp(prefix="zenos-kanal-ruhe."))
        self.addCleanup(shutil.rmtree, self.ordner, True)
        self.uid = os.getuid()
        self.name = pwd.getpwuid(self.uid).pw_name
        code = os.path.join(self.ordner, "opt-zenos")
        schreiben(os.path.join(code, "scripts", "bin", "zenos-ipc"), IPC_ATTRAPPE, 0o755)
        setpriv = os.path.join(self.ordner, "bin", "setpriv")
        schreiben(setpriv, SETPRIV_ATTRAPPE, 0o755)
        self.attrappen = os.path.join(self.ordner, "attrappen")
        os.makedirs(self.attrappen)
        for wer in ("loginctl", "systemctl", "timedatectl"):
            schreiben(os.path.join(self.ordner, "bin", wer), BEFEHL_ATTRAPPE.replace("ORDNER", f"'{self.attrappen}'"),
                      0o755)
        os.makedirs(os.path.join(self.ordner, "run-systemd"))
        self.laufzeit = os.path.join(self.ordner, "run-user", str(self.uid))
        os.makedirs(os.path.join(self.laufzeit, "zenos"))
        self.proc = os.path.join(self.ordner, "proc")
        schreiben(os.path.join(self.proc, "uptime"), "1000.00 1.00\n")
        werte = {"CODE_DIR": code, "SETPRIV": setpriv, "RUN_USER": os.path.join(self.ordner, "run-user"),
                 "LOGINCTL": os.path.join(self.ordner, "bin", "loginctl"),
                 "SYSTEMCTL": os.path.join(self.ordner, "bin", "systemctl"),
                 "TIMEDATECTL": os.path.join(self.ordner, "bin", "timedatectl"),
                 "SYSTEMD_RUN_DIR": os.path.join(self.ordner, "run-systemd"), "PROC": self.proc,
                 "TIMESYNC_FLAG": os.path.join(self.ordner, "timesync-synchronized"),
                 "POWER_STATUS": os.path.join(self.ordner, "geraet.json"),
                 "POWER_SUPPLY_DIR": os.path.join(self.ordner, "power_supply")}
        for name, wert in werte.items():
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)

    def verhalten(self, name, aus=None, code=None):
        if aus is not None:
            schreiben(os.path.join(self.attrappen, name + ".aus"), aus)
        if code is not None:
            schreiben(os.path.join(self.attrappen, name + ".exit"), str(code))

    def sitzungen(self, liste, zustaende=None):
        """Sitzungen für loginctl. zustaende: id → State (dann Type wayland, nicht fern) oder die ganze Ausgabe von
        show-session («State=…\\nType=…»)."""
        self.verhalten("loginctl.list-sessions", json.dumps(liste))
        for sid, zustand in (zustaende or {}).items():
            text = zustand if "=" in zustand else f"State={zustand}\nType=wayland\nRemote=no\n"
            self.verhalten(f"loginctl.show-session.{sid}", text + ("" if text.endswith("\n") else "\n"))

    def gesperrt(self, alter_minuten=10, antwort="gesperrt"):
        marker = os.path.join(self.laufzeit, "zenos", "gesperrt")
        schreiben(marker, "")
        zeit = time.time() - alter_minuten * 60
        os.utime(marker, (zeit, zeit))
        if antwort is None:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(os.path.join(self.laufzeit, "ipc-antwort"))
        else:
            schreiben(os.path.join(self.laufzeit, "ipc-antwort"), antwort + "\n")

    def sitzung(self, **mehr):
        return {"session": "c1", "uid": self.uid, "user": self.name, "seat": "seat0", "leader": 1, "class": "user",
                "tty": None, "idle": False, "since": None, **mehr}

    def test_sitzungen_nur_menschen_auf_seat0(self):
        self.sitzungen([self.sitzung(), self.sitzung(session="c2", **{"class": "greeter"}),
                        self.sitzung(session="5", seat=None),
                        self.sitzung(session="c3", **{"class": "background"}),
                        self.sitzung(session="c4", **{"class": "user-early"}),
                        self.sitzung(session="c5"), self.sitzung(session="c6", **{"class": "manager"})],
                       {"c1": "active", "c4": "online", "c5": "closing"})
        self.assertEqual(K.seat_sessions(), [("c1", self.uid, self.name, "wayland"),
                                             ("c4", self.uid, self.name, "wayland")])

    def test_sitzungen_nicht_pruefbar(self):
        self.verhalten("loginctl.list-sessions", "kein json\n")
        self.assertIsNone(K.seat_sessions())
        self.verhalten("loginctl.list-sessions", "[]", code=1)
        self.assertIsNone(K.seat_sessions())
        self.verhalten("loginctl.list-sessions", json.dumps([self.sitzung(user="$(x)")]), code=0)
        self.assertIsNone(K.seat_sessions(), "ein seltsamer Name heisst: nicht prüfbar")
        self.assertEqual(K.quiet_now({"art": "sperre"})[0], False)

    def test_ohne_sitzung_erst_nach_fuenf_minuten_login_bildschirm(self):
        """Ohne Sitzung auf seat0 ist es erst ruhig, wenn der Login-Bildschirm seit 5 Min. läuft (ein beim Start
        nachgeholter Lauf träfe sonst jemanden, der gerade das Passwort tippt)."""
        self.sitzungen([self.sitzung(session="c2", **{"class": "greeter"})])
        self.addCleanup(setattr, K, "greeter_age", K.greeter_age)
        alter = [None]
        K.greeter_age = lambda: alter[0]
        self.verhalten("systemctl.is-enabled", "enabled\n")
        ruhig, grund = K.quiet_now({"art": "sperre"})
        self.assertFalse(ruhig)
        self.assertIn("Login-Bildschirm läuft nicht", grund)
        alter[0] = 60.0
        ruhig, grund = K.quiet_now({"art": "sperre"})
        self.assertFalse(ruhig)
        self.assertIn("erst seit Kurzem", grund)
        alter[0] = 400.0
        self.assertEqual(K.quiet_now({"art": "sperre"}), (True, "niemand angemeldet (Login-Bildschirm seit 6 Min.)"))
        # Ohne greetd (kein Login-Bildschirm): 5 Min. nach dem Start
        alter[0] = None
        self.verhalten("systemctl.is-enabled", "disabled\n", code=1)
        self.assertEqual(K.quiet_now({"art": "sperre"}), (True, "niemand angemeldet"))
        schreiben(os.path.join(self.proc, "uptime"), "100.00 1.00\n")
        self.assertFalse(K.quiet_now({"art": "sperre"})[0])

    def test_ohne_systemd_ruhig(self):
        self.addCleanup(setattr, K, "SYSTEMD_RUN_DIR", K.SYSTEMD_RUN_DIR)
        K.SYSTEMD_RUN_DIR = os.path.join(self.ordner, "gibt-es-nicht")
        self.assertEqual(K.quiet_now({"art": "sperre"}), (True, "niemand angemeldet"))

    def test_ssh_sitzung_nie_ruhig(self):
        """Wer per SSH angemeldet ist (logind Remote), arbeitet: «bei Sperre» ist dann nicht ruhig, auch nicht am
        Login-Bildschirm."""
        self.addCleanup(setattr, K, "greeter_age", K.greeter_age)
        K.greeter_age = lambda: 900.0
        fern = self.sitzung(session="7", seat=None, tty="pts/0")
        self.sitzungen([fern], {"7": "State=active\nType=tty\nRemote=yes\n"})
        self.assertEqual(K.quiet_now({"art": "sperre"}), (False, f"{self.name} ist per SSH angemeldet"))
        self.sitzungen([self.sitzung(), fern], {"c1": "active", "7": "State=active\nType=tty\nRemote=yes\n"})
        self.gesperrt()
        self.assertFalse(K.quiet_now({"art": "sperre"})[0])
        # Ohne die SSH-Sitzung: gesperrt heisst ruhig
        self.sitzungen([self.sitzung()], {"c1": "active"})
        self.assertEqual(K.quiet_now({"art": "sperre"}), (True, "gesperrt"))
        # «jederzeit» und «fenster» meinen ausdrücklich auch während der Arbeit
        self.sitzungen([fern], {"7": "State=active\nType=tty\nRemote=yes\n"})
        self.assertTrue(K.quiet_now({"art": "jederzeit"})[0])

    def test_textkonsole_neben_gesperrter_sitzung(self):
        """Grafische Sitzung gesperrt, dazu eine Textkonsole (Ctrl+Alt+F3) desselben Benutzers: nicht ruhig."""
        self.sitzungen([self.sitzung(), self.sitzung(session="c3", tty="tty3")],
                       {"c1": "active", "c3": "State=online\nType=tty\nRemote=no\n"})
        self.gesperrt()
        self.assertEqual(K.quiet_now({"art": "sperre"}), (False, f"{self.name} ist auf einer Textkonsole angemeldet"))

    def test_fehlende_klasse_nicht_pruefbar(self):
        """Fehlt «class» in der Liste (andere Fassung von systemd), gilt show-session; fehlt es dort auch, ist die Lage
        nicht prüfbar (nie «niemand angemeldet»)."""
        ohne = self.sitzung()
        del ohne["class"]
        self.sitzungen([ohne], {"c1": "active"})
        self.assertIsNone(K.logind_sessions())
        self.assertEqual(K.quiet_now({"art": "sperre"}), (False, "Sitzungen nicht prüfbar (loginctl)"))
        self.sitzungen([ohne], {"c1": "State=active\nType=wayland\nRemote=no\nClass=user\n"})
        self.assertEqual(K.seat_sessions(), [("c1", self.uid, self.name, "wayland")])

    def test_sperre_vor_dem_abgleich_der_uhr(self):
        """Die Sperre begann vor dem ersten Abgleich der Uhr (der Pi hat keine Uhr mit Batterie): Ihr Alter zählt erst
        ab dem Abgleich, sonst wirkte eine eben gesetzte Sperre nach einem Sprung der Uhr sofort alt."""
        self.sitzungen([self.sitzung()], {"c1": "active"})
        self.gesperrt(alter_minuten=600)
        schreiben(K.TIMESYNC_FLAG, "")
        zeit = time.time() - 60
        os.utime(K.TIMESYNC_FLAG, (zeit, zeit))
        ruhig, grund = K.quiet_now({"art": "sperre"})
        self.assertFalse(ruhig)
        self.assertIn("erst seit Kurzem", grund)
        zeit = time.time() - 20 * 60
        os.utime(K.TIMESYNC_FLAG, (zeit, zeit))
        self.assertEqual(K.quiet_now({"art": "sperre"}), (True, "gesperrt"))

    def test_sperre_braucht_marker_alter_und_oberflaeche(self):
        self.sitzungen([self.sitzung()], {"c1": "active"})
        ruhig, grund = K.quiet_now({"art": "sperre"})
        self.assertEqual((ruhig, grund), (False, f"{self.name} ist angemeldet, nicht gesperrt"))
        self.gesperrt(alter_minuten=1)
        ruhig, grund = K.quiet_now({"art": "sperre"})
        self.assertFalse(ruhig)
        self.assertIn("erst seit Kurzem gesperrt", grund)
        self.gesperrt(alter_minuten=10, antwort="offen")
        self.assertEqual(K.quiet_now({"art": "sperre"})[0], False, "die Oberfläche sagt «offen»")
        self.gesperrt(alter_minuten=10, antwort=None)
        ruhig, grund = K.quiet_now({"art": "sperre"})
        self.assertFalse(ruhig, "ohne Antwort der Oberfläche nicht")
        self.assertIn("bestätigt keine Sperre", grund)
        self.gesperrt(alter_minuten=10)
        self.assertEqual(K.quiet_now({"art": "sperre"}), (True, "gesperrt"))
        # Gefragt wird die Oberfläche als Benutzer der Sitzung, mit Argumentliste
        aufruf = lesen(os.path.join(self.laufzeit, "setpriv-aufrufe")).splitlines()[-1]
        self.assertEqual(aufruf, f"--reuid={self.uid} --regid={pwd.getpwuid(self.uid).pw_gid} --init-groups "
                                 f"--no-new-privs -- {K.CODE_DIR}/scripts/bin/zenos-ipc sperre status")

    def test_marker_als_verweis_gilt_nicht(self):
        self.sitzungen([self.sitzung()], {"c1": "active"})
        self.gesperrt()
        marker = os.path.join(self.laufzeit, "zenos", "gesperrt")
        os.unlink(marker)
        os.symlink("/etc/hostname", marker)
        self.assertEqual(K.quiet_now({"art": "sperre"}), (False, f"Sperr-Marker von {self.name} ist ungültig"))

    def test_eine_offene_von_zwei_sitzungen_reicht(self):
        self.sitzungen([self.sitzung(), self.sitzung(session="c7", uid=self.uid + 4242, user="anderer")],
                       {"c1": "active", "c7": "online"})
        self.gesperrt()
        self.assertFalse(K.quiet_now({"art": "sperre"})[0])

    def test_arten(self):
        self.assertFalse(K.quiet_now({"art": "hand"})[0])
        self.assertEqual(K.quiet_now({"art": "jederzeit"}), (True, "Zeitpunkt «jederzeit»"))
        fenster = {"art": "fenster", "von": "02:00", "bis": "05:00"}
        self.addCleanup(setattr, K, "local_now", K.local_now)
        K.local_now = lambda: datetime.datetime(2026, 10, 5, 3, 0)
        self.verhalten("timedatectl.show", "no\n")
        ruhig, grund = K.quiet_now(fenster)
        self.assertFalse(ruhig)
        self.assertIn("nicht synchronisiert", grund)
        self.verhalten("timedatectl.show", "yes\n")
        self.assertEqual(K.quiet_now(fenster), (True, "im Zeitfenster 02:00–05:00"))
        K.local_now = lambda: datetime.datetime(2026, 10, 5, 12, 0)
        ruhig, grund = K.quiet_now(fenster)
        self.assertEqual((ruhig, grund), (False, "ausserhalb des Zeitfensters 02:00–05:00 (jetzt 12:00)"))

    def test_uhr_von_timedatectl(self):
        self.verhalten("timedatectl.show", "yes\n")
        self.assertTrue(K.clock_synced())
        self.assertEqual(lesen(os.path.join(self.attrappen, "timedatectl.aufrufe")).split("\n")[0],
                         "show --property=NTPSynchronized --value")
        self.verhalten("timedatectl.show", "no\n")
        self.assertFalse(K.clock_synced())
        self.verhalten("timedatectl.show", "yes\n", code=1)
        self.assertFalse(K.clock_synced(), "nicht feststellbar heisst nein")

    def test_login_bestaetigen(self):
        self.addCleanup(setattr, K, "greeter_running", K.greeter_running)
        greeter = [False]
        K.greeter_running = lambda: greeter[0]
        self.sitzungen([])
        self.verhalten("systemctl.is-enabled", "enabled\n")
        self.verhalten("systemctl.is-active", "failed\n", code=3)
        self.assertEqual(K.login_state(True), (False, "greetd läuft nicht (failed)"))
        self.verhalten("systemctl.is-active", "active\n", code=0)
        self.assertEqual(K.login_state(True), (False, "greetd läuft, aber weder Login-Bildschirm noch Sitzung"))
        greeter[0] = True
        self.assertEqual(K.login_state(True), (True, "der Login-Bildschirm läuft"))
        greeter[0] = False
        self.sitzungen([self.sitzung()], {"c1": "active"})
        self.assertEqual(K.login_state(True), (True, "eine grafische Sitzung ist offen"))
        # Anmeldung auf der Textkonsole (Ctrl+Alt+F2), der grafische Login ist kaputt: zählt nicht
        self.sitzungen([self.sitzung(tty="tty2")], {"c1": "State=active\nType=tty\nRemote=no\n"})
        ok, grund = K.login_state(True)
        self.assertFalse(ok)
        self.assertIn("Textkonsole", grund)
        greeter[0] = True
        self.assertEqual(K.login_state(True), (True, "der Login-Bildschirm läuft"))
        greeter[0] = False
        # greetd nicht aktiviert und bei der Installation auch nicht: kein Login zu prüfen
        self.sitzungen([])
        self.verhalten("systemctl.is-enabled", "disabled\n", code=1)
        self.assertTrue(K.login_state(False)[0])
        self.assertFalse(K.login_state(True)[0], "war greetd bei der Installation an, zählt es weiter")

    def test_greeter_prozess(self):
        proc = os.path.join(self.ordner, "proc")
        schreiben(os.path.join(proc, "uptime"), "1000.00 1.00\n")
        tick = os.sysconf("SC_CLK_TCK")

        def prozess(pid, comm, seit_start):
            felder = ["S"] + ["0"] * 18 + [str(int(seit_start * tick))] + ["0"] * 5
            schreiben(os.path.join(proc, str(pid), "stat"), f"{pid} ({comm}) {' '.join(felder)}\n")

        for name, wert in (("PROC", proc), ("GREETER_USER", self.name)):
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)
        prozess(10, "labwc", 100)
        self.assertFalse(K.greeter_running())
        prozess(11, "quickshell", 995)
        self.assertFalse(K.greeter_running(), "erst 5 s alt: ein Greeter, der abstürzt, zählt nicht")
        prozess(12, "quickshell", 900)
        self.assertTrue(K.greeter_running())
        self.assertEqual(K.greeter_age(), 100.0, "das Alter des ältesten Greeter-Prozesses")
        K.GREETER_USER = "gibt-es-nicht-zenos"
        self.assertFalse(K.greeter_running())


    def test_uebernahme_meldet_es_der_oberflaeche(self):
        """Während install.sh aus dem Kanal bekommt jede Oberfläche auf seat0 Bescheid (beginn, ende): Sie lädt
        geänderte Dateien solange nicht einzeln nach. Als Benutzer der Sitzung, mit Argumentliste."""
        self.sitzungen([self.sitzung()], {"c1": "active"})
        laufzeit = os.path.join(self.ordner, "run-zenos-kanal")
        os.makedirs(laufzeit)
        for name, wert in (("RUNTIME_DIR", laufzeit), ("TRUSTED_UIDS", (0, os.getuid())),
                           ("PATH_CHECK_TOP", self.ordner)):
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)
        flagge = os.path.join(laufzeit, "uebernahme")
        with K.takeover_flag({"commit": "1" * 40}):
            self.assertEqual(lesen(flagge), "1" * 40 + "\n")
        self.assertFalse(os.path.exists(flagge))
        aufrufe = lesen(os.path.join(self.laufzeit, "setpriv-aufrufe")).splitlines()
        vorne = f"--reuid={self.uid} --regid={pwd.getpwuid(self.uid).pw_gid} --init-groups --no-new-privs -- "
        self.assertEqual(aufrufe[-2:], [vorne + f"{K.CODE_DIR}/scripts/bin/zenos-ipc kanal uebernahme beginn",
                                        vorne + f"{K.CODE_DIR}/scripts/bin/zenos-ipc kanal uebernahme ende"])
        # Ohne Sitzung auf seat0 niemand zu fragen
        os.unlink(os.path.join(self.laufzeit, "setpriv-aufrufe"))
        self.sitzungen([])
        with K.takeover_flag({"commit": "1" * 40}):
            pass
        self.assertFalse(os.path.exists(os.path.join(self.laufzeit, "setpriv-aufrufe")))

    # -- Akku --

    def geraet(self, akku, alter=0):
        zeit = (datetime.datetime.now().astimezone() - datetime.timedelta(seconds=alter)).isoformat(timespec="seconds")
        schreiben(K.POWER_STATUS, json.dumps({"version": 1, "zeit": zeit, "geraet": "argon-one-up", "akku": akku}))

    def test_akku_aus_der_statusdatei(self):
        self.assertEqual(K.power_state(), (None, None), "ohne Angaben: unbekannt, gilt als Netzteil")
        self.assertIsNone(K.power_problem())
        self.geraet({"vorhanden": True, "prozent": 20, "laedt": False, "zustand": "ok"})
        self.assertEqual(K.power_state(), (True, 20))
        self.assertEqual(K.power_problem(), "im Akkubetrieb mit 20 % (automatisch erst am Netzteil oder ab 50 %)")
        self.geraet({"vorhanden": True, "prozent": 80, "laedt": False, "zustand": "ok"})
        self.assertIsNone(K.power_problem(), "ab 50 % auch im Akkubetrieb")
        self.geraet({"vorhanden": True, "prozent": 20, "laedt": True, "zustand": "ok"})
        self.assertEqual(K.power_state(), (False, 20))
        self.assertIsNone(K.power_problem())
        # Unsicherer Messwert oder veraltete Datei: unbekannt
        self.geraet({"vorhanden": True, "prozent": 20, "laedt": False, "zustand": "unbekannt"})
        self.assertEqual(K.power_state(), (None, None))
        self.geraet({"vorhanden": True, "prozent": 20, "laedt": False, "zustand": "ok"}, alter=3600)
        self.assertEqual(K.power_state(), (None, None))
        self.geraet({"vorhanden": False})
        self.assertIsNone(K.power_problem())

    def test_akku_aus_sys(self):
        def eintrag(name, **werte):
            for schluessel, wert in werte.items():
                schreiben(os.path.join(K.POWER_SUPPLY_DIR, name, schluessel), wert + "\n")

        eintrag("BAT0", type="Battery", status="Discharging", capacity="30")
        eintrag("AC", type="Mains", online="0")
        self.assertEqual(K.power_state(), (True, 30))
        self.assertIn("30 %", K.power_problem())
        eintrag("AC", type="Mains", online="1")
        self.assertEqual(K.power_state(), (False, None))
        self.assertIsNone(K.power_problem())
        # Akku einer Maus (scope Device) zählt nicht
        shutil.rmtree(K.POWER_SUPPLY_DIR)
        eintrag("hid-maus", type="Battery", status="Discharging", capacity="5", scope="Device")
        self.assertEqual(K.power_state(), (None, None))


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Uhr(B.Basis):
    """«erstmals» nur mit synchronisierter Uhr; die 24 h auf stabil im selben Start nach der Zeit seit dem Start."""

    def setUp(self):
        super().setUp()
        self.addCleanup(setattr, K, "boot_clock", K.boot_clock)
        self.start("aaaaaaaa-1111-4222-8333-444444444444", 1000.0)
        self.synchron = [True]
        K.clock_synced = lambda: self.synchron[0]
        self.addCleanup(setattr, K, "now", K.now)
        self.jetzt = K.now()
        K.now = lambda: self.jetzt

    def start(self, boot, uhr):
        K.boot_clock = lambda: (boot, uhr)

    def stabil_bereit(self):
        self.commit("zwei")
        self.signieren("v0.2.0")
        self.kanal("stabil")

    def test_erstmals_nur_mit_synchroner_uhr(self):
        self.stabil_bereit()
        self.synchron[0] = False
        _, stand = self.lauf()
        self.assertIsNone(self.hauptbuch()["v0.2.0"]["erstmals"])
        self.assertIs(stand["uhr_synchron"], False)
        self.assertEqual((stand["bereit"]["erstmals"], stand["bereit"]["frei_ab"], stand["bereit"]["frei"]),
                         (None, None, False))
        self.assertIn("synchronisierter Uhr", stand["grund"])
        # Später, synchron: jetzt erst gilt es als gesehen, die 24 h beginnen hier
        self.jetzt += datetime.timedelta(hours=30)
        self.synchron[0] = True
        _, stand = self.pruefen()
        eintrag = self.hauptbuch()["v0.2.0"]
        self.assertEqual(eintrag["erstmals"], K.iso(self.jetzt))
        self.assertEqual(eintrag["erstmals_start"], {"start": "aaaaaaaa-1111-4222-8333-444444444444",
                                                     "seit_start": 1000.0})
        self.assertIs(stand["bereit"]["frei"], False)
        self.assertEqual(stand["bereit"]["frei_ab"], K.iso(self.jetzt + datetime.timedelta(hours=24)))

    def test_vorschau_ohne_wartezeit_auch_ohne_uhr(self):
        self.commit("zwei")
        self.signieren("v0.2.0-rc1")
        self.synchron[0] = False
        _, stand = self.lauf()
        self.assertIs(stand["bereit"]["frei"], True)
        self.assertEqual(stand["zustand"], "bereit")

    def test_sprung_der_uhr_im_selben_start(self):
        self.stabil_bereit()
        self.lauf()
        # NTP stellt die Uhr 30 h vor, seit dem Start ist aber nur 1 h vergangen: nicht frei
        self.jetzt += datetime.timedelta(hours=30)
        self.start("aaaaaaaa-1111-4222-8333-444444444444", 1000.0 + 3600)
        _, stand = self.pruefen()
        self.assertIs(stand["bereit"]["frei"], False)
        self.start("aaaaaaaa-1111-4222-8333-444444444444", 1000.0 + 25 * 3600)
        _, stand = self.pruefen()
        self.assertIs(stand["bereit"]["frei"], True)

    def test_neustart_braucht_synchrone_uhr(self):
        self.stabil_bereit()
        self.lauf()
        self.jetzt += datetime.timedelta(hours=30)
        self.start("bbbbbbbb-1111-4222-8333-444444444444", 50.0)
        self.synchron[0] = False
        _, stand = self.pruefen()
        self.assertIs(stand["bereit"]["frei"], False, "nach einem Neustart gilt die Uhr nur synchronisiert")
        self.synchron[0] = True
        _, stand = self.pruefen()
        self.assertIs(stand["bereit"]["frei"], True)

    def test_wunsch_der_automatik_ohne_ja(self):
        K.write_wish("automatik")
        self.assertEqual(K.take_wish(K.now())["art"], "automatik")
        K.write_wish("automatik", ja="0" * 40)
        self.assertIsNone(K.take_wish(K.now()), "die Automatik stimmt nie zu")


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Automatik(I.Geraet):
    """automatik lauf und gelegenheit mit den Units im Prozess. Ohne systemd: keine Sitzung auf seat0 (ruhig)."""

    def setUp(self):
        super().setUp()
        for name, wert in (("CLOCK_WAIT", 0), ("CONFIRM_WAIT", 0), ("CONFIRM_LOCK_WAIT", 0), ("CONFIRM_POLL", 0.05)):
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)
        for name in ("quiet_now", "start_id", "login_state", "local_now", "boot_clock"):
            self.addCleanup(setattr, K, name, getattr(K, name))
        K.start_id = lambda: "start-1"
        self.zeitpunkt("jederzeit")

    # -- Hilfen --

    def zeitpunkt(self, art, von=None, bis=None):
        text = f"zeitpunkt={art}\n" + (f"von={von}\nbis={bis}\n" if von else "")
        schreiben(K.SCHEDULE_FILE, text)

    def automatik(self, art="lauf"):
        self.protokoll = []
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.cmd_automatic([art])
        self.ausgabe = aus.getvalue() + "".join(p[2] for p in self.protokoll)
        return rc

    def bestaetigen(self):
        self.protokoll = []
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.cmd_confirm([])
        self.ausgabe = aus.getvalue() + "".join(p[2] for p in self.protokoll)
        return rc

    def units(self):
        return [p[0] for p in self.protokoll]

    def neu_signiert(self, name, dateien=None):
        neu = self.commit(f"stand {name}", dateien)
        self.signieren(name)
        return neu

    def letzter_lauf(self):
        return self.zustand(K.AUTO_LOG)

    def datei(self, name):
        return os.path.join(K.STATE_DIR, name)

    # -- Tests --

    def test_jederzeit_installiert_und_wartet_auf_bestaetigung(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.units(), ["holen", "pruefen", "installieren", "pruefen"])
        self.assertEqual(self.kopf(), neu)
        self.assertEqual(self.laeufe()[-1], ["normal", neu, "1"])
        self.assertIs(self.zustand("letzte.json")["ziel"]["von_hand"], False, "install.sh mit --ruhig")
        offen = self.zustand(K.UNCONFIRMED)
        self.assertEqual((offen["commit"], offen["tag"], offen["art"], offen["von_hand"], offen["start"],
                          offen["fehlstarts"], offen["guter_stand"]), (neu, "v0.1.0-rc5", "automatik", False,
                                                                       "start-1", [], gut))
        self.assertEqual(self.zustand("gut.json")["commit"], gut, "gut erst nach der Bestätigung")
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert")
        self.assertIn("automatisch", self.zustand("letzte.json")["grund"])
        self.assertEqual(self.hoechste(), "v0.1.0-rc5")
        self.assertEqual(sorted(os.listdir(self.datei("bereit"))), sorted([neu, gut]), "der gute Stand bleibt bereit")
        self.assertEqual(self.letzter_lauf()["ergebnis"], "installiert")
        self.assertEqual(K.installation_summary()[0], "unbestaetigt")
        # Danach ist nichts mehr zu tun, auch nicht für zen update
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "nichts")
        self.assertEqual(len(self.laeufe()), 2)
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertIn("Schon installiert", self.ausgabe)

    def test_ohne_ruhe_nur_holen_und_pruefen(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        K.quiet_now = lambda zeitpunkt: (False, "test ist nicht ruhig")
        vorher = self.kopf()
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.units(), ["holen", "pruefen"])
        self.assertEqual(self.kopf(), vorher)
        self.assertEqual(self.zustand("stand.json")["zustand"], "bereit")
        self.assertIsNone(self.zustand("stand.json")["wunsch"], "ohne Ruhe kein Wunsch")
        self.assertTrue(os.path.exists(self.datei(K.READY_MARK)))
        lauf = self.letzter_lauf()
        self.assertEqual((lauf["ergebnis"], lauf["art"]), ("wartet", "lauf"))
        self.assertIn("test ist nicht ruhig", lauf["grund"])

    def test_von_hand_nie(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        vorher = self.kopf()
        self.zeitpunkt("hand")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), vorher)
        self.assertEqual(self.zustand("stand.json")["zustand"], "bereit")
        self.assertIn("von Hand", self.letzter_lauf()["grund"])
        self.assertEqual(self.automatik("gelegenheit"), 0)
        self.assertEqual(self.kopf(), vorher)

    def test_dev_nie(self):
        self.kanal("dev")
        neu = self.commit("signiert", signiert_mit="rel")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertNotEqual(self.kopf(), neu)
        self.assertEqual(self.zustand("stand.json")["zustand"], "dev")
        self.assertIn("Kanal dev", self.letzter_lauf()["grund"])
        self.assertFalse(os.path.exists(self.datei(K.READY_MARK)))
        # Auch ein Wunsch der Automatik auf dev wird abgelehnt (falls der Kanal dazwischen wechselt)
        K.write_wish("automatik")
        _, stand = self.pruefen()
        self.assertEqual(stand["wunsch"]["ergebnis"], "abgelehnt")
        self.assertNotEqual(self.kopf(), neu)

    def test_zustimmung_bleibt_liegen(self):
        self.signiert_installiert("v0.1.0-rc4")
        vorher = self.kopf()
        self.neu_signiert("v0.1.0-rc5", {"scripts/module/35-netzwerk.sh": "# neu\n"})
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), vorher)
        self.assertEqual(self.zustand("stand.json")["zustand"], "zustimmung")
        self.assertEqual(self.letzter_lauf()["ergebnis"], "wartet")
        self.assertIn("Zustimmung", self.letzter_lauf()["grund"])
        self.assertFalse(os.path.exists(self.datei("auftrag.json")))

    def test_stabil_erst_nach_24_stunden(self):
        self.kanal("stabil")
        boot = ["cccccccc-1111-4222-8333-444444444444", 500.0]
        K.boot_clock = lambda: (boot[0], boot[1])
        self.signiert_installiert("v0.1.0")
        neu = self.neu_signiert("v0.2.0")
        vorher = self.kopf()
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), vorher)
        self.assertIn("24 h", self.letzter_lauf()["grund"])
        spaeter = K.now() + datetime.timedelta(hours=25)
        self.addCleanup(setattr, K, "now", K.now)
        K.now = lambda: spaeter
        boot[1] += 25 * 3600
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)

    def test_notschalter(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        vorher = self.kopf()
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_automatic(["aus"]), 0)
        self.assertTrue(os.path.exists(K.AUTOMATIC_OFF_FILE))
        self.assertEqual(os.stat(K.AUTOMATIC_OFF_FILE).st_mode & 0o777, 0o644)
        self.assertEqual(self.automatik(), 0)
        self.assertEqual((self.units(), self.kopf()), ([], vorher), "aus: weder holen noch installieren")
        self.assertEqual(self.letzter_lauf()["ergebnis"], "aus")
        _, stand = self.lauf()
        self.assertEqual(stand["automatik"], {"an": False})
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_automatic(["an"]), 0)
        self.assertFalse(os.path.exists(K.AUTOMATIC_OFF_FILE))
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertNotEqual(self.kopf(), vorher)

    def test_notschalter_nur_root(self):
        self.addCleanup(setattr, K, "TRUSTED_UIDS", K.TRUSTED_UIDS)
        K.TRUSTED_UIDS = (0,) if os.getuid() != 0 else (4242,)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(K.cmd_automatic(["aus"]), 2)
            self.assertEqual(K.cmd_automatic(["lauf"]), 2)
        self.assertFalse(os.path.exists(K.AUTOMATIC_OFF_FILE))

    def test_falsche_aufrufe(self):
        with contextlib.redirect_stderr(io.StringIO()):
            for argumente in (["jetzt"], ["an", "aus"], ["lauf", "x"], ["--lauf"]):
                self.assertEqual(K.cmd_automatic(argumente), 2, argumente)

    def test_fenster(self):
        self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        vorher = self.kopf()
        self.zeitpunkt("fenster", "22:00", "04:00")
        K.local_now = lambda: datetime.datetime(2026, 10, 5, 12, 0)
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), vorher)
        self.assertIn("ausserhalb des Zeitfensters 22:00–04:00", self.letzter_lauf()["grund"])
        K.local_now = lambda: datetime.datetime(2026, 10, 6, 1, 30)
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertNotIn("holen", self.units(), "die Gelegenheit holt nicht")
        self.assertEqual(self.kopf(), neu)
        self.assertEqual(self.letzter_lauf()["art"], "gelegenheit")

    def test_vor_dem_installieren_noch_einmal(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        vorher = self.kopf()
        antworten = [(True, "erst ruhig"), (False, "inzwischen entsperrt")]
        K.quiet_now = lambda zeitpunkt: antworten.pop(0)
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.units(), ["holen", "pruefen"])
        self.assertEqual(self.kopf(), vorher)
        self.assertFalse(os.path.exists(self.datei("auftrag.json")), "der Auftrag ist weg")
        self.assertIn("inzwischen entsperrt", self.letzter_lauf()["grund"])

    def test_bedienung_belegt(self):
        lauf = K.take_lock(K.UI_LOCK_FILE)
        self.addCleanup(os.close, lauf)
        self.assertEqual(self.automatik(), 75)
        self.assertEqual(self.units(), [])

    def test_unterbrochene_installation_setzt_sie_fort(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        echt = K.run_visible

        def ersatz(argv, env, timeout=None, cwd="/"):
            rc = echt(argv, env, timeout, cwd)
            if argv[0].endswith("/scripts/install.sh"):
                K.run_visible = echt
                raise I.Abgebrochen()
            return rc

        self.addCleanup(setattr, K, "run_visible", echt)
        K.run_visible = ersatz
        with self.assertRaises(I.Abgebrochen):
            self.automatik()
        self.assertTrue(os.path.exists(self.datei("laeuft.json")))
        self.git("checkout", "-q", "--force", "--detach", gut, ort=K.CODE_DIR)
        # Nicht ruhig: wartet
        K.quiet_now = lambda zeitpunkt: (False, "test ist nicht ruhig")
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), gut)
        self.assertIn("unterbrochen", self.letzter_lauf()["grund"])
        # Ruhig: fortgesetzt, und es bleibt eine automatische Installation (Bestätigung nach dem Start)
        K.quiet_now = lambda zeitpunkt: (True, "test ist ruhig")
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertEqual(self.zustand("letzte.json")["versuche"]["ziel"], 2)
        self.assertEqual(self.zustand(K.UNCONFIRMED)["commit"], neu)

    def test_rollback_stellt_die_verlassene_version_zurueck(self):
        alt = self.signiert_installiert("v0.1.0-rc4")
        neu = self.signiert_installiert("v0.1.0-rc5")
        self.assertEqual(self.zen("rollback", "v0.1.0-rc4"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), alt)
        halt = self.zustand(K.HOLD)
        self.assertEqual((halt["zurueckgestellt"], halt["nach"]), ("v0.1.0-rc5", "v0.1.0-rc4"))
        self.assertIn("zurückgestellt", self.zustand("letzte.json")["hinweise"][-1])
        # Die Automatik bringt rc5 nicht wieder
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), alt)
        stand = self.zustand("stand.json")
        self.assertEqual(stand["zurueckgestellt"]["version"], "v0.1.0-rc5")
        self.assertIn("zurückgestellt", stand["grund"])
        self.assertEqual(stand["hoechste"], "v0.1.0-rc5", "hoechste sinkt nicht: Das hält rc5 von der Automatik fern")
        status = io.StringIO()
        with contextlib.redirect_stdout(status):
            K.cmd_status([])
        self.assertIn("v0.1.0-rc5 (seit", status.getvalue())
        # zen update von Hand hebt das auf
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertFalse(os.path.exists(self.datei(K.HOLD)))

    def test_neuere_version_hebt_die_rueckstellung_auf(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.signiert_installiert("v0.1.0-rc5")
        self.assertEqual(self.zen("rollback", "v0.1.0-rc4"), 0, self.ausgabe)
        neu = self.neu_signiert("v0.1.0-rc6")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertFalse(os.path.exists(self.datei(K.HOLD)))

    def test_rollback_auf_neuere_version_stellt_nichts_zurueck(self):
        self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.zen("rollback", "v0.1.0-rc5"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertFalse(os.path.exists(self.datei(K.HOLD)))

    def test_bestaetigung_nach_dem_neustart(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        K.login_state = lambda greetd: (True, "der Login-Bildschirm läuft")
        # Im selben Start nichts
        self.assertEqual(self.bestaetigen(), 0)
        self.assertIn("kein Neustart", self.ausgabe)
        self.assertTrue(os.path.exists(self.datei(K.UNCONFIRMED)))
        K.start_id = lambda: "start-2"
        self.assertEqual(self.bestaetigen(), 0, self.ausgabe)
        self.assertIn("Bestätigt", self.ausgabe)
        gut_json = self.zustand("gut.json")
        self.assertEqual((gut_json["commit"], gut_json["tag"]), (neu, "v0.1.0-rc5"))
        self.assertTrue(K.parse_iso(gut_json["bestaetigt"]))
        self.assertFalse(os.path.exists(self.datei(K.UNCONFIRMED)))
        self.assertEqual(os.listdir(self.datei("bereit")), [neu], "der alte gute Stand ist nicht mehr nötig")
        self.assertNotEqual(gut, neu)
        self.assertEqual(K.installation_summary()[0], "gut")
        self.assertEqual(self.bestaetigen(), 0)
        self.assertIn("Nichts zu bestätigen", self.ausgabe)

    def test_zweimal_ohne_login_zurueck_auf_den_guten_stand(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        K.login_state = lambda greetd: (False, "greetd läuft nicht (failed)")
        K.start_id = lambda: "start-2"
        self.assertEqual(self.bestaetigen(), 10, self.ausgabe)
        self.assertEqual(self.zustand(K.UNCONFIRMED)["fehlstarts"], ["start-2"])
        self.assertEqual(self.bestaetigen(), 10, "derselbe Start zählt nur einmal")
        self.assertEqual(self.zustand(K.UNCONFIRMED)["fehlstarts"], ["start-2"])
        K.start_id = lambda: "start-3"
        self.assertEqual(self.bestaetigen(), 0, self.ausgabe)
        self.assertEqual(self.units(), ["installieren", "pruefen"])
        self.assertEqual(self.kopf(), gut)
        self.assertEqual(self.laeufe()[-1][:2], ["normal", gut])
        gesperrt = K.load_json(os.path.join(K.STATE_DIR, "gesperrt", "v0.1.0-rc5"))
        self.assertIn("kein Login", gesperrt["grund"])
        self.assertFalse(os.path.exists(self.datei(K.UNCONFIRMED)))
        letzte = self.zustand("letzte.json")
        self.assertEqual(letzte["ergebnis"], "zurueck")
        self.assertIn("kein Login", letzte["grund"])
        self.assertEqual(self.zustand("gut.json")["commit"], gut)
        # Die gesperrte Version kommt automatisch nicht wieder, und zen update fragt nicht nach ihr
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), gut)
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual((self.kopf(), self.fragen), (gut, []))
        self.assertIn("gesperrt: v0.1.0-rc5; noch einmal versuchen: zen rollback v0.1.0-rc5", self.ausgabe)

    def test_ohne_guten_stand_kaputt(self):
        # Das allererste Update über den Kanal kam automatisch: Es gibt keinen guten Stand für den Weg zurück
        neu = self.neu_signiert("v0.1.0-rc4")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        K.login_state = lambda greetd: (False, "greetd läuft nicht (failed)")
        for start in ("start-2", "start-3"):
            K.start_id = lambda s=start: s
            rc = self.bestaetigen()
        self.assertEqual(rc, 5, self.ausgabe)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "kaputt")
        self.assertTrue(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt", "v0.1.0-rc4")))
        self.assertEqual(self.kopf(), neu, "nichts installiert")

    def test_von_hand_danach_gilt_sofort(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        neu = self.neu_signiert("v0.1.0-rc6")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.zustand("gut.json")["commit"], neu)
        self.assertFalse(os.path.exists(self.datei(K.UNCONFIRMED)))

    def test_ausgetauschter_stand_wird_nicht_bestaetigt(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.git("checkout", "-q", "--force", "--detach", self.basis, ort=K.CODE_DIR)
        K.start_id = lambda: "start-2"
        K.login_state = lambda greetd: (True, "test")
        self.assertEqual(self.bestaetigen(), 0)
        self.assertIn("nicht mehr installiert", self.ausgabe)
        self.assertFalse(os.path.exists(self.datei(K.UNCONFIRMED)))

    def test_marker_fuer_die_gelegenheit(self):
        self.signiert_installiert("v0.1.0-rc4")
        objekt = self.signieren("v0.1.0-rc5", ref=self.commit("rc5"))
        self.lauf()
        marke = self.zustand(K.READY_MARK)
        self.assertEqual((marke["version"], marke["objekt"], marke["frei"]), ("v0.1.0-rc5", objekt, True))
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertFalse(os.path.exists(self.datei(K.READY_MARK)), "nach der Installation nichts mehr bereit")

    def test_status_und_hilfe(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_automatic([]), 0)
            K.cmd_status([])
        text = aus.getvalue()
        self.assertIn("Automatik   an", text)
        self.assertIn("Bestätigung v0.1.0-rc5 automatisch installiert", text)
        self.assertIn("zuletzt", text)
        self.assertIn("gilt als gut nach einem Neustart mit Login", text)
        for befehl in ("automatik", "bestaetigen"):
            self.assertRegex(K.__doc__, re.compile(rf"^  zenos-kanal {befehl}\b", re.M))

    # -- Befunde der Prüfung (Teil B) --

    def werkbank(self):
        """install.sh von Hand aus einem Arbeitsstand: lokaler Commit in /opt/zenos, Vermerk «angehalten» (10-code)."""
        self.commit("werkbank", {"werkbank": "arbeit\n"}, ort=K.CODE_DIR)
        hand = self.kopf()
        K.write_json(self.datei("angehalten"), {"version": 1, "commit": hand, "zeit": K.iso(K.now())})
        return hand

    def test_angehalten_ruht_bis_zen_update(self):
        """10-code: «bis zum nächsten zen update kommt nichts automatisch». Auch nicht auf vorschau ohne Wartezeit,
        auch nicht beim Login-Bildschirm (Lauf und Gelegenheit)."""
        self.signiert_installiert("v0.1.0-rc4")
        hand = self.werkbank()
        neu = self.neu_signiert("v0.1.0-rc5")
        for art in ("lauf", "gelegenheit"):
            self.assertEqual(self.automatik(art), 0, self.ausgabe)
            self.assertEqual(self.kopf(), hand, art)
            self.assertNotIn("installieren", self.units())
            self.assertEqual(self.letzter_lauf()["ergebnis"], "wartet")
            self.assertIn("Von Hand angehalten", self.letzter_lauf()["grund"])
        stand = self.zustand("stand.json")
        self.assertEqual(stand["angehalten"]["commit"], hand)
        self.assertEqual(stand["installation_lage"]["schluessel"], "angehalten")
        self.assertFalse(os.path.exists(self.datei(K.READY_MARK)), "die Gelegenheit läuft gar nicht erst")
        # Auch ein Wunsch der Automatik wird abgelehnt
        K.write_wish("automatik")
        _, stand = self.pruefen()
        self.assertEqual(stand["wunsch"]["ergebnis"], "abgelehnt")
        # zen update kehrt zum Kanal zurück, danach gilt die Automatik wieder
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertFalse(os.path.exists(self.datei("angehalten")))

    def test_angehalten_zwischen_pruefen_und_installieren(self):
        """Ein install.sh von Hand wird genau zwischen Prüfen und Installieren der Automatik fertig: Der Auftrag der
        Automatik gilt nicht mehr."""
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        echt = K.start_unit
        hand = []

        def unit(schluessel, follow=False):
            if schluessel == "installieren" and not hand:
                hand.append(self.werkbank())
            return echt(schluessel, follow)

        K.start_unit = unit
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), hand[0])
        self.assertEqual(self.letzter_lauf()["ergebnis"], "wartet")
        self.assertIn("Von Hand angehalten", self.letzter_lauf()["grund"])
        self.assertFalse(os.path.exists(self.datei("auftrag.json")))
        self.assertTrue(os.path.exists(self.datei("angehalten")))

    def test_zeitpunkt_von_hand_waehrend_des_laufs(self):
        """Der Zeitpunkt wird auf «von Hand» gestellt, während die Automatik prüft: Vor dem Installieren gilt der neue."""
        self.signiert_installiert("v0.1.0-rc4")
        vorher = self.kopf()
        self.neu_signiert("v0.1.0-rc5")
        echt = K.start_unit

        def unit(schluessel, follow=False):
            rc = echt(schluessel, follow)
            if schluessel == "pruefen":
                self.zeitpunkt("hand")
            return rc

        K.start_unit = unit
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), vorher)
        self.assertNotIn("installieren", self.units())
        self.assertIn("inzwischen «von Hand", self.letzter_lauf()["grund"])
        self.assertFalse(os.path.exists(self.datei("auftrag.json")))

    def unterbrochen_von_hand(self):
        """zen update mit «ja» bzw. ohne, mittendrin abgebrochen (Strom, kill): laeuft.json bleibt."""
        echt = K.run_visible

        def ersatz(argv, env, timeout=None, cwd="/"):
            rc = echt(argv, env, timeout, cwd)
            if argv[0].endswith("/scripts/install.sh"):
                K.run_visible = echt
                raise I.Abgebrochen()
            return rc

        self.addCleanup(setattr, K, "run_visible", echt)
        K.run_visible = ersatz
        with self.assertRaises(I.Abgebrochen):
            self.zen()
        self.assertTrue(os.path.exists(self.datei("laeuft.json")))

    def test_dev_unterbrochen_setzt_nur_zen_update_fort(self):
        """Kanal dev: Ein zen update mit «ja» wurde unterbrochen. Die Automatik setzt es nicht fort (dev kommt nie
        automatisch, und das «ja» galt dem Terminal), auch Tage später und in Ruhe nicht."""
        self.kanal("dev")
        self.ohne_anker()
        self.commit("neu auf dev")
        self.antworten = ["ja"]
        self.unterbrochen_von_hand()
        self.git("checkout", "-q", "--force", "--detach", self.basis, ort=K.CODE_DIR)
        laeufe = len(self.laeufe())
        K.quiet_now = lambda zeitpunkt: (True, "gesperrt")
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual((len(self.laeufe()), self.kopf()), (laeufe, self.basis))
        self.assertIn("von Hand wurde unterbrochen", self.letzter_lauf()["grund"])
        self.assertIn("zen update", self.letzter_lauf()["grund"])
        self.assertTrue(os.path.exists(self.datei("laeuft.json")), "zen update setzt fort")

    def test_vorschau_von_hand_unterbrochen_nicht_automatisch(self):
        self.signiert_installiert("v0.1.0-rc4")
        alt = self.kopf()
        self.neu_signiert("v0.1.0-rc5")
        self.unterbrochen_von_hand()
        self.git("checkout", "-q", "--force", "--detach", alt, ort=K.CODE_DIR)
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), alt)
        self.assertIn("von Hand wurde unterbrochen", self.letzter_lauf()["grund"])

    def test_akku_haelt_die_automatik_auf(self):
        """Argon ONE UP mit zugeklapptem Deckel im Akkubetrieb: unter 50 % nichts, am Netzteil schon."""
        self.signiert_installiert("v0.1.0-rc4")
        vorher = self.kopf()
        neu = self.neu_signiert("v0.1.0-rc5")

        def akku(prozent, laedt):
            zeit = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
            schreiben(K.POWER_STATUS, json.dumps({"version": 1, "zeit": zeit, "akku": {
                "vorhanden": True, "prozent": prozent, "laedt": laedt, "zustand": "ok"}}))

        akku(12, False)
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), vorher)
        self.assertIn("im Akkubetrieb mit 12 %", self.letzter_lauf()["grund"])
        akku(12, True)
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)

    def test_akku_haelt_auch_das_fortsetzen_auf(self):
        self.signiert_installiert("v0.1.0-rc4")
        gut = self.kopf()
        neu = self.neu_signiert("v0.1.0-rc5")
        echt = K.run_visible

        def ersatz(argv, env, timeout=None, cwd="/"):
            rc = echt(argv, env, timeout, cwd)
            if argv[0].endswith("/scripts/install.sh"):
                K.run_visible = echt
                raise I.Abgebrochen()
            return rc

        self.addCleanup(setattr, K, "run_visible", echt)
        K.run_visible = ersatz
        with self.assertRaises(I.Abgebrochen):
            self.automatik()
        self.git("checkout", "-q", "--force", "--detach", gut, ort=K.CODE_DIR)
        zeit = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        schreiben(K.POWER_STATUS, json.dumps({"version": 1, "zeit": zeit, "akku": {
            "vorhanden": True, "prozent": 5, "laedt": False, "zustand": "ok"}}))
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), gut)
        self.assertIn("im Akkubetrieb mit 5 %", self.letzter_lauf()["grund"])
        os.unlink(K.POWER_STATUS)
        self.assertEqual(self.automatik("gelegenheit"), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)

    def test_bestaetigung_wartet_auf_die_sperre_der_bedienung(self):
        """Beim Start läuft gerade die Automatik (Persistent): Die Bestätigung wartet darauf, statt bis zum nächsten
        Start zu verfallen; dieser Start ohne Login zählt."""
        self.signiert_installiert("v0.1.0-rc4")
        self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        K.start_id = lambda: "start-2"
        K.login_state = lambda greetd: (False, "greetd läuft nicht (failed)")
        lauf = K.take_lock(K.UI_LOCK_FILE)
        K.CONFIRM_LOCK_WAIT = 30
        freigabe = threading.Timer(0.5, os.close, (lauf,))
        freigabe.start()
        self.addCleanup(freigabe.join)
        self.assertEqual(self.bestaetigen(), 10, self.ausgabe)
        self.assertIn("wartet darauf", self.ausgabe)
        self.assertEqual(self.zustand(K.UNCONFIRMED)["fehlstarts"], ["start-2"])
        # Bleibt die Sperre belegt, endet es nach der Wartezeit mit 75
        lauf = K.take_lock(K.UI_LOCK_FILE)
        self.addCleanup(os.close, lauf)
        K.CONFIRM_LOCK_WAIT = 0.2
        self.assertEqual(self.bestaetigen(), 75, self.ausgabe)

    def test_keine_neue_automatik_vor_der_bestaetigung(self):
        """Ein automatisch installierter Stand aus einem früheren Start wartet auf die Bestätigung: Die Automatik
        installiert nichts Neues (die Zählung der Starts ohne Login begänne sonst von vorn)."""
        self.signiert_installiert("v0.1.0-rc4")
        rc5 = self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.neu_signiert("v0.1.0-rc6")
        K.start_id = lambda: "start-2"
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), rc5)
        self.assertIn("wartet auf die Bestätigung", self.letzter_lauf()["grund"])
        K.login_state = lambda greetd: (True, "der Login-Bildschirm läuft")
        self.assertEqual(self.bestaetigen(), 0, self.ausgabe)
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        self.assertNotEqual(self.kopf(), rc5, "nach der Bestätigung geht es weiter")

    def test_weg_zurueck_scheitert(self):
        """Zweimal kein Login, und install.sh des guten Stands scheitert (etwa ohne Netz): Kein Rückweg auf den Stand
        ohne Login, der gute Stand bleibt ungesperrt, «kaputt», und der nächste Start versucht es noch einmal."""
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        K.login_state = lambda greetd: (False, "greetd läuft nicht (failed)")
        echt = K.run_visible
        gut_ordner = os.path.join(K.STATE_DIR, "bereit", gut)
        scheitern = [True]

        def ersatz(argv, env, timeout=None, cwd="/"):
            if scheitern[0] and argv[0] == os.path.join(gut_ordner, "scripts", "install.sh"):
                return 1
            return echt(argv, env, timeout, cwd)

        self.addCleanup(setattr, K, "run_visible", echt)
        K.run_visible = ersatz
        K.start_id = lambda: "start-2"
        self.assertEqual(self.bestaetigen(), 10, self.ausgabe)
        K.start_id = lambda: "start-3"
        self.assertEqual(self.bestaetigen(), 5, self.ausgabe)
        letzte = self.zustand("letzte.json")
        self.assertEqual(letzte["ergebnis"], "kaputt")
        self.assertIn("Weg zurück auf den guten Stand", letzte["grund"])
        self.assertIsNone(letzte["rueckweg"], "kein Rückweg auf den Stand ohne Login")
        self.assertEqual(sorted(os.listdir(self.datei("gesperrt"))), ["v0.1.0-rc5"], "der gute Stand ist nicht gesperrt")
        offen = self.zustand(K.UNCONFIRMED)
        self.assertEqual(offen["commit"], neu)
        self.assertTrue(K.parse_iso(offen["zurueck"]))
        self.assertEqual(K.installation_summary()[0], "kaputt")
        # Nächster Start, wieder kein Login: noch ein Versuch, jetzt gelingt er
        scheitern[0] = False
        K.start_id = lambda: "start-4"
        self.assertEqual(self.bestaetigen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), gut)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "zurueck")
        self.assertEqual(self.zustand("gut.json")["commit"], gut)
        self.assertFalse(os.path.exists(self.datei(K.UNCONFIRMED)))

    def test_weg_zurueck_gescheitert_dann_kommt_der_login(self):
        """Der Weg zurück scheiterte, beim nächsten Start kommt der Login doch: Der Stand ist gut, seine Sperre weg."""
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.neu_signiert("v0.1.0-rc5")
        self.assertEqual(self.automatik(), 0, self.ausgabe)
        K.login_state = lambda greetd: (False, "greetd läuft nicht (failed)")
        echt = K.run_visible
        gut_install = os.path.join(K.STATE_DIR, "bereit", gut, "scripts", "install.sh")
        self.addCleanup(setattr, K, "run_visible", echt)
        K.run_visible = lambda argv, env, timeout=None, cwd="/": 1 if argv[0] == gut_install else echt(argv, env,
                                                                                                      timeout, cwd)
        for start in ("start-2", "start-3"):
            K.start_id = lambda s=start: s
            self.bestaetigen()
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "kaputt")
        self.assertEqual(self.kopf(), neu)
        K.start_id = lambda: "start-4"
        K.login_state = lambda greetd: (True, "der Login-Bildschirm läuft")
        self.assertEqual(self.bestaetigen(), 0, self.ausgabe)
        self.assertEqual(self.zustand("gut.json")["commit"], neu)
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt", "v0.1.0-rc5")))

    def test_selbsttest_probelauf_kennt_die_automatik(self):
        self.assertIn(("automatik", ["automatik"]), [tuple(x) for x in self._probelauf_schritte()])

    def _probelauf_schritte(self):
        quelle = lesen(os.path.join(WURZEL, "scripts", "bin", "zenos-kanal"))
        teil = quelle[quelle.index("steps = ((\"status\""):quelle.index("with open(os.devnull")]
        return [(m.group(1), [x.strip(' "') for x in m.group(2).split(",") if x.strip()])
                for m in re.finditer(r'\("([a-z -]+)", \[([^\]]*)\]\)', teil)]


class Units(unittest.TestCase):
    def zeilen(self, name):
        return [z.strip() for z in lesen(os.path.join(UNITS, name)).splitlines()]

    def test_timer(self):
        timer = self.zeilen("zenos-kanal.timer")
        for zeile in ("OnBootSec=10min", "OnCalendar=*-*-* 00/6:00:00", "RandomizedDelaySec=10min", "Persistent=true",
                      "Unit=zenos-kanal-automatik.service", "WantedBy=timers.target"):
            self.assertIn(zeile, timer)
        gelegenheit = self.zeilen("zenos-kanal-gelegenheit.timer")
        self.assertIn("OnCalendar=*:0/15", gelegenheit)
        self.assertIn("Unit=zenos-kanal-gelegenheit.service", gelegenheit)
        self.assertFalse(any(z.startswith("OnUnitActiveSec") for z in gelegenheit),
                         "OnUnitActiveSec bliebe stehen, wenn die Bedingung der Unit nicht erfüllt ist")
        bestaetigen = self.zeilen("zenos-kanal-bestaetigen.timer")
        self.assertIn("OnBootSec=2min", bestaetigen)
        self.assertIn("Unit=zenos-kanal-bestaetigen.service", bestaetigen)

    def test_services(self):
        programm = "/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal"
        for name, befehl in (("zenos-kanal-automatik.service", "automatik lauf"),
                             ("zenos-kanal-gelegenheit.service", "automatik gelegenheit"),
                             ("zenos-kanal-bestaetigen.service", "bestaetigen")):
            with self.subTest(name):
                zeilen = self.zeilen(name)
                self.assertIn(f"ExecStart={programm} {befehl}", zeilen)
                self.assertIn("Type=oneshot", zeilen)
                self.assertIn("SuccessExitStatus=10 75", zeilen)
                self.assertIn("RuntimeDirectory=zenos-sperre", zeilen)
                self.assertIn("RuntimeDirectoryPreserve=yes", zeilen)
                self.assertIn("ProtectHome=read-only", zeilen)
                self.assertFalse(any(z.startswith("[Install]") for z in zeilen), "nur über den Timer")
        for name in ("zenos-kanal-automatik.service", "zenos-kanal-gelegenheit.service"):
            self.assertIn("ConditionPathExists=!/etc/xdg/zenos/kanal-automatik-aus", self.zeilen(name))
        gelegenheit = self.zeilen("zenos-kanal-gelegenheit.service")
        self.assertIn(f"ConditionPathExists=|/var/lib/zenos/kanal/{K.READY_MARK}", gelegenheit)
        self.assertIn("ConditionPathExists=|/var/lib/zenos/kanal/laeuft.json", gelegenheit)
        self.assertIn(f"ConditionPathExists=/var/lib/zenos/kanal/{K.UNCONFIRMED}",
                      self.zeilen("zenos-kanal-bestaetigen.service"))
        self.assertNotIn("ProcSubset=pid", self.zeilen("zenos-kanal-pruefen.service"),
                         "das Prüfen braucht die Start-ID")

    def test_modul_doctor_zen(self):
        modul = lesen(MODUL)
        for name in ("zenos-kanal.timer", "zenos-kanal-automatik.service", "zenos-kanal-gelegenheit.timer",
                     "zenos-kanal-gelegenheit.service", "zenos-kanal-bestaetigen.timer",
                     "zenos-kanal-bestaetigen.service"):
            self.assertIn(name, modul)
            self.assertIn(name, lesen(DOCTOR))
            self.assertTrue(os.path.isfile(os.path.join(UNITS, name)))
        self.assertIn(f"_KANAL_AUS={K.AUTOMATIC_OFF_FILE}", modul)
        self.assertEqual(K.TIMERS, ("zenos-kanal.timer", "zenos-kanal-gelegenheit.timer"))
        self.assertIn("_KANAL_AUTOMATIK=(zenos-kanal.timer zenos-kanal-gelegenheit.timer)", modul)
        # Die Bestätigung nur aktivieren, nie im Betrieb starten: Nach dem Start feuerte sie sofort und hielte nach
        # jedem install.sh kurz die Sperre der Bedienung (im Ende-zu-Ende-Test endete die Automatik so mit 75)
        self.assertIn("dienst_aktivieren zenos-kanal-bestaetigen.timer", modul)
        self.assertNotIn("_kanal_timer_an zenos-kanal-bestaetigen.timer", modul)
        zen = lesen(ZEN_KANAL)
        self.assertIn('automatik "$1"', zen)


if __name__ == "__main__":
    unittest.main(verbosity=1)
