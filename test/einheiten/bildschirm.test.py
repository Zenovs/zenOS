#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-bildschirm (Bildschirm aus nur gesperrt, an, status).

Ohne Sitzung: Jeder Test hat einen eigenen Baum mit einer Kopie von zenos-bildschirm, daneben Attrappen von zen
und zenos-ipc, dazu falsche wlopm, logger und systemctl in einem PATH, der sonst nur die nötigen Werkzeuge enthält
(so fehlt wlopm wirklich, wenn der Test es entfernt). Alle Attrappen schreiben ihre Aufrufe der Reihe nach in eine
gemeinsame Datei. Geprüft wird vor allem die Leitplanke «dunkel heisst gesperrt»: ohne bestätigte Sperre nie
«wlopm --off».

  python3 test/einheiten/bildschirm.test.py
"""

import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BILDSCHIRM = os.path.join(WURZEL, "scripts", "bin", "zenos-bildschirm")
WERKZEUGE = ["bash", "python3", "timeout", "sed", "head", "readlink", "dirname", "cat", "sleep"]

# Attrappe: schreibt {"wer", "argv", "wayland"} als JSON-Zeile. Verhalten aus Dateien im Testordner:
#   <wer>.exit   Exit-Code (Standard 0)
#   <wer>.aus    Ausgabe auf stdout (wlopm: für «--json» allein; für --on/--off ist {"errors": []} Standard)
#   <wer>.warten Sekunden, die die Attrappe vorher wartet
ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, sys, time
WER = %r
ORDNER = os.environ["BILDSCHIRM_TEST"]
def datei(name):
    try:
        with open(os.path.join(ORDNER, WER + "." + name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None
with open(os.path.join(ORDNER, "ereignisse"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"wer": WER, "argv": sys.argv[1:], "wayland": os.environ.get("WAYLAND_DISPLAY")}) + "\n")
if datei("warten"):
    time.sleep(float(datei("warten")))
if WER == "wlopm" and len(sys.argv) > 2:
    aus = datei("schalten")
    print(aus if aus is not None else '{"errors": []}')
elif datei("aus") is not None:
    print(datei("aus"), end="")
sys.exit(int(datei("exit") or 0))
'''


def status_json(*modi):
    return json.dumps([{"output": f"HDMI-A-{i + 1}", "power-mode": m} for i, m in enumerate(modi)])


class BildschirmTest(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-bildschirm-test.")
        self.bin = os.path.join(self.wurzel, "scripts", "bin")
        self.fake = os.path.join(self.wurzel, "fake")
        self.werkzeuge = os.path.join(self.wurzel, "werkzeuge")
        self.lz = os.path.join(self.wurzel, "run")
        for ordner in (self.bin, self.fake, self.werkzeuge, self.lz):
            os.makedirs(ordner)
        os.chmod(self.lz, 0o700)
        self.programm = os.path.join(self.bin, "zenos-bildschirm")
        shutil.copy2(BILDSCHIRM, self.programm)
        self.attrappe(os.path.join(self.wurzel, "scripts", "zen"), "zen")
        self.attrappe(os.path.join(self.bin, "zenos-ipc"), "ipc")
        for name in ("wlopm", "logger", "systemctl"):
            self.attrappe(os.path.join(self.fake, name), name)
        # systemctl --user show-environment: keine Sitzung (die echte Benutzerinstanz bleibt aussen vor)
        self.verhalten("systemctl", "exit", "1")
        for name in WERKZEUGE:
            pfad = shutil.which(name)
            self.assertIsNotNone(pfad, name)
            os.symlink(pfad, os.path.join(self.werkzeuge, name))
        self.sockets = []
        self.socket("wayland-7")
        self.umgebung = {
            "PATH": self.fake + os.pathsep + self.werkzeuge,
            "HOME": self.wurzel,
            "XDG_RUNTIME_DIR": self.lz,
            "WAYLAND_DISPLAY": "wayland-7",
            "LANG": "C.UTF-8",
            "BILDSCHIRM_TEST": self.wurzel,
        }

    def tearDown(self):
        for s in self.sockets:
            s.close()
        shutil.rmtree(self.wurzel, ignore_errors=True)

    # --- Hilfen

    def attrappe(self, pfad, wer):
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(ATTRAPPE % wer)
        os.chmod(pfad, 0o755)

    def verhalten(self, wer, art, text):
        with open(os.path.join(self.wurzel, f"{wer}.{art}"), "w", encoding="utf-8") as f:
            f.write(text)

    def vergessen(self, *namen):
        for name in namen:
            pfad = os.path.join(self.wurzel, name)
            if os.path.exists(pfad):
                os.unlink(pfad)

    def socket(self, name):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(os.path.join(self.lz, name))
        self.sockets.append(s)

    def aufruf(self, *args, cwd=None):
        ergebnis = subprocess.run([self.programm, *args], capture_output=True, text=True, env=self.umgebung,
                                  timeout=30, check=False, cwd=cwd or self.wurzel)
        return ergebnis.returncode, ergebnis.stdout, ergebnis.stderr

    def ereignisse(self, ohne=("systemctl", "logger")):
        try:
            with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
                liste = [json.loads(z) for z in f if z.strip()]
        except OSError:
            return []
        return [(e["wer"], e["argv"]) for e in liste if e["wer"] not in ohne]

    def wlopm_aufrufe(self):
        return [argv for wer, argv in self.ereignisse() if wer == "wlopm"]

    # --- aus

    def test_aus_sperrt_zuerst(self):
        code, aus, fehler = self.aufruf("aus")
        self.assertEqual((code, aus, fehler), (0, "", ""))
        self.assertEqual(self.ereignisse(), [
            ("zen", ["lock"]),
            ("ipc", ["sperre", "bildschirm", "aus"]),
            ("wlopm", ["--json", "--off", "*"]),
        ])

    def test_aus_ohne_sperre_bleibt_hell(self):
        for rc in ("1", "3", "124"):
            with self.subTest(rc=rc):
                self.vergessen("ereignisse")
                self.verhalten("zen", "exit", rc)
                code, _, fehler = self.aufruf("aus")
                self.assertEqual(code, 1)
                self.assertIn("Sperren fehlgeschlagen", fehler)
                self.assertEqual(self.wlopm_aufrufe(), [])
                self.assertNotIn(("ipc", ["sperre", "bildschirm", "aus"]), self.ereignisse())
                # ins Journal
                self.assertTrue(any(w == "logger" and a[:2] == ["-t", "zenos-bildschirm"]
                                    for w, a in self.ereignisse(ohne=())))

    def test_aus_ohne_zen_bleibt_hell(self):
        os.unlink(os.path.join(self.wurzel, "scripts", "zen"))
        code, _, fehler = self.aufruf("aus")
        self.assertEqual(code, 1)
        self.assertIn("zen fehlt", fehler)
        self.assertEqual(self.wlopm_aufrufe(), [])

    def test_aus_wlopm_meldet_fehler_dann_wieder_an(self):
        self.verhalten("wlopm", "schalten", '{"errors": [{"output": "HDMI-A-1", "error": "x"}]}')
        code, _, fehler = self.aufruf("aus")
        self.assertEqual(code, 1)
        self.assertIn("wlopm --off", fehler)
        self.assertEqual(self.ereignisse(), [
            ("zen", ["lock"]),
            ("ipc", ["sperre", "bildschirm", "aus"]),
            ("wlopm", ["--json", "--off", "*"]),
            ("ipc", ["sperre", "bildschirm", "an"]),
        ])

    def test_aus_wlopm_scheitert(self):
        for verhalten in (("exit", "1"), ("schalten", "kein json")):
            with self.subTest(verhalten=verhalten):
                self.vergessen("wlopm.exit", "wlopm.schalten", "ereignisse")
                self.verhalten("wlopm", *verhalten)
                self.assertEqual(self.aufruf("aus")[0], 1)
                self.assertEqual(self.ereignisse()[-1], ("ipc", ["sperre", "bildschirm", "an"]))

    def test_aus_ohne_wlopm_gesperrt_und_hell(self):
        os.unlink(os.path.join(self.fake, "wlopm"))
        code, _, fehler = self.aufruf("aus")
        self.assertEqual(code, 1)
        self.assertIn("wlopm fehlt", fehler)
        self.assertEqual(self.ereignisse(), [("zen", ["lock"])])

    def test_aus_wartet_nicht_auf_eine_haengende_oberflaeche(self):
        self.verhalten("ipc", "warten", "20")
        beginn = time.monotonic()
        self.assertEqual(self.aufruf("aus")[0], 0)
        self.assertLess(time.monotonic() - beginn, 10)
        self.assertEqual(self.wlopm_aufrufe(), [["--json", "--off", "*"]])

    def test_stern_bleibt_ein_argument(self):
        # «*» darf nie zu Dateinamen werden (kein Glob, keine Shell)
        for name in ("a", "b"):
            with open(os.path.join(self.wurzel, name), "w", encoding="utf-8") as f:
                f.write("x")
        self.assertEqual(self.aufruf("aus", cwd=self.wurzel)[0], 0)
        self.assertEqual(self.aufruf("an", cwd=self.wurzel)[0], 0)
        self.assertEqual(self.wlopm_aufrufe(), [["--json", "--off", "*"], ["--json", "--on", "*"]])

    # --- an

    def test_an(self):
        self.assertEqual(self.aufruf("an"), (0, "", ""))
        self.assertEqual(self.ereignisse(), [
            ("wlopm", ["--json", "--on", "*"]),
            ("ipc", ["sperre", "bildschirm", "an"]),
        ])

    def test_an_sperrt_nicht_und_entsperrt_nicht(self):
        self.aufruf("an")
        self.assertNotIn("zen", [w for w, _ in self.ereignisse()])
        self.assertNotIn(["sperre", "entsperren"], [a for _, a in self.ereignisse()])

    def test_an_fehler(self):
        self.verhalten("wlopm", "exit", "1")
        self.assertEqual(self.aufruf("an")[0], 1)
        os.unlink(os.path.join(self.fake, "wlopm"))
        code, _, fehler = self.aufruf("an")
        self.assertEqual(code, 1)
        self.assertIn("wlopm fehlt", fehler)

    # --- status

    def test_status(self):
        faelle = [
            (status_json("on"), (0, "an\n")),
            (status_json("off"), (0, "aus\n")),
            (status_json("on", "off"), (0, "teils\n")),
            (status_json("off", "off"), (0, "aus\n")),
            ("[]", (1, "")),
            ("kein json", (1, "")),
            ('[{"output": "X", "power-mode": "standby"}]', (1, "")),
            ("{}", (1, "")),
        ]
        for text, erwartet in faelle:
            with self.subTest(text=text):
                self.verhalten("wlopm", "aus", text)
                code, aus, _ = self.aufruf("status")
                self.assertEqual((code, aus), erwartet)
        self.assertTrue(all(argv == ["--json"] for argv in self.wlopm_aufrufe()))
        self.assertNotIn("zen", [w for w, _ in self.ereignisse()])

    # --- Aufruf und Sitzung

    def test_falscher_aufruf(self):
        for args in ((), ("aus", "an"), ("AUS",), ("--off",), ("an;aus",), ("*",)):
            with self.subTest(args=args):
                code, aus, _ = self.aufruf(*args)
                self.assertEqual((code, aus), (2, ""))
        self.assertEqual(self.ereignisse(), [])

    def test_ohne_sitzung_nichts(self):
        del self.umgebung["WAYLAND_DISPLAY"]
        for s in self.sockets:
            s.close()
        os.unlink(os.path.join(self.lz, "wayland-7"))
        for befehl in ("aus", "an", "status"):
            with self.subTest(befehl=befehl):
                code, _, fehler = self.aufruf(befehl)
                self.assertEqual(code, 3)
                self.assertIn("keine grafische Sitzung", fehler)
        self.assertEqual(self.ereignisse(), [])

    def test_sitzung_ohne_wayland_display_finden(self):
        # per SSH: WAYLAND_DISPLAY fehlt, der Socket im Laufzeitordner zählt
        del self.umgebung["WAYLAND_DISPLAY"]
        self.verhalten("wlopm", "aus", status_json("on"))
        self.assertEqual(self.aufruf("status")[:2], (0, "an\n"))
        with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
            wlopm = [json.loads(z) for z in f if '"wlopm"' in z]
        self.assertEqual(wlopm[-1]["wayland"], "wayland-7")

    def test_falsches_wayland_display_wird_ersetzt(self):
        self.umgebung["WAYLAND_DISPLAY"] = "wayland-99"
        self.assertEqual(self.aufruf("an")[0], 0)
        with open(os.path.join(self.wurzel, "ereignisse"), encoding="utf-8") as f:
            wlopm = [json.loads(z) for z in f if '"wlopm"' in z]
        self.assertEqual(wlopm[-1]["wayland"], "wayland-7")

    def test_keine_shell_im_skript(self):
        with open(BILDSCHIRM, encoding="utf-8") as f:
            text = "".join(z for z in f if not z.lstrip().startswith("#"))
        self.assertNotRegex(text, r"\b(?:ba)?sh\s+-c\b")
        self.assertNotRegex(text, r"\beval\b")
        # wlopm nur mit festen Wörtern und «*», nie mit wlr-randr
        self.assertNotIn("wlr-randr", text)
        self.assertEqual(sorted(set(re.findall(r"schalten (--\w+)", text))), ["--off", "--on"])


if __name__ == "__main__":
    unittest.main()
