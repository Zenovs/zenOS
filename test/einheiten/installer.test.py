#!/usr/bin/env python3
"""Einheitentests für den zen Installer: scripts/bin/zenos-installer (Ansehen ohne Rechte, Auswertung, Hinweise und
Ablehnungen; sicheres Kopieren in die Ablage mit SHA-256; Installieren und Entfernen in den Units mit Sperren, Plan,
Liste, letzte.json und Log; liste, status, oeffnen), der Helfer scripts/bin/zenos-installer-bedienen, die
polkit-Aktionen, die Units, der Starter, das Modul 76-installer und die Prüfung in zen doctor.

Die Test-.deb baut der Test selbst mit «dpkg-deb --build»: einfaches Programm mit Starter und Symbol, mit postinst, mit
systemd-Unit, mit Paketquelle, mit setuid, falsche Architektur, beschädigt, Essential, geschützter Name, Kernel-Modul,
Rechte, Autostart, Starter und Symbol als Verweis. dpkg-deb arbeitet echt (ohne dpkg-deb, etwa auf dem Mac, fallen
diese Tests weg); apt-get, apt-mark, dpkg-query und «dpkg --print-architecture» sind Attrappen (Python-Skripte, der
Vergleich von Versionen geht an das echte dpkg), systemd gibt es im Test nicht (kein Inhibitor, die Unit läuft im
Prozess). Ohne Root, ohne Netz; als root ebenso, dazu Öffnen als ein anderer Benutzer.

  python3 test/einheiten/installer.test.py
"""

import fcntl
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib
from unittest import mock

sys.dont_write_bytecode = True

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-installer")
HELFER = os.path.join(WURZEL, "scripts", "bin", "zenos-installer-bedienen")
BASIS = os.path.join(WURZEL, "scripts", "bin", "zenos-basis")
POLICY = os.path.join(WURZEL, "system", "polkit", "org.zenos.installer.policy")
UNITS = os.path.join(WURZEL, "system", "systemd", "system")
STARTER = os.path.join(WURZEL, "system", "applications", "zenos-installer.desktop")
MIMEAPPS = os.path.join(WURZEL, "system", "xdg", "labwc-mimeapps.list")
MODUL = os.path.join(WURZEL, "scripts", "module", "76-installer.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "76-installer.sh")
SENSIBEL = os.path.join(WURZEL, "scripts", "lib", "sensible-pfade")
BASH = shutil.which("bash")
DPKG_DEB = shutil.which("dpkg-deb")
DPKG = shutil.which("dpkg")


def laden(name, pfad):
    loader = importlib.machinery.SourceFileLoader(name, pfad)
    spec = importlib.util.spec_from_loader(name, loader)
    modul = importlib.util.module_from_spec(spec)
    loader.exec_module(modul)
    return modul


I = laden("zenos_installer", PROGRAMM)
ORIGINAL = {k: getattr(I, k) for k in dir(I) if k.isupper()}

# Attrappen. W ist der Temp-Ordner des Tests, DEB das echte dpkg-deb, DPKG das echte dpkg.
KOPF = r'''
import json, os, subprocess, sys
def lies(name, vorgabe=""):
    try:
        with open(os.path.join(W, "apt", name), encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return vorgabe
def zustand():
    try:
        with open(os.path.join(W, "dpkg-zustand.json"), encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
def zustand_schreiben(z):
    with open(os.path.join(W, "dpkg-zustand.json"), "w", encoding="utf-8") as f:
        json.dump(z, f)
def feld(deb, name):
    return subprocess.run([DEB, "-f", deb, name], capture_output=True, text=True, check=True).stdout.strip()
'''

APT_GET = r'''
args = sys.argv[1:]
with open(os.path.join(W, "apt", "aufrufe"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"args": args, "env": {k: os.environ.get(k) for k in ("DEBIAN_FRONTEND", "LC_ALL", "PATH")}})
            + "\n")
z = zustand()
if "-s" in args:
    if os.path.exists(os.path.join(W, "apt", "sim-stopp")):
        os.unlink(os.path.join(W, "apt", "sim-stopp"))
        import signal
        os.kill(os.getppid(), signal.SIGTERM)
    code = int(lies("sim.exit", "0"))
    if code:
        sys.stdout.write(lies("sim-fehler.txt"))
        sys.exit(code)
    if "install" in args:
        deb = args[-1]
        name, version, arch = feld(deb, "Package"), feld(deb, "Version"), feld(deb, "Architecture")
        alt = z.get(name, [None, None])[1]
        if alt == version:
            print(f"{name} is already the newest version ({version}).")
        else:
            print(f"Inst {name} {'[' + alt + '] ' if alt else ''}({version} local-deb [{arch}])")
        sys.stdout.write(lies("sim-extra.txt"))
    elif "remove" in args:
        name = args[-1]
        print(f"Remv {name} [{z.get(name, ['', '?'])[1]}]")
        sys.stdout.write(lies("sim-remove-extra.txt"))
    sys.exit(0)
if "install" in args:
    deb = args[-1]
    code = int(lies("install.exit", "0"))
    if code:
        print("E: Sub-process /usr/bin/dpkg returned an error code (1)")
        sys.exit(code)
    name, version = feld(deb, "Package"), feld(deb, "Version")
    ziel = os.path.join(W, "fs")
    subprocess.run([DEB, "-x", deb, ziel], check=True)
    liste = subprocess.run([DEB, "-c", deb], capture_output=True, text=True, check=True).stdout
    pfade = ["/" + zeile.split(None, 5)[5].split(" -> ")[0].lstrip("./").rstrip("/") for zeile in liste.splitlines()]
    os.makedirs(os.path.join(W, "dpkg-L"), exist_ok=True)
    with open(os.path.join(W, "dpkg-L", name), "w", encoding="utf-8") as f:
        f.write("\n".join(pfade) + "\n")
    z[name] = ["installed", version]
    for zeile in lies("install-weg.txt").split():
        z.pop(zeile, None)
    zustand_schreiben(z)
    print(f"Setting up {name} ({version}) ...")
    sys.exit(0)
if "remove" in args:
    code = int(lies("remove.exit", "0"))
    if code:
        print("E: Sub-process /usr/bin/dpkg returned an error code (1)")
        sys.exit(code)
    z.pop(args[-1], None)
    zustand_schreiben(z)
    sys.exit(0)
sys.exit(99)
'''

APT_MARK = r'''
if sys.argv[1:] != ["showmanual"]:
    sys.exit(2)
sys.stdout.write(lies("manuell.txt"))
'''

DPKG_QUERY = r'''
args = sys.argv[1:]
z = zustand()
if args[0] == "-L":
    try:
        with open(os.path.join(W, "dpkg-L", args[-1]), encoding="utf-8") as f:
            sys.stdout.write(f.read())
    except FileNotFoundError:
        sys.exit(1)
    sys.exit(0)
if args[0] == "-W" and args[-2] == "--":
    if args[-1] not in z:
        print(f"dpkg-query: no packages found matching {args[-1]}", file=sys.stderr)
        sys.exit(1)
    status, version = z[args[-1]]
    print(f"{status}\t{version}")
    sys.exit(0)
for name, (status, version) in sorted(z.items()):
    print(f"{name}\t{version}\t{status}")
'''

DPKG_ATTRAPPE = r'''
args = sys.argv[1:]
if args == ["--print-architecture"]:
    print(lies("arch", "arm64").strip())
    sys.exit(0)
os.execv(DPKG, [DPKG] + args)
'''

IPC = r'''
with open(os.path.join(W, "ipc-aufrufe"), "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
# Antwort der Oberfläche (installer/Installer.qml)
print(lies("ipc.antwort", "offen"))
sys.exit(int(lies("ipc.exit", "0")))
'''

KONTROLLE = """Package: {name}
Version: {version}
Architecture: {arch}
Maintainer: Beispiel Hersteller <info@example.org>
Homepage: https://example.org/app
Installed-Size: 24
Section: utils
{extra}Description: Eine Beispielanwendung
 Erste Zeile der langen Beschreibung.
 .
 Zweiter Absatz.
"""


def png(breite):
    roh = b"".join(b"\x00" + b"\x10\x20\x30" * breite for _ in range(breite))

    def stueck(art, daten):
        return struct.pack(">I", len(daten)) + art + daten + struct.pack(">I", zlib.crc32(art + daten) & 0xffffffff)

    return (b"\x89PNG\r\n\x1a\n" + stueck(b"IHDR", struct.pack(">IIBBBBB", breite, breite, 8, 2, 0, 0, 0))
            + stueck(b"IDAT", zlib.compress(roh)) + stueck(b"IEND", b""))


SVG = b'<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"></svg>\n'
STARTER_TEXT = ("[Desktop Entry]\nType=Application\nName=Beispiel\nName[de]=Beispiel-App\nExec={name}\nIcon={icon}\n"
                "[Desktop Action neu]\nName=Neu\n")


def schreiben(pfad, inhalt, modus=0o644):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "wb" if isinstance(inhalt, bytes) else "w", **({} if isinstance(inhalt, bytes) else
                                                                   {"encoding": "utf-8"})) as f:
        f.write(inhalt)
    os.chmod(pfad, modus)


def setUpModule():
    os.umask(0o022)


@unittest.skipUnless(DPKG_DEB and DPKG, "dpkg-deb oder dpkg fehlt (nur unter Linux)")
class Umgebung(unittest.TestCase):
    """Temp-Ordner mit allen Pfaden des Programms, Attrappen und einem Bauplatz für Test-.deb."""

    def setUp(self):
        self.w = os.path.realpath(tempfile.mkdtemp(prefix="zenos-installer-test."))
        os.chmod(self.w, 0o755)
        self.addCleanup(shutil.rmtree, self.w, True)
        self.addCleanup(self.zuruecksetzen)
        w = self.w
        pfade = {
            "PATH_CHECK_TOP": w, "TRUSTED_UIDS": (0, os.getuid()), "CODE_DIR": f"{w}/opt/zenos",
            "STATE_DIR": f"{w}/var/lib/zenos/installer", "DROP_DIR": f"{w}/var/lib/zenos/installer/ablage",
            "RUNTIME_DIR": f"{w}/run/zenos-installer", "LOG_FILE": f"{w}/var/log/zenos/installer.log",
            "LOCK_FILE": f"{w}/run/zenos-sperre/kanal.lock", "HAND_MARK": f"{w}/run/zenos-sperre/hand",
            "LISTS_LOCK": f"{w}/var/lib/apt/lists/lock",
            "APT_LOCKS": (f"{w}/var/lib/apt/lists/lock", f"{w}/var/lib/dpkg/lock-frontend", f"{w}/var/lib/dpkg/lock"),
            "DPKG_UPDATES": f"{w}/var/lib/dpkg/updates", "SYSTEMD_RUN_DIR": f"{w}/run/systemd/system",
            "PROC": f"{w}/proc", "RUN_USER": f"{w}/run/user", "IPC": f"{w}/bin/zenos-ipc", "FS_ROOT": f"{w}/fs",
            "APT_GET": f"{w}/bin/apt-get", "APT_MARK": f"{w}/bin/apt-mark", "DPKG": f"{w}/bin/dpkg",
            "DPKG_QUERY": f"{w}/bin/dpkg-query", "DPKG_DEB": DPKG_DEB, "LOGGER": f"{w}/bin/logger-fehlt",
            "LOCK_WAIT": 0, "APT_WAIT": 0, "POLL": 0,
        }
        for name, wert in pfade.items():
            setattr(I, name, wert)
        for ordner in ("var/lib/dpkg/updates", "var/lib/apt/lists", "apt", "proc", "bin", "bau", "fs", "laufzeit",
                       "run"):
            os.makedirs(os.path.join(w, ordner), exist_ok=True)
        os.chmod(os.path.join(w, "laufzeit"), 0o700)
        kopf = f"#!{sys.executable} -S\nW = {w!r}\nDEB = {DPKG_DEB!r}\nDPKG = {DPKG!r}\n{KOPF}"
        for pfad, text in ((I.APT_GET, APT_GET), (I.APT_MARK, APT_MARK), (I.DPKG_QUERY, DPKG_QUERY),
                           (I.DPKG, DPKG_ATTRAPPE), (I.IPC, IPC)):
            schreiben(pfad, kopf + text, 0o755)
        schreiben(f"{I.CODE_DIR}/scripts/pakete/basis.txt", "# zenOS-Pakete\ngreetd labwc   # Login\nkitty\n")
        schreiben(f"{w}/apt/manuell.txt", "bash\neigenes-werkzeug\n")
        umgebung = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": os.path.join(w, "laufzeit")})
        umgebung.start()
        self.addCleanup(umgebung.stop)
        # Ein SIGTERM einer Attrappe ohne den Handler von zenos-installer beendete sonst den Testlauf
        self.fremd = []
        alt = signal.signal(signal.SIGTERM, lambda *_: self.fremd.append(1))
        self.addCleanup(signal.signal, signal.SIGTERM, alt)
        self.addCleanup(lambda: self.assertEqual(self.fremd, [], "SIGTERM ohne Handler von zenos-installer"))

    @staticmethod
    def zuruecksetzen():
        for name, wert in ORIGINAL.items():
            setattr(I, name, wert)

    # --- Helfer ---

    def deb(self, name="zenos-beispiel", version="1.0-1", arch="arm64", dateien=None, verweise=None, skripte=None,
            extra="", datei=None, starter=True, icon=None):
        """Baut eine .deb mit dpkg-deb --build. DATEIEN {Pfad: Inhalt oder (Inhalt, Modus)}, VERWEISE {Pfad: Ziel},
        SKRIPTE {Name: Text}. Standard: Programm, Starter und zwei Symbole (48 und 128 Pixel, dazu SVG)."""
        bau = tempfile.mkdtemp(dir=os.path.join(self.w, "bau"))
        wurzel = os.path.join(bau, "paket")
        inhalt = {}
        if starter:
            inhalt = {f"/usr/bin/{name}": (b"#!/bin/sh\necho hallo\n", 0o755),
                      f"/usr/share/applications/{name}.desktop": STARTER_TEXT.format(name=name, icon=icon or name),
                      f"/usr/share/icons/hicolor/48x48/apps/{name}.png": png(48),
                      f"/usr/share/icons/hicolor/128x128/apps/{name}.png": png(128),
                      f"/usr/share/icons/hicolor/scalable/apps/{name}.svg": SVG}
        inhalt.update(dateien or {})
        for pfad, wert in inhalt.items():
            daten, modus = wert if isinstance(wert, tuple) else (wert, 0o644)
            schreiben(wurzel + pfad, daten, 0o644)
            os.chmod(wurzel + pfad, modus)
        for pfad, ziel in (verweise or {}).items():
            os.makedirs(os.path.dirname(wurzel + pfad), exist_ok=True)
            os.symlink(ziel, wurzel + pfad)
        schreiben(f"{wurzel}/DEBIAN/control", KONTROLLE.format(name=name, version=version, arch=arch, extra=extra))
        for skript, text in (skripte or {}).items():
            schreiben(f"{wurzel}/DEBIAN/{skript}", text, 0o755)
        ziel = os.path.join(self.w, "ablage-benutzer", datei or f"{name}_{version}_{arch}.deb")
        os.makedirs(os.path.dirname(ziel), exist_ok=True)
        subprocess.run([DPKG_DEB, "--root-owner-group", "-Zgzip", "-z1", "--build", wurzel, ziel], check=True,
                       capture_output=True)
        shutil.rmtree(bau)
        return ziel

    def zustand(self, **pakete):
        """dpkg-Zustand der Attrappen: Name=Version (installiert)."""
        schreiben(f"{self.w}/dpkg-zustand.json", json.dumps({k.replace("_", "-"): ["installed", v]
                                                             for k, v in pakete.items()}))

    def apt(self, name, text):
        schreiben(f"{self.w}/apt/{name}", text)

    def apt_aufrufe(self):
        try:
            with open(f"{self.w}/apt/aufrufe", encoding="utf-8") as f:
                return [json.loads(z)["args"] for z in f if z.strip()]
        except FileNotFoundError:
            return []

    def echte_aufrufe(self, wort):
        return [a for a in self.apt_aufrufe() if wort in a and "-s" not in a]

    def ansehen(self, pfad, **kwargs):
        return I.evaluate_file(pfad, **kwargs)

    def arten(self, ev):
        return [h["art"] for h in ev["hinweise"]]

    def lauf(self, befehl, argv):
        """Befehl im Prozess, Ausgabe (auch der Kindprozesse) gesammelt: (Exit, Text)."""
        sys.stdout.flush()
        sys.stderr.flush()
        with tempfile.TemporaryFile() as f:
            gesichert = os.dup(1), os.dup(2)
            os.dup2(f.fileno(), 1)
            os.dup2(f.fileno(), 2)
            try:
                code = befehl(argv)
            finally:
                sys.stdout.flush()
                sys.stderr.flush()
                os.dup2(gesichert[0], 1)
                os.dup2(gesichert[1], 2)
                os.close(gesichert[0])
                os.close(gesichert[1])
            f.seek(0)
            return code, f.read().decode("utf-8", "replace")

    def json_datei(self, name):
        with open(I.state_path(name), encoding="utf-8") as f:
            return json.load(f)

    def liste_schreiben(self, *namen):
        os.makedirs(I.STATE_DIR, exist_ok=True)
        I.write_installed_list({n: {"name": n, "anzeigename": n.title(), "version": "1.0-1", "zeit": "2026-10-08T08:00:00Z",
                                    "programme": []} for n in namen})

    def auftrag(self, pfad, plan=None):
        """Wie auftrag-installieren ohne Unit: kopiert in die Ablage und schreibt den Auftrag. SHA-256."""
        ev = self.ansehen(pfad)
        os.makedirs(I.DROP_DIR, exist_ok=True)
        fd = I.open_as_user(pfad, os.getuid())
        try:
            I.copy_to_drop(fd, ev["sha256"])
        finally:
            os.close(fd)
        I.write_json(os.path.join(I.DROP_DIR, f"{ev['sha256']}.json"),
                     {"version": 1, "sha256": ev["sha256"], "plan": plan or ev["plan"], "datei": os.path.basename(pfad),
                      "groesse": ev["groesse"], "uid": os.getuid(), "von": "pkexec", "zeit": "2026-10-08T08:00:00Z"})
        return ev["sha256"]


class Ansehen(Umgebung):
    def test_einfaches_programm(self):
        pfad = self.deb()
        ev = self.ansehen(pfad, with_icon=True)
        self.assertEqual((ev["ergebnis"], ev["zustand"], ev["ablehnung"]), ("bereit", "neu", None), ev["grund"])
        self.assertEqual(ev["name"], "Beispiel-App", "Name[de] aus dem Starter")
        self.assertEqual(ev["programme"], [{"id": "zenos-beispiel.desktop", "name": "Beispiel-App"}])
        p = ev["paket"]
        self.assertEqual((p["name"], p["version"], p["architektur"]), ("zenos-beispiel", "1.0-1", "arm64"))
        self.assertEqual((p["herausgeber"], p["homepage"], p["installiert_groesse"], p["abschnitt"]),
                         ("Beispiel Hersteller <info@example.org>", "https://example.org/app", 24 * 1024, "utils"))
        self.assertEqual(p["zusammenfassung"], "Eine Beispielanwendung")
        self.assertEqual(p["beschreibung"], "Erste Zeile der langen Beschreibung.\n\nZweiter Absatz.")
        with open(pfad, "rb") as f:
            self.assertEqual(ev["sha256"], hashlib.sha256(f.read()).hexdigest())
        self.assertEqual(ev["groesse"], os.path.getsize(pfad))
        self.assertRegex(ev["plan"], r"^[0-9a-f]{40}$")
        self.assertEqual(ev["hinweise"], [], "nichts Besonderes")
        self.assertEqual((ev["zusaetzlich"], ev["entfernen"], ev["dateien"]), ([], [], 5))
        # Symbol: das PNG mit 128 Pixeln (zwischen 64 und 256) im Laufzeitordner des Benutzers
        self.assertEqual(os.path.dirname(ev["symbol"]), os.path.join(self.w, "laufzeit", "zenos-installer"))
        with open(ev["symbol"], "rb") as f:
            self.assertEqual(I.png_size(f.read()), 128)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(ev["symbol"])).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(ev["symbol"]).st_mode), 0o600)

    def test_json_und_text(self):
        pfad = self.deb()
        code, text = self.lauf(I.cmd_view, [pfad, "--json"])
        self.assertEqual(code, 0, text)
        daten = json.loads(text)
        self.assertEqual(daten["ergebnis"], "bereit")
        self.assertEqual(set(daten), {"version", "ergebnis", "grund", "ablehnung", "pfad", "datei", "groesse",
                                      "sha256", "plan", "name", "paket", "zustand", "installierte_version",
                                      "ueber_installer", "symbol", "programme", "zusaetzlich", "entfernen", "hinweise",
                                      "dateien"})
        code, text = self.lauf(I.cmd_view, [pfad])
        self.assertEqual(code, 0, text)
        self.assertIn("Beispiel-App 1.0-1 (zenos-beispiel, arm64)", text)
        self.assertIn("Zustand      neu", text)
        self.assertIn("Ergebnis: Beispiel-App 1.0-1 ist bereit zum Installieren.", text)
        for argv in ([], [pfad, pfad], ["--json"], [pfad, "--json", "--json"], ["-x.deb"], [pfad, "--json", "--auftrag"],
                     [pfad, "--auftrag", "--auftrag"]):
            with self.subTest(argv=argv):
                self.assertEqual(self.lauf(I.cmd_view, argv)[0], 2)

    def test_auftrag_fuer_zen_install(self):
        """--auftrag: die Ansicht als Text und zuletzt SHA-256 und Plan genau dieser Ansicht (nur bei «bereit»)."""
        pfad = self.deb()
        code, text = self.lauf(I.cmd_view, [pfad, "--auftrag"])
        self.assertEqual(code, 0, text)
        zeilen = text.strip().split("\n")
        ev = self.ansehen(pfad)
        self.assertEqual(zeilen[-1], f"auftrag {ev['sha256']} {ev['plan']}")
        self.assertEqual(zeilen[-2], "Ergebnis: Beispiel-App 1.0-1 ist bereit zum Installieren.")
        self.assertEqual(sum(1 for z in zeilen if z.startswith("auftrag ")), 1)
        # Abgelehnt: kein Auftrag
        code, text = self.lauf(I.cmd_view, [self.deb(name="anders", arch="amd64"), "--auftrag"])
        self.assertEqual(code, 3)
        self.assertNotIn("auftrag ", text)

    def test_relativer_pfad_und_verweis(self):
        pfad = self.deb()
        verweis = os.path.join(self.w, "verweis.deb")
        os.symlink(pfad, verweis)
        alt = os.getcwd()
        os.chdir(os.path.dirname(pfad))
        self.addCleanup(os.chdir, alt)
        for argv in ([os.path.basename(pfad), "--json"], [verweis, "--json"]):
            code, text = self.lauf(I.cmd_view, argv)
            self.assertEqual(code, 0, text)
            self.assertEqual(json.loads(text)["pfad"], pfad, "der echte Pfad, den der Helfer ohne Verweis öffnet")

    def test_postinst(self):
        ev = self.ansehen(self.deb(skripte={"postinst": "#!/bin/sh\nset -e\nsystemctl restart beispiel || true\n",
                                            "prerm": "#!/bin/sh\nexit 0\n"}))
        self.assertEqual(ev["ergebnis"], "bereit")
        self.assertEqual(self.arten(ev), ["skripte", "dienste"])
        self.assertIn("eigene Skripte als root aus (postinst, prerm)", ev["hinweise"][0]["text"])
        self.assertIn("(Skript postinst)", ev["hinweise"][1]["text"])
        self.assertTrue(all(h["stufe"] == "hinweis" for h in ev["hinweise"]), "ruhig, keine Warnung")

    def test_systemd_unit(self):
        ev = self.ansehen(self.deb(dateien={"/lib/systemd/system/beispiel.service": "[Service]\n",
                                            "/usr/lib/systemd/system/beispiel.socket": "[Socket]\n",
                                            "/usr/lib/systemd/user/beispiel-sitzung.service": "[Service]\n"}))
        self.assertEqual(self.arten(ev), ["dienste", "dienste"])
        self.assertEqual(ev["hinweise"][0]["text"], "Startet Systemdienste: beispiel.service, beispiel.socket.")
        self.assertIn("deine Sitzung", ev["hinweise"][1]["text"])
        self.assertEqual(ev["ergebnis"], "bereit")

    def test_paketquelle(self):
        ev = self.ansehen(self.deb(dateien={"/etc/apt/sources.list.d/beispiel.list": "deb https://example.org x y\n"}))
        self.assertEqual(self.arten(ev), ["paketquellen", "ausserhalb"])
        self.assertIn("Basis-Updates", ev["hinweise"][0]["text"])
        self.assertEqual(ev["hinweise"][1]["text"], "Legt Dateien ausserhalb von /usr und /opt ab: /etc (1).")
        # Auch ein Skript, das eine Quelle einträgt (wie Chrome)
        ev = self.ansehen(self.deb(name="zenos-zwei", skripte={"postinst": "#!/bin/sh\necho x > "
                                                                           "/etc/apt/sources.list.d/z.list\n"}))
        self.assertIn("paketquellen", self.arten(ev))

    def test_setuid(self):
        ev = self.ansehen(self.deb(dateien={"/usr/bin/helfer": (b"x", 0o4755), "/usr/bin/gruppe": (b"x", 0o2755),
                                            "/opt/beispiel/normal": (b"x", 0o755)}))
        self.assertEqual(self.arten(ev), ["setuid"])
        self.assertIn("/usr/bin/gruppe, /usr/bin/helfer", ev["hinweise"][0]["text"])

    def test_falsche_architektur(self):
        ev = self.ansehen(self.deb(arch="amd64"))
        self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "architektur"))
        self.assertEqual(ev["grund"], "Das Paket ist für amd64, dieser Rechner braucht arm64.")
        self.assertEqual(ev["paket"]["name"], "zenos-beispiel", "die Daten des Pakets bleiben sichtbar")
        self.assertEqual(self.apt_aufrufe(), [], "keine Simulation")
        ev = self.ansehen(self.deb(name="zenos-alle", arch="all"))
        self.assertEqual(ev["ergebnis"], "bereit", ev["grund"])
        self.apt("arch", "amd64\n")
        ev = self.ansehen(self.deb(name="zenos-intel", arch="amd64"))
        self.assertEqual(ev["ergebnis"], "bereit", "auf dem Bürorechner (amd64)")

    def test_beschaedigt(self):
        pfad = self.deb()
        with open(pfad, "rb") as f:
            daten = f.read()
        faelle = {"halb.deb": daten[: len(daten) // 2], "kopf.deb": daten[:100], "leer.deb": b"",
                  "zufall.deb": os.urandom(4096), "text.deb": b"!<arch>\nkein paket\n"}
        for name, inhalt in faelle.items():
            with self.subTest(name=name):
                ziel = os.path.join(self.w, name)
                schreiben(ziel, inhalt)
                ev = self.ansehen(ziel)
                self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "beschaedigt"), ev["grund"])
                self.assertIsNone(ev["plan"])
                code, _ = self.lauf(I.cmd_view, [ziel])
                self.assertEqual(code, 3)

    def test_ohne_endung_zu_gross_fehlt(self):
        pfad = self.deb()
        anders = os.path.join(self.w, "paket.zip")
        shutil.copy(pfad, anders)
        self.assertEqual(self.ansehen(anders)["ablehnung"], "endung")
        gross = os.path.join(self.w, "GROSS.DEB")
        shutil.copy(pfad, gross)
        self.assertEqual(self.ansehen(gross)["ablehnung"], "endung", "apt nimmt nur .deb")
        I.MAX_DEB = 100
        ev = self.ansehen(pfad)
        self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "zu_gross"))
        I.MAX_DEB = ORIGINAL["MAX_DEB"]
        ev = self.ansehen(os.path.join(self.w, "fehlt.deb"))
        self.assertEqual((ev["ergebnis"], ev["grund"]), ("fehler", "Die Datei gibt es nicht (mehr)."))
        self.assertEqual(self.lauf(I.cmd_view, [os.path.join(self.w, "fehlt.deb")])[0], 1)
        code, text = self.lauf(I.cmd_view, [os.path.join(self.w, "a\nb.deb"), "--json"])
        self.assertEqual((code, json.loads(text)["grund"]), (1, "Ungültiger Dateiname."))

    def test_fremde_datei(self):
        ev = I.Evaluation(self.deb(), owner=os.getuid() + 1).run()
        self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "fremd"))
        self.assertIn("Ablage", ev["grund"])

    def test_essential_und_geschuetzte_namen(self):
        ev = self.ansehen(self.deb(extra="Essential: yes\n"))
        self.assertEqual(ev["ablehnung"], "essentiell")
        for name in ("base-files", "greetd", "kitty"):
            with self.subTest(name=name):
                ev = self.ansehen(self.deb(name=name))
                self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "geschuetzt"), ev["grund"])
                self.assertIn(f"({name})", ev["grund"])

    def test_abhaengigkeiten(self):
        self.apt("sim.exit", "100")
        self.apt("sim-fehler.txt", "Reading package lists...\nThe following packages have unmet dependencies:\n"
                                   " zenos-beispiel : Depends: libnichtda1 but it is not installable\n"
                                   "E: Unable to satisfy dependencies.\n")
        ev = self.ansehen(self.deb())
        self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "abhaengigkeiten"))
        self.assertIn("Depends: libnichtda1 but it is not installable", ev["grund"])

    def test_zusaetzliche_pakete_und_entfernungen(self):
        self.apt("sim-extra.txt", "Inst libbeispiel1 (2.0-1 Ubuntu:26.04/resolute [arm64])\n"
                                  "Inst libalt2 [1.0] (1.1 Ubuntu:26.04/resolute-updates [arm64]) []\n"
                                  "Remv libfrei1 [1.0]\n")
        ev = self.ansehen(self.deb())
        self.assertEqual(ev["ergebnis"], "bereit", ev["grund"])
        self.assertEqual(ev["zusaetzlich"], [{"name": "libbeispiel1", "version": "2.0-1", "alt": None},
                                             {"name": "libalt2", "version": "1.1", "alt": "1.0"}])
        self.assertEqual(ev["entfernen"], ["libfrei1"])
        self.assertEqual(ev["hinweise"], [{"art": "entfernen", "stufe": "warnung", "text": "Entfernt dafür: libfrei1."}])

    def test_entfernung_geschuetzt(self):
        pfad = self.deb()
        for zeile in ("Remv ubuntu-minimal [1.539]", "Remv greetd [0.10]", "Purg eigenes-werkzeug [2.0]"):
            with self.subTest(zeile=zeile):
                self.apt("sim-extra.txt", zeile + "\n")
                ev = self.ansehen(pfad)
                self.assertEqual((ev["ergebnis"], ev["ablehnung"]), ("abgelehnt", "geschuetzt"))
                self.assertIn(zeile.split()[1], ev["grund"])
        # Manuell installiert, aber selbst über den zen Installer gekommen: darf gehen (mit Warnung)
        self.liste_schreiben("eigenes-werkzeug")
        self.apt("sim-extra.txt", "Remv eigenes-werkzeug [2.0]\n")
        ev = self.ansehen(pfad)
        self.assertEqual(ev["ergebnis"], "bereit", ev["grund"])
        self.assertEqual(self.arten(ev), ["entfernen"])

    def test_zustaende(self):
        pfad = self.deb(version="1.2-1")
        self.zustand(zenos_beispiel="1.0-1")
        ev = self.ansehen(pfad)
        self.assertEqual((ev["ergebnis"], ev["zustand"], ev["installierte_version"]), ("bereit", "update", "1.0-1"))
        self.assertEqual(self.arten(ev), ["ersetzt"], "kam nicht über den zen Installer")
        self.liste_schreiben("zenos-beispiel")
        ev = self.ansehen(pfad)
        self.assertEqual((ev["zustand"], ev["ueber_installer"], ev["hinweise"]), ("update", True, []))
        self.zustand(zenos_beispiel="1.2-1")
        ev = self.ansehen(pfad)
        self.assertEqual((ev["ergebnis"], ev["zustand"]), ("installiert", "gleich"))
        self.assertEqual(ev["grund"], "Beispiel-App 1.2-1 ist schon installiert.")
        self.zustand(zenos_beispiel="2:0.1")
        ev = self.ansehen(pfad)
        self.assertEqual((ev["ergebnis"], ev["zustand"]), ("bereit", "rueckschritt"))
        self.assertEqual(self.arten(ev), ["rueckschritt"])

    def test_plan(self):
        a = I.plan_hash("x", "neu", [{"name": "x"}, {"name": "liby:arm64"}], [])
        self.assertEqual(a, I.plan_hash("x", "neu", [{"name": "liby"}, {"name": "x"}], []), "Reihenfolge, Architektur")
        self.assertNotEqual(a, I.plan_hash("x", "update", [{"name": "x"}, {"name": "liby"}], []))
        self.assertNotEqual(a, I.plan_hash("x", "neu", [{"name": "x"}, {"name": "liby"}], [{"name": "z"}]))
        pfad = self.deb()
        erst = self.ansehen(pfad)["plan"]
        self.apt("sim-extra.txt", "Inst libbeispiel1 (2.0-1 Ubuntu:26.04/resolute [arm64])\n")
        dann = self.ansehen(pfad)["plan"]
        self.assertNotEqual(erst, dann)
        self.apt("sim-extra.txt", "Inst libbeispiel1 (2.0-2 Ubuntu:26.04/resolute-updates [arm64])\n")
        self.assertEqual(self.ansehen(pfad)["plan"], dann, "eine neuere Version derselben Abhängigkeit ändert nichts")

    def test_kernel_rechte_autostart(self):
        ev = self.ansehen(self.deb(dateien={"/lib/modules/7.0.0-1-raspi/extra/beispiel.ko.zst": b"x",
                                            "/etc/sudoers.d/beispiel": "x\n",
                                            "/etc/xdg/autostart/beispiel.desktop": "[Desktop Entry]\n"}))
        self.assertEqual(self.arten(ev), ["autostart", "ausserhalb", "kernel", "rechte"])
        self.assertIn("/etc (2)", ev["hinweise"][1]["text"])
        ev = self.ansehen(self.deb(name="zenos-dkms", dateien={"/usr/src/beispiel-1.0/dkms.conf": "x\n"}))
        self.assertEqual(self.arten(ev), ["kernel"])

    def test_starter_und_symbol_als_verweis(self):
        pfad = self.deb(starter=False, dateien={
            "/opt/beispiel/beispiel.desktop": STARTER_TEXT.format(name="beispiel", icon="/opt/beispiel/symbol.png"),
            "/opt/beispiel/symbol.png": png(64), "/opt/beispiel/verborgen.desktop": "x"},
            verweise={"/usr/share/applications/beispiel.desktop": "../../../opt/beispiel/beispiel.desktop",
                      "/usr/share/applications/versteckt.desktop": "/opt/beispiel/versteckt.desktop"})
        ev = self.ansehen(pfad, with_icon=True)
        self.assertEqual(ev["programme"], [{"id": "beispiel.desktop", "name": "Beispiel-App"}])
        with open(ev["symbol"], "rb") as f:
            self.assertEqual(I.png_size(f.read()), 64)

    def test_versteckte_starter_und_svg(self):
        pfad = self.deb(starter=False, dateien={
            "/usr/share/applications/zenos-beispiel.desktop": "[Desktop Entry]\nName=Sichtbar\nIcon=bild\n",
            "/usr/share/applications/hilfe.desktop": "[Desktop Entry]\nName=Hilfe\nNoDisplay=true\n",
            "/usr/share/applications/kein.desktop": "[Desktop Entry]\nType=Link\nName=Link\n",
            "/usr/share/pixmaps/bild.svg": SVG, "/usr/share/pixmaps/bild.png": b"kein png"})
        ev = self.ansehen(pfad, with_icon=True)
        self.assertEqual(ev["programme"], [{"id": "zenos-beispiel.desktop", "name": "Sichtbar"}])
        self.assertTrue(ev["symbol"].endswith(".svg"), "das kaputte PNG fällt weg")

    def test_ohne_laufzeitordner_kein_symbol(self):
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": os.path.join(self.w, "gibt-es-nicht")}):
            ev = self.ansehen(self.deb(), with_icon=True)
        self.assertEqual((ev["ergebnis"], ev["symbol"]), ("bereit", None))

    def test_texte_bereinigt(self):
        pfad = self.deb(starter=False, dateien={"/usr/share/applications/x.desktop":
                                                "[Desktop Entry]\nName=Böse\x1b[31m App\n"})
        ev = self.ansehen(pfad)
        self.assertEqual(ev["name"], "Böse [31m App")
        self.assertEqual(ev["paket"]["homepage"], "https://example.org/app")
        for adresse in ("javascript:alert(1)", "file:///etc/passwd", "https://a b", "http://x\"y"):
            self.assertIsNone(I.URL_RE.fullmatch(adresse), adresse)
        self.assertIsNone(I.Evaluation("x").data["paket"])
        self.assertEqual(I.clean("a\x00b\x07c"), "a b c")
        self.assertEqual(I.clean("Zeile\x1b1\nZeile 2", lines=True), "Zeile1\nZeile 2")
        self.assertEqual(I.clean("x" * 300, 10), "x" * 9 + "…")

    def test_pfade_im_archiv(self):
        self.assertEqual(I.member_path("./usr/bin/x"), "/usr/bin/x")
        self.assertEqual(I.member_path("usr/bin/"), "/usr/bin")
        self.assertEqual(I.member_path("./"), "/")
        for schlecht in ("/etc/passwd", "./usr/../etc/x", "../x", "./a\nb"):
            with self.subTest(pfad=schlecht), self.assertRaises(I.Refusal):
                I.member_path(schlecht)

    def test_simulation_lesen(self):
        inst, remv = I.parse_simulation(
            "NOTE: This is only a simulation!\nInst rustdesk (1.4.2 local-deb [arm64])\n"
            "Inst libxdo3 (1:3.20160805.1-5 Ubuntu:26.04/resolute [arm64])\nConf rustdesk (1.4.2 local-deb [arm64])\n"
            "Inst libc6:armhf [2.42-0ubuntu3] (2.42-0ubuntu3.1 Ubuntu:26.04/resolute-updates [armhf])\n"
            "Remv fish [4.2.1-3.2]\nPurg alt\n")
        self.assertEqual([p["name"] for p in inst], ["rustdesk", "libxdo3", "libc6:armhf"])
        self.assertEqual(inst[2]["alt"], "2.42-0ubuntu3")
        self.assertEqual(remv, [{"name": "fish", "alt": "4.2.1-3.2"}, {"name": "alt", "alt": None}])
        with self.assertRaises(I.Failure):
            I.parse_simulation("Inst kaputt\n")


class Ablage(Umgebung):
    def setUp(self):
        super().setUp()
        os.makedirs(I.DROP_DIR)

    def test_kopie_mit_sha(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        fd = I.open_as_user(pfad, os.getuid())
        try:
            ziel, groesse = I.copy_to_drop(fd, ev["sha256"])
        finally:
            os.close(fd)
        self.assertEqual(ziel, os.path.join(I.DROP_DIR, f"{ev['sha256']}.deb"))
        self.assertEqual(groesse, ev["groesse"])
        self.assertEqual(stat.S_IMODE(os.stat(ziel).st_mode), 0o644)
        with open(ziel, "rb") as a, open(pfad, "rb") as b:
            self.assertEqual(a.read(), b.read())

    def test_geaenderte_datei(self):
        pfad = self.deb()
        sha = self.ansehen(pfad)["sha256"]
        with open(pfad, "ab") as f:
            f.write(b"x")
        fd = I.open_as_user(pfad, os.getuid())
        try:
            with self.assertRaises(I.Refusal) as e:
                I.copy_to_drop(fd, sha)
        finally:
            os.close(fd)
        self.assertEqual(e.exception.kind, "geaendert")
        self.assertEqual(os.listdir(I.DROP_DIR), [], "nichts bleibt liegen")

    def test_verweis_und_ordner(self):
        pfad = self.deb()
        verweis = os.path.join(self.w, "verweis.deb")
        os.symlink(pfad, verweis)
        for ziel, art in ((verweis, "verweis"), (os.path.join(self.w, "bau"), "lesen"),
                          (os.path.join(self.w, "fehlt.deb"), "fehlt")):
            with self.subTest(ziel=ziel), self.assertRaises(I.Refusal) as e:
                os.close(I.open_as_user(ziel, os.getuid()))
            self.assertEqual(e.exception.kind, art)

    def test_zu_gross(self):
        pfad = self.deb()
        I.MAX_DEB = 100
        with self.assertRaises(I.Refusal) as e:
            os.close(I.open_as_user(pfad, os.getuid()))
        self.assertEqual(e.exception.kind, "zu_gross")

    @unittest.skipIf(os.geteuid() == 0, "als root ginge der Wechsel")
    def test_ohne_root_kein_wechsel(self):
        with self.assertRaises(I.Failure):
            I.open_as_user(self.deb(), os.getuid() + 1)

    @unittest.skipUnless(os.geteuid() == 0, "nur als root")
    def test_als_anderer_benutzer(self):
        nobody = 65534
        pfad = self.deb()
        for ordner in (self.w, os.path.dirname(pfad)):
            os.chmod(ordner, 0o755)
        # Gehört root: für nobody «fremd»
        with self.assertRaises(I.Refusal) as e:
            os.close(I.open_as_user(pfad, nobody))
        self.assertEqual(e.exception.kind, "fremd")
        # Gehört nobody: geht, auch als root bleibt root danach root
        os.chown(pfad, nobody, nobody)
        fd = I.open_as_user(pfad, nobody)
        os.close(fd)
        self.assertEqual((os.geteuid(), os.getegid()), (0, 0))
        # nobody kann sie nicht lesen (0600 in einem Ordner nur für root): abgelehnt, obwohl root sie läse
        geheim = os.path.join(self.w, "geheim")
        os.makedirs(geheim, 0o700)
        ziel = os.path.join(geheim, "x.deb")
        shutil.copy(pfad, ziel)
        os.chown(ziel, nobody, nobody)
        with self.assertRaises(I.Refusal) as e:
            os.close(I.open_as_user(ziel, nobody))
        self.assertEqual(e.exception.kind, "lesen")
        self.assertEqual(os.geteuid(), 0)

    def test_reste_aufraeumen(self):
        alt = os.path.join(I.DROP_DIR, "a" * 64 + ".deb")
        neu = os.path.join(I.DROP_DIR, "b" * 64 + ".deb")
        eigen = os.path.join(I.DROP_DIR, "c" * 64 + ".json")
        for p in (alt, neu, eigen):
            schreiben(p, "x")
        os.utime(alt, (1, 1))
        os.utime(eigen, (1, 1))
        I.clean_drop(keep="c" * 64)
        self.assertEqual(sorted(os.listdir(I.DROP_DIR)), sorted([os.path.basename(neu), os.path.basename(eigen)]))


class Auftrag(Umgebung):
    """auftrag-installieren und auftrag-entfernen (root über den Helfer); die Unit läuft im Prozess."""

    def setUp(self):
        super().setUp()
        self.units = []

        def start(unit):
            self.units.append(unit)
            m = re.fullmatch(r"zenos-installer-(installieren|entfernen)@(.+)\.service", unit)
            if m.group(1) == "installieren":
                return I.cmd_install([m.group(2)])
            name = re.sub(r"\\x([0-9a-f]{2})", lambda x: chr(int(x.group(1), 16)), m.group(2))
            return I.cmd_remove([name])

        patch = mock.patch.object(I, "start_unit", side_effect=start)
        patch.start()
        self.addCleanup(patch.stop)
        env = mock.patch.dict(os.environ, {"PKEXEC_UID": str(os.getuid())})
        env.start()
        self.addCleanup(env.stop)

    def test_installieren_ganz(self):
        pfad = self.deb(skripte={"postinst": "#!/bin/sh\nexit 0\n"})
        ev = self.ansehen(pfad)
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 0, text)
        self.assertEqual(self.units, [f"zenos-installer-installieren@{ev['sha256']}.service"])
        aufrufe = self.echte_aufrufe("install")
        self.assertEqual(len(aufrufe), 1)
        self.assertEqual(aufrufe[0][-2:], ["install", os.path.join(I.DROP_DIR, f"{ev['sha256']}.deb")])
        for option in ("Dpkg::Options::=--force-confdef", "Dpkg::Options::=--force-confold", "DPkg::Lock::Timeout=300",
                       "APT::Get::AutomaticRemove=false"):
            self.assertIn(option, aufrufe[0])
        self.assertIn("-y", aufrufe[0])
        self.assertNotIn("--allow-downgrades", aufrufe[0])
        self.assertEqual(os.listdir(I.DROP_DIR), [], "Ablage leer")
        letzte = self.json_datei(I.LAST)
        self.assertEqual((letzte["art"], letzte["ergebnis"], letzte["paket"], letzte["version_neu"], letzte["von"]),
                         ("installieren", "installiert", "zenos-beispiel", "1.0-1", "pkexec"))
        self.assertEqual(letzte["programme"], [{"id": "zenos-beispiel.desktop", "name": "Beispiel-App"}])
        self.assertEqual(letzte["datei"], os.path.basename(pfad))
        liste = self.json_datei(I.INSTALLED)["pakete"]
        self.assertEqual([(e["name"], e["version"], e["anzeigename"], e["sha256"]) for e in liste],
                         [("zenos-beispiel", "1.0-1", "Beispiel-App", ev["sha256"])])
        for name in (I.LAST, I.INSTALLED):
            self.assertEqual(stat.S_IMODE(os.stat(I.state_path(name)).st_mode), 0o644)
        with open(I.LOG_FILE, encoding="utf-8") as f:
            log = f.read()
        self.assertRegex(log, r"== Beginn .* · installieren zenos-beispiel 1\.0-1 · Datei .* · SHA-256 [0-9a-f]{64} · "
                              r"von pkexec\n")
        self.assertIn("zenos-beispiel (neu) → 1.0-1", log)
        self.assertIn("· installiert\n", log)
        self.assertEqual(stat.S_IMODE(os.stat(I.LOG_FILE).st_mode), 0o640)
        self.assertEqual(I.running_jobs(), [])
        self.assertEqual([n for n in os.listdir(I.RUNTIME_DIR) if n.startswith("laeuft")], [])
        # Jetzt ist es da: noch einmal ansehen sagt «installiert»
        self.assertEqual(self.ansehen(pfad)["ergebnis"], "installiert")
        code, text = self.lauf(I.cmd_list, ["--json"])
        self.assertEqual(json.loads(text)["pakete"][0]["installierte_version"], "1.0-1")

    def test_datei_geaendert(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        with open(pfad, "ab") as f:
            f.write(b"x")
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 3, text)
        self.assertIn("seit dem Ansehen geändert", text)
        self.assertEqual((self.units, os.listdir(I.DROP_DIR)), ([], []))

    def test_plan_geaendert(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        self.apt("sim-extra.txt", "Remv libfrei1 [1.0]\n")
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 3, text)
        self.assertEqual(self.echte_aufrufe("install"), [])
        letzte = self.json_datei(I.LAST)
        self.assertEqual(letzte["ergebnis"], "abgelehnt")
        self.assertIn("Noch einmal ansehen", letzte["grund"])
        self.assertEqual(os.listdir(I.DROP_DIR), [])
        self.assertFalse(os.path.exists(I.state_path(I.INSTALLED)))

    def test_falsche_aufrufe(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        for argv in ([], [pfad], [pfad, ev["sha256"]], ["x.deb", ev["sha256"], ev["plan"]],
                     [pfad, ev["sha256"].upper(), ev["plan"]], [pfad, ev["sha256"], ev["plan"][:-1]],
                     [pfad[:-4] + ".zip", ev["sha256"], ev["plan"]], [pfad + "\n.deb", ev["sha256"], ev["plan"]],
                     [pfad, ev["sha256"], ev["plan"], "x"]):
            with self.subTest(argv=argv):
                self.assertEqual(self.lauf(I.cmd_order_install, argv)[0], 2)
        self.assertEqual(self.units, [])

    def test_nicht_root(self):
        I.TRUSTED_UIDS = (0,) if os.geteuid() != 0 else (12345,)
        pfad = self.deb()
        ev = self.ansehen(pfad)
        for befehl, argv in ((I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]]),
                             (I.cmd_order_remove, ["zenos-beispiel"]), (I.cmd_install, [ev["sha256"]]),
                             (I.cmd_remove, ["zenos-beispiel"])):
            with self.subTest(befehl=befehl.__name__):
                code, text = self.lauf(befehl, argv)
                self.assertEqual(code, 2)
                self.assertIn("nur als root", text)

    def test_rueckschritt_und_gleich(self):
        self.liste_schreiben("zenos-beispiel")
        self.zustand(zenos_beispiel="2.0-1")
        pfad = self.deb()
        ev = self.ansehen(pfad)
        self.assertEqual(self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])[0], 0)
        self.assertIn("--allow-downgrades", self.echte_aufrufe("install")[0])
        # Dieselbe Version noch einmal: nichts zu tun, apt läuft nicht
        ev = self.ansehen(pfad)
        self.assertEqual(ev["ergebnis"], "installiert")
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 0, text)
        self.assertEqual(len(self.echte_aufrufe("install")), 1)
        self.assertEqual(self.json_datei(I.LAST)["ergebnis"], "gleich")

    def test_apt_scheitert(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        self.apt("install.exit", "100")
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 1, text)
        letzte = self.json_datei(I.LAST)
        self.assertEqual(letzte["ergebnis"], "fehler")
        self.assertIn("apt-get Exit 100: Sub-process /usr/bin/dpkg returned an error code (1)", letzte["grund"])
        self.assertFalse(os.path.exists(I.state_path(I.INSTALLED)))
        self.assertEqual(os.listdir(I.DROP_DIR), [])

    def test_abgelehnt_unter_root(self):
        """Was beim Ansehen abgelehnt war, lehnt auch die Unit ab (etwa: inzwischen ein geschützter Name)."""
        pfad = self.deb(name="greetd")
        ev = self.ansehen(pfad)
        self.assertEqual(ev["ablehnung"], "geschuetzt")
        code, _ = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], "0" * 40])
        self.assertEqual(code, 3)
        self.assertEqual(self.echte_aufrufe("install"), [])

    def test_belegt(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        os.makedirs(os.path.dirname(I.LOCK_FILE), mode=0o700)
        fd = os.open(I.LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 75, text)
        self.assertIn("Warte auf ein laufendes Update", text)
        self.assertEqual(self.json_datei(I.LAST)["ergebnis"], "wartet")
        self.assertEqual(self.echte_aufrufe("install"), [])
        self.assertEqual(os.listdir(I.DROP_DIR), [])

    def test_install_sh_von_hand(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        schreiben(os.path.join(I.PROC, "4242", "cmdline"), b"bash\0/opt/zenos/scripts/install.sh\0")
        os.makedirs(os.path.dirname(I.HAND_MARK), mode=0o700)
        schreiben(I.HAND_MARK, "4242\n")
        code, _ = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 75)
        os.unlink(I.HAND_MARK)
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 0, text)

    def test_anderer_paketvorgang(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        sperre = I.APT_LOCKS[1]
        os.makedirs(os.path.dirname(sperre), exist_ok=True)
        halter = subprocess.Popen([sys.executable, "-S", "-c", "import fcntl, os, sys, time\n"
                                   "fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT)\nfcntl.lockf(fd, fcntl.LOCK_EX)\n"
                                   "print('ok', flush=True)\ntime.sleep(60)", sperre], stdout=subprocess.PIPE)
        self.addCleanup(halter.stdout.close)
        self.addCleanup(halter.wait)
        self.addCleanup(halter.kill)
        halter.stdout.readline()
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 75, text)
        self.assertIn("anderer Paketvorgang", self.json_datei(I.LAST)["grund"])

    def test_dpkg_unterbrochen(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        schreiben(os.path.join(I.DPKG_UPDATES, "0001"), "x")
        code, _ = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 1)
        self.assertIn("dpkg ist unterbrochen", self.json_datei(I.LAST)["grund"])
        self.assertEqual(self.echte_aufrufe("install"), [])

    def test_stopp_vor_apt(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        self.apt("sim-stopp", "")
        code, text = self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])
        self.assertEqual(code, 10, text)
        self.assertEqual(self.json_datei(I.LAST)["ergebnis"], "wartet")
        self.assertEqual(self.echte_aufrufe("install"), [])
        self.assertEqual(os.listdir(I.DROP_DIR), [])

    def test_kein_auftrag(self):
        os.makedirs(I.DROP_DIR, exist_ok=True)
        code, _ = self.lauf(I.cmd_install, ["a" * 64])
        self.assertEqual(code, 3)
        self.assertIn("Kein Auftrag", self.json_datei(I.LAST)["grund"])
        # Auftrag da, Datei fehlt
        I.write_json(os.path.join(I.DROP_DIR, "b" * 64 + ".json"), {"sha256": "b" * 64, "plan": "0" * 40})
        code, _ = self.lauf(I.cmd_install, ["b" * 64])
        self.assertEqual(code, 3)
        self.assertEqual(os.listdir(I.DROP_DIR), [])

    def test_entfernen(self):
        pfad = self.deb()
        ev = self.ansehen(pfad)
        self.assertEqual(self.lauf(I.cmd_order_install, [pfad, ev["sha256"], ev["plan"]])[0], 0)
        code, text = self.lauf(I.cmd_order_remove, ["zenos-beispiel"])
        self.assertEqual(code, 0, text)
        self.assertEqual(self.units[-1], "zenos-installer-entfernen@zenos\\x2dbeispiel.service")
        entfernen = self.echte_aufrufe("remove")
        self.assertEqual(len(entfernen), 1)
        self.assertEqual(entfernen[0][-2:], ["remove", "zenos-beispiel"])
        self.assertNotIn("purge", entfernen[0])
        self.assertEqual(self.json_datei(I.INSTALLED)["pakete"], [])
        letzte = self.json_datei(I.LAST)
        self.assertEqual((letzte["art"], letzte["ergebnis"], letzte["grund"]),
                         ("entfernen", "entfernt", "Beispiel-App ist entfernt."))

    def test_entfernen_nur_aus_der_liste(self):
        self.zustand(fremd="1.0")
        self.assertEqual(self.lauf(I.cmd_order_remove, ["fremd"])[0], 3)
        self.assertEqual(self.units, [], "die Unit startet gar nicht")
        code, _ = self.lauf(I.cmd_remove, ["fremd"])
        self.assertEqual(code, 3, "und die Unit prüft selbst")
        self.assertEqual(self.echte_aufrufe("remove"), [])
        for argv in ([], ["A"], ["a b"], ["-x"], ["a", "b"]):
            with self.subTest(argv=argv):
                self.assertEqual(self.lauf(I.cmd_order_remove, argv)[0], 2)

    def test_entfernen_nimmt_andere_mit(self):
        self.liste_schreiben("zenos-beispiel")
        self.zustand(zenos_beispiel="1.0-1")
        self.apt("sim-remove-extra.txt", "Remv anderes [2.0]\n")
        code, _ = self.lauf(I.cmd_order_remove, ["zenos-beispiel"])
        self.assertEqual(code, 3)
        self.assertIn("Mit zenos-beispiel gingen auch anderes", self.json_datei(I.LAST)["grund"])
        self.assertEqual(self.echte_aufrufe("remove"), [])

    def test_entfernen_schon_weg_und_geschuetzt(self):
        self.liste_schreiben("zenos-beispiel", "greetd", "lib+plus")
        code, _ = self.lauf(I.cmd_order_remove, ["zenos-beispiel"])
        self.assertEqual(code, 0)
        self.assertIn("war schon entfernt", self.json_datei(I.LAST)["grund"])
        self.assertEqual([e["name"] for e in self.json_datei(I.INSTALLED)["pakete"]], ["greetd", "lib+plus"])
        code, _ = self.lauf(I.cmd_order_remove, ["greetd"])
        self.assertEqual(code, 3)
        self.assertEqual(self.lauf(I.cmd_order_remove, ["lib+plus"])[0], 0)
        self.assertEqual(self.units[-1], "zenos-installer-entfernen@lib\\x2bplus.service")

    def test_entfernen_scheitert(self):
        self.liste_schreiben("zenos-beispiel")
        self.zustand(zenos_beispiel="1.0-1")
        self.apt("remove.exit", "100")
        self.assertEqual(self.lauf(I.cmd_order_remove, ["zenos-beispiel"])[0], 1)
        self.assertEqual([e["name"] for e in self.json_datei(I.INSTALLED)["pakete"]], ["zenos-beispiel"])


class ListeUndStatus(Umgebung):
    def test_liste(self):
        code, text = self.lauf(I.cmd_list, [])
        self.assertEqual((code, text.strip()), (0, "Über den zen Installer kam noch nichts."))
        self.liste_schreiben("eins", "zwei")
        self.zustand(eins="1.0-1")
        code, text = self.lauf(I.cmd_list, ["--json"])
        pakete = json.loads(text)["pakete"]
        self.assertEqual([(p["name"], p["installierte_version"]) for p in pakete], [("eins", "1.0-1"), ("zwei", None)])
        code, text = self.lauf(I.cmd_list, [])
        self.assertIn("nicht mehr installiert", text)
        self.assertEqual(self.lauf(I.cmd_list, ["x"])[0], 2)

    def test_liste_nur_root_eigen(self):
        if os.geteuid() == 0:
            self.skipTest("als root gehört die Datei ohnehin root")
        self.liste_schreiben("eins")
        I.TRUSTED_UIDS = (0,)
        self.assertEqual(I.load_installed_list(), {}, "eine Liste, die nicht root gehört, zählt nicht")

    def test_status(self):
        code, text = self.lauf(I.cmd_status, ["--kurz"])
        self.assertEqual(text.strip(), "keine noch nichts über den zen Installer")
        os.makedirs(I.STATE_DIR, exist_ok=True)
        I.write_json(I.state_path(I.LAST), {"art": "installieren", "ergebnis": "fehler", "paket": "x",
                                            "grund": "kaputt", "ende": "2026-10-08T08:00:00Z"})
        code, text = self.lauf(I.cmd_status, ["--kurz"])
        self.assertRegex(text.strip(), r"^fehler 2026-10-08 \d\d:\d\d: Installation x: kaputt$")
        # Was läuft: nur mit lebendem Prozess
        os.makedirs(I.RUNTIME_DIR)
        I.write_json(os.path.join(I.RUNTIME_DIR, "laeuft-4243.json"), {"art": "installieren", "paket": "y",
                                                                       "phase": "wartet", "pid": 4243})
        self.assertEqual(I.running_jobs(), [])
        schreiben(os.path.join(I.PROC, "4243", "cmdline"), b"/usr/bin/python3\0-I\0/x/zenos-installer\0installieren\0")
        self.assertEqual(I.running_jobs(), [{"art": "installieren", "paket": "y", "phase": "wartet", "seit": None}])
        code, text = self.lauf(I.cmd_status, ["--kurz"])
        self.assertEqual(text.strip(), "laeuft Installation läuft: y")
        code, text = self.lauf(I.cmd_status, ["--json"])
        self.assertEqual(json.loads(text)["laeuft"][0]["paket"], "y")
        self.assertEqual(self.lauf(I.cmd_status, ["--x"])[0], 2)


class Oeffnen(Umgebung):
    def ipc(self):
        try:
            with open(os.path.join(self.w, "ipc-aufrufe"), encoding="utf-8") as f:
                return [json.loads(z) for z in f]
        except FileNotFoundError:
            return []

    def test_gibt_den_pfad_weiter(self):
        pfad = self.deb(datei="mit leer zeichen.deb")
        alt = os.getcwd()
        os.chdir(os.path.dirname(pfad))
        self.addCleanup(os.chdir, alt)
        self.assertEqual(self.lauf(I.cmd_open, ["mit leer zeichen.deb"])[0], 0)
        self.assertEqual(self.ipc(), [["installer", "oeffnen", pfad]])

    def test_prueft(self):
        pfad = self.deb()
        anders = os.path.join(self.w, "x.zip")
        shutil.copy(pfad, anders)
        for argv in ([], [pfad, pfad], [anders], [os.path.join(self.w, "fehlt.deb")], ["file://" + pfad],
                     [pfad + "\x01.deb"], [os.path.join(self.w, "bau") + "/.deb"]):
            with self.subTest(argv=argv):
                self.assertEqual(self.lauf(I.cmd_open, argv)[0], 2)
        self.assertEqual(self.ipc(), [])

    def test_oberflaeche_fehlt(self):
        self.apt("ipc.exit", "2")
        code, text = self.lauf(I.cmd_open, [self.deb()])
        self.assertEqual(code, 1)
        self.assertIn("zen install", text)

    def test_antwort_der_oberflaeche(self):
        """Offen ist es nur bei «offen» oder «laeuft»; gesperrt, Einrichtung und Unbekanntes sind ein Fehler."""
        pfad = self.deb()
        for antwort, erwartet, text in (("offen", 0, ""), ("laeuft", 0, "läuft eine Installation"),
                                        ("gesperrt", 1, "gesperrt"), ("einrichtung", 1, "Einrichtung"),
                                        ("ungueltig", 1, "nimmt den Pfad nicht an"), ("", 1, "Antwort «»"),
                                        ("x\x1by", 1, "Antwort")):
            with self.subTest(antwort=antwort):
                self.apt("ipc.antwort", antwort)
                code, ausgabe = self.lauf(I.cmd_open, [pfad])
                self.assertEqual(code, erwartet, ausgabe)
                self.assertIn(text, ausgabe)
                self.assertNotIn("\x1b", ausgabe)


class Helfer(unittest.TestCase):
    """scripts/bin/zenos-installer-bedienen: nur feste Wörter und streng geprüfte Argumente; als root ändert dieser
    Test nichts (nur falsche Aufrufe)."""

    def lauf(self, *argumente):
        return subprocess.run([HELFER, *argumente], capture_output=True, text=True, timeout=30, check=False,
                              env={"PATH": "/usr/bin:/bin"})

    def test_ausfuehrbar(self):
        self.assertTrue(os.access(HELFER, os.X_OK))
        self.assertTrue(os.access(PROGRAMM, os.X_OK))

    @unittest.skipUnless(BASH, "bash fehlt")
    def test_falsche_aufrufe(self):
        sha, plan = "ab" * 32, "cd" * 20
        for argumente in ((), ("installieren",), ("installieren", "/a.deb"), ("installieren", "/a.deb", sha),
                          ("installieren", "a.deb", sha, plan), ("installieren", "/a.zip", sha, plan),
                          ("installieren", "/a\n.deb", sha, plan), ("installieren", "/a\x01.deb", sha, plan),
                          ("installieren", "/" + "a" * 4100 + ".deb", sha, plan),
                          ("installieren", "/a.deb", sha.upper(), plan), ("installieren", "/a.deb", sha[:-1], plan),
                          ("installieren", "/a.deb", sha, plan + "0"), ("installieren", "/a.deb", sha, plan, "x"),
                          ("installieren", "/a.deb", sha + ";id", plan), ("entfernen",), ("entfernen", "A"),
                          ("entfernen", "-rf"), ("entfernen", "a b"), ("entfernen", "a", "b"), ("entfernen", "a;id"),
                          ("Installieren", "/a.deb", sha, plan), ("ansehen", "/a.deb"), ("status",), ("--hilfe",),
                          ("",), ("auftrag-installieren", "/a.deb", sha, plan)):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("zenos-installer-bedienen:", e.stderr)
                self.assertEqual(e.stdout, "")

    @unittest.skipIf(os.geteuid() == 0, "als root würde der Helfer wirklich installieren")
    @unittest.skipUnless(BASH, "bash fehlt")
    def test_nur_als_root(self):
        for argumente in (("installieren", "/a b/ä.deb", "0" * 64, "0" * 40), ("entfernen", "lib+x.y-1")):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("nur als root", e.stderr)

    def test_startet_nur_mit_argumentlisten(self):
        with open(HELFER, encoding="utf-8") as f:
            text = f.read()
        self.assertNotRegex(text, r"\b(eval|sh -c|bash -c)\b")
        self.assertIn("_programm=/usr/local/libexec/zenos/zenos-installer", text)
        self.assertIn('/usr/bin/python3 -I "$_programm" auftrag-installieren "$2" "$3" "$4"', text)
        self.assertIn('/usr/bin/python3 -I "$_programm" auftrag-entfernen "$2"', text)
        with open(PROGRAMM, encoding="utf-8") as f:
            text = f.read()
        self.assertNotRegex(text, r"shell\s*=\s*True|os\.system|os\.popen")
        self.assertTrue(text.startswith("#!/usr/bin/python3 -I\n"))


class Policy(unittest.TestCase):
    def test_aktionen(self):
        aktionen = ET.parse(POLICY).getroot().findall("action")
        erwartet = {"org.zenos.installer.installieren": "installieren", "org.zenos.installer.entfernen": "entfernen"}
        self.assertEqual(sorted(a.get("id") for a in aktionen), sorted(erwartet))
        for a in aktionen:
            notizen = {n.get("key"): n.text for n in a.findall("annotate")}
            self.assertEqual(notizen, {"org.freedesktop.policykit.exec.path":
                                       "/opt/zenos/scripts/bin/zenos-installer-bedienen",
                                       "org.freedesktop.policykit.exec.argv1": erwartet[a.get("id")]})
            vorgaben = a.find("defaults")
            self.assertEqual((vorgaben.findtext("allow_any"), vorgaben.findtext("allow_inactive"),
                              vorgaben.findtext("allow_active")), ("no", "no", "auth_admin"),
                             "jedes Mal mit Passwort, nie auth_admin_keep")


class Units(unittest.TestCase):
    def lesen(self, name):
        with open(os.path.join(UNITS, name), encoding="utf-8") as f:
            return f.read()

    def test_units(self):
        for name, befehl in (("zenos-installer-installieren@.service", "installieren %i"),
                             ("zenos-installer-entfernen@.service", "entfernen %I")):
            with self.subTest(name=name):
                text = self.lesen(name)
                self.assertIn(f"ExecStart=/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-installer {befehl}\n",
                              text)
                self.assertIn("ConditionPathExists=/usr/local/libexec/zenos/zenos-installer\n", text)
                self.assertIn("Type=oneshot\n", text)
                self.assertIn("KillMode=mixed\n", text)
                self.assertIn("StateDirectory=zenos/installer\n", text)
                self.assertNotIn("RuntimeDirectory=", text, "mehrere Instanzen teilen sich /run/zenos-installer")
                self.assertNotIn("\nSuccessExitStatus=", text)
                self.assertNotIn("[Install]", text, "statisch")

    def test_maskieren_wie_systemd(self):
        for name, erwartet in (("rustdesk", "rustdesk"), ("lib+foo.bar-1", "lib\\x2bfoo.bar\\x2d1"),
                               ("g++-14", "g\\x2b\\x2b\\x2d14")):
            self.assertEqual(I.unit_escape(name), erwartet)
        escape = shutil.which("systemd-escape")
        if escape:
            for name in ("rustdesk", "lib+foo.bar-1", "a.b"):
                r = subprocess.run([escape, "--", name], capture_output=True, text=True, check=True)
                self.assertEqual(I.unit_escape(name), r.stdout.strip())


class Gleichlauf(unittest.TestCase):
    def test_geschuetzt_wie_basis(self):
        with open(BASIS, encoding="utf-8") as f:
            text = f.read()
        m = re.search(r"^PROTECTED = \((.*?)\)\n", text, re.S | re.M)
        self.assertEqual(set(re.findall(r'"([^"]+)"', m.group(1))), set(I.PROTECTED))

    def test_starter_und_standard(self):
        werte = {}
        with open(STARTER, encoding="utf-8") as f:
            for zeile in f:
                if "=" in zeile and not zeile.startswith("#"):
                    k, _, v = zeile.rstrip("\n").partition("=")
                    werte[k] = v
        self.assertEqual(werte["Exec"], "/opt/zenos/scripts/bin/zenos-installer oeffnen %f")
        self.assertEqual(werte["NoDisplay"], "true")
        self.assertEqual(werte["Name"], "zen Installer")
        self.assertEqual(set(werte["MimeType"].strip(";").split(";")),
                         {"application/vnd.debian.binary-package", "application/x-deb"})
        with open(MIMEAPPS, encoding="utf-8") as f:
            text = f.read()
        self.assertIn("\napplication/vnd.debian.binary-package=zenos-installer.desktop\n", text)
        self.assertIn("\napplication/x-deb=zenos-installer.desktop\n", text)

    def test_sensible_pfade(self):
        with open(SENSIBEL, encoding="utf-8") as f:
            zeilen = {z.strip() for z in f if z.strip() and not z.startswith("#")}
        for zeile in ("vertrauen scripts/bin/zenos-installer*", "vertrauen scripts/module/*-installer.sh",
                      "vertrauen system/systemd/system/zenos-installer*", "anmeldung system/polkit/"):
            self.assertIn(zeile, zeilen)


MODUL_RAHMEN = r'''
set -u
datei_installieren() {
  mkdir -p -- "$(dirname -- "$2")"
  if [[ -f "$2" ]] && cmp -s -- "$1" "$2" && [[ "$(stat -c %a -- "$2")" == "${3#0}" ]]; then return 0; fi
  cp -- "$1" "$2"
  chmod "$3" -- "$2"
  printf 'aenderung: %s\n' "$2"
}
ordner_sicherstellen() {
  [[ -d "$1" ]] && return 0
  mkdir -p -- "$1"
  printf 'aenderung: %s\n' "$1"
}
log_warnung() { printf 'warnung: %s\n' "$*"; }
source "$MODUL"
_INSTALLER_LIBEXEC=$ZIEL/usr/local/libexec
_INSTALLER_UNITS=$ZIEL/etc/systemd/system
_INSTALLER_ZUSTAND=$ZIEL/var/lib/zenos
_INSTALLER_POLICY=$ZIEL/usr/share/polkit-1/actions/org.zenos.installer.policy
_INSTALLER_STARTER=$ZIEL/usr/local/share/applications/zenos-installer.desktop
if [[ "${PFAD_PRUEFEN:-0}" != 1 ]]; then _installer_pfad_sicher() { return 0; }; fi
modul_system
'''

DOCTOR_RAHMEN = r'''
set -u
abschnitt() { printf 'abschnitt: %s\n' "$*"; }
ok() { printf 'ok: %s\n' "$*"; }
hinweis() { printf 'hinweis: %s\n' "$*"; }
warnung() { printf 'warnung: %s\n' "$*"; }
fehler() { printf 'fehler: %s\n' "$*"; }
source "$DOCTOR"
_INSTALLER_PROGRAMM=$ZIEL/libexec/zenos-installer
_INSTALLER_QUELLE=$QUELLE
_INSTALLER_UNITS=$ZIEL/units
_INSTALLER_POLICY=$ZIEL/policy
_INSTALLER_STARTER=$ZIEL/starter
_INSTALLER_ABLAGE=$ZIEL/ablage
_INSTALLER_PYTHON=$ZIEL/python3
_installer_nur_root() { [[ ! -e "$ZIEL/nicht-root" ]]; }
_installer_standard() { ok "Standard (Attrappe)"; }
pruefe_installer
'''


@unittest.skipUnless(BASH and shutil.which("stat"), "bash fehlt")
class Modul(unittest.TestCase):
    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-installer-modul.")
        self.addCleanup(shutil.rmtree, self.ziel, True)

    def lauf(self, **env):
        return subprocess.run([BASH, "-c", MODUL_RAHMEN], capture_output=True, text=True, check=False, timeout=60,
                              env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "MODUL": MODUL, "ZIEL": self.ziel,
                                   "ZENOS_CODE": WURZEL, **env})

    def test_installiert_und_zweiter_lauf_ohne_aenderung(self):
        r = self.lauf()
        self.assertEqual(r.returncode, 0, r.stderr)
        if "stat: illegal option" in r.stderr:
            self.skipTest("GNU stat fehlt")
        for pfad, modus in (("usr/local/libexec/zenos/zenos-installer", 0o755),
                            ("etc/systemd/system/zenos-installer-installieren@.service", 0o644),
                            ("etc/systemd/system/zenos-installer-entfernen@.service", 0o644),
                            ("usr/share/polkit-1/actions/org.zenos.installer.policy", 0o644),
                            ("usr/local/share/applications/zenos-installer.desktop", 0o644)):
            with self.subTest(pfad=pfad):
                voll = os.path.join(self.ziel, pfad)
                self.assertTrue(os.path.isfile(voll))
                self.assertEqual(stat.S_IMODE(os.stat(voll).st_mode), modus)
        self.assertTrue(os.path.isdir(os.path.join(self.ziel, "var/lib/zenos/installer/ablage")))
        with open(os.path.join(self.ziel, "usr/local/libexec/zenos/zenos-installer"), "rb") as a, \
                open(PROGRAMM, "rb") as b:
            self.assertEqual(a.read(), b.read())
        r = self.lauf()
        self.assertEqual((r.returncode, r.stdout), (0, ""), "zweiter Lauf: keine Änderung")

    @unittest.skipIf(os.geteuid() == 0, "root besitzt den Temp-Ordner")
    def test_unsicherer_weg(self):
        r = self.lauf(PFAD_PRUEFEN="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("warnung:", r.stdout)
        self.assertIn("zen Installer bleibt weg", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.ziel, "usr/local/libexec/zenos/zenos-installer")))


@unittest.skipUnless(BASH, "bash fehlt")
class Doctor(unittest.TestCase):
    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-installer-doctor.")
        self.addCleanup(shutil.rmtree, self.ziel, True)
        # «python3 -I zenos-installer status --kurz» als Attrappe: gibt $STATUS aus
        schreiben(os.path.join(self.ziel, "python3"), "#!/bin/sh\nprintf '%s\\n' \"$STATUS\"\n", 0o755)
        self.status = "keine noch nichts über den zen Installer"

    def lauf(self):
        r = subprocess.run([BASH, "-c", DOCTOR_RAHMEN], capture_output=True, text=True, check=False, timeout=60,
                           env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "DOCTOR": DOCTOR, "ZIEL": self.ziel,
                                "QUELLE": PROGRAMM, "STATUS": self.status})
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def test_nicht_eingerichtet(self):
        self.assertIn("hinweis: zen Installer noch nicht eingerichtet", self.lauf())

    def test_eingerichtet(self):
        os.makedirs(os.path.join(self.ziel, "libexec"))
        shutil.copy(PROGRAMM, os.path.join(self.ziel, "libexec", "zenos-installer"))
        aus = self.lauf()
        self.assertIn("warnung: zen Installer unvollständig, es fehlt: zenos-installer-installieren@.service "
                      "zenos-installer-entfernen@.service polkit-Aktionen Starter", aus)
        os.makedirs(os.path.join(self.ziel, "units"))
        for name in ("units/zenos-installer-installieren@.service", "units/zenos-installer-entfernen@.service",
                     "policy", "starter"):
            schreiben(os.path.join(self.ziel, name), "x")
        os.makedirs(os.path.join(self.ziel, "ablage"))
        aus = self.lauf()
        self.assertIn("ok: zen Installer eingerichtet", aus)
        self.assertNotIn("warnung", aus)
        self.assertNotIn("Ablage", aus)
        schreiben(os.path.join(self.ziel, "ablage", "x.deb"), "x")
        self.assertIn("hinweis: Ablage des zen Installers nicht leer (1 Dateien", self.lauf())
        self.status = "laeuft Installation läuft: x"
        aus = self.lauf()
        self.assertNotIn("Ablage", aus, "während einer Installation liegt dort etwas")
        self.assertIn("hinweis: zen Installer: Installation läuft: x", aus)
        self.status = "installiert 2026-10-08 10:00: Installation x: X 1.0 ist installiert."
        self.assertIn("ok: zen Installer zuletzt 2026-10-08 10:00: Installation x: X 1.0 ist installiert.", self.lauf())
        self.status = "fehler 2026-10-08 10:00: Installation x: kaputt"
        self.assertIn("warnung: zen Installer zuletzt gescheitert 2026-10-08 10:00", self.lauf())
        schreiben(os.path.join(self.ziel, "nicht-root"), "")
        self.assertIn("fehler:", self.lauf())


if __name__ == "__main__":
    unittest.main(verbosity=1)
