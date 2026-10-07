#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-energie (Ausschalten nach langer Sperre und am Login-Bildschirm, Ein/Aus-Taste,
Mitteilung danach).

Nie ein echtes Ausschalten: Jeder Test hat einen eigenen Baum mit einer Kopie von zenos-energie und dem echten
zenos-idle (es liest die Einstellungen), daneben Attrappen von zen, zenos-ipc und zenos-bildschirm. Im PATH liegen
falsche loginctl, pgrep, systemctl, busctl und logger. pgrep sucht wie das echte (Name oder mit -f die ganze
Befehlszeile, -x, -i) in einer Liste erfundener Prozesse; so werden die Muster selbst geprüft. Die festen Pfade unter
/run (geraet.json, Sperre von install.sh) liegen unter ZENOS_ENERGIE_TESTWURZEL. Alle Attrappen schreiben ihre Aufrufe
der Reihe nach in eine gemeinsame Datei. Läuft unter Linux (GNU stat, flock, /proc).

  python3 test/einheiten/energie.test.py
"""

import datetime
import fcntl
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest


# Als root (CI im Container) laufen die Helfer als nobody, denn sie verweigern root bewusst. Dafür gehört der
# Testordner vor jedem Aufruf nobody; ohne root bleibt alles, wie es ist.
NOBODY = 65534


def als_benutzer(argv, ordner):
    if os.geteuid() != 0:
        return argv
    for wurzel, unterordner, dateien in os.walk(ordner):
        for name in [wurzel] + [os.path.join(wurzel, n) for n in unterordner + dateien]:
            os.lchown(name, NOBODY, NOBODY)
    # Absoluter Pfad: Die Tests geben dem Helfer einen eigenen, knappen PATH
    return ["/usr/bin/setpriv", f"--reuid={NOBODY}", f"--regid={NOBODY}", "--clear-groups", "--", *argv]


WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENERGIE = os.path.join(WURZEL, "scripts", "bin", "zenos-energie")
IDLE = os.path.join(WURZEL, "scripts", "bin", "zenos-idle")
LOGIK = os.path.join(WURZEL, "shell", "modi", "zustandslogik.js")
ENERGIE_JS = os.path.join(WURZEL, "shell", "dienste", "energie.js")
RC_XML = os.path.join(WURZEL, "system", "labwc", "rc.xml.in")

# Attrappe: schreibt {"wer", "argv"} als JSON-Zeile. Verhalten aus Dateien im Testordner (ENERGIE_TEST):
#   <wer>.exit / <wer>.aus           Exit-Code und Ausgabe
#   <wer>.exit.<unter> / .aus.<unter>  dasselbe nur für einen Unterbefehl (erstes Argument ohne «-»)
#   pgrep: prozesse.json [{"comm", "args"}]; pgrep.exit erzwingt einen Exit-Code (z. B. 2: Fehler)
#   loginctl show-session ID -p NAME: sitzungen.json {"ID": {"Remote": "yes", "Class": "greeter"}}; fehlt die ID, Exit 1
#   busctl: Unterbefehl ist die Methode (letztes Argument), z. B. busctl.aus.CanPowerOff
#   <wer>.loeschen.<unter>  diese Datei löschen (z. B. die Oberfläche bricht während der letzten Prüfung ab)
ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, re, sys
WER = %r
ORDNER = os.environ["ENERGIE_TEST"]
argv = sys.argv[1:]
def datei(name):
    try:
        with open(os.path.join(ORDNER, WER + "." + name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"wer": WER, "argv": argv}) + "\n")
if WER == "pgrep":
    code = datei("exit")
    if code is not None:
        sys.exit(int(code))
    ganz = "-x" in argv
    zeile = "-f" in argv
    flags = re.I if "-i" in argv else 0
    muster = re.compile(argv[-1], flags)
    try:
        with open(os.path.join(ORDNER, "prozesse.json"), encoding="utf-8") as f:
            prozesse = json.load(f)
    except OSError:
        prozesse = []
    for p in prozesse:
        ziel = p["args"] if zeile else p["comm"][:15]
        if (muster.fullmatch(ziel) if ganz else muster.search(ziel)):
            sys.exit(0)
    sys.exit(1)
unter = argv[-1] if WER == "busctl" and argv else next((a for a in argv if not a.startswith("-")), "")
loeschen = datei("loeschen." + unter)
if loeschen:
    try:
        os.remove(loeschen.strip())
    except OSError:
        pass
if WER == "loginctl" and unter == "show-session":
    with open(os.path.join(ORDNER, "sitzungen.json"), encoding="utf-8") as f:
        sitzungen = json.load(f)
    eintrag = sitzungen.get(argv[1])
    if eintrag is None:
        sys.exit(1)
    name = argv[argv.index("-p") + 1]
    print(eintrag.get(name, {"Remote": "no", "Class": "user"}.get(name, "")))
    sys.exit(0)
aus = datei("aus." + unter)
aus = aus if aus is not None else datei("aus")
if aus is not None:
    print(aus, end="")
code = datei("exit." + unter)
sys.exit(int(code if code is not None else datei("exit") or 0))
'''

KEIN_HEMMER = {"type": "a(ssssuu)", "data": [[["shutdown", "Unattended Upgrades Shutdown",
                                              "Stop ongoing upgrades or perform upgrades before shutdown", "delay",
                                              0, 124]]]}


@unittest.skipUnless(os.path.exists("/proc/self"),
                     "nur unter Linux (bash 5, /proc), etwa im Testcontainer oder in der CI")
class EnergieTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-energie-test.")
        self.bin = os.path.join(self.wurzel, "scripts", "bin")
        self.fake = os.path.join(self.wurzel, "fake")
        self.home = os.path.join(self.wurzel, "home")
        self.lz = os.path.join(self.wurzel, "run-user")
        self.testwurzel = os.path.join(self.wurzel, "system")
        for ordner in (self.bin, self.fake, os.path.join(self.home, ".config", "zenos"), os.path.join(self.lz, "zenos"),
                       os.path.join(self.testwurzel, "run", "zenos"), os.path.join(self.testwurzel, "run", "lock")):
            os.makedirs(ordner, exist_ok=True)
        os.chmod(self.lz, 0o700)
        # Laufzeit seit dem Start eingefroren (zenos-energie liest sie im Testmodus von hier): Eine Sekunde, die
        # während des Tests verstreicht, darf die Grenze bei 60 s nicht verschieben
        os.makedirs(os.path.join(self.testwurzel, "proc"), exist_ok=True)
        # Fest statt der echten Laufzeit: Ein eben gestarteter Rechner (CI-Runner) läuft keine 5 Min., der Marker
        # «vor 295 s» läge dann vor dem Start
        laufzeit = "100000.00"
        with open(os.path.join(self.testwurzel, "proc", "uptime"), "w", encoding="utf-8") as f:
            f.write(f"{laufzeit} 1.00\n")
        self.programm = os.path.join(self.bin, "zenos-energie")
        shutil.copy2(ENERGIE, self.programm)
        shutil.copy2(IDLE, os.path.join(self.bin, "zenos-idle"))
        self.attrappe(os.path.join(self.bin, "zenos-ipc"), "ipc")
        self.attrappe(os.path.join(self.bin, "zenos-bildschirm"), "bildschirm")
        self.attrappe(os.path.join(self.wurzel, "scripts", "zen"), "zen")
        for name in ("loginctl", "pgrep", "systemctl", "busctl", "logger"):
            self.attrappe(os.path.join(self.fake, name), name)
        self.einstellungen = os.path.join(self.home, ".config", "zenos", "einstellungen.json")
        self.geraet = os.path.join(self.testwurzel, "run", "zenos", "geraet.json")
        self.sperrdatei = os.path.join(self.testwurzel, "run", "lock", "zenos-install.lock")
        self.marker = os.path.join(self.lz, "zenos", "vorwarnung")
        self.gesperrt = os.path.join(self.lz, "zenos", "gesperrt")
        self.zustand = os.path.join(self.home, ".local", "state", "zenos", "energie.json")
        # Standard: keine Sitzung, keine Prozesse, keine Hemmer (ausser einem verzögernden), apt-daily ruht
        self.verhalten("loginctl", "aus.list-sessions", "")
        self.sitzungen({})
        self.prozesse([])
        self.verhalten("busctl", "aus", json.dumps(KEIN_HEMMER) + "\n")
        self.verhalten("busctl", "aus.CanPowerOff", 's "yes"\n')
        self.verhalten("systemctl", "aus.is-active", "inactive\ninactive\n")
        self.verhalten("systemctl", "exit.is-active", "3")
        self.umgebung = {
            "PATH": self.fake + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": self.home,
            "XDG_RUNTIME_DIR": self.lz,
            "ENERGIE_TEST": self.wurzel,
            "ZENOS_ENERGIE_TESTWURZEL": self.testwurzel,
            "LANG": "C.UTF-8",
        }
        self.sperre_halter = None

    def tearDown(self):
        if self.sperre_halter:
            self.sperre_halter.close()
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

    def sitzungen(self, daten):
        with open(os.path.join(self.wurzel, "sitzungen.json"), "w", encoding="utf-8") as f:
            json.dump(daten, f)

    def prozesse(self, liste):
        with open(os.path.join(self.wurzel, "prozesse.json"), "w", encoding="utf-8") as f:
            json.dump([{"comm": c, "args": a} for c, a in liste], f)

    def einstellen(self, **werte):
        with open(self.einstellungen, "w", encoding="utf-8") as f:
            json.dump(werte, f)

    def akku(self, laedt=False, zustand="ok", prozent=40, alter=0, vorhanden=True, zeit=None):
        jetzt = datetime.datetime.now().astimezone() - datetime.timedelta(seconds=alter)
        daten = {"version": 1, "zeit": zeit if zeit is not None else jetzt.isoformat(timespec="seconds"),
                 "geraet": "argon-one-up",
                 "akku": {"vorhanden": vorhanden, "prozent": prozent, "laedt": laedt, "zustand": zustand}}
        with open(self.geraet, "w", encoding="utf-8") as f:
            json.dump(daten, f)

    def start_jetzt(self):
        """(Start-ID, ganze Sekunden seit dem Start) wie zenos-energie, mit der eingefrorenen Laufzeit"""
        with open("/proc/sys/kernel/random/boot_id", encoding="utf-8") as f:
            boot = f.read().strip()
        with open(os.path.join(self.testwurzel, "proc", "uptime"), encoding="utf-8") as f:
            laufzeit = int(float(f.read().split()[0]))
        return boot, laufzeit

    def vorwarnung(self, alter, boot=None, inhalt=None):
        """Marker wie von «darf-ausschalten»: vor «alter» Sekunden Laufzeit angelegt"""
        jetzt_boot, laufzeit = self.start_jetzt()
        if inhalt is None:
            inhalt = f"zenos-vorwarnung 1 {boot or jetzt_boot} {laufzeit - alter}\n"
        with open(self.marker, "w", encoding="utf-8") as f:
            f.write(inhalt)

    def sperren(self):
        with open(self.gesperrt, "w", encoding="utf-8") as f:
            f.write("2026-10-05T20:00:00Z\n")

    def aufruf(self, *args):
        lauf = subprocess.run(als_benutzer([self.programm, *args], self.wurzel), capture_output=True, text=True, env=self.umgebung, timeout=60,
                              check=False)
        return lauf.returncode, lauf.stdout, lauf.stderr

    def ereignisse(self):
        try:
            with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def aufrufe(self, wer):
        return [e["argv"] for e in self.ereignisse() if e["wer"] == wer]

    def poweroff(self):
        return [a for a in self.aufrufe("systemctl") if "poweroff" in a]

    def journal(self):
        return [" ".join(a[a.index("--") + 1:]) for a in self.aufrufe("logger") if "--" in a]

    def darf(self):
        code, aus, fehler = self.aufruf("darf-ausschalten")
        self.assertEqual(fehler, "")
        return code, aus.strip()

    def frei(self):
        """Alles frei, im Akkubetrieb: darf ausschalten."""
        self.akku()

    # --- Einstellung und Akkubetrieb

    def test_standard_akku_nur_im_akkubetrieb(self):
        self.akku()
        self.assertEqual(self.darf(), (0, "ja"))
        faelle = {
            "lädt": dict(laedt=True),
            "Laderichtung unbekannt": dict(laedt=None),
            "Zustand unbekannt": dict(zustand="unbekannt"),
            "Freigabe fehlt": dict(zustand="freigabe"),
            "kein Akku": dict(vorhanden=False),
            "Prozent fehlt": dict(prozent=None),
            "Prozent kein int": dict(prozent=40.5),
            "Prozent bool": dict(prozent=True),
            "Prozent zu hoch": dict(prozent=101),
            "Datei zu alt": dict(alter=90),
            "Datei aus der Zukunft": dict(alter=-90),
            "Zeit ohne Zone": dict(zeit="2026-10-05T20:00:00"),
            "Zeit kaputt": dict(zeit="gestern"),
        }
        for name, akku in faelle.items():
            with self.subTest(name):
                self.akku(**akku)
                self.assertEqual(self.darf(), (1, "nein: nicht im Akkubetrieb (Netzteil oder Akku unbekannt)"))
        for inhalt in ("", "{kaputt", "[]", json.dumps({"version": 2})):
            with self.subTest(inhalt=inhalt):
                with open(self.geraet, "w", encoding="utf-8") as f:
                    f.write(inhalt)
                self.assertEqual(self.darf()[0], 1)
        os.remove(self.geraet)
        self.assertEqual(self.darf()[0], 1)

    def test_immer_auch_ohne_akku_nie_nie(self):
        self.einstellen(ausschalten="immer")
        self.assertEqual(self.darf(), (0, "ja"))
        self.einstellen(ausschalten="nie")
        self.akku()
        self.assertEqual(self.darf(), (1, "nein: Ausschalten ist auf «Nie» gestellt"))
        # Ungültig: Standard «akku»
        self.einstellen(ausschalten="Immer")
        self.assertEqual(self.darf(), (0, "ja"))
        self.vergessen()
        os.remove(self.geraet)
        self.assertEqual(self.darf()[0], 1)

    def test_ohne_zenos_idle_nie(self):
        os.remove(os.path.join(self.bin, "zenos-idle"))
        self.einstellen(ausschalten="immer")
        self.assertEqual(self.darf(), (1, "nein: Einstellungen nicht lesbar (zenos-idle energie)"))

    def test_darf_ausschalten_schreibt_ins_journal_status_nicht(self):
        self.frei()
        self.darf()
        self.assertEqual(self.journal(), ["Ausschalten erlaubt: Vorwarnung beginnt"])
        self.prozesse([("tmux: server", "tmux new -s arbeit")])
        self.darf()
        self.assertEqual(self.journal()[-1], "Ausschalten blockiert: tmux läuft")
        self.assertFalse(os.path.exists(self.marker), "blockiert: kein Marker")
        self.vergessen("ereignisse")
        self.assertEqual(self.aufruf("status"), (1, "nein: tmux läuft\n", ""))
        self.prozesse([])
        self.assertEqual(self.aufruf("status"), (0, "ja\n", ""))
        self.assertFalse(os.path.exists(self.marker), "status legt keinen Marker an")
        self.assertEqual(self.journal(), [])
        # Nur lesen: weder ausgeschaltet noch etwas angefasst
        self.assertEqual(self.poweroff(), [])
        self.assertEqual(self.aufrufe("zen") + self.aufrufe("ipc") + self.aufrufe("bildschirm"), [])

    def test_darf_ausschalten_legt_den_marker_an(self):
        # Die Vorwarnung beginnt mit «ja»: Marker mit Start-ID und Laufzeit (nicht der Uhr), nur für den Benutzer
        self.frei()
        vorher = self.start_jetzt()
        self.assertEqual(self.darf(), (0, "ja"))
        nachher = self.start_jetzt()
        with open(self.marker, encoding="utf-8") as f:
            teile = f.read().split()
        self.assertEqual(teile[:3], ["zenos-vorwarnung", "1", vorher[0]])
        self.assertTrue(vorher[1] <= int(teile[3]) <= nachher[1])
        self.assertEqual([n for n in os.listdir(os.path.dirname(self.marker)) if ".neu." in n], [])
        # Ohne Ordner legt es ihn an (0700)
        shutil.rmtree(os.path.dirname(self.marker))
        self.assertEqual(self.darf(), (0, "ja"))
        self.assertEqual(os.stat(os.path.dirname(self.marker)).st_mode & 0o777, 0o700)
        # Ein «nein» räumt einen alten Marker weg
        self.prozesse([("tmux: server", "tmux")])
        self.assertEqual(self.darf()[0], 1)
        self.assertFalse(os.path.exists(self.marker))

    # --- Wächter

    def test_jeder_waechter_einzeln(self):
        self.frei()
        faelle = {
            "SSH-Verbindung offen": [("sshd-session", "sshd-session: tester [priv]")],
            "tmux läuft": [("tmux: server", "tmux new-session -d -s probe")],
            "tmux läuft ": [("tmux: client", "tmux attach")],
            "screen läuft": [("screen", "SCREEN -dmS probe sleep 300")],
            "Update läuft (zen update)": [("zen", "bash /opt/zenos/scripts/zen update")],
            "Update läuft (zen update) ": [("zen", "/bin/bash /usr/local/bin/zen rollback v0.1")],
            "Paketverwaltung läuft (apt, dpkg)": [("apt-get", "apt-get install -y wlopm")],
            "Paketverwaltung läuft (apt, dpkg) ": [("dpkg", "/usr/bin/dpkg --configure -a")],
            "Paketverwaltung läuft (apt, dpkg)  ": [("apt", "apt upgrade")],
            "Automatische Updates laufen": [("unattended-upgr", "/usr/bin/python3 /usr/bin/unattended-upgrade")],
        }
        for grund, prozesse in faelle.items():
            with self.subTest(grund):
                self.prozesse(prozesse)
                self.assertEqual(self.darf(), (1, "nein: " + grund.strip()))
        # Kein Grund: der ständige Wächter von unattended-upgrades, fremde Prozesse mit ähnlichen Namen
        self.prozesse([
            ("unattended-upgr", "/usr/bin/python3 /usr/share/unattended-upgrades/unattended-upgrade-shutdown "
                                "--wait-for-signal"),
            ("sshd", "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"),
            ("bash", "bash -c echo zen update-notes"),
            ("aptd", "aptd"),
            ("dpkg-query", "dpkg-query -W"),
            ("vim", "vim tmux.conf"),
            ("zen", "bash /opt/zenos/scripts/zen doctor"),
        ])
        self.assertEqual(self.darf(), (0, "ja"))

    def test_ssh_sitzung_ueber_logind(self):
        self.frei()
        self.verhalten("loginctl", "aus.list-sessions", "c1 1000 tester seat0 887 user tty1 no -\n"
                                                         "4 1000 tester - 1234 user pts/0 no -\n")
        self.sitzungen({"c1": {"Remote": "no"}, "4": {"Remote": "yes"}})
        self.assertEqual(self.darf(), (1, "nein: SSH-Sitzung offen"))
        self.sitzungen({"c1": {"Remote": "no"}, "4": {"Remote": "no"}})
        self.assertEqual(self.darf(), (0, "ja"))
        self.assertIn(["show-session", "4", "-p", "Remote", "--value"], self.aufrufe("loginctl"))

    def test_nicht_pruefbar_heisst_blockiert(self):
        self.frei()
        faelle = {
            "Sitzungen nicht prüfbar (loginctl)": [("loginctl", "exit.list-sessions", "1")],
            "Sitzungen nicht prüfbar (loginctl) ": [("loginctl", "aus.list-sessions", "9 1000 tester - 1 user\n")],
            "Sitzungen nicht prüfbar (loginctl)  ": [("loginctl", "aus.list-sessions", "$(x) 1000 tester\n")],
            "Prozesse nicht prüfbar (pgrep)": [("pgrep", "exit", "2")],
            "Hemmer nicht prüfbar (logind)": [("busctl", "exit", "1")],
            "Hemmer nicht prüfbar (logind) ": [("busctl", "aus", "keine Antwort\n")],
            "Hemmer nicht prüfbar (logind)  ": [("busctl", "aus", json.dumps({"type": "a(ssssuu)", "data": []}))],
        }
        for grund, verhalten in faelle.items():
            with self.subTest(grund):
                self.vergessen("loginctl.exit.list-sessions", "loginctl.aus.list-sessions", "pgrep.exit",
                               "busctl.exit")
                self.verhalten("busctl", "aus", json.dumps(KEIN_HEMMER))
                for eintrag in verhalten:
                    self.verhalten(*eintrag)
                self.assertEqual(self.darf(), (1, "nein: " + grund.strip()))

    def test_sperre_von_install_sh(self):
        self.frei()
        # Datei da, aber frei: kein Grund
        with open(self.sperrdatei, "w", encoding="utf-8") as f:
            f.write("")
        self.assertEqual(self.darf(), (0, "ja"))
        # install.sh hält sie exklusiv
        self.sperre_halter = open(self.sperrdatei, "a", encoding="utf-8")
        fcntl.flock(self.sperre_halter, fcntl.LOCK_EX)
        self.assertEqual(self.darf(), (1, "nein: Installation läuft (install.sh)"))
        self.sperre_halter.close()
        self.sperre_halter = None
        self.assertEqual(self.darf(), (0, "ja"))
        # Nur lesend geöffnet, nie angelegt: fehlt sie, bleibt sie weg
        os.remove(self.sperrdatei)
        self.assertEqual(self.darf(), (0, "ja"))
        self.assertFalse(os.path.exists(self.sperrdatei))

    def test_kanal_installation_als_root(self):
        # Ein Lauf des Kanals (zen update, Einstellungen, Automatik, Bestätigung nach dem Start) arbeitet in Units als
        # root: Seine Sperren in /run/zenos-sperre sieht ein Benutzer nicht, der Block-Hemmer gilt nur während
        # install.sh. systemd sagt jedem, ob eine Unit zenos-kanal-* läuft; ebenso für die Basis-Updates
        # (zenos-basis-*: apt-get update, apt-get full-upgrade, install.sh, Gesundheitsprüfung).
        self.frei()
        self.assertEqual(self.darf(), (0, "ja"))
        for einheit, zustand in (("zenos-kanal-installieren.service", "activating"),
                                 ("zenos-kanal-automatik.service", "activating"),
                                 ("zenos-kanal-bestaetigen.service", "activating"),
                                 ("zenos-kanal-zustimmen@0123456789abcdef0123456789abcdef01234567.service",
                                  "deactivating"),
                                 ("zenos-basis-installieren.service", "activating"),
                                 ("zenos-basis-pruefen.service", "active")):
            with self.subTest(einheit):
                self.verhalten("systemctl", "aus.list-units",
                               f"{einheit} loaded {zustand} start start zenOS: Kanal\nzenos-kanal-pruefen.service "
                               "loaded activating start start zenOS\n")
                self.assertEqual(self.darf(), (1, f"nein: Update läuft ({einheit})"))
                self.assertEqual(self.aufruf("status")[1], f"nein: Update läuft ({einheit})\n")
        self.verhalten("systemctl", "exit.list-units", "1")
        self.assertEqual(self.darf(), (1, "nein: Updates nicht prüfbar (systemctl)"))
        self.vergessen("systemctl.exit.list-units", "systemctl.aus.list-units")
        self.assertEqual(self.darf(), (0, "ja"))
        aufruf = [a for a in self.aufrufe("systemctl") if a and a[0] == "list-units"][-1]
        self.assertEqual(aufruf, ["list-units", "--type=service", "--state=activating,active,deactivating,reloading",
                                  "--no-legend", "--plain", "--no-pager", "zenos-kanal-*.service",
                                  "zenos-basis-*.service"])
        # Auch unmittelbar vor dem Ausschalten (nach der Vorwarnung) und am Login-Bildschirm
        self.sperren()
        self.vorwarnung(70)
        self.verhalten("systemctl", "aus.list-units", "zenos-kanal-installieren.service loaded activating start "
                                                      "start x\n")
        code, aus, _ = self.aufruf("ausschalten")
        self.assertEqual((code, aus), (1, "nein: Update läuft (zenos-kanal-installieren.service)\n"))
        self.assertEqual(self.poweroff(), [])
        self.login_sitzungen()
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2],
                         (1, "nein: Update läuft (zenos-kanal-installieren.service)\n"))

    @unittest.skipIf(os.geteuid() == 0, "root liest jede Datei")
    def test_sperrdatei_nicht_lesbar(self):
        self.frei()
        with open(self.sperrdatei, "w", encoding="utf-8") as f:
            f.write("")
        os.chmod(self.sperrdatei, 0)
        self.assertEqual(self.darf(), (1, "nein: Installation nicht prüfbar (Sperrdatei nicht lesbar)"))

    def test_logind_muss_ohne_passwort_ausschalten_lassen(self):
        # Sonst lehnte «systemctl --no-ask-password poweroff» erst nach der Vorwarnung ab (z. B. eine zweite Sitzung)
        self.frei()
        faelle = {
            's "challenge"\n': "Ausschalten bräuchte ein Passwort (logind)",
            's "no"\n': "Ausschalten nicht erlaubt (logind)",
            's "na"\n': "Ausschalten nicht erlaubt (logind)",
            "": "Ausschalten nicht erlaubt (logind)",
        }
        for antwort, grund in faelle.items():
            with self.subTest(antwort=antwort):
                self.verhalten("busctl", "aus.CanPowerOff", antwort)
                self.assertEqual(self.darf(), (1, "nein: " + grund))
                self.assertEqual(self.aufruf("status")[1], f"nein: {grund}\n")
        self.verhalten("busctl", "aus.CanPowerOff", 's "yes"\n')
        self.verhalten("busctl", "exit.CanPowerOff", "1")
        self.assertEqual(self.darf(), (1, "nein: Ausschalten nicht prüfbar (logind)"))
        self.vergessen("busctl.exit.CanPowerOff")
        self.assertEqual(self.darf(), (0, "ja"))
        self.assertIn(["--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                       "org.freedesktop.login1.Manager", "CanPowerOff"], self.aufrufe("busctl"))

    def test_apt_daily(self):
        self.frei()
        for zustand in ("active", "activating", "deactivating", "reloading"):
            with self.subTest(zustand):
                self.verhalten("systemctl", "aus.is-active", f"inactive\n{zustand}\n")
                self.assertEqual(self.darf(), (1, "nein: Automatische Updates laufen (apt-daily)"))
        self.verhalten("systemctl", "aus.is-active", "inactive\nfailed\n")
        self.assertEqual(self.darf(), (0, "ja"))
        self.assertIn(["is-active", "apt-daily.service", "apt-daily-upgrade.service"], self.aufrufe("systemctl"))

    def test_hemmer_von_logind(self):
        self.frei()

        def hemmer(*eintraege):
            daten = {"type": "a(ssssuu)", "data": [[list(e) for e in eintraege]]}
            self.verhalten("busctl", "aus", json.dumps(daten))

        hemmer(("shutdown:sleep", "Brenner", "brennt", "block", 1000, 42))
        self.assertEqual(self.darf(), (1, "nein: «Brenner» verhindert das Ausschalten"))
        hemmer(("sleep:shutdown:idle", "\x1b[31mFarbe\x07", "x", "block", 0, 1))
        self.assertEqual(self.darf(), (1, "nein: «[31mFarbe» verhindert das Ausschalten"))
        hemmer(("shutdown", "", "x", "block", 0, 1))
        self.assertEqual(self.darf(), (1, "nein: «Ein Programm» verhindert das Ausschalten"))
        # Kein Grund: nur verzögernd, nur Schlaf, die Ein/Aus-Taste von zenOS, ein Video (idle)
        hemmer(("shutdown", "Unattended Upgrades Shutdown", "x", "delay", 0, 124),
               ("sleep", "swayidle", "Swayidle is preventing sleep", "delay", 1000, 7),
               ("handle-power-key", "zenOS", "Ein/Aus-Taste", "block", 1000, 8),
               ("idle", "Chrome", "Video", "block", 1000, 9),
               ("shutdowns", "Fremd", "x", "block", 1000, 10))
        self.assertEqual(self.darf(), (0, "ja"))
        self.assertIn(["--system", "--json=short", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                       "org.freedesktop.login1.Manager", "ListInhibitors"], self.aufrufe("busctl"))

    # --- Ausschalten

    def bereit(self):
        """Gesperrt, Vorwarnung vor 70 s, alles frei, «immer»."""
        self.einstellen(ausschalten="immer", ausschaltenNachMinuten=90)
        self.sperren()
        self.vorwarnung(70)

    def test_ausschalten_nur_mit_check_inhibitors(self):
        self.bereit()
        code, aus, fehler = self.aufruf("ausschalten")
        self.assertEqual((code, aus, fehler), (0, "ausgeschaltet\n", ""))
        self.assertEqual(self.poweroff(), [["--no-ask-password", "poweroff", "--check-inhibitors=yes"]])
        # Die Vorwarnung gilt einmal
        self.assertFalse(os.path.exists(self.marker))
        with open(self.zustand, encoding="utf-8") as f:
            zustand = json.load(f)
        with open("/proc/sys/kernel/random/boot_id", encoding="utf-8") as f:
            boot = f.read().strip()
        self.assertEqual((zustand["version"], zustand["boot"], zustand["minuten"], zustand["wenn"]),
                         (1, boot, 90, "immer"))
        self.assertTrue(datetime.datetime.fromisoformat(zustand["ausgeschaltet"]).tzinfo)
        self.assertTrue(any(z.startswith("Schalte aus: 90 Min. gesperrt") for z in self.journal()))
        # Ein zweiter Aufruf ohne neue Vorwarnung: nein
        self.vergessen("ereignisse")
        self.assertEqual(self.aufruf("ausschalten")[:2], (1, "nein: keine Vorwarnung\n"))
        self.assertEqual(self.poweroff(), [])

    def test_vorwarnung_60_s_bis_5_min(self):
        self.bereit()
        # 4: noch zu früh (der Takt der Oberfläche war etwas schneller), der Marker bleibt für den nächsten Takt
        for alter, erwartet in ((0, 4), (30, 4), (58, 4), (59, 4), (60, 0), (61, 0), (120, 0), (295, 0), (310, 1),
                                (600, 1), (-120, 1)):
            with self.subTest(alter=alter):
                self.vergessen("ereignisse")
                if os.path.exists(self.zustand):
                    os.remove(self.zustand)
                self.vorwarnung(alter)
                code, aus, _ = self.aufruf("ausschalten")
                self.assertEqual(code, erwartet, aus)
                self.assertEqual(len(self.poweroff()), 1 if erwartet == 0 else 0)
                if erwartet == 4:
                    self.assertEqual(aus, f"nein: Vorwarnung erst {alter} s alt (mindestens 60 s)\n")
                    self.assertTrue(os.path.exists(self.marker), "zu früh: der Marker bleibt")
                    self.assertEqual(self.journal(), [], "zu früh: kein Eintrag je Takt")
                else:
                    self.assertFalse(os.path.exists(self.marker), "Marker gilt einmal")
                if erwartet:
                    self.assertTrue(aus.startswith("nein: Vorwarnung"), aus)
                    self.assertFalse(os.path.exists(self.zustand))

    def test_vorwarnung_nach_laufzeit_nicht_nach_der_uhr(self):
        # Die Uhr springt (NTP nach langer Zeit offline): Die Datei scheint 2 Std. alt, die Vorwarnung lief aber erst
        # 10 s. Es zählt die Laufzeit seit dem Start.
        self.bereit()
        self.vorwarnung(10)
        alt = time.time() - 7200
        os.utime(self.marker, (alt, alt))
        self.assertEqual(self.aufruf("ausschalten")[:2], (4, "nein: Vorwarnung erst 10 s alt (mindestens 60 s)\n"))
        self.assertEqual(self.poweroff(), [])
        # Umgekehrt: Uhr zurück, die Datei scheint neu, die Vorwarnung lief aber 70 s
        self.vorwarnung(70)
        neu = time.time() + 3600
        os.utime(self.marker, (neu, neu))
        self.assertEqual(self.aufruf("ausschalten")[:2], (0, "ausgeschaltet\n"))

    def test_vorwarnung_nur_aus_diesem_start_und_lesbar(self):
        self.bereit()
        faelle = {
            "anderer Start": dict(boot="00000000-0000-0000-0000-000000000000"),
            "altes Format": dict(inhalt="2026-10-05T20:00:00Z\n"),
            "leer": dict(inhalt=""),
            "Zusatz": dict(inhalt=f"zenos-vorwarnung 1 {self.start_jetzt()[0]} 5 x\n"),
            "Version 2": dict(inhalt=f"zenos-vorwarnung 2 {self.start_jetzt()[0]} 5\n"),
            "keine Zahl": dict(inhalt=f"zenos-vorwarnung 1 {self.start_jetzt()[0]} $(reboot)\n"),
        }
        for name, art in faelle.items():
            with self.subTest(name):
                self.vergessen("ereignisse")
                self.vorwarnung(70, **art)
                self.assertEqual(self.aufruf("ausschalten")[:2], (1, "nein: Vorwarnung nicht lesbar\n"))
                self.assertEqual(self.poweroff(), [])
                self.assertFalse(os.path.exists(self.marker), "Marker gilt einmal")

    def test_eingabe_bis_zuletzt_bricht_ab(self):
        # Die Oberfläche löscht den Marker (eine Eingabe), während der Helfer noch prüft: kein Aus
        self.bereit()
        self.verhalten("busctl", "loeschen.CanPowerOff", self.marker)
        self.assertEqual(self.aufruf("ausschalten")[:2], (1, "nein: Vorwarnung abgebrochen\n"))
        self.assertEqual(self.poweroff(), [])
        self.assertFalse(os.path.exists(self.zustand))
        # Verbraucht wird er erst nach allen Prüfungen: Ist etwas im Weg, bleibt kein Aus übrig
        self.vergessen("busctl.loeschen.CanPowerOff", "ereignisse")
        self.bereit()
        self.assertEqual(self.aufruf("ausschalten")[:2], (0, "ausgeschaltet\n"))
        self.assertFalse(os.path.exists(self.marker))
        self.assertFalse(os.path.exists(self.marker + ".verbraucht"))

    def test_vorwarnung_nur_als_eigene_datei(self):
        self.bereit()
        os.remove(self.marker)
        ziel = os.path.join(self.wurzel, "ziel")
        with open(ziel, "w", encoding="utf-8") as f:
            f.write("x\n")
        alt = time.time() - 120
        os.utime(ziel, (alt, alt))
        os.symlink(ziel, self.marker)
        self.assertEqual(self.aufruf("ausschalten")[:2], (1, "nein: keine Vorwarnung\n"))
        self.assertTrue(os.path.exists(ziel), "nur der Verweis wird gelöscht")
        self.assertFalse(os.path.lexists(self.marker))
        os.mkdir(self.marker)
        self.assertEqual(self.aufruf("ausschalten")[:2], (1, "nein: keine Vorwarnung\n"))
        self.assertEqual(self.poweroff(), [])

    def test_ausschalten_nur_gesperrt(self):
        self.bereit()
        os.remove(self.gesperrt)
        self.assertEqual(self.aufruf("ausschalten")[:2], (1, "nein: nicht gesperrt\n"))
        self.assertEqual(self.poweroff(), [])
        self.assertIn("Nicht ausgeschaltet: nicht gesperrt", self.journal())

    def test_ausschalten_prueft_alles_erneut(self):
        faelle = {
            "SSH-Sitzung offen": lambda: (self.verhalten("loginctl", "aus.list-sessions", "7 1000 t - 1 user\n"),
                                          self.sitzungen({"7": {"Remote": "yes"}})),
            "tmux läuft": lambda: self.prozesse([("tmux: server", "tmux")]),
            "Paketverwaltung läuft (apt, dpkg)": lambda: self.prozesse([("dpkg", "dpkg -i x.deb")]),
            "Ausschalten ist auf «Nie» gestellt": lambda: self.einstellen(ausschalten="nie"),
            "nicht im Akkubetrieb (Netzteil oder Akku unbekannt)": lambda: (self.einstellen(ausschalten="akku"),
                                                                          self.akku(laedt=True)),
        }
        for grund, aufbau in faelle.items():
            with self.subTest(grund):
                self.vergessen("ereignisse", "loginctl.aus.list-sessions")
                self.verhalten("loginctl", "aus.list-sessions", "")
                self.prozesse([])
                self.bereit()
                aufbau()
                self.assertEqual(self.aufruf("ausschalten")[:2], (1, f"nein: {grund}\n"))
                self.assertEqual(self.poweroff(), [])
                self.assertFalse(os.path.exists(self.zustand))
                self.assertIn(f"Nicht ausgeschaltet: {grund}", self.journal())

    def test_poweroff_abgelehnt(self):
        self.bereit()
        self.verhalten("systemctl", "exit.poweroff", "1")
        self.verhalten("systemctl", "aus.poweroff", "Operation inhibited by \"Brenner\"\nPlease retry\n")
        code, aus, _ = self.aufruf("ausschalten")
        # Exit 3: Die Oberfläche versucht es erst nach der nächsten Eingabe wieder
        self.assertEqual(code, 3)
        self.assertEqual(aus, 'nein: systemctl poweroff abgelehnt (Exit 1): Operation inhibited by "Brenner" '
                              "Please retry\n")
        self.assertFalse(os.path.exists(self.zustand), "keine Mitteilung für ein Aus, das nicht kam")

    def test_skript_schaltet_nie_anders_aus(self):
        with open(ENERGIE, encoding="utf-8") as f:
            zeilen = [z for z in f if not z.lstrip().startswith("#")]
        text = "".join(zeilen)
        # Genau ein Aufruf, dazu der Text der Meldung
        self.assertEqual([z.strip() for z in zeilen if "poweroff" in z],
                         ["ausgabe=$(systemctl --no-ask-password poweroff --check-inhibitors=yes 2>&1) || rc=$?",
                          'grund="systemctl poweroff abgelehnt (Exit $rc): ${ausgabe//$\'\\n\'/ }"'])
        # (-i für systemctl schliesst die Zeile oben aus; pgrep -i kommt vor)
        for verboten in (r"\breboot\b", r"\bhalt\b", r"--force", r"--ignore-inhibitors",
                         r"check-inhibitors=no", r"\bshutdown\s+-", r"\bsh\s+-c\b", r"\beval\b"):
            self.assertNotRegex(text, verboten)

    # --- Login-Bildschirm

    def login_sitzungen(self, **mehr):
        """Nur der Greeter und der Benutzerdienst von systemd, dazu weitere Sitzungen {ID: Klasse}"""
        zeilen = ["c1 117 _greetd seat0 1100 greeter tty7 no -", "2 117 _greetd - 1101 manager - no -"]
        daten = {"c1": {"Class": "greeter"}, "2": {"Class": "manager"}}
        for nummer, klasse in mehr.items():
            zeilen.append(f"{nummer} 1000 tester - 1 {klasse} - no -")
            daten[nummer] = {"Class": klasse}
        self.verhalten("loginctl", "aus.list-sessions", "\n".join(zeilen) + "\n")
        self.sitzungen(daten)

    def test_login_nur_im_akkubetrieb_fest(self):
        self.login_sitzungen()
        self.akku()
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (0, "ja\n"))
        self.assertTrue(os.path.exists(self.marker))
        self.assertIn("Ausschalten erlaubt (Login-Bildschirm): Vorwarnung beginnt", self.journal())
        # Die Einstellungen der Sitzung gelten dort nicht: auch «immer» heisst am Login nur im Akkubetrieb, «nie» ändert
        # nichts
        for einstellung in ("immer", "nie"):
            with self.subTest(einstellung=einstellung):
                self.einstellen(ausschalten=einstellung)
                self.akku(laedt=True)
                self.assertEqual(self.aufruf("darf-ausschalten-login")[:2],
                                 (1, "nein: nicht im Akkubetrieb (Netzteil oder Akku unbekannt)\n"))
                self.assertFalse(os.path.exists(self.marker))
        self.einstellen(ausschalten="nie")
        self.akku()
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (0, "ja\n"))

    def test_login_keine_andere_sitzung(self):
        self.akku()
        for klasse in ("user", "user-early", "background", "user-incomplete"):
            with self.subTest(klasse=klasse):
                self.login_sitzungen(**{"5": klasse})
                self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (1, "nein: eine andere Sitzung ist offen\n"))
        self.login_sitzungen(**{"6": "manager-early"})
        self.assertEqual(self.aufruf("darf-ausschalten-login")[0], 0)
        # SSH wie in der Sitzung
        self.login_sitzungen(**{"7": "user"})
        self.sitzungen({"c1": {"Class": "greeter"}, "2": {"Class": "manager"}, "7": {"Class": "user", "Remote": "yes"}})
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (1, "nein: SSH-Sitzung offen\n"))
        # Nicht prüfbar: blockiert
        self.login_sitzungen()
        self.sitzungen({"c1": {"Class": "greeter"}})
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (1, "nein: Sitzungen nicht prüfbar (loginctl)\n"))

    def test_login_dieselben_waechter(self):
        self.login_sitzungen()
        self.akku()
        self.prozesse([("tmux: server", "tmux")])
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (1, "nein: tmux läuft\n"))
        self.prozesse([("dpkg", "dpkg --configure -a")])
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2], (1, "nein: Paketverwaltung läuft (apt, dpkg)\n"))
        self.prozesse([])
        self.verhalten("busctl", "aus.CanPowerOff", 's "challenge"\n')
        self.assertEqual(self.aufruf("darf-ausschalten-login")[:2],
                         (1, "nein: Ausschalten bräuchte ein Passwort (logind)\n"))

    def test_login_ausschalten_ohne_sperre_und_ohne_mitteilung(self):
        self.login_sitzungen()
        self.akku()
        self.vorwarnung(70)
        code, aus, fehler = self.aufruf("ausschalten-login")
        self.assertEqual((code, aus, fehler), (0, "ausgeschaltet\n", ""))
        self.assertEqual(self.poweroff(), [["--no-ask-password", "poweroff", "--check-inhibitors=yes"]])
        self.assertFalse(os.path.exists(self.marker))
        self.assertFalse(os.path.exists(self.zustand), "keine Mitteilung: niemand war angemeldet")
        self.assertIn("Schalte aus: 30 Min. ohne Eingabe am Login-Bildschirm im Akkubetrieb, nach 60 s Vorwarnung",
                      self.journal())
        # Ohne Vorwarnung, zu früh oder am Netzteil: nein
        self.vergessen("ereignisse")
        self.assertEqual(self.aufruf("ausschalten-login")[:2], (1, "nein: keine Vorwarnung\n"))
        self.vorwarnung(20)
        self.assertEqual(self.aufruf("ausschalten-login")[0], 4)
        self.vorwarnung(70)
        self.akku(laedt=True)
        self.assertEqual(self.aufruf("ausschalten-login")[:2],
                         (1, "nein: nicht im Akkubetrieb (Netzteil oder Akku unbekannt)\n"))
        self.assertEqual(self.poweroff(), [])
        self.assertIn("Nicht ausgeschaltet (Login-Bildschirm): nicht im Akkubetrieb (Netzteil oder Akku unbekannt)",
                      self.journal())

    def test_login_ohne_home(self):
        # greetd setzt HOME für _greetd womöglich nicht
        self.login_sitzungen()
        self.akku()
        del self.umgebung["HOME"]
        code, aus, fehler = self.aufruf("darf-ausschalten-login")
        self.assertEqual((code, aus, fehler), (0, "ja\n", ""))

    # --- Mitteilung beim nächsten Start

    def zustand_schreiben(self, **mehr):
        os.makedirs(os.path.dirname(self.zustand), exist_ok=True)
        daten = {"version": 1, "ausgeschaltet": "2026-10-05T22:41:07+02:00", "boot": "anderer-start", "minuten": 60,
                 "wenn": "akku"}
        daten.update(mehr)
        with open(self.zustand, "w", encoding="utf-8") as f:
            json.dump(daten, f)

    def test_meldung_einmal_nach_neustart(self):
        self.assertEqual(self.aufruf("meldung"), (0, "", ""))
        with open("/proc/sys/kernel/random/boot_id", encoding="utf-8") as f:
            boot = f.read().strip()
        # Derselbe Start (das Ausschalten läuft gerade): nichts, die Datei bleibt
        self.zustand_schreiben(boot=boot)
        self.assertEqual(self.aufruf("meldung"), (0, "", ""))
        self.assertTrue(os.path.exists(self.zustand))
        # Nach dem nächsten Start: einmal
        self.zustand_schreiben(boot="00000000-0000-0000-0000-000000000000")
        code, aus, fehler = self.aufruf("meldung")
        self.assertEqual((code, fehler), (0, ""))
        zeit = datetime.datetime.fromisoformat("2026-10-05T22:41:07+02:00").astimezone()
        self.assertEqual(aus, "zenOS hat ausgeschaltet\n"
                              f"Am {zeit.day}.{zeit.month}. um {zeit:%H:%M}, nach 60 Min. gesperrt im Akkubetrieb.\n")
        self.assertFalse(os.path.exists(self.zustand))
        self.assertEqual(self.aufruf("meldung"), (0, "", ""))
        self.zustand_schreiben(wenn="immer", minuten=240)
        self.assertTrue(self.aufruf("meldung")[1].endswith(", nach 240 Min. gesperrt.\n"))

    def test_meldung_ungueltig_wird_still_geloescht(self):
        for mehr in (dict(version=2), dict(minuten=5), dict(minuten=True), dict(wenn="nie"), dict(boot=None),
                     dict(ausgeschaltet="gestern")):
            with self.subTest(mehr=mehr):
                self.zustand_schreiben(**mehr)
                self.assertEqual(self.aufruf("meldung")[:2], (0, ""))
                self.assertFalse(os.path.exists(self.zustand))
        os.makedirs(os.path.dirname(self.zustand), exist_ok=True)
        with open(self.zustand, "w", encoding="utf-8") as f:
            f.write("{kaputt")
        self.assertEqual(self.aufruf("meldung")[:2], (0, ""))
        self.assertFalse(os.path.exists(self.zustand))

    # --- Ein/Aus-Taste

    def taste(self):
        code, aus, fehler = self.aufruf("taste")
        self.assertEqual(code, 0, fehler)
        return [(e["wer"], e["argv"]) for e in self.ereignisse() if e["wer"] in ("zen", "ipc", "bildschirm")]

    def test_taste_ungesperrt(self):
        self.assertEqual(self.taste(), [("zen", ["energie", "aus"])])
        self.vergessen("ereignisse")
        self.einstellen(einAusTaste="menue")
        self.assertEqual(self.taste(), [("ipc", ["leiste", "menue", "system"])])
        # Ohne Oberfläche: sperren statt Menü
        self.vergessen("ereignisse")
        self.verhalten("ipc", "exit", "2")
        self.assertEqual(self.taste(), [("ipc", ["leiste", "menue", "system"]), ("zen", ["energie", "aus"])])

    def test_taste_ausschalten_ueberlaesst_logind(self):
        self.einstellen(einAusTaste="ausschalten")
        self.assertEqual(self.taste(), [])
        self.sperren()
        self.assertEqual(self.taste(), [])
        self.assertEqual(self.poweroff(), [])

    def test_taste_gesperrt_fragt_die_sperre(self):
        self.sperren()
        for einstellung in ("sperren", "menue"):
            for antwort in ("an\n", "aus\n"):
                with self.subTest(einstellung=einstellung, antwort=antwort):
                    self.vergessen("ereignisse")
                    self.einstellen(einAusTaste=einstellung)
                    self.verhalten("ipc", "aus", antwort)
                    self.assertEqual(self.taste(), [("ipc", ["sperre", "taste"])])
        # Die Sperre meldet «offen» (eben entsperrt): wie ungesperrt
        self.vergessen("ereignisse")
        self.einstellen(einAusTaste="sperren")
        self.verhalten("ipc", "aus", "offen\n")
        self.assertEqual(self.taste(), [("ipc", ["sperre", "taste"]), ("zen", ["energie", "aus"])])

    def test_taste_gesperrt_ohne_oberflaeche(self):
        self.sperren()
        self.verhalten("ipc", "exit", "2")
        self.verhalten("bildschirm", "aus", "aus\n")
        self.assertEqual(self.taste(), [("ipc", ["sperre", "taste"]), ("bildschirm", ["status"]),
                                        ("bildschirm", ["an"])])
        self.vergessen("ereignisse")
        self.verhalten("bildschirm", "aus", "an\n")
        self.assertEqual(self.taste(), [("ipc", ["sperre", "taste"]), ("bildschirm", ["status"]),
                                        ("zen", ["energie", "aus"])])

    # --- Aufruf und Abgleich

    def test_falscher_aufruf(self):
        for argumente in ([], ["aus"], ["ausschalten", "jetzt"], ["--force"], ["poweroff"]):
            with self.subTest(argumente=argumente):
                code, aus, fehler = self.aufruf(*argumente)
                self.assertEqual((code, aus), (2, ""))
                self.assertTrue(fehler.startswith("zenos-energie: "))
        self.assertEqual(self.ereignisse(), [])

    def test_grenzen_wie_leitplanken(self):
        with open(ENERGIE, encoding="utf-8") as f:
            skript = f.read()
        werte = dict(re.findall(r"\b(VORWARNUNG_(?:MIN|MAX))=(\d+)", skript))
        with open(LOGIK, encoding="utf-8") as f:
            logik = f.read()
        with open(ENERGIE_JS, encoding="utf-8") as f:
            js = f.read()
        self.assertEqual(int(werte["VORWARNUNG_MIN"]), int(re.search(r"vorwarnungSekunden: (\d+)", logik).group(1)))
        login = re.search(r"\bLOGIN_MINUTEN=(\d+)", skript)
        self.assertIsNotNone(login)
        self.assertEqual(int(login.group(1)), int(re.search(r"loginAusschaltenMinuten: (\d+)", logik).group(1)))
        maximum = re.search(r"var VORWARNUNG_MAX_MS = (\d+) \* 60000;", js)
        self.assertIsNotNone(maximum)
        self.assertEqual(int(werte["VORWARNUNG_MAX"]), int(maximum.group(1)) * 60)

    def test_tastenkuerzel_auch_gesperrt(self):
        with open(RC_XML, encoding="utf-8") as f:
            xml = f.read()
        self.assertRegex(xml, r'<keybind key="XF86PowerOff" allowWhenLocked="yes">\s*'
                              r'<action name="Execute" command="@@BIN@@/zenos-energie taste" />\s*</keybind>')


if __name__ == "__main__":
    unittest.main()
