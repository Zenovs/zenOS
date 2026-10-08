#!/usr/bin/env python3
"""Einheitentests für scripts/module/71-basis.sh (Sperre des Ubuntu-Basiswechsels: Prompt=never per Drop-in, alter
Hinweis auf eine neue Version geleert; Programm, Units und Timer der Basis-Updates mit dem gemeinsamen Notschalter) und
die Prüfungen in zen doctor (scripts/doctor.d/71-ubuntu.sh: Prompt=never, Basis-Updates, Timer). Das Programm
zenos-basis selbst prüfen test/einheiten/basis-updates.test.py und basis-automatik.test.py.

Modul und Prüfung laufen in bash mit Attrappen für die Hilfsfunktionen von install.sh bzw. zen doctor, gegen Ordner im
Temp-Ordner. Die Reihenfolge, in der der Release-Upgrader liest (release-upgrades, danach release-upgrades.d/*.cfg in
Namensreihenfolge, der letzte Wert zählt), bildet der Test mit configparser nach wie MetaRelease.py; dass das Programm
selbst den Drop-in liest, ist im Container geprüft (docs/module/kennung.md). Ohne Root, ohne Netz.

  python3 test/einheiten/basis.test.py
"""

import configparser
import glob
import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODUL = os.path.join(WURZEL, "scripts", "module", "71-basis.sh")
DOCTOR = os.path.join(WURZEL, "scripts", "doctor.d", "71-ubuntu.sh")
DROPIN = os.path.join(WURZEL, "system", "update-manager", "zenos.cfg")
BASH = shutil.which("bash")
EINHEITEN = ("zenos-basis-pruefen.service", "zenos-basis-installieren.service", "zenos-basis-automatik.service",
             "zenos-basis-automatik.timer", "zenos-basis-gelegenheit.service", "zenos-basis-gelegenheit.timer")
TIMER = ("zenos-basis-automatik.timer", "zenos-basis-gelegenheit.timer")

MODUL_RAHMEN = r'''
set -u
datei_installieren() {
  mkdir -p -- "$(dirname -- "$2")"
  if [[ -f "$2" ]] && cmp -s -- "$1" "$2"; then return 0; fi
  cp -- "$1" "$2"
  printf 'aenderung: %s\n' "$2"
}
datei_schreiben() { local t; t=$(mktemp); cat > "$t"; datei_installieren "$t" "$1"; rm -f -- "$t"; }
ordner_sicherstellen() {
  [[ -d "$1" ]] && return 0
  mkdir -p -- "$1"
  printf 'aenderung: %s\n' "$1"
}
aenderung() { printf 'aenderung: %s\n' "$*"; }
log_info() { printf 'info: %s\n' "$*"; }
log_warnung() { printf 'warnung: %s\n' "$*"; }
# systemd zum Schein: aktivierte Einheiten als Dateien in $ZIEL/aktiviert, ohne laufendes systemd (wie im Image)
ZENOS_SYSTEMD=0
ZENOS_IMAGE=0
SUDO=""
systemctl() {
  case "$1" in
    is-enabled) if [[ -e "$ZIEL/aktiviert/$2" ]]; then echo enabled; else echo disabled; return 1; fi ;;
    disable) rm -f -- "$ZIEL/aktiviert/$3" ;;
    *) return 1 ;;
  esac
}
dienst_aktivieren() {
  [[ -e "$ZIEL/aktiviert/$1" ]] && return 0
  mkdir -p -- "$ZIEL/aktiviert"
  : > "$ZIEL/aktiviert/$1"
  aenderung "Dienst aktiviert: $1"
}
systemd_neu_laden() { :; }
source "$MODUL"
_BASIS_DROPIN=$ZIEL/etc/update-manager/release-upgrades.d/zenos.cfg
_BASIS_HINWEIS=$ZIEL/var/lib/ubuntu-release-upgrader/release-upgrade-available
_BASIS_LIBEXEC=$ZIEL/usr/local/libexec
_BASIS_UNITS=$ZIEL/etc/systemd/system
_BASIS_ZUSTAND=$ZIEL/var/lib/zenos
_BASIS_AUS=$ZIEL/etc/xdg/zenos/kanal-automatik-aus
# Der Temp-Ordner gehört nicht root: die Prüfung des Wegs nur, wenn der Test sie verlangt
if [[ "${PFAD_PRUEFEN:-0}" != 1 ]]; then _basis_pfad_sicher() { return 0; }; fi
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
_UBUNTU_ORDNER=$ZIEL/etc/update-manager
_UBUNTU_PROGRAMM=$ZIEL/libexec/zenos-basis
_UBUNTU_QUELLE=$ZIEL/opt/zenos-basis
_UBUNTU_UNITS=$ZIEL/units
_UBUNTU_PYTHON=$ZIEL/python3
_UBUNTU_AUS=$ZIEL/aus
_UBUNTU_SYSTEMD=$ZIEL/run-systemd
_ubuntu_nur_root() { [[ ! -e "$ZIEL/nicht-root" ]]; }
# Zustand der Timer aus $ZIEL/timer.<name> («enabled active», «enabled», «disabled»), ohne Datei: aktiviert und aktiv
systemctl() {
  local zustand="enabled active" timer=${*: -1}
  [[ ! -f "$ZIEL/timer.$timer" ]] || zustand=$(cat "$ZIEL/timer.$timer")
  case "$1" in
    is-enabled) echo "${zustand%% *}"; [[ "${zustand%% *}" == enabled ]] ;;
    --quiet) [[ "$zustand" == *active* ]] ;;
    *) return 1 ;;
  esac
}
"${FUNKTION:-pruefe_ubuntu}"
'''

UBUNTU_RELEASE_UPGRADES = """# Default behavior for the release upgrader.

[DEFAULT]
# Default prompting and upgrade behavior, valid options:
#  never  - Never check for, or allow upgrading to, a new release.
Prompt=lts
"""

UBUNTU_ADVANTAGE = """[Sources]
Pockets=security,updates,proposed,backports,infra-security,infra-updates,apps-security,apps-updates
[Distro]
PostInstallScripts=./xorg_fix_proprietary.py
"""


def schreiben(pfad, text):
    os.makedirs(os.path.dirname(pfad), exist_ok=True)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(text)


def prompt_wie_metarelease(ordner):
    """Prompt wie MetaReleaseCore: release-upgrades, dann release-upgrades.d/*.cfg sortiert, der letzte Wert zählt."""
    dateien = [os.path.join(ordner, "release-upgrades")] if os.path.exists(os.path.join(ordner, "release-upgrades")) \
        else []
    dateien += sorted(glob.glob(os.path.join(ordner, "release-upgrades.d", "*.cfg")))
    prompt = None
    for datei in dateien:
        parser = configparser.ConfigParser()
        parser.read(datei)
        if parser.has_option("DEFAULT", "Prompt"):
            wert = parser.get("DEFAULT", "Prompt").lower()
            prompt = "never" if wert in ("never", "no") else "lts" if wert == "lts" else "normal"
    return prompt


@unittest.skipUnless(BASH, "bash fehlt")
class Modul(unittest.TestCase):
    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-basis-test.")
        self.addCleanup(shutil.rmtree, self.ziel, True)
        self.dropin = os.path.join(self.ziel, "etc", "update-manager", "release-upgrades.d", "zenos.cfg")
        self.hinweis = os.path.join(self.ziel, "var", "lib", "ubuntu-release-upgrader", "release-upgrade-available")

    def lauf(self, pfad_pruefen=False, nur_aenderungen=True):
        r = subprocess.run([BASH, "-c", MODUL_RAHMEN], capture_output=True, text=True, check=False,
                           env={"PATH": "/usr/bin:/bin", "MODUL": MODUL, "ZIEL": self.ziel, "ZENOS_CODE": WURZEL,
                                "PFAD_PRUEFEN": "1" if pfad_pruefen else "0"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        if not nur_aenderungen:
            return r.stdout.splitlines()
        return [z for z in r.stdout.splitlines() if z.startswith("aenderung: ")]

    def basis_teile(self):
        """Programm, Units und Zustandsordner, wie das Modul sie anlegt."""
        z = self.ziel
        return [f"{z}/usr/local/libexec/zenos", f"{z}/usr/local/libexec/zenos/zenos-basis",
                *(f"{z}/etc/systemd/system/{e}" for e in EINHEITEN), f"{z}/var/lib/zenos", f"{z}/var/lib/zenos/basis",
                "Dienst aktiviert: zenos-basis-automatik.timer", "Dienst aktiviert: zenos-basis-gelegenheit.timer"]

    def test_dropin_einmal(self):
        self.assertEqual(self.lauf(), [f"aenderung: {self.dropin}"] + [f"aenderung: {p}" for p in self.basis_teile()])
        with open(self.dropin, encoding="utf-8") as a, open(DROPIN, encoding="utf-8") as b:
            self.assertEqual(a.read(), b.read())
        self.assertEqual(self.lauf(), [], "zweiter Lauf: 0 Änderungen")
        self.assertFalse(os.path.exists(self.hinweis), "kein Hinweis angelegt, wo keiner war")

    def test_programm_und_units(self):
        self.lauf()
        paare = [("scripts/bin/zenos-basis", "usr/local/libexec/zenos/zenos-basis")]
        paare += [(f"system/systemd/system/{e}", f"etc/systemd/system/{e}") for e in EINHEITEN]
        for quelle, ziel in paare:
            with open(os.path.join(WURZEL, quelle), "rb") as a, open(os.path.join(self.ziel, ziel), "rb") as b:
                self.assertEqual(a.read(), b.read(), ziel)
        self.assertTrue(os.path.isdir(os.path.join(self.ziel, "var", "lib", "zenos", "basis")))
        self.assertEqual(sorted(os.listdir(os.path.join(self.ziel, "aktiviert"))),
                         ["zenos-basis-automatik.timer", "zenos-basis-gelegenheit.timer"], "nur die Timer, ab Werk an")

    def test_notschalter_schaltet_die_timer_aus(self):
        """Der gemeinsame Notschalter (sudo zen kanal automatik aus): install.sh schaltet die Timer nicht ein, sondern
        aus; danach 0 Änderungen. Ohne ihn wieder an."""
        self.lauf()
        schreiben(os.path.join(self.ziel, "etc", "xdg", "zenos", "kanal-automatik-aus"), "seit=jetzt\n")
        self.assertEqual(self.lauf(), [f"aenderung: Timer ausgeschaltet (Notschalter {self.ziel}/etc/xdg/zenos/"
                                       f"kanal-automatik-aus): {t}" for t in TIMER])
        self.assertEqual(os.listdir(os.path.join(self.ziel, "aktiviert")), [])
        self.assertEqual(self.lauf(), [], "zweiter Lauf: 0 Änderungen")
        os.unlink(os.path.join(self.ziel, "etc", "xdg", "zenos", "kanal-automatik-aus"))
        self.assertEqual(self.lauf(), [f"aenderung: Dienst aktiviert: {t}" for t in TIMER])

    def test_unsicherer_weg(self):
        """Ein Ordner auf dem Weg gehört nicht root (hier: der Temp-Ordner): Programm und Units bleiben weg."""
        if os.geteuid() == 0:
            os.makedirs(os.path.join(self.ziel, "usr", "local", "libexec"))
            os.chmod(os.path.join(self.ziel, "usr", "local", "libexec"), 0o777)
        zeilen = self.lauf(pfad_pruefen=True, nur_aenderungen=False)
        self.assertIn("ist nicht nur für root schreibbar: zenos-basis bleibt weg", "\n".join(zeilen))
        self.assertFalse(os.path.exists(os.path.join(self.ziel, "usr", "local", "libexec", "zenos")))
        self.assertTrue(os.path.exists(self.dropin), "Prompt=never gilt trotzdem")

    def test_units_wie_vorgesehen(self):
        """Statisch (ohne [Install]), root, mit Netz; installieren mit Laufzeitordner, Inhibitor-tauglichem KillMode und
        langen Zeitlimits wie der Kanal."""
        for name in ("zenos-basis-pruefen.service", "zenos-basis-installieren.service"):
            parser = configparser.ConfigParser(strict=False, interpolation=None)
            parser.optionxform = str
            parser.read(os.path.join(WURZEL, "system", "systemd", "system", name), encoding="utf-8")
            self.assertFalse(parser.has_section("Install"), name)
            self.assertEqual(parser.get("Service", "Type"), "oneshot", name)
            self.assertNotIn("User", parser["Service"], name)
            self.assertNotIn("PrivateNetwork", parser["Service"], name)
            self.assertNotIn("SuccessExitStatus", parser["Service"], name)
            self.assertIn("network-online.target", parser.get("Unit", "Wants"), name)
            self.assertEqual(parser.get("Unit", "ConditionPathExists"), "/usr/local/libexec/zenos/zenos-basis")
            # Ein eigener Mount-Namensraum gilt apt als chroot: Es liesse die Staffelung (Phasing) aus, und die
            # Auswertung passte nicht mehr zu apt-get full-upgrade (im Container geprüft)
            for schluessel in ("PrivateTmp", "PrivateDevices", "PrivateMounts", "ProtectSystem", "ProtectHome",
                               "ProtectKernelTunables", "ProtectKernelModules", "ProtectKernelLogs",
                               "ProtectControlGroups", "ProtectProc", "ProcSubset", "ReadOnlyPaths", "ReadWritePaths",
                               "InaccessiblePaths", "TemporaryFileSystem", "BindPaths", "BindReadOnlyPaths",
                               "RootDirectory", "RootImage", "DynamicUser"):
                self.assertNotIn(schluessel, parser["Service"], f"{name}: {schluessel}")
        parser = configparser.ConfigParser(strict=False, interpolation=None)
        parser.optionxform = str
        parser.read(os.path.join(WURZEL, "system", "systemd", "system", "zenos-basis-installieren.service"),
                    encoding="utf-8")
        dienst = parser["Service"]
        self.assertEqual((dienst["RuntimeDirectory"], dienst["KillMode"], dienst["TimeoutStartSec"],
                          dienst["TimeoutStopSec"]), ("zenos-basis", "mixed", "3h", "20min"))
        self.assertTrue(dienst["ExecStart"].endswith("/usr/local/libexec/zenos/zenos-basis installieren"))
        self.assertIn("apt-daily-upgrade.service", parser.get("Unit", "After"))
        # Auch das Prüfen kann «dpkg --configure -a» nachholen: Ein Stopp darf dpkg nicht mittendrin beenden, und das
        # Zeitlimit deckt Warten (20 Min.), dpkg (1 h), apt-get update (30 Min.) und Auswertung ab
        parser = configparser.ConfigParser(strict=False, interpolation=None)
        parser.optionxform = str
        parser.read(os.path.join(WURZEL, "system", "systemd", "system", "zenos-basis-pruefen.service"),
                    encoding="utf-8")
        dienst = parser["Service"]
        self.assertEqual((dienst["KillMode"], dienst["TimeoutStartSec"], dienst["TimeoutStopSec"]),
                         ("mixed", "3h", "20min"))

    @staticmethod
    def unit(name):
        with open(os.path.join(WURZEL, "system", "systemd", "system", name), encoding="utf-8") as f:
            return [z.strip() for z in f.read().splitlines()]

    def test_automatik_units(self):
        """Wie die Automatik des Kanals: ohne Netz und in derselben Sandbox (zenos-kanal automatik darf liest Sitzungen
        und fragt die Oberfläche als Benutzer), Exit 10 und 75 kein Ausfall, gemeinsamer Notschalter; statisch, nur
        über die Timer."""
        programm = "/usr/bin/python3 -I /usr/local/libexec/zenos/zenos-basis"
        kanal = self.unit("zenos-kanal-automatik.service")
        sandbox = [z for z in kanal if z.split("=", 1)[0] in (
            "PrivateNetwork", "ProtectSystem", "ProtectHome", "PrivateTmp", "PrivateDevices", "RestrictSUIDSGID",
            "RuntimeDirectory", "RuntimeDirectoryMode", "RuntimeDirectoryPreserve", "SuccessExitStatus", "UMask")]
        self.assertEqual(len(sandbox), 11)
        for name, befehl in (("zenos-basis-automatik.service", "automatik lauf"),
                             ("zenos-basis-gelegenheit.service", "automatik gelegenheit")):
            with self.subTest(name):
                zeilen = self.unit(name)
                self.assertIn(f"ExecStart={programm} {befehl}", zeilen)
                self.assertIn("Type=oneshot", zeilen)
                self.assertIn("StateDirectory=zenos/basis", zeilen)
                self.assertIn("ConditionPathExists=!/etc/xdg/zenos/kanal-automatik-aus", zeilen)
                self.assertNotIn("NoNewPrivileges=yes", zeilen, "setpriv zum Benutzer für die Sperre")
                for zeile in sandbox:
                    self.assertIn(zeile, zeilen)
                self.assertFalse(any(z.startswith("[Install]") for z in zeilen), "nur über den Timer")
        self.assertIn("ConditionPathExists=/var/lib/zenos/basis/automatik-bereit",
                      self.unit("zenos-basis-gelegenheit.service"))

    def test_timer(self):
        timer = self.unit("zenos-basis-automatik.timer")
        for zeile in ("OnBootSec=30min", "OnCalendar=*-*-* 03/6:00:00", "RandomizedDelaySec=10min", "Persistent=true",
                      "Unit=zenos-basis-automatik.service", "WantedBy=timers.target"):
            self.assertIn(zeile, timer)
        self.assertIn("OnCalendar=*-*-* 00/6:00:00", self.unit("zenos-kanal.timer"), "versetzt zum Kanal")
        gelegenheit = self.unit("zenos-basis-gelegenheit.timer")
        for zeile in ("OnCalendar=*:07/15", "Unit=zenos-basis-gelegenheit.service", "WantedBy=timers.target"):
            self.assertIn(zeile, gelegenheit)
        self.assertIn("OnCalendar=*:0/15", self.unit("zenos-kanal-gelegenheit.timer"), "versetzt zum Kanal")
        self.assertFalse(any(z.startswith("OnUnitActiveSec") for z in gelegenheit))

    def test_dropin_gewinnt_wie_metarelease(self):
        ordner = os.path.join(self.ziel, "etc", "update-manager")
        schreiben(os.path.join(ordner, "release-upgrades"), UBUNTU_RELEASE_UPGRADES)
        schreiben(os.path.join(ordner, "release-upgrades.d", "ubuntu-advantage-upgrades.cfg"), UBUNTU_ADVANTAGE)
        self.assertEqual(prompt_wie_metarelease(ordner), "lts")
        self.lauf()
        self.assertEqual(prompt_wie_metarelease(ordner), "never")
        with open(os.path.join(ordner, "release-upgrades"), encoding="utf-8") as f:
            self.assertEqual(f.read(), UBUNTU_RELEASE_UPGRADES, "die Conffile bleibt unberührt")

    def test_dropin_nur_ascii(self):
        """Der Release-Upgrader liest mit der Kodierung der Umgebung (configparser.read ohne encoding)."""
        with open(DROPIN, "rb") as f:
            inhalt = f.read()
        self.assertTrue(all(32 <= b < 127 or b == 10 for b in inhalt), "nur druckbares ASCII")
        parser = configparser.ConfigParser()
        parser.read_string(inhalt.decode("ascii"))
        self.assertEqual(parser.get("DEFAULT", "Prompt"), "never")

    def test_alter_hinweis_wird_geleert(self):
        schreiben(self.hinweis, "New release '28.04 LTS' available.\nRun 'do-release-upgrade' to upgrade to it.\n")
        self.assertIn(f"aenderung: {self.hinweis}", self.lauf())
        self.assertEqual(os.path.getsize(self.hinweis), 0)
        self.assertEqual(self.lauf(), [], "zweiter Lauf: 0 Änderungen")

    def test_leerer_hinweis_bleibt(self):
        schreiben(self.hinweis, "")
        self.lauf()
        self.assertEqual(self.lauf(), [])
        self.assertEqual(os.path.getsize(self.hinweis), 0)


@unittest.skipUnless(BASH, "bash fehlt")
class Doctor(unittest.TestCase):
    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-basis-doctor.")
        self.addCleanup(shutil.rmtree, self.ziel, True)
        self.ordner = os.path.join(self.ziel, "etc", "update-manager")
        self.dropin = os.path.join(self.ordner, "release-upgrades.d", "zenos.cfg")

    def doctor(self, funktion="_ubuntu_prompt", alle=False):
        r = subprocess.run([BASH, "-c", DOCTOR_RAHMEN], capture_output=True, text=True, check=False,
                           env={"PATH": "/usr/bin:/bin", "DOCTOR": DOCTOR, "ZIEL": self.ziel, "FUNKTION": funktion})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        zeilen = [z for z in r.stdout.splitlines() if not z.startswith("abschnitt: ")]
        if alle:
            return zeilen
        self.assertEqual(len(zeilen), 1, r.stdout)
        return zeilen[0]

    def mit_dropin(self):
        os.makedirs(os.path.dirname(self.dropin), exist_ok=True)
        shutil.copy(DROPIN, self.dropin)

    def test_ohne_alles(self):
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «normal», nicht «never»"), zeile)
        self.assertIn("fehlt, install.sh legt ihn an", zeile)

    def test_wie_auf_dem_geraet(self):
        schreiben(os.path.join(self.ordner, "release-upgrades"), UBUNTU_RELEASE_UPGRADES)
        schreiben(os.path.join(self.ordner, "release-upgrades.d", "ubuntu-advantage-upgrades.cfg"), UBUNTU_ADVANTAGE)
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «lts»"), zeile)
        self.mit_dropin()
        self.assertEqual(self.doctor(), f"ok: Kein Wechsel der Ubuntu-Hauptversion: Prompt=never ({self.dropin})")

    def test_spaetere_datei_gewinnt(self):
        self.mit_dropin()
        schreiben(os.path.join(self.ordner, "release-upgrades.d", "zz-eigen.cfg"), "[DEFAULT]\nprompt = Normal\n")
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «normal»"), zeile)
        self.assertIn("zz-eigen.cfg gilt nach", zeile)
        self.assertEqual(prompt_wie_metarelease(self.ordner), "normal", "dasselbe wie der Release-Upgrader")

    def test_dropin_veraendert(self):
        schreiben(os.path.join(self.ordner, "release-upgrades"), UBUNTU_RELEASE_UPGRADES)
        schreiben(self.dropin, "[DEFAULT]\n# Prompt=never\n")
        zeile = self.doctor()
        self.assertTrue(zeile.startswith("warnung: Prompt ist «lts»"), zeile)
        self.assertIn("weicht ab, install.sh stellt ihn wieder her", zeile)

    def test_schreibweisen(self):
        faelle = (("[DEFAULT]\nPrompt=never\n", "ok"), ("[DEFAULT]\nPROMPT: No\n", "ok"),
                  ("[DEFAULT]\nprompt =  never  \n", "ok"), ("[Sources]\nPrompt=never\n", "warnung"),
                  ("[DEFAULT]\nPrompt=lts\n", "warnung"), ("[DEFAULT]\nPrompt=never\nPrompt=lts\n", "warnung"))
        for text, erwartet in faelle:
            with self.subTest(text=text):
                schreiben(self.dropin, text)
                self.assertTrue(self.doctor().startswith(erwartet + ": "), text)


@unittest.skipUnless(BASH, "bash fehlt")
class DoctorUpdates(unittest.TestCase):
    """_ubuntu_updates: Programm und Units da, Zustand aus «zenos-basis status --kurz» und «--installation» (hier eine
    Attrappe für python3, die die Zeilen ausgibt)."""

    def setUp(self):
        self.ziel = tempfile.mkdtemp(prefix="zenos-basis-doctor.")
        self.addCleanup(shutil.rmtree, self.ziel, True)
        schreiben(os.path.join(self.ziel, "libexec", "zenos-basis"), "programm\n")
        schreiben(os.path.join(self.ziel, "opt", "zenos-basis"), "programm\n")
        for name in EINHEITEN:
            schreiben(os.path.join(self.ziel, "units", name), "")
        os.makedirs(os.path.join(self.ziel, "run-systemd"))
        python = os.path.join(self.ziel, "python3")
        schreiben(python, '#!/bin/sh\ncase "$4" in --kurz) cat "$(dirname "$0")/kurz" ;; '
                          '--installation) cat "$(dirname "$0")/installation" ;; esac\n')
        os.chmod(python, 0o755)
        self.zeilen("ungeprueft noch nie geprüft", "keine noch kein Basis-Update über zenOS")

    def zeilen(self, kurz, installation):
        schreiben(os.path.join(self.ziel, "kurz"), kurz + "\n")
        schreiben(os.path.join(self.ziel, "installation"), installation + "\n")

    def doctor(self):
        r = subprocess.run([BASH, "-c", DOCTOR_RAHMEN], capture_output=True, text=True, check=False,
                           env={"PATH": "/usr/bin:/bin", "DOCTOR": DOCTOR, "ZIEL": self.ziel,
                                "FUNKTION": "_ubuntu_updates"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout.splitlines()

    def test_zustaende(self):
        faelle = (
            ("ungeprueft noch nie geprüft", "hinweis: Basis-Updates noch nie geprüft (zen update)"),
            ("aktuell aktuell", "ok: Basis-Updates: keine ausstehend"),
            ("bereit 12 Updates (3 Sicherheit)", "hinweis: Basis-Updates ausstehend: 12 Updates (3 Sicherheit) (zen update)"),
            ("zustimmung 2 Updates (Kernel/Firmware/Bootloader)",
             "hinweis: Basis-Updates ausstehend: 2 Updates (Kernel/Firmware/Bootloader) (zen update)"),
            ("laeuft Basis-Update läuft", "hinweis: Ein Basis-Update läuft gerade"),
            ("gesperrt 1 Update, gesperrt: ubuntu-minimal ginge weg",
             "warnung: Basis-Updates gesperrt: 1 Update, gesperrt: ubuntu-minimal ginge weg (apt-get -s full-upgrade)"),
            ("fehler Prüfung gescheitert: apt-get update endete mit Exit 100",
             "warnung: Basis-Updates: Prüfung gescheitert: apt-get update endete mit Exit 100"),
            # Seit der Prüfung änderten sich Pakete (unattended-upgrades): kein «ausstehend: aktuell»
            ("veraltet aktuell (Stand 2026-10-07 09:00, seither Paketänderungen)",
             "hinweis: Basis-Updates: letzte Prüfung aktuell (Stand 2026-10-07 09:00, seither Paketänderungen); neu "
             "prüfen: zen update"),
            ("veraltet 3 Updates (1 Sicherheit) (Stand 2026-10-07 09:00, seither Paketänderungen)",
             "hinweis: Basis-Updates: letzte Prüfung 3 Updates (1 Sicherheit) (Stand 2026-10-07 09:00, seither "
             "Paketänderungen); neu prüfen: zen update"),
        )
        for kurz, erwartet in faelle:
            with self.subTest(kurz=kurz):
                self.zeilen(kurz, "keine noch kein Basis-Update über zenOS")
                self.assertEqual(self.doctor(), [erwartet])

    def test_installation(self):
        faelle = (("installiert 2026-10-07 12:00: 6 Pakete aktualisiert, gesund.",
                   "ok: Letztes Basis-Update 2026-10-07 12:00: 6 Pakete aktualisiert, gesund."),
                  ("kaputt 2026-10-07 12:00: Nach dem Update schlechter als vorher: greetd ist ausgefallen.",
                   "fehler: Letztes Basis-Update kaputt 2026-10-07 12:00: Nach dem Update schlechter als vorher: "
                   f"greetd ist ausgefallen. (behoben? sudo {self.ziel}/libexec/zenos-basis quittieren)"),
                  # Mit zenos-basis quittieren als behoben vermerkt: kein Fehler mehr
                  ("behoben 2026-10-07 12:00: kaputt, als behoben vermerkt am 2026-10-08 09:00 (Nach dem Update "
                   "schlechter als vorher: greetd ist ausgefallen.)",
                   "ok: Letztes Basis-Update 2026-10-07 12:00: kaputt, als behoben vermerkt am 2026-10-08 09:00 (Nach "
                   "dem Update schlechter als vorher: greetd ist ausgefallen.)"),
                  ("fehler 2026-10-07 12:00: apt-get full-upgrade endete mit Exit 100",
                   "warnung: Letztes Basis-Update brach ab 2026-10-07 12:00: apt-get full-upgrade endete mit Exit 100"))
        for installation, erwartet in faelle:
            with self.subTest(installation=installation):
                self.zeilen("aktuell aktuell", installation)
                self.assertEqual(self.doctor(), ["ok: Basis-Updates: keine ausstehend", erwartet])

    def test_programm_und_units(self):
        os.unlink(os.path.join(self.ziel, "units", "zenos-basis-installieren.service"))
        schreiben(os.path.join(self.ziel, "opt", "zenos-basis"), "neuer\n")
        zeilen = self.doctor()
        self.assertIn("warnung: zenos-basis-installieren.service fehlt (install.sh)", zeilen)
        self.assertTrue(any(z.startswith("warnung: ") and "weicht vom Stand in /opt/zenos ab" in z for z in zeilen))
        schreiben(os.path.join(self.ziel, "nicht-root"), "")
        self.assertTrue(any(z.startswith("fehler: ") and "nicht nur für root schreibbar" in z for z in self.doctor()))
        shutil.rmtree(os.path.join(self.ziel, "libexec"))
        self.assertEqual(self.doctor(), [f"hinweis: Basis-Updates noch nicht eingerichtet "
                                         f"({self.ziel}/libexec/zenos-basis fehlt; install.sh richtet es ein)"])

    def test_timer(self):
        self.zeilen("aktuell aktuell", "keine noch kein Basis-Update über zenOS")
        self.assertEqual(self.doctor(), ["ok: Basis-Updates: keine ausstehend"], "aktiviert und aktiv: still")
        schreiben(os.path.join(self.ziel, "timer.zenos-basis-gelegenheit.timer"), "disabled")
        schreiben(os.path.join(self.ziel, "timer.zenos-basis-automatik.timer"), "enabled")
        self.assertEqual(self.doctor()[:2], [
            "warnung: zenos-basis-automatik.timer ist aktiviert, läuft aber nicht (sudo systemctl start "
            "zenos-basis-automatik.timer)",
            "warnung: zenos-basis-gelegenheit.timer ist nicht aktiviert (disabled): Basis-Updates kommen nicht "
            "automatisch (install.sh)"])
        schreiben(os.path.join(self.ziel, "aus"), "")
        self.assertEqual(self.doctor()[0], f"hinweis: Basis-Updates nur von Hand: Automatik aus (Notschalter "
                                           f"{self.ziel}/aus, gilt auch für den Kanal)")
        os.unlink(os.path.join(self.ziel, "units", "zenos-basis-automatik.timer"))
        os.unlink(os.path.join(self.ziel, "aus"))
        self.assertEqual(self.doctor()[:2], ["warnung: zenos-basis-automatik.timer fehlt (install.sh)",
                                             "ok: Basis-Updates: keine ausstehend"], "ohne Timer-Datei keine Prüfung")

    def test_ganzer_abschnitt(self):
        r = subprocess.run([BASH, "-c", DOCTOR_RAHMEN], capture_output=True, text=True, check=False,
                           env={"PATH": "/usr/bin:/bin", "DOCTOR": DOCTOR, "ZIEL": self.ziel})
        zeilen = r.stdout.splitlines()
        self.assertEqual(zeilen[0], "abschnitt: Ubuntu-Basis")
        self.assertTrue(zeilen[1].startswith("warnung: Prompt ist"))
        self.assertEqual(zeilen[2], "hinweis: Basis-Updates noch nie geprüft (zen update)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
