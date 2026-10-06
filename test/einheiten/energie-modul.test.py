#!/usr/bin/env python3
"""Einheitentests für den Energie-Teil von install.sh und zen doctor: der Neustart von zenos-idle nach einem Update
(scripts/module/65-oberflaeche.sh, _oberflaeche_idle_neu_laden) und der Abschnitt «Energie» von zen doctor
(scripts/doctor.d/66-energie.sh).

Ohne Sitzung: Jeder Test hat einen eigenen Baum mit Attrappen von zenos-idle, zenos-bildschirm und zenos-energie, dazu
falsche systemctl, busctl und wlopm im PATH. systemctl meldet die Startzeit von zenos-idle und schreibt «try-restart»
auf; die Attrappen der Helfer geben aus, was der Test vorgibt. Der Laufzeitordner hat einen echten Socket «bus».
Geprüft wird vor allem: zenos-idle startet nur gesperrt, mit neuerem Code und bei hellem Bildschirm neu (sonst
leuchtete die Sperre nach dem resume von swayidle), ein zweiter Lauf startet nichts mehr neu, und zen doctor sagt
ohne Akku ehrlich, dass «Im Akkubetrieb» nie greift. Linux (GNU stat), nicht als root:

  python3 test/einheiten/energie-modul.test.py
"""

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODUL = os.path.join(WURZEL, "scripts", "module", "65-oberflaeche.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "66-energie.sh")

# Attrappe: schreibt {"wer", "argv"} als JSON-Zeile in <ORDNER>/ereignisse. Verhalten aus Dateien im Testordner:
#   <wer>.aus.<unter> / <wer>.aus      Ausgabe (unter: erstes Argument ohne «-», bei systemctl nach «--user»)
#   <wer>.exit.<unter> / <wer>.exit    Exit-Code (Standard 0)
#   <wer>.exit.<einheit>               nur systemctl is-active: Exit je Einheit (Standard 3: inaktiv)
ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, sys
WER = %r
ORDNER = os.environ["MODUL_TEST"]
argv = sys.argv[1:]
def datei(name):
    try:
        with open(os.path.join(ORDNER, WER + "." + name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"wer": WER, "argv": argv}) + "\n")
unter = next((a for a in argv if not a.startswith("-")), "")
if WER == "systemctl" and unter == "is-active":
    code = datei("exit." + argv[-1])
    sys.exit(int(code) if code is not None else 3)
aus = datei("aus." + unter)
aus = aus if aus is not None else datei("aus")
if aus is not None:
    print(aus, end="")
code = datei("exit." + unter)
sys.exit(int(code if code is not None else datei("exit") or 0))
'''

# Ausgaben von zen doctor als Liste «art: text»
DOCTOR_TEIL = r"""
abschnitt() { :; }
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$1"
shift
for teil in "$@"; do "$teil"; done
"""

MODUL_TEIL = r"""
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
aenderung() { printf 'aenderung: %s\n' "$*"; }
source "$1"
shift
"$@"
"""

STANDARD_ENERGIE = ("sperre 5 standard\nbildschirm 1 standard\nausschalten 60 standard\n"
                    "ausschaltenwenn akku standard\ntaste sperren standard\n")


@unittest.skipUnless(sys.platform.startswith("linux"), "nur unter Linux (GNU stat, bash 5)")
@unittest.skipIf(os.geteuid() == 0, "Benutzerteile und zen doctor laufen hier als Benutzer")
class EnergieModulTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-energie-modul-test.")
        self.code = os.path.join(self.wurzel, "code")
        self.bin = os.path.join(self.code, "scripts", "bin")
        self.doctor_bin = os.path.join(self.wurzel, "system", "opt", "zenos", "scripts", "bin")
        self.fake = os.path.join(self.wurzel, "fake")
        self.home = os.path.join(self.wurzel, "home")
        self.lz = os.path.join(self.wurzel, "run-user")
        self.geraet = os.path.join(self.wurzel, "system", "run", "zenos", "geraet.json")
        for ordner in (self.bin, self.doctor_bin, self.fake, self.home, os.path.join(self.lz, "zenos"),
                       os.path.dirname(self.geraet)):
            os.makedirs(ordner, exist_ok=True)
        os.chmod(self.lz, 0o700)
        for ordner in (self.bin, self.doctor_bin):
            self.attrappe(os.path.join(ordner, "zenos-idle"), "idle")
            self.attrappe(os.path.join(ordner, "zenos-bildschirm"), "bildschirm")
            self.attrappe(os.path.join(ordner, "zenos-energie"), "energie")
        for name in ("systemctl", "busctl", "wlopm"):
            self.attrappe(os.path.join(self.fake, name), name)
        self.verhalten("idle", "aus", STANDARD_ENERGIE)
        self.verhalten("bildschirm", "aus", "an\n")
        self.verhalten("energie", "aus", "ja\n")
        self.bus = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.bus.bind(os.path.join(self.lz, "bus"))
        self.umgebung = {
            "PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": self.home,
            "XDG_RUNTIME_DIR": self.lz,
            "LANG": "C.UTF-8",
            "MODUL_TEST": self.wurzel,
            "ZENOS_CODE": self.code,
            "ZENOS_DOCTOR_TESTWURZEL": os.path.join(self.wurzel, "system"),
        }

    def tearDown(self):
        self.bus.close()
        shutil.rmtree(self.wurzel, ignore_errors=True)

    # --- Hilfen

    def attrappe(self, pfad, wer):
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(ATTRAPPE % wer)
        os.chmod(pfad, 0o755)

    def verhalten(self, wer, art, inhalt):
        with open(os.path.join(self.wurzel, f"{wer}.{art}"), "w", encoding="utf-8") as f:
            f.write(inhalt)

    def vergessen(self, *dateien):
        for datei in dateien:
            pfad = os.path.join(self.wurzel, datei)
            if os.path.exists(pfad):
                os.remove(pfad)

    def ereignisse(self):
        try:
            with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def aufrufe(self, wer):
        return [e["argv"] for e in self.ereignisse() if e["wer"] == wer]

    def bash(self, programm, *argumente):
        lauf = subprocess.run(["bash", "-c", programm, "test", *argumente], capture_output=True, text=True,
                              env=self.umgebung, timeout=60, check=False)
        self.assertEqual(lauf.stderr, "")
        return [z for z in lauf.stdout.splitlines() if z.strip()]

    def gesperrt(self, ja=True):
        marker = os.path.join(self.lz, "zenos", "gesperrt")
        if ja:
            with open(marker, "w", encoding="utf-8") as f:
                f.write("2026-10-05T20:00:00+02:00\n")
        elif os.path.exists(marker):
            os.remove(marker)

    def code_alter(self, sekunden_vor_dem_start):
        """zenos-idle läuft seit jetzt; der Code ist so viele Sekunden älter (negativ: neuer)."""
        start = int(time.time()) - 100
        self.verhalten("systemctl", "aus.show", f"@{start}\n")
        zeit = start - sekunden_vor_dem_start
        for name in ("zenos-idle", "zenos-bildschirm"):
            os.utime(os.path.join(self.bin, name), (zeit, zeit))
        return start

    # --- 65-oberflaeche: zenos-idle nach einem Update neu starten

    def neu_laden(self):
        return self.bash(MODUL_TEIL, MODUL, "_oberflaeche_idle_neu_laden", self.lz)

    def neustarts(self):
        return [a for a in self.aufrufe("systemctl") if "try-restart" in a]

    def test_kein_neuer_code_nichts(self):
        self.code_alter(50)
        self.gesperrt()
        self.assertEqual(self.neu_laden(), [])
        self.assertEqual(self.neustarts(), [])
        self.assertEqual(self.aufrufe("bildschirm"), [])

    def test_ungesperrt_nie_neu_starten(self):
        # Ein Neustart beginnt die Leerlaufzeit von vorn und schöbe die automatische Sperre hinaus
        self.code_alter(-50)
        self.gesperrt(False)
        ausgabe = self.neu_laden()
        self.assertEqual(self.neustarts(), [])
        self.assertEqual(len(ausgabe), 1)
        self.assertTrue(ausgabe[0].startswith("info: Automatische Sperre geändert; zenos-idle übernimmt den neuen "
                                              "Stand bei der nächsten Sperre (ein Stand von vor der "
                                              "Bildschirm-Abschaltung erst nach dem nächsten Anmelden)"), ausgabe)

    def test_gesperrt_und_hell_neu_starten(self):
        self.code_alter(-50)
        self.gesperrt()
        self.assertEqual(self.neu_laden(), ["info: Automatische Sperre neu gestartet (neuer Stand von zenos-idle, "
                                            "gesperrt)"])
        self.assertEqual(self.neustarts(), [["--user", "try-restart", "zenos-idle.service"]])
        self.assertEqual(self.aufrufe("bildschirm"), [["status"]])

    def test_gesperrt_und_dunkel_nicht_neu_starten(self):
        # swayidle schaltete beim Beenden über resume an: Die Sperre leuchtete bis S+B. zenos-idle übernimmt selbst.
        self.code_alter(-50)
        self.gesperrt()
        for status in ("aus", "teils"):
            with self.subTest(status=status):
                self.vergessen("ereignisse")
                self.verhalten("bildschirm", "aus", status + "\n")
                ausgabe = self.neu_laden()
                self.assertEqual(self.neustarts(), [])
                self.assertEqual(len(ausgabe), 1)
                self.assertIn("gesperrt und dunkel", ausgabe[0])

    def test_bildschirm_unbekannt_gilt_als_hell(self):
        # Ohne Antwort von wlopm kann auch zenos-bildschirm nichts schalten: dann darf der Neustart sein
        self.code_alter(-50)
        self.gesperrt()
        self.verhalten("bildschirm", "exit", "3")
        self.verhalten("bildschirm", "aus", "")
        self.neu_laden()
        self.assertEqual(len(self.neustarts()), 1)

    def test_neustart_scheitert(self):
        self.code_alter(-50)
        self.gesperrt()
        self.verhalten("systemctl", "exit.try-restart", "1")
        self.assertEqual(self.neu_laden(), ["warnung: zenos-idle.service liess sich nicht neu starten "
                                            "(systemctl --user status zenos-idle)"])

    def test_zweiter_lauf_ohne_neustart(self):
        start = self.code_alter(-50)
        self.gesperrt()
        self.neu_laden()
        self.assertEqual(len(self.neustarts()), 1)
        # Der neue Dienst läuft seit dem Neustart: Der Code ist älter, nichts mehr zu tun
        self.verhalten("systemctl", "aus.show", f"@{start + 200}\n")
        self.vergessen("ereignisse")
        self.assertEqual(self.neu_laden(), [])
        self.assertEqual(self.neustarts(), [])

    def test_startzeit_unbekannt_nichts(self):
        self.gesperrt()
        for ausgabe in ("", "n/a\n", "@\n"):
            with self.subTest(ausgabe=ausgabe):
                self.verhalten("systemctl", "aus.show", ausgabe)
                self.assertEqual(self.neu_laden(), [])
                self.assertEqual(self.neustarts(), [])

    # --- 66-energie: zen doctor

    def doctor(self, *teile):
        return self.bash(DOCTOR_TEIL, DOCTOR, *teile)

    def akku(self, vorhanden=True):
        with open(self.geraet, "w", encoding="utf-8") as f:
            json.dump({"version": 1, "zeit": "2026-10-05T20:00:00+02:00",
                       "akku": {"vorhanden": vorhanden, "prozent": 40, "laedt": False, "zustand": "ok"}}, f)

    def energie(self, **werte):
        zeilen = {"sperre": "5 standard", "bildschirm": "1 standard", "ausschalten": "60 standard",
                  "ausschaltenwenn": "akku standard", "taste": "sperren standard"}
        zeilen.update(werte)
        self.verhalten("idle", "aus", "".join(f"{k} {v}\n" for k, v in zeilen.items()))

    def test_doctor_zeiten(self):
        self.assertEqual(self.doctor("_energie_zeit"),
                         ["ok: Bildschirm aus 1 Min. nach der Sperre, also nach 6 Min. ohne Eingabe (Standard)"])
        self.energie(sperre="3 einstellung", bildschirm="4 einstellung")
        self.assertEqual(self.doctor("_energie_zeit"),
                         ["ok: Bildschirm aus 4 Min. nach der Sperre, also nach 7 Min. ohne Eingabe"])
        self.energie(bildschirm="10 begrenzt")
        self.assertTrue(self.doctor("_energie_zeit")[0].startswith("warnung: bildschirmAusNachSperre liegt ausserhalb"))
        self.energie(bildschirm="0 einstellung")
        self.assertEqual(self.doctor("_energie_zeit"),
                         ["fehler: Zeit für «Bildschirm aus» nicht ermittelbar (zenos-idle energie)"])

    def test_doctor_ausschalten_ohne_akku_ehrlich(self):
        # «Im Akkubetrieb» ohne Akku: kein ✓, sondern der Hinweis, dass es hier nie greift (und keine Wächter-Zeile)
        self.assertEqual(self.doctor("_energie_ausschalten", "_energie_login"),
                         ["hinweis: Ausschalten nach 60 Min. gesperrt im Akkubetrieb: kein Akku erkannt, greift auf "
                          "diesem Gerät nie"])
        self.assertEqual(self.aufrufe("energie"), [])
        self.akku(vorhanden=False)
        self.assertEqual(len(self.doctor("_energie_ausschalten")), 1)

    def test_doctor_ausschalten_mit_akku(self):
        self.akku()
        self.assertEqual(self.doctor("_energie_ausschalten", "_energie_login"), [
            "ok: Ausschalten nach 60 Min. gesperrt im Akkubetrieb, mit 60 s Vorwarnung",
            "ok: Ausschalten zurzeit möglich (nichts im Weg)",
            "ok: Am Login-Bildschirm im Akkubetrieb aus nach 30 Min. ohne Eingabe, mit 60 s Vorwarnung (fest)",
        ])
        self.assertEqual(self.aufrufe("energie"), [["status"]])
        self.verhalten("energie", "aus", "nein: SSH-Sitzung offen\n")
        self.assertEqual(self.doctor("_energie_ausschalten")[1], "hinweis: Ausschalten zurzeit nicht möglich: "
                                                                  "SSH-Sitzung offen")
        self.verhalten("energie", "aus", "quatsch\n")
        self.assertEqual(self.doctor("_energie_ausschalten")[1], "warnung: Wächter für das Ausschalten nicht prüfbar "
                                                                  "(zenos-energie status)")
        # «Nie»: nur der Hinweis, der Login-Bildschirm gilt trotzdem (fest)
        self.energie(ausschaltenwenn="nie einstellung")
        self.assertEqual(self.doctor("_energie_ausschalten", "_energie_login"), [
            "hinweis: Ausschalten nach langer Sperre: nie (Einstellung)",
            "ok: Am Login-Bildschirm im Akkubetrieb aus nach 30 Min. ohne Eingabe, mit 60 s Vorwarnung (fest)",
        ])

    def test_doctor_ausschalten_immer_und_unbekannt(self):
        self.energie(ausschaltenwenn="immer einstellung", ausschalten="90 einstellung")
        self.assertEqual(self.doctor("_energie_ausschalten", "_energie_login")[0],
                         "ok: Ausschalten nach 90 Min. gesperrt, mit 60 s Vorwarnung")
        self.verhalten("idle", "aus", "")
        self.assertEqual(self.doctor("_energie_ausschalten"),
                         ["fehler: Einstellung zum Ausschalten nicht ermittelbar (zenos-idle energie)"])
        os.remove(os.path.join(self.doctor_bin, "zenos-energie"))
        self.assertTrue(self.doctor("_energie_ausschalten")[0].startswith("fehler: "))

    def test_doctor_sitzung_und_stand_von_zenos_idle(self):
        os.remove(os.path.join(self.lz, "bus"))
        self.assertEqual(self.doctor("_energie_sitzung"),
                         ["hinweis: Keine laufende zenOS-Sitzung, Bildschirm-Steuerung erst nach der Anmeldung prüfbar"])
        self.bus.close()
        self.bus = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.bus.bind(os.path.join(self.lz, "bus"))
        self.verhalten("systemctl", "exit.zenos-sitzung.target", "0")
        self.verhalten("systemctl", "exit.zenos-idle.service", "0")
        self.verhalten("bildschirm", "aus", "aus\n")
        start = int(time.time()) - 100
        self.verhalten("systemctl", "aus.show", f"@{start}\n")
        for name in ("zenos-idle", "zenos-bildschirm"):
            os.utime(os.path.join(self.doctor_bin, name), (start - 50, start - 50))
        self.assertEqual(self.doctor("_energie_sitzung"),
                         ["ok: Bildschirm-Steuerung in der Sitzung erreichbar (Bildschirm aus)"])
        # Neuerer Code: der ehrliche Hinweis, wann er gilt
        os.utime(os.path.join(self.doctor_bin, "zenos-bildschirm"), (start + 50, start + 50))
        self.assertEqual(self.doctor("_energie_sitzung")[1],
                         "hinweis: zenos-idle läuft mit einem älteren Stand und übernimmt den neuen bei der nächsten "
                         "Sperre (ein Stand von vor der Bildschirm-Abschaltung erst nach dem nächsten Anmelden)")
        # Kein Bildschirm aktiv (Deckel zu, alle Ausgänge aus): ein Hinweis, keine Warnung
        self.verhalten("bildschirm", "aus", "keiner\n")
        self.assertEqual(self.doctor("_energie_sitzung")[0],
                         "hinweis: Kein Bildschirm aktiv (Deckel zu, kein Monitor oder alle Ausgänge aus), "
                         "Bildschirm-Steuerung jetzt nicht prüfbar")
        # wlopm erreicht nichts
        self.verhalten("bildschirm", "exit", "1")
        self.assertTrue(self.doctor("_energie_sitzung")[0].startswith("warnung: wlopm erreicht die Bildschirme"))

    def test_doctor_ein_aus_taste(self):
        self.energie(taste="ausschalten einstellung")
        self.assertEqual(self.doctor("_energie_taste"), ["hinweis: Ein/Aus-Taste: kurzer Druck schaltet aus "
                                                         "(Einstellung)"])
        self.energie()
        self.assertEqual(self.doctor("_energie_taste"), ["hinweis: Ein/Aus-Taste: Hemmer erst in einer laufenden "
                                                         "Sitzung prüfbar"])
        self.verhalten("systemctl", "exit.zenos-idle.service", "0")
        hemmer = {"type": "a(ssssuu)", "data": [[["handle-power-key", "zenOS", "Ein/Aus-Taste", "block",
                                                  os.getuid(), 42]]]}
        self.verhalten("busctl", "aus", json.dumps(hemmer))
        self.assertTrue(self.doctor("_energie_taste")[0].startswith("ok: Ein/Aus-Taste: kurzer Druck sperrt"))
        hemmer["data"][0][0][4] = os.getuid() + 1
        self.verhalten("busctl", "aus", json.dumps(hemmer))
        self.assertTrue(self.doctor("_energie_taste")[0].startswith("warnung: Ein/Aus-Taste: kein Hemmer von zenOS"))
        # labwc ohne Tastenkürzel
        os.makedirs(os.path.join(self.home, ".config", "labwc"))
        with open(os.path.join(self.home, ".config", "labwc", "rc.xml"), "w", encoding="utf-8") as f:
            f.write("<labwc_config/>\n")
        self.assertTrue(self.doctor("_energie_taste")[0].startswith("warnung: labwc kennt die Ein/Aus-Taste nicht"))

    def test_doctor_bereitschaft_nur_hinweis(self):
        ausgabe = self.doctor("_energie_bereitschaft")
        self.assertEqual(len(ausgabe), 1)
        self.assertTrue(ausgabe[0].startswith("hinweis: "))

    def test_doctor_liest_nur(self):
        self.akku()
        self.verhalten("systemctl", "exit.zenos-sitzung.target", "0")
        self.verhalten("systemctl", "exit.zenos-idle.service", "0")
        self.bash(DOCTOR_TEIL, DOCTOR, "pruefe_energie")
        for argv in self.aufrufe("systemctl"):
            self.assertTrue(argv[1] in ("--quiet", "show"), argv)
        self.assertEqual(self.aufrufe("energie"), [["status"]])
        self.assertEqual(self.aufrufe("bildschirm"), [["status"]])
        self.assertNotIn(["aus"], self.aufrufe("bildschirm") + self.aufrufe("energie"))


if __name__ == "__main__":
    unittest.main()
