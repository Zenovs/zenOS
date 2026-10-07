#!/usr/bin/env python3
"""Einheitentests für die Bedienung der Basis-Updates in scripts/bin/zenos-basis: «update» (Schritt 2 von zen update:
prüfen, zeigen, «ja» oder --ja, installieren), «jetzt» und «zustimmen» (die Knöpfe der Einstellungen über
zenos-kanal-bedienen), die Automatik («automatik lauf» und «gelegenheit»: nur ohne Kernel, Firmware, Bootloader und
Entfernungen, nur wenn «zenos-kanal automatik darf --ohne-ssh» ja sagt), der Marker automatik-bereit, start_unit und
status mit der Automatik.

Baut auf test/einheiten/basis-updates.test.py auf (Temp-Ordner, Attrappen für apt, dpkg, install.sh und zen). Die
Units laufen im Prozess (start_unit ersetzt: pruefen → cmd_check, installieren → cmd_install); zenos-kanal ist eine
Attrappe, die die Antwort von «automatik darf» aus einer Datei gibt (die echte Abfrage prüft
test/einheiten/kanal-automatik.test.py, auch dass zenos-basis ihre Antwort so liest). Zeiten sind eingefroren. Ohne
Root, ohne Netz; als root ebenso.

  python3 test/einheiten/basis-automatik.test.py
"""

import datetime
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True

_HIER = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("basis_updates", os.path.join(_HIER, "basis-updates.test.py"))
_spec = importlib.util.spec_from_loader("basis_updates", _loader)
U = importlib.util.module_from_spec(_spec)
_loader.exec_module(U)
B = U.B
JETZT = U.JETZT
START_UNIT = B.start_unit

# Attrappe für zenos-kanal: «automatik darf --ohne-ssh --json» antwortet aus W/darf.json (Exit 0 bei darf, sonst 10)
KANAL = r'''
import json, os, sys
with open(os.path.join(W, "darf-aufrufe"), "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
try:
    text = open(os.path.join(W, "darf.json"), encoding="utf-8").read()
except FileNotFoundError:
    text = json.dumps({"darf": False, "grund": "Zeitpunkt «von Hand»: automatisch wird nichts installiert",
                       "zeitpunkt": "hand", "hinweis": None})
print(text.strip())
try:
    sys.exit(0 if json.loads(text)["darf"] is True else 10)
except (ValueError, KeyError, TypeError):
    sys.exit(1)
'''

# Attrappe für systemctl (nur start_unit): «start» endet mit W/systemctl.start, «show» gibt W/systemctl.status aus
SYSTEMCTL = r'''
import os, sys
with open(os.path.join(W, "systemctl-aufrufe"), "a", encoding="utf-8") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
def lies(name, vorgabe):
    try:
        return open(os.path.join(W, name), encoding="utf-8").read().strip()
    except FileNotFoundError:
        return vorgabe
if sys.argv[1] == "start":
    rc = int(lies("systemctl.start", "0"))
    if rc:
        print("Job for x failed.", file=sys.stderr)
    sys.exit(rc)
if sys.argv[1] == "show":
    print(lies("systemctl.status", "0"))
sys.exit(0)
'''

DARF_JA = {"darf": True, "grund": "Zeitpunkt «jederzeit»", "zeitpunkt": "jederzeit", "hinweis": None}
DARF_NEIN = {"darf": False, "grund": "ausserhalb des Zeitfensters 02:00–05:00 (jetzt 12:00)", "zeitpunkt": "fenster",
             "hinweis": None}


class Bedienung(U.Umgebung):
    """Umgebung von basis-updates.test.py, dazu die Sperre der Bedienung, der Notschalter, die Attrappe von
    zenos-kanal und die Units im Prozess."""

    def setUp(self):
        super().setUp()
        w = self.w
        for name, wert in (("UI_LOCK_FILE", f"{w}/run/zenos-sperre/bedienung.lock"),
                           ("AUTOMATIC_OFF_FILE", f"{w}/etc/xdg/zenos/kanal-automatik-aus"),
                           ("CHANNEL_PROGRAM", f"{w}/libexec/zenos-kanal"), ("PYTHON", sys.executable)):
            setattr(B, name, wert)
        U.schreiben(B.CHANNEL_PROGRAM, f"W = {w!r}\n" + KANAL, 0o755)
        # Nach apt: der Paketstand danach, und die Auswertung danach findet nichts mehr
        self.sim(U.SIM_OHNE_KERNEL, nachher=U.SIM_LEER)
        self.paketstand(U.STAND_NACHHER, "nachher.txt")
        self.units = []
        self.ersatz = {}
        for name in ("start_unit", "interactive", "ask", "hand_run"):
            self.addCleanup(setattr, B, name, getattr(B, name))
        B.start_unit = self.einheit
        B.interactive = lambda: True
        self.antworten = []
        B.ask = self.fragen
        self.fragen_gestellt = []

    # --- Helfer ---

    def einheit(self, key, follow=False):
        """Die Units im Prozess: pruefen → cmd_check, installieren → cmd_install (liest auftrag.json)."""
        self.units.append(key)
        if key in self.ersatz:
            return self.ersatz[key]()
        befehl = {"pruefen": B.cmd_check, "installieren": B.cmd_install}[key]
        return befehl([])

    def fragen(self, prompt):
        self.fragen_gestellt.append(prompt)
        if not self.antworten:
            raise AssertionError(f"unerwartete Frage: {prompt}")
        antwort = self.antworten.pop(0)
        if isinstance(antwort, BaseException):
            raise antwort
        return antwort

    def darf(self, antwort):
        U.schreiben(f"{self.w}/darf.json", json.dumps(antwort))

    def darf_aufrufe(self):
        try:
            with open(f"{self.w}/darf-aufrufe", encoding="utf-8") as f:
                return [json.loads(z) for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def datei(self, name):
        return B.state_path(name)

    def letzte(self):
        return self.json(B.LAST) if os.path.exists(self.datei(B.LAST)) else None

    def automatik(self, art="lauf"):
        return self.lauf(B.cmd_automatic, [art])

    def update(self, *argumente):
        return self.lauf(B.cmd_update, list(argumente))

    def apt_updates(self):
        return [a for a in self.apt_aufrufe() if "update" in a["args"]]

    def spaeter(self, minuten):
        """Die eingefrorene Uhr weiterstellen (stand.json und letzte.json eines späteren Laufs sind dann neuer)."""
        t = JETZT + datetime.timedelta(minutes=minuten)
        B.now = lambda: t


class Update(Bedienung):
    """zenos-basis update: der Basis-Schritt von zen update."""

    def test_ja_installiert_genau_diese_liste(self):
        self.antworten = ["ja"]
        code, aus = self.update()
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.units, ["pruefen", "installieren"])
        stand_liste = self.install_aufrufe()
        self.assertEqual(len(stand_liste), 1, "install.sh lief nach apt")
        letzte = self.letzte()
        self.assertEqual((letzte["ergebnis"], letzte["von"], letzte["zustimmung"]), ("installiert", "zen update", True))
        self.assertIn("Ubuntu-Basis: 6 Updates (4 Sicherheit) bereit.", aus)
        self.assertIn("  Updates: 6, davon Sicherheit: 4", aus)
        self.assertIn("  Kernel, Firmware, Bootloader: nein", aus)
        self.assertIn("  Auch aus Herstellerquellen: Example Vendor LLC", aus)
        self.assertIn("Ubuntu-Basis: installiert – 6 Pakete aktualisiert, gesund.", aus)
        self.assertEqual(len(self.fragen_gestellt), 1)
        self.assertIn(f"({letzte['liste'][:12]})", self.fragen_gestellt[0])
        self.assertFalse(os.path.exists(self.datei(B.ORDER)))

    def test_nein_aendert_nichts(self):
        for antwort in ("nein", "", "Ja", "ja bitte"):
            with self.subTest(antwort=antwort):
                self.antworten = [antwort]
                self.units = []
                code, aus = self.update()
                self.assertEqual(code, 10, aus)
                self.assertEqual(self.units, ["pruefen"])
                self.assertIn("Nichts geändert.", aus)
                self.assertIsNone(self.letzte())
                self.assertFalse(os.path.exists(self.datei(B.ORDER)))
        self.assertEqual(self.install_aufrufe(), [])

    def test_ja_ohne_rueckfrage_auch_ohne_terminal(self):
        B.interactive = lambda: False
        code, aus = self.update()
        self.assertEqual(code, 10, aus)
        self.assertIn("Bestätigen geht nur im Terminal (zen update) oder mit «zen update --ja»", aus)
        self.assertIsNone(self.letzte())
        code, aus = self.update("--ja")
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.fragen_gestellt, [], "--ja fragt nie")
        self.assertEqual((self.letzte()["von"], self.letzte()["zustimmung"]), ("zen update", True))

    def test_kernel_mit_ja(self):
        """Kernel, Firmware, Bootloader: das «ja» ist die Zustimmung; zen update sagt, dass danach ein Neustart nötig
        ist (zenOS startet nie selbst neu)."""
        self.sim(U.SIM_MIT_KERNEL, nachher=U.SIM_LEER)
        self.antworten = ["ja"]
        code, aus = self.update()
        self.assertEqual(code, 0, aus)
        self.assertIn("  Kernel, Firmware, Bootloader: flash-kernel, linux-firmware-raspi, linux-image-7.0.0-1012-raspi,",
                      aus)
        self.assertIn("danach ist ein Neustart nötig; zenOS startet nie selbst neu", aus)
        self.assertIn("  Neustart voraussichtlich nötig", aus)
        self.assertEqual((self.letzte()["ergebnis"], self.letzte()["zustimmung"]), ("installiert", True))

    def test_aktuell_ohne_frage(self):
        self.sim(U.SIM_LEER)
        code, aus = self.update()
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.units, ["pruefen"])
        self.assertIn("Die Ubuntu-Basis ist aktuell.", aus)
        self.assertEqual(self.fragen_gestellt, [])

    def test_gesperrt_ohne_frage(self):
        self.sim(U.SIM_GESCHUETZT)
        code, aus = self.update("--ja")
        self.assertEqual(code, 3, aus)
        self.assertEqual(self.units, ["pruefen"], "auch --ja installiert nie, was ein geschütztes Paket entfernt")
        self.assertIn("ubuntu-minimal", aus)

    def test_dpkg_unterbrochen(self):
        """Nach einem Abbruch mitten in dpkg: zen update sagt es, die Prüfung holt «dpkg --configure -a» nach, danach
        zählt der Stand von jetzt. Bleibt dpkg unterbrochen: Exit 1, nichts installiert."""
        U.schreiben(f"{B.DPKG_UPDATES}/0000", "")
        self.sim(U.SIM_LEER)
        code, aus = self.update("--ja")
        self.assertEqual(code, 0, aus)
        self.assertIn("dpkg wurde unterbrochen (Abbruch mitten in einem Update): Die Prüfung holt zuerst", aus)
        self.assertIn("dpkg wurde unterbrochen: dpkg --configure -a", aus)
        self.assertIn("Die Ubuntu-Basis ist aktuell.", aus)
        self.assertEqual((self.units, os.listdir(B.DPKG_UPDATES)), (["pruefen"], []))
        U.schreiben(f"{B.DPKG_UPDATES}/0001", "")
        U.schreiben(f"{self.w}/dpkg-bleibt-unterbrochen", "")
        self.spaeter(30)
        code, aus = self.update("--ja")
        self.assertEqual(code, 1, aus)
        self.assertIn("Prüfung gescheitert: dpkg ist unterbrochen", aus)
        self.assertNotIn("installieren", self.units)

    def test_pruefung_scheitert(self):
        U.schreiben(f"{self.w}/apt/update.exit", "100")
        code, aus = self.update()
        self.assertEqual(code, 1, aus)
        self.assertIn("apt-get update endete mit Exit 100", aus)
        self.assertEqual(self.fragen_gestellt, [])

    def test_pruefung_antwortet_nicht(self):
        for exit_code, erwartet, text in ((75, 75, "läuft gerade"), (1, 1, "hat nicht geantwortet (Exit 1")):
            with self.subTest(exit_code=exit_code):
                self.ersatz["pruefen"] = lambda c=exit_code: c
                code, aus = self.update("--ja")
                self.assertEqual(code, erwartet, aus)
                self.assertIn(text, aus)
                self.assertNotIn("installieren", self.units)

    def test_alter_stand_zaehlt_nicht(self):
        """Antwortet die Prüfung nicht, gilt ein stand.json von früher nicht als ihre Antwort."""
        self.lauf(B.cmd_check, [])
        self.spaeter(30)
        self.ersatz["pruefen"] = lambda: 1
        code, aus = self.update("--ja")
        self.assertEqual(code, 1, aus)
        self.assertNotIn("installieren", self.units)

    def test_kanal_unterbrochen_oder_kaputt(self):
        U.schreiben(f"{B.CHANNEL_STATE_DIR}/laeuft.json", "{}\n")
        code, aus = self.update("--ja")
        self.assertEqual((code, self.units), (10, []), aus)
        self.assertIn("Basis-Updates übersprungen: Eine Installation des zenOS-Kanals ist unterbrochen", aus)
        os.unlink(f"{B.CHANNEL_STATE_DIR}/laeuft.json")
        U.schreiben(f"{B.CHANNEL_STATE_DIR}/letzte.json", json.dumps({"ergebnis": "kaputt"}))
        code, aus = self.update("--ja")
        self.assertEqual((code, self.units), (10, []), aus)
        self.assertIn("meldet «kaputt»", aus)

    def test_install_von_hand(self):
        B.hand_run = lambda: 4242
        code, aus = self.update("--ja")
        self.assertEqual((code, self.units), (75, []), aus)
        self.assertIn("PID 4242", aus)

    def test_bedienung_belegt(self):
        fd = B.take_lock(B.UI_LOCK_FILE)
        self.addCleanup(os.close, fd)
        code, aus = self.update("--ja")
        self.assertEqual((code, self.units), (75, []), aus)
        self.assertIn("läuft gerade", aus)

    def test_liste_aendert_sich_vor_dem_installieren(self):
        """Zwischen Prüfen und Installieren kam etwas dazu (etwa unattended-upgrades): Die Unit lehnt ab, nichts wird
        installiert, stand.json zeigt die neue Liste."""
        self.antworten = ["ja"]
        echt = self.einheit

        def dazwischen(key, follow=False):
            if key == "installieren":
                self.sim(U.SIM_GREETD)
            return echt(key, follow)

        B.start_unit = dazwischen
        code, aus = self.update()
        self.assertEqual(code, 3, aus)
        self.assertIsNone(self.letzte(), "apt lief nicht")
        self.assertEqual(self.json(B.STAND)["anzahl"], 1)
        self.assertFalse(os.path.exists(self.datei(B.ORDER)))

    def test_strg_c(self):
        self.antworten = [KeyboardInterrupt()]
        code, aus = self.update()
        self.assertEqual(code, 130, aus)
        self.assertIn("Abgebrochen", aus)
        fd = B.take_lock(B.UI_LOCK_FILE)
        self.assertIsNotNone(fd, "die Sperre ist wieder frei")
        os.close(fd)

    def test_falsche_aufrufe_und_nur_root(self):
        for argumente in (["--JA"], ["--ja", "x"], ["ja"], ["--nur-basis"]):
            with self.subTest(argumente=argumente):
                self.assertEqual(self.update(*argumente)[0], 2)
        B.TRUSTED_UIDS = (0,) if os.geteuid() != 0 else (4242,)
        code, aus = self.update()
        self.assertEqual(code, 2)
        self.assertIn("nur als root", aus)
        self.assertEqual(self.units, [])


class Jetzt(Bedienung):
    """zenos-basis jetzt HASH und zustimmen HASH: die Knöpfe der Einstellungen."""

    def geprueft(self, sim):
        self.sim(sim, nachher=U.SIM_LEER)
        self.assertIn(self.lauf(B.cmd_check, [])[0], (0, 3))
        return self.json(B.STAND)["liste"]

    def test_jetzt_installiert_die_angezeigte_liste(self):
        liste = self.geprueft(U.SIM_OHNE_KERNEL)
        code, aus = self.lauf(lambda a: B.cmd_now(a, False), [liste])
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.units, ["installieren"], "ohne neues apt-get update")
        self.assertEqual(len(self.apt_updates()), 1)
        letzte = self.letzte()
        self.assertEqual((letzte["von"], letzte["zustimmung"], letzte["liste"]), ("einstellungen", False, liste))

    def test_kernel_und_entfernungen_nur_mit_zustimmung(self):
        for sim in (U.SIM_MIT_KERNEL, U.SIM_ENTFERNUNG):
            with self.subTest(sim=sim.splitlines()[-1]):
                liste = self.geprueft(sim)
                code, aus = self.lauf(lambda a: B.cmd_now(a, False), [liste])
                self.assertEqual(code, 10, aus)
                self.assertIsNone(self.letzte(), "ohne Zustimmung lehnt die Unit ab")
                code, aus = self.lauf(lambda a: B.cmd_now(a, True), [liste])
                self.assertEqual(code, 0, aus)
                self.assertEqual((self.letzte()["von"], self.letzte()["zustimmung"]), ("einstellungen", True))
                os.unlink(self.datei(B.LAST))
                os.unlink(f"{self.w}/apt/gelaufen")

    def test_andere_liste_wird_abgelehnt(self):
        self.geprueft(U.SIM_OHNE_KERNEL)
        for zustimmung in (False, True):
            code, aus = self.lauf(lambda a, z=zustimmung: B.cmd_now(a, z), ["0" * 40])
            self.assertEqual(code, 3, aus)
        self.assertIsNone(self.letzte())
        self.assertFalse(os.path.exists(self.datei(B.ORDER)))

    def test_auftrag_bleibt_nicht_liegen(self):
        """Lief die Unit gar nicht (fehlt, Bedingung), bleibt kein Auftrag mit Zustimmung für einen späteren Start."""
        liste = self.geprueft(U.SIM_MIT_KERNEL)
        self.ersatz["installieren"] = lambda: 1
        code, _ = self.lauf(lambda a: B.cmd_now(a, True), [liste])
        self.assertEqual(code, 1)
        self.assertFalse(os.path.exists(self.datei(B.ORDER)))

    def test_falsche_aufrufe_belegt_und_nur_root(self):
        for argumente in ([], ["A" * 40], ["0" * 39], ["0" * 40, "x"], ["0" * 40, "--zustimmung"]):
            for zustimmung in (False, True):
                with self.subTest(argumente=argumente, zustimmung=zustimmung):
                    self.assertEqual(self.lauf(lambda a, z=zustimmung: B.cmd_now(a, z), argumente)[0], 2)
        fd = B.take_lock(B.UI_LOCK_FILE)
        code, aus = self.lauf(lambda a: B.cmd_now(a, False), ["0" * 40])
        os.close(fd)
        self.assertEqual(code, 75, aus)
        B.TRUSTED_UIDS = (0,) if os.geteuid() != 0 else (4242,)
        self.assertEqual(self.lauf(lambda a: B.cmd_now(a, True), ["0" * 40])[0], 2)
        self.assertEqual(self.units, [])

    def test_befehle_im_programm(self):
        self.assertEqual(self.lauf(B.main, ["jetzt"])[0], 2)
        self.assertEqual(self.lauf(B.main, ["zustimmen", "x"])[0], 2)
        self.assertIn("zenos-basis zustimmen HASH", B.__doc__)


class Automatik(Bedienung):
    """zenos-basis automatik lauf|gelegenheit."""

    def letzter_lauf(self):
        return self.json(B.AUTO_LOG)

    def test_lauf_installiert_wenn_er_darf(self):
        self.darf(DARF_JA)
        code, aus = self.automatik()
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.units, ["pruefen", "installieren"])
        self.assertEqual(self.darf_aufrufe(), [["automatik", "darf", "--ohne-ssh", "--json"]])
        letzte = self.letzte()
        self.assertEqual((letzte["ergebnis"], letzte["von"], letzte["zustimmung"]), ("installiert", "automatik", False))
        lauf = self.letzter_lauf()
        self.assertEqual((lauf["art"], lauf["ergebnis"], lauf["zeitpunkt"], lauf["liste"]),
                         ("lauf", "installiert", "jederzeit", letzte["liste"]))
        self.assertFalse(os.path.exists(self.datei(B.READY_MARK)), "danach aktuell")

    def test_nicht_jetzt(self):
        self.darf(DARF_NEIN)
        code, aus = self.automatik()
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.units, ["pruefen"])
        lauf = self.letzter_lauf()
        self.assertEqual((lauf["ergebnis"], lauf["zeitpunkt"]), ("wartet", "fenster"))
        self.assertIn("6 Updates (4 Sicherheit) bereit, nicht jetzt: ausserhalb des Zeitfensters", lauf["grund"])
        self.assertIsNone(self.letzte())
        self.assertTrue(os.path.exists(self.datei(B.READY_MARK)), "die Gelegenheit versucht es später")

    def test_kernel_firmware_bootloader_und_entfernungen_nie(self):
        self.darf(DARF_JA)
        for sim in (U.SIM_MIT_KERNEL, U.SIM_ENTFERNUNG):
            with self.subTest(sim=sim.splitlines()[-1]):
                self.sim(sim)
                self.units = []
                code, aus = self.automatik()
                self.assertEqual(code, 0, aus)
                self.assertEqual(self.units, ["pruefen"])
                lauf = self.letzter_lauf()
                self.assertEqual(lauf["ergebnis"], "zustimmung")
                self.assertEqual(lauf["liste"], self.json(B.STAND)["liste"], "die Oberfläche meldet je Liste einmal")
                self.assertTrue(lauf["grund"].startswith("Basis-Updates warten auf dich: "), lauf["grund"])
                self.assertFalse(os.path.exists(self.datei(B.READY_MARK)))
        self.assertEqual(self.darf_aufrufe(), [], "gefragt wird gar nicht erst")
        self.assertIsNone(self.letzte())
        self.assertEqual(self.install_aufrufe(), [])

    def test_geschuetzt_nie(self):
        self.darf(DARF_JA)
        self.sim(U.SIM_GESCHUETZT)
        self.assertEqual(self.automatik()[0], 0)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "gesperrt")
        self.assertIsNone(self.letzte())

    def test_gelegenheit_ohne_netz(self):
        """Der Lauf (alle 6 h) prüft; die Gelegenheit (alle 15 Min.) installiert die bereite Liste ohne apt-get
        update, sobald sie darf."""
        self.darf(DARF_NEIN)
        self.automatik()
        self.assertEqual(len(self.apt_updates()), 1)
        self.darf(DARF_JA)
        self.units = []
        code, aus = self.automatik("gelegenheit")
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.units, ["installieren"])
        self.assertEqual(len(self.apt_updates()), 1, "kein neues apt-get update")
        self.assertEqual((self.letzter_lauf()["art"], self.letzter_lauf()["ergebnis"]), ("gelegenheit", "installiert"))

    def test_gelegenheit_liste_geaendert(self):
        """Seit der Prüfung brachte etwa unattended-upgrades einen Teil: Die Unit lehnt ab, stand.json zeigt die neue
        Liste, die nächste Gelegenheit nimmt sie."""
        self.darf(DARF_NEIN)
        self.automatik()
        alt = self.json(B.STAND)["liste"]
        self.sim(U.SIM_GREETD)
        self.darf(DARF_JA)
        self.spaeter(15)
        code, aus = self.automatik("gelegenheit")
        self.assertEqual(code, 0, aus)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "wartet")
        self.assertIn("Liste hat sich seit der Prüfung geändert", self.letzter_lauf()["grund"])
        self.assertNotEqual(self.json(B.STAND)["liste"], alt)
        self.assertTrue(os.path.exists(self.datei(B.READY_MARK)))
        self.spaeter(30)
        self.assertEqual(self.automatik("gelegenheit")[0], 0)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "installiert")

    def test_gelegenheit_ohne_stand(self):
        code, aus = self.automatik("gelegenheit")
        self.assertEqual((code, self.units), (0, []), aus)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "nichts")

    def test_notschalter(self):
        self.darf(DARF_JA)
        U.schreiben(B.AUTOMATIC_OFF_FILE, "seit=x\n")
        for art in ("lauf", "gelegenheit"):
            code, aus = self.automatik(art)
            self.assertEqual((code, self.units), (0, []), aus)
            self.assertEqual(self.letzter_lauf()["ergebnis"], "aus")

    def test_kanal_unterbrochen(self):
        self.darf(DARF_JA)
        U.schreiben(f"{B.CHANNEL_STATE_DIR}/laeuft.json", "{}\n")
        code, aus = self.automatik()
        self.assertEqual((code, self.units), (0, []), aus)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "wartet")

    def test_install_von_hand_und_bedienung_belegt(self):
        B.hand_run = lambda: 4242
        self.assertEqual(self.automatik()[0], 75)
        self.assertEqual(self.units, [])
        B.hand_run = lambda: None
        fd = B.take_lock(B.UI_LOCK_FILE)
        code, aus = self.automatik()
        os.close(fd)
        self.assertEqual((code, self.units), (75, []), aus)
        self.assertIn("beim nächsten Mal", aus)

    def test_pruefung_ohne_netz(self):
        """apt-get update scheitert (kein Netz): Die Unit fällt nicht aus (Exit 10), automatik.json nennt es."""
        self.darf(DARF_JA)
        U.schreiben(f"{self.w}/apt/update.exit", "100")
        code, aus = self.automatik()
        self.assertEqual(code, 10, aus)
        self.assertEqual(self.letzter_lauf()["ergebnis"], "fehler")
        self.assertNotIn("installieren", self.units)

    def test_darf_antwortet_nicht_heisst_nein(self):
        for inhalt in ("kein json", json.dumps({"darf": "ja"}), json.dumps({"grund": "x"})):
            with self.subTest(inhalt=inhalt):
                U.schreiben(f"{self.w}/darf.json", inhalt)
                self.units = []
                self.assertEqual(self.automatik()[0], 0)
                self.assertEqual(self.units, ["pruefen"])
                self.assertIn("zenos-kanal automatik darf antwortete nicht", self.letzter_lauf()["grund"])

    def test_zenos_kanal_unsicher_heisst_nein(self):
        self.darf(DARF_JA)
        os.chmod(os.path.dirname(B.CHANNEL_PROGRAM), 0o777)
        self.addCleanup(os.chmod, os.path.dirname(B.CHANNEL_PROGRAM), 0o755)
        self.automatik()
        self.assertEqual(self.letzter_lauf()["ergebnis"], "wartet")
        self.assertIn("zenos-kanal nicht nutzbar", self.letzter_lauf()["grund"])
        self.assertEqual(self.darf_aufrufe(), [])

    def test_anzeige_falsche_aufrufe_und_nur_root(self):
        code, aus = self.lauf(B.cmd_automatic, [])
        self.assertEqual(code, 0)
        self.assertIn("Automatik    an", aus)
        self.darf(DARF_NEIN)
        self.automatik()
        code, aus = self.lauf(B.cmd_automatic, [])
        self.assertIn("zuletzt", aus)
        for argumente in (["jetzt"], ["lauf", "x"], ["an"], ["aus"], ["darf"]):
            self.assertEqual(self.lauf(B.cmd_automatic, argumente)[0], 2, argumente)
        B.TRUSTED_UIDS = (0,) if os.geteuid() != 0 else (4242,)
        self.assertEqual(self.automatik()[0], 2)


class Marker(Bedienung):
    """automatik-bereit gibt es genau dann, wenn die Liste ohne Zustimmung installierbar ist."""

    def test_marker_folgt_dem_stand(self):
        mark = self.datei(B.READY_MARK)
        faelle = ((U.SIM_OHNE_KERNEL, True), (U.SIM_MIT_KERNEL, False), (U.SIM_OHNE_KERNEL, True),
                  (U.SIM_ENTFERNUNG, False), (U.SIM_OHNE_KERNEL, True), (U.SIM_LEER, False),
                  (U.SIM_OHNE_KERNEL, True), (U.SIM_GESCHUETZT, False))
        for sim, erwartet in faelle:
            self.sim(sim)
            self.lauf(B.cmd_check, [])
            self.assertIs(os.path.exists(mark), erwartet, sim.splitlines()[-1])
        self.sim(U.SIM_OHNE_KERNEL)
        self.lauf(B.cmd_check, [])
        U.schreiben(f"{self.w}/apt/update.exit", "100")
        self.lauf(B.cmd_check, [])
        self.assertFalse(os.path.exists(mark), "Prüfung gescheitert")

    def test_nach_der_installation_weg(self):
        self.sim(U.SIM_OHNE_KERNEL, nachher=U.SIM_LEER)
        self.lauf(B.cmd_check, [])
        self.assertTrue(os.path.exists(self.datei(B.READY_MARK)))
        self.auftrag()
        self.assertEqual(self.lauf(B.cmd_install, [])[0], 0)
        self.assertFalse(os.path.exists(self.datei(B.READY_MARK)))


class StartUnit(Bedienung):
    """start_unit mit einer Attrappe für systemctl: Exit aus ExecMainStatus, eine Unit, die gar nicht lief, ist 1."""

    def setUp(self):
        super().setUp()
        B.start_unit = START_UNIT
        U.schreiben(f"{self.w}/bin/systemctl", f"#!{sys.executable} -S\nW = {self.w!r}\n" + SYSTEMCTL, 0o755)
        B.SYSTEMCTL = f"{self.w}/bin/systemctl"
        B.JOURNALCTL = f"{self.w}/bin/journalctl-fehlt"

    def faelle(self, start, status):
        U.schreiben(f"{self.w}/systemctl.start", str(start))
        U.schreiben(f"{self.w}/systemctl.status", status)
        return self.lauf(lambda a: B.start_unit("pruefen"), [])

    def test_exit_aus_execmainstatus(self):
        self.assertEqual(self.faelle(0, "0")[0], 0)
        self.assertEqual(self.faelle(3, "3")[0], 3)
        self.assertEqual(self.faelle(1, "75")[0], 75)
        code, aus = self.faelle(5, "0")
        self.assertEqual(code, 1, "die Unit lief gar nicht")
        self.assertIn("zenos-basis-pruefen.service", aus)
        self.assertEqual(self.faelle(0, "")[0], 0)
        with open(f"{self.w}/systemctl-aufrufe", encoding="utf-8") as f:
            aufrufe = f.read().splitlines()
        self.assertIn("start zenos-basis-pruefen.service", aufrufe)
        self.assertIn("show --property=ExecMainStatus --value zenos-basis-pruefen.service", aufrufe)


class Status(Bedienung):
    def test_automatik_im_status(self):
        self.darf(DARF_NEIN)
        self.automatik()
        code, aus = self.lauf(B.cmd_status, ["--json"])
        self.assertEqual(code, 0)
        daten = json.loads(aus)
        self.assertEqual(daten["automatik"]["an"], True)
        self.assertEqual(daten["automatik"]["zuletzt"]["ergebnis"], "wartet")
        code, aus = self.lauf(B.cmd_status, [])
        self.assertIn("Automatik    an", aus)
        U.schreiben(B.AUTOMATIC_OFF_FILE, "")
        code, aus = self.lauf(B.cmd_status, [])
        self.assertIn("Automatik    aus (Notschalter; sudo zen kanal automatik an)", aus)
        self.assertFalse(json.loads(self.lauf(B.cmd_status, ["--json"])[1])["automatik"]["an"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
