#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-kanal: Holen ohne Rechte, Prüfkern (Anker, Tags, Hauptbuch, hoechste,
vertrauen/NNNN), Status und Anker von Hand.

Alles mit Wegwerf-Repos und Wegwerf-Schlüsseln im Temp-Ordner, erzeugt zur Laufzeit: ein «Server» (origin, erreichbar
über file://), ein «Gerät» als Klon davon (statt /opt/zenos) und ein Anker aus Testschlüsseln. Das Programm wird als
Modul geladen; die Tests legen nur seine Pfade in den Temp-Ordner, erlauben file:// für den Holer und nehmen die
eigene UID als Besitzer an (sonst müsste alles root gehören). Die Prüfung selbst ist dieselbe. Ohne Root, ohne Netz.
Ohne git oder ssh-keygen unter /usr/bin werden die Tests übersprungen, der OpenPGP-Fall ohne gpg und gpg-agent.

  python3 test/einheiten/kanal.test.py
"""

import contextlib
import datetime
import fcntl
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-kanal")
ANKER_REPO = os.path.join(WURZEL, "system", "vertrauen")

SYSTEM_PFAD = "/usr/bin:/bin"
HAT_WERKZEUGE = os.access("/usr/bin/git", os.X_OK) and os.access("/usr/bin/ssh-keygen", os.X_OK)
GPG = shutil.which("gpg", path=SYSTEM_PFAD) if shutil.which("gpg-agent", path=SYSTEM_PFAD) else None

_loader = importlib.machinery.SourceFileLoader("zenos_kanal", PROGRAMM)
_spec = importlib.util.spec_from_loader("zenos_kanal", _loader)
K = importlib.util.module_from_spec(_spec)
_loader.exec_module(K)

_modul = {}


def setUpModule():
    if not HAT_WERKZEUGE:
        return
    ordner = tempfile.mkdtemp(prefix="zenos-kanal-schluessel.")
    _modul["ordner"] = ordner
    _modul["schluessel"] = {}
    for name in ("rel", "rel2", "wur", "fremd"):
        pfad = os.path.join(ordner, name)
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "", "-f", pfad], check=True,
                       env={"PATH": SYSTEM_PFAD, "HOME": ordner})
        with open(pfad + ".pub", encoding="utf-8") as f:
            _modul["schluessel"][name] = " ".join(f.read().split()[:2])


def tearDownModule():
    if _modul.get("ordner"):
        shutil.rmtree(_modul["ordner"], ignore_errors=True)


def k(name):
    return _modul["schluessel"][name]


def privat(name):
    return os.path.join(_modul["ordner"], name)


def anker_texte(release=("rel",), wurzel="wur", widerrufen=(), serie=1):
    return {
        "release": "# Testanker\n" + "".join(f'zenos-release namespaces="git" {k(n)}\n' for n in release),
        "wurzel": "# Testanker\n" + (f'zenos-wurzel namespaces="git" {k(wurzel)}\n' if wurzel else ""),
        "widerrufen": "# Testanker\n" + "".join(f"{k(n)}\n" for n in widerrufen),
        "serie": "# Testanker\n" + (f"{serie}\n" if serie else ""),
    }


@unittest.skipUnless(HAT_WERKZEUGE, "git oder ssh-keygen fehlt unter /usr/bin")
class Basis(unittest.TestCase):
    """Server mit dev («eins»), Gerät als Klon auf «eins», Kanal vorschau, Anker rel/wur, Serie 1."""

    def setUp(self):
        self.ordner = os.path.realpath(tempfile.mkdtemp(prefix="zenos-kanal-test."))
        self.addCleanup(shutil.rmtree, self.ordner, True)
        self.home = self.pfad("home")
        os.makedirs(self.home)
        gitconfig = os.path.join(self.home, ".gitconfig")
        with open(gitconfig, "w", encoding="utf-8") as f:
            f.write("[user]\n\tname = Test\n\temail = test@example.invalid\n[init]\n\tdefaultBranch = dev\n"
                    "[advice]\n\tdetachedHead = false\n[tag]\n\tgpgSign = false\n")
        self.env = {"PATH": SYSTEM_PFAD, "HOME": self.home, "LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_CONFIG_GLOBAL": gitconfig}
        werte = {
            "CODE_DIR": self.pfad("opt-zenos"),
            "CHANNEL_FILE": self.pfad("etc", "xdg", "zenos", "kanal"),
            "ANCHOR_DIR": self.pfad("etc", "zenos", "vertrauen"),
            "STATE_DIR": self.pfad("var", "lib", "zenos", "kanal"),
            "FETCH_DIR": self.pfad("var", "lib", "zenos-kanal-holen"),
            "LOCK_FILE": self.pfad("run", "sperre", "kanal.lock"),
            "HAND_MARK": self.pfad("run", "sperre", "hand"),
            "TRUSTED_UIDS": (0, os.getuid()),
            "PATH_CHECK_TOP": self.ordner,
            "ALLOWED_SCHEMES": ("https", "file"),
        }
        for name, wert in werte.items():
            self.addCleanup(setattr, K, name, getattr(K, name))
            setattr(K, name, wert)
        for teil in (("etc", "xdg", "zenos"), ("var", "lib", "zenos"), ("run",)):
            os.makedirs(self.pfad(*teil), mode=0o755, exist_ok=True)

        self.server = self.pfad("server")
        self.git("init", "-q", "-b", "dev", self.server, ort=self.ordner)
        self.eins = self.commit("eins")
        self.git("clone", "-q", f"file://{self.server}", K.CODE_DIR, ort=self.ordner)
        self.kanal("vorschau")
        self.anker()

    # -- Hilfen --

    def pfad(self, *teile):
        return os.path.join(self.ordner, *teile)

    def git(self, *argumente, ort=None, pruefen=True):
        r = subprocess.run(["git", "-C", ort or self.server, *argumente], env=self.env, capture_output=True,
                           text=True, check=False)
        if pruefen and r.returncode != 0:
            self.fail(f"git {' '.join(argumente)}: {r.stderr}")
        return r.stdout.strip()

    def commit(self, nachricht, dateien=None, ort=None, signiert_mit=None):
        ort = ort or self.server
        for name, inhalt in (dateien or {"datei": nachricht + "\n"}).items():
            ziel = os.path.join(ort, name)
            os.makedirs(os.path.dirname(ziel), exist_ok=True)
            with open(ziel, "w", encoding="utf-8") as f:
                f.write(inhalt)
        self.git("add", "-A", ort=ort)
        if signiert_mit:
            self.git("-c", "gpg.format=ssh", "-c", f"user.signingkey={privat(signiert_mit)}", "commit", "-q", "-S",
                     "-m", nachricht, ort=ort)
        else:
            self.git("commit", "-q", "-m", nachricht, ort=ort)
        return self.git("rev-parse", "HEAD", ort=ort)

    def signieren(self, name, schluessel="rel", ref="HEAD", nachricht=None):
        self.git("-c", "gpg.format=ssh", "-c", f"user.signingkey={privat(schluessel)}", "tag", "-s", "-m",
                 nachricht or f"zenOS {name}", name, ref)
        return self.git("rev-parse", f"refs/tags/{name}")

    def unsigniert(self, name, ref="HEAD"):
        self.git("tag", "-a", "-m", f"zenOS {name}", name, ref)

    def geraet_auf(self, ref):
        commit = self.git("rev-parse", f"{ref}^{{commit}}")
        self.git("fetch", "-q", "origin", "+refs/heads/*:refs/remotes/origin/*", "+refs/tags/*:refs/tags/*",
                 ort=K.CODE_DIR)
        self.git("checkout", "-q", "--detach", commit, ort=K.CODE_DIR)
        return commit

    def kanal(self, name):
        with open(K.CHANNEL_FILE, "w", encoding="utf-8") as f:
            f.write(name + "\n")

    def anker(self, **art):
        self.anker_dateien(anker_texte(**art))

    def anker_dateien(self, texte):
        shutil.rmtree(K.ANCHOR_DIR, ignore_errors=True)
        os.makedirs(K.ANCHOR_DIR, mode=0o755)
        os.chmod(K.ANCHOR_DIR, 0o755)
        for name, text in texte.items():
            ziel = os.path.join(K.ANCHOR_DIR, name)
            with open(ziel, "w", encoding="utf-8") as f:
                f.write(text)
            os.chmod(ziel, 0o644)

    def anker_lesen(self, name):
        with open(os.path.join(K.ANCHOR_DIR, name), encoding="utf-8") as f:
            return f.read()

    def holen(self):
        aus, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(err):
            rc = K.cmd_fetch_internal([])
        self.holen_ausgabe = aus.getvalue() + err.getvalue()
        return rc

    def pruefen(self):
        aus, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(err):
            rc = K.cmd_check([])
        self.ausgabe = aus.getvalue() + err.getvalue()
        with open(os.path.join(K.STATE_DIR, "stand.json"), encoding="utf-8") as f:
            return rc, json.load(f)

    def lauf(self):
        self.assertEqual(self.holen(), 0, self.holen_ausgabe)
        return self.pruefen()

    def neu_verpackt(self, name, breite=64, anhang=""):
        """Angriff ohne Schlüssel: dasselbe Tag-Objekt, die Base64-Zeilen der Signatur anders umbrochen (dazu ANHANG am
        Ende), mit git mktag neu angelegt und unter NAME gesetzt. Nutzlast und Signatur bleiben gleich, git verify-tag
        nimmt es an, nur die Objekt-ID ist neu."""
        roh = self.git("cat-file", "tag", f"refs/tags/{name}") + "\n"
        anfang = roh.index(K.SIG_BEGIN) + len(K.SIG_BEGIN) + 1
        ende = roh.index(K.SIG_END)
        b64 = "".join(roh[anfang:ende].split())
        neu = roh[:anfang] + "\n".join(b64[i:i + breite] for i in range(0, len(b64), breite)) + "\n" + roh[ende:]
        oid = subprocess.run(["git", "-C", self.server, "mktag"], input=neu + anhang, text=True, env=self.env,
                             capture_output=True, check=True).stdout.strip()
        self.assertNotEqual(oid, self.git("rev-parse", f"refs/tags/{name}"))
        with open(self.pfad("erlaubt-wur"), "w", encoding="utf-8") as f:
            f.write(f'zenos-release namespaces="git" {k("rel")}\nzenos-wurzel namespaces="git" {k("wur")}\n')
        r = subprocess.run(["git", "-C", self.server, "-c", f"gpg.ssh.allowedSignersFile={self.pfad('erlaubt-wur')}",
                            "verify-tag", oid], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(r.returncode, 0, "git nimmt die neue Hülle an: " + r.stderr)
        self.git("update-ref", f"refs/tags/{name}", oid)
        return oid

    def abgelehnt(self, stand):
        return {e["tag"]: e["grund"] for e in stand["abgelehnt"]}

    def hauptbuch(self):
        with open(os.path.join(K.STATE_DIR, "gesehen.json"), encoding="utf-8") as f:
            return json.load(f)["tags"]

    def hoechste(self):
        try:
            with open(os.path.join(K.STATE_DIR, "hoechste"), encoding="utf-8") as f:
                return f.read().strip()
        except FileNotFoundError:
            return None


class Releases(Basis):
    def test_erstes_signiertes_release(self):
        self.commit("zwei")
        self.signieren("v0.1.0-rc4")
        rc, stand = self.lauf()
        self.assertEqual(rc, 0, self.ausgabe)
        self.assertEqual(stand["zustand"], "bereit")
        self.assertEqual(stand["bereit"]["version"], "v0.1.0-rc4")
        self.assertEqual(stand["bereit"]["frei_ab"], stand["bereit"]["erstmals"], "vorschau ohne Wartezeit")
        self.assertEqual(stand["gueltig"], ["v0.1.0-rc4"])
        self.assertEqual(stand["installiert"]["commit"], self.eins)
        self.assertIsNone(stand["hoechste"])
        self.assertIn("vor allen signierten Versionen", " ".join(stand["hinweise"]))
        self.assertEqual(stand["anker"]["serie"], 1)
        self.assertEqual(stand["anker"]["release"], [K.fingerprint(k("rel"))])

    def test_installiert_nichts(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        vorher = (self.git("rev-parse", "HEAD", ort=K.CODE_DIR), self.git("status", "--porcelain", ort=K.CODE_DIR),
                  sorted(os.listdir(K.CODE_DIR)))
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "bereit"))
        nachher = (self.git("rev-parse", "HEAD", ort=K.CODE_DIR),
                   self.git("status", "--porcelain", ort=K.CODE_DIR), sorted(os.listdir(K.CODE_DIR)))
        self.assertEqual(vorher, nachher)
        self.assertIn("zen update", stand["grund"])
        self.assertEqual(stand["bereit"]["rueckfrage"], [])
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "arbeit")), "Arbeitsordner bleibt nicht liegen")

    def test_unsigniert_und_leicht(self):
        self.commit("zwei")
        self.unsigniert("v0.2.0")
        self.git("tag", "v0.2.1")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "aktuell"))
        self.assertEqual(self.abgelehnt(stand), {"v0.2.0": "unsigniert", "v0.2.1": "kein annotierter Tag"})
        self.assertIsNone(stand["bereit"])

    def test_fremder_schluessel(self):
        self.commit("zwei")
        self.signieren("v0.2.0", "fremd")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "aktuell"))
        self.assertIn("fremder Schlüssel", self.abgelehnt(stand)["v0.2.0"])
        self.assertIn(K.fingerprint(k("fremd")), self.abgelehnt(stand)["v0.2.0"])

    def test_wurzel_signiert_kein_release(self):
        self.commit("zwei")
        self.signieren("v0.2.0", "wur")
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["v0.2.0"], "mit dem falschen Schlüssel signiert (zenos-wurzel)")
        self.assertEqual(stand["gueltig"], [])

    def test_tag_name_falsch(self):
        self.commit("zwei")
        objekt = self.signieren("v0.1.0")
        self.git("update-ref", "refs/tags/v0.9.0", objekt)
        rc, stand = self.lauf()
        self.assertEqual(rc, 0, self.ausgabe)
        self.assertEqual(self.abgelehnt(stand)["v0.9.0"], "Feld «tag» ist «v0.1.0», nicht «v0.9.0»")
        self.assertEqual(stand["bereit"]["version"], "v0.1.0")

    def test_tag_auf_baum(self):
        self.git("-c", "gpg.format=ssh", "-c", f"user.signingkey={privat('rel')}", "tag", "-s", "-m", "x", "v0.4.0",
                 "HEAD^{tree}")
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["v0.4.0"], "zeigt nicht auf einen Commit")

    def test_zwei_signaturen(self):
        self.commit("zwei")
        alt = self.signieren("v0.1.0")
        roh = self.git("cat-file", "tag", alt)
        signatur = roh[roh.index(K.SIG_BEGIN):]
        self.commit("drei")
        self.signieren("v0.2.0", nachricht=f"zenOS v0.2.0\n\n{signatur}")
        # git selbst nimmt diesen Tag an (es prüft nur eine der beiden Signaturen)
        with open(self.pfad("erlaubt"), "w", encoding="utf-8") as f:
            f.write(f'zenos-release namespaces="git" {k("rel")}\n')
        self.assertEqual(subprocess.run(
            ["git", "-C", self.server, "-c", f"gpg.ssh.allowedSignersFile={self.pfad('erlaubt')}", "verify-tag",
             "v0.2.0"], env=self.env, capture_output=True, check=False).returncode, 0)
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["v0.2.0"], "mehr als eine Signatur")
        self.assertEqual(stand["bereit"]["version"], "v0.1.0")

    @unittest.skipUnless(GPG, "gpg oder gpg-agent fehlt")
    def test_openpgp_mit_importiertem_schluessel(self):
        gnupg = self.pfad("gnupg")
        os.makedirs(gnupg, mode=0o700)
        env = dict(self.env, GNUPGHOME=gnupg)
        gpgconf = shutil.which("gpgconf", path=SYSTEM_PFAD)
        if gpgconf:
            self.addCleanup(subprocess.run, [gpgconf, "--kill", "gpg-agent"], env=env, capture_output=True,
                            check=False)
        subprocess.run([GPG, "--batch", "--passphrase", "", "--quick-gen-key", "Test <pgp@example.invalid>",
                        "ed25519", "sign", "never"], env=env, check=True, capture_output=True)
        self.commit("zwei")
        subprocess.run(["git", "-C", self.server, "-c", "gpg.format=openpgp", "-c", f"gpg.program={GPG}",
                        "-c", "user.signingkey=pgp@example.invalid", "tag", "-s", "-m", "zenOS v0.2.0", "v0.2.0"],
                       env=env, check=True, capture_output=True)
        # Mit dem Schlüsselbund von gpg nimmt git die Signatur an …
        self.assertEqual(subprocess.run(["git", "-C", self.server, "-c", f"gpg.program={GPG}", "verify-tag",
                                         "v0.2.0"], env=env, capture_output=True, check=False).returncode, 0)
        # … der Kanal nie
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["v0.2.0"], "OpenPGP-Signatur (nicht erlaubt)")
        self.assertEqual(stand["gueltig"], [])

    def test_widerrufen(self):
        self.commit("zwei")
        self.signieren("v0.2.0", "rel")
        self.anker(release=("rel2",), widerrufen=("rel",))
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["v0.2.0"], f"Schlüssel widerrufen ({K.fingerprint(k('rel'))})")
        self.assertEqual(stand["zustand"], "aktuell")

    def test_rc_auf_stabil(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0-rc1")
        self.kanal("stabil")
        rc, stand = self.lauf()
        self.assertEqual(rc, 0)
        self.assertEqual(stand["bereit"]["version"], "v0.1.0")
        self.assertEqual(stand["gueltig"], ["v0.1.0"])
        self.assertNotIn("v0.2.0-rc1", self.abgelehnt(stand))
        self.kanal("vorschau")
        _, stand = self.pruefen()
        self.assertEqual(stand["bereit"]["version"], "v0.2.0-rc1")

    def test_versionen_vergleichen(self):
        namen = ["v0.1.0", "v0.1.0-rc10", "v0.1.0-rc3", "v0.10.0", "v0.9.9", "v1.0.0-rc1"]
        self.assertEqual(sorted(namen, key=K.version_key),
                         ["v0.1.0-rc3", "v0.1.0-rc10", "v0.1.0", "v0.9.9", "v0.10.0", "v1.0.0-rc1"])
        for falsch in ("v01.0.0", "v0.1", "0.1.0", "v0.1.0-rc0", "v0.1.0-beta", "v٣.0.0", "v0.1.0\n"):
            self.assertIsNone(K.version_key(falsch), falsch)

    def test_wartezeit_stabil(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.kanal("stabil")
        _, stand = self.lauf()
        erstmals = K.parse_iso(stand["bereit"]["erstmals"])
        self.assertEqual(K.parse_iso(stand["bereit"]["frei_ab"]) - erstmals, datetime.timedelta(hours=24))
        self.assertIn("24 h Wartezeit", stand["grund"])
        # Später: «erstmals» bleibt, die Wartezeit ist um
        spaeter = erstmals + datetime.timedelta(hours=30)
        self.addCleanup(setattr, K, "now", K.now)
        K.now = lambda: spaeter
        _, stand = self.pruefen()
        self.assertEqual(stand["bereit"]["erstmals"], K.iso(erstmals))
        self.assertNotIn("Wartezeit", stand["grund"])

    def test_gesperrte_version(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0")
        os.makedirs(os.path.join(K.STATE_DIR, "gesperrt"))
        open(os.path.join(K.STATE_DIR, "gesperrt", "v0.2.0"), "w", encoding="utf-8").close()
        _, stand = self.lauf()
        self.assertEqual(stand["bereit"]["version"], "v0.1.0")

    def test_viele_tags_blockieren_nicht(self):
        """Angriff (Prüfung, Probe F): 1001 leichte Tags per Push, ohne Schlüssel. Früher «blockiert» auf jedem Gerät,
        auch für ein neues, gültig signiertes Release. Jetzt kosten sie kaum etwas und blockieren nichts."""
        self.commit("zwei")
        self.signieren("v1.0.0")
        befehle = "".join(f"create refs/tags/v0.0.{n} HEAD\n" for n in range(1001))
        subprocess.run(["git", "-C", self.server, "update-ref", "--stdin"], input=befehle, text=True, env=self.env,
                       check=True)
        for n in range(50):
            self.unsigniert(f"v0.1.{n}")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"], stand["bereit"]["version"]), (0, "bereit", "v1.0.0"), stand["grund"])
        self.assertEqual(len(stand["abgelehnt"]), K.MAX_REJECTED_SHOWN, "die Liste bleibt kurz")
        self.assertIn(f"{1051 - K.MAX_REJECTED_SHOWN} weitere Tags abgelehnt (nicht einzeln aufgeführt)",
                      stand["hinweise"])
        # Ein neues, gültig signiertes Release kommt trotzdem an
        self.commit("drei")
        self.signieren("v1.1.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["bereit"]["version"]), (0, "v1.1.0"))

    def test_signaturpruefungen_begrenzt(self):
        """Kopien einer echten Signatur unter anderen Namen kosten je ein git verify-tag. Höchstens MAX_VERIFY je Lauf;
        die übrigen bleiben ungeprüft (Hinweis), nichts ist «blockiert», bekannte gültige Namen zählen nicht mit."""
        self.commit("zwei")
        echt = self.signieren("v0.1.0")
        self.lauf()
        roh = self.git("cat-file", "tag", echt)
        for name in ("v9.0.0", "v9.0.1", "v9.0.2"):
            kopie = roh.replace("tag v0.1.0\n", f"tag {name}\n", 1) + "\n"
            oid = subprocess.run(["git", "-C", self.server, "mktag"], input=kopie, text=True, env=self.env,
                                 capture_output=True, check=True).stdout.strip()
            self.git("update-ref", f"refs/tags/{name}", oid)
        self.commit("drei")
        self.signieren("v0.2.0")
        self.addCleanup(setattr, K, "MAX_VERIFY", K.MAX_VERIFY)
        K.MAX_VERIFY = 2
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "bereit"))
        self.assertEqual(stand["bereit"]["version"], "v0.1.0", "v0.2.0 blieb ungeprüft, v0.1.0 ist bekannt")
        self.assertIn("2 Tags blieben ungeprüft", " ".join(stand["hinweise"]))
        self.assertEqual(self.abgelehnt(stand).get("v9.0.2"), "Signatur ungültig")
        K.MAX_VERIFY = 4
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["bereit"]["version"]), (0, "v0.2.0"))
        self.assertNotIn("ungeprüft", " ".join(stand["hinweise"]))


class Hauptbuch(Basis):
    def test_verschoben_gueltig_ist_alarm(self):
        self.commit("zwei")
        vorher = self.signieren("v0.1.0")
        self.lauf()
        self.assertEqual(self.hauptbuch()["v0.1.0"]["objekt"], vorher)
        self.commit("drei")
        self.git("tag", "-d", "v0.1.0")
        self.signieren("v0.1.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (3, "blockiert"))
        self.assertIn("ALARM: v0.1.0", stand["grund"])
        self.assertIsNone(stand["bereit"])
        self.assertEqual(self.hauptbuch()["v0.1.0"]["objekt"], vorher, "das Hauptbuch behält das alte Objekt")
        # Zurück auf das alte Objekt: wieder in Ordnung
        self.git("update-ref", "refs/tags/v0.1.0", vorher)
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "bereit"))

    def test_neu_umbrochen_ist_kein_alarm(self):
        """Angriff (Prüfung, Befund 1, Probe A): Wer auf GitHub schreiben darf, bricht die Signatur von v0.1.0 neu um
        oder hängt eine Leerzeile an. Früher: ALARM und «blockiert» auf jedem Gerät, auch für das nächste echte
        Release. Jetzt zählt der Commit: dasselbe Commit in anderer Hülle gilt weiter."""
        commit = self.commit("zwei")
        vorher = self.signieren("v0.1.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["bereit"]["version"]), (0, "v0.1.0"))
        self.assertEqual(self.hauptbuch()["v0.1.0"]["commit"], commit)
        for breite, anhang in ((64, ""), (70, "\n")):
            neu = self.neu_verpackt("v0.1.0", breite, anhang)
            rc, stand = self.lauf()
            self.assertEqual((rc, stand["zustand"]), (0, "bereit"), stand["grund"])
            self.assertNotIn("ALARM", stand["grund"])
            self.assertTrue(any("derselbe Commit" in h for h in stand["hinweise"]), stand["hinweise"])
            self.assertEqual(self.hauptbuch()["v0.1.0"]["objekt"], neu)
            self.assertNotEqual(neu, vorher)
        # Das nächste echte Release kommt an
        self.commit("drei")
        self.signieren("v0.2.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["bereit"]["version"]), (0, "v0.2.0"))

    def test_altes_hauptbuch_ohne_commit(self):
        """Ein Hauptbuch der vorigen Fassung (ohne Commit, mit ungültigen Namen) wird gelesen und ergänzt."""
        commit = self.commit("zwei")
        objekt = self.signieren("v0.1.0")
        self.unsigniert("v0.0.9")
        os.makedirs(K.STATE_DIR, exist_ok=True)
        K.write_json(os.path.join(K.STATE_DIR, "gesehen.json"), {"version": 1, "tags": {
            "v0.1.0": {"objekt": objekt, "gueltig": True, "erstmals": "2026-10-01T00:00:00Z"},
            "v0.0.9": {"objekt": self.git("rev-parse", "refs/tags/v0.0.9"), "gueltig": False, "erstmals": None}}})
        rc, stand = self.lauf()
        self.assertEqual(rc, 0, stand["grund"])
        self.assertEqual(self.hauptbuch(), {"v0.1.0": {"objekt": objekt, "gueltig": True, "commit": commit,
                                                       "erstmals": "2026-10-01T00:00:00Z"}})

    def test_verschoben_ungueltig(self):
        self.commit("zwei")
        vorher = self.signieren("v0.1.0")
        self.lauf()
        self.git("tag", "-d", "v0.1.0")
        self.unsigniert("v0.1.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "aktuell"))
        self.assertIn("auf origin verschoben", self.abgelehnt(stand)["v0.1.0"])
        self.assertEqual(self.hauptbuch()["v0.1.0"], {"objekt": vorher, "gueltig": True, "commit": self.git(
            "rev-parse", "HEAD"), "erstmals": self.hauptbuch()["v0.1.0"]["erstmals"]})

    def test_geloescht(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.lauf()
        self.git("tag", "-d", "v0.1.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "aktuell"))
        self.assertIn("v0.1.0 gibt es auf origin nicht mehr", stand["hinweise"])

    def test_vorher_ungueltig_jetzt_gueltig(self):
        self.commit("zwei")
        self.unsigniert("v0.1.0")
        self.lauf()
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "gesehen.json")),
                         "ungültige Namen kommen nicht ins Hauptbuch (sonst wüchse es mit jedem fremden Tag)")
        self.git("tag", "-d", "v0.1.0")
        neu = self.signieren("v0.1.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["bereit"]["version"]), (0, "v0.1.0"))
        self.assertEqual(self.hauptbuch()["v0.1.0"]["objekt"], neu)

    def test_erstmals_bleibt(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.lauf()
        erstmals = self.hauptbuch()["v0.1.0"]["erstmals"]
        self.addCleanup(setattr, K, "now", K.now)
        K.now = lambda: K.parse_iso(erstmals) + datetime.timedelta(days=2)
        self.lauf()
        self.assertEqual(self.hauptbuch()["v0.1.0"]["erstmals"], erstmals)


class Hoechste(Basis):
    def test_kein_downgrade(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0")
        self.geraet_auf("v0.2.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"], stand["hoechste"]), (0, "aktuell", "v0.2.0"))
        self.assertEqual(stand["installiert"]["version"], "v0.2.0")
        self.assertEqual(self.hoechste(), "v0.2.0")
        # Ein Angreifer hält v0.2.0 zurück: v0.1.0 ist kein Ziel
        self.git("tag", "-d", "v0.2.0")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"], stand["hoechste"]), (0, "aktuell", "v0.2.0"))
        self.assertIsNone(stand["bereit"])

    def test_hoechste_sinkt_nie(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0")
        os.makedirs(K.STATE_DIR, exist_ok=True)
        with open(os.path.join(K.STATE_DIR, "hoechste"), "w", encoding="utf-8") as f:
            f.write("v0.3.0\n")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"], stand["hoechste"]), (0, "aktuell", "v0.3.0"))

    def test_hoechste_steigt_mit_dem_installierten_stand(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0")
        self.geraet_auf("v0.1.0")
        _, stand = self.lauf()
        self.assertEqual((stand["hoechste"], stand["bereit"]["version"]), ("v0.1.0", "v0.2.0"))
        self.geraet_auf("v0.2.0")  # etwa über zen update auf dev
        _, stand = self.pruefen()
        self.assertEqual((stand["hoechste"], stand["zustand"]), ("v0.2.0", "aktuell"))

    def test_nicht_aus_einer_unterbrochenen_installation(self):
        """Ein Abbruch liess /opt/zenos auf einem Ziel stehen, das nie gesund wurde; die Prüfung danach hob hoechste
        darauf, obwohl die Version gleich gesperrt wurde (Ende-zu-Ende-Test). Solange laeuft.json da ist, nicht."""
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0")
        self.geraet_auf("v0.1.0")
        _, stand = self.lauf()
        self.assertEqual(self.hoechste(), "v0.1.0")
        self.geraet_auf("v0.2.0")
        K.write_json(os.path.join(K.STATE_DIR, "laeuft.json"), {"version": 1, "phase": "ziel"})
        _, stand = self.pruefen()
        self.assertEqual((self.hoechste(), stand["hoechste"]), ("v0.1.0", "v0.1.0"))
        self.assertIn("hoechste bleibt", " ".join(stand["hinweise"]))
        os.unlink(os.path.join(K.STATE_DIR, "laeuft.json"))
        _, stand = self.pruefen()
        self.assertEqual(self.hoechste(), "v0.2.0")

    def test_ableitung_aus_lokalem_stand(self):
        """Fehlt hoechste und liegt der installierte Stand nur auf dem Gerät (nicht gepusht), zählt der Verlauf in
        /opt/zenos."""
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.commit("drei")
        self.signieren("v0.2.0")
        self.geraet_auf("v0.1.0")
        self.commit("lokal", ort=K.CODE_DIR)
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["hoechste"], stand["bereit"]["version"]), (0, "v0.1.0", "v0.2.0"))
        self.assertIn("hoechste aus dem installierten Stand abgeleitet: v0.1.0", stand["hinweise"])

    def test_ableitung_unmoeglich(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.git("checkout", "-q", "--orphan", "fremd", ort=K.CODE_DIR)
        self.commit("anderer Verlauf", ort=K.CODE_DIR)
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (3, "blockiert"))
        self.assertIn("hoechste fehlt", stand["grund"])
        self.assertIsNone(self.hoechste())

    def test_ohne_installierten_stand(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        rc = self.holen()
        self.assertEqual(rc, 0)
        shutil.rmtree(K.CODE_DIR)
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["zustand"]), (3, "blockiert"))
        self.assertIn("unbekannt", stand["grund"])
        # Mit gespeichertem hoechste reicht das
        with open(os.path.join(K.STATE_DIR, "hoechste"), "w", encoding="utf-8") as f:
            f.write("v0.0.1\n")
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["bereit"]["version"]), (10, "v0.1.0"))
        # Ohne installierten Stand lässt sich der Weg nicht mit den Rückfrage-Pfaden vergleichen: nur mit Zustimmung
        self.assertEqual((stand["zustand"], stand["bereit"]["rueckfrage"]), ("zustimmung", None))


class Vertrauen(Basis):
    def neuer_anker(self, nummer, schluessel="wur", **art):
        texte = anker_texte(**art)
        self.commit(f"vertrauen {nummer}", {f"system/vertrauen/{n}": t for n, t in texte.items()})
        self.signieren(f"vertrauen/{nummer:04d}", schluessel)

    def test_schluesselwechsel(self):
        self.neuer_anker(2, release=("rel2",), widerrufen=("rel",), serie=2)
        self.commit("neu")
        self.signieren("v0.2.0", "rel2")
        self.commit("alt")
        self.signieren("v0.3.0", "rel")
        rc, stand = self.lauf()
        self.assertEqual(rc, 0, self.ausgabe)
        self.assertEqual(stand["anker"]["serie"], 2)
        self.assertIn("Vertrauensanker Serie 2 aus vertrauen/0002 übernommen", stand["hinweise"])
        self.assertEqual(self.abgelehnt(stand)["v0.3.0"], f"Schlüssel widerrufen ({K.fingerprint(k('rel'))})")
        self.assertEqual(stand["bereit"]["version"], "v0.2.0")
        anker = K.load_device_anchor()
        self.assertEqual((anker.release, anker.revoked, anker.root, anker.series), ([k("rel2")], [k("rel")], k("wur"), 2))
        self.assertIn(f'zenos-wurzel namespaces="git" {k("wur")}', self.anker_lesen("wurzel"))
        # Zweiter Lauf: nichts mehr zu übernehmen
        _, stand = self.pruefen()
        self.assertNotIn("Vertrauensanker Serie 2 aus vertrauen/0002 übernommen", stand["hinweise"])

    def test_mit_release_schluessel_signiert(self):
        self.neuer_anker(2, schluessel="rel", release=("fremd",), serie=2)
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["vertrauen/0002"], "mit dem falschen Schlüssel signiert (zenos-release)")
        self.assertEqual(K.load_device_anchor().series, 1)
        self.assertEqual(K.load_device_anchor().release, [k("rel")])

    def test_serie_passt_nicht(self):
        self.neuer_anker(2, release=("rel2",), serie=3)
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["vertrauen/0002"], "Serie im Commit ist 3, nicht 2")
        self.assertEqual(K.load_device_anchor().series, 1)

    def test_serie_zurueck(self):
        self.anker(serie=3)
        self.neuer_anker(2, release=("fremd",), serie=2)
        rc, stand = self.lauf()
        self.assertEqual(rc, 0, self.ausgabe)
        self.assertEqual(K.load_device_anchor().series, 3)
        self.assertEqual(K.load_device_anchor().release, [k("rel")])
        self.assertNotIn("vertrauen/0002", self.abgelehnt(stand))

    def test_andere_wurzel(self):
        self.neuer_anker(2, wurzel="fremd", serie=2)
        _, stand = self.lauf()
        self.assertIn("andere Wurzel", self.abgelehnt(stand)["vertrauen/0002"])
        self.assertEqual(K.load_device_anchor().root, k("wur"))

    def test_vertrauens_tag_neu_umbrochen(self):
        """Wie Befund 1, für vertrauen/NNNN: neu umbrochen ist kein Alarm, der Anker bleibt."""
        self.neuer_anker(2, release=("rel2",), widerrufen=("rel",), serie=2)
        self.lauf()
        self.assertEqual(K.load_device_anchor().series, 2)
        self.neu_verpackt("vertrauen/0002")
        rc, stand = self.lauf()
        self.assertNotEqual(stand["zustand"], "blockiert", stand["grund"])
        self.assertEqual(K.load_device_anchor().series, 2)

    def test_abbruch_beim_ankerwechsel(self):
        """Ausfall (Prüfung, Befund 11): Strom weg zwischen den Dateien des Ankers. Früher stand nach «widerrufen» der
        alte Release-Schlüssel in release und in widerrufen: Anker ungültig, für immer «Anker fehlt». Jetzt ist jeder
        Zwischenstand gültig, und der nächste Lauf vollendet den Wechsel."""
        self.neuer_anker(2, release=("rel2",), widerrufen=("rel",), serie=2)
        self.holen()
        echt = K.write_atomic
        self.addCleanup(setattr, K, "write_atomic", echt)
        for abbruch_bei in (1, 2, 3):
            self.anker()
            gezaehlt = []

            def schreiben(pfad, text, mode=0o644, grenze=abbruch_bei, liste=gezaehlt):
                if pfad.startswith(K.ANCHOR_DIR + os.sep):
                    liste.append(pfad)
                    if len(liste) == grenze:
                        raise OSError(5, "Strom weg")
                return echt(pfad, text, mode)

            K.write_atomic = schreiben
            self.pruefen()
            K.write_atomic = echt
            zwischen = K.load_device_anchor()  # wirft, wenn der Zwischenstand ungültig ist
            self.assertIn(zwischen.series, (1, 2), abbruch_bei)
            rc, stand = self.pruefen()
            anker = K.load_device_anchor()
            self.assertEqual((anker.series, anker.release, anker.revoked), (2, [k("rel2")], [k("rel")]), abbruch_bei)
            self.assertNotEqual(stand["zustand"], "anker_fehlt", abbruch_bei)

    def test_widerruf_bleibt(self):
        self.anker(widerrufen=("fremd",))
        self.neuer_anker(2, release=("rel2",), serie=2)
        self.lauf()
        anker = K.load_device_anchor()
        self.assertEqual((anker.series, anker.release, anker.revoked), (2, [k("rel2")], [k("fremd")]))

    def test_ueberspringt_nichts_rueckwaerts(self):
        """vertrauen/0002 und 0003 in einem Lauf, aufsteigend; 0003 prüft gegen den Anker nach 0002."""
        self.neuer_anker(2, release=("rel2",), widerrufen=("rel",), serie=2)
        self.neuer_anker(3, release=("rel",), widerrufen=("rel",), serie=3)  # will rel zurück: widerrufen
        _, stand = self.lauf()
        self.assertEqual(self.abgelehnt(stand)["vertrauen/0003"], "Anker im Commit unbrauchbar: ein Release-Schlüssel "
                                                                  "steht auch in widerrufen")
        self.assertEqual(K.load_device_anchor().series, 2)


class Anker(Basis):
    def test_leerer_anker_wie_im_repo(self):
        texte = {}
        for name in K.ANCHOR_FILES:
            with open(os.path.join(ANKER_REPO, name), encoding="utf-8") as f:
                texte[name] = f.read()
        self.anker_dateien(texte)
        self.commit("rc3")
        self.unsigniert("v0.1.0-rc3")
        self.commit("rc4")
        self.signieren("v0.1.0-rc4")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (3, "anker_fehlt"))
        self.assertEqual(self.abgelehnt(stand), {"v0.1.0-rc3": "unsigniert",
                                                 "v0.1.0-rc4": "signiert, aber nicht prüfbar (Anker fehlt)"})
        self.assertIsNone(stand["bereit"])
        self.assertEqual(stand["gueltig"], [])
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "gesehen.json")))
        self.assertIn("zen update", stand["grund"])

    def test_ordner_fehlt(self):
        shutil.rmtree(K.ANCHOR_DIR)
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (3, "anker_fehlt"))
        self.assertIn("fehlt", stand["anker_problem"])

    def test_widerrufsdatei_fehlt(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        os.unlink(os.path.join(K.ANCHOR_DIR, "widerrufen"))
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"], stand["anker_problem"]), (3, "anker_fehlt", "widerrufen fehlt"))
        self.assertIsNone(stand["bereit"])

    def test_rechte(self):
        os.chmod(os.path.join(K.ANCHOR_DIR, "release"), 0o666)
        _, stand = self.lauf()
        self.assertEqual(stand["zustand"], "anker_fehlt")
        self.assertIn("für andere schreibbar", stand["anker_problem"])
        os.chmod(os.path.join(K.ANCHOR_DIR, "release"), 0o644)
        os.chmod(K.ANCHOR_DIR, 0o775)
        _, stand = self.pruefen()
        self.assertIn("für andere schreibbar", stand["anker_problem"])

    def test_verweis(self):
        ziel = os.path.join(K.ANCHOR_DIR, "release")
        os.rename(ziel, self.pfad("release-woanders"))
        os.symlink(self.pfad("release-woanders"), ziel)
        _, stand = self.lauf()
        self.assertEqual(stand["zustand"], "anker_fehlt")

    def test_strenges_format(self):
        falsch = [
            {"release": f'zenos-release namespaces="git",cert-authority {k("rel")}\n'},
            {"release": f'zenos-release namespaces="git" {k("rel")} kommentar\n'},
            {"release": f'zenos-wurzel namespaces="git" {k("rel")}\n'},
            {"wurzel": f'zenos-wurzel namespaces="git" {k("rel")}\n'},
            {"wurzel": f'zenos-wurzel namespaces="git" {k("wur")}\nzenos-wurzel namespaces="git" {k("fremd")}\n'},
            {"widerrufen": f"{k('rel')}\n"},
            {"serie": "0\n"},
            {"serie": "1\n2\n"},
            {"release": "zenos-release namespaces=\"git\" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ\n"},
        ]
        for aenderung in falsch:
            texte = anker_texte()
            texte.update(aenderung)
            with self.assertRaises(K.AnchorError, msg=str(aenderung)):
                K.parse_anchor(texte)
        self.assertEqual(K.parse_anchor(anker_texte()).series, 1)

    def test_fingerabdruck_wie_ssh_keygen(self):
        for name in ("rel", "wur"):
            r = subprocess.run(["ssh-keygen", "-l", "-f", privat(name) + ".pub"], capture_output=True, text=True,
                               check=True, env={"PATH": SYSTEM_PFAD})
            self.assertEqual(K.fingerprint(k(name)), r.stdout.split()[1])

    def test_anker_pruefen_repo(self):
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_anchor(["--pruefen", ANKER_REPO]), 1)
        self.assertTrue(aus.getvalue().startswith("leer:"))
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_anchor(["--pruefen", K.ANCHOR_DIR]), 0)
        os.unlink(os.path.join(K.ANCHOR_DIR, "serie"))
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_anchor(["--pruefen", K.ANCHOR_DIR]), 3)

    def anker_von_hand(self, ordner, antworten):
        self.addCleanup(setattr, K, "interactive", K.interactive)
        self.addCleanup(setattr, K, "ask", K.ask)
        K.interactive = lambda: True
        rest = list(antworten)
        K.ask = lambda prompt: rest.pop(0)
        aus, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(aus), contextlib.redirect_stderr(err):
            rc = K.cmd_anchor([ordner])
        return rc, aus.getvalue() + err.getvalue()

    def quelle(self, **art):
        ordner = self.pfad("quelle")
        shutil.rmtree(ordner, ignore_errors=True)
        os.makedirs(ordner)
        for name, text in anker_texte(**art).items():
            with open(os.path.join(ordner, name), "w", encoding="utf-8") as f:
                f.write(text)
        return ordner

    def test_anker_von_hand(self):
        shutil.rmtree(K.ANCHOR_DIR)
        ordner = self.quelle(release=("rel2",))
        rc, text = self.anker_von_hand(ordner, ["SHA256:falsch"])
        self.assertEqual(rc, 3, text)
        self.assertFalse(os.path.exists(K.ANCHOR_DIR))
        # Angriff (Prüfung, Befund 7): Die Fingerabdrücke aus dem Ordner stehen vor der Eingabe nicht auf dem
        # Bildschirm, auch nicht nach einer falschen; abtippen geht nicht
        self.assertNotIn(K.fingerprint(k("wur")), text)
        self.assertNotIn(K.fingerprint(k("rel2"))[7:15], text)
        rc, text = self.anker_von_hand(ordner, [K.fingerprint(k("wur")), "ja"])
        self.assertEqual(rc, 3, text)
        self.assertNotIn(K.fingerprint(k("rel2"))[7:15], text)
        rc, text = self.anker_von_hand(ordner, [K.fingerprint(k("wur")), K.fingerprint(k("rel"))[7:15]])
        self.assertEqual(rc, 3, text)
        self.assertFalse(os.path.exists(K.ANCHOR_DIR))
        rc, text = self.anker_von_hand(ordner, [K.fingerprint(k("wur")), K.fingerprint(k("rel2"))[7:15]])
        self.assertEqual(rc, 0, text)
        self.assertIn(K.fingerprint(k("rel2")), text, "danach zeigt es die übernommenen Fingerabdrücke")
        anker = K.load_device_anchor()
        self.assertEqual((anker.release, anker.root, anker.series), ([k("rel2")], k("wur"), 1))

    def test_anker_von_hand_nicht_zurueck(self):
        self.anker(serie=3, widerrufen=("fremd",))
        rc, text = self.anker_von_hand(self.quelle(serie=2), [])
        self.assertEqual(rc, 3, text)
        self.assertIn("kleiner", text)
        rc, text = self.anker_von_hand(self.quelle(serie=4, release=("rel2", "rel")),
                                       [K.fingerprint(k("wur")), K.fingerprint(k("rel"))[7:15],
                                        K.fingerprint(k("rel2"))[7:15]])
        self.assertEqual(rc, 0, text)
        anker = K.load_device_anchor()
        self.assertEqual((anker.series, anker.revoked), (4, [k("fremd")]), "Widerrufe des Geräts bleiben")

    def test_anker_von_hand_nur_im_terminal(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(K.cmd_anchor([self.quelle()]), 2)
        self.assertIn("nur im Terminal", err.getvalue())


class Ablauf(Basis):
    def test_kein_kontakt(self):
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["zustand"]), (10, "kein_kontakt"))
        self.assertIsNone(stand["letzter_kontakt"])

    def test_holen_mit_verbotener_adresse(self):
        for url in ("http://example.invalid/zenOS.git", "ssh://git@example.invalid/zenOS.git",
                    "https://name:geheim@example.invalid/zenOS.git", "ext::sh -c touch% /tmp/x",
                    "https://example.invalid/../x"):
            self.git("remote", "set-url", "origin", url, ort=K.CODE_DIR)
            self.assertEqual(self.holen(), 1, url)
            self.assertIn("nicht erlaubt", self.holen_ausgabe)
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["zustand"]), (10, "kein_kontakt"))
        self.assertIn("nicht erlaubt", stand["holen_fehler"])

    def test_holen_scheitert_alter_stand_bleibt(self):
        self.commit("zwei")
        self.signieren("v0.1.0")
        self.lauf()
        self.git("remote", "set-url", "origin", f"file://{self.pfad('gibtsnicht')}", ort=K.CODE_DIR)
        self.assertEqual(self.holen(), 10)
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["zustand"]), (0, "bereit"), "das letzte Bundle gilt weiter")
        self.assertIsNotNone(stand["letzter_kontakt"])
        self.assertTrue(stand["holen_fehler"])

    def test_holen_verschobener_und_geloeschter_tag(self):
        self.signieren("v0.1.0")
        self.assertEqual(self.holen(), 0)
        self.commit("zwei")
        self.git("tag", "-d", "v0.1.0")
        self.signieren("v0.1.0")
        self.unsigniert("v0.2.0")
        self.assertEqual(self.holen(), 0, self.holen_ausgabe)
        self.git("tag", "-d", "v0.2.0")
        self.assertEqual(self.holen(), 0, self.holen_ausgabe)
        refs = self.git("for-each-ref", "--format=%(refname)",
                        ort=os.path.join(K.FETCH_DIR, "spiegel.git"))
        self.assertNotIn("refs/kanal/tags/v0.2.0", refs)

    def test_holen_nur_was_der_kanal_braucht(self):
        """Angriff (Prüfung, Befund 4, Probe C): Ein fremder Branch voller Daten, je Runde neu, und der Spiegel des
        Holers wuchs ohne Grenze (gc.auto=0, alle Branches). Jetzt holt er nur dev und v*, und was nicht mehr erreichbar
        ist, fliegt nach dem Holen raus."""
        spiegel = os.path.join(K.FETCH_DIR, "spiegel.git")

        def groesse():
            return K.tree_size(spiegel)

        self.signieren("v0.1.0")
        self.unsigniert("anderer-tag")
        self.git("checkout", "-q", "-b", "gross")
        self.commit("gross", {"daten": os.urandom(3 << 20).hex()})
        self.git("checkout", "-q", "dev")
        self.assertEqual(self.holen(), 0, self.holen_ausgabe)
        refs = self.git("for-each-ref", "--format=%(refname)", ort=spiegel).split("\n")
        self.assertEqual(sorted(refs), ["refs/kanal/heads/dev", "refs/kanal/tags/v0.1.0"])
        klein = groesse()
        self.assertLess(klein, 1 << 20)
        # Daten auf dev selbst, danach dev zurückgesetzt: Sie bleiben nicht im Spiegel
        for runde in range(3):
            self.commit(f"daten {runde}", {"daten": os.urandom(2 << 20).hex()})
            self.assertEqual(self.holen(), 0, self.holen_ausgabe)
            self.assertGreater(groesse(), 2 << 20)
            self.git("reset", "-q", "--hard", "HEAD~1")
            self.assertEqual(self.holen(), 0, self.holen_ausgabe)
            self.assertLess(groesse(), klein + (256 << 10), f"Runde {runde}")
        # Zu gross: weg damit, Meldung statt voller Platte
        self.addCleanup(setattr, K, "MAX_MIRROR", K.MAX_MIRROR)
        K.MAX_MIRROR = 1024
        self.assertEqual(self.holen(), 1)
        self.assertFalse(os.path.exists(spiegel))
        self.assertIn("grösser als", self.holen_ausgabe)

    def test_holen_ohne_dev_und_ohne_tags(self):
        self.git("branch", "-m", "dev", "main")
        self.assertEqual(self.holen(), 0, self.holen_ausgabe)
        self.git("checkout", "-q", "--detach", "HEAD")
        self.git("branch", "-D", "main")
        self.assertEqual(self.holen(), 0, self.holen_ausgabe)
        self.assertFalse(os.path.exists(os.path.join(K.FETCH_DIR, "uebergabe.bundle")))
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["zustand"]), (0, "aktuell"))

    def test_bundle_als_verweis(self):
        self.signieren("v0.1.0")
        self.holen()
        bundle = os.path.join(K.FETCH_DIR, "uebergabe.bundle")
        os.rename(bundle, self.pfad("b"))
        os.symlink(self.pfad("b"), bundle)
        rc, stand = self.pruefen()
        self.assertEqual((rc, stand["zustand"]), (1, "fehler"))
        self.assertIn("Bundle", stand["grund"])

    def test_wunsch_bei_uhrsprung(self):
        """Ausfall (Prüfung, Befund 15c): Stellt NTP die Uhr nach dem Start um mehr als eine Stunde, galt der Wunsch von
        zen update als zu alt. Jetzt zählt die Zeit seit dem Start."""
        if K.boot_clock()[0] is None:
            self.skipTest("ohne /proc/sys/kernel/random/boot_id")
        self.commit("zwei")
        self.signieren("v0.1.0")
        K.write_wish("update")
        spaeter = K.now() + datetime.timedelta(hours=3)
        self.addCleanup(setattr, K, "now", K.now)
        K.now = lambda: spaeter
        _, stand = self.lauf()
        self.assertIsNotNone(stand["wunsch"], "der Wunsch gilt trotz Uhrsprung")
        # Ein Wunsch aus einem anderen Start zählt nach der Uhrzeit
        pfad = os.path.join(K.STATE_DIR, "wunsch.json")
        K.write_wish("update")
        alt = K.load_json(pfad)
        alt.update(start="00000000-0000-0000-0000-000000000000", zeit=K.iso(spaeter - datetime.timedelta(hours=2)))
        K.write_json(pfad, alt, 0o600)
        _, stand = self.pruefen()
        self.assertIsNone(stand["wunsch"])

    def test_kanal(self):
        self.kanal("nightly")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (3, "blockiert"))
        self.kanal("main")
        _, stand = self.pruefen()
        self.assertEqual(stand["kanal"], "stabil")
        self.assertIn("Kanal main gilt als stabil", stand["hinweise"])
        os.unlink(K.CHANNEL_FILE)
        _, stand = self.pruefen()
        self.assertEqual(stand["kanal"], "dev")

    def test_sperre_belegt(self):
        os.makedirs(os.path.dirname(K.LOCK_FILE), mode=0o755)
        fd = os.open(K.LOCK_FILE, os.O_WRONLY | os.O_CREAT, 0o644)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(K.cmd_check([]), 75)
        self.assertIn("läuft gerade", err.getvalue())
        self.assertIn(f"PID {os.getpid()}", err.getvalue(), "wer die Sperre hält, steht dabei")
        self.assertFalse(os.path.exists(os.path.join(K.STATE_DIR, "stand.json")))

    def test_sperre_nur_fuer_root(self):
        """Angriff (Prüfung, Befund 2): In /run/lock (für alle beschreibbar) konnte jeder Benutzer die Sperre anlegen
        oder lesend öffnen und halten. Jetzt liegt sie in einem Ordner nur für root (0700), die Datei muss root gehören,
        ein Verweis führt zu einer Meldung statt zu einem Abbruch mit Traceback."""
        ordner = os.path.dirname(K.LOCK_FILE)
        self.assertEqual(K.lock_or_exit().release(), None)
        self.assertEqual(os.stat(ordner).st_mode & 0o777, 0o700, "nur root kommt hinein")
        self.assertEqual(os.stat(K.LOCK_FILE).st_mode & 0o777, 0o600)
        os.chmod(ordner, 0o755)
        K.lock_or_exit().release()
        self.assertEqual(os.stat(ordner).st_mode & 0o777, 0o700, "zu weite Rechte werden wieder eng")
        # Eine Datei, die nicht root gehört (hier: Tests laufen ohne root, also nur die eigene UID als «fremd»)
        self.addCleanup(setattr, K, "TRUSTED_UIDS", K.TRUSTED_UIDS)
        K.TRUSTED_UIDS = (0,)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(K.lock_or_exit(), 1)
        self.assertIn("gehört nicht root", err.getvalue())
        K.TRUSTED_UIDS = (0, os.getuid())
        os.unlink(K.LOCK_FILE)
        os.symlink(self.pfad("woanders"), K.LOCK_FILE)
        for befehl in (K.cmd_check, K.cmd_install, K.cmd_after_boot):
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(befehl([]), 1, befehl.__name__)
            self.assertIn("Sperre", err.getvalue())
        self.assertFalse(os.path.exists(self.pfad("woanders")))

    def test_haertung_gegen_fremde_config_und_hooks(self):
        """Weder eine globale git-config noch config und Hooks in /opt/zenos ändern die Prüfung oder führen etwas
        aus."""
        marke = self.pfad("ausgefuehrt")
        boese = self.pfad("boese.sh")
        with open(boese, "w", encoding="utf-8") as f:
            f.write(f"#!/bin/sh\necho boese >> {marke}\nexit 0\n")
        os.chmod(boese, 0o755)
        hooks = self.pfad("hooks")
        os.makedirs(hooks)
        for hook in ("reference-transaction", "post-checkout", "post-merge", "pre-auto-gc", "fsmonitor-watchman"):
            shutil.copy(boese, os.path.join(hooks, hook))
            shutil.copy(boese, os.path.join(K.CODE_DIR, ".git", "hooks", hook))
        erlaubt = self.pfad("erlaubt")
        with open(erlaubt, "w", encoding="utf-8") as f:
            f.write(f'zenos-release namespaces="git" {k("fremd")}\n')
        globale = self.pfad("global.gitconfig")
        with open(globale, "w", encoding="utf-8") as f:
            f.write(f"[core]\n\thooksPath = {hooks}\n\tfsmonitor = {boese}\n[gpg \"ssh\"]\n\tallowedSignersFile = "
                    f"{erlaubt}\n\tprogram = {boese}\n")
        for name, wert in (("GIT_CONFIG_GLOBAL", globale), ("GIT_CONFIG_PARAMETERS", f"'core.hooksPath'='{hooks}'"),
                           ("GIT_DIR", K.CODE_DIR), ("GIT_EXEC_PATH", hooks)):
            alt = os.environ.get(name)
            self.addCleanup(lambda n=name, a=alt: os.environ.__setitem__(n, a) if a is not None
                            else os.environ.pop(n, None))
            os.environ[name] = wert
        self.git("config", "core.fsmonitor", boese, ort=K.CODE_DIR)
        self.git("config", "core.hooksPath", hooks, ort=K.CODE_DIR)
        self.git("config", "gpg.ssh.allowedSignersFile", erlaubt, ort=K.CODE_DIR)
        self.commit("zwei")
        self.signieren("v0.2.0", "fremd")
        rc, stand = self.lauf()
        self.assertEqual(rc, 0, self.ausgabe)
        self.assertIn("fremder Schlüssel", self.abgelehnt(stand)["v0.2.0"])
        self.assertFalse(os.path.exists(marke), "ein Hook oder fsmonitor lief")

    def test_status(self):
        self.commit("zwei")
        self.unsigniert("v0.1.0-rc3")
        self.signieren("v0.1.0-rc4")
        self.lauf()
        aus = io.StringIO()
        with contextlib.redirect_stdout(aus):
            self.assertEqual(K.cmd_status([]), 0)
        text = aus.getvalue()
        for erwartet in ("vorschau", "neue Version bereit", "Serie 1", K.fingerprint(k("wur")),
                         K.fingerprint(k("rel")), "v0.1.0-rc3: unsigniert", "Widerrufen  keine"):
            self.assertIn(erwartet, text)
        with contextlib.redirect_stdout(io.StringIO()) as kurz:
            K.cmd_status(["--kurz"])
        self.assertTrue(kurz.getvalue().startswith("bereit "))
        with contextlib.redirect_stdout(io.StringIO()) as roh:
            K.cmd_status(["--json"])
        self.assertEqual(json.loads(roh.getvalue())["bereit"]["version"], "v0.1.0-rc4")

    def test_status_nach_ankerwechsel_veraltet(self):
        self.lauf()
        with contextlib.redirect_stdout(io.StringIO()) as kurz:
            K.cmd_status(["--kurz"])
        self.assertTrue(kurz.getvalue().startswith("kein_kontakt ") or kurz.getvalue().startswith("aktuell "),
                        kurz.getvalue())
        self.anker(release=("rel2",))
        with contextlib.redirect_stdout(io.StringIO()) as kurz:
            K.cmd_status(["--kurz"])
        self.assertTrue(kurz.getvalue().startswith("veraltet "), kurz.getvalue())
        with contextlib.redirect_stdout(io.StringIO()) as aus:
            K.cmd_status([])
        self.assertIn("seit der letzten Prüfung geändert", aus.getvalue())

    def test_status_ohne_pruefung(self):
        shutil.rmtree(K.ANCHOR_DIR)
        with contextlib.redirect_stdout(io.StringIO()) as aus:
            self.assertEqual(K.cmd_status([]), 0)
        self.assertIn("noch nie geprüft", aus.getvalue())
        self.assertIn("fehlt", aus.getvalue())


class Dev(Basis):
    def test_unsignierter_zwischencommit(self):
        """Fall b1: Unter einer signierten Spitze liegt ein unsignierter Commit."""
        self.kanal("dev")
        self.commit("unsigniert")
        spitze = self.commit("signiert", signiert_mit="rel")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (0, "dev"))
        self.assertEqual(stand["dev"]["commit"], spitze)
        self.assertEqual((stand["dev"]["commits"], stand["dev"]["vorfahre"]), (2, True))
        self.assertFalse(stand["dev"]["signiert"])
        self.assertTrue(stand["dev"]["braucht_ja"])
        self.assertIn("«ja»", stand["grund"])

    def test_alle_signiert(self):
        self.kanal("dev")
        self.commit("a", signiert_mit="rel")
        self.commit("b", signiert_mit="rel")
        _, stand = self.lauf()
        self.assertTrue(stand["dev"]["signiert"])
        self.assertFalse(stand["dev"]["braucht_ja"])

    def test_signiert_mit_fremdem_schluessel(self):
        self.kanal("dev")
        self.commit("a", signiert_mit="fremd")
        _, stand = self.lauf()
        self.assertFalse(stand["dev"]["signiert"])

    def test_dev_ohne_anker(self):
        self.kanal("dev")
        shutil.rmtree(K.ANCHOR_DIR)
        self.commit("a", signiert_mit="rel")
        rc, stand = self.lauf()
        self.assertEqual((rc, stand["zustand"]), (3, "anker_fehlt"))
        self.assertTrue(stand["dev"]["braucht_ja"])

    def test_dev_aktuell(self):
        self.kanal("dev")
        _, stand = self.lauf()
        self.assertFalse(stand["dev"]["neu"])
        self.assertIn("installiert ist der Stand von origin/dev", stand["grund"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
