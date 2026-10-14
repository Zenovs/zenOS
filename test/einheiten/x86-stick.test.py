#!/usr/bin/env python3
"""Einheitentests für den Installer-Stick für x86: image/x86-stick.sh, image/x86/autoinstall.yaml und
image/x86/einrichten.sh.

Ohne Netz, ohne Download und ohne root:
- Der Ubuntu-CD-Schlüssel in x86-stick.sh ist derselbe wie in image/bauen.sh.
- autoinstall.yaml fragt alles Persönliche am Bildschirm ab, enthält kein Passwort und ruft einrichten.sh ohne Shell auf.
- einrichten.sh nimmt nur einen gültigen Stand an (stand_lesen, geladen ohne main).
- «x86-stick.sh --nur-pruefen» in einem Wegwerf-Repo: Ohne gültig signierten Tag nur als Testbau, dann Kanal dev und
  Version mit «-testbau»; ein Stand ohne image/x86/ wird abgelehnt.

  python3 test/einheiten/x86-stick.test.py
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STICK = os.path.join(WURZEL, "image", "x86-stick.sh")
BAUEN = os.path.join(WURZEL, "image", "bauen.sh")
YAML = os.path.join(WURZEL, "image", "x86", "autoinstall.yaml")
EINRICHTEN = os.path.join(WURZEL, "image", "x86", "einrichten.sh")
README = os.path.join(WURZEL, "image", "x86", "README")

try:
    import yaml
except ImportError:  # python3-yaml fehlt (etwa auf dem Mac)
    yaml = None


def lesen(pfad):
    with open(pfad, encoding="utf-8") as f:
        return f.read()


def schluessel(text):
    m = re.search(r"cdimage_keyring\(\) \{\n  base64 -d[^\n]*<<'EOF'[^\n]*\n(.*?)\nEOF\n", text, re.S)
    return m.group(1) if m else None


class Schluessel(unittest.TestCase):
    def test_gleich_wie_bauen(self):
        stick, bauen = lesen(STICK), lesen(BAUEN)
        self.assertIsNotNone(schluessel(stick))
        self.assertEqual(schluessel(stick), schluessel(bauen))
        # Fallback für base64 -D (Mac) mit demselben Inhalt
        m = re.search(r"\nEOF\n(.*?)\nEOF2\n", stick, re.S)
        self.assertEqual(m.group(1), schluessel(bauen))
        fpr = re.compile(r"CDIMAGE_FINGERPRINT=([0-9A-F]{40})")
        self.assertEqual(fpr.search(stick).group(1), fpr.search(bauen).group(1))


class Autoinstall(unittest.TestCase):
    def test_kein_passwort_und_keine_persoenlichen_werte(self):
        text = lesen(YAML)
        for wort in ("password", "passwort:", "hostname:", "username:", "realname:", "authorized-keys"):
            self.assertNotIn(wort, text.lower())
        self.assertNotIn("\t", text)

    @unittest.skipIf(yaml is None, "python3-yaml fehlt")
    def test_aufbau(self):
        with open(YAML, encoding="utf-8") as f:
            daten = yaml.safe_load(f)
        a = daten["autoinstall"]
        self.assertEqual(a["version"], 1)
        for teil in ("locale", "keyboard", "network", "storage", "identity", "ssh"):
            self.assertIn(teil, a["interactive-sections"])
        self.assertNotIn("identity", a)
        self.assertNotIn("storage", a)
        self.assertEqual(a["refresh-installer"], {"update": False})
        self.assertEqual(a["source"]["id"], "ubuntu-server")
        self.assertIn("git", a["packages"])
        self.assertEqual(a["snaps"], [])
        self.assertEqual(a["updates"], "security")
        # Argumentliste, keine Shell
        self.assertEqual(a["late-commands"], [["bash", "/cdrom/zenos/einrichten.sh", "/target"]])
        self.assertEqual(a["shutdown"], "reboot")


STAND = r"""
set -uo pipefail
source "$1"
QUELLE=$2
stand_lesen
printf 'ERGEBNIS %s|%s|%s|%s|%s|%s\n' "$TAG" "$COMMIT" "$KANAL" "$VERSION" "$ORIGIN" "$SIGNIERT"
"""


class Stand(unittest.TestCase):
    COMMIT = "0123456789abcdef0123456789abcdef01234567"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        with open(os.path.join(self.tmp.name, "zenos.bundle"), "w", encoding="utf-8") as f:
            f.write("bundle\n")

    def lauf(self, **werte):
        stand = {"tag": "v0.1.0-rc8", "commit": self.COMMIT, "kanal": "vorschau", "version": "0.1.0-rc8",
                 "origin": "https://github.com/Zenovs/zenOS.git", "signiert": "1"}
        stand.update(werte)
        with open(os.path.join(self.tmp.name, "stand"), "w", encoding="utf-8") as f:
            f.write("# Test\n" + "".join(f"{k}={v}\n" for k, v in stand.items()))
        return subprocess.run(["bash", "-c", STAND, "stand", EINRICHTEN, self.tmp.name], capture_output=True,
                              text=True, timeout=30, check=False)

    def test_gueltig(self):
        r = self.lauf()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"ERGEBNIS v0.1.0-rc8|{self.COMMIT}|vorschau|0.1.0-rc8|https://github.com/Zenovs/zenOS.git|1",
                      r.stdout)

    def test_testbau(self):
        r = self.lauf(tag="", kanal="dev", version="0.1.0-rc7-5-gabc-testbau", signiert="0", origin="")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Testbau ohne gültige Signatur", r.stderr)

    def test_ungueltig(self):
        for werte in ({"commit": "abc"}, {"commit": self.COMMIT + "; rm"}, {"tag": "v1.0"}, {"tag": "v1.0.0-beta"},
                      {"kanal": "nacht"}, {"version": "-x"}, {"version": "1 2"}, {"origin": "http://example.org/x"},
                      {"origin": "https://user@example.org/x"}, {"signiert": "ja"}, {"tag": "", "signiert": "1"}):
            r = self.lauf(**werte)
            self.assertEqual(r.returncode, 1, werte)
            self.assertNotIn("ERGEBNIS", r.stdout, werte)

    def test_ohne_bundle(self):
        os.unlink(os.path.join(self.tmp.name, "zenos.bundle"))
        self.assertEqual(self.lauf().returncode, 1)


class NurPruefen(unittest.TestCase):
    """x86-stick.sh --nur-pruefen in einem Wegwerf-Repo (git und ssh-keygen, kein Netz)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = os.path.join(self.tmp.name, "repo")
        os.makedirs(os.path.join(self.repo, "image", "x86"))
        for pfad in (YAML, EINRICHTEN, README):
            shutil.copy(pfad, os.path.join(self.repo, "image", "x86", os.path.basename(pfad)))
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.git("init", "-q", "-b", "main")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "stick")

    def git(self, *argumente):
        subprocess.run(["git", "-C", self.repo, *argumente], check=True, env=self.env, capture_output=True)

    def lauf(self, *argumente):
        return subprocess.run([STICK, "--quelle", self.repo, "--nur-pruefen", *argumente], capture_output=True,
                              text=True, timeout=60, check=False, env=self.env)

    def werte(self, r):
        self.assertEqual(r.returncode, 0, r.stderr)
        return dict(z.split("=", 1) for z in r.stdout.splitlines() if "=" in z)

    def test_ohne_tag_nur_testbau(self):
        self.assertEqual(self.lauf().returncode, 1)
        w = self.werte(self.lauf("--testbau-ohne-signatur"))
        self.assertEqual((w["tag"], w["kanal"], w["signiert"]), ("", "dev", "0"))
        self.assertTrue(w["version"].endswith("-testbau"), w)

    def test_unsignierter_tag_abgelehnt(self):
        self.git("tag", "-a", "-m", "v9.9.9", "v9.9.9")
        r = self.lauf()
        self.assertEqual(r.returncode, 1)
        self.assertIn("nicht gültig signiert", r.stderr)
        w = self.werte(self.lauf("--ref", "v9.9.9", "--testbau-ohne-signatur"))
        self.assertEqual((w["tag"], w["kanal"], w["version"]), ("v9.9.9", "dev", "9.9.9-testbau"))

    def test_stand_ohne_stick(self):
        self.git("rm", "-q", "-r", "image")
        self.git("commit", "-q", "-m", "ohne")
        r = self.lauf("--testbau-ohne-signatur")
        self.assertEqual(r.returncode, 1)
        self.assertIn("ab v0.1.0-rc8", r.stderr)

    def test_falscher_aufruf(self):
        for argumente in (("--ref",), ("--ubuntu", "26"), ("--unbekannt",)):
            self.assertEqual(self.lauf(*argumente).returncode, 2, argumente)


if __name__ == "__main__":
    unittest.main()
