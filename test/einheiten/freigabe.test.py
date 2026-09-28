#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-freigabe (Marker, Nachlauf, Reihenfolge der Aufrufe, Wahl, Zurücksetzen).

Ohne Portal und ohne laufende Oberfläche: jeder Test hat ein eigenes XDG_RUNTIME_DIR, slurp ist eine Attrappe
im PATH. Die meisten Tests rufen eine Kopie des Skripts auf, neben der eine Attrappe von zenos-ipc die
Meldungen an die Oberfläche mitschreibt; ein Test ruft das Skript im Repo mit dem echten zenos-ipc auf (findet
im eigenen XDG_RUNTIME_DIR keine Oberfläche). Wegen des festen Nachlaufs von 3 s dauert der Lauf rund 50 s.

  python3 test/einheiten/freigabe.test.py
"""

import os
import shlex
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FREIGABE = os.path.join(WURZEL, "scripts", "bin", "zenos-freigabe")


class Beobachter(threading.Thread):
    """Liest den Marker alle 5 ms und hält jede Änderung fest (None = fehlt oder leer)."""

    def __init__(self, lesen):
        super().__init__(daemon=True)
        self.lesen = lesen
        self.verlauf = []
        self._halt = threading.Event()

    def run(self):
        alt = object()
        while not self._halt.is_set():
            wert = self.lesen()
            if wert != alt:
                self.verlauf.append(wert)
                alt = wert
            time.sleep(0.005)

    def stoppen(self):
        self._halt.set()
        self.join(5)
        return self.verlauf


class FreigabeTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-freigabe-test.")
        self.lz = os.path.join(self.wurzel, "lz")
        self.bin = os.path.join(self.wurzel, "bin")
        os.makedirs(self.lz, mode=0o700)
        os.makedirs(self.bin)
        self.ordner = os.path.join(self.lz, "zenos")
        self.ipc_log = os.path.join(self.wurzel, "ipc.log")
        self.slurp_ausgabe = os.path.join(self.wurzel, "slurp-ausgabe")
        # Kopie des Skripts: zenos-freigabe ruft zenos-ipc aus seinem eigenen Ordner auf
        self.programm = os.path.join(self.bin, "zenos-freigabe")
        shutil.copy2(FREIGABE, self.programm)
        self._skript("zenos-ipc", f'printf \'%s\\n\' "$*" >> {shlex.quote(self.ipc_log)}\n')
        # slurp: gibt den Inhalt von slurp-ausgabe aus; fehlt die Datei, wie Esc (Exit 1)
        self._skript("slurp", f"exec cat {shlex.quote(self.slurp_ausgabe)} 2>/dev/null\n")
        self.slurp("HEADLESS-1")
        self.umgebung = {
            "PATH": self.bin + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "XDG_RUNTIME_DIR": self.lz,
            "HOME": self.wurzel,
            "LANG": "C.UTF-8",
        }

    def tearDown(self):
        # Kein «ende» im Nachlauf zurücklassen
        frist = time.monotonic() + 10
        while self._laufende() and time.monotonic() < frist:
            time.sleep(0.1)
        for pid in self._laufende():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        shutil.rmtree(self.wurzel, ignore_errors=True)

    # --- Hilfen

    def _skript(self, name, rumpf):
        pfad = os.path.join(self.bin, name)
        with open(pfad, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\n" + rumpf)
        os.chmod(pfad, 0o755)

    def _laufende(self):
        """PIDs der Prozesse, deren Befehlszeile auf den Testordner zeigt"""
        pids = []
        kennung = self.wurzel.encode()
        for eintrag in os.listdir("/proc"):
            if not eintrag.isdigit() or int(eintrag) == os.getpid():
                continue
            try:
                with open(f"/proc/{eintrag}/cmdline", "rb") as f:
                    if kennung in f.read():
                        pids.append(int(eintrag))
            except OSError:
                pass
        return pids

    def slurp(self, ausgabe):
        if ausgabe is None:
            os.unlink(self.slurp_ausgabe)
            return
        with open(self.slurp_ausgabe, "w", encoding="utf-8") as f:
            f.write(ausgabe + "\n")

    def aufruf(self, *args, programm=None):
        return subprocess.run([programm or self.programm, *args], capture_output=True, text=True,
                              env=self.umgebung, timeout=60, check=False)

    def hintergrund(self, *args):
        return subprocess.Popen([self.programm, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                env=self.umgebung)

    def verzoegert(self, sekunden, befehl):
        """Wie ein Aufruf, der früh beginnt, aber spät an die Sperre kommt: sh wartet und startet zenos-freigabe
        dann als Kindprozess. Wie bei xdpw bleibt sh Elternprozess (dash führt auch den letzten Befehl in einem
        Kindprozess aus), seine Startzeit ist der Aufrufzeitpunkt, und seine Befehlszeile endet auf den Befehl.
        Mit exec wäre die Befehlszeile während des Wechsels kurz leer; pgrep in «ende» fände den Aufruf dann
        nicht, was bei xdpw nicht vorkommt."""
        zeile = f"sleep {sekunden}; {shlex.quote(self.programm)} {befehl}"
        return subprocess.Popen(["sh", "-c", zeile], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                env=self.umgebung)

    def xdpw(self, befehl):
        """Wie xdg-desktop-portal-wlr (exec_with_shell): Doppel-fork, dann «sh -c <Befehl>», ohne zu warten.
        Gibt die PID von sh zurück."""
        lesen, schreiben = os.pipe()
        kind = os.fork()
        if kind == 0:
            try:
                os.close(lesen)
                enkel = os.fork()
                if enkel == 0:
                    os.close(schreiben)
                    leer = os.open(os.devnull, os.O_RDWR)
                    for fd in (0, 1, 2):
                        os.dup2(leer, fd)
                    os.execvpe("sh", ["sh", "-c", f"{shlex.quote(self.programm)} {befehl}"], self.umgebung)
                os.write(schreiben, str(enkel).encode())
            finally:
                os._exit(0)
        os.close(schreiben)
        os.waitpid(kind, 0)
        with os.fdopen(lesen) as f:
            return int(f.read())

    def datei(self, name):
        return os.path.join(self.ordner, name)

    def marker(self):
        """Zeilen des Markers oder None (fehlt oder leer)"""
        try:
            with open(self.datei("freigabe"), encoding="utf-8") as f:
                zeilen = [z for z in f.read().splitlines() if z]
        except OSError:
            return None
        return zeilen or None

    def eintraege(self):
        try:
            with open(self.datei("freigabe-eintraege"), encoding="utf-8") as f:
                return [z for z in f.read().splitlines() if z]
        except OSError:
            return []

    def ipc(self):
        try:
            with open(self.ipc_log, encoding="utf-8") as f:
                return f.read().splitlines()
        except OSError:
            return []

    def beobachten(self):
        b = Beobachter(self.marker)
        b.start()
        self.addCleanup(b.stoppen)
        # erster Wert, bevor es weitergeht
        while not b.verlauf:
            time.sleep(0.005)
        return b

    def warten(self, bedingung, sekunden=10):
        frist = time.monotonic() + sekunden
        while time.monotonic() < frist:
            if bedingung():
                return True
            time.sleep(0.05)
        return bedingung()

    def assertNieLeer(self, verlauf):
        self.assertNotIn(None, verlauf, f"Marker zwischendurch leer: {verlauf}")

    # --- Abläufe

    def test_wahl_start_ende_mit_nachlauf(self):
        ergebnis = self.aufruf("waehlen")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        self.assertEqual(ergebnis.stdout, "Monitor: HEADLESS-1\n")
        self.assertTrue(os.path.exists(self.datei("freigabe-wahl")))
        self.aufruf("start")
        self.assertEqual(self.marker(), ["HEADLESS-1"])
        self.assertFalse(os.path.exists(self.datei("freigabe-wahl")), "start übernimmt die Wahl")
        self.assertEqual(self.aufruf("status").stdout, "aktiv 1\n")
        ende = self.hintergrund("ende")
        time.sleep(1)
        self.assertEqual(self.marker(), ["HEADLESS-1"], "im Nachlauf bleibt der Marker")
        self.assertEqual(ende.wait(15), 0)
        self.assertIsNone(self.marker())
        self.assertEqual(self.eintraege(), [])
        self.assertFalse(os.path.exists(self.datei("freigabe-ende")))
        self.assertEqual(self.aufruf("status").stdout, "inaktiv\n")
        self.assertEqual(self.ipc(), ["freigabe gewaehlt HEADLESS-1", "freigabe gestartet", "freigabe beendet"])

    def test_chrome_zweite_sitzung_ohne_wahl(self):
        # Chrome schliesst die Sitzung der Vorschau und öffnet sofort eine zweite ohne Wahl
        self.aufruf("waehlen")
        self.aufruf("start")
        b = self.beobachten()
        ende = self.hintergrund("ende")
        start = self.hintergrund("start")
        self.assertEqual(start.wait(15), 0)
        self.assertEqual(ende.wait(15), 0)
        time.sleep(0.1)
        self.assertNieLeer(b.stoppen())
        self.assertEqual(self.marker(), ["*"], "nur die zweite Sitzung bleibt")
        self.assertEqual(len(self.eintraege()), 1)
        # Die Oberfläche erfährt kein Ende zwischen den Sitzungen
        self.assertEqual(self.ipc(), ["freigabe gewaehlt HEADLESS-1", "freigabe gestartet", "freigabe gestartet"])
        self.aufruf("ende")
        self.assertIsNone(self.marker())
        self.assertEqual(self.ipc()[-1], "freigabe beendet")

    def test_ende_frueher_aufgerufen_kommt_spaeter_an_die_sperre(self):
        self.aufruf("waehlen")
        self.aufruf("start")
        b = self.beobachten()
        ende = self.verzoegert(0.4, "ende")
        time.sleep(0.05)
        self.aufruf("start")
        self.assertEqual(self.marker(), ["HEADLESS-1", "*"])
        self.assertEqual(ende.wait(15), 0)
        time.sleep(0.2)
        self.assertNieLeer(b.stoppen())
        self.assertEqual(self.marker(), ["*"], "ende entfernt nur, was vor ihm begann")
        self.aufruf("ende")
        self.assertIsNone(self.marker())

    def test_start_erst_nach_dem_nachlauf_an_der_sperre(self):
        # xdpw wartet nicht auf exec_before: «start» kann nach dem Nachlauf von «ende» ankommen
        self.aufruf("start")
        b = self.beobachten()
        ende = self.hintergrund("ende")
        time.sleep(0.05)
        start = self.verzoegert(4.5, "start")
        self.assertEqual(ende.wait(20), 0)
        self.assertEqual(start.wait(20), 0)
        time.sleep(0.2)
        self.assertNieLeer(b.stoppen())
        self.assertEqual(self.marker(), ["*"])
        self.assertEqual(len(self.eintraege()), 1)
        self.assertNotIn("freigabe beendet", self.ipc())

    def test_neue_wahl_im_nachlauf(self):
        self.aufruf("waehlen")
        self.aufruf("start")
        b = self.beobachten()
        ende = self.hintergrund("ende")
        time.sleep(2.5)
        self.aufruf("waehlen")
        time.sleep(1.5)
        self.assertEqual(self.marker(), ["HEADLESS-1"], "eine frische Wahl hält den Marker")
        self.aufruf("start")
        self.assertEqual(ende.wait(15), 0)
        time.sleep(0.2)
        self.assertNieLeer(b.stoppen())
        self.assertEqual(self.marker(), ["HEADLESS-1"])
        self.assertNotIn("freigabe beendet", self.ipc())
        self.aufruf("ende")
        self.assertIsNone(self.marker())

    def test_zuruecksetzen_im_nachlauf(self):
        self.aufruf("start")
        ende = self.hintergrund("ende")
        time.sleep(0.5)
        ergebnis = self.aufruf("zuruecksetzen")
        self.assertEqual(ergebnis.returncode, 0)
        self.assertIn("Freigabe zurückgesetzt", ergebnis.stderr)
        self.assertIsNone(self.marker(), "Marker sofort weg")
        self.assertEqual(ende.wait(15), 0)
        for name in ("freigabe-ende", "freigabe-eintraege", "freigabe-wahl"):
            self.assertFalse(os.path.exists(self.datei(name)), name)
        # «beendet» nur einmal, vom Zurücksetzen
        self.assertEqual(self.ipc(), ["freigabe gestartet", "freigabe beendet"])

    def test_zuruecksetzen_nennt_das_ende_des_portals(self):
        self.aufruf("start")
        umgebung = dict(self.umgebung, SERVICE_RESULT="signal", EXIT_STATUS="SEGV")
        ergebnis = subprocess.run([self.programm, "zuruecksetzen"], capture_output=True, text=True, env=umgebung,
                                  timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 0)
        self.assertIn("Portal beendet (signal SEGV), Freigabe zurückgesetzt", ergebnis.stderr)
        self.assertIsNone(self.marker())

    def test_wahl_waehrend_einer_freigabe(self):
        # exec_before kommt nur für die erste von gleichzeitigen Freigaben: die Wahl trägt sich selbst ein
        self.aufruf("start")
        self.slurp("HEADLESS-2")
        ergebnis = self.aufruf("waehlen")
        self.assertEqual(ergebnis.stdout, "Monitor: HEADLESS-2\n")
        self.assertEqual(self.marker(), ["*", "HEADLESS-2"])
        self.assertFalse(os.path.exists(self.datei("freigabe-wahl")))
        self.assertEqual(self.aufruf("status").stdout, "aktiv 2\n")
        self.aufruf("ende")
        self.assertIsNone(self.marker(), "exec_after kommt erst nach der letzten")

    def test_gleicher_ausgang_einmal_im_marker(self):
        self.aufruf("waehlen")
        self.aufruf("start")
        self.aufruf("waehlen")
        self.assertEqual(len(self.eintraege()), 2)
        self.assertEqual(self.marker(), ["HEADLESS-1"])

    def test_marker_eines_aelteren_stands(self):
        os.makedirs(self.ordner, mode=0o700)
        with open(self.datei("freigabe"), "w", encoding="utf-8") as f:
            f.write("HEADLESS-1\n")
        self.aufruf("ende")
        self.assertIsNone(self.marker())
        self.assertEqual(self.ipc(), ["freigabe beendet"])

    def test_verwaiste_eintraege_ohne_marker_zaehlen_nicht(self):
        # zenos-sitzung löscht bei der Anmeldung nur den Marker
        os.makedirs(self.ordner, mode=0o700)
        with open(self.datei("freigabe-eintraege"), "w", encoding="utf-8") as f:
            f.write("1 1 HEADLESS-9\n")
        self.aufruf("start")
        self.assertEqual(self.marker(), ["*"])
        self.assertEqual(len(self.eintraege()), 1)

    def test_zuruecksetzen_ohne_freigabe_still_und_schnell(self):
        beginn = time.monotonic()
        ergebnis = self.aufruf("zuruecksetzen")
        dauer = time.monotonic() - beginn
        self.assertEqual((ergebnis.returncode, ergebnis.stdout, ergebnis.stderr), (0, "", ""))
        self.assertLess(dauer, 2)
        self.assertFalse(os.path.exists(self.ordner), "legt ohne Freigabe nichts an")
        os.makedirs(self.ordner, mode=0o700)
        ergebnis = self.aufruf("zuruecksetzen")
        self.assertEqual((ergebnis.returncode, ergebnis.stdout, ergebnis.stderr), (0, "", ""))
        self.assertEqual(self.ipc(), [], "keine Meldung an die Oberfläche")

    def test_wahl_abgebrochen(self):
        self.slurp(None)
        ergebnis = self.aufruf("waehlen")
        self.assertEqual((ergebnis.returncode, ergebnis.stdout), (1, ""))
        self.assertFalse(os.path.exists(self.datei("freigabe-wahl")))
        self.assertEqual(self.ipc(), [])

    def test_wahl_mit_unerwarteter_ausgabe(self):
        self.slurp("HDMI 1; rm -rf ~")
        ergebnis = self.aufruf("waehlen")
        self.assertEqual((ergebnis.returncode, ergebnis.stdout), (1, ""))
        self.assertIn("unerwartete Ausgabe von slurp", ergebnis.stderr)
        self.assertFalse(os.path.exists(self.datei("freigabe-wahl")))
        self.assertEqual(self.ipc(), [])

    def test_unbekannter_befehl(self):
        ergebnis = self.aufruf("irgendwas")
        self.assertEqual(ergebnis.returncode, 2)
        self.assertIn("zenos-freigabe start", ergebnis.stderr)

    def test_ordner_nur_fuer_den_benutzer(self):
        self.aufruf("start")
        self.assertEqual(os.stat(self.ordner).st_mode & 0o777, 0o700)

    def test_stempel_ueber_doppel_fork_und_sh_c_wie_xdpw(self):
        # Startzeit und PID von sh (dash führt den Befehl in einem Kindprozess aus) ordnen die Aufrufe so,
        # wie xdpw sie gestartet hat, egal, welches Skript zuerst an die Sperre kommt
        self.xdpw("start")
        self.assertTrue(self.warten(lambda: self.marker() == ["*"]))
        time.sleep(0.2)
        self.xdpw("ende")
        zweiter = self.xdpw("start")
        self.assertTrue(self.warten(lambda: not self._laufende(), 15), "Aufrufe enden nicht")
        self.assertEqual(self.marker(), ["*"])
        eintraege = self.eintraege()
        self.assertEqual(len(eintraege), 1, eintraege)
        self.assertEqual(eintraege[0].split()[1], str(zweiter), "Eintrag trägt die PID von sh")
        self.assertFalse(os.path.exists(self.datei("freigabe-ende")))

    def test_ohne_oberflaeche_mit_echtem_zenos_ipc(self):
        # Das Skript im Repo mit dem echten zenos-ipc: Im eigenen XDG_RUNTIME_DIR läuft keine Oberfläche,
        # zenos-ipc endet sofort, und nichts blockiert das Portal
        beginn = time.monotonic()
        ergebnis = self.aufruf("waehlen", programm=FREIGABE)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        self.assertEqual(ergebnis.stdout, "Monitor: HEADLESS-1\n")
        self.assertEqual(self.aufruf("start", programm=FREIGABE).returncode, 0)
        self.assertLess(time.monotonic() - beginn, 5)
        self.assertEqual(self.marker(), ["HEADLESS-1"])
        beginn = time.monotonic()
        self.assertEqual(self.aufruf("ende", programm=FREIGABE).returncode, 0)
        self.assertLess(time.monotonic() - beginn, 8)
        self.assertIsNone(self.marker())
        self.assertEqual(self.ipc(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
