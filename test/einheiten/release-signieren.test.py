#!/usr/bin/env python3
"""Einheitentests für scripts/release-signieren.sh (signierte Releases und Tags vertrauen/NNNN) und für den Anker
system/vertrauen im Repo.

Alles mit Wegwerf-Repos und Wegwerf-Schlüsseln im Temp-Ordner, erzeugt zur Laufzeit: ein «origin» als blankes Repo,
ein Arbeits-Checkout mit dem Skript und einem Anker aus Testschlüsseln. Signiert wird mit ssh-keygen über einen
eigenen ssh-agent (ZENOS_TEST_SIGNIERPROGRAMM), nie mit 1Password und nie mit dem ssh-agent des Benutzers. gh ist ein
Ersatzskript mit festem CI-Stand; nichts geht ins Netz. Das Skript läuft mit dem bash aus /usr/bin:/bin, auf dem Mac
also mit bash 3.2 wie bei Zeno. Ohne git, ssh-keygen, ssh-agent oder ssh-add werden die Tests übersprungen.

  python3 test/einheiten/release-signieren.test.py
"""

import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKRIPT = os.path.join(WURZEL, "scripts", "release-signieren.sh")
LISTE = os.path.join(WURZEL, "scripts", "lib", "sensible-pfade")
ANKER = os.path.join(WURZEL, "system", "vertrauen")

SYSTEM_PFAD = "/usr/bin:/bin:/usr/sbin:/sbin"
WERKZEUGE = ("git", "ssh-keygen", "ssh-agent", "ssh-add", "bash", "awk", "comm", "cmp")
HAT_WERKZEUGE = all(shutil.which(w, path=SYSTEM_PFAD) for w in WERKZEUGE)

ED25519 = r"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}"

# Signiert mit dem Schlüssel aus FAKE_PRIVAT statt mit dem verlangten (für «falscher Schlüssel hat signiert»)
FALSCH_SIGNIEREN = """#!/bin/bash
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -f) args+=(-f "$FAKE_PRIVAT"); shift 2 ;;
    -U) shift ;;
    *) args+=("$1"); shift ;;
  esac
done
exec ssh-keygen "${args[@]}"
"""

# Ersatz für gh: meldet den CI-Stand aus FAKE_GH_STAND
GH = """#!/bin/sh
printf '%s\\n' "${FAKE_GH_STAND:-completed success}"
"""

_modul = {}


def setUpModule():
    if not HAT_WERKZEUGE:
        return
    # Kurzer Pfad: Unix-Sockets dürfen höchstens etwa 100 Zeichen lang sein (macOS: /var/folders/… ist zu lang)
    basis = "/tmp" if os.path.isdir("/tmp") else None
    ordner = tempfile.mkdtemp(prefix="zrs.", dir=basis)
    _modul["ordner"] = ordner
    schluessel = {}
    for name in ("rel", "rel2", "wur", "fremd"):
        pfad = os.path.join(ordner, name)
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "", "-f", pfad], check=True,
                       env={"PATH": SYSTEM_PFAD, "HOME": ordner})
        with open(pfad + ".pub", encoding="utf-8") as f:
            schluessel[name] = " ".join(f.read().split()[:2])
    _modul["schluessel"] = schluessel
    sock = os.path.join(ordner, "a.sock")
    _modul["agent"] = subprocess.Popen(["ssh-agent", "-D", "-a", sock], stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, env={"PATH": SYSTEM_PFAD, "HOME": ordner})
    for _ in range(100):
        if os.path.exists(sock):
            break
        time.sleep(0.05)
    _modul["sock"] = sock
    # «fremd» bleibt absichtlich draussen
    subprocess.run(["ssh-add", "-q"] + [os.path.join(ordner, n) for n in ("rel", "rel2", "wur")], check=True,
                   env={"PATH": SYSTEM_PFAD, "HOME": ordner, "SSH_AUTH_SOCK": sock},
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def tearDownModule():
    agent = _modul.get("agent")
    if agent is not None:
        agent.terminate()
        try:
            agent.wait(timeout=5)
        except subprocess.TimeoutExpired:
            agent.kill()
    if _modul.get("ordner"):
        shutil.rmtree(_modul["ordner"], ignore_errors=True)


def k(name):
    return _modul["schluessel"][name]


def anker(release=("rel",), wurzel="wur", widerrufen=(), serie=1, kommentar="# Testanker"):
    """Dateien für system/vertrauen; Schlüssel über ihre Namen."""
    return {
        "system/vertrauen/release": kommentar + "\n" + "".join(
            f'zenos-release namespaces="git" {k(n)}\n' for n in release),
        "system/vertrauen/wurzel": kommentar + "\n" + (f'zenos-wurzel namespaces="git" {k(wurzel)}\n' if wurzel else ""),
        "system/vertrauen/widerrufen": kommentar + "\n" + "".join(f"{k(n)}\n" for n in widerrufen),
        "system/vertrauen/serie": kommentar + "\n" + (f"{serie}\n" if serie else ""),
    }


@unittest.skipUnless(HAT_WERKZEUGE, "git, ssh-keygen, ssh-agent oder ssh-add fehlt")
class Basis(unittest.TestCase):
    """origin mit dev: «basis» (Anker nur mit Kommentaren wie im Repo, unsignierter Tag v0.1.0-rc3), darauf
    «vertrauen: erste Schlüssel» (Anker rel/wur, Serie 1) mit einer Änderung an system/pam."""

    def setUp(self):
        self.ordner = tempfile.mkdtemp(prefix="zenos-signieren-test.")
        self.home = os.path.join(self.ordner, "home")
        self.bin = os.path.join(self.ordner, "bin")
        os.makedirs(self.home)
        os.makedirs(self.bin)
        self.datei(os.path.join(self.bin, "gh"), GH, ausfuehrbar=True)
        self.origin = os.path.join(self.ordner, "origin.git")
        self.mac = os.path.join(self.ordner, "mac")
        self.git("init", "-q", "--bare", "-b", "dev", self.origin, ort=self.ordner)
        self.git("init", "-q", "-b", "dev", self.mac, ort=self.ordner)
        self.git("remote", "add", "origin", self.origin)

        dateien = {"README.md": "Test\n", "system/pam/zenos-sperre": "auth required pam_unix.so\n",
                   "shell/leiste/Uhr.qml": "Item {}\n"}
        for name in ("release", "wurzel", "widerrufen", "serie"):
            with open(os.path.join(ANKER, name), encoding="utf-8") as f:
                dateien[f"system/vertrauen/{name}"] = f.read()
        with open(SKRIPT, encoding="utf-8") as f:
            dateien["scripts/release-signieren.sh"] = f.read()
        with open(LISTE, encoding="utf-8") as f:
            dateien["scripts/lib/sensible-pfade"] = f.read()
        self.commit("basis", dateien)
        os.chmod(os.path.join(self.mac, "scripts", "release-signieren.sh"), 0o755)
        self.git("add", "-A")
        self.git("commit", "-q", "--amend", "--no-edit")
        self.git("tag", "-a", "-m", "rc3", "v0.1.0-rc3")
        self.git("push", "-q", "origin", "dev", "refs/tags/v0.1.0-rc3")

        erste = anker()
        erste["system/pam/zenos-sperre"] = "auth required pam_unix.so\naccount required pam_unix.so\n"
        erste["shell/leiste/Uhr.qml"] = "Item { id: uhr }\n"
        self.commit("vertrauen: erste Schlüssel", erste)
        self.git("push", "-q", "origin", "dev")

    def tearDown(self):
        shutil.rmtree(self.ordner, ignore_errors=True)

    # --- Hilfen ---

    def umgebung(self, **extra):
        umgebung = {
            "PATH": f"{self.bin}:{SYSTEM_PFAD}",
            "HOME": self.home,
            "TMPDIR": self.ordner,
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid",
            "LC_ALL": "C",
            "SSH_AUTH_SOCK": _modul["sock"],
            "ZENOS_TEST_SIGNIERPROGRAMM": "ssh-keygen",
        }
        umgebung.update(extra)
        return {s: w for s, w in umgebung.items() if w is not None}

    def datei(self, pfad, inhalt, ausfuehrbar=False):
        os.makedirs(os.path.dirname(pfad), exist_ok=True)
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(inhalt)
        if ausfuehrbar:
            os.chmod(pfad, 0o755)
        return pfad

    def git(self, *argumente, ort=None, pruefen=True):
        ergebnis = subprocess.run(["git", *argumente], cwd=ort or self.mac, env=self.umgebung(),
                                  capture_output=True, text=True, timeout=30, check=False)
        if pruefen:
            self.assertEqual(ergebnis.returncode, 0, f"git {' '.join(argumente)}: {ergebnis.stderr}")
        return ergebnis.stdout.strip()

    def commit(self, nachricht, dateien):
        for name, inhalt in dateien.items():
            self.datei(os.path.join(self.mac, name), inhalt)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", nachricht)
        return self.git("rev-parse", "HEAD")

    def lauf(self, *argumente, eingabe="", **extra):
        ergebnis = subprocess.run(["bash", os.path.join(self.mac, "scripts", "release-signieren.sh"), *argumente],
                                  cwd=self.mac, env=self.umgebung(**extra), input=eingabe,
                                  capture_output=True, text=True, timeout=60, check=False)
        ergebnis.ausgabe = ergebnis.stdout + ergebnis.stderr
        return ergebnis

    def remote_tag(self, name):
        zeilen = self.git("ls-remote", "--refs", "origin", f"refs/tags/{name}")
        return zeilen.split()[0] if zeilen else ""

    def lokal_tag(self, name):
        return self.git("rev-parse", "-q", "--verify", f"refs/tags/{name}", pruefen=False)

    def signers(self, name, schluessel, prinzipal):
        return self.datei(os.path.join(self.ordner, name),
                          "".join(f'{prinzipal} namespaces="git" {k(s)}\n' for s in schluessel))

    def verify(self, tag, signers, widerrufen=None):
        argumente = ["-c", "gpg.ssh.program=ssh-keygen", "-c", f"gpg.ssh.allowedSignersFile={signers}"]
        if widerrufen:
            argumente += ["-c", f"gpg.ssh.revocationFile={widerrufen}"]
        ergebnis = subprocess.run(["git", *argumente, "verify-tag", "--raw", tag], cwd=self.mac, env=self.umgebung(),
                                  capture_output=True, text=True, timeout=30, check=False)
        return ergebnis.returncode, ergebnis.stdout + ergebnis.stderr

    def signiert(self, tag, eingabe="ja\nja\n"):
        ergebnis = self.lauf(tag, eingabe=eingabe)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.ausgabe)
        return ergebnis

    def falsch_programm(self, schluessel):
        programm = self.datei(os.path.join(self.bin, "falsch-signieren"), FALSCH_SIGNIEREN, ausfuehrbar=True)
        return {"ZENOS_TEST_SIGNIERPROGRAMM": programm,
                "FAKE_PRIVAT": os.path.join(_modul["ordner"], schluessel)}

    def kein_tag(self, name):
        self.assertEqual(self.lokal_tag(name), "", f"lokaler Tag {name} liegt noch da")
        self.assertEqual(self.remote_tag(name), "", f"Tag {name} ist auf origin")


class Release(Basis):
    def test_erstes_signiertes_release(self):
        ergebnis = self.signiert("v0.1.0-rc4")
        a = ergebnis.ausgabe
        self.assertIn("TESTMODUS", a)
        self.assertIn("Kanal vorschau", a)
        self.assertIn("Letztes Release: v0.1.0-rc3 (unsigniert)", a)
        self.assertIn("ERSTER ANKER", a)
        self.assertIn("vertrauen: erste Schlüssel", a)
        self.assertIn("Anmeldung und Rechte", a)
        self.assertIn("system/pam/zenos-sperre", a)
        self.assertIn("Vertrauen und Updates", a)
        self.assertIn("system/vertrauen/release", a)
        self.assertNotIn("shell/leiste/Uhr.qml", a.split("Sensible Pfade")[1])
        self.assertIn("Gepusht", a)

        oid = self.lokal_tag("v0.1.0-rc4")
        self.assertTrue(oid)
        self.assertEqual(self.remote_tag("v0.1.0-rc4"), oid)
        roh = self.git("cat-file", "tag", oid)
        self.assertIn(f"object {self.git('rev-parse', 'HEAD')}\n", roh)
        self.assertIn("type commit\n", roh)
        self.assertIn("tag v0.1.0-rc4\n", roh)
        self.assertIn("zenOS v0.1.0-rc4", roh)
        self.assertEqual(roh.count("-----BEGIN SSH SIGNATURE-----"), 1)

        rc, text = self.verify("v0.1.0-rc4", self.signers("rel.signers", ["rel"], "zenos-release"))
        self.assertEqual(rc, 0, text)
        self.assertIn("for zenos-release with", text)
        # Weder die Wurzel noch ein fremder Schlüssel gilt für diesen Tag
        rc, _ = self.verify("v0.1.0-rc4", self.signers("wur.signers", ["wur"], "zenos-wurzel"))
        self.assertNotEqual(rc, 0)
        widerrufen = self.datei(os.path.join(self.ordner, "wid"), k("rel") + "\n")
        rc, _ = self.verify("v0.1.0-rc4", self.signers("rel.signers", ["rel"], "zenos-release"), widerrufen)
        self.assertNotEqual(rc, 0)

    def test_nicht_pushen(self):
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nnein\n")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.ausgabe)
        self.assertIn("Nicht gepusht", ergebnis.ausgabe)
        self.assertTrue(self.lokal_tag("v0.1.0-rc4"))
        self.assertEqual(self.remote_tag("v0.1.0-rc4"), "")

    def test_abbruch_vor_dem_signieren(self):
        for eingabe in ("nein\n", "\n", "", "Ja\n"):
            with self.subTest(eingabe=eingabe):
                ergebnis = self.lauf("v0.1.0-rc4", eingabe=eingabe)
                self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
                self.assertIn("Durchgesehen?", ergebnis.ausgabe)
                self.assertIn("Nichts signiert", ergebnis.ausgabe)
                self.kein_tag("v0.1.0-rc4")

    def test_diff_der_sensiblen_pfade(self):
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="d\nja\nnein\n")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.ausgabe)
        self.assertIn("diff --git a/system/pam/zenos-sperre", ergebnis.ausgabe)
        self.assertIn("+account required pam_unix.so", ergebnis.ausgabe)
        self.assertNotIn("diff --git a/shell/leiste/Uhr.qml", ergebnis.ausgabe)

    def test_arbeitsbaum_nicht_sauber(self):
        self.datei(os.path.join(self.mac, "neu.txt"), "x\n")
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("nicht sauber", ergebnis.ausgabe)
        self.kein_tag("v0.1.0-rc4")

    def test_head_nicht_auf_origin(self):
        self.commit("lokal", {"README.md": "lokal\n"})
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("nicht auf origin", ergebnis.ausgabe)
        self.kein_tag("v0.1.0-rc4")

    def test_tag_gibt_es_schon(self):
        ergebnis = self.lauf("v0.1.0-rc3", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("auf origin schon", ergebnis.ausgabe)
        self.git("tag", "v0.1.0-rc4")
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("lokal schon", ergebnis.ausgabe)
        self.assertEqual(self.remote_tag("v0.1.0-rc4"), "")

    def test_versionen(self):
        faelle = [("v0.1.0-rc2", False), ("v0.0.9", False), ("v0.1.0-rc10", True), ("v0.1.0", True),
                  ("v0.2.0-rc1", True), ("v1.0.0", True), ("v0.1.1", True)]
        for name, hoeher in faelle:
            with self.subTest(name=name):
                ergebnis = self.lauf(name, eingabe="nein\n")
                self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
                if hoeher:
                    self.assertIn("Durchgesehen?", ergebnis.ausgabe)
                    self.assertIn("Kanal stabil" if "-rc" not in name else "Kanal vorschau", ergebnis.ausgabe)
                else:
                    self.assertIn("nicht höher", ergebnis.ausgabe)
                    self.assertNotIn("Durchgesehen?", ergebnis.ausgabe)
                self.kein_tag(name)

    def test_rc_nach_finalem_release(self):
        self.git("tag", "-a", "-m", "final", "v0.1.0")
        self.git("push", "-q", "origin", "refs/tags/v0.1.0")
        ergebnis = self.lauf("v0.1.0-rc5", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("nicht höher als das letzte Release v0.1.0", ergebnis.ausgabe)

    def test_ungueltiger_name(self):
        for name in ("0.1.0", "v0.1", "v01.0.0", "v0.1.0-rc0", "v0.1.0-beta1", "v0.1.0-rc", "vertrauen/0002"):
            with self.subTest(name=name):
                ergebnis = self.lauf(name, eingabe="ja\nja\n")
                self.assertEqual(ergebnis.returncode, 2, ergebnis.ausgabe)
        ergebnis = self.lauf(eingabe="")
        self.assertEqual(ergebnis.returncode, 2)

    def test_anker_ohne_schluessel(self):
        dateien = {}
        for name in ("release", "wurzel", "widerrufen", "serie"):
            with open(os.path.join(ANKER, name), encoding="utf-8") as f:
                dateien[f"system/vertrauen/{name}"] = f.read()
        self.commit("anker leer", dateien)
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("Anker unvollständig", ergebnis.ausgabe)
        self.assertNotIn("Durchgesehen?", ergebnis.ausgabe)
        self.kein_tag("v0.1.0-rc4")

    def test_anker_ungueltig(self):
        faelle = {
            "anderer Prinzipal": {"system/vertrauen/release": f'zenos-wurzel namespaces="git" {k("rel")}\n'},
            "Option": {"system/vertrauen/release": f'zenos-release cert-authority,namespaces="git" {k("rel")}\n'},
            "Kommentar hinter dem Schlüssel": {
                "system/vertrauen/release": f'zenos-release namespaces="git" {k("rel")} zeno@mac\n'},
            "RSA": {"system/vertrauen/release": 'zenos-release namespaces="git" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ\n'},
            "Wurzel gleich Release": anker(release=("rel",), wurzel="rel"),
            "Release widerrufen": anker(release=("rel",), widerrufen=("rel",)),
            "zwei Wurzeln": {"system/vertrauen/wurzel":
                             f'zenos-wurzel namespaces="git" {k("wur")}\nzenos-wurzel namespaces="git" {k("rel2")}\n'},
            "Serie keine Zahl": {"system/vertrauen/serie": "eins\n"},
            "Serie 0": {"system/vertrauen/serie": "0\n"},
            "Widerruf mit Prinzipal": {"system/vertrauen/widerrufen": f'zenos-release {k("fremd")}\n'},
        }
        basis = self.git("rev-parse", "HEAD")
        for fall, dateien in faelle.items():
            with self.subTest(fall=fall):
                self.git("reset", "-q", "--hard", basis)
                self.commit(fall, dateien)
                self.git("push", "-q", "--force", "origin", "dev")
                ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
                self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
                self.assertIn("Anker unvollständig", ergebnis.ausgabe)
                self.kein_tag("v0.1.0-rc4")

    def test_schluessel_nicht_verfuegbar(self):
        self.commit("anker fremd", anker(release=("fremd",)))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("Signieren ist fehlgeschlagen", ergebnis.ausgabe)
        self.kein_tag("v0.1.0-rc4")

    def test_falscher_schluessel_hat_signiert(self):
        for schluessel in ("fremd", "wur"):
            with self.subTest(schluessel=schluessel):
                ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n", **self.falsch_programm(schluessel))
                self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
                self.assertIn("besteht die Prüfung nicht", ergebnis.ausgabe)
                self.assertIn("wieder gelöscht", ergebnis.ausgabe)
                self.kein_tag("v0.1.0-rc4")

    def test_ci_rot(self):
        for stand in ("completed failure", "completed cancelled"):
            with self.subTest(stand=stand):
                ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n", FAKE_GH_STAND=stand)
                self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
                self.assertIn("nicht grün", ergebnis.ausgabe)
                self.assertNotIn("Durchgesehen?", ergebnis.ausgabe)
                self.kein_tag("v0.1.0-rc4")

    def test_ci_offen(self):
        for stand, text in (("in_progress ", "läuft noch"), ("null null", "keinen Lauf"),
                            ("completed success", "ist grün")):
            with self.subTest(stand=stand):
                ergebnis = self.lauf("v0.1.0-rc4", eingabe="nein\n", FAKE_GH_STAND=stand)
                self.assertIn(text, ergebnis.ausgabe)
                self.assertIn("Durchgesehen?", ergebnis.ausgabe)

    def test_ohne_gh(self):
        if shutil.which("gh", path=SYSTEM_PFAD):
            self.skipTest("gh liegt im System-PATH")
        os.remove(os.path.join(self.bin, "gh"))
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="nein\n")
        self.assertIn("CI nicht geprüft: gh fehlt", ergebnis.ausgabe)
        self.assertIn("Durchgesehen?", ergebnis.ausgabe)

    def test_verschobener_tag(self):
        alt = self.lokal_tag("v0.1.0-rc3")
        self.git("tag", "-f", "-a", "-m", "verschoben", "v0.1.0-rc3", "HEAD")
        self.git("push", "-q", "--force", "origin", "refs/tags/v0.1.0-rc3")
        self.git("update-ref", "refs/tags/v0.1.0-rc3", alt)
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("v0.1.0-rc3 ist lokal anders als auf origin", ergebnis.ausgabe)
        self.assertEqual(self.lokal_tag("v0.1.0-rc3"), alt)
        self.kein_tag("v0.1.0-rc4")

    def test_head_baut_nicht_auf_dem_letzten_release_auf(self):
        dev = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "-b", "seite", "HEAD~1")
        self.commit("seitenweg", {"README.md": "seite\n"})
        self.git("push", "-q", "origin", "seite")
        self.git("tag", "-a", "-m", "seite", "v0.1.0-rc4")
        self.git("push", "-q", "origin", "refs/tags/v0.1.0-rc4")
        self.git("checkout", "-q", "dev")
        self.assertEqual(self.git("rev-parse", "HEAD"), dev)
        ergebnis = self.lauf("v0.1.0-rc5", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("baut nicht auf v0.1.0-rc4 auf", ergebnis.ausgabe)

    def test_gleicher_stand_wie_rc(self):
        self.signiert("v0.1.0-rc4")
        ergebnis = self.signiert("v0.1.0")
        self.assertIn("keine (gleicher Stand wie v0.1.0-rc4)", ergebnis.ausgabe)
        self.assertIn("Letztes Release: v0.1.0-rc4 (gültig signiert)", ergebnis.ausgabe)
        self.assertIn("Anker: Serie 1, wie in v0.1.0-rc4", ergebnis.ausgabe)
        self.assertEqual(self.git("rev-parse", "v0.1.0^{commit}"), self.git("rev-parse", "v0.1.0-rc4^{commit}"))

    def test_anker_ohne_neue_serie_geaendert(self):
        self.signiert("v0.1.0-rc4")
        self.commit("anker anders", anker(release=("rel2",)))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc5", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("ohne neue Serie", ergebnis.ausgabe)
        self.kein_tag("v0.1.0-rc5")

    def test_wurzel_im_release_geaendert(self):
        self.signiert("v0.1.0-rc4")
        self.commit("wurzel anders", anker(wurzel="rel2", serie=2))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc5", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("Die Wurzel hat sich seit v0.1.0-rc4 geändert", ergebnis.ausgabe)

    def test_nur_kommentare_im_anker_geaendert(self):
        self.signiert("v0.1.0-rc4")
        self.commit("anker: Kommentar", anker(kommentar="# anderer Kommentar\n# zweite Zeile"))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.signiert("v0.1.0-rc5")
        self.assertIn("Anker: Serie 1, wie in v0.1.0-rc4", ergebnis.ausgabe)
        self.assertIn("system/vertrauen/release", ergebnis.ausgabe)

    def test_sensible_liste_aus_beiden_staenden(self):
        self.signiert("v0.1.0-rc4")
        with open(os.path.join(self.mac, "scripts", "lib", "sensible-pfade"), encoding="utf-8") as f:
            liste = f.read()
        self.assertIn("anmeldung system/pam/\n", liste)
        self.commit("pam still und leise", {
            "scripts/lib/sensible-pfade": liste.replace("anmeldung system/pam/\n", ""),
            "system/pam/zenos-sperre": "auth sufficient pam_permit.so\n",
        })
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc5", eingabe="nein\n")
        teil = ergebnis.ausgabe.split("Sensible Pfade")[1]
        self.assertIn("Anmeldung und Rechte", teil)
        self.assertIn("system/pam/zenos-sperre", teil)
        self.assertIn("scripts/lib/sensible-pfade", teil)

    def test_rueckfrage_pfade(self):
        self.commit("firewall, netz, boot", {
            "scripts/module/70-sicherheit.sh": "# x\n",
            "system/modprobe/zenos-brcmfmac.conf": "# x\n",
            "system/plymouth/zenos/zenos.script": "// x\n",
        })
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="nein\n")
        teil = ergebnis.ausgabe.split("Sensible Pfade")[1]
        for text in ("Firewall · Rückfrage am Gerät", "scripts/module/70-sicherheit.sh",
                     "Netz · Rückfrage am Gerät", "system/modprobe/zenos-brcmfmac.conf",
                     "Boot · Rückfrage am Gerät", "system/plymouth/zenos/zenos.script"):
            self.assertIn(text, teil)


class Vertrauen(Basis):
    """Tags vertrauen/NNNN mit dem Wurzel-Schlüssel und Releases danach."""

    def serie_2(self, **anker_argumente):
        werte = {"release": ("rel2",), "widerrufen": ("rel",), "serie": 2}
        werte.update(anker_argumente)
        self.commit("vertrauen: Serie 2", anker(**werte))
        self.git("push", "-q", "origin", "dev")

    def test_serie_1_braucht_keinen_tag(self):
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("Serie 1 ist der erste Anker", ergebnis.ausgabe)

    def test_neue_serie_und_release_danach(self):
        self.signiert("v0.1.0-rc4")
        self.serie_2()
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.ausgabe)
        self.assertIn("Vertrauensanker Serie 2 als vertrauen/0002", ergebnis.ausgabe)
        self.assertIn("Neu widerrufen:", ergebnis.ausgabe)
        oid = self.remote_tag("vertrauen/0002")
        self.assertTrue(oid)
        self.assertEqual(self.lokal_tag("vertrauen/0002"), oid)
        roh = self.git("cat-file", "tag", oid)
        self.assertIn("tag vertrauen/0002\n", roh)
        self.assertIn("zenOS Vertrauensanker Serie 2", roh)

        rc, text = self.verify("vertrauen/0002", self.signers("wur.signers", ["wur"], "zenos-wurzel"))
        self.assertEqual(rc, 0, text)
        self.assertIn("for zenos-wurzel with", text)
        rc, _ = self.verify("vertrauen/0002", self.signers("rel.signers", ["rel", "rel2"], "zenos-release"))
        self.assertNotEqual(rc, 0)

        ergebnis = self.signiert("v0.1.0-rc5")
        self.assertIn("Anker: Serie 2, neue Serie 2 seit v0.1.0-rc4", ergebnis.ausgabe)
        rc, text = self.verify("v0.1.0-rc5", self.signers("rel2.signers", ["rel2"], "zenos-release"))
        self.assertEqual(rc, 0, text)
        # Der alte Release-Schlüssel ist widerrufen: rc4 gilt mit dem neuen Anker nicht mehr
        widerrufen = self.datei(os.path.join(self.ordner, "wid"), k("rel") + "\n")
        rc, _ = self.verify("v0.1.0-rc4", self.signers("rel.signers", ["rel"], "zenos-release"), widerrufen)
        self.assertNotEqual(rc, 0)

    def test_release_ohne_vertrauen_tag(self):
        self.serie_2()
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("den Tag vertrauen/0002 gibt es auf origin nicht", ergebnis.ausgabe)
        self.kein_tag("v0.1.0-rc4")

    def test_anker_nach_dem_vertrauen_tag_geaendert(self):
        self.serie_2()
        self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertTrue(self.remote_tag("vertrauen/0002"))
        self.commit("noch ein schlüssel", anker(release=("rel2", "fremd"), widerrufen=("rel",), serie=2))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("v0.1.0-rc4", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("passt nicht zum Tag vertrauen/0002", ergebnis.ausgabe)

    def test_wurzel_geaendert(self):
        self.serie_2(wurzel="fremd")
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("Die Wurzel ist anders als vorher", ergebnis.ausgabe)
        self.kein_tag("vertrauen/0002")

    def test_serie_springt(self):
        self.serie_2(serie=3)
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("genau um 1", ergebnis.ausgabe)
        self.kein_tag("vertrauen/0003")

    def test_ohne_aenderung(self):
        self.serie_2(release=("rel",), widerrufen=())
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("ändert nichts", ergebnis.ausgabe)

    def test_widerruf_schrumpft(self):
        self.serie_2()
        self.assertEqual(self.lauf("--vertrauen", eingabe="ja\nja\n").returncode, 0)
        self.commit("vertrauen: Serie 3", anker(release=("rel2", "fremd"), widerrufen=(), serie=3))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("Die Liste wächst nur", ergebnis.ausgabe)
        self.kein_tag("vertrauen/0003")

    def test_dritte_serie_nach_dem_tag(self):
        self.serie_2()
        self.assertEqual(self.lauf("--vertrauen", eingabe="ja\nja\n").returncode, 0)
        self.commit("vertrauen: Serie 3", anker(release=("fremd",), widerrufen=("rel", "rel2"), serie=3))
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.ausgabe)
        self.assertIn("Vorher: Serie 2 (Tag vertrauen/0002)", ergebnis.ausgabe)
        self.assertTrue(self.remote_tag("vertrauen/0003"))

    def test_nur_kommentar_nach_der_erhoehung(self):
        self.serie_2()
        self.commit("serie: Kommentar", {"system/vertrauen/serie": "# neu kommentiert\n2\n"})
        self.git("push", "-q", "origin", "dev")
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nnein\n")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.ausgabe)
        self.assertIn("Vorher: Serie 1", ergebnis.ausgabe)
        self.assertTrue(self.lokal_tag("vertrauen/0002"))

    def test_mit_dem_release_schluessel_signiert(self):
        self.serie_2()
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n", **self.falsch_programm("rel2"))
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("besteht die Prüfung nicht", ergebnis.ausgabe)
        self.kein_tag("vertrauen/0002")

    def test_vertrauen_tag_gibt_es_schon(self):
        self.serie_2()
        self.git("tag", "-a", "-m", "x", "vertrauen/0002")
        self.git("push", "-q", "origin", "refs/tags/vertrauen/0002")
        ergebnis = self.lauf("--vertrauen", eingabe="ja\nja\n")
        self.assertEqual(ergebnis.returncode, 1, ergebnis.ausgabe)
        self.assertIn("auf origin schon", ergebnis.ausgabe)


class Dateien(unittest.TestCase):
    """Der Anker und die Liste im Repo selbst."""

    def test_anker_im_repo(self):
        muster = {
            "release": rf'^zenos-release namespaces="git" {ED25519}$',
            "wurzel": rf'^zenos-wurzel namespaces="git" {ED25519}$',
            "widerrufen": rf"^{ED25519}$",
            "serie": r"^[1-9][0-9]{0,3}$",
        }
        for name, regel in muster.items():
            with self.subTest(datei=name):
                pfad = os.path.join(ANKER, name)
                self.assertTrue(os.path.isfile(pfad), f"{pfad} fehlt")
                with open(pfad, encoding="utf-8") as f:
                    inhalt = f.read()
                self.assertNotIn("PRIVATE KEY", inhalt)
                zeilen = [z for z in inhalt.splitlines() if z.strip() and not z.lstrip().startswith("#")]
                for zeile in zeilen:
                    self.assertRegex(zeile, regel)
                if name in ("wurzel", "serie"):
                    self.assertLessEqual(len(zeilen), 1)
        # Alle oder keiner: Ohne Release-Schlüssel auch keine Wurzel und keine Serie (der Anker ist dann «fehlt»)
        def zeilen_von(name):
            with open(os.path.join(ANKER, name), encoding="utf-8") as f:
                return [z for z in f.read().splitlines() if z.strip() and not z.lstrip().startswith("#")]
        befuellt = [bool(zeilen_von(n)) for n in ("release", "wurzel", "serie")]
        self.assertTrue(all(befuellt) or not any(befuellt), "Anker nur teilweise befüllt")

    def test_sensible_pfade(self):
        gruppen = {"firewall", "netz", "boot", "anmeldung", "vertrauen"}
        gesehen = set()
        with open(LISTE, encoding="utf-8") as f:
            for nummer, zeile in enumerate(f, 1):
                if not zeile.strip() or zeile.lstrip().startswith("#"):
                    continue
                teile = zeile.split()
                self.assertEqual(len(teile), 2, f"Zeile {nummer}: {zeile!r}")
                gruppe, pfad = teile
                self.assertIn(gruppe, gruppen, f"Zeile {nummer}")
                self.assertFalse(pfad.startswith("/") or ".." in pfad.split("/"), f"Zeile {nummer}: {pfad}")
                gesehen.add(gruppe)
                if "*" not in pfad and not pfad.startswith("scripts/zen.d/kanal"):
                    self.assertTrue(os.path.exists(os.path.join(WURZEL, pfad.rstrip("/"))),
                                    f"Zeile {nummer}: {pfad} gibt es nicht")
        self.assertEqual(gesehen, gruppen)

    def test_bash_32(self):
        """Das Skript läuft auf dem Mac mit bash 3.2: keine Mittel aus bash 4 oder neuer."""
        verboten = [r"\bdeclare\s+-[aA]*A", r"\blocal\s+-[a-zA-Z]*[An]", r"\bmapfile\b", r"\breadarray\b",
                    r"\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}", r"\|&", r"&>>", r";;&", r"\bcoproc\b",
                    r"\[\[\s+-v\s", r"\$\{[A-Za-z_][A-Za-z0-9_]*@[QEPAKaUuL]\}", r"\bwait\s+-n\b",
                    r"\$EPOCHSECONDS", r"\$EPOCHREALTIME", r"\bshopt\s+-s\s+(globstar|lastpipe)"]
        with open(SKRIPT, encoding="utf-8") as f:
            for nummer, zeile in enumerate(f, 1):
                code = zeile.split(" #", 1)[0] if not zeile.lstrip().startswith("#") else ""
                for regel in verboten:
                    self.assertIsNone(re.search(regel, code), f"Zeile {nummer} braucht bash 4+: {zeile.strip()}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
