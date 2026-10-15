#!/usr/bin/env python3
"""Einheitentests für das Geräteprofil «Öffentlicher Bildschirm»: scripts/bin/zenos-anzeige, config/schema/anzeige.schema.json,
die Regeln der Anzeige in scripts/lib/firewall.sh und die Dateien der Anzeige-Sitzung.

Ohne root und ohne das System anzufassen: einrichten und entfernen laufen mit --wurzel in einer Testwurzel (useradd,
systemctl, loginctl und zenos-firewall stehen dann nur in der Ausgabe). Die polkit-Regel wertet node aus, wenn es da ist.

  python3 test/einheiten/anzeige.test.py
"""

import datetime
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-anzeige")
SCHEMA = os.path.join(WURZEL, "config", "schema", "anzeige.schema.json")
BEISPIEL = os.path.join(WURZEL, "config", "beispiele", "anzeige.beispiel.json")
GREETD = os.path.join(WURZEL, "system", "greetd", "config.toml")
FIREWALL = os.path.join(WURZEL, "scripts", "lib", "firewall.sh")
_loader = importlib.machinery.SourceFileLoader("zenos_anzeige", PROGRAMM)
A = importlib.util.module_from_spec(importlib.util.spec_from_loader("zenos_anzeige", _loader))
_loader.exec_module(A)

try:
    import jsonschema
except ImportError:
    jsonschema = None


def lesen(pfad):
    with open(pfad, encoding="utf-8") as f:
        return f.read()


def schreiben(pfad, inhalt, modus=0o644):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(inhalt)
    os.chmod(pfad, modus)


GUELTIG = [
    {"version": 1},
    {"version": 1, "konto": "anzeige", "app": {"einheit": "slatedesk.service"}, "ports": [7380]},
    {"version": 1, "app": {"befehl": ["/usr/bin/programm", "--vollbild", "a b", "$(nie)"]}, "ports": []},
    {"version": 1, "konto": "kiosk_1", "bildschirmzeiten": [{"tage": ["mo", "fr"], "an": "07:00", "aus": "19:30"},
                                                            {"tage": ["sa"], "an": "22:00", "aus": "02:00"}]},
]
UNGUELTIG = [
    [],
    {"konto": "anzeige"},
    {"version": 2},
    {"version": 1, "fremd": True},
    {"version": 1, "konto": "root"},
    {"version": 1, "konto": "Anzeige"},
    {"version": 1, "konto": "a b"},
    {"version": 1, "app": {}},
    {"version": 1, "app": {"einheit": "x.service", "befehl": ["/bin/true"]}},
    {"version": 1, "app": {"einheit": "x.timer"}},
    {"version": 1, "app": {"befehl": []}},
    {"version": 1, "app": {"befehl": ["programm"]}},
    {"version": 1, "app": {"befehl": "/usr/bin/programm --vollbild"}},
    {"version": 1, "app": {"befehl": ["/usr/bin/programm", 3]}},
    {"version": 1, "ports": [22]},
    {"version": 1, "ports": [0]},
    {"version": 1, "ports": [70000]},
    {"version": 1, "ports": ["7380"]},
    {"version": 1, "ports": [8080, 8080]},
    {"version": 1, "bildschirmzeiten": [{"tage": ["montag"], "an": "07:00", "aus": "19:00"}]},
    {"version": 1, "bildschirmzeiten": [{"tage": ["mo"], "an": "7:00", "aus": "19:00"}]},
    {"version": 1, "bildschirmzeiten": [{"tage": ["mo"], "an": "24:00", "aus": "19:00"}]},
    {"version": 1, "bildschirmzeiten": [{"tage": [], "an": "07:00", "aus": "19:00"}]},
    {"version": 1, "bildschirmzeiten": [{"tage": ["mo"], "an": "07:00"}]},
]


class Konfiguration(unittest.TestCase):
    def test_beispiel_neutral_und_gueltig(self):
        daten = json.loads(lesen(BEISPIEL))
        A.check_config(daten)
        self.assertNotIn("slatedesk", lesen(BEISPIEL).lower())

    def test_gueltig(self):
        for daten in GUELTIG:
            with self.subTest(daten=daten):
                aus = A.check_config(daten)
                self.assertEqual(aus["konto"], daten.get("konto", "anzeige"))

    def test_ungueltig(self):
        for daten in UNGUELTIG:
            with self.subTest(daten=daten):
                with self.assertRaises(A.Abort):
                    A.check_config(daten)

    @unittest.skipIf(jsonschema is None, "python3-jsonschema fehlt")
    def test_schema_gleich_streng(self):
        schema = json.loads(lesen(SCHEMA))
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.validate(json.loads(lesen(BEISPIEL)), schema)
        for daten in GUELTIG:
            with self.subTest(gueltig=daten):
                jsonschema.validate(daten, schema)
        for daten in UNGUELTIG:
            if daten == {"version": 1, "bildschirmzeiten": [{"tage": ["mo"], "an": "07:00", "aus": "07:00"}]}:
                continue
            with self.subTest(ungueltig=daten):
                with self.assertRaises(jsonschema.ValidationError):
                    jsonschema.validate(daten, schema)

    def test_geordnet(self):
        aus = A.check_config({"version": 1, "ports": [9000, 8080],
                              "bildschirmzeiten": [{"tage": ["fr", "mo"], "an": "07:00", "aus": "19:00"}]})
        self.assertEqual(aus["ports"], [8080, 9000])
        self.assertEqual(aus["bildschirmzeiten"][0]["tage"], ["mo", "fr"])


class Bildschirmzeiten(unittest.TestCase):
    def test_tag(self):
        zeiten = [{"tage": ["mo", "di", "mi", "do", "fr"], "an": "07:00", "aus": "19:00"}]
        mo = datetime.datetime(2026, 10, 12, 7, 0)  # Montag
        self.assertTrue(A.screen_on(zeiten, mo))
        self.assertFalse(A.screen_on(zeiten, mo.replace(hour=6, minute=59)))
        self.assertFalse(A.screen_on(zeiten, mo.replace(hour=19, minute=0)))
        self.assertFalse(A.screen_on(zeiten, datetime.datetime(2026, 10, 18, 12, 0)))  # Sonntag

    def test_ueber_mitternacht(self):
        zeiten = [{"tage": ["sa"], "an": "22:00", "aus": "02:00"}]
        self.assertTrue(A.screen_on(zeiten, datetime.datetime(2026, 10, 17, 23, 0)))  # Samstag
        self.assertTrue(A.screen_on(zeiten, datetime.datetime(2026, 10, 18, 1, 59)))  # Sonntag früh
        self.assertFalse(A.screen_on(zeiten, datetime.datetime(2026, 10, 18, 2, 0)))
        self.assertFalse(A.screen_on(zeiten, datetime.datetime(2026, 10, 17, 1, 0)))  # Samstag früh: Freitag fehlt

    def test_ohne_zeiten_immer_an(self):
        self.assertTrue(A.screen_on([], datetime.datetime(2026, 10, 18, 3, 0)))


class Testwurzel(unittest.TestCase):
    """einrichten → zweites einrichten → entfernen in einer Testwurzel."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.w = self.tmp.name
        self.p = lambda rel: os.path.join(self.w, rel.lstrip("/"))
        schreiben(self.p("/etc/passwd"), "root:x:0:0:root:/root:/bin/bash\nmensch:x:1000:1000::/home/mensch:/bin/bash\n")
        schreiben(self.p("/etc/group"), "root:x:0:\nsudo:x:27:mensch\n")
        schreiben(self.p("/etc/shadow"), "root:*:1::::::\nmensch:$6$x:1::::::\n", 0o640)
        os.makedirs(self.p("/etc/greetd"))
        shutil.copy(GREETD, self.p("/etc/greetd/config.toml"))
        self.konfig({"version": 1, "konto": "anzeige", "app": {"einheit": "beispiel-anzeige.service"},
                     "ports": [8080]})

    def konfig(self, daten):
        schreiben(self.p("/etc/zenos/anzeige.json"), json.dumps(daten))

    def lauf(self, *argumente):
        return subprocess.run([sys.executable, PROGRAMM, "--wurzel", self.w, "--code", WURZEL, *argumente],
                              capture_output=True, text=True, timeout=60, check=False,
                              env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))

    def test_ohne_profil(self):
        self.assertEqual(self.lauf("aktiv").returncode, 3)
        self.assertEqual(self.lauf("ports").returncode, 3)
        r = self.lauf("greetd-konfig")
        self.assertEqual(r.stdout, lesen(GREETD), "ohne Profil genau die Datei aus dem Repo")
        self.assertNotRegex(r.stdout, r"(?m)^\[initial_session\]")

    def test_einrichten_und_entfernen(self):
        r = self.lauf("einrichten")
        self.assertEqual(r.returncode, 1, "ohne --ja nichts")
        self.assertFalse(os.path.exists(self.p("/var/lib/zenos/anzeige.json")))

        r = self.lauf("einrichten", "--ja")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("useradd --system --create-home --home-dir /home/anzeige --shell /usr/sbin/nologin", r.stdout)
        self.assertRegex(r.stdout, r"--skel \S*zenos-anzeige-skel\.\S+ anzeige", "ohne Dateien aus /etc/skel")
        self.assertIn("usermod --lock anzeige", r.stdout)
        self.assertIn("scripts/bin/zenos-firewall anzeige", r.stdout)
        zustand = json.loads(lesen(self.p("/var/lib/zenos/anzeige.json")))
        self.assertEqual((zustand["aktiv"], zustand["konto"], zustand["angelegt"]), (True, "anzeige", True))
        greetd = lesen(self.p("/etc/greetd/config.toml"))
        self.assertTrue(greetd.startswith(lesen(GREETD)), "der Login von zenOS bleibt [default_session]")
        self.assertIn('[initial_session]\ncommand = "/opt/zenos/scripts/bin/zenos-anzeige-sitzung"\n'
                      'user = "anzeige"\n', greetd)
        self.assertEqual(len(re.findall(r"(?m)^\[initial_session\]", greetd)), 1)
        self.assertIn('subject.user !== "anzeige"', lesen(self.p("/etc/polkit-1/rules.d/50-zenos-anzeige.rules")))
        for name in A.EINHEITEN:
            self.assertEqual(lesen(self.p("/etc/systemd/user/" + name)),
                             lesen(os.path.join(WURZEL, "system", "systemd", "user", name)))
        self.assertIn("Wants=beispiel-anzeige.service",
                      lesen(self.p("/etc/systemd/user/zenos-anzeige.target.d/zenos-app.conf")))
        self.assertEqual(self.lauf("aktiv").returncode, 0)
        self.assertEqual(self.lauf("ports").stdout, "8080\n")
        self.assertEqual(self.lauf("konto").stdout, "anzeige\n")
        self.assertIn("Anzeige-Konto:", lesen(self.p("/var/log/zenos/anzeige.log")) + self.lauf("status").stdout)

        # Zweiter Lauf und anwenden ändern keine Datei
        r = self.lauf("anwenden", "--melden")
        self.assertEqual((r.returncode, r.stdout), (0, ""), r.stderr)

        # App wechselt zum Befehl: das Drop-in geht
        self.konfig({"version": 1, "konto": "anzeige", "app": {"befehl": ["/usr/bin/programm"]}})
        r = self.lauf("anwenden", "--melden")
        self.assertIn("zenos-app.conf entfernt", r.stdout)
        self.assertEqual(self.lauf("hat-befehl").returncode, 0)
        self.assertEqual(self.lauf("hat-bildschirmzeiten").returncode, 1)

        # Das Konto gibt es inzwischen (useradd lief im Test nicht): entfernen löscht es, das Home bleibt
        with open(self.p("/etc/passwd"), "a", encoding="utf-8") as f:
            f.write("anzeige:x:990:990:zenOS Anzeige:/home/anzeige:/usr/sbin/nologin\n")
        r = self.lauf("entfernen", "--ja")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("loginctl disable-linger anzeige", r.stdout)
        self.assertIn("loginctl terminate-user anzeige", r.stdout)
        self.assertIn("userdel anzeige", r.stdout)
        self.assertNotIn("--remove", r.stdout)
        self.assertEqual(lesen(self.p("/etc/greetd/config.toml")), lesen(GREETD), "genau wie vorher")
        for rest in ("/var/lib/zenos/anzeige.json", "/etc/polkit-1/rules.d/50-zenos-anzeige.rules",
                     "/etc/systemd/user/zenos-anzeige.target", "/etc/systemd/user/zenos-anzeige.target.d"):
            self.assertFalse(os.path.exists(self.p(rest)), rest)
        self.assertEqual(self.lauf("aktiv").returncode, 3)

    def test_entfernen_mit_daten(self):
        self.lauf("einrichten", "--ja")
        with open(self.p("/etc/passwd"), "a", encoding="utf-8") as f:
            f.write("anzeige:x:990:990:zenOS Anzeige:/home/anzeige:/usr/sbin/nologin\n")
        r = self.lauf("entfernen", "--ja", "--daten-loeschen")
        self.assertIn("userdel --remove anzeige", r.stdout)

    def test_persoenliches_konto_nie(self):
        self.konfig({"version": 1, "konto": "mensch"})
        r = self.lauf("einrichten", "--ja")
        self.assertEqual(r.returncode, 1)
        self.assertIn("kein Systemkonto", r.stderr)
        self.assertIn("Login-Shell /bin/bash", r.stderr)
        self.assertIn("es hat ein Passwort", r.stderr)
        self.assertIn("Gruppe sudo", r.stderr)
        self.assertFalse(os.path.exists(self.p("/var/lib/zenos/anzeige.json")))
        self.assertEqual(lesen(self.p("/etc/greetd/config.toml")), lesen(GREETD))

    def test_vorhandenes_systemkonto_mit_schluessel(self):
        with open(self.p("/etc/passwd"), "a", encoding="utf-8") as f:
            f.write("anzeige:x:990:990::/home/anzeige:/usr/sbin/nologin\n")
        with open(self.p("/etc/shadow"), "a", encoding="utf-8") as f:
            f.write("anzeige:!:1::::::\n")
        schreiben(self.p("/home/anzeige/.ssh/authorized_keys"), "ssh-ed25519 AAAA test\n")
        r = self.lauf("einrichten", "--ja")
        self.assertEqual(r.returncode, 1)
        self.assertIn("SSH-Schlüssel", r.stderr)
        os.unlink(self.p("/home/anzeige/.ssh/authorized_keys"))
        r = self.lauf("einrichten", "--ja")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("useradd", r.stdout)
        self.assertFalse(json.loads(lesen(self.p("/var/lib/zenos/anzeige.json")))["angelegt"])
        r = self.lauf("entfernen", "--ja")
        self.assertNotIn("userdel", r.stdout, "ein Konto, das es vorher gab, bleibt")

    def test_befehl_als_argumentliste(self):
        befehl = ["/usr/bin/programm", "a b", "$(nie)", ";", "|", "'"]
        self.konfig({"version": 1, "app": {"befehl": befehl}})
        self.lauf("einrichten", "--ja")
        r = self.lauf("app")
        self.assertEqual(json.loads(r.stdout), befehl)

    def test_hinweis_zur_app(self):
        """Fehlt die App, sagt das Ersatzbild, was fehlt (statt endlos «Anzeige startet …»); der Plan warnt, ohne
        abzubrechen. Am EliteDesk stand nach dem Einrichten mit der Vorlage nur «Anzeige startet …»."""
        self.assertEqual(self.lauf("hinweis").stdout, "App beispiel-anzeige.service ist nicht installiert\n",
                         "auch vor dem Einrichten, aus der Konfiguration")
        r = self.lauf("plan", "einrichten")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Hinweis: App beispiel-anzeige.service ist nicht installiert", r.stdout)
        self.assertEqual(self.lauf("einrichten", "--ja").returncode, 0)
        self.assertIn("Hinweis: App beispiel-anzeige.service ist nicht installiert", self.lauf("status").stdout)
        # Das Setup der App legt die Einheit ins Home des Kontos: der Hinweis verschwindet
        with open(self.p("/etc/passwd"), "a", encoding="utf-8") as f:
            f.write("anzeige:x:990:990:zenOS Anzeige:/home/anzeige:/usr/sbin/nologin\n")
        schreiben(self.p("/home/anzeige/.config/systemd/user/beispiel-anzeige.service"), "[Service]\n")
        self.assertEqual(self.lauf("hinweis").stdout, A.STARTET + "\n")
        self.assertNotIn("Hinweis:", self.lauf("plan", "einrichten").stdout)
        self.assertNotIn("Hinweis:", self.lauf("status").stdout)
        # ohne App, und ein Befehl, den es nicht gibt
        self.konfig({"version": 1})
        self.assertEqual(self.lauf("hinweis").stdout, "Keine App eingerichtet\n")
        self.konfig({"version": 1, "app": {"befehl": ["/usr/bin/gibt-es-nicht", "--vollbild"]}})
        self.assertEqual(self.lauf("hinweis").stdout, "App /usr/bin/gibt-es-nicht fehlt\n")
        # kaputte Konfiguration: nie ein Fehler im Ersatzbild
        schreiben(self.p("/etc/zenos/anzeige.json"), "{ kaputt")
        r = self.lauf("hinweis")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "Keine App eingerichtet\n")

    def test_sitzung_nur_am_bildschirm(self):
        """Am EliteDesk meldete status «läuft», obwohl nur der Diensteverwalter des Kontos lief (Klasse
        manager-early, ohne Sitz) und Zeno selbst am Bildschirm angemeldet war."""
        eliteDesk = [{"session": "1", "uid": 997, "user": "anzeige", "seat": None, "class": "manager-early"},
                     {"session": "5", "uid": 1000, "user": "mensch", "seat": "seat0", "class": "user"}]
        self.assertFalse(A.display_session_running(eliteDesk, "anzeige"))
        anzeige = eliteDesk + [{"session": "9", "uid": 997, "user": "anzeige", "seat": "seat0", "class": "user-early"}]
        self.assertTrue(A.display_session_running(anzeige, "anzeige"))
        self.assertFalse(A.display_session_running(anzeige, "kiosk"))

    def test_einheit_im_system_und_als_vorlage(self):
        p = A.Paths(self.w, WURZEL)
        self.assertIs(A.unit_installed(p, "anzeige", "kiosk.service"), False)
        schreiben(self.p("/usr/lib/systemd/user/kiosk.service"), "[Service]\n")
        self.assertIs(A.unit_installed(p, "anzeige", "kiosk.service"), True)
        self.assertIs(A.unit_installed(p, "anzeige", "tafel@flur.service"), False)
        schreiben(self.p("/etc/systemd/user/tafel@.service"), "[Service]\n")
        self.assertIs(A.unit_installed(p, "anzeige", "tafel@flur.service"), True)

    def test_kaputte_konfiguration_haelt_die_anzeige(self):
        self.lauf("einrichten", "--ja")
        schreiben(self.p("/etc/zenos/anzeige.json"), "{ kaputt")
        self.assertEqual(self.lauf("aktiv").returncode, 0)
        self.assertEqual(self.lauf("ports").stdout, "", "ohne gültige Konfiguration keine Ports")
        self.assertEqual(self.lauf("konto").stdout, "anzeige\n")
        self.assertEqual(self.lauf("konfig").returncode, 1)


class Polkit(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "node fehlt")
    def test_regel(self):
        regel = A.polkit_rule("anzeige")
        prog = """
const regeln = [];
const polkit = { Result: { YES: "yes", NO: "no", NOT_HANDLED: null }, addRule: f => regeln.push(f) };
%s
const fall = (aktion, benutzer) => regeln[0]({ id: aktion }, { user: benutzer });
console.log(JSON.stringify([
  fall("org.freedesktop.login1.power-off", "anzeige"),
  fall("org.freedesktop.login1.reboot", "anzeige"),
  fall("org.freedesktop.login1.suspend", "anzeige"),
  fall("org.freedesktop.NetworkManager.settings.modify.system", "anzeige"),
  fall("org.freedesktop.login1.inhibit-block-sleep", "anzeige"),
  fall("org.freedesktop.login1.inhibit-block-idle", "anzeige"),
  fall("org.freedesktop.login1.power-off", "mensch"),
]));
""" % regel
        r = subprocess.run(["node", "-e", prog], capture_output=True, text=True, timeout=30, check=True)
        self.assertEqual(json.loads(r.stdout), ["no", "no", "no", "no", "yes", "yes", None])


class Firewall(unittest.TestCase):
    """_firewall_auswerten anzeige: nur Regeln mit dem Kommentar zenos-anzeige."""

    def auswerten(self, tupel):
        skript = 'source "$1"; _firewall_auswerten anzeige'
        r = subprocess.run(["bash", "-c", skript, "test", FIREWALL], input=tupel, capture_output=True, text=True,
                           timeout=30, check=True)
        return r.stdout.splitlines()

    def test_eigene_regeln(self):
        k = "zenos-anzeige".encode().hex()
        fremd = "SlateDesk Fernsteuerung".encode().hex()
        tupel = "\n".join([
            "### tuple ### allow tcp 8080 0.0.0.0/0 any 192.168.0.0/16 in comment=" + k,
            "### tuple ### allow tcp 8080 0.0.0.0/0 any 10.0.0.0/8 in comment=" + k,
            "### tuple ### allow tcp 7380 0.0.0.0/0 any 192.168.19.0/24 in comment=" + fremd,
            "### tuple ### limit tcp 22 0.0.0.0/0 any 192.168.0.0/16 in",
            "### tuple ### deny tcp 9000 0.0.0.0/0 any 10.0.0.0/8 in comment=" + k,
        ]) + "\n"
        self.assertEqual(self.auswerten(tupel), ["8080 192.168.0.0/16", "8080 10.0.0.0/8"])


class Dateien(unittest.TestCase):
    def test_labwc_nur_der_ausweg(self):
        rc = lesen(os.path.join(WURZEL, "system", "anzeige", "labwc", "rc.xml"))
        self.assertEqual(rc.count("<keybind "), 1)
        self.assertIn('<keybind key="C-A-S-BackSpace">', rc)
        self.assertIn('<action name="Exit" />', rc)
        self.assertIn('serverDecoration="no"', rc)

    def test_keine_sperre_in_der_anzeige(self):
        ziel = "".join(z for z in lesen(os.path.join(WURZEL, "system", "systemd", "user", "zenos-anzeige.target"))
                       .splitlines(True) if not z.startswith("#"))
        self.assertIn("BindsTo=graphical-session.target", ziel)
        self.assertNotIn("zenos-idle", ziel)
        self.assertNotIn("zenos-shell", ziel)
        wach = lesen(os.path.join(WURZEL, "system", "systemd", "user", "zenos-anzeige-wach.service"))
        self.assertIn("--what=idle:sleep:handle-lid-switch --mode=block", wach)

    def test_sitzung_ohne_benutzerteile(self):
        sitzung = lesen(os.path.join(WURZEL, "scripts", "bin", "zenos-anzeige-sitzung"))
        self.assertNotIn("install.sh", sitzung.split("set -uo pipefail", 1)[1])
        self.assertIn('--config-dir "$code/system/anzeige/labwc"', sitzung)

    def test_ersatzbild_fragt_den_hinweis_ohne_shell(self):
        qml = lesen(os.path.join(WURZEL, "shell", "anzeige.qml"))
        self.assertIn('command: ["/usr/bin/python3", "-I", Pfade.bin + "/zenos-anzeige", "hinweis"]', qml)
        self.assertIn("text: root.hinweis", qml)
        self.assertNotIn('"-c"', qml)

    def test_kein_autologin_im_repo(self):
        self.assertNotRegex(lesen(GREETD), r"(?m)^\[initial_session\]")


if __name__ == "__main__":
    unittest.main()
