#!/usr/bin/env python3
"""Einheitentests für Bereitstellung, Installation, Gesundheit und Rückweg von scripts/bin/zenos-kanal (zen update,
zen rollback, installieren, nachstart, selbsttest).

Baut auf test/einheiten/kanal.test.py auf (Server, Gerät, Wegwerf-Schlüssel, Pfade im Temp-Ordner). Dazu: ein
install.sh als Attrappe im Repo (stellt das Gerät wie 10-code auf den Stand der Bereitstellung und schreibt das
install.log; mit einer Datei «kaputt» im Stand endet es mit Exit 1), ein scripts/zen für «zen version» und ein Ersatz
für den installierten zenos-kanal beim Selbsttest. Die Units startet der Test nicht über systemd, sondern ruft dieselben
Befehle im Prozess auf. Ohne Root, ohne Netz. Die echten Abläufe mit systemd prüft test/container/kanal-e2e.sh.

  python3 test/einheiten/kanal-installieren.test.py
"""

import contextlib
import datetime
import importlib.machinery
import importlib.util
import io
import json
import fcntl
import os
import re
import signal
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True

_HIER = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("kanal_basis", os.path.join(_HIER, "kanal.test.py"))
_spec = importlib.util.spec_from_loader("kanal_basis", _loader)
B = importlib.util.module_from_spec(_spec)
_loader.exec_module(B)
K = B.K
WURZEL = B.WURZEL


def setUpModule():
    B.setUpModule()


def tearDownModule():
    B.tearDownModule()


INSTALL_ATTRAPPE = """#!/bin/bash
# Attrappe für install.sh (Test): Gerät wie 10-code auf den Stand dieser Quelle, Zeilen ins install.log
# und wie das echte install.sh ins Ergebnis für den Kanal (ZENOS_KANAL_ERGEBNIS)
set -u
quelle=$(cd "$(dirname "$0")/.." && pwd -P)
modus=normal
if [ "${1:-}" = --nur-code ]; then modus=code; fi
marke() {
  printf '%s\\n' "$1" >> "$ZENOS_TEST_LOG"
  if [ -n "${ZENOS_KANAL_ERGEBNIS:-}" ]; then printf '%s\\n' "$1" >> "$ZENOS_KANAL_ERGEBNIS"; fi
}
# Ein Prozess mit Benutzerrechten verändert das install.log (gehört nach einem Lauf von Hand dem Benutzer): kürzt es
# und hängt ein «== Beginn» ohne Ende an
sabotage() {
  if [ -e "$quelle/log-sabotage" ]; then
    : > "$ZENOS_TEST_LOG"
    printf '== Beginn 2026-10-05 10:00:02 · normal · zenOS-Installation\\n' >> "$ZENOS_TEST_LOG"
  fi
}
# Sperre von install.sh belegt: Exit 75, bevor etwas beginnt (wie das echte install.sh)
if [ -e "$ZENOS_TEST_CODE.sperre-belegt" ]; then sabotage; exit 75; fi
printf '\\n' >> "$ZENOS_TEST_LOG"
marke "== Beginn 2026-10-05 10:00:00 · $modus · zenOS-Installation"
commit=$(git -C "$quelle" rev-parse HEAD) || exit 3
git -C "$ZENOS_TEST_CODE" fetch -q --no-tags "$quelle" HEAD || exit 3
git -C "$ZENOS_TEST_CODE" checkout -q --force --detach "$commit" || exit 4
printf '%s %s %s\\n' "$modus" "$commit" "${ZENOS_KANAL_LAUF:-}" >> "$ZENOS_TEST_CODE.laeufe"
if [ "$modus" = normal ] && [ -e "$quelle/greetd-kaputt" ]; then : > "$ZENOS_TEST_CODE.greetd-ausgefallen"; fi
if [ "$modus" = normal ] && [ -e "$quelle/kaputt-und-sperre" ]; then : > "$ZENOS_TEST_CODE.sperre-belegt"; exit 1; fi
if [ "$modus" = normal ] && [ -e "$quelle/kaputt" ]; then exit 1; fi
marke "== Ende 2026-10-05 10:00:01 · $modus · ok · 0 Änderungen · 0 Warnungen"
if [ -e "$quelle/ergebnis-offen" ] && [ -n "${ZENOS_KANAL_ERGEBNIS:-}" ]; then chmod 0666 "$ZENOS_KANAL_ERGEBNIS"; fi
sabotage
"""

# Ein älteres install.sh (etwa v0.1.0-rc3) kennt das Ergebnis für den Kanal nicht und schreibt nur ins install.log
ALTE_ATTRAPPE = "".join(z for z in INSTALL_ATTRAPPE.splitlines(True) if "ZENOS_KANAL_ERGEBNIS" not in z)
assert "ZENOS_KANAL_ERGEBNIS" not in ALTE_ATTRAPPE

ZEN_ATTRAPPE = """#!/bin/bash
if [ "${1:-}" = version ]; then printf 'zenOS        test\\n'; exit 0; fi
exit 2
"""

SELBSTTEST_ATTRAPPE = """import os
import sys
hier = os.path.dirname(os.path.abspath(__file__))
if os.path.exists(os.path.join(hier, "selbsttest-scheitert")):
    print("Selbsttest kaputt")
    sys.exit(3)
if "--tag" in sys.argv and os.path.exists(os.path.join(hier, "tag-widerrufen")):
    print("selbsttest: Tag gilt nicht: Schlüssel widerrufen")
    sys.exit(3)
print("selbsttest ok")
"""

SYSTEMCTL_ATTRAPPE = """#!/bin/sh
# Attrappe für systemctl (Test): greetd gilt als ausgefallen, solange die Marke da ist
if [ "$1" = is-failed ]; then
  for a in "$@"; do last=$a; done
  if [ "$last" = greetd.service ] && [ -e "$ZENOS_TEST_CODE.greetd-ausgefallen" ]; then exit 0; fi
  exit 1
fi
exit 0
"""


class Abgebrochen(BaseException):
    """Ersatz für einen harten Abbruch (kill -9, Strom weg) mitten in install.sh."""


class Geraet(B.Basis):
    """Gerät auf «basis» (mit Attrappen), installiert über den Kanal noch nichts."""

    def setUp(self):
        super().setUp()
        self.log = self.pfad("var", "log", "install.log")
        os.makedirs(os.path.dirname(self.log))
        open(self.log, "w").close()
        laufzeit = self.pfad("run", "zenos-kanal")
        os.makedirs(laufzeit)
        programm = self.pfad("libexec", "zenos-kanal")
        os.makedirs(os.path.dirname(programm))
        with open(programm, "w", encoding="utf-8") as f:
            f.write(SELBSTTEST_ATTRAPPE)
        self.selbsttest_marker = self.pfad("libexec", "selbsttest-scheitert")
        werte = {
            "INSTALL_LOG": self.log,
            "RUNTIME_DIR": laufzeit,
            "UI_LOCK_FILE": self.pfad("run", "sperre", "bedienung.lock"),
            "INSTALLED_PROGRAM": programm,
            "PYTHON": sys.executable,
            "QUICKSHELL": self.pfad("gibt-es-nicht", "quickshell"),
            "SYSTEMD_RUN_DIR": self.pfad("gibt-es-nicht", "systemd"),
            "SPACE_PATHS": (self.ordner,),
            "DPKG_UPDATES": self.pfad("gibt-es-nicht", "dpkg"),
            "INSTALL_PATH": B.SYSTEM_PFAD,
        }
        for name, wert in werte.items():
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)
        alte_umgebung = K.install_env
        self.addCleanup(setattr, K, "install_env", alte_umgebung)
        setattr(K, "install_env", lambda: {**alte_umgebung(), "ZENOS_TEST_LOG": self.log,
                                           "ZENOS_TEST_CODE": K.CODE_DIR})
        self.addCleanup(setattr, K, "start_unit", K.start_unit)
        K.start_unit = self.unit
        self.addCleanup(setattr, K, "interactive", K.interactive)
        self.addCleanup(setattr, K, "ask", K.ask)
        K.interactive = lambda: True
        self.antworten = []
        self.fragen = []
        K.ask = self.antwort
        self.basis = self.commit("basis", {"scripts/install.sh": INSTALL_ATTRAPPE, "scripts/zen": ZEN_ATTRAPPE,
                                           "datei": "basis\n"})
        for name in ("scripts/install.sh", "scripts/zen"):
            os.chmod(os.path.join(self.server, name), 0o755)
        self.git("add", "-A")
        self.git("commit", "-q", "--amend", "-m", "basis")
        self.basis = self.git("rev-parse", "HEAD")
        self.geraet_auf(self.basis)

    # -- Hilfen --

    def unit(self, schluessel, follow=False):
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = {"holen": K.cmd_fetch_internal, "pruefen": K.cmd_check, "installieren": K.cmd_install}[schluessel]([])
        self.protokoll.append((schluessel, rc, aus.getvalue()))
        return rc

    def antwort(self, frage):
        self.fragen.append(frage)
        return self.antworten.pop(0) if self.antworten else ""

    def zen(self, art="update", tag=None):
        """zen update bzw. zen rollback TAG (Operator), Ausgabe in self.ausgabe, Rückgabe der Exit-Code."""
        self.protokoll = []
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.Operator().run({"art": art, "tag": tag})
        self.ausgabe = aus.getvalue() + "".join(p[2] for p in self.protokoll)
        return rc

    def installieren(self):
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.cmd_install([])
        self.ausgabe = aus.getvalue()
        return rc

    def nachstart(self):
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.cmd_after_boot([])
        self.ausgabe = aus.getvalue()
        return rc

    def zustand(self, name):
        return K.load_json(os.path.join(K.STATE_DIR, name))

    def kopf(self):
        return self.git("rev-parse", "HEAD", ort=K.CODE_DIR)

    def laeufe(self):
        try:
            with open(K.CODE_DIR + ".laeufe", encoding="utf-8") as f:
                return [z.split() for z in f.read().splitlines()]
        except FileNotFoundError:
            return []

    def ohne_anker(self):
        """Anker wie im Repo vor den ersten Schlüsseln: nur die Kommentare, ohne Schlüssel- und Serienzeilen."""
        texte = {}
        for name in K.ANCHOR_FILES:
            with open(os.path.join(B.ANKER_REPO, name), encoding="utf-8") as f:
                texte[name] = "".join(z for z in f if not z.strip() or z.lstrip().startswith("#"))
        self.anker_dateien(texte)

    def signiert_installiert(self, name="v0.1.0-rc4"):
        """Signierter Stand NAME auf dem Server, über den Kanal installiert (vorschau)."""
        self.commit(f"stand {name}")
        self.signieren(name)
        self.assertEqual(self.zen(), 0, self.ausgabe)
        return self.git("rev-parse", "HEAD")


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Dev(Geraet):
    def setUp(self):
        super().setUp()
        self.kanal("dev")

    def test_ohne_anker_nur_mit_ja(self):
        # Wie Zenos Pi heute: Anker ohne Schlüssel, Kanal dev, ein neuer unsignierter Commit
        self.ohne_anker()
        neu = self.commit("neu")
        self.antworten = ["nein"]
        self.assertEqual(self.zen(), 10)
        self.assertIn("Anker fehlt", self.ausgabe)
        self.assertIn(neu[:12], self.fragen[0])
        self.assertIn("? " + neu[:12] + " neu", self.ausgabe, "die neuen Commits werden gezeigt")
        self.assertEqual(self.kopf(), self.basis, "ohne «ja» ändert sich nichts")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))
        self.assertEqual(self.laeufe(), [])

        self.antworten = ["ja"]
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertEqual(self.laeufe(), [["normal", neu, "1"]], "install.sh einmal, mit ZENOS_KANAL_LAUF=1")
        gut = self.zustand("gut.json")
        self.assertEqual((gut["commit"], gut["zweig"], gut["freigabe"]), (neu, "dev", "ja"))
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")))
        self.assertEqual(os.listdir(os.path.join(K.STATE_DIR, "bereit")), [neu], "nur der gute Stand bleibt")

        # Danach ist nichts mehr zu tun
        self.assertEqual(self.zen(), 0)
        self.assertIn("Schon installiert", self.ausgabe)
        self.assertEqual(len(self.laeufe()), 1)

    def test_ohne_terminal_nichts(self):
        self.ohne_anker()
        self.commit("neu")
        K.interactive = lambda: False
        self.assertEqual(self.zen(), 10)
        self.assertIn("nur im Terminal", self.ausgabe)
        self.assertEqual((self.kopf(), self.laeufe()), (self.basis, []))

    def test_ja_gilt_nur_fuer_diesen_commit(self):
        self.ohne_anker()
        alt = self.commit("alt")
        self.lauf()
        # Ein «ja» für den alten Stand gilt nicht für einen neueren
        K.write_wish("update", ja=alt)
        self.commit("neuer")
        self.lauf()
        stand = self.zustand("stand.json")
        self.assertEqual(stand["wunsch"]["ergebnis"], "zustimmung")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))

    def test_alle_signiert_ohne_frage(self):
        neu = self.commit("signiert", signiert_mit="rel")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.fragen, [])
        self.assertEqual(self.kopf(), neu)
        self.assertIsNone(self.zustand("gut.json")["freigabe"])

    def test_bereich_wird_beim_installieren_nachgeprueft(self):
        self.commit("signiert", signiert_mit="rel")
        K.write_wish("update")
        rc, stand = self.lauf()
        self.assertEqual(stand["wunsch"]["auftrag"]["bereich_von"], self.basis)
        # Zwischen Prüfen und Installieren wird der Schlüssel widerrufen: nichts
        self.anker(widerrufen=("rel",), release=("rel2",))
        self.assertEqual(self.installieren(), 3)
        self.assertIn("nicht mehr jeder neue Commit ist gültig signiert", self.ausgabe)
        self.assertEqual((self.kopf(), self.laeufe()), (self.basis, []))

    def test_installierter_stand_nicht_gepusht(self):
        # Von Hand: Das Gerät steht auf einem Commit, den origin nicht kennt. Der Vergleich kommt aus /opt/zenos.
        lokal = self.commit("lokal", ort=K.CODE_DIR)
        neu = self.commit("neu", signiert_mit="rel")
        K.write_wish("update")
        rc, stand = self.lauf()
        frage = stand["wunsch"]["frage"]
        self.assertTrue(any("liegt nicht in origin/dev" in g for g in frage["gruende"]), frage)
        self.assertFalse(any("Vergleich" in g for g in frage["gruende"]), "Rückfrage-Pfade liessen sich vergleichen")
        self.assertNotEqual(lokal, neu)

    def test_unsignierter_zwischencommit_fragt(self):
        self.commit("unsigniert")
        neu = self.commit("oben signiert", signiert_mit="rel")
        self.antworten = ["ja"]
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertIn("1 von 2 neuen Commits sind nicht gültig signiert", self.ausgabe)
        self.assertEqual(self.kopf(), neu)

    def test_umgeschrieben_fragt(self):
        # Installiert ist x, dann wird dev auf origin umgeschrieben (basis → y): nur mit «ja»
        self.commit("x", signiert_mit="rel")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.git("reset", "-q", "--hard", self.basis)
        neu = self.commit("y", signiert_mit="rel")
        self.antworten = ["ja"]
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertIn("liegt nicht in origin/dev", self.ausgabe)
        self.assertEqual(self.kopf(), neu)


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Signiert(Geraet):
    def test_vorschau_installiert_signiert(self):
        neu = self.signiert_installiert("v0.1.0-rc4")
        self.assertEqual(self.fragen, [])
        self.assertEqual(self.kopf(), neu)
        gut = self.zustand("gut.json")
        self.assertEqual((gut["tag"], gut["signiert"]), ("v0.1.0-rc4", True))
        self.assertEqual(self.hoechste(), "v0.1.0-rc4")
        self.assertEqual(self.zen(), 0)
        self.assertIn("Schon installiert", self.ausgabe)

    def test_stabil_nimmt_kein_rc_und_ohne_anker_nichts(self):
        self.kanal("stabil")
        self.commit("rc")
        self.signieren("v0.1.0-rc4")
        self.assertEqual(self.zen(), 0)
        self.assertIn("Keine gültig signierte Version", self.ausgabe)
        self.ohne_anker()
        self.assertEqual(self.zen(), 3)
        self.assertIn("Anker fehlt", self.ausgabe)
        self.assertEqual(self.laeufe(), [])

    def test_kaputtes_install_rueckweg(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("kaputt", {"kaputt": "1\n"})
        self.signieren("v0.2.0-rc1")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        letzte = self.zustand("letzte.json")
        self.assertEqual(letzte["ergebnis"], "zurueck")
        self.assertIn("install.sh endete mit Exit 1", letzte["grund"])
        self.assertEqual(self.kopf(), gut, "zurück auf dem Stand davor")
        self.assertFalse(os.path.exists(os.path.join(K.CODE_DIR, "kaputt")))
        self.assertEqual([z[0] for z in self.laeufe()], ["normal", "normal", "normal"])
        self.assertTrue(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt", "v0.2.0-rc1")))
        self.assertEqual(self.zustand("gut.json")["commit"], gut)
        self.assertEqual(self.hoechste(), "v0.1.0-rc4", "eine gescheiterte Version hebt hoechste nicht")
        # zen update lässt die gesperrte Version aus (wie die Anzeige); noch einmal versuchen geht bewusst mit
        # zen rollback und nur mit «ja», ohne bleibt alles
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertIn("Schon installiert", self.ausgabe)
        self.assertIn("v0.2.0-rc1 ist gesperrt (eine Installation scheiterte) und kein Ziel; noch einmal versuchen: "
                      "zen rollback v0.2.0-rc1", self.ausgabe)
        self.assertEqual((self.kopf(), self.fragen), (gut, []))
        self.assertEqual(self.zen("rollback", "v0.2.0-rc1"), 10)
        self.assertIn("gesperrt", self.ausgabe)
        self.assertEqual(self.kopf(), gut)

    def test_leeres_zen_ist_nicht_gesund(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("zen leer", {"scripts/zen": ""})
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        grund = self.zustand("letzte.json")["grund"]
        self.assertIn("scripts/zen fehlt oder ist leer", grund)
        self.assertIn("zen version läuft nicht", grund)
        self.assertEqual(self.kopf(), gut)

    def test_selbsttest_scheitert_rueckweg(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("weiter")
        self.signieren("v0.1.0-rc5")
        open(self.selbsttest_marker, "w").close()
        self.assertEqual(self.zen(), 5, self.ausgabe)
        letzte = self.zustand("letzte.json")
        self.assertEqual(letzte["ergebnis"], "kaputt", "auch der Rückweg besteht den Selbsttest nicht")
        self.assertIn("Selbsttest", letzte["grund"])
        self.assertIn("ANLEITUNG", letzte["grund"])
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")), "kaputt: keine weiteren Versuche")
        self.assertEqual(self.kopf(), gut, "der Rückweg lief trotzdem")
        os.unlink(self.selbsttest_marker)

    def test_platz_fehlt(self):
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        self.addCleanup(setattr, K, "MIN_FREE", K.MIN_FREE)
        K.MIN_FREE = 1 << 62
        self.assertEqual(self.zen(), 10)
        self.assertIn("frei", self.ausgabe)
        self.assertEqual((self.kopf(), self.laeufe()), (self.basis, []))

    def test_rueckfrage_pfade(self):
        self.signiert_installiert("v0.1.0-rc4")
        neu = self.commit("netz", {"scripts/module/35-netzwerk.sh": "# neu\n"})
        self.signieren("v0.1.0-rc5")
        # Der Stand allein meldet «zustimmung»
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (10, "zustimmung"))
        self.assertEqual(stand["bereit"]["rueckfrage"], ["scripts/module/35-netzwerk.sh"])
        # zen update fragt, auch wenn alles signiert ist
        self.antworten = ["nein"]
        self.assertEqual(self.zen(), 10)
        self.assertIn("Betrifft Firewall, Netz oder Boot: scripts/module/35-netzwerk.sh", self.ausgabe)
        self.antworten = ["ja"]
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)

    def test_rueckfrage_liste_des_neuen_stands_kommt_dazu(self):
        self.signiert_installiert("v0.1.0-rc4")
        with open(os.path.join(WURZEL, "scripts", "lib", "sensible-pfade"), encoding="utf-8") as f:
            liste = f.read() + "boot system/neu-boot/\n"
        self.commit("neue Liste", {"scripts/lib/sensible-pfade": liste, "system/neu-boot/x": "1\n"})
        self.signieren("v0.1.0-rc5")
        rc, stand = self.lauf()
        self.assertEqual(stand["bereit"]["rueckfrage"], ["system/neu-boot/x"])

    def test_auftrag_veraendert(self):
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        self.zen_bis_bereit()
        auftrag = self.zustand("auftrag.json")
        with open(os.path.join(auftrag["pfad"], "datei"), "w", encoding="utf-8") as f:
            f.write("untergeschoben\n")
        self.assertEqual(self.installieren(), 3)
        self.assertIn("Bereitstellung fehlt, ist verändert", self.ausgabe)
        self.assertEqual((self.kopf(), self.laeufe()), (self.basis, []))

    def test_auftrag_zu_alt(self):
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        self.zen_bis_bereit()
        pfad = os.path.join(K.STATE_DIR, "auftrag.json")
        auftrag = self.zustand("auftrag.json")
        # Nur die Uhr springt (NTP nach dem Start): Der Auftrag gilt weiter (Prüfung, Befund 15c)
        if auftrag.get("start"):
            self.assertTrue(K.fresh(auftrag, K.now() + datetime.timedelta(hours=3)), "nur die Uhr sprang")
            auftrag["seit_start"] -= 7200
        else:
            auftrag["zeit"] = K.iso(K.now() - datetime.timedelta(hours=2))
        K.write_json(pfad, auftrag)
        self.assertEqual(self.installieren(), 3)
        self.assertIn("älter als eine Stunde", self.ausgabe)
        self.assertEqual(self.laeufe(), [])

    def test_signatur_gilt_bei_der_installation_nicht_mehr(self):
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        self.zen_bis_bereit()
        self.anker(widerrufen=("rel",), release=("rel2",))
        self.assertEqual(self.installieren(), 3)
        self.assertIn("Signatur gilt nicht mehr", self.ausgabe)
        self.assertEqual(self.laeufe(), [])

    def zen_bis_bereit(self):
        """Wunsch, holen, prüfen: bis auftrag.json, ohne zu installieren."""
        K.write_wish("update")
        rc, stand = self.lauf()
        self.assertEqual(stand["wunsch"]["ergebnis"], "bereitgestellt", stand["wunsch"])


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Abbruch(Geraet):
    def abbrechen_nach_install(self):
        """Der nächste install.sh-Lauf übernimmt den Code und wird danach hart abgebrochen."""
        echt = K.run_visible

        def ersatz(argv, env, timeout=None, cwd="/"):
            rc = echt(argv, env, timeout, cwd)
            if argv[0].endswith("/scripts/install.sh") and "--nur-code" not in argv:
                K.run_visible = echt
                raise Abgebrochen()
            return rc

        self.addCleanup(setattr, K, "run_visible", echt)
        K.run_visible = ersatz

    def test_abbruch_nachstart_fortsetzen(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.commit("neu")
        self.signieren("v0.1.0-rc5")
        self.abbrechen_nach_install()
        with self.assertRaises(Abgebrochen):
            self.zen()
        laeuft = self.zustand("laeuft.json")
        self.assertEqual((laeuft["phase"], laeuft["versuche"]["ziel"], laeuft["ziel"]["commit"]), ("ziel", 1, neu))
        self.assertEqual(laeuft["rueckweg"]["commit"], gut)
        # Halbe Übernahme nachstellen: /opt/zenos zeigt noch auf den alten Stand
        self.git("checkout", "-q", "--force", "--detach", gut, ort=K.CODE_DIR)
        self.assertEqual(K.installation_summary()[0], "unterbrochen")
        # Beim Start, vor dem Login: nur der Code
        self.assertEqual(self.nachstart(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertEqual(self.laeufe()[-1][:2], ["code", neu])
        self.assertTrue(os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")), "der Rest steht noch aus")
        # zen update setzt fort
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertIn("unterbrochen", self.ausgabe)
        self.assertEqual(self.zustand("letzte.json")["versuche"]["ziel"], 2)
        self.assertEqual(self.zustand("gut.json")["commit"], neu)
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")))

    def test_zweimal_unterbrochen_rueckweg(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("neu")
        self.signieren("v0.1.0-rc5")
        self.abbrechen_nach_install()
        with self.assertRaises(Abgebrochen):
            self.zen()
        self.abbrechen_nach_install()
        with self.assertRaises(Abgebrochen):
            self.installieren()
        self.assertEqual(self.zustand("laeuft.json")["versuche"]["ziel"], 2)
        # Nach dem zweiten Abbruch nimmt nachstart den Code des Rückwegs und sperrt die Version
        self.assertEqual(self.nachstart(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), gut)
        self.assertEqual(self.zustand("laeuft.json")["phase"], "rueckweg")
        self.assertTrue(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt", "v0.1.0-rc5")))
        self.assertEqual(self.installieren(), 4, self.ausgabe)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "zurueck")
        self.assertEqual(self.kopf(), gut)

    def test_nachstart_ohne_lauf(self):
        self.assertEqual(self.nachstart(), 0)
        self.assertIn("Keine unterbrochene", self.ausgabe)

    def test_alter_rueckweg_ohne_nur_code(self):
        # Ein Rückweg auf einen Stand, dessen install.sh --nur-code nicht kennt: nachstart lässt ihn für zen update
        alt = INSTALL_ATTRAPPE.replace("--nur-code", "--nur-kode")
        self.commit("alt", {"scripts/install.sh": alt})
        self.signieren("v0.1.0-rc3")
        gut = self.git("rev-parse", "HEAD")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.commit("neu", {"scripts/install.sh": INSTALL_ATTRAPPE})
        self.signieren("v0.1.0-rc4")
        for _ in range(2):
            self.abbrechen_nach_install()
            with self.assertRaises(Abgebrochen):
                self.installieren() if os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")) else self.zen()
        self.assertEqual(self.nachstart(), 0, self.ausgabe)
        self.assertIn("kennt --nur-code nicht", self.ausgabe)
        self.assertEqual(self.installieren(), 4, self.ausgabe)
        self.assertEqual(self.kopf(), gut)


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Rollback(Geraet):
    def test_signiert_ohne_frage_hoechste_bleibt(self):
        self.commit("rc3")
        rc3 = self.git("rev-parse", "HEAD")
        self.signieren("v0.1.0-rc3")
        rc4 = self.signiert_installiert("v0.1.0-rc4")
        self.assertEqual(self.zen("rollback", "v0.1.0-rc3"), 0, self.ausgabe)
        self.assertEqual(self.fragen, [])
        self.assertEqual(self.kopf(), rc3)
        self.assertEqual(self.hoechste(), "v0.1.0-rc4")
        # zen update kehrt auf den Kanal zurück
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), rc4)

    def test_unsigniert_nur_mit_ja_fuer_das_objekt(self):
        self.signiert_installiert("v0.1.0-rc4")
        self.git("checkout", "-q", "-b", "alt", self.basis)
        self.unsigniert("v0.1.0-rc2")
        self.git("checkout", "-q", "dev")
        objekt = self.git("rev-parse", "refs/tags/v0.1.0-rc2")
        self.lauf()
        # Ein «ja» für den Commit statt für das Tag-Objekt zählt nicht
        K.write_wish("rollback", tag="v0.1.0-rc2", ja=self.basis)
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["wunsch"]["ergebnis"]), (10, "zustimmung"))
        self.assertEqual(stand["wunsch"]["frage"]["id"], objekt)
        self.antworten = ["ja"]
        self.assertEqual(self.zen("rollback", "v0.1.0-rc2"), 0, self.ausgabe)
        self.assertIn("ungeprüft (nicht gültig signiert: unsigniert)", self.ausgabe)
        self.assertEqual(self.kopf(), self.basis)

    def test_unbekannter_tag(self):
        self.assertEqual(self.zen("rollback", "v9.9.9"), 3)
        self.assertIn("gibt es auf origin nicht", self.ausgabe)

    def test_vertrauens_tag_ist_kein_stand(self):
        self.assertEqual(K.cmd_rollback(["vertrauen/0002"]), 2)


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Weiteres(Geraet):
    def test_rueckfrage_liste_wie_sensible_pfade(self):
        gruppen = []
        with open(os.path.join(WURZEL, "scripts", "lib", "sensible-pfade"), encoding="utf-8") as f:
            for zeile in f:
                teile = zeile.split()
                if len(teile) == 2 and teile[0] in K.CONSENT_GROUPS:
                    gruppen.append(teile[1])
        self.assertEqual(sorted(gruppen), sorted(K.CONSENT_PATHS))

    def test_bedienung_gesperrt(self):
        os.makedirs(os.path.dirname(K.UI_LOCK_FILE), mode=0o700, exist_ok=True)
        fd = os.open(K.UI_LOCK_FILE, os.O_WRONLY | os.O_CREAT, 0o644)
        self.addCleanup(os.close, fd)
        import fcntl
        fcntl.flock(fd, fcntl.LOCK_EX)
        self.assertEqual(self.zen(), 75)
        self.assertIn("läuft gerade", self.ausgabe)

    def test_angehalten_wird_ersetzt(self):
        neu = self.signiert_installiert("v0.1.0-rc4")
        with open(os.path.join(K.CODE_DIR, "datei"), "w", encoding="utf-8") as f:
            f.write("von Hand\n")
        K.write_json(os.path.join(K.STATE_DIR, "angehalten"), {"version": 1, "commit": neu, "zeit": K.iso(K.now())})
        self.assertEqual(K.installation_summary()[0], "angehalten")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.git("status", "--porcelain", ort=K.CODE_DIR), "")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "angehalten")))
        self.assertEqual(K.installation_summary()[0], "gut")

    def test_status_zeigt_installation(self):
        self.signiert_installiert("v0.1.0-rc4")
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            K.cmd_status([])
            K.cmd_status(["--installation"])
        text = aus.getvalue()
        self.assertRegex(text, r"Update +v0\.1\.0-rc4 \(")
        self.assertTrue(text.splitlines()[-1].startswith("gut v0.1.0-rc4"))

    def test_selbsttest(self):
        self.commit("neu")
        objekt = self.signieren("v0.1.0-rc4")
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            self.assertEqual(K.cmd_selftest(["--anker", "--tag", "v0.1.0-rc4", objekt, self.server]), 0)
            self.assertEqual(K.cmd_selftest(["--tag", "v0.1.0-rc5", objekt, self.server]), 3)
            self.ohne_anker()
            self.assertEqual(K.cmd_selftest([]), 0, "ohne Anker (dev) reicht es, dass er läuft")
            self.assertEqual(K.cmd_selftest(["--anker"]), 3)
        self.assertIn("Feld «tag»", aus.getvalue())

    def test_zustand_nicht_sicher(self):
        os.makedirs(K.STATE_DIR, exist_ok=True)
        os.chmod(K.STATE_DIR, 0o777)
        self.addCleanup(os.chmod, K.STATE_DIR, 0o755)
        K.write_json(os.path.join(K.STATE_DIR, "auftrag.json"), {"version": 1})
        self.assertEqual(self.installieren(), 1)
        self.assertIn("Zustand unsicher", self.ausgabe)

    def test_hilfe_nennt_alle_befehle(self):
        for befehl in ("update", "rollback", "installieren", "nachstart", "selbsttest"):
            self.assertRegex(K.__doc__, re.compile(rf"^  zenos-kanal {befehl}\b", re.M))


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Befunde(Geraet):
    """Angriffe und Ausfälle aus der Prüfung von Schritt 4, je mit dem Ablauf, der vorher scheiterte."""

    def hand_lauf(self):
        """Ein Prozess install.sh (wartet nur), als wäre ein install.sh von Hand am Laufen; dazu sein Vermerk."""
        programm = self.pfad("install.sh")
        with open(programm, "w", encoding="utf-8") as f:
            f.write("import time\ntime.sleep(60)\n")
        proc = subprocess.Popen([sys.executable, programm])
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        os.makedirs(os.path.dirname(K.HAND_MARK), mode=0o700, exist_ok=True)
        with open(K.HAND_MARK, "w", encoding="utf-8") as f:
            f.write(f"{proc.pid}\n")
        return proc

    @unittest.skipUnless(os.path.exists("/proc/self"), "der Vermerk gilt nur mit /proc (Linux)")
    def test_lauf_von_hand_haelt_den_kanal_an(self):
        """Befund 2: Die Abstimmung mit install.sh von Hand geht nicht mehr über eine Sperre in /run/lock (die jeder
        Benutzer halten konnte), sondern über einen Vermerk, den nur root schreibt. Solange er gilt: 75, nichts
        installiert. Ein Vermerk eines beendeten Prozesses zählt nicht."""
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        proc = self.hand_lauf()
        self.assertEqual(self.zen(), 75, self.ausgabe)
        self.assertIn(f"install.sh von Hand läuft gerade (PID {proc.pid})", self.ausgabe)
        K.write_wish("update")
        self.lauf()
        self.assertEqual(self.installieren(), 75, self.ausgabe)
        self.assertTrue(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")), "der Auftrag bleibt")
        self.assertEqual(self.laeufe(), [])
        proc.kill()
        proc.wait()
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), self.git("rev-parse", "HEAD"))

    def test_sperre_von_install_sh_belegt(self):
        """Befund 2 (Probe B2): Kam install.sh nicht an seine Sperre (Exit 75, nichts begonnen), wurde die Version
        gesperrt, der Rückweg scheiterte an derselben Sperre: «kaputt». Jetzt zählt der Versuch nicht."""
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("neu")
        self.signieren("v0.1.0-rc5")
        marke = K.CODE_DIR + ".sperre-belegt"
        open(marke, "w").close()
        self.assertEqual(self.zen(), 75, self.ausgabe)
        self.assertIn("kam nicht an seine Sperre", self.ausgabe)
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt")), "nichts gesperrt")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")), "nichts begonnen")
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert", "letzte.json bleibt")
        self.assertEqual(self.kopf(), gut)
        os.unlink(marke)
        self.assertEqual(self.zen(), 0, self.ausgabe)
        # Belegt erst beim Rückweg: laeuft.json bleibt (Phase Rückweg), der nächste Lauf vollendet ihn
        self.commit("kaputt", {"kaputt-und-sperre": "1\n"})
        self.signieren("v0.1.0-rc6")
        self.assertEqual(self.zen(), 75, self.ausgabe)
        laeuft = self.zustand("laeuft.json")
        self.assertEqual((laeuft["phase"], laeuft["versuche"]["rueckweg"]), ("rueckweg", 0))
        os.unlink(marke)
        self.assertEqual(self.zen(), 4, self.ausgabe)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "zurueck")

    def test_greetd_war_schon_ausgefallen(self):
        """Befund 9: greetd fiel schon vor dem Update aus. Früher «kaputt» bei jedem Versuch, auch für das Update, das
        es reparieren soll. Jetzt zählt nur, was das Update verschlechtert."""
        systemd = self.pfad("systemd")
        os.makedirs(systemd)
        systemctl = self.pfad("systemctl")
        with open(systemctl, "w", encoding="utf-8") as f:
            f.write(SYSTEMCTL_ATTRAPPE)
        os.chmod(systemctl, 0o755)
        for name, wert in (("SYSTEMD_RUN_DIR", systemd), ("SYSTEMCTL", systemctl), ("LOGINCTL", "/bin/false")):
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)
        self.signiert_installiert("v0.1.0-rc4")
        marke = K.CODE_DIR + ".greetd-ausgefallen"
        open(marke, "w").close()
        neu = self.commit("fix")
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertIn("greetd war schon vor dem Update ausgefallen", " ".join(self.zustand("letzte.json")["hinweise"]))
        # Fällt greetd erst durch das Update aus, ist es nicht gesund; der Rückweg gelingt trotzdem
        os.unlink(marke)
        self.commit("bricht greetd", {"greetd-kaputt": "1\n"})
        self.signieren("v0.1.0-rc6")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        letzte = self.zustand("letzte.json")
        self.assertEqual(letzte["ergebnis"], "zurueck")
        self.assertIn("greetd ist ausgefallen", letzte["grund"])
        self.assertEqual(self.kopf(), neu)

    def test_zurueckgebliebene_git_sperren(self):
        """Befund 10: Strom weg mitten in 10-code liess .git/index.lock liegen; danach scheiterten Ziel, Rückweg und
        Notweg. Jetzt räumt der Kanal sie unter seiner Sperre weg (installieren und nachstart)."""
        gitdir = os.path.join(K.CODE_DIR, ".git")
        for name in ("index.lock", "HEAD.lock", os.path.join("refs", "heads", "dev.lock")):
            open(os.path.join(gitdir, name), "w").close()
        neu = self.commit("neu")
        self.signieren("v0.1.0-rc4")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertIn("index.lock", " ".join(self.zustand("letzte.json")["hinweise"]))
        self.assertFalse(os.path.exists(os.path.join(gitdir, "index.lock")))
        # nachstart ebenso
        K.write_json(os.path.join(K.STATE_DIR, "laeuft.json"), {
            "version": 1, "phase": "ziel", "versuche": {"ziel": 1, "rueckweg": 0}, "rueckweg": None, "grund": None,
            "ziel": {**self.zustand("gut.json"), "pfad": os.path.join(K.STATE_DIR, "bereit", neu)}})
        open(os.path.join(gitdir, "index.lock"), "w").close()
        self.assertEqual(self.nachstart(), 0, self.ausgabe)
        self.assertIn("index.lock", self.ausgabe)
        self.assertFalse(os.path.exists(os.path.join(gitdir, "index.lock")))

    def test_stand_nach_der_installation(self):
        """Befund 12: stand.json zeigte nach zen update noch die Lage davor («neue Version bereit», «von Hand
        geändert?»). Jetzt prüft zen update danach neu; und status merkt, wenn seither installiert wurde."""
        self.signiert_installiert("v0.1.0-rc4")
        neu = self.commit("neu")
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        stand = self.zustand("stand.json")
        self.assertEqual((stand["zustand"], stand["installiert"]["commit"], stand["hoechste"]),
                         ("aktuell", neu, "v0.1.0-rc5"))
        with contextlib.redirect_stdout(io.StringIO()) as aus:
            K.cmd_status(["--kurz"])
        self.assertTrue(aus.getvalue().startswith("aktuell "), aus.getvalue())
        # Ohne die Prüfung danach (Installation von Hand über die Unit): «veraltet» statt falscher Meldungen
        self.commit("weiter")
        self.signieren("v0.1.0-rc6")
        K.write_wish("update")
        self.lauf()
        self.assertEqual(self.installieren(), 0, self.ausgabe)
        with contextlib.redirect_stdout(io.StringIO()) as aus:
            K.cmd_status(["--kurz"])
            K.cmd_status([])
        self.assertTrue(aus.getvalue().startswith("veraltet Seit der letzten Prüfung wurde installiert"),
                        aus.getvalue())
        self.assertNotIn("von Hand geändert", aus.getvalue())

    def test_selbsttest_probelauf(self):
        """Befund 13: Ein Laufzeitfehler in update galt als gesund, das nächste zen update brach ab. Der Selbsttest
        macht jetzt einen Probelauf (status, update, rollback, installieren, nachstart) im Wegwerf-Zustand."""
        self.signiert_installiert("v0.1.0-rc4")
        self.commit("neu")
        self.signieren("v0.1.0-rc5")
        self.lauf()
        vorher = {n: open(os.path.join(K.STATE_DIR, n), encoding="utf-8").read()
                  for n in ("stand.json", "gesehen.json", "gut.json", "hoechste")}
        bereit = sorted(os.listdir(os.path.join(K.STATE_DIR, "bereit")))
        werte = (K.STATE_DIR, K.LOCK_FILE, K.DRY_RUN, K.start_unit)
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_selftest(["--anker", "--probelauf"]), 0, aus.getvalue())
        nachher = {n: open(os.path.join(K.STATE_DIR, n), encoding="utf-8").read() for n in vorher}
        self.assertEqual(vorher, nachher, "der echte Zustand bleibt")
        self.assertEqual(sorted(os.listdir(os.path.join(K.STATE_DIR, "bereit"))), bereit, "nichts bereitgestellt")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "selbsttest")))
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "auftrag.json")))
        self.assertEqual((K.STATE_DIR, K.LOCK_FILE, K.DRY_RUN, K.start_unit), werte, "alles zurückgestellt")
        self.assertEqual(self.laeufe()[-1][1], self.kopf(), "kein install.sh im Probelauf")
        for ziel, wo in ((K.Operator, "steps"), (K.Check, "fulfil"), (K.Installation, "new_run")):
            echt = getattr(ziel, wo)

            def kaputt(*_a, **_k):
                raise RuntimeError("Probe: Laufzeitfehler")

            setattr(ziel, wo, kaputt)
            try:
                with contextlib.redirect_stdout(io.StringIO()) as aus:
                    self.assertEqual(K.cmd_selftest(["--probelauf"]), 1, wo)
                    self.assertEqual(K.cmd_selftest([]), 0, "ohne --probelauf kein Probelauf")
            finally:
                setattr(ziel, wo, echt)
            self.assertIn("Probelauf", aus.getvalue())
            self.assertIn("RuntimeError: Probe: Laufzeitfehler", aus.getvalue())

    def test_probelauf_nur_fuer_einen_geaenderten_updater(self):
        """Der Probelauf läuft nur, wenn der Stand einen anderen zenos-kanal brachte, der ihn kennt, und nie beim
        Rückweg: Ein Fehlalarm darin machte sonst Ziel und Rückweg «kaputt» (im Ende-zu-Ende-Test passiert)."""
        protokoll = self.pfad("selbsttest.argv")
        with open(K.INSTALLED_PROGRAM, "a", encoding="utf-8") as f:
            f.write(f"open({protokoll!r}, 'a').write(' '.join(sys.argv[1:]) + chr(10))\n")
        self.signiert_installiert("v0.1.0-rc4")
        echt = K.run_visible
        self.addCleanup(setattr, K, "run_visible", echt)

        def neuer_updater(argv, env, timeout=None, cwd="/"):
            rc = echt(argv, env, timeout, cwd)
            with open(K.INSTALLED_PROGRAM, "a", encoding="utf-8") as f:
                f.write("# neue Fassung, kennt --probelauf\n")
            return rc

        K.run_visible = neuer_updater
        self.commit("neu")
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.commit("kaputt", {"kaputt": "1\n"})
        self.signieren("v0.1.0-rc6")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        with open(protokoll, encoding="utf-8") as f:
            aufrufe = f.read().splitlines()
        self.assertNotIn("--probelauf", aufrufe[0], "unverändert: kein Probelauf")
        self.assertIn("--probelauf", aufrufe[1], "geändert: Probelauf")
        self.assertIn("--probelauf", aufrufe[2], "Ziel rc6: Probelauf")
        self.assertEqual(aufrufe[3], "selbsttest --anker", "Rückweg: nur der Anker")

    def test_syntaxfehler_in_zen_d(self):
        """Befund 13: bash -n prüfte nur scripts/zen, nicht scripts/zen.d/*.sh und install.sh."""
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("kaputtes zen.d", {"scripts/zen.d/kaputt.sh": "befehl_kaputt() {\n  if true; then\n}\n"})
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        self.assertIn("Syntaxfehler in scripts/zen.d/kaputt.sh", self.zustand("letzte.json")["grund"])
        self.assertEqual(self.kopf(), gut)

    def test_alte_bereitstellung_ohne_tag(self):
        """Befund 6 (Probe D): Eine alte Bereitstellung desselben Commits (von dev, ohne den Tag) wurde übernommen,
        das signierte Ziel bei jedem Versuch abgelehnt («Tag fehlt in der Bereitstellung»). Jetzt immer neu."""
        self.kanal("dev")
        c = self.commit("c")
        self.antworten = ["ja"]
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertTrue(os.path.isdir(os.path.join(K.STATE_DIR, "bereit", c)))
        self.signieren("v0.2.0")
        self.kanal("vorschau")
        K.write_json(os.path.join(K.STATE_DIR, "angehalten"), {"version": 1, "commit": c, "zeit": K.iso(K.now())})
        for _ in range(2):
            rc = self.zen()
            self.assertNotIn("fehlt in der Bereitstellung", self.ausgabe)
            self.assertEqual(rc, 0, self.ausgabe)
        gut = self.zustand("gut.json")
        self.assertEqual((gut["tag"], gut["commit"], gut["signiert"]), ("v0.2.0", c, True))

    def test_nur_gepruefte_tags_in_der_bereitstellung(self):
        """Befund 8: Alle Tags von origin kamen in die Bereitstellung und nach /opt/zenos, ein fremder v9.9.9 auf
        demselben Commit fälschte «zen version». Jetzt nur der geprüfte Ziel-Tag (dev: nur gültige)."""
        neu = self.commit("neu")
        self.signieren("v0.2.0")
        self.git("-c", "user.name=Fremd", "tag", "-a", "-m", "fremd", "v9.9.9", ort=self.server,
                 pruefen=True)
        self.assertEqual(self.zen(), 0, self.ausgabe)
        tags = self.git("tag", "-l", ort=os.path.join(K.STATE_DIR, "bereit", neu)).split()
        self.assertEqual(tags, ["v0.2.0"])
        self.kanal("dev")
        weiter = self.commit("weiter", signiert_mit="rel")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        tags = self.git("tag", "-l", ort=os.path.join(K.STATE_DIR, "bereit", weiter)).split()
        self.assertEqual(tags, ["v0.2.0"])

    def test_rueckweg_auf_widerrufenen_schluessel(self):
        """Befund 18b: Der Rückweg auf einen Stand, dessen Schlüssel inzwischen widerrufen ist, scheiterte am Selbsttest
        (--tag): «kaputt», obwohl der alte Stand läuft. Beim Rückweg prüft der Selbsttest den Tag nicht mehr."""
        gut = self.signiert_installiert("v0.1.0-rc4")
        open(os.path.join(os.path.dirname(K.INSTALLED_PROGRAM), "tag-widerrufen"), "w").close()
        self.commit("kaputt", {"kaputt": "1\n"})
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "zurueck")
        self.assertEqual(self.kopf(), gut)

    def test_gescheitert_bleibt_sichtbar(self):
        """Befund 16: «gescheitert» fiel in doctor auf «gut» zurück, und ein späteres «abgelehnt» überschrieb ein
        «kaputt» oder «zurueck» in letzte.json."""
        self.kanal("dev")
        kaputt = self.commit("kaputt", {"kaputt": "1\n"})
        self.geraet_auf(kaputt)
        os.makedirs(K.STATE_DIR, exist_ok=True)
        K.write_json(os.path.join(K.STATE_DIR, "angehalten"), {"version": 1, "commit": kaputt,
                                                               "zeit": K.iso(K.now())})
        self.antworten = ["ja"]
        self.assertEqual(self.zen(), 4, self.ausgabe)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "gescheitert")
        self.assertEqual(K.installation_summary()[0], "gescheitert")
        K.write_json(os.path.join(K.STATE_DIR, "auftrag.json"), {"version": 1})
        self.assertEqual(self.installieren(), 3)
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "gescheitert", "abgelehnt überschreibt nichts")

    def test_stopp_vor_install_sh(self):
        """Befund 19c: Kam der Stopp (Ausschalten) vor install.sh, startete es trotzdem mitten im Herunterfahren."""
        self.commit("neu")
        self.signieren("v0.1.0-rc4")
        echt = K.dpkg_repair
        self.addCleanup(setattr, K, "dpkg_repair", echt)
        K.dpkg_repair = lambda: os.kill(os.getpid(), signal.SIGTERM)
        self.assertEqual(self.zen(), 10, self.ausgabe)
        self.assertIn("Stopp verlangt", self.ausgabe)
        self.assertEqual(self.laeufe(), [])
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "laeuft.json")))

    def test_pruefung_belegt_gibt_75(self):
        """Befund 15a: Hielt ein anderer Lauf die Kanal-Sperre, endete zen update mit 1 statt 75."""
        os.makedirs(os.path.dirname(K.LOCK_FILE), mode=0o700, exist_ok=True)
        fd = os.open(K.LOCK_FILE, os.O_WRONLY | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        self.commit("neu")
        self.assertEqual(self.zen(), 75, self.ausgabe)
        self.assertIn("läuft gerade", self.ausgabe)

    def test_ohne_netz_wartet(self):
        """Befund 15b: Erstes zen update ohne Netz auf dev ohne Anker: «abgelehnt – origin/dev fehlt» statt «wartet»."""
        self.kanal("dev")
        self.ohne_anker()
        self.git("remote", "set-url", "origin", f"file://{self.pfad('gibt-es-nicht')}", ort=K.CODE_DIR)
        self.assertEqual(self.zen(), 10, self.ausgabe)
        self.assertIn("Kein Kontakt zu origin", self.ausgabe)
        self.assertNotIn("origin/dev fehlt", self.ausgabe)


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Wechseln(Geraet):
    """Befund rel-03: Einen Befehl für den Kanal gab es nicht; wer wechseln wollte, schrieb die Datei von Hand (ohne
    sudo scheiterte es, ein Tippfehler blockierte den Kanal)."""

    def wechseln(self, *argv):
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(aus):
            rc = K.cmd_switch_channel(list(argv))
        self.ausgabe = aus.getvalue()
        return rc

    def kanal_datei(self):
        with open(K.CHANNEL_FILE, encoding="utf-8") as f:
            return f.read()

    def test_setzt_nur_feste_woerter(self):
        self.kanal("dev")
        self.assertEqual(self.wechseln("vorschau"), 0, self.ausgabe)
        self.assertEqual(self.kanal_datei(), "vorschau\n")
        self.assertEqual(os.stat(K.CHANNEL_FILE).st_mode & 0o777, 0o644)
        self.assertEqual(K.read_channel(), ("vorschau", None))
        self.assertIn("Kanal: vorschau, vorher dev", self.ausgabe)
        self.assertIn("zen update", self.ausgabe)
        self.assertEqual(self.wechseln("vorschau"), 0)
        self.assertIn("schon vorschau", self.ausgabe)
        for falsch in (("main",), ("Stabil",), ("",), ("dev\nstabil",), ("../x",), (), ("stabil", "dev")):
            with self.subTest(argumente=falsch):
                self.assertEqual(self.wechseln(*falsch), K.EXIT_USAGE)
                self.assertEqual(self.kanal_datei(), "vorschau\n", "nichts geändert")
        # Ein unbekannter Wert (der Kanal war blockiert) wird ersetzt
        self.kanal("kaputt")
        self.assertEqual(self.wechseln("stabil"), 0, self.ausgabe)
        self.assertIn("vorher unbekannt", self.ausgabe)
        self.assertEqual(self.kanal_datei(), "stabil\n")

    def test_nur_als_root(self):
        if os.geteuid() == 0:
            self.skipTest("als root gibt es keinen fremden Benutzer")
        self.kanal("dev")
        self.addCleanup(setattr, K, "TRUSTED_UIDS", K.TRUSTED_UIDS)
        K.TRUSTED_UIDS = (0,)
        self.assertEqual(self.wechseln("stabil"), K.EXIT_USAGE)
        self.assertIn("nur als root", self.ausgabe)
        self.assertEqual(self.kanal_datei(), "dev\n")

    def test_ohne_anker_ein_hinweis(self):
        self.kanal("dev")
        self.ohne_anker()
        self.assertEqual(self.wechseln("stabil"), 0, self.ausgabe)
        self.assertIn("Anker fehlt", self.ausgabe)
        self.assertIn("sudo zen kanal anker", self.ausgabe)
        self.assertNotIn("1Password", self.ausgabe)

    def test_zurueck_von_dev_ist_ein_rueckschritt_nur_mit_ja(self):
        # Der Pi nach rc4 weiter auf dev, dann zurück auf vorschau: rc4 ist älter als der installierte Stand
        self.kanal("dev")
        self.commit("rc4", signiert_mit="rel")
        self.signieren("v0.1.0-rc4")
        neuer = self.commit("danach", signiert_mit="rel")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neuer)
        self.assertEqual(self.wechseln("vorschau"), 0, self.ausgabe)
        self.assertIn("Rückschritt", self.ausgabe)
        self.antworten = ["nein"]
        self.assertEqual(self.zen(), 10, self.ausgabe)
        self.assertIn("Rückschritt", self.ausgabe)
        self.assertEqual(self.kopf(), neuer, "ohne «ja» bleibt der Stand")


@unittest.skipUnless(B.HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Ergebnis(Geraet):
    """Befund sich-01: Die Gesundheitsprüfung stützte sich auf das install.log, das nach einem Lauf von Hand dem
    Benutzer gehört. Ein Prozess mit Benutzerrechten konnte es kürzen oder ein «== Beginn» anhängen; die gültige
    Version wurde gesperrt, und das Gerät ging zurück. Jetzt zählt nur das root-eigene Ergebnis von install.sh."""

    def ergebnis(self):
        with open(os.path.join(K.STATE_DIR, K.INSTALL_RESULT), encoding="utf-8") as f:
            return f.read().splitlines()

    def test_veraendertes_install_log_sperrt_nichts(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        neu = self.commit("neu", {"log-sabotage": "1\n"})
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertNotEqual(neu, gut)
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt")), "nichts gesperrt")
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert")
        with open(self.log, encoding="utf-8") as f:
            self.assertFalse(K.marks_ok(f.read().splitlines()), "das install.log allein sähe nicht gesund aus")
        self.assertEqual(self.ergebnis(), ["== Beginn 2026-10-05 10:00:00 · normal · zenOS-Installation",
                                           "== Ende 2026-10-05 10:00:01 · normal · ok · 0 Änderungen · 0 Warnungen"],
                         "nur dieser Lauf, ohne die Zeilen davor")

    def test_veraendertes_install_log_macht_aus_belegt_keinen_fehlschlag(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("neu", {"log-sabotage": "1\n"})
        self.signieren("v0.1.0-rc5")
        marke = K.CODE_DIR + ".sperre-belegt"
        open(marke, "w").close()
        self.addCleanup(lambda: os.path.exists(marke) and os.unlink(marke))
        self.assertEqual(self.zen(), 75, self.ausgabe)
        self.assertIn("kam nicht an seine Sperre", self.ausgabe)
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "gesperrt")), "nichts gesperrt")
        self.assertEqual(self.kopf(), gut)

    def test_ergebnis_fuer_andere_schreibbar_zaehlt_nicht(self):
        gut = self.signiert_installiert("v0.1.0-rc4")
        self.commit("offen", {"ergebnis-offen": "1\n"})
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 4, self.ausgabe)
        letzte = self.zustand("letzte.json")
        self.assertEqual(letzte["ergebnis"], "zurueck")
        self.assertIn(f"im {os.path.join(K.STATE_DIR, K.INSTALL_RESULT)} fehlt «== Ende … ok»", letzte["grund"])
        self.assertEqual(self.kopf(), gut)

    def test_aelteres_install_sh_nutzt_das_install_log(self):
        # Ein Stand vor dieser Änderung (etwa v0.1.0-rc3) schreibt kein Ergebnis: Für ihn gilt weiter das install.log
        self.signiert_installiert("v0.1.0-rc4")
        neu = self.commit("alt", {"scripts/install.sh": ALTE_ATTRAPPE})
        self.signieren("v0.1.0-rc5")
        self.assertEqual(self.zen(), 0, self.ausgabe)
        self.assertEqual(self.kopf(), neu)
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, K.INSTALL_RESULT)), "das alte Ergebnis ist weg")
        self.assertEqual(self.zustand("letzte.json")["ergebnis"], "installiert")


if __name__ == "__main__":
    unittest.main(verbosity=1)
