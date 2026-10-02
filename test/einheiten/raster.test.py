#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-labwc (rc.xml, Tastenkürzel, Scroll-Tempo, laufzeit.json).

Läuft mit einem leeren Test-HOME, ohne labwc und ohne Bildschirm (--kein-neuladen, nie ein Signal an
ein laufendes labwc): python3 test/einheiten/raster.test.py. Das Zusammenführen von laufzeit.json braucht
python3-jsonschema (zenos-konfig).
"""

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

# realpath wie zenos-labwc, damit die Pfade in rc.xml vergleichbar sind
WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
LABWC = os.path.join(WURZEL, "scripts", "bin", "zenos-labwc")
VORLAGEN_RASTER = os.path.join(WURZEL, "config", "vorlagen", "raster")
MENU = os.path.join(WURZEL, "system", "labwc", "menu.xml")
SCHEMA_EINSTELLUNGEN = os.path.join(WURZEL, "config", "schema", "einstellungen.schema.json")
QML_EINSTELLUNGEN = os.path.join(WURZEL, "shell", "dienste", "Einstellungen.qml")
QML_SEITE_ALLGEMEIN = os.path.join(WURZEL, "shell", "einstellungen", "SeiteAllgemein.qml")
SHELLS = {"sh", "bash", "dash", "zsh", "fish", "ksh", "mksh", "busybox"}

# Bauplan 8 (Super+1 … Super+4 kommen aus dem Raster)
TASTEN = {
    "W-space", "W-l", "W-m", "W-z", "W-Left", "W-Right", "W-Return", "W-S-Left", "W-S-Right", "W-q",
    "A-Tab", "A-S-Tab", "C-A-t", "W-S-s", "Print", "W-S-c", "W-comma",
    "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute", "XF86AudioMicMute",
}
# Für kitty frei (Bauplan 8, M10)
FREI = {"W-Up", "W-Down", "W-t", "W-d", "W-c", "W-v", "W-w", "W-k", "W-plus", "W-minus", "W-0"}


def jsonschema_da():
    try:
        import jsonschema  # noqa: F401, PLC0415
    except ImportError:
        return False
    return True


def ipc_ziele():
    """{ziel: {funktion: anzahl_parameter}} aus allen IpcHandler der Oberfläche (grob, reicht als Abgleich)."""
    ziele = {}
    for ordner, _, dateien in os.walk(os.path.join(WURZEL, "shell")):
        for name in dateien:
            if not name.endswith(".qml"):
                continue
            with open(os.path.join(ordner, name), encoding="utf-8") as f:
                teile = f.read().split("IpcHandler {")[1:]
            for teil in teile:
                ziel = re.search(r'target:\s*"([^"]+)"', teil)
                if not ziel:
                    continue
                funktionen = ziele.setdefault(ziel.group(1), {})
                for m in re.finditer(r"function\s+(\w+)\s*\(([^)]*)\)", teil):
                    funktionen.setdefault(m.group(1), len([p for p in m.group(2).split(",") if p.strip()]))
    return ziele


def execute_befehle(wurzel):
    """(Auslöser, argv) aller Execute-Aktionen, zerlegt wie labwc (ohne Shell)."""
    befehle = []
    for eltern in wurzel.iter():
        for aktion in eltern.findall("action"):
            if aktion.get("name", "").lower() == "execute":
                befehle.append((eltern.get("key") or eltern.get("label"), shlex.split(aktion.get("command", ""))))
    return befehle


class RasterTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="zenos-raster-test.")
        laufzeit = os.path.join(self.home, "run")
        os.makedirs(laufzeit, mode=0o700)
        self.umgebung = {"HOME": self.home, "XDG_RUNTIME_DIR": laufzeit, "LANG": "C.UTF-8",
                         "PATH": os.environ.get("PATH", "/usr/bin:/bin")}
        self.rc = os.path.join(self.home, ".config", "labwc", "rc.xml")
        self.laufzeit = os.path.join(self.home, ".local", "state", "zenos", "laufzeit.json")

    def tearDown(self):
        zustand = os.path.join(self.home, ".local", "state", "zenos")
        if os.path.isdir(zustand):
            os.chmod(zustand, 0o700)
        shutil.rmtree(self.home, ignore_errors=True)

    def labwc(self, *args, programm=LABWC):
        ergebnis = subprocess.run([programm, *args], capture_output=True, text=True, env=self.umgebung,
                                  timeout=60, check=False)
        return ergebnis.returncode, ergebnis.stdout, ergebnis.stderr

    def ausgeben(self, raster):
        code, text, fehler = self.labwc("--ausgeben", "--raster", raster)
        self.assertEqual(code, 0, fehler)
        return ET.fromstring(text.encode("utf-8"))

    def laufzeit_lesen(self):
        with open(self.laufzeit, encoding="utf-8") as f:
            return json.load(f)

    def laufzeit_schreiben(self, daten):
        os.makedirs(os.path.dirname(self.laufzeit), mode=0o700, exist_ok=True)
        with open(self.laufzeit, "w", encoding="utf-8") as f:
            json.dump(daten, f)

    def einstellungen_schreiben(self, text):
        """einstellungen.json mit genau diesem Text (auch ungültiges JSON)."""
        ordner = os.path.join(self.home, ".config", "zenos")
        os.makedirs(ordner, exist_ok=True)
        with open(os.path.join(ordner, "einstellungen.json"), "w", encoding="utf-8") as f:
            f.write(text)

    def scroll_faktor(self, text):
        """<scrollFactor> aus einer erzeugten rc.xml; genau einer, im default-Block von libinput."""
        wurzel = ET.fromstring(text.encode("utf-8"))
        self.assertEqual(len(list(wurzel.iter("scrollFactor"))), 1)
        geraete = wurzel.findall("libinput/device")
        self.assertEqual([g.get("category") for g in geraete], ["default"])
        self.assertEqual(geraete[0].findtext("naturalScroll"), "yes")
        return geraete[0].findtext("scrollFactor")

    def ausgeben_scroll(self):
        code, text, fehler = self.labwc("--ausgeben")
        self.assertEqual(code, 0, fehler)
        return self.scroll_faktor(text), fehler

    # --- rc.xml

    def test_jede_vorlage_ergibt_gueltige_rcxml(self):
        for name in sorted(os.listdir(VORLAGEN_RASTER)):
            raster = name[:-5]
            with open(os.path.join(VORLAGEN_RASTER, name), encoding="utf-8") as f:
                bereiche = json.load(f)["bereiche"]
            wurzel = self.ausgeben(raster)
            self.assertEqual(wurzel.tag, "labwc_config", raster)
            regionen = [r.get("name") for r in wurzel.iter("region")]
            self.assertEqual(regionen, [f"r{i}" for i in range(1, len(bereiche) + 1)], raster)
            tasten = {k.get("key") for k in wurzel.iter("keybind")}
            ziffern = {t for t in tasten if re.fullmatch(r"W-[0-9]", t)}
            self.assertEqual(ziffern, {f"W-{i}" for i in range(1, min(4, len(bereiche)) + 1)}, raster)

    def test_tastenkuerzel_nach_bauplan(self):
        tasten = [k.get("key") for k in self.ausgeben("4er-grid").iter("keybind")]
        self.assertEqual(len(tasten), len(set(tasten)), "doppelte Tastenkürzel")
        self.assertEqual(set(tasten), TASTEN | {"W-1", "W-2", "W-3", "W-4"})
        self.assertFalse(set(tasten) & FREI, "Kürzel, die für kitty frei bleiben")

    def test_befehle_ohne_shell_und_vorhanden(self):
        ziele = ipc_ziele()
        quellen = [("rc.xml", self.ausgeben("4er-grid"))]
        with open(MENU, encoding="utf-8") as f:
            quellen.append(("menu.xml", ET.fromstring(f.read().encode("utf-8"))))
        anzahl = 0
        for quelle, wurzel in quellen:
            for wo, argv in execute_befehle(wurzel):
                anzahl += 1
                with self.subTest(quelle=quelle, taste=wo):
                    self.assertTrue(argv, "leerer Befehl")
                    self.assertNotIn(os.path.basename(argv[0]), SHELLS)
                    programm = argv[0]
                    if programm.startswith("/opt/zenos/"):
                        programm = os.path.join(WURZEL, programm[len("/opt/zenos/"):])
                    if os.sep in programm:
                        self.assertTrue(programm.startswith(WURZEL + os.sep), argv[0])
                        self.assertTrue(os.access(programm, os.X_OK), f"{argv[0]} fehlt oder ist nicht ausführbar")
                    name = os.path.basename(programm)
                    if name == "zenos-ipc":
                        ziel, funktion, *rest = argv[1:]
                        self.assertIn(ziel, ziele, f"IPC-Ziel {ziel}")
                        self.assertIn(funktion, ziele[ziel], f"IPC-Funktion {ziel}.{funktion}")
                        self.assertEqual(len(rest), ziele[ziel][funktion], f"Argumente für {ziel}.{funktion}")
                    elif name == "zen":
                        self.assertTrue(os.path.isfile(os.path.join(WURZEL, "scripts", "zen.d", argv[1] + ".sh")))
        self.assertGreaterEqual(anzahl, 15)

    def test_vorlage_mit_shell_wird_abgelehnt(self):
        code_ordner = os.path.join(self.home, "code")
        for teil in ("scripts/bin", "system/labwc", "config"):
            shutil.copytree(os.path.join(WURZEL, teil), os.path.join(code_ordner, teil))
        os.makedirs(os.path.join(code_ordner, "shell", "theme"))
        shutil.copy(os.path.join(WURZEL, "shell", "theme", "tokens.json"), os.path.join(code_ordner, "shell", "theme"))
        vorlage = os.path.join(code_ordner, "system", "labwc", "rc.xml.in")
        with open(vorlage, encoding="utf-8") as f:
            text = f.read()
        self.assertIn('command="kitty"', text)
        with open(vorlage, "w", encoding="utf-8") as f:
            f.write(text.replace('command="kitty"', 'command="sh -c kitty"'))
        code, _, fehler = self.labwc("--ausgeben", programm=os.path.join(code_ordner, "scripts", "bin", "zenos-labwc"))
        self.assertEqual(code, 2)
        self.assertIn("startet eine Shell", fehler)

    # --- Scroll-Tempo (einstellungen.json «scrollTempo» → <scrollFactor>)

    def test_scrolltempo_ohne_einstellung_wie_bisher(self):
        self.assertEqual(self.ausgeben_scroll(), ("1.0", ""))
        self.einstellungen_schreiben('{"name": "", "erscheinungsbild": "hell"}')
        self.assertEqual(self.ausgeben_scroll(), ("1.0", ""))

    def test_scrolltempo_aus_einstellungen(self):
        erwartet = {"0.5": "0.5", "1": "1.0", "1.0": "1.0", "1.5": "1.5", "2": "2.0", "0.25": "0.25", "3": "3.0",
                    "0.75": "0.75", "0.333": "0.33", "2.999": "3.0",
                    # gerundet wie Math.round in Einstellungen.qml (halb auf), nicht wie Pythons round (1.12)
                    "1.125": "1.13", "1.005": "1.0"}
        for wert, faktor in erwartet.items():
            with self.subTest(wert=wert):
                self.einstellungen_schreiben('{"erscheinungsbild": "dunkel", "scrollTempo": %s}' % wert)
                self.assertEqual(self.ausgeben_scroll(), (faktor, ""))

    def test_scrolltempo_ungueltig_gilt_standard(self):
        for wert in ('"schnell"', '"1.5"', "0", "-1", "0.2", "3.5", "1e400", "-1e400", "true", "null",
                     "[1.5]", '{"wert": 1.5}', "1" + "0" * 400):
            with self.subTest(wert=wert):
                self.einstellungen_schreiben('{"scrollTempo": %s}' % wert)
                faktor, fehler = self.ausgeben_scroll()
                self.assertEqual(faktor, "1.0")
                self.assertIn("scrollTempo ist ungültig", fehler)

    def test_ungueltige_datei_behaelt_bisheriges_tempo(self):
        # Ohne bisherige rc.xml: Standard
        self.einstellungen_schreiben("{kaputt")
        faktor, fehler = self.ausgeben_scroll()
        self.assertEqual(faktor, "1.0")
        self.assertIn("Scroll-Tempo bleibt 1.0", fehler)
        # Mit rc.xml von zenOS: deren Tempo bleibt (wie die Oberfläche: bisherige Werte bleiben)
        self.einstellungen_schreiben('{"scrollTempo": 1.5}')
        self.assertEqual(self.labwc("--kein-neuladen")[0], 0)
        # NaN und Infinity sind kein JSON (wie JSON.parse in der Oberfläche): die ganze Datei gilt als ungültig
        for text in ("{kaputt", "[1.5]", "", '{"scrollTempo": NaN}', '{"scrollTempo": Infinity}'):
            with self.subTest(text=text):
                self.einstellungen_schreiben(text)
                faktor, fehler = self.ausgeben_scroll()
                self.assertEqual(faktor, "1.5")
                self.assertIn("Scroll-Tempo bleibt 1.5", fehler)
                self.assertEqual(self.labwc("--pruefen")[0], 0)
        # Eine fremde rc.xml zählt nicht
        with open(self.rc, "w", encoding="utf-8") as f:
            f.write("<labwc_config><libinput><device><scrollFactor>2.5</scrollFactor></device></libinput></labwc_config>\n")
        self.assertEqual(self.ausgeben_scroll()[0], "1.0")

    def test_scrolltempo_wechsel_schreibt_neu(self):
        self.einstellungen_schreiben('{"scrollTempo": 1}')
        self.assertEqual(self.labwc("--kein-neuladen")[0], 0)
        self.einstellungen_schreiben('{"scrollTempo": 2}')
        self.assertEqual(self.labwc("--pruefen")[0], 1)
        code, ausgabe, fehler = self.labwc("--melden", "--kein-neuladen")
        self.assertEqual((code, ausgabe.strip(), fehler), (0, "labwc rc.xml (Raster 4er-grid)", ""))
        with open(self.rc, encoding="utf-8") as f:
            self.assertEqual(self.scroll_faktor(f.read()), "2.0")
        self.assertEqual(self.labwc("--melden", "--kein-neuladen")[:2], (0, ""))
        code, ausgabe, _ = self.labwc("--status")
        self.assertEqual((code, json.loads(ausgabe)["scrollTempo"]), (0, 2))

    def test_scrolltempo_grenzen_ueberall_gleich(self):
        with open(SCHEMA_EINSTELLUNGEN, encoding="utf-8") as f:
            schema = json.load(f)["properties"]["scrollTempo"]
        with open(LABWC, encoding="utf-8") as f:
            labwc = dict(re.findall(r"^SCROLL_(DEFAULT|MIN|MAX) = ([\d.]+)$", f.read(), re.M))
        with open(QML_EINSTELLUNGEN, encoding="utf-8") as f:
            qml = dict(re.findall(r"readonly property real scrollTempo(Standard|Min|Max): ([\d.]+)", f.read()))
        with open(QML_SEITE_ALLGEMEIN, encoding="utf-8") as f:
            stufen = [float(w) for w in re.findall(r'wert: "([\d.]+)"', f.read())]
        self.assertEqual(schema["type"], "number")
        self.assertEqual((float(labwc["MIN"]), float(labwc["MAX"]), float(labwc["DEFAULT"])),
                         (schema["minimum"], schema["maximum"], 1.0))
        self.assertEqual((float(qml["Min"]), float(qml["Max"]), float(qml["Standard"])),
                         (schema["minimum"], schema["maximum"], 1.0))
        self.assertEqual(stufen, [0.5, 1.0, 1.5, 2.0])
        self.assertTrue(all(schema["minimum"] <= s <= schema["maximum"] for s in stufen))

    # --- laufzeit.json

    @unittest.skipUnless(jsonschema_da(), "python3-jsonschema fehlt")
    def test_rasterwechsel_behaelt_modus_und_zustand(self):
        zustand = {"id": "fokus", "seit": "2026-09-27T10:00:00+02:00", "endeArt": "manuell", "ausloeser": "manuell"}
        self.laufzeit_schreiben({"modus": "arbeit", "zustand": zustand, "eigenes": 1})
        code, ausgabe, fehler = self.labwc("--raster", "haelften", "--melden", "--kein-neuladen")
        self.assertEqual(code, 0, fehler)
        self.assertEqual(ausgabe.strip(), "labwc rc.xml (Raster haelften)")
        self.assertEqual(self.laufzeit_lesen(), {"modus": "arbeit", "zustand": zustand, "eigenes": 1, "raster": "haelften"})

    @unittest.skipUnless(jsonschema_da(), "python3-jsonschema fehlt")
    def test_zweiter_lauf_schreibt_nichts(self):
        self.assertEqual(self.labwc("--raster", "voll", "--kein-neuladen")[0], 0)
        vorher = (os.stat(self.rc).st_ino, os.stat(self.rc).st_mtime_ns,
                  os.stat(self.laufzeit).st_ino, os.stat(self.laufzeit).st_mtime_ns)
        for args in (("--raster", "voll"), ()):
            code, ausgabe, fehler = self.labwc(*args, "--melden", "--kein-neuladen")
            self.assertEqual((code, ausgabe, fehler), (0, "", ""))
        nachher = (os.stat(self.rc).st_ino, os.stat(self.rc).st_mtime_ns,
                   os.stat(self.laufzeit).st_ino, os.stat(self.laufzeit).st_mtime_ns)
        self.assertEqual(nachher, vorher)
        self.assertEqual(self.labwc("--pruefen")[0], 0)

    def test_ohne_argument_bleibt_laufzeit_unberuehrt(self):
        code, ausgabe, fehler = self.labwc("--melden", "--kein-neuladen")
        self.assertEqual(code, 0, fehler)
        self.assertEqual(ausgabe.strip(), "labwc rc.xml (Raster 4er-grid)")
        self.assertFalse(os.path.exists(self.laufzeit))

    @unittest.skipUnless(jsonschema_da(), "python3-jsonschema fehlt")
    def test_profil_mit_sonderzeichen(self):
        name = "Tisch $(touch boese) ; \"x\" #"
        bildschirme = {"profile": [{"name": name, "ausgaenge": ["*"], "raster": {"*": "drei-spalten"}}]}
        os.makedirs(os.path.join(self.home, ".config", "zenos"))
        with open(os.path.join(self.home, ".config", "zenos", "bildschirme.json"), "w", encoding="utf-8") as f:
            json.dump(bildschirme, f)
        self.laufzeit_schreiben({"modus": "arbeit"})
        code, _, fehler = self.labwc("--profil-hex", name.encode("utf-8").hex(), "--kein-neuladen")
        self.assertEqual(code, 0, fehler)
        self.assertEqual(self.laufzeit_lesen(), {"modus": "arbeit", "raster": "drei-spalten", "profil": name})
        self.assertFalse(os.path.exists(os.path.join(self.home, "boese")))

    @unittest.skipUnless(jsonschema_da(), "python3-jsonschema fehlt")
    @unittest.skipIf(os.geteuid() == 0, "root schreibt auch in schreibgeschützte Ordner")
    def test_laufzeit_nicht_schreibbar_rcxml_bleibt(self):
        self.assertEqual(self.labwc("--raster", "4er-grid", "--kein-neuladen")[0], 0)
        with open(self.rc, encoding="utf-8") as f:
            vorher = f.read()
        os.chmod(os.path.dirname(self.laufzeit), 0o500)
        code, _, fehler = self.labwc("--raster", "voll", "--kein-neuladen")
        os.chmod(os.path.dirname(self.laufzeit), 0o700)
        self.assertEqual(code, 2)
        self.assertIn("laufzeit.json nicht aktualisiert", fehler)
        with open(self.rc, encoding="utf-8") as f:
            self.assertEqual(f.read(), vorher)
        self.assertEqual(self.laufzeit_lesen()["raster"], "4er-grid")


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=[sys.argv[0]])
