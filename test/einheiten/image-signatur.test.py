#!/usr/bin/env python3
"""Einheitentests für die Prüfung vor dem Image-Bau: image/tag-pruefen.sh (gültig signierter Release-Tag gegen den
Anker im Stand), «image/bauen.sh --nur-pruefen» (Tag, Signatur, Kanal und Version, ohne root und ohne Bau) und die
Prüfschritte in .github/workflows/image.yml und pruefen.yml (Aufbau der Jobs; die Schritte «Signatur prüfen»,
«Versionshinweise», «Manifest» und «Release erstellen» laufen so, wie GitHub sie ausführt, gegen ein Wegwerf-Repo bzw.
mit einem nachgebauten gh, das nur mitschreibt; ohne PyYAML übersprungen).

Alles mit Wegwerf-Repos und Wegwerf-Schlüsseln im Temp-Ordner, erzeugt zur Laufzeit; signiert wird mit ssh-keygen und
einer Schlüsseldatei, nie mit 1Password. tag-pruefen.sh hat den ersten Anker von zenOS (Serie 1) fest im Code: Die Tests
laufen mit einer Kopie von image/ (tag-pruefen.sh und bauen.sh), in der dort die Fingerabdrücke des Wegwerf-Ankers
stehen; das echte Skript prüft test_echter_anker. Kein Netz, kein root nötig (als root läuft es genauso, wie in der CI).
tag-pruefen.sh läuft auch auf dem Mac (bash 3.2); die Tests für bauen.sh nur unter Linux (bash 4+, GNU coreutils) und
überspringen sich sonst. Ohne /usr/bin/git oder /usr/bin/ssh-keygen wird alles übersprungen.

  python3 test/einheiten/image-signatur.test.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

try:
    import yaml
except ImportError:  # auf dem Mac ohne PyYAML; in der CI installiert pruefen.yml python3-yaml
    yaml = None

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TAG_PRUEFEN = os.path.join(WURZEL, "image", "tag-pruefen.sh")
BAUEN = os.path.join(WURZEL, "image", "bauen.sh")
ANKER_REPO = os.path.join(WURZEL, "system", "vertrauen")
WORKFLOWS = os.path.join(WURZEL, ".github", "workflows")

SYSTEM_PFAD = "/usr/bin:/bin"
BASH = shutil.which("bash", path=SYSTEM_PFAD)
HAT_WERKZEUGE = bool(BASH) and os.access("/usr/bin/git", os.X_OK) and os.access("/usr/bin/ssh-keygen", os.X_OK)
LINUX = os.path.exists("/proc/self")

_modul = {}


def setUpModule():
    if not HAT_WERKZEUGE:
        return
    ordner = tempfile.mkdtemp(prefix="zenos-image-schluessel.")
    _modul["ordner"] = ordner
    _modul["schluessel"] = {}
    for name in ("rel", "rel2", "wur", "fremd"):
        pfad = os.path.join(ordner, name)
        subprocess.run(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "", "-f", pfad], check=True,
                       env={"PATH": SYSTEM_PFAD, "HOME": ordner})
        with open(pfad + ".pub", encoding="utf-8") as f:
            _modul["schluessel"][name] = " ".join(f.read().split()[:2])
    # Kopie von image/ mit dem Wegwerf-Anker (wur, rel) als Serie 1
    kopie = os.path.join(ordner, "kopie", "image")
    os.makedirs(kopie)
    shutil.copy(BAUEN, os.path.join(kopie, "bauen.sh"))
    with open(TAG_PRUEFEN, encoding="utf-8") as f:
        text = f.read()
    for name, wert in (("SERIE1_WURZEL", fingerabdruck("wur")), ("SERIE1_RELEASE", fingerabdruck("rel"))):
        alt = next(z for z in text.split("\n") if z.startswith(name + "="))
        text = text.replace(alt + "\n", f"{name}='{wert}'\n", 1)
    with open(os.path.join(kopie, "tag-pruefen.sh"), "w", encoding="utf-8") as f:
        f.write(text)
    for name in ("bauen.sh", "tag-pruefen.sh"):
        os.chmod(os.path.join(kopie, name), 0o755)
    _modul["tag_pruefen"] = os.path.join(kopie, "tag-pruefen.sh")
    _modul["bauen"] = os.path.join(kopie, "bauen.sh")


def tearDownModule():
    if _modul.get("ordner"):
        shutil.rmtree(_modul["ordner"], ignore_errors=True)


def k(name):
    return _modul["schluessel"][name]


def privat(name):
    return os.path.join(_modul["ordner"], name)


def fingerabdruck(name):
    r = subprocess.run(["/usr/bin/ssh-keygen", "-lf", privat(name) + ".pub"], capture_output=True, text=True,
                       check=True)
    return r.stdout.split()[1]


def anker_texte(release=("rel",), wurzel="wur", widerrufen=(), serie=1):
    return {
        "release": "# Testanker\n" + "".join(f'zenos-release namespaces="git" {k(n)}\n' for n in release),
        "wurzel": "# Testanker\n" + (f'zenos-wurzel namespaces="git" {k(wurzel)}\n' if wurzel else ""),
        "widerrufen": "# Testanker\n" + "".join(f"{k(n)}\n" for n in widerrufen),
        "serie": "# Testanker\n" + (f"{serie}\n" if serie else ""),
    }


@unittest.skipUnless(HAT_WERKZEUGE, "bash, /usr/bin/git oder /usr/bin/ssh-keygen fehlt")
class Basis(unittest.TestCase):
    """Repo mit dev und einem Anker rel/wur, Serie 1, im ersten Commit."""

    def setUp(self):
        self.ordner = os.path.realpath(tempfile.mkdtemp(prefix="zenos-image-test."))
        self.addCleanup(shutil.rmtree, self.ordner, True)
        self.home = os.path.join(self.ordner, "home")
        os.makedirs(self.home)
        gitconfig = os.path.join(self.home, ".gitconfig")
        with open(gitconfig, "w", encoding="utf-8") as f:
            f.write("[user]\n\tname = Test\n\temail = test@example.invalid\n[init]\n\tdefaultBranch = dev\n"
                    "[advice]\n\tdetachedHead = false\n[tag]\n\tgpgSign = false\n[commit]\n\tgpgSign = false\n")
        self.env = {"PATH": SYSTEM_PFAD, "HOME": self.home, "LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_CONFIG_GLOBAL": gitconfig}
        self.repo = os.path.join(self.ordner, "repo")
        self.git("init", "-q", "-b", "dev", self.repo, ort=self.ordner)
        self.anker()

    # -- Hilfen --

    def git(self, *argumente, ort=None, eingabe=None):
        r = subprocess.run(["/usr/bin/git", "-C", ort or self.repo, *argumente], env=self.env, capture_output=True,
                           text=True, check=False, input=eingabe)
        if r.returncode != 0:
            self.fail(f"git {' '.join(argumente)}: {r.stderr}")
        return r.stdout.strip()

    def commit(self, nachricht, dateien=None):
        for name, inhalt in (dateien or {"datei": nachricht + "\n"}).items():
            ziel = os.path.join(self.repo, name)
            os.makedirs(os.path.dirname(ziel), exist_ok=True)
            with open(ziel, "w", encoding="utf-8") as f:
                f.write(inhalt)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", nachricht)
        return self.git("rev-parse", "HEAD")

    def anker(self, **art):
        texte = anker_texte(**art)
        return self.commit(f"anker {art}", {f"system/vertrauen/{n}": t for n, t in texte.items()})

    def signieren(self, name, schluessel="rel", ref="HEAD"):
        self.git("-c", "gpg.format=ssh", "-c", f"user.signingkey={privat(schluessel)}", "tag", "-s", "-m",
                 f"zenOS {name}", name, ref)
        return self.git("rev-parse", f"refs/tags/{name}")

    def pruefen(self, name, commit=None, quelle=None, umgebung=None, skript=None):
        argv = [BASH, skript or _modul["tag_pruefen"], "--quelle", quelle or self.repo]
        if commit:
            argv += ["--commit", commit]
        argv.append(name)
        env = {"PATH": SYSTEM_PFAD, "HOME": self.home, "LC_ALL": "C", **(umgebung or {})}
        r = subprocess.run(argv, env=env, capture_output=True, text=True, check=False)
        werte = dict(z.split("=", 1) for z in r.stdout.splitlines() if "=" in z)
        return r.returncode, werte, r.stderr

    def gueltig(self, name, **art):
        rc, werte, err = self.pruefen(name, **art)
        self.assertEqual(rc, 0, err)
        return werte

    def abgelehnt(self, name, grund, **art):
        rc, werte, err = self.pruefen(name, **art)
        self.assertEqual(rc, 1, err)
        self.assertEqual(werte, {}, "bei Ablehnung keine Ausgabe auf stdout")
        self.assertIn(grund, err)
        return err


class TagPruefen(Basis):
    def test_rc_gueltig_vorschau(self):
        commit = self.commit("eins")
        objekt = self.signieren("v0.1.0-rc4")
        werte = self.gueltig("v0.1.0-rc4", commit=commit)
        self.assertEqual(werte["kanal"], "vorschau")
        self.assertEqual(werte["release"], "true", "auch ein -rc bekommt eine Release-Seite")
        self.assertEqual(werte["vorab"], "true", "als Vorabversion, nie «Latest»")
        self.assertEqual(werte["version"], "0.1.0-rc4")
        self.assertEqual(werte["commit"], commit)
        self.assertEqual(werte["objekt"], objekt)
        self.assertEqual(werte["schluessel"], fingerabdruck("rel"))
        self.assertEqual(werte["wurzel"], fingerabdruck("wur"))
        self.assertEqual(werte["serie"], "1")

    def test_final_gueltig_stabil(self):
        self.commit("eins")
        self.signieren("v0.2.0")
        werte = self.gueltig("v0.2.0")
        self.assertEqual(werte["kanal"], "stabil")
        self.assertEqual(werte["release"], "true")
        self.assertEqual(werte["vorab"], "false")
        self.assertEqual(set(werte), {"tag", "version", "kanal", "release", "vorab", "commit", "objekt", "schluessel",
                                      "serie", "wurzel"})

    def test_vorab_nur_aus_dem_namen(self):
        """Ob Vorabversion, sagt allein der geprüfte Name: Eine Tag-Nachricht mit «-rc» macht vX.Y.Z nicht zum
        Release-Kandidaten, und ohne Nachricht dazu bleibt -rcN eine Vorabversion."""
        self.commit("eins")
        self.git("-c", "gpg.format=ssh", "-c", f"user.signingkey={privat('rel')}", "tag", "-s", "-m",
                 "zenOS v0.2.0-rc9\n\nvorab=true", "v0.2.0")
        werte = self.gueltig("v0.2.0")
        self.assertEqual((werte["kanal"], werte["vorab"]), ("stabil", "false"))
        self.git("-c", "gpg.format=ssh", "-c", f"user.signingkey={privat('rel')}", "tag", "-s", "-m",
                 "zenOS v0.2.1\n\nvorab=false", "v0.2.1-rc10")
        werte = self.gueltig("v0.2.1-rc10")
        self.assertEqual((werte["kanal"], werte["vorab"], werte["version"]), ("vorschau", "true", "0.2.1-rc10"))

    def test_anderer_commit(self):
        eins = self.commit("eins")
        self.signieren("v0.2.0")
        self.commit("zwei")
        self.abgelehnt("v0.2.0", "gebaut werden soll", commit=self.git("rev-parse", "HEAD"))
        self.gueltig("v0.2.0", commit=eins)

    def test_unsigniert(self):
        self.commit("eins")
        self.git("tag", "-a", "-m", "zenOS v0.2.0", "v0.2.0")
        self.abgelehnt("v0.2.0", "unsigniert")

    def test_leichter_tag(self):
        self.commit("eins")
        self.git("tag", "v0.2.0")
        self.abgelehnt("v0.2.0", "kein annotierter Tag")

    def test_fremder_schluessel(self):
        self.commit("eins")
        self.signieren("v0.2.0", schluessel="fremd")
        self.abgelehnt("v0.2.0", "git verify-tag lehnt")

    def test_wurzel_statt_release(self):
        self.commit("eins")
        self.signieren("v0.2.0", schluessel="wur")
        self.abgelehnt("v0.2.0", "git verify-tag lehnt")

    def test_widerrufen(self):
        self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("vertrauen/0002", schluessel="wur")
        self.signieren("v0.2.0", schluessel="rel")
        self.abgelehnt("v0.2.0", "lehnt")
        self.signieren("v0.2.1", schluessel="rel2")
        self.gueltig("v0.2.1")

    def test_falscher_name_im_objekt(self):
        """git verify-tag prüft den Namen nicht: v0.2.0 unter dem Namen v9.0.0."""
        self.commit("eins")
        objekt = self.signieren("v0.2.0")
        self.git("update-ref", "refs/tags/v9.0.0", objekt)
        self.abgelehnt("v9.0.0", "Feld «tag»")

    def test_zwei_signaturen(self):
        self.commit("eins")
        objekt = self.signieren("v0.2.0")
        roh = self.git("cat-file", "tag", objekt) + "\n"
        start = roh.index("-----BEGIN SSH SIGNATURE-----")
        neu = self.git("mktag", eingabe=roh + roh[start:])
        self.git("update-ref", "refs/tags/v0.2.0", neu)
        self.abgelehnt("v0.2.0", "mehr als eine")

    def test_keine_release_version(self):
        """Gültig signiert, aber kein Name eines Kanals: keine Ausgabe, also kein Release und keine Vorabversion."""
        self.commit("eins")
        for name in ("v0.2.0-beta1", "v01.2.0", "0.2.0", "v0.2", "vertrauen/0001", "v0.2.0-rc0", "v0.2.0-rc01",
                     "v0.2.0-RC1", "v0.2.0-rc", "v0.2.0-rc1-fix", "v0.2.0rc1", "v0.2.0-rc1.1", "v0.2.0+rc1"):
            self.signieren(name)
            self.abgelehnt(name, "kein Release-Tag")

    def test_tag_fehlt(self):
        self.commit("eins")
        self.abgelehnt("v0.2.0", "gibt es in")

    def test_anker_leer(self):
        self.commit("anker leer", {f"system/vertrauen/{n}": "# noch ohne Schlüssel\n"
                                   for n in ("release", "wurzel", "widerrufen", "serie")})
        self.signieren("v0.2.0")
        self.abgelehnt("v0.2.0", "keine Schlüssel")

    def test_anker_fehlt(self):
        self.git("rm", "-q", "system/vertrauen/widerrufen")
        self.git("commit", "-q", "-m", "ohne widerrufen")
        self.signieren("v0.2.0")
        self.abgelehnt("v0.2.0", "widerrufen fehlt")

    def test_anker_mit_option(self):
        self.commit("anker cert", {"system/vertrauen/release":
                                   f'zenos-release cert-authority,namespaces="git" {k("rel")}\n'})
        self.signieren("v0.2.0")
        self.abgelehnt("v0.2.0", "ungültige Zeile")

    def test_anker_aus_dem_commit_nicht_aus_dem_arbeitsbaum(self):
        """Ein Anker im Arbeitsbaum (nicht committet) mit dem fremden Schlüssel hilft nicht."""
        self.commit("eins")
        self.signieren("v0.2.0", schluessel="fremd")
        with open(os.path.join(self.repo, "system", "vertrauen", "release"), "w", encoding="utf-8") as f:
            f.write(f'zenos-release namespaces="git" {k("fremd")}\n')
        self.abgelehnt("v0.2.0", "lehnt")

    def test_fremde_config_im_repo(self):
        """Angriff: Die config des Repos setzt Prüfprogramm, Schlüsselliste, Hooks und fsmonitor. Die Befehlszeile
        gewinnt, nichts davon läuft, der fremd signierte Tag bleibt abgelehnt."""
        self.commit("eins")
        self.signieren("v0.2.0", schluessel="fremd")
        marke = os.path.join(self.ordner, "gelaufen")
        programm = os.path.join(self.ordner, "programm")
        with open(programm, "w", encoding="utf-8") as f:
            f.write(f"#!/bin/sh\ntouch {marke}\nexit 0\n")
        os.chmod(programm, 0o755)
        liste = os.path.join(self.ordner, "liste")
        with open(liste, "w", encoding="utf-8") as f:
            f.write(f'zenos-release namespaces="git" {k("fremd")}\n')
        haken = os.path.join(self.ordner, "haken")
        os.makedirs(haken)
        for name in ("post-checkout", "reference-transaction", "fsmonitor-watchman"):
            shutil.copy(programm, os.path.join(haken, name))
        self.git("config", "gpg.ssh.program", programm)
        self.git("config", "gpg.ssh.allowedSignersFile", liste)
        self.git("config", "gpg.ssh.revocationFile", "/dev/null")
        self.git("config", "core.hooksPath", haken)
        self.git("config", "core.fsmonitor", programm)
        self.abgelehnt("v0.2.0", "lehnt")
        self.assertFalse(os.path.exists(marke), "ein Programm aus der config des Repos ist gelaufen")

    def test_serie_2_mit_vertrauen(self):
        self.commit("eins")
        self.signieren("v0.1.0")
        neu = self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("vertrauen/0002", schluessel="wur")
        self.commit("zwei")
        self.signieren("v0.2.0", schluessel="rel2")
        werte = self.gueltig("v0.2.0")
        self.assertEqual(werte["serie"], "2")
        self.assertEqual(werte["schluessel"], fingerabdruck("rel2"))
        self.assertNotEqual(neu, werte["commit"])

    def test_serie_2_ohne_vertrauen(self):
        self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("v0.2.0", schluessel="rel2")
        self.abgelehnt("v0.2.0", "vertrauen/0002")

    def test_vertrauen_mit_release_schluessel(self):
        self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("vertrauen/0002", schluessel="rel2")
        self.signieren("v0.2.0", schluessel="rel2")
        self.abgelehnt("v0.2.0", "vertrauen/0002")

    def test_vertrauen_auf_anderem_anker(self):
        """vertrauen/0002 zeigt auf einen Commit mit einem anderen Anker als dem im Stand des Releases."""
        self.anker(release=("rel2",), serie=2)
        self.signieren("vertrauen/0002", schluessel="wur")
        self.anker(release=("rel2", "fremd"), serie=2)
        self.signieren("v0.2.0", schluessel="fremd")
        self.abgelehnt("v0.2.0", "nicht der aus vertrauen/0002")

    def test_echter_anker_im_format(self):
        """Der Anker system/vertrauen im Repo besteht mit dem echten Skript die strenge Formprüfung und passt zum festen
        Anker (unsignierter Tag: Grund ist die Signatur, nicht der Anker)."""
        dateien = {}
        for name in ("release", "wurzel", "widerrufen", "serie"):
            with open(os.path.join(ANKER_REPO, name), encoding="utf-8") as f:
                dateien[f"system/vertrauen/{name}"] = f.read()
        self.commit("echter anker", dateien)
        self.git("tag", "-a", "-m", "zenOS v0.2.0", "v0.2.0")
        rc, _, err = self.pruefen("v0.2.0", skript=TAG_PRUEFEN)
        self.assertEqual(rc, 1, err)
        self.assertIn("unsigniert", err)
        self.assertNotIn("Anker", err)
        self.assertNotIn("Wurzel", err)

    def test_echter_anker_fest_im_skript(self):
        """Solange system/vertrauen Serie 1 ist, stehen genau seine Fingerabdrücke als fester Anker in tag-pruefen.sh."""
        with open(os.path.join(ANKER_REPO, "serie"), encoding="utf-8") as f:
            serie = [z.strip() for z in f if z.strip() and not z.lstrip().startswith("#")]
        if serie != ["1"]:
            self.skipTest("system/vertrauen ist schon eine spätere Serie")

        def fingerabdruecke(datei):
            werte = []
            with open(os.path.join(ANKER_REPO, datei), encoding="utf-8") as f:
                for zeile in f:
                    if zeile.strip() and not zeile.lstrip().startswith("#"):
                        r = subprocess.run(["/usr/bin/ssh-keygen", "-lf", "-"], input=" ".join(zeile.split()[-2:]),
                                           capture_output=True, text=True, check=True)
                        werte.append(r.stdout.split()[1])
            return " ".join(sorted(werte))

        with open(TAG_PRUEFEN, encoding="utf-8") as f:
            text = f.read()
        self.assertIn(f"SERIE1_WURZEL='{fingerabdruecke('wurzel')}'", text)
        self.assertIn(f"SERIE1_RELEASE='{fingerabdruecke('release')}'", text)

    # -- fremder oder gewachsener Anker (die Kette wie auf dem Gerät) --

    def test_fremder_anker_serie_1(self):
        """Angriff: Ein Commit tauscht den Anker gegen einen eigenen (Serie 1) und signiert den Tag damit."""
        self.anker(release=("fremd",), wurzel="rel2")
        self.signieren("v9.9.9", schluessel="fremd")
        self.abgelehnt("v9.9.9", "nicht die Wurzel von zenOS")

    def test_zusaetzlicher_release_schluessel_serie_1(self):
        """Ein gültig signiertes Release bringt ungewollt einen zusätzlichen Release-Schlüssel mit (Serie 1 bleibt)."""
        self.anker(release=("rel", "fremd"))
        self.signieren("v0.2.0")
        err = self.abgelehnt("v0.2.0", "nicht die des Ankers Serie 1")
        self.assertIn(fingerabdruck("fremd"), err)
        self.signieren("v0.2.1", schluessel="fremd")
        self.abgelehnt("v0.2.1", "nicht die des Ankers Serie 1")

    def test_fremde_wurzel_mit_eigenem_vertrauen(self):
        """Angriff: eigene Wurzel, Serie 2 und ein eigenes vertrauen/0002."""
        self.anker(release=("fremd",), wurzel="rel2", serie=2)
        self.signieren("vertrauen/0002", schluessel="rel2")
        self.signieren("v9.9.10", schluessel="fremd")
        self.abgelehnt("v9.9.10", "nicht die Wurzel von zenOS")

    def test_serie_3_ohne_vertrauen_0002(self):
        """Die Kette braucht jede Serie: vertrauen/0003 allein reicht nicht."""
        self.anker(release=("rel2",), widerrufen=("rel",), serie=3)
        self.signieren("vertrauen/0003", schluessel="wur")
        self.signieren("v0.3.0", schluessel="rel2")
        self.abgelehnt("v0.3.0", "vertrauen/0002")

    def test_serie_3_mit_kette(self):
        self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("vertrauen/0002", schluessel="wur")
        self.anker(release=("rel2", "fremd"), widerrufen=("rel",), serie=3)
        self.signieren("vertrauen/0003", schluessel="wur")
        self.commit("drei")
        self.signieren("v0.3.0", schluessel="fremd")
        self.assertEqual(self.gueltig("v0.3.0")["serie"], "3")

    def test_widerruf_der_kette_fehlt(self):
        """Serie 2 widerruft rel; der Anker von Serie 3 lässt den Widerruf weg (ein Gerät behält ihn)."""
        self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("vertrauen/0002", schluessel="wur")
        self.anker(release=("rel2",), serie=3)
        self.signieren("vertrauen/0003", schluessel="wur")
        self.signieren("v0.3.0", schluessel="rel2")
        self.abgelehnt("v0.3.0", "fehlt ein Widerruf")

    def test_widerrufener_schluessel_kommt_zurueck(self):
        """Serie 3 nimmt den in Serie 2 widerrufenen Schlüssel wieder als Release-Schlüssel: abgelehnt."""
        self.anker(release=("rel2",), widerrufen=("rel",), serie=2)
        self.signieren("vertrauen/0002", schluessel="wur")
        self.anker(release=("rel",), serie=3)
        self.signieren("vertrauen/0003", schluessel="wur")
        self.signieren("v0.3.0", schluessel="rel")
        self.abgelehnt("v0.3.0", "vertrauen/0003: ein Release-Schlüssel ist schon widerrufen")

    def test_github_meldung(self):
        self.commit("eins")
        self.git("tag", "-a", "-m", "zenOS v0.2.0", "v0.2.0")
        rc, _, err = self.pruefen("v0.2.0", umgebung={"GITHUB_ACTIONS": "true"})
        self.assertEqual(rc, 1)
        self.assertIn("::error::", err)

    def test_aufruf(self):
        for argv in ([], ["--commit", "abc", "v0.1.0"], ["--unbekannt", "v0.1.0"], ["v0.1.0", "v0.2.0"]):
            r = subprocess.run([BASH, _modul["tag_pruefen"], *argv], env={"PATH": SYSTEM_PFAD, "HOME": self.home},
                               capture_output=True, text=True, check=False, cwd=self.repo)
            self.assertEqual(r.returncode, 2, f"{argv}: {r.stderr}")


@unittest.skipUnless(LINUX, "bauen.sh läuft nur unter Linux (bash 4+, GNU coreutils)")
class BauenVorpruefung(Basis):
    """image/bauen.sh --nur-pruefen: dieselbe Vorbereitung wie vor einem echten Bau, ohne root und ohne Bau."""

    def bauen(self, *argumente, umgebung=None):
        env = {"PATH": SYSTEM_PFAD, "HOME": self.home, "LC_ALL": "C.UTF-8", **(umgebung or {})}
        r = subprocess.run([BASH, _modul["bauen"], "--nur-pruefen", "--quelle", self.repo, *argumente], env=env,
                           capture_output=True, text=True, check=False)
        return r.returncode, r.stdout + r.stderr

    def ok(self, *argumente, **art):
        rc, aus = self.bauen(*argumente, **art)
        self.assertEqual(rc, 0, aus)
        return aus

    def nein(self, text, *argumente, **art):
        rc, aus = self.bauen(*argumente, **art)
        self.assertNotEqual(rc, 0, aus)
        self.assertIn(text, aus)
        self.assertIn("Kein Image", aus)
        return aus

    def test_rc_folgt_vorschau(self):
        self.commit("eins")
        self.signieren("v0.1.0-rc4")
        aus = self.ok("--ref", "refs/tags/v0.1.0-rc4", "--version", "0.1.0-rc4")
        self.assertIn("zenOS 0.1.0-rc4 ", aus)
        self.assertIn("Kanal vorschau", aus)
        self.assertIn("gültig signiert", aus)
        self.assertIn(fingerabdruck("rel"), aus)

    def test_final_folgt_stabil(self):
        self.commit("eins")
        self.signieren("v0.2.0")
        aus = self.ok("--ref", "v0.2.0")
        self.assertIn("zenOS 0.2.0 ", aus)
        self.assertIn("Kanal stabil", aus)

    def test_kanal_passend_angegeben(self):
        self.commit("eins")
        self.signieren("v0.2.0")
        self.ok("--ref", "v0.2.0", "--kanal", "stabil")

    def test_unsigniert_bricht_ab(self):
        self.commit("eins")
        self.git("tag", "-a", "-m", "zenOS v0.2.0", "v0.2.0")
        self.nein("unsigniert", "--ref", "refs/tags/v0.2.0")

    def test_fremd_signiert_bricht_ab(self):
        self.commit("eins")
        self.signieren("v0.2.0", schluessel="fremd")
        self.nein("nicht gültig signiert", "--ref", "v0.2.0")

    def test_ohne_tag_bricht_ab(self):
        self.commit("eins")
        self.nein("kein Release-Tag")
        self.nein("kein Release-Tag", "--ref", "dev")

    def test_anderer_kanal_bricht_ab(self):
        self.commit("eins")
        self.signieren("v0.1.0-rc4")
        self.nein("folgt dem Kanal des Tags", "--ref", "v0.1.0-rc4", "--kanal", "dev")
        self.nein("folgt dem Kanal des Tags", "--ref", "v0.1.0-rc4", "--kanal", "stabil")

    def test_andere_version_bricht_ab(self):
        self.commit("eins")
        self.signieren("v0.2.0")
        self.nein("passt nicht zum Tag", "--ref", "v0.2.0", "--version", "0.2.1")

    def test_testbau_ohne_tag(self):
        self.commit("eins")
        aus = self.ok("--testbau-ohne-signatur")
        self.assertIn("-testbau ", aus)
        self.assertIn("Kanal dev", aus)
        self.assertIn("ohne gültige Signatur", aus)

    def test_testbau_unsignierter_tag(self):
        self.commit("eins")
        self.git("tag", "-a", "-m", "zenOS v0.2.0", "v0.2.0")
        aus = self.ok("--testbau-ohne-signatur", "--ref", "v0.2.0")
        self.assertIn("zenOS 0.2.0-testbau ", aus)
        self.assertIn("Kanal stabil", aus)
        self.assertIn("Warnung", aus)

    def test_testbau_anderer_kanal(self):
        self.commit("eins")
        self.signieren("v0.1.0-rc4")
        aus = self.ok("--testbau-ohne-signatur", "--ref", "v0.1.0-rc4", "--kanal", "dev")
        self.assertIn("Kanal dev", aus)
        self.assertIn("ohne Zustand ab Werk", aus)

    def test_testbau_nie_in_github(self):
        self.commit("eins")
        self.signieren("v0.2.0")
        self.nein("GitHub Actions", "--testbau-ohne-signatur", "--ref", "v0.2.0", umgebung={"GITHUB_ACTIONS": "true"})

    def test_ungueltiger_kanal(self):
        self.commit("eins")
        self.nein("Ungültiger Kanal", "--testbau-ohne-signatur", "--kanal", "main")

    def test_mechanik_ohne_signatur(self):
        self.commit("eins")
        aus = self.ok("--nur-mechanik")
        self.assertIn("-mechanik ", aus)

    def test_mechanik_nie_in_github(self):
        """--nur-mechanik baut auch ohne Signatur: in GitHub Actions verweigert wie --testbau-ohne-signatur."""
        self.commit("eins")
        self.nein("GitHub Actions", "--nur-mechanik", umgebung={"GITHUB_ACTIONS": "true"})

    def test_fremder_anker_bricht_ab(self):
        self.anker(release=("fremd",), wurzel="rel2")
        self.signieren("v9.9.9", schluessel="fremd")
        self.nein("nicht gültig signiert", "--ref", "v9.9.9")



def workflow(name):
    with open(os.path.join(WORKFLOWS, name), encoding="utf-8") as f:
        daten = yaml.safe_load(f)
    # YAML 1.1: der Schlüssel «on» wird zu True
    daten["on"] = daten.pop(True, daten.get("on"))
    return daten


def schritt(job, name):
    for s in job["steps"]:
        if s.get("name") == name:
            return s
    raise AssertionError(f"Schritt «{name}» fehlt")


@unittest.skipUnless(yaml, "PyYAML fehlt")
class WorkflowBasis(Basis):
    """image.yml und pruefen.yml geladen, Schritte ausführbar wie in GitHub Actions (bash --noprofile --norc -eo
    pipefail) mit GITHUB_OUTPUT und GITHUB_STEP_SUMMARY als Dateien."""

    def setUp(self):
        super().setUp()
        self.image = workflow("image.yml")
        self.pruefen_yml = workflow("pruefen.yml")

    def ausfuehren(self, job, name, werte, ort, pfad=SYSTEM_PFAD, als=None):
        """Führt einen run:-Schritt aus wie GitHub (bash --noprofile --norc -eo pipefail) mit WERTE als env. Jeder Wert
        muss im env des Schritts stehen: So prüft der Test auch, dass der Schritt ihn von dort bekommt. ALS (uid, nur als
        root): der Schritt läuft mit dieser uid und gid, wie die Schritte auf dem Runner ohne sudo."""
        s = schritt(self.image["jobs"][job], name)
        for schluessel in werte:
            self.assertIn(schluessel, s.get("env", {}), f"{name}: {schluessel} fehlt im env")
        lauf = os.path.join(self.ordner, "lauf")
        os.makedirs(lauf, exist_ok=True)
        skript = os.path.join(lauf, "schritt.sh")
        with open(skript, "w", encoding="utf-8") as f:
            f.write(s["run"])
        env = {"PATH": pfad, "HOME": self.home, "LC_ALL": "C.UTF-8", "RUNNER_TEMP": lauf, "GITHUB_ACTIONS": "true",
               **werte}
        for datei in ("output", "summary"):
            open(os.path.join(lauf, datei), "w", encoding="utf-8").close()
        env["GITHUB_OUTPUT"], env["GITHUB_STEP_SUMMARY"] = os.path.join(lauf, "output"), os.path.join(lauf, "summary")
        vorne = []
        if als is not None:
            for datei in ("output", "summary", "schritt.sh"):
                os.chown(os.path.join(lauf, datei), als, als)
            vorne = ["/usr/bin/setpriv", f"--reuid={als}", f"--regid={als}", "--clear-groups"]
        r = subprocess.run([*vorne, BASH, "--noprofile", "--norc", "-eo", "pipefail", skript], cwd=ort, env=env,
                           capture_output=True, text=True, check=False)
        return r.returncode, r.stdout + r.stderr, lauf


class Workflow(WorkflowBasis):
    """Aufbau von image.yml und pruefen.yml, dazu die Schritte «Signatur prüfen», «Versionshinweise» und «Manifest»."""

    def test_aufbau_image(self):
        jobs = self.image["jobs"]
        self.assertEqual(self.image["on"], {"push": {"tags": ["v*"]}})
        self.assertEqual(self.image["permissions"], {})
        tag = jobs["tag"]
        self.assertEqual(tag["permissions"], {"contents": "read"})
        auschecken = schritt(tag, "Repo auschecken")
        self.assertEqual(auschecken["with"]["fetch-depth"], 0, "nur so kommen die Tag-Objekte mit")
        self.assertIn("image/tag-pruefen.sh --commit", schritt(tag, "Signatur prüfen (verify-tag gegen system/vertrauen)")["run"])
        self.assertEqual(jobs["bauen"]["needs"], "tag")
        bauen = schritt(jobs["bauen"], "Image bauen")
        self.assertIn('--kanal "$KANAL"', bauen["run"])
        self.assertEqual(bauen["env"]["KANAL"], "${{ needs.tag.outputs.kanal }}")
        self.assertNotIn("testbau", bauen["run"])
        self.assertEqual(jobs["pruefen"]["uses"], "./.github/workflows/pruefen.yml")
        self.assertEqual(set(jobs["veroeffentlichen"]["needs"]), {"tag", "pruefen", "bauen", "quellen"})
        self.assertEqual(jobs["veroeffentlichen"]["if"], "needs.tag.outputs.release == 'true'")
        self.assertEqual(jobs["veroeffentlichen"]["permissions"], {"contents": "write"})
        self.assertGreaterEqual(jobs["veroeffentlichen"]["timeout-minutes"], 60, "rund 4,5 GB holen und hochladen")
        for name, job in jobs.items():
            if name != "veroeffentlichen" and "permissions" in job:
                self.assertNotEqual(job["permissions"].get("contents"), "write", name)
            if "steps" in job:
                self.assertIn("timeout-minutes", job, name)

    def test_vorab_durchgereicht(self):
        """tag gibt release und vorab weiter; Manifest, Versionshinweise und Release lesen vorab nur über env."""
        jobs = self.image["jobs"]
        self.assertEqual(jobs["tag"]["outputs"]["vorab"], "${{ steps.pruefen.outputs.vorab }}")
        self.assertEqual(jobs["tag"]["outputs"]["release"], "${{ steps.pruefen.outputs.release }}")
        for job, name in (("bauen", "Manifest für den Raspberry Pi Imager"), ("bauen", "Versionshinweise"),
                          ("veroeffentlichen", "Release erstellen")):
            s = schritt(jobs[job], name)
            self.assertEqual(s["env"]["VORAB"], "${{ needs.tag.outputs.vorab }}", name)
            self.assertIn('case "$VORAB" in', s["run"], name)
        release = schritt(jobs["veroeffentlichen"], "Release erstellen")["run"]
        self.assertNotIn("--clobber", release, "ein veröffentlichtes Release bleibt, wie es ist")
        self.assertNotIn("*-*", release, "Vorabversion nie aus einem Muster über den Namen, nur aus vorab")

    def test_ausdruecke_nur_ueber_env(self):
        """Kein ${{ … }} in einem run: (Einschleusen über Werte); alles kommt über env."""
        for datei, daten in (("image.yml", self.image), ("pruefen.yml", self.pruefen_yml)):
            for name, job in daten["jobs"].items():
                for s in job.get("steps", []):
                    if "run" in s:
                        self.assertNotIn("${{", s["run"], f"{datei}: {name} › {s.get('name')}")

    def test_artefakte_kurz(self):
        """Image, Paketliste und Quellen als Artefakt nur 3 Tage, bei -rc wie bei vX.Y.Z (danach: Release-Seite)."""
        jobs = self.image["jobs"]
        for job, name in (("bauen", "Paketliste für den Quellcode ablegen"), ("bauen", "Image als Artefakt ablegen"),
                          ("quellen", "Quellen als Artefakt ablegen")):
            self.assertEqual(schritt(jobs[job], name)["with"]["retention-days"], 3, name)

    def test_manifest_url_auf_release_seite(self):
        """Die url im Manifest zeigt immer auf die Datei der Release-Seite, auch bei -rc."""
        s = schritt(self.image["jobs"]["bauen"], "Manifest für den Raspberry Pi Imager")
        self.assertEqual(s["env"]["DOWNLOAD"], "${{ github.server_url }}/${{ github.repository }}/releases/download")
        self.assertIn('--arg url "$DOWNLOAD/$TAG/$datei"', s["run"])

    def test_aufbau_pruefen(self):
        on = self.pruefen_yml["on"]
        self.assertEqual(on["push"]["tags"], ["v*"])
        self.assertIn("workflow_call", on)
        self.assertIn("github.workflow", self.pruefen_yml["concurrency"]["group"],
                      "sonst bricht der Lauf für den Tag den aus image.yml ab")

    def signatur_schritt(self, tag, commit):
        """Führt «Signatur prüfen» aus wie GitHub: im Checkout, mit den env-Werten des Schritts."""
        ziel = os.path.join(self.repo, "image")
        os.makedirs(ziel, exist_ok=True)
        shutil.copy(_modul["tag_pruefen"], os.path.join(ziel, "tag-pruefen.sh"))
        rc, aus, lauf = self.ausfuehren("tag", "Signatur prüfen (verify-tag gegen system/vertrauen)",
                                        {"TAG": tag, "COMMIT": commit}, self.repo)
        with open(os.path.join(lauf, "output"), encoding="utf-8") as f:
            werte = dict(z.split("=", 1) for z in f.read().splitlines() if "=" in z)
        with open(os.path.join(lauf, "summary"), encoding="utf-8") as f:
            return rc, werte, f.read(), aus

    def test_signatur_schritt_gueltig(self):
        commit = self.commit("eins")
        self.signieren("v0.1.0-rc4")
        rc, werte, zusammenfassung, aus = self.signatur_schritt("v0.1.0-rc4", commit)
        self.assertEqual(rc, 0, aus)
        self.assertEqual((werte["kanal"], werte["release"], werte["vorab"], werte["version"]),
                         ("vorschau", "true", "true", "0.1.0-rc4"))
        self.assertIn("- Kanal: vorschau", zusammenfassung)
        self.assertIn("- Release: Vorabversion (Pre-release, nie «Latest»)", zusammenfassung)
        self.assertIn(f"- Signiert mit dem Release-Schlüssel {fingerabdruck('rel')}", zusammenfassung)
        self.assertIn("- Anker system/vertrauen, Serie 1", zusammenfassung)

    def test_signatur_schritt_final(self):
        commit = self.commit("eins")
        self.signieren("v0.2.0")
        rc, werte, zusammenfassung, aus = self.signatur_schritt("v0.2.0", commit)
        self.assertEqual(rc, 0, aus)
        self.assertEqual((werte["kanal"], werte["release"], werte["vorab"]), ("stabil", "true", "false"))
        self.assertIn("- Release: «Latest»", zusammenfassung)
        self.assertNotIn("Vorabversion", zusammenfassung)

    def test_signatur_schritt_unsigniert(self):
        commit = self.commit("eins")
        self.git("tag", "-a", "-m", "zenOS v0.2.0", "v0.2.0")
        rc, werte, _, aus = self.signatur_schritt("v0.2.0", commit)
        self.assertNotEqual(rc, 0)
        self.assertEqual(werte, {}, "ohne gültige Signatur keine Ausgaben für die folgenden Jobs")
        self.assertIn("::error::", aus)

    def test_signatur_schritt_anderer_commit(self):
        """github.sha ist ein anderer Commit als der des Tags (etwa ein verschobener Tag): kein Bau."""
        self.commit("eins")
        self.signieren("v0.2.0")
        anderer = self.commit("zwei")
        rc, werte, _, _ = self.signatur_schritt("v0.2.0", anderer)
        self.assertNotEqual(rc, 0)
        self.assertEqual(werte, {})

    def test_signatur_schritt_leichter_tag(self):
        """Kommt der Tag ohne Tag-Objekt an (leichter Tag auf den Commit): kein Bau."""
        commit = self.commit("eins")
        self.signieren("v0.2.0")
        self.git("tag", "-f", "v0.2.0", commit)
        rc, werte, _, aus = self.signatur_schritt("v0.2.0", commit)
        self.assertNotEqual(rc, 0)
        self.assertIn("kein annotierter Tag", aus)

    # -- Versionshinweise und Manifest --

    def hinweise(self, version, vorab):
        ort = os.path.join(self.ordner, "lauf", "image")
        os.makedirs(ort, exist_ok=True)
        with open(os.path.join(ort, "basis.txt"), "w", encoding="utf-8") as f:
            f.write("ubuntu_datei=ubuntu-test.img.xz\nubuntu_sha256=" + "a" * 64 + "\n")
        kanal = "vorschau" if "-rc" in version else "stabil"
        rc, aus, lauf = self.ausfuehren("bauen", "Versionshinweise", {
            "VERSION": version, "KANAL": kanal, "VORAB": vorab, "SCHLUESSEL": "SHA256:test", "TAG": "v" + version,
            "REPO": "besitzer/zenOS"}, self.ordner)
        datei = os.path.join(lauf, "hinweise", "versionshinweise.md")
        text = None
        if os.path.exists(datei):
            with open(datei, encoding="utf-8") as f:
                text = f.read()
        return rc, aus, text

    def test_hinweise_rc(self):
        rc, aus, text = self.hinweise("0.1.0-rc4", "true")
        self.assertEqual(rc, 0, aus)
        self.assertTrue(text.startswith("> **Release-Kandidat zum Testen, nicht für den Alltag.** `v0.1.0-rc4` ist "
                                        "eine Vorabversion im Kanal `vorschau`"), text[:200])
        deutsch, englisch = text.split("\n---\n")
        self.assertIn("**zenOS 0.1.0-rc4 für den Raspberry Pi 5", deutsch)
        self.assertTrue(englisch.lstrip().startswith("> **Release candidate for testing, not for everyday use.** "
                                                     "`v0.1.0-rc4` is a pre-release on the `vorschau` channel"))
        self.assertIn("**zenOS 0.1.0-rc4 for Raspberry Pi 5", englisch)
        # Auch nach der Endversion bleibt das Gerät im Kanal vorschau; der Weg zurück steht in beiden Sprachen
        self.assertIn("Es bleibt auch danach im Kanal `vorschau`", deutsch)
        self.assertIn("They stay on the `vorschau` channel after that", englisch)
        self.assertIn("`sudo zen kanal wechseln stabil`", deutsch)
        self.assertIn("`sudo zen kanal wechseln stabil`", englisch)
        self.assertIn("ubuntu-test.img.xz", deutsch)
        self.assertIn("Canonical Ltd.", englisch)

    def test_hinweise_final(self):
        rc, aus, text = self.hinweise("0.2.0", "false")
        self.assertEqual(rc, 0, aus)
        self.assertTrue(text.startswith("**zenOS 0.2.0 für den Raspberry Pi 5"), text[:200])
        self.assertNotIn("Release-Kandidat", text)
        self.assertNotIn("Release candidate", text)
        self.assertIn("\n---\n\n**zenOS 0.2.0 for Raspberry Pi 5", text)
        self.assertIn("Kanal `stabil`", text)

    def test_hinweise_ohne_vorab(self):
        for wert in ("", "ja", "True"):
            rc, aus, text = self.hinweise("0.2.0", wert)
            self.assertNotEqual(rc, 0, wert)
            self.assertIn("::error::", aus)
            self.assertIsNone(text)

    @unittest.skipUnless(LINUX and shutil.which("jq", path=SYSTEM_PFAD), "jq, GNU stat und sha256sum nur unter Linux")
    def test_manifest_rc(self):
        """Manifest bei -rc: url auf die Datei der Release-Seite (kein Umschreiben von Hand mehr), Beschreibung nennt
        den Release-Kandidaten; das Manifest kommt in SHA256SUMS."""
        lauf = os.path.join(self.ordner, "lauf")
        for ordner in ("image", "ausgabe"):
            os.makedirs(os.path.join(lauf, ordner), exist_ok=True)
        with open(os.path.join(lauf, "image", "basis.txt"), "w", encoding="utf-8") as f:
            f.write("image_groesse=4096\nimage_sha256=" + "b" * 64 + "\n")
        with open(os.path.join(lauf, "ausgabe", "zenos-0.1.0-rc4-pi5-arm64.img.xz"), "wb") as f:
            f.write(b"image")
        open(os.path.join(lauf, "ausgabe", "SHA256SUMS"), "w", encoding="utf-8").close()
        for vorab, version, beschreibung in (
                ("true", "0.1.0-rc4", "zenOS 0.1.0-rc4 (Release-Kandidat zum Testen), basiert auf Ubuntu 26.04 LTS"),
                ("false", "0.1.0", "zenOS 0.1.0, basiert auf Ubuntu 26.04 LTS")):
            datei = f"zenos-{version}-pi5-arm64.img.xz"
            if not os.path.exists(os.path.join(lauf, "ausgabe", datei)):
                shutil.copy(os.path.join(lauf, "ausgabe", "zenos-0.1.0-rc4-pi5-arm64.img.xz"),
                            os.path.join(lauf, "ausgabe", datei))
            rc, aus, _ = self.ausfuehren("bauen", "Manifest für den Raspberry Pi Imager", {
                "VERSION": version, "VORAB": vorab, "TAG": "v" + version,
                "DOWNLOAD": "https://github.com/besitzer/zenOS/releases/download"}, self.ordner)
            self.assertEqual(rc, 0, aus)
            with open(os.path.join(lauf, "hinweise", f"zenos-{version}.rpi-imager-manifest"), encoding="utf-8") as f:
                eintrag = json.load(f)["os_list"][0]
            self.assertEqual(eintrag["url"], f"https://github.com/besitzer/zenOS/releases/download/v{version}/{datei}")
            self.assertEqual(eintrag["description"], beschreibung)
            self.assertEqual(eintrag["init_format"], "cloudinit")
            with open(os.path.join(lauf, "ausgabe", "SHA256SUMS"), encoding="utf-8") as f:
                self.assertIn(f"  zenos-{version}.rpi-imager-manifest\n", f.read())
        rc, aus, _ = self.ausfuehren("bauen", "Manifest für den Raspberry Pi Imager", {
            "VERSION": "0.1.0", "VORAB": "", "TAG": "v0.1.0", "DOWNLOAD": "https://example.invalid"}, self.ordner)
        self.assertNotEqual(rc, 0)
        self.assertIn("::error::", aus)


    def test_bau_gibt_die_ausgabe_dem_runner(self):
        """Im Schritt «Image bauen» kommt nach bauen.sh (mit sudo) ein chown der Ausgabe auf den Benutzer des Runners."""
        zeilen = schritt(self.image["jobs"]["bauen"], "Image bauen")["run"].splitlines()
        bau = next(i for i, z in enumerate(zeilen) if "image/bauen.sh" in z)
        chown = [i for i, z in enumerate(zeilen) if z.strip() == 'sudo chown -R "$(id -u):$(id -g)" "$RUNNER_TEMP/ausgabe"']
        self.assertEqual(len(chown), 1, "chown der Ausgabe fehlt")
        self.assertGreater(chown[0], bau)

    @unittest.skipUnless(LINUX and os.geteuid() == 0 and os.path.exists("/usr/bin/setpriv")
                         and shutil.which("jq", path=SYSTEM_PFAD), "nur als root unter Linux mit jq (wie die CI)")
    def test_manifest_als_runner_nach_bau_mit_sudo(self):
        """Wie auf GitHub: bauen.sh läuft mit sudo, Ausgabe und Arbeitsordner gehören root, «Manifest» läuft ohne root.
        Ohne das chown aus «Image bauen» scheitert es an SHA256SUMS (so bei v0.1.0-rc4), mit ihm läuft es durch."""
        runner = 65534
        os.chmod(self.ordner, 0o755)
        lauf = os.path.join(self.ordner, "lauf")
        os.makedirs(os.path.join(lauf, "image"))
        os.makedirs(os.path.join(lauf, "ausgabe"))
        os.chown(lauf, runner, runner)
        with open(os.path.join(lauf, "image", "basis.txt"), "w", encoding="utf-8") as f:
            f.write("image_groesse=4096\nimage_sha256=" + "b" * 64 + "\n")
        with open(os.path.join(lauf, "ausgabe", "zenos-0.1.0-rc5-pi5-arm64.img.xz"), "wb") as f:
            f.write(b"image")
        with open(os.path.join(lauf, "ausgabe", "SHA256SUMS"), "w", encoding="utf-8") as f:
            f.write("a" * 64 + "  zenos-0.1.0-rc5-pi5-arm64.img.xz\n")
        werte = {"VERSION": "0.1.0-rc5", "VORAB": "true", "TAG": "v0.1.0-rc5",
                 "DOWNLOAD": "https://github.com/besitzer/zenOS/releases/download"}
        rc, aus, _ = self.ausfuehren("bauen", "Manifest für den Raspberry Pi Imager", werte, self.ordner, als=runner)
        self.assertNotEqual(rc, 0, aus)
        self.assertIn("Permission denied", aus)
        # Die Zeile aus «Image bauen», mit sudo und id des Runners nachgebaut
        zeile = next(z.strip() for z in schritt(self.image["jobs"]["bauen"], "Image bauen")["run"].splitlines()
                     if "chown" in z)
        werkzeug = os.path.join(self.ordner, "werkzeug")
        os.makedirs(werkzeug)
        for name, inhalt in (("sudo", 'exec "$@"'), ("id", f"echo {runner}")):
            with open(os.path.join(werkzeug, name), "w", encoding="utf-8") as f:
                f.write("#!/bin/sh\n" + inhalt + "\n")
            os.chmod(os.path.join(werkzeug, name), 0o755)
        r = subprocess.run([BASH, "--noprofile", "--norc", "-eo", "pipefail", "-c", zeile],
                           env={"PATH": werkzeug + ":" + SYSTEM_PFAD, "RUNNER_TEMP": lauf},
                           capture_output=True, text=True, check=False)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        rc, aus, _ = self.ausfuehren("bauen", "Manifest für den Raspberry Pi Imager", werte, self.ordner, als=runner)
        self.assertEqual(rc, 0, aus)
        with open(os.path.join(lauf, "ausgabe", "SHA256SUMS"), encoding="utf-8") as f:
            self.assertIn("  zenos-0.1.0-rc5.rpi-imager-manifest\n", f.read())


# Nachgebautes gh für «Release erstellen»: schreibt jeden Aufruf als JSON-Zeile mit (gh-protokoll) und spielt ein
# Release aus einer Zustandsdatei (gh-zustand.json: kein Release, Entwurf oder veröffentlicht, mit Dateinamen), beide im
# Ordner über seinem bin/. Kein Netz.
GH_NACHBAU = r'''
import json, os, sys
ordner = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
zustand_datei, protokoll = os.path.join(ordner, "gh-zustand.json"), os.path.join(ordner, "gh-protokoll")
argv = sys.argv[1:]
with open(protokoll, "a", encoding="utf-8") as f:
    f.write(json.dumps(argv) + "\n")
with open(zustand_datei, encoding="utf-8") as f:
    zustand = json.load(f)
release = zustand.get("release")
if argv[:2] == ["release", "view"]:
    if release is None:
        sys.stderr.write("release not found\n")
        sys.exit(1)
    jq = argv[argv.index("--jq") + 1]
    if ".assets[].name" in jq:
        print("\n".join(release["assets"]))
    else:
        print(f"{str(release['isDraft']).lower()} {str(release['isPrerelease']).lower()}")
elif argv[:2] == ["release", "delete"]:
    zustand["release"] = None
elif argv[:2] == ["release", "create"]:
    if release is not None:
        sys.stderr.write("a release with the same tag name already exists\n")
        sys.exit(1)
    zustand["release"] = {"isDraft": False, "isPrerelease": "--prerelease" in argv, "assets": []}
else:
    sys.stderr.write("unerwartet: " + " ".join(argv) + "\n")
    sys.exit(2)
with open(zustand_datei, "w", encoding="utf-8") as f:
    json.dump(zustand, f)
'''


@unittest.skipUnless(yaml, "PyYAML fehlt")
class ReleaseSchritt(WorkflowBasis):
    """«Release erstellen» aus image.yml mit nachgebautem gh: -rc als Vorabversion (nie «Latest»), vX.Y.Z als «Latest»,
    Neustart über einen Entwurf oder ein schon veröffentlichtes Release, falsche Werte für vorab."""

    def setUp(self):
        super().setUp()
        self.bin = os.path.join(self.ordner, "bin")
        os.makedirs(self.bin)
        gh = os.path.join(self.bin, "gh")
        with open(gh, "w", encoding="utf-8") as f:
            f.write(f"#!{sys.executable}\n" + GH_NACHBAU)
        os.chmod(gh, 0o755)
        self.zustand = os.path.join(self.ordner, "gh-zustand.json")
        self.protokoll = os.path.join(self.ordner, "gh-protokoll")
        self.arbeit = os.path.join(self.ordner, "arbeit")

    def dateien(self, version):
        namen = [f"artefakt/ausgabe/zenos-{version}-pi5-arm64.img.xz", "artefakt/ausgabe/SHA256SUMS",
                 f"artefakt/ausgabe/zenos-{version}-pi5-arm64.pakete.txt",
                 f"artefakt/hinweise/zenos-{version}.rpi-imager-manifest",
                 f"quellen/zenos-{version}-quellen-teil01.tar", f"quellen/zenos-{version}-quellen-teil02.tar",
                 f"quellen/zenos-{version}-quickshell-0.2.1.tar", f"quellen/zenos-{version}-QUELLEN.txt",
                 "quellen/SHA256SUMS-quellen", "artefakt/hinweise/versionshinweise.md"]
        for name in namen:
            ziel = os.path.join(self.arbeit, name)
            os.makedirs(os.path.dirname(ziel), exist_ok=True)
            with open(ziel, "w", encoding="utf-8") as f:
                f.write(name + "\n")
        return [n for n in namen if not n.endswith("versionshinweise.md")]

    def release(self, tag, vorab, vorher=None):
        """Führt den Schritt aus; gibt Exit, Ausgabe, die gh-Aufrufe und das Release danach zurück."""
        version = tag[1:]
        self.dateien(version)
        with open(self.zustand, "w", encoding="utf-8") as f:
            json.dump({"release": vorher}, f)
        open(self.protokoll, "w", encoding="utf-8").close()
        rc, aus, _ = self.ausfuehren("veroeffentlichen", "Release erstellen", {
            "GH_TOKEN": "kein-echtes-token", "GH_REPO": "besitzer/zenOS", "TAG": tag, "VERSION": version,
            "VORAB": vorab}, self.arbeit, pfad=f"{self.bin}:{SYSTEM_PFAD}")
        with open(self.protokoll, encoding="utf-8") as f:
            aufrufe = [json.loads(z) for z in f if z.strip()]
        with open(self.zustand, encoding="utf-8") as f:
            nachher = json.load(f)["release"]
        return rc, aus, aufrufe, nachher

    def erstellt(self, aufrufe):
        return [a for a in aufrufe if a[:2] == ["release", "create"]]

    def test_rc_als_vorabversion(self):
        rc, aus, aufrufe, nachher = self.release("v0.1.0-rc4", "true")
        self.assertEqual(rc, 0, aus)
        (create,) = self.erstellt(aufrufe)
        dateien = self.dateien("0.1.0-rc4")
        self.assertEqual(create[2], "v0.1.0-rc4")
        self.assertEqual(create[3:3 + len(dateien)], dateien)
        self.assertEqual(create[3 + len(dateien):], ["--verify-tag", "--title", "zenOS 0.1.0-rc4", "--notes-file",
                                                     "artefakt/hinweise/versionshinweise.md", "--prerelease",
                                                     "--latest=false"])
        self.assertTrue(nachher["isPrerelease"])

    def test_final_als_latest(self):
        rc, aus, aufrufe, nachher = self.release("v0.1.0", "false")
        self.assertEqual(rc, 0, aus)
        (create,) = self.erstellt(aufrufe)
        self.assertEqual(create[-1], "--latest")
        self.assertNotIn("--prerelease", create)
        self.assertNotIn("--latest=false", create)
        self.assertIn("quellen/zenos-0.1.0-quellen-teil02.tar", create)
        self.assertFalse(nachher["isPrerelease"])

    def test_vorab_falsch_oder_unpassend(self):
        """Kein Release ohne gültiges vorab, und vorab muss zum Tag passen (rc ↔ true, vX.Y.Z ↔ false)."""
        for tag, vorab in (("v0.1.0-rc4", ""), ("v0.1.0-rc4", "ja"), ("v0.1.0-rc4", "false"), ("v0.1.0", "true"),
                           ("v0.1.0-beta1", "true"), ("v0.1.0-beta1", "false"), ("v0.1.0", "TRUE")):
            rc, aus, aufrufe, nachher = self.release(tag, vorab)
            self.assertNotEqual(rc, 0, f"{tag} {vorab!r}: {aus}")
            self.assertIn("::error::", aus)
            self.assertEqual(aufrufe, [], f"{tag} {vorab!r}: gh darf gar nicht laufen")
            self.assertIsNone(nachher)

    def test_entwurf_wird_neu_angelegt(self):
        """Ein Entwurf von einem abgebrochenen Lauf: löschen (ohne den Tag) und neu anlegen."""
        entwurf = {"isDraft": True, "isPrerelease": True, "assets": ["zenos-0.1.0-rc4-pi5-arm64.img.xz"]}
        rc, aus, aufrufe, nachher = self.release("v0.1.0-rc4", "true", vorher=entwurf)
        self.assertEqual(rc, 0, aus)
        self.assertIn(["release", "delete", "v0.1.0-rc4", "--yes"], aufrufe)
        self.assertFalse(any("--cleanup-tag" in a for a in aufrufe), "der Tag bleibt")
        self.assertEqual(len(self.erstellt(aufrufe)), 1)
        self.assertIn("::warning::", aus)
        self.assertFalse(nachher["isDraft"])

    def test_veroeffentlicht_bleibt(self):
        """Schon veröffentlicht und vollständig: nichts hochladen, nichts löschen, Exit 0."""
        namen = [os.path.basename(d) for d in self.dateien("0.1.0-rc4")]
        fertig = {"isDraft": False, "isPrerelease": True, "assets": namen}
        rc, aus, aufrufe, nachher = self.release("v0.1.0-rc4", "true", vorher=fertig)
        self.assertEqual(rc, 0, aus)
        self.assertEqual({tuple(a[:2]) for a in aufrufe}, {("release", "view")})
        self.assertIn("::notice::", aus)
        self.assertEqual(nachher, fertig)

    def test_veroeffentlicht_unvollstaendig(self):
        namen = [os.path.basename(d) for d in self.dateien("0.1.0")]
        teilweise = {"isDraft": False, "isPrerelease": False, "assets": namen[:3]}
        rc, aus, aufrufe, nachher = self.release("v0.1.0", "false", vorher=teilweise)
        self.assertNotEqual(rc, 0)
        self.assertIn("::error::", aus)
        self.assertIn("zenos-0.1.0-quellen-teil01.tar", aus)
        self.assertEqual({tuple(a[:2]) for a in aufrufe}, {("release", "view")})
        self.assertEqual(nachher, teilweise)

    def test_veroeffentlicht_falsch_markiert(self):
        """Ein -rc liegt schon als normales Release vor (oder umgekehrt): Fehler, nichts ändern."""
        for tag, vorab, prerelease in (("v0.1.0-rc4", "true", False), ("v0.1.0", "false", True)):
            namen = [os.path.basename(d) for d in self.dateien(tag[1:])]
            vorher = {"isDraft": False, "isPrerelease": prerelease, "assets": namen}
            rc, aus, aufrufe, nachher = self.release(tag, vorab, vorher=vorher)
            self.assertNotEqual(rc, 0, tag)
            self.assertIn("::error::", aus)
            self.assertEqual(self.erstellt(aufrufe), [])
            self.assertEqual(nachher, vorher)


if __name__ == "__main__":
    unittest.main(verbosity=2)
