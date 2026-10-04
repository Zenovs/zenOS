#!/usr/bin/env python3
"""Einheitentests für das Entfernen von snapd und landscape-common: scripts/lib/aufraeumen.sh (Auswerten von «snap
list», state.json, Snap-Dateien und des Probelaufs «apt-get -s purge»), scripts/module/22-aufraeumen.sh und die
Pin-Datei system/apt/zenos-ohne-snapd.

Die reinen Funktionen laufen überall mit bash und python3 (auch bash 3.2 auf dem Mac). Die Teile mit apt und dpkg
bauen im Temp-Ordner einen eigenen Paketstand (APT_CONFIG mit eigenem dpkg-Status, eigenen Paketlisten und eigenem
preferences.d; dpkg-query mit --admindir) und laufen nur, wo apt-get und dpkg-query da sind (Container, CI); auf dem
Mac werden sie übersprungen. Ohne Root, ohne Netz, ohne das System zu ändern.

  python3 test/einheiten/aufraeumen.test.py
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.path.join(WURZEL, "scripts", "lib", "aufraeumen.sh")
MODUL = os.path.join(WURZEL, "scripts", "module", "22-aufraeumen.sh")
PIN = os.path.join(WURZEL, "system", "apt", "zenos-ohne-snapd")
BASH = shutil.which("bash")

# Ausgabe von «LC_ALL=C apt-get -s purge snapd landscape-common» im Container (Ubuntu 26.04 mit ubuntu-server)
PROBE_OK = """NOTE: This is only a simulation!
      apt-get needs root privileges for real execution.
      Keep also in mind that locking is deactivated,
      so don't depend on the relevance to the real current situation!
Reading package lists...
Building dependency tree...
Reading state information...
Solving dependencies...
The following packages were automatically installed and are no longer required:
  bc python3-automat python3-configobj python3-twisted
Use 'apt autoremove' to remove them.
The following packages will be REMOVED:
  landscape-common* snapd*
0 upgraded, 0 newly installed, 2 to remove and 12 not upgraded.
Purg landscape-common [26.02.2-0ubuntu1]
Purg snapd [2.76.3+ubuntu26.04]
"""

QUELLEN = """snapd snapd
landscape-common landscape-client
landscape-client landscape-client
ubuntu-server ubuntu-meta
ubuntu-minimal ubuntu-meta
python3-twisted twisted
bc bc
ufw ufw
"""

GESCHUETZT = """# fest
ubuntu-minimal
ubuntu-server
ufw
"""

SNAP_LIST = """Name                Version          Rev    Tracking       Publisher   Notes
bare                1.0              5      latest/stable  canonical✓  base
core22              20240111         1122   latest/stable  canonical✓  base
firefox             128.0-2          4650   latest/stable  mozilla✓    -
gnome-42-2204       0+git.510a601    176    latest/stable  canonical✓  -
snapd               2.76.3           27709  latest/stable  canonical✓  snapd
firefox             127.0-1          4600   latest/stable  mozilla✓    disabled
"""


def bash(*argumente, eingabe=""):
    """Ruft eine Funktion aus scripts/lib/aufraeumen.sh auf (stdin: eingabe)."""
    skript = 'source "$1"; shift; "$@"'
    return subprocess.run([BASH, "-c", skript, "test", LIB, *argumente], input=eingabe, capture_output=True,
                          text=True, timeout=60, check=False)


def zeilen(text):
    return [z for z in text.splitlines() if z]


class PinDatei(unittest.TestCase):
    def setUp(self):
        with open(PIN, encoding="utf-8") as f:
            self.text = f.read()

    def test_eintrag(self):
        eintraege = [z for z in self.text.splitlines() if z and not z.startswith("#")]
        self.assertEqual(eintraege, ["Package: snapd", "Pin: release *", "Pin-Priority: -10"])

    def test_kommentare_nur_mit_raute_und_vor_dem_eintrag(self):
        # apt liest «#»-Zeilen als Kommentar (im Container geprüft); eine Leerzeile trennte Einträge
        kopf = self.text.split("Package:", 1)[0]
        for zeile in kopf.splitlines():
            self.assertTrue(zeile.startswith("#"), zeile)

    def test_dateiname_gilt_fuer_preferences_d(self):
        # apt_preferences(5): ohne Endung oder «.pref», nur Buchstaben, Ziffern, «-», «_» und «.»
        self.assertRegex(os.path.basename(PIN), r"^[A-Za-z0-9_.-]+$")
        self.assertNotIn(".", os.path.basename(PIN))


class Modul(unittest.TestCase):
    def test_kopfzeile(self):
        with open(MODUL, encoding="utf-8") as f:
            self.assertRegex(f.read(), r"(?m)^# 22-aufraeumen: \S")

    def test_nur_erlaubte_funktionen(self):
        # install.sh erlaubt in einem Modul nur modul_system, modul_benutzer und _<name>_* (die Bibliothek wird im
        # Modul gesourct und zählt mit)
        for pfad in (MODUL, LIB):
            with open(pfad, encoding="utf-8") as f:
                namen = re.findall(r"(?m)^([A-Za-z_][A-Za-z0-9_]*)\(\)", f.read())
            self.assertTrue(namen, pfad)
            for name in namen:
                self.assertTrue(name in ("modul_system", "modul_benutzer") or name.startswith("_aufraeumen_"),
                                f"{pfad}: {name}")

    def test_nie_autoremove(self):
        with open(MODUL, encoding="utf-8") as f:
            code = "\n".join(z for z in f.read().splitlines() if not z.lstrip().startswith("#"))
        self.assertNotIn("autoremove", code)
        self.assertNotIn("--auto-remove", code)
        # Probelauf und echter Lauf schalten AutomaticRemove ausdrücklich ab
        self.assertEqual(code.count("APT::Get::AutomaticRemove=false"), 2)


@unittest.skipUnless(BASH and shutil.which("python3"), "bash oder python3 fehlt")
class Snaps(unittest.TestCase):
    def test_snap_list(self):
        aus = bash("_aufraeumen_snap_liste", eingabe=SNAP_LIST)
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertEqual(zeilen(aus.stdout), ["bare", "core22", "firefox", "gnome-42-2204", "snapd"])

    def test_snap_list_leer(self):
        # «No snaps are installed yet …» steht auf stderr, stdout bleibt leer
        self.assertEqual(bash("_aufraeumen_snap_liste", eingabe="").stdout, "")

    def test_snap_list_ohne_kopf_zaehlt_nicht(self):
        # Fehlermeldungen oder ein unbekanntes Format ergeben keine Namen
        aus = bash("_aufraeumen_snap_liste", eingabe="error: cannot communicate with server\n")
        self.assertEqual(aus.stdout, "")

    def test_snap_list_mit_instanzschluessel(self):
        aus = bash("_aufraeumen_snap_liste", eingabe="Name Version Rev\nfirefox_test 1 2\nBAD 1 2\n")
        self.assertEqual(zeilen(aus.stdout), ["firefox_test"])

    def test_grundbestand(self):
        eingabe = "snapd\ncore\ncore18\ncore22\ncore24\nbare\nfirefox\ncore22_test\nlxd\nsnapd-desktop-integration\n\n"
        aus = bash("_aufraeumen_eigene", eingabe=eingabe)
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertEqual(zeilen(aus.stdout), ["core22_test", "firefox", "lxd", "snapd-desktop-integration"])

    def test_nur_grundbestand_ergibt_nichts(self):
        aus = bash("_aufraeumen_eigene", eingabe="snapd\ncore24\nbare\n")
        self.assertEqual((aus.returncode, aus.stdout), (0, ""))

    def test_state_json(self):
        state = '{"data": {"snaps": {"snapd": {"active": true}, "firefox": {}}, "seeded": true}}'
        aus = bash("_aufraeumen_state_liste", eingabe=state)
        self.assertEqual(aus.returncode, 0, aus.stderr)
        self.assertEqual(zeilen(aus.stdout), ["firefox", "snapd"])

    def test_state_json_ohne_snaps(self):
        # So sieht sie aus, wenn snapd gelaufen ist, aber nie einen Snap installiert hat (im Container gesehen)
        aus = bash("_aufraeumen_state_liste", eingabe='{"data": {"seeded": true}}')
        self.assertEqual((aus.returncode, aus.stdout), (0, ""))

    def test_state_json_ungueltig(self):
        for text in ("{kaputt", '{"data": {"snaps": ["firefox"]}}', "[]"):
            self.assertEqual(bash("_aufraeumen_state_liste", eingabe=text).returncode, 1, text)

    def test_snap_dateien(self):
        eingabe = "snapd_27709.snap\ncore22_1122.snap\nfirefox_4650.snap\nhallo_x1.snap\nfirefox_test_12.snap\n" \
                  "partial\nohne-revision.snap\n"
        aus = bash("_aufraeumen_snap_dateien", eingabe=eingabe)
        self.assertEqual(zeilen(aus.stdout), ["core22", "firefox", "firefox_test", "hallo", "snapd"])

    def test_liste(self):
        self.assertEqual(bash("_aufraeumen_liste", "a", "b", "c").stdout, "a, b, c")


@unittest.skipUnless(BASH, "bash fehlt")
class Probelauf(unittest.TestCase):
    """_aufraeumen_simulation_pruefen mit festen Texten (wie aus apt-get -s und dpkg-query)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="zenos-aufraeumen-test.")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def pruefen(self, probe, *ziele, quellen=QUELLEN, geschuetzt=GESCHUETZT):
        dateien = []
        for name, inhalt in (("probe", probe), ("quellen", quellen), ("geschuetzt", geschuetzt)):
            pfad = os.path.join(self.tmp, name)
            with open(pfad, "w", encoding="utf-8") as f:
                f.write(inhalt)
            dateien.append(pfad)
        aus = bash("_aufraeumen_simulation_pruefen", *dateien, *ziele)
        return aus.returncode, zeilen(aus.stdout)

    def test_nur_die_ziele(self):
        self.assertEqual(self.pruefen(PROBE_OK, "snapd", "landscape-common"), (0, []))

    def test_metapaket_ginge_mit(self):
        probe = PROBE_OK + "Purg ubuntu-server [1.570.4]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["geschuetzt: ubuntu-server"]))

    def test_fremdes_paket_ginge_mit(self):
        probe = PROBE_OK + "Purg python3-twisted [25.5.0]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["mehr: python3-twisted"]))

    def test_zenos_paket_ginge_mit(self):
        probe = PROBE_OK + "Remv ufw [0.36]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["geschuetzt: ufw"]))

    def test_unbekanntes_paket_ginge_mit(self):
        # Ohne Eintrag in den Quellen gilt kein Paket als eigener Teil
        probe = PROBE_OK + "Purg irgendwas [1]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["mehr: irgendwas"]))

    def test_eigener_teil_aus_demselben_quellpaket(self):
        probe = PROBE_OK + "Purg landscape-client [26.02.2-0ubuntu1]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (0, []))

    def test_eigener_teil_manuell_installiert(self):
        probe = PROBE_OK + "Purg landscape-client [26.02.2-0ubuntu1]\n"
        geschuetzt = GESCHUETZT + "landscape-client\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common", geschuetzt=geschuetzt),
                         (1, ["geschuetzt: landscape-client"]))

    def test_installieren_ist_nie_erlaubt(self):
        probe = PROBE_OK + "Inst ersatz (1.0 Ubuntu:26.04/resolute [all])\nConf ersatz (1.0)\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["installiert: ersatz"]))

    def test_ziel_fehlt(self):
        probe = "Purg snapd [2.76.3+ubuntu26.04]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["fehlt: landscape-common"]))

    def test_nur_snapd(self):
        self.assertEqual(self.pruefen("Purg snapd [2.76.3]\n", "snapd"), (0, []))

    def test_architektur_zaehlt_nicht(self):
        probe = "Purg snapd:arm64 [2.76.3]\nPurg landscape-common:arm64 [26.02]\n"
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (0, []))

    def test_mehrere_befunde_sortiert(self):
        probe = PROBE_OK + "Purg ubuntu-server [1]\nPurg bc [1]\nInst neu (1)\n"
        rc, befund = self.pruefen(probe, "snapd", "landscape-common")
        self.assertEqual(rc, 1)
        self.assertEqual(befund, ["geschuetzt: ubuntu-server", "installiert: neu", "mehr: bc"])

    def test_geschuetzte_liste_der_bibliothek(self):
        namen = zeilen(bash("_aufraeumen_geschuetzt").stdout)
        for name in ("ubuntu-minimal", "ubuntu-standard", "ubuntu-server", "ubuntu-server-raspi", "ubuntu-pro-client",
                     "lsb-release", "distro-info-data", "update-notifier-common", "apport", "base-files"):
            self.assertIn(name, namen)
        self.assertNotIn("snapd", namen)
        self.assertNotIn("landscape-common", namen)


APT_DA = all(shutil.which(b) for b in ("apt-get", "apt-cache", "dpkg-query", "dpkg"))

# Eigener Paketstand: ubuntu-server empfiehlt snapd und landscape-common (wie in Ubuntu 26.04)
STATUS = """Package: snapd
Status: install ok installed
Priority: optional
Section: devel
Architecture: all
Version: 2.76.3
Description: snapd (Testpaket)

Package: landscape-common
Status: install ok installed
Priority: optional
Section: admin
Architecture: all
Source: landscape-client
Version: 26.02.2-0ubuntu1
Depends: bc
Description: landscape-common (Testpaket)

Package: bc
Status: install ok installed
Priority: optional
Section: math
Architecture: all
Version: 1.07.1
Description: bc (Testpaket)

Package: ubuntu-server
Status: install ok installed
Priority: optional
Section: metapackages
Architecture: all
Source: ubuntu-meta
Version: 1.570.4
{abhaengig}: snapd, landscape-common
Description: ubuntu-server (Testpaket)
"""

PAKETLISTE = """Package: snapd
Architecture: all
Version: 2.76.4
Priority: optional
Section: devel
Filename: pool/main/s/snapd/snapd_2.76.4_all.deb
Size: 1000
Description: snapd (Testpaket)
"""

SERVER = "http://archiv.example.invalid/ubuntu"
LISTEN_PRAEFIX = "archiv.example.invalid_ubuntu_dists_resolute_"
RELEASE = """Origin: Ubuntu
Label: Ubuntu
Suite: resolute
Codename: resolute
Date: Sun, 04 Oct 2026 00:00:00 UTC
Architectures: {arch}
Components: main
Description: Ubuntu Resolute (Test)
"""


@unittest.skipUnless(APT_DA and BASH, "apt-get, apt-cache, dpkg-query oder dpkg fehlt (nur unter Ubuntu/Debian)")
class MitApt(unittest.TestCase):
    """Echter Probelauf von apt-get und echte Pin-Auswertung gegen einen eigenen Paketstand."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="zenos-aufraeumen-apt.")
        self.arch = subprocess.run(["dpkg", "--print-architecture"], capture_output=True, text=True,
                                   check=True).stdout.strip()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def stand(self, abhaengig="Recommends", pin=False):
        """Legt den Paketstand an und gibt die Umgebung mit APT_CONFIG zurück."""
        t = self.tmp
        for ordner in ("apt.conf.d", "preferences.d", "sources.list.d", "lists/partial", "cache", "admin/updates",
                       "admin/info"):
            os.makedirs(os.path.join(t, ordner), exist_ok=True)
        with open(os.path.join(t, "admin", "status"), "w", encoding="utf-8") as f:
            f.write(STATUS.replace("{abhaengig}", abhaengig))
        # snapd und landscape-common als «automatisch installiert», wie im Raspi-Image
        with open(os.path.join(t, "extended_states"), "w", encoding="utf-8") as f:
            for name in ("snapd", "landscape-common", "bc"):
                f.write(f"Package: {name}\nArchitecture: all\nAuto-Installed: 1\n\n")
        with open(os.path.join(t, "sources.list"), "w", encoding="utf-8") as f:
            f.write(f"deb [trusted=yes] {SERVER} resolute main\n")
        with open(os.path.join(t, "lists", f"{LISTEN_PRAEFIX}Release"), "w", encoding="utf-8") as f:
            f.write(RELEASE.format(arch=self.arch))
        with open(os.path.join(t, "lists", f"{LISTEN_PRAEFIX}main_binary-{self.arch}_Packages"), "w",
                  encoding="utf-8") as f:
            f.write(PAKETLISTE)
        if pin:
            shutil.copyfile(PIN, os.path.join(t, "preferences.d", os.path.basename(PIN)))
        konfig = os.path.join(t, "apt.conf")
        with open(konfig, "w", encoding="utf-8") as f:
            f.write(f"""Dir::Etc::parts "{t}/apt.conf.d";
Dir::Etc::main "{t}/fehlt.conf";
Dir::Etc::sourcelist "{t}/sources.list";
Dir::Etc::sourceparts "{t}/sources.list.d";
Dir::Etc::preferences "{t}/preferences";
Dir::Etc::preferencesparts "{t}/preferences.d";
Dir::State::lists "{t}/lists/";
Dir::State::status "{t}/admin/status";
Dir::State::extended_states "{t}/extended_states";
Dir::Cache "{t}/cache/";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
""")
        return dict(os.environ, APT_CONFIG=konfig, LC_ALL="C")

    def probe(self, umgebung, *ziele):
        aus = subprocess.run(["apt-get", "-s", "-o", "APT::Get::AutomaticRemove=false", "purge", *ziele],
                             env=umgebung, capture_output=True, text=True, timeout=60, check=False)
        self.assertEqual(aus.returncode, 0, aus.stdout + aus.stderr)
        return aus.stdout

    def quellen(self):
        # Wie im Modul: «PAKET QUELLPAKET» je installiertem Paket
        aus = subprocess.run(["dpkg-query", f"--admindir={self.tmp}/admin", "-W",
                              "-f=${db:Status-Status} ${Package} ${source:Package}\\n"],
                             capture_output=True, text=True, timeout=60, check=True)
        return "".join(f"{f[1]} {f[2]}\n" for f in (z.split() for z in aus.stdout.splitlines())
                       if len(f) == 3 and f[0] == "installed")

    def pruefen(self, probe, *ziele, geschuetzt="ubuntu-server\n"):
        dateien = []
        for name, inhalt in (("probe.txt", probe), ("quellen.txt", self.quellen()), ("geschuetzt.txt", geschuetzt)):
            pfad = os.path.join(self.tmp, name)
            with open(pfad, "w", encoding="utf-8") as f:
                f.write(inhalt)
            dateien.append(pfad)
        aus = bash("_aufraeumen_simulation_pruefen", *dateien, *ziele)
        return aus.returncode, zeilen(aus.stdout)

    def test_quellpakete_aus_dpkg_query(self):
        self.stand()
        quellen = dict(z.split() for z in self.quellen().splitlines())
        self.assertEqual(quellen["landscape-common"], "landscape-client")
        self.assertEqual(quellen["snapd"], "snapd")
        self.assertEqual(quellen["ubuntu-server"], "ubuntu-meta")

    def test_empfehlung_bleibt_metapaket_bleibt(self):
        umgebung = self.stand("Recommends")
        probe = self.probe(umgebung, "snapd", "landscape-common")
        self.assertIn("Purg snapd", probe)
        self.assertIn("Purg landscape-common", probe)
        self.assertNotIn("ubuntu-server [", probe)
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (0, []))

    def test_abhaengigkeit_nimmt_metapaket_mit(self):
        # Hinge ubuntu-server fest an landscape-common, ginge es mit: dann wird nichts entfernt
        umgebung = self.stand("Depends")
        probe = self.probe(umgebung, "snapd", "landscape-common")
        self.assertIn("ubuntu-server", probe)
        self.assertEqual(self.pruefen(probe, "snapd", "landscape-common"), (1, ["geschuetzt: ubuntu-server"]))

    def test_nie_autoremove_im_probelauf(self):
        # bc wird mit landscape-common überflüssig, geht aber nicht mit
        umgebung = self.stand("Recommends")
        probe = self.probe(umgebung, "landscape-common")
        self.assertNotIn("Purg bc", probe)
        self.assertNotIn("Remv bc", probe)

    def test_pin_sperrt_snapd(self):
        umgebung = self.stand(pin=True)
        aus = subprocess.run(["apt-cache", "policy", "snapd"], env=umgebung, capture_output=True, text=True,
                             timeout=60, check=False)
        self.assertEqual(aus.returncode, 0, aus.stderr)
        # Keine Warnung über die Datei (Kommentare mit «#» und Umlauten)
        self.assertEqual(aus.stderr.strip(), "")
        self.assertIn("Candidate: (none)", aus.stdout)
        self.assertRegex(aus.stdout, r"2\.76\.4 -10")

    def test_ohne_pin_waere_snapd_installierbar(self):
        umgebung = self.stand(pin=False)
        aus = subprocess.run(["apt-cache", "policy", "snapd"], env=umgebung, capture_output=True, text=True,
                             timeout=60, check=False)
        self.assertIn("Candidate: 2.76.4", aus.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
