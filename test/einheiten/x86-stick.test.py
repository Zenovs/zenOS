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

import json
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
INSTALLER = os.path.join(WURZEL, "image", "x86", "installer")
TOKENS = os.path.join(WURZEL, "shell", "theme", "tokens.json")
ZEICHEN = os.path.join(WURZEL, "assets", "zeichen")

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
        """Grafischer Installer von Ubuntu Desktop: alle Schritte interaktiv, die Datei hängt nur git und die
        Einrichtung an. Keine vorbelegten Antworten (Konto, Festplatte, Quelle), die den Installer überspringen
        liessen."""
        with open(YAML, encoding="utf-8") as f:
            daten = yaml.safe_load(f)
        a = daten["autoinstall"]
        self.assertEqual(a["version"], 1)
        self.assertEqual(a["interactive-sections"], ["*"])
        for schluessel in ("identity", "storage", "source", "locale", "keyboard", "network", "user-data", "shutdown"):
            self.assertNotIn(schluessel, a)
        self.assertIn("git", a["packages"])
        # Argumentliste, keine Shell
        self.assertEqual(a["late-commands"], [["bash", "/cdrom/zenos/einrichten.sh", "/target"]])
        self.assertEqual(set(a), {"version", "interactive-sections", "refresh-installer", "apt", "packages",
                                  "late-commands"})
        # Kein Neuladen des Installers: sonst Kanal aus .disk/info («zenOS <Version>») und ein ungeprüfter Installer
        self.assertEqual(a["refresh-installer"], {"update": False})
        # Hauptspiegel statt Standortwahl, Wiederholungen bei langsamen Verbindungen (Abbruch beim Kernel)
        self.assertIs(a["apt"]["geoip"], False)
        self.assertIn('Acquire::Retries "10";', a["apt"]["conf"])
        self.assertEqual(set(a["apt"]), {"geoip", "conf"})


STAND = r"""
set -uo pipefail
source "$1"
QUELLE=$2
stand_lesen
printf 'ERGEBNIS %s|%s|%s|%s|%s|%s\n' "$TAG" "$COMMIT" "$KANAL" "$VERSION" "$ORIGIN" "$SIGNIERT"
"""


class Vorlagen(unittest.TestCase):
    """image/x86/installer: whitelabel.yaml und Folien für den grafischen Installer."""

    def test_platzhalter_nur_farben(self):
        text = lesen(os.path.join(INSTALLER, "whitelabel.yaml"))
        self.assertEqual(sorted(set(re.findall(r"@([A-Z_]+)@", text))),
                         ["AKZENT_DUNKEL", "AKZENT_HELL", "KNOPFTEXT_DUNKEL", "KNOPFTEXT_HELL"])
        self.assertNotRegex(text, r"#[0-9A-Fa-f]{6}", "Farben nur aus tokens.json")
        self.assertNotRegex(lesen(os.path.join(INSTALLER, "live-look.sh.in")), r"#[0-9A-Fa-f]{6}")

    def test_folien(self):
        zeilen = [z.split("|") for z in lesen(os.path.join(INSTALLER, "folien.txt")).splitlines()
                  if z.strip() and not z.startswith("#")]
        paare = {(z[0], z[1]) for z in zeilen}
        nummern = sorted({z[0] for z in zeilen})
        for nr in nummern:
            self.assertIn((nr, "de"), paare)
            self.assertIn((nr, "en"), paare, "ohne englischen Rückfall zeigte der Installer Ubuntus Folien")
        for z in zeilen:
            self.assertEqual(len(z), 5, z)
            self.assertFalse(set("<>&") & set("".join(z[2:])), z)

    def test_startmenue_und_schicht(self):
        text = lesen(STICK)
        self.assertIn("SCHICHT=minimal.standard.live.zenos.squashfs", text)
        self.assertIn('menuentry "zenOS installieren" {', text)
        self.assertIn("layerfs-path=$SCHICHT", text)
        self.assertIn('-map "$TMP/info" /.disk/info', text)

    def produkt(self, version, zeile):
        r = subprocess.run(["bash", "-c", 'source "$1"; produkt_zeile "$2" "$3"', "test", STICK, version, zeile],
                           capture_output=True, text=True)
        return r.returncode, r.stdout

    def test_produktname(self):
        """Der Installer liest Name und Version vor dem ersten Anführungszeichen, casper das erste Wort (Live-Konto)
        und die Seriennummer am Ende in Klammern (pollinate)."""
        ubuntu = 'Ubuntu 26.04.1 LTS "Resolute Raccoon" - Release amd64 (20260826)'
        rc, zeile = self.produkt("0.1.0-rc8", ubuntu)
        self.assertEqual(rc, 0)
        self.assertEqual(zeile, 'zenOS 0.1.0-rc8 "Ubuntu 26.04.1 LTS" - Release amd64 (20260826)')
        self.assertEqual(zeile.split('"')[0].strip(), "zenOS 0.1.0-rc8")
        self.assertEqual(zeile.split()[0], "zenOS")
        self.assertTrue(zeile.endswith("(20260826)"))
        self.assertEqual(self.produkt("0.1.0", "Ubuntu 26.04 ohne Anführungszeichen")[0], 1)


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


DESKTOP = r"""
set -uo pipefail
source "$1"
ZIEL=$2
# Attrappe: systemctl disable im chroot entfernt den Verweis wie systemd
in_chroot() {
  printf 'chroot %s\n' "$*"
  if [[ "$1 $2" == "systemctl disable" ]]; then rm -f -- "$ZIEL/etc/systemd/system/display-manager.service"; fi
}
"$3"
"""


class Desktop(unittest.TestCase):
    """Ubuntu Desktop als Grundlage: gdm3 weicht greetd, die Netzumstellung beim ersten Start entfällt."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ziel = self.tmp.name
        os.makedirs(os.path.join(self.ziel, "etc", "systemd", "system"))
        os.makedirs(os.path.join(self.ziel, "etc", "netplan"))
        os.makedirs(os.path.join(self.ziel, "var", "lib", "zenos"))

    def pfad(self, *teile):
        return os.path.join(self.ziel, *teile)

    def lauf(self, funktion):
        return subprocess.run(["bash", "-c", DESKTOP, "desktop", EINRICHTEN, self.ziel, funktion],
                              capture_output=True, text=True, timeout=30, check=False)

    def dm(self, dienst):
        os.symlink(f"/usr/lib/systemd/system/{dienst}", self.pfad("etc", "systemd", "system", "display-manager.service"))

    def test_gdm_wird_deaktiviert(self):
        self.dm("gdm3.service")
        r = self.lauf("anmeldung_vorbereiten")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("chroot systemctl disable --quiet gdm3.service", r.stdout)
        self.assertFalse(os.path.lexists(self.pfad("etc", "systemd", "system", "display-manager.service")))

    def test_greetd_und_ohne_anmeldedienst_unveraendert(self):
        r = self.lauf("anmeldung_vorbereiten")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("chroot", r.stdout)
        self.dm("greetd.service")
        r = self.lauf("anmeldung_vorbereiten")
        self.assertNotIn("chroot", r.stdout)
        self.assertTrue(os.path.islink(self.pfad("etc", "systemd", "system", "display-manager.service")))

    def test_seltsamer_verweis_abgelehnt(self):
        os.symlink("/usr/lib/systemd/system/x y.service",
                   self.pfad("etc", "systemd", "system", "display-manager.service"))
        r = self.lauf("anmeldung_vorbereiten")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("chroot", r.stdout)

    def marke(self):
        with open(self.pfad("var", "lib", "zenos", "netzwerk-erststart"), "w", encoding="utf-8") as f:
            f.write("# Test\n")

    def test_networkmanager_schon_da(self):
        with open(self.pfad("etc", "netplan", "01-network-manager-all.yaml"), "w", encoding="utf-8") as f:
            f.write("# Let NetworkManager manage all devices on this system\nnetwork:\n  version: 2\n"
                    "  renderer: NetworkManager\n")
        self.marke()
        r = self.lauf("netz_abschliessen")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(self.pfad("var", "lib", "zenos", "netzwerk-erststart")))

    def test_networkd_behaelt_die_umstellung(self):
        with open(self.pfad("etc", "netplan", "50-cloud-init.yaml"), "w", encoding="utf-8") as f:
            f.write("network:\n  version: 2\n  ethernets:\n    enp1s0:\n      dhcp4: true\n")
        self.marke()
        r = self.lauf("netz_abschliessen")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.exists(self.pfad("var", "lib", "zenos", "netzwerk-erststart")))

    def test_saubere_umgebung(self):
        # Neustart mit leerer Umgebung nur beim Ausführen, nicht beim Laden (Tests)
        text = lesen(EINRICHTEN)
        self.assertIn("exec /usr/bin/env -i", text)
        self.assertIn('"${BASH_SOURCE[0]}" == "$0" && "${ZENOS_EINRICHTEN_SAUBER:-}" != 1', text)


class NurPruefen(unittest.TestCase):
    """x86-stick.sh --nur-pruefen in einem Wegwerf-Repo (git und ssh-keygen, kein Netz)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = os.path.join(self.tmp.name, "repo")
        os.makedirs(os.path.join(self.repo, "image", "x86"))
        for pfad in (YAML, EINRICHTEN, README):
            shutil.copy(pfad, os.path.join(self.repo, "image", "x86", os.path.basename(pfad)))
        shutil.copytree(INSTALLER, os.path.join(self.repo, "image", "x86", "installer"))
        os.makedirs(os.path.join(self.repo, "shell", "theme"))
        shutil.copy(TOKENS, os.path.join(self.repo, "shell", "theme", "tokens.json"))
        shutil.copytree(ZEICHEN, os.path.join(self.repo, "assets", "zeichen"))
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

    def test_anpassung_des_installers(self):
        """--nur-anpassung legt die Schicht für den Installer an: Farben aus tokens.json, Bilder, Folien."""
        ziel = os.path.join(self.tmp.name, "schicht")
        r = subprocess.run([STICK, "--quelle", self.repo, "--testbau-ohne-signatur", "--nur-anpassung", ziel],
                           capture_output=True, text=True, timeout=60, check=False, env=self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        basis = os.path.join(ziel, "usr", "share", "desktop-provision")
        weiss = lesen(os.path.join(basis, "whitelabel.yaml"))
        self.assertNotIn("@", weiss.split("\n# ")[-1].split("app-name")[1], "kein Platzhalter übrig")
        tokens = json.loads(lesen(TOKENS))["farben"]
        akzent = tokens["akzente"][tokens["standardAkzent"]]
        self.assertIn('accent-color: "%s"' % akzent["hell"], weiss)
        self.assertIn('accent-color: "%s"' % akzent["dunkel"], weiss)
        if yaml is not None:
            daten = yaml.safe_load(weiss)
            self.assertEqual(daten["app-name"], "zenOS installieren")
            for seite in ("try-or-install", "refresh", "ubuntu-pro-onboarding", "source-selection"):
                self.assertIs(daten["pages"][seite]["visible"], False, seite)
            for seite, angaben in daten["pages"].items():
                for name in (angaben.get("image"), angaben.get("image-dark")):
                    if name:
                        self.assertTrue(os.path.isfile(os.path.join(basis, "images", name)), (seite, name))
        folien = sorted(os.listdir(os.path.join(basis, "slides")))
        self.assertEqual(folien, ["1", "2", "3", "4"])
        for nr in folien:
            ordner = os.path.join(basis, "slides", nr)
            for name in ("slide_en_US.html", "slide_de_CH.html", "slide_de_DE.html", "zenos-zeichen.svg"):
                self.assertTrue(os.path.isfile(os.path.join(ordner, name)), (nr, name))
            html = lesen(os.path.join(ordner, "slide_de_CH.html"))
            self.assertNotIn("@", html)
            self.assertIn(tokens["dunkel"]["grund"], html)
        look = os.path.join(basis, "zenos-live-look")
        self.assertTrue(os.access(look, os.X_OK))
        self.assertIn("primary-color '%s'" % tokens["dunkel"]["grund"], lesen(look))
        self.assertIn("Exec=/usr/share/desktop-provision/zenos-live-look",
                      lesen(os.path.join(ziel, "etc", "xdg", "autostart", "zenos-live-look.desktop")))

    def test_falscher_aufruf(self):
        for argumente in (("--ref",), ("--ubuntu", "26"), ("--unbekannt",)):
            self.assertEqual(self.lauf(*argumente).returncode, 2, argumente)


if __name__ == "__main__":
    unittest.main()
