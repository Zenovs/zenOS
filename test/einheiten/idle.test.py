#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-idle (Sperre und Bildschirm aus über swayidle, Hemmer für die Ein/Aus-Taste).

Ohne Sitzung und ohne echtes swayidle: Jeder Test hat einen eigenen Baum mit einer Kopie von zenos-idle, daneben
Attrappen von zenos-bildschirm und zen, dazu falsche swayidle und systemd-inhibit im PATH. Alle Attrappen schreiben ihre
Aufrufe der Reihe nach in eine gemeinsame Datei. Geprüft werden die Argumente für swayidle (Reihenfolge, Sekunden,
resume), «an» beim Start, der Neustart nur bei geänderten Zeiten, SIGUSR1 und SIGTERM, der neue Stand nach einem Update
(nur gesperrt), der Hemmer «handle-power-key» (nur ausser bei «ausschalten», kein verwaister Prozess nach einem Wechsel
oder dem Ende), die unveränderte Ausgabe von «pruefen» und der Abgleich der Grenzen und Wörter mit zustandslogik.js,
energie.js (über node, falls vorhanden) und dem Schema. Läuft unter Linux (GNU stat, /proc).

  python3 test/einheiten/idle.test.py
"""

import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IDLE = os.path.join(WURZEL, "scripts", "bin", "zenos-idle")
LOGIK = os.path.join(WURZEL, "shell", "modi", "zustandslogik.js")
ENERGIE = os.path.join(WURZEL, "shell", "dienste", "energie.js")
SCHEMA = os.path.join(WURZEL, "config", "schema", "einstellungen.schema.json")

# Attrappe: schreibt {"wer", "argv"} als JSON-Zeile; swayidle meldet dazu Signale und wartet
ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, signal, sys, time
WER = %r
def schreiben(eintrag):
    eintrag.update({"wer": WER, "pid": os.getpid()})
    with open(os.environ["IDLE_TEST_LOG"], "a", encoding="utf-8") as f:
        f.write(json.dumps(eintrag) + "\n")
schreiben({"argv": sys.argv[1:]})
if WER == "bildschirm" and sys.argv[1:] == ["status"]:
    try:
        with open(os.environ["IDLE_TEST_STATUS"], encoding="utf-8") as f:
            print(f.read().strip())
    except OSError:
        print("an")
if WER == "inhibit":
    # Wie systemd-inhibit: den Befehl nach den Optionen als Kind starten und auf ihn warten (ohne Todessignal: Endet
    # die Attrappe, bliebe das Kind, ausser zenos-idle räumt es weg). inhibit.exit lässt den Hemmer scheitern.
    import subprocess
    try:
        with open(os.environ["IDLE_TEST_LOG"] + ".inhibit-exit", encoding="utf-8") as f:
            sys.exit(int(f.read().strip()))
    except OSError:
        pass
    argv = sys.argv[1:]
    befehl = argv[next(i for i, a in enumerate(argv) if not a.startswith("--")):]
    sys.exit(subprocess.call(befehl))
if WER == "swayidle":
    def usr1(*_):
        schreiben({"signal": "USR1"})
    def term(*_):
        schreiben({"signal": "TERM"})
        sys.exit(0)
    signal.signal(signal.SIGUSR1, usr1)
    signal.signal(signal.SIGTERM, term)
    while True:
        time.sleep(0.05)
'''


def node_da():
    return shutil.which("node") is not None


class IdleTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-idle-test.")
        self.bau(self.wurzel)

    def bau(self, wurzel):
        self.bin = os.path.join(wurzel, "scripts", "bin")
        self.fake = os.path.join(wurzel, "fake")
        self.home = os.path.join(wurzel, "home")
        self.lz = os.path.join(wurzel, "run")
        for ordner in (self.bin, self.fake, os.path.join(self.home, ".config", "zenos"), self.lz):
            os.makedirs(ordner, exist_ok=True)
        os.chmod(self.lz, 0o700)
        self.programm = os.path.join(self.bin, "zenos-idle")
        shutil.copy2(IDLE, self.programm)
        self.bildschirm = os.path.join(self.bin, "zenos-bildschirm")
        self.zen = os.path.join(wurzel, "scripts", "zen")
        self.attrappe(self.bildschirm, "bildschirm")
        self.attrappe(self.zen, "zen")
        self.attrappe(os.path.join(self.fake, "swayidle"), "swayidle")
        self.attrappe(os.path.join(self.fake, "systemd-inhibit"), "inhibit")
        self.log = os.path.join(wurzel, "ereignisse")
        self.status = os.path.join(wurzel, "status")
        self.einstellungen = os.path.join(self.home, ".config", "zenos", "einstellungen.json")
        self.umgebung = {
            "PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": self.home,
            "XDG_RUNTIME_DIR": self.lz,
            "WAYLAND_DISPLAY": "wayland-test",
            "LANG": "C.UTF-8",
            "IDLE_TEST_LOG": self.log,
            "IDLE_TEST_STATUS": self.status,
            "ZENOS_IDLE_INTERVALL": "1",
        }
        self.prozess = None

    def tearDown(self):
        if self.prozess:
            if self.prozess.poll() is None:
                try:
                    os.killpg(self.prozess.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.prozess.wait(5)
            self.prozess.stdout.close()
            self.prozess.stderr.close()
        # Übrige Attrappen und Kinder des Hemmers (nur Prozesse aus diesem Testordner)
        for pid in self.hemmer_kinder():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for eintrag in self.ereignisse():
            if eintrag.get("wer") not in ("swayidle", "inhibit"):
                continue
            try:
                with open(f"/proc/{eintrag['pid']}/cmdline", "rb") as f:
                    if self.wurzel.encode() not in f.read():
                        continue
                os.kill(eintrag["pid"], signal.SIGKILL)
            except (OSError, ProcessLookupError):
                pass
        shutil.rmtree(self.wurzel, ignore_errors=True)

    # --- Hilfen

    def attrappe(self, pfad, wer):
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(ATTRAPPE % wer)
        os.chmod(pfad, 0o755)

    def schreiben(self, daten):
        text = daten if isinstance(daten, str) else json.dumps(daten)
        # atomar ersetzen wie die Oberfläche (neue Inode)
        tmp = self.einstellungen + ".neu"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, self.einstellungen)

    def aufruf(self, *args):
        ergebnis = subprocess.run([self.programm, *args], capture_output=True, text=True, env=self.umgebung,
                                  timeout=30, check=False)
        return ergebnis.returncode, ergebnis.stdout, ergebnis.stderr

    def ereignisse(self):
        try:
            with open(self.log, encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except OSError:
            return []

    def starts(self):
        return [e for e in self.ereignisse() if e["wer"] == "swayidle" and "argv" in e]

    def hemmer(self):
        return [e for e in self.ereignisse() if e["wer"] == "inhibit"]

    def hemmer_kinder(self):
        """Laufende «tail --pid=<zenos-idle>» (die Kinder des Hemmers) dieses Tests."""
        if not self.prozess:
            return []
        gefunden = []
        for eintrag in os.listdir("/proc"):
            if not eintrag.isdigit():
                continue
            try:
                with open(f"/proc/{eintrag}/cmdline", "rb") as f:
                    argv = f.read().split(b"\0")
                with open(f"/proc/{eintrag}/stat", encoding="utf-8") as f:
                    zustand = f.read().rsplit(")", 1)[1].split()[0]
            except OSError:
                continue
            if zustand != "Z" and argv[:2] == [b"tail", f"--pid={self.prozess.pid}".encode()]:
                gefunden.append(int(eintrag))
        return gefunden

    def erwarteter_hemmer(self):
        return ["--what=handle-power-key", "--mode=block", "--who=zenOS",
                "--why=Ein/Aus-Taste: zenOS sperrt (Einstellung «Ein/Aus-Taste»)", "tail",
                f"--pid={self.prozess.pid}", "-f", "/dev/null"]

    def warten(self, bedingung, frist=10.0):
        ende = time.monotonic() + frist
        while time.monotonic() < ende:
            wert = bedingung()
            if wert:
                return wert
            time.sleep(0.05)
        return bedingung()

    def starten(self):
        self.prozess = subprocess.Popen([self.programm], env=self.umgebung, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.assertTrue(self.warten(lambda: len(self.starts()) >= 1), "swayidle startet nicht")
        return self.starts()[-1]

    def erwartete_argumente(self, sperre, bildschirm):
        lock = f"{self.zen} lock"
        return ["-w", "timeout", str((sperre + bildschirm) * 60), f"{self.bildschirm} aus", "resume",
                f"{self.bildschirm} an", "before-sleep", lock, "lock", lock, "timeout", str(sperre * 60), lock]

    # --- pruefen, energie, minuten

    def test_pruefen_format_unveraendert(self):
        faelle = [
            (None, "5 standard"),
            ({}, "5 standard"),
            ({"sperreNachMinuten": 7}, "7 einstellung"),
            ({"sperreNachMinuten": 7, "bildschirmAusNachSperre": 4}, "7 einstellung"),
            ({"sperreNachMinuten": 30}, "15 begrenzt"),
            ({"sperreNachMinuten": 0}, "1 begrenzt"),
            ({"sperreNachMinuten": "7,4"}, "7 einstellung"),
            ({"sperreNachMinuten": "aus"}, "5 ungueltig"),
            ({"sperreNachMinuten": True}, "5 ungueltig"),
            ("{kaputt", "5 ungueltig"),
            ("[]", "5 standard"),
        ]
        for daten, erwartet in faelle:
            with self.subTest(daten=daten):
                if daten is None:
                    if os.path.exists(self.einstellungen):
                        os.unlink(self.einstellungen)
                else:
                    self.schreiben(daten)
                code, aus, fehler = self.aufruf("pruefen")
                self.assertEqual((code, aus, fehler), (0, erwartet + "\n", ""))

    def test_energie_werte(self):
        rest = "ausschalten 60 standard\nausschaltenwenn akku standard\ntaste sperren standard\n"
        faelle = [
            (None, "sperre 5 standard\nbildschirm 1 standard\n" + rest),
            ({"bildschirmAusNachSperre": 3}, "sperre 5 standard\nbildschirm 3 einstellung\n" + rest),
            ({"sperreNachMinuten": 2, "bildschirmAusNachSperre": 0}, "sperre 2 einstellung\nbildschirm 1 begrenzt\n" + rest),
            ({"bildschirmAusNachSperre": 25}, "sperre 5 standard\nbildschirm 10 begrenzt\n" + rest),
            ({"bildschirmAusNachSperre": "4,4"}, "sperre 5 standard\nbildschirm 4 einstellung\n" + rest),
            ({"bildschirmAusNachSperre": "nie"}, "sperre 5 standard\nbildschirm 1 ungueltig\n" + rest),
            ({"bildschirmAusNachSperre": None}, "sperre 5 standard\nbildschirm 1 ungueltig\n" + rest),
            ({"bildschirmAusNachSperre": False}, "sperre 5 standard\nbildschirm 1 ungueltig\n" + rest),
            ("nicht json", "sperre 5 ungueltig\nbildschirm 1 ungueltig\nausschalten 60 ungueltig\n"
                           "ausschaltenwenn akku ungueltig\ntaste sperren ungueltig\n"),
        ]
        for daten, erwartet in faelle:
            with self.subTest(daten=daten):
                if daten is not None:
                    self.schreiben(daten)
                self.assertEqual(self.aufruf("energie"), (0, erwartet, ""))

    def test_energie_ausschalten_und_taste(self):
        def werte(daten):
            self.schreiben(daten)
            code, aus, fehler = self.aufruf("energie")
            self.assertEqual((code, fehler), (0, ""))
            return {z.split()[0]: tuple(z.split()[1:]) for z in aus.splitlines()}

        faelle = [
            ({"ausschalten": "nie", "ausschaltenNachMinuten": 90, "einAusTaste": "menue"},
             {"ausschalten": ("90", "einstellung"), "ausschaltenwenn": ("nie", "einstellung"),
              "taste": ("menue", "einstellung")}),
            ({"ausschalten": "immer", "ausschaltenNachMinuten": 10, "einAusTaste": "ausschalten"},
             {"ausschalten": ("30", "begrenzt"), "ausschaltenwenn": ("immer", "einstellung"),
              "taste": ("ausschalten", "einstellung")}),
            ({"ausschaltenNachMinuten": 999}, {"ausschalten": ("240", "begrenzt")}),
            ({"ausschaltenNachMinuten": "120"}, {"ausschalten": ("120", "einstellung")}),
            ({"ausschaltenNachMinuten": "2 Std."}, {"ausschalten": ("60", "ungueltig")}),
            ({"ausschalten": "Immer", "einAusTaste": "menü"},
             {"ausschaltenwenn": ("akku", "ungueltig"), "taste": ("sperren", "ungueltig")}),
            ({"ausschalten": True, "einAusTaste": ["sperren"]},
             {"ausschaltenwenn": ("akku", "ungueltig"), "taste": ("sperren", "ungueltig")}),
            ({"ausschalten": "nie; reboot", "einAusTaste": "sperren menue"},
             {"ausschaltenwenn": ("akku", "ungueltig"), "taste": ("sperren", "ungueltig")}),
        ]
        for daten, erwartet in faelle:
            with self.subTest(daten=daten):
                ergebnis = werte(daten)
                for name, wert in erwartet.items():
                    self.assertEqual(ergebnis[name], wert, name)

    def test_minuten_und_unbekannter_befehl(self):
        self.schreiben({"sperreNachMinuten": 12})
        self.assertEqual(self.aufruf("minuten"), (0, "12\n", ""))
        code, aus, fehler = self.aufruf("bildschirm")
        self.assertEqual((code, aus), (2, ""))
        self.assertIn("energie", fehler)

    # --- laufen

    def test_argumente_fuer_swayidle(self):
        start = self.starten()
        self.assertEqual(start["argv"], self.erwartete_argumente(5, 1))

    def test_werte_aus_den_einstellungen(self):
        self.schreiben({"sperreNachMinuten": 3, "bildschirmAusNachSperre": 4})
        self.assertEqual(self.starten()["argv"], self.erwartete_argumente(3, 4))

    def test_sperre_zuletzt_bildschirm_zuerst(self):
        # swayidle stellt Timeouts vorne in seine Liste: SIGUSR1 löst die Sperre damit vor «Bildschirm aus» aus
        argv = self.starten()["argv"]
        timeouts = [argv[i + 2] for i, wert in enumerate(argv) if wert == "timeout"]
        self.assertEqual(timeouts, [f"{self.bildschirm} aus", f"{self.zen} lock"])
        self.assertGreater(int(argv[2]), int(argv[-2]))
        self.assertEqual(argv[argv.index(f"{self.bildschirm} aus") + 1:argv.index(f"{self.bildschirm} aus") + 3],
                         ["resume", f"{self.bildschirm} an"])

    def test_bildschirm_an_beim_start(self):
        self.starten()
        ereignisse = self.ereignisse()
        erster_start = next(i for i, e in enumerate(ereignisse) if e["wer"] == "swayidle")
        an = [i for i, e in enumerate(ereignisse) if e["wer"] == "bildschirm" and e["argv"] == ["an"]]
        self.assertTrue(an and an[0] < erster_start, ereignisse)

    def test_neustart_nur_bei_geaenderten_werten(self):
        self.schreiben({"sperreNachMinuten": 5})
        self.starten()
        # Fremde Schlüssel und Energie-Schlüssel, die zenos-idle nicht betrifft: kein Neustart
        self.schreiben({"sperreNachMinuten": 5, "name": "Beispiel", "ausschalten": "nie", "einAusTaste": "menue"})
        time.sleep(2.5)
        self.schreiben({"sperreNachMinuten": 5, "bildschirmAusNachSperre": 1, "ausschaltenNachMinuten": 30})
        time.sleep(2.5)
        self.assertEqual(len(self.starts()), 1)
        # Bildschirm geändert: Neustart mit neuen Sekunden, das alte swayidle bekommt TERM (resume)
        self.schreiben({"sperreNachMinuten": 5, "bildschirmAusNachSperre": 3})
        self.assertTrue(self.warten(lambda: len(self.starts()) >= 2))
        self.assertEqual(self.starts()[-1]["argv"], self.erwartete_argumente(5, 3))
        alt = self.starts()[0]["pid"]
        self.assertTrue(any(e.get("signal") == "TERM" and e["pid"] == alt for e in self.ereignisse()))
        # Sperre geändert: ebenso
        self.schreiben({"sperreNachMinuten": 9, "bildschirmAusNachSperre": 3})
        self.assertTrue(self.warten(lambda: len(self.starts()) >= 3))
        self.assertEqual(self.starts()[-1]["argv"], self.erwartete_argumente(9, 3))
        self.assertIsNone(self.prozess.poll())

    def test_usr1_wird_weitergereicht(self):
        start = self.starten()
        os.kill(self.prozess.pid, signal.SIGUSR1)
        self.assertTrue(self.warten(lambda: any(e.get("signal") == "USR1" and e["pid"] == start["pid"]
                                                for e in self.ereignisse())))
        time.sleep(1.5)
        self.assertIsNone(self.prozess.poll(), "zenos-idle hat sich bei USR1 beendet")
        self.assertEqual(len(self.starts()), 1)
        # zweimal hintereinander geht auch
        os.kill(self.prozess.pid, signal.SIGUSR1)
        self.assertTrue(self.warten(lambda: sum(e.get("signal") == "USR1" for e in self.ereignisse()) >= 2))

    def test_term_beendet_beide(self):
        start = self.starten()
        self.assertTrue(self.warten(lambda: self.hemmer_kinder()), "kein Hemmer")
        self.prozess.send_signal(signal.SIGTERM)
        self.assertEqual(self.prozess.wait(10), 0)
        self.assertTrue(self.warten(lambda: any(e.get("signal") == "TERM" and e["pid"] == start["pid"]
                                                for e in self.ereignisse())))
        self.assertTrue(self.warten(lambda: not self.hemmer_kinder()), "Hemmer verwaist")

    # --- Hemmer für die Ein/Aus-Taste

    def test_hemmer_ausser_bei_ausschalten(self):
        self.starten()
        self.assertTrue(self.warten(lambda: self.hemmer()), "kein Hemmer bei «sperren»")
        self.assertEqual(self.hemmer()[0]["argv"], self.erwarteter_hemmer())
        self.assertTrue(self.warten(lambda: len(self.hemmer_kinder()) == 1))
        # Auf «ausschalten»: Hemmer weg, ohne verwaiste Prozesse, swayidle läuft weiter (kein Neustart)
        self.schreiben({"einAusTaste": "ausschalten"})
        self.assertTrue(self.warten(lambda: not self.hemmer_kinder()), "Hemmer nach dem Wechsel noch da")
        time.sleep(2.5)
        self.assertEqual(len(self.hemmer()), 1)
        self.assertEqual(len(self.starts()), 1)
        # Zurück auf «menue»: wieder genau ein Hemmer
        self.schreiben({"einAusTaste": "menue"})
        self.assertTrue(self.warten(lambda: len(self.hemmer()) == 2 and len(self.hemmer_kinder()) == 1))
        self.assertEqual(len(self.starts()), 1)
        self.assertIn("Ein/Aus-Taste: menue (Hemmer handle-power-key)", self.ende_der_ausgabe())

    def test_kein_hemmer_bei_ausschalten_von_anfang_an(self):
        self.schreiben({"einAusTaste": "ausschalten"})
        self.starten()
        time.sleep(2.5)
        self.assertEqual(self.hemmer(), [])
        self.assertEqual(self.hemmer_kinder(), [])

    def test_hemmer_scheitert_ohne_folgen(self):
        # polkit lehnt ab: zenos-idle läuft weiter, meldet es einmal und versucht es später still erneut
        with open(self.log + ".inhibit-exit", "w", encoding="utf-8") as f:
            f.write("1\n")
        self.starten()
        time.sleep(3.5)
        self.assertIsNone(self.prozess.poll())
        self.assertEqual(len(self.hemmer()), 1)
        self.assertEqual(len(self.starts()), 1)
        self.prozess.send_signal(signal.SIGTERM)
        self.assertEqual(self.prozess.wait(10), 0)
        fehler = self.prozess.stderr.read()
        self.assertEqual(fehler.count("Hemmer für die Ein/Aus-Taste beendet (Exit 1"), 1, fehler)

    def test_hemmer_endet_mit_zenos_idle_auch_nach_sigkill(self):
        self.starten()
        self.assertTrue(self.warten(lambda: len(self.hemmer_kinder()) == 1))
        # SIGKILL: keine Falle in zenos-idle räumt auf, tail --pid merkt das Ende trotzdem (spätestens nach 1 s)
        os.kill(self.prozess.pid, signal.SIGKILL)
        self.prozess.wait(5)
        self.assertTrue(self.warten(lambda: not self.hemmer_kinder(), 5), "tail lebt nach dem Ende von zenos-idle weiter")

    def test_ohne_bildschirm_helfer_nur_die_sperre(self):
        os.unlink(self.bildschirm)
        argv = self.starten()["argv"]
        lock = f"{self.zen} lock"
        self.assertEqual(argv, ["-w", "before-sleep", lock, "lock", lock, "timeout", "300", lock])

    def test_neuer_stand_erst_gesperrt_und_hell(self):
        self.starten()
        # Update ohne Sperre: weiterlaufen (ein Neustart schöbe die automatische Sperre hinaus)
        with open(self.bildschirm, "a", encoding="utf-8") as f:
            f.write("# neuer Stand\n")
        time.sleep(2.5)
        self.assertIsNone(self.prozess.poll())
        # gesperrt, aber dunkel: weiter warten
        os.makedirs(os.path.join(self.lz, "zenos"), exist_ok=True)
        with open(os.path.join(self.lz, "zenos", "gesperrt"), "w", encoding="utf-8") as f:
            f.write("2026-10-05T20:00:00+02:00\n")
        with open(self.status, "w", encoding="utf-8") as f:
            f.write("aus\n")
        time.sleep(2.5)
        self.assertIsNone(self.prozess.poll())
        # gesperrt und hell: neu starten (systemd startet den Dienst wieder)
        with open(self.status, "w", encoding="utf-8") as f:
            f.write("an\n")
        self.assertEqual(self.prozess.wait(10), 0)
        self.assertIn("Neuer Stand", self.prozess.stdout.read())
        start = self.starts()[0]
        self.assertTrue(any(e.get("signal") == "TERM" and e["pid"] == start["pid"] for e in self.ereignisse()))

    def test_unsicherer_pfad_kommt_nicht_in_die_shell(self):
        # swayidle führt Befehle über sh aus: Pfade mit Leerzeichen oder Sonderzeichen nie weitergeben
        shutil.rmtree(self.wurzel)
        self.wurzel = tempfile.mkdtemp(prefix="zenos-idle-test.")
        self.bau(os.path.join(self.wurzel, "a b;$(x)"))
        self.attrappe(os.path.join(self.fake, "zen"), "zen-path")
        argv = self.starten()["argv"]
        self.assertEqual(argv, ["-w", "before-sleep", "zen lock", "lock", "zen lock", "timeout", "300", "zen lock"])
        self.assertNotIn("a b", " ".join(argv))

    def ende_der_ausgabe(self):
        self.prozess.send_signal(signal.SIGTERM)
        self.prozess.wait(10)
        return self.prozess.stdout.read()

    # --- Abgleich

    def test_grenzen_wie_leitplanken_und_schema(self):
        with open(IDLE, encoding="utf-8") as f:
            skript = f.read()
        werte = {k: int(v) for k, v in
                 re.findall(r"\b((?:BILDSCHIRM_|AUSSCHALTEN_)?(?:STANDARD|MINIMUM|MAXIMUM))=(\d+)", skript)}
        with open(LOGIK, encoding="utf-8") as f:
            logik = {k: int(v) for k, v in re.findall(r"^\s*(\w+): (\d+),?$", f.read(), re.M)}
        with open(SCHEMA, encoding="utf-8") as f:
            schema = json.load(f)["properties"]
        self.assertEqual((werte["MINIMUM"], werte["MAXIMUM"], werte["STANDARD"]),
                         (logik["sperreMinutenMin"], logik["sperreMinutenMax"], logik["sperreMinutenStandard"]))
        self.assertEqual((werte["BILDSCHIRM_MINIMUM"], werte["BILDSCHIRM_MAXIMUM"], werte["BILDSCHIRM_STANDARD"]),
                         (logik["bildschirmAusNachSperreMin"], logik["bildschirmAusNachSperreMax"],
                          logik["bildschirmAusNachSperreStandard"]))
        self.assertEqual((schema["sperreNachMinuten"]["minimum"], schema["sperreNachMinuten"]["maximum"]),
                         (werte["MINIMUM"], werte["MAXIMUM"]))
        self.assertEqual((schema["bildschirmAusNachSperre"]["minimum"], schema["bildschirmAusNachSperre"]["maximum"]),
                         (werte["BILDSCHIRM_MINIMUM"], werte["BILDSCHIRM_MAXIMUM"]))
        self.assertEqual((werte["AUSSCHALTEN_MINIMUM"], werte["AUSSCHALTEN_MAXIMUM"], werte["AUSSCHALTEN_STANDARD"]),
                         (logik["ausschaltenMinutenMin"], logik["ausschaltenMinutenMax"],
                          logik["ausschaltenMinutenStandard"]))
        self.assertEqual((schema["ausschaltenNachMinuten"]["minimum"], schema["ausschaltenNachMinuten"]["maximum"]),
                         (werte["AUSSCHALTEN_MINIMUM"], werte["AUSSCHALTEN_MAXIMUM"]))
        # Wörter: dieselben wie im Schema, das erste ist der Standard wie in energie.js
        woerter = dict(re.findall(r'\b(AUSSCHALTEN_WENN|TASTE)="([a-z ]+)"', skript))
        with open(ENERGIE, encoding="utf-8") as f:
            js = f.read()
        standard = dict(re.findall(r"^\s*(ausschalten|einAusTaste): \"(\w+)\"", js, re.M))
        self.assertEqual(sorted(woerter["AUSSCHALTEN_WENN"].split()), sorted(schema["ausschalten"]["enum"]))
        self.assertEqual(sorted(woerter["TASTE"].split()), sorted(schema["einAusTaste"]["enum"]))
        self.assertEqual(woerter["AUSSCHALTEN_WENN"].split()[0], standard["ausschalten"])
        self.assertEqual(woerter["TASTE"].split()[0], standard["einAusTaste"])

    @unittest.skipUnless(node_da(), "node fehlt")
    def test_auswertung_wie_energie_js(self):
        vektoren = [1, 5, 10, 0, -3, 11, 2.4, 2.5, 9.6, "4", " 7 ", "2,5", "2.5", ".5", "5.", "+3", "-2", None, True,
                    False, "", "aus", "1e1", "0x5", "1_0", [5], {"wert": 5}, 1e308]
        programm = r"""
const fs = require("fs"), vm = require("vm");
const [logik, energie, vektoren] = process.argv.slice(1);
const Z = vm.createContext({});
vm.runInContext(fs.readFileSync(logik, "utf8").replace(/^\.pragma library\s*$/m, ""), Z);
const E = vm.createContext({ Logik: Z });
vm.runInContext(fs.readFileSync(energie, "utf8").replace(/^\.pragma library\s*$/m, "").replace(/^\.import .*$/gm, ""), E);
console.log(JSON.stringify(JSON.parse(vektoren).map((v) => [E.bildschirmMinuten(v), Z.sperreMinuten(v)])));
"""
        ergebnis = subprocess.run(["node", "-e", programm, LOGIK, ENERGIE, json.dumps(vektoren)], capture_output=True,
                                  text=True, timeout=30, check=True)
        js = json.loads(ergebnis.stdout)
        for wert, (bildschirm_js, sperre_js) in zip(vektoren, js):
            with self.subTest(wert=wert):
                self.schreiben({"sperreNachMinuten": wert, "bildschirmAusNachSperre": wert})
                code, aus, _ = self.aufruf("energie")
                self.assertEqual(code, 0)
                zeilen = dict(z.split(" ", 1) for z in aus.splitlines())
                self.assertEqual(int(zeilen["bildschirm"].split()[0]), bildschirm_js)
                # Die Sperre liest Text wie bisher etwas grosszügiger (float), Zahlen aber gleich wie die Oberfläche
                if not isinstance(wert, str):
                    self.assertEqual(int(zeilen["sperre"].split()[0]), sperre_js)

    def test_keine_shell_im_skript(self):
        with open(IDLE, encoding="utf-8") as f:
            zeilen = [z for z in f if not z.lstrip().startswith("#")]
        text = "".join(zeilen)
        self.assertNotRegex(text, r"\b(?:ba)?sh\s+-c\b")
        self.assertNotRegex(text, r"\beval\b")


if __name__ == "__main__":
    unittest.main()
