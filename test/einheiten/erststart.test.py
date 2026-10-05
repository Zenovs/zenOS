#!/usr/bin/env python3
"""Einheitentests für den ersten Start des Images (image/erststart/) und die Quellen-Werkzeuge (image/quellen.sh).

Geprüft wird ohne YAML-Bibliothek (die fehlt auf dem Mac), über die Zeilen der Dateien: user-data und
90-zenos-benutzer.cfg passen zusammen (derselbe Benutzer, sonst setzte chpasswd das Passwort für einen Benutzer,
den es nicht gibt), sudo ohne Passwort ist abgeschaltet, SSH nimmt keine Passwörter an, das Passwort ist
abgelaufen, keine Spur von Ubuntus Standardbenutzer. Dazu, dass image/bauen.sh genau diese Dateien einsetzt und
config.txt den Abschnitt [cm5] bekommt, und die Ausgaben von image/quellen.sh ohne Netz (Hilfe, falsche Aufrufe).
Ohne Root, ohne Netz.

  python3 test/einheiten/erststart.test.py
"""

import os
import re
import subprocess
import tempfile
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ERSTSTART = os.path.join(REPO, "image", "erststart")
BAUEN = os.path.join(REPO, "image", "bauen.sh")
QUELLEN = os.path.join(REPO, "image", "quellen.sh")


def lesen(name):
    with open(os.path.join(ERSTSTART, name), encoding="utf-8") as f:
        return f.read()


def ohne_kommentare(text):
    return [z for z in text.splitlines() if z.strip() and not z.lstrip().startswith("#")]


class UserData(unittest.TestCase):
    def setUp(self):
        self.text = lesen("user-data")
        self.zeilen = ohne_kommentare(self.text)

    def test_cloud_config(self):
        self.assertEqual(self.text.splitlines()[0], "#cloud-config")

    def test_keine_tabulatoren(self):
        self.assertNotIn("\t", self.text)

    def test_passwort_abgelaufen(self):
        self.assertIn("chpasswd:", self.zeilen)
        self.assertIn("  expire: true", self.zeilen)

    def test_benutzer_user(self):
        self.assertIn("  - name: user", self.zeilen)
        self.assertIn("    password: user", self.zeilen)
        self.assertIn("    type: text", self.zeilen)

    def test_ssh_ohne_passwort(self):
        self.assertIn("ssh_pwauth: false", self.zeilen)

    def test_rechnername(self):
        self.assertIn("hostname: zenos", self.zeilen)

    def test_keine_eigene_benutzerliste(self):
        # Mit «users:» auf oberster Ebene legte cloud-init den Standardbenutzer nicht an
        self.assertFalse([z for z in self.zeilen if z.startswith("users:")])

    def test_kein_ubuntu_benutzer(self):
        self.assertNotIn("ubuntu", "\n".join(self.zeilen).lower())


class Benutzer(unittest.TestCase):
    def setUp(self):
        self.zeilen = ohne_kommentare(lesen("90-zenos-benutzer.cfg"))

    def test_default_user(self):
        self.assertEqual(self.zeilen, ["system_info:", "  default_user:", "    name: user", "    gecos: Default User",
                                       "    sudo: null"])

    def test_gleicher_benutzer_wie_user_data(self):
        name = re.search(r"^    name: (\S+)$", "\n".join(self.zeilen), re.M).group(1)
        self.assertIn(f"  - name: {name}", ohne_kommentare(lesen("user-data")))

    def test_kein_nopasswd(self):
        self.assertNotIn("NOPASSWD", "\n".join(self.zeilen))


class Readme(unittest.TestCase):
    def test_basis_und_kein_ubuntu_name(self):
        text = lesen("README")
        self.assertIn("zenOS basiert auf Ubuntu", text)
        self.assertNotIn("Ubuntu Server for Raspberry Pi", text)
        self.assertNotIn("offiziell", text.lower())
        self.assertTrue(all(len(z) <= 80 for z in text.splitlines()))


class Bauen(unittest.TestCase):
    def setUp(self):
        with open(BAUEN, encoding="utf-8") as f:
            self.text = f.read()

    def test_schritt_im_ablauf(self):
        ablauf = self.text[self.text.index('step "Kennung und Sicherheitsquelle prüfen"'):]
        self.assertLess(ablauf.index("check_identity"), ablauf.index("prepare_first_boot"))
        self.assertLess(ablauf.index("prepare_first_boot"), ablauf.index("write_package_list"))
        self.assertLess(ablauf.index("write_package_list"), ablauf.index("clean_image"))

    def test_dateien_eingesetzt(self):
        funktion = self.text[self.text.index("prepare_first_boot() {"):self.text.index("write_package_list() {")]
        self.assertIn('"$code/user-data" "$boot/user-data"', funktion)
        self.assertIn('"$code/README" "$boot/README"', funktion)
        self.assertIn('"$r/etc/cloud/cloud.cfg.d/90-zenos-benutzer.cfg"', funktion)
        self.assertIn("printf 'zenos\\n' > \"$r/etc/hostname\"", funktion)
        self.assertIn("'dtoverlay=dwc2,dr_mode=host'", funktion)
        self.assertIn("\\n[cm5]\\n", funktion)
        self.assertIn("\\n\\n[all]\\n", funktion)

    def test_paketliste_in_prüfsummen(self):
        self.assertIn('sha256sum -- "${files[@]}" > SHA256SUMS', self.text)
        self.assertIn('files+=("$list")', self.text)


class Quellen(unittest.TestCase):
    def lauf(self, *argumente):
        return subprocess.run(["bash", QUELLEN, *argumente], capture_output=True, text=True, timeout=30,
                              env=dict(os.environ, LC_ALL="C.UTF-8"))

    def test_ausfuehrbar(self):
        self.assertTrue(os.access(QUELLEN, os.X_OK))

    def test_hilfe(self):
        aus = self.lauf("--hilfe")
        self.assertEqual(aus.returncode, 0)
        self.assertIn("quellen.sh PAKETLISTE ZIELORDNER", aus.stdout)

    def test_ohne_argumente(self):
        self.assertEqual(self.lauf().returncode, 2)

    def test_leere_liste(self):
        with tempfile.TemporaryDirectory() as tmp:
            liste = os.path.join(tmp, "zenos-1.0.0-pi5-arm64.pakete.txt")
            open(liste, "w").close()
            aus = self.lauf(liste, os.path.join(tmp, "aus"))
            self.assertEqual(aus.returncode, 1)
            self.assertIn("leer", aus.stderr)

    def test_teilgroesse(self):
        with tempfile.TemporaryDirectory() as tmp:
            liste = os.path.join(tmp, "zenos-1.0.0-pi5-arm64.pakete.txt")
            with open(liste, "w") as f:
                f.write("bash\t5.2\tbash\t5.2\n")
            for wert in ("5", "2048", "viel"):
                aus = self.lauf(liste, os.path.join(tmp, "aus"), "--teilgroesse", wert)
                self.assertEqual(aus.returncode, 1, wert)
                self.assertIn("--teilgroesse", aus.stderr)

    def test_kein_sh_c(self):
        with open(QUELLEN, encoding="utf-8") as f:
            self.assertNotRegex(f.read(), r"\bsh -c\b")


if __name__ == "__main__":
    unittest.main()
