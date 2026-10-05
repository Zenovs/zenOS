#!/usr/bin/env python3
"""Einheitentests für den Weg von «zen update» und «zen rollback»: scripts/lib/wechsel.sh (Holen von origin mit
verschobenem Tag, Zeitlimit, Platzprüfung, Sperren), dazu die Prüfungen von zen doctor auf einen Installationslauf
ohne Ende (scripts/doctor.d/00-basis.sh) und auf einen unterbrochenen dpkg-Lauf (dpkg_unterbrochen,
scripts/lib/gemeinsam.sh).

Alles mit Wegwerf-Repos im Temp-Ordner (ein «origin» als blankes Repo, ein Checkout als Ziel), ohne Netz, ohne Root
und ohne /opt/zenos. Die Bibliotheken werden über ein kleines Treiberskript gesourct, das eine Funktion mit
Argumentliste aufruft (keine Shell-Zeichenkette). Die Teile mit Sperren brauchen flock (util-linux) und werden ohne
übersprungen, etwa auf dem Mac.

  python3 test/einheiten/wechsel.test.py
"""

import fcntl
import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WECHSEL = os.path.join(WURZEL, "scripts", "lib", "wechsel.sh")
GEMEINSAM = os.path.join(WURZEL, "scripts", "lib", "gemeinsam.sh")
BASIS = os.path.join(WURZEL, "scripts", "doctor.d", "00-basis.sh")

# Wie scripts/zen: zen_git lesend, Meldungen auf stdout bzw. stderr. Einstellungen der Bibliothek (_WECHSEL_*=WERT)
# stehen vor dem Funktionsnamen und gelten nach dem Sourcen.
TREIBER_WECHSEL = """#!/usr/bin/env bash
set -uo pipefail
ZENOS_CODE=$1
LIB=$2
shift 2
SUDO=""
zen_git() { git -c safe.directory="$ZENOS_CODE" -C "$ZENOS_CODE" "$@"; }
zen_fehler() { printf 'zen: %s\\n' "$*" >&2; }
zen_warnung() { printf 'zen: Warnung: %s\\n' "$*" >&2; }
zen_hinweis() { printf '%s\\n' "$*"; }
source "$LIB" || exit 99
while (( $# > 0 )) && [[ "$1" == _WECHSEL_*=* ]]; do printf -v "${1%%=*}" '%s' "${1#*=}"; shift; done

# Sperre nehmen; danach muss sie belegt sein (ein zweites flock scheitert)
_test_sperre_gehalten() {
  _wechsel_sperren || return 1
  if flock -n "$_WECHSEL_SPERRE" true; then return 2; fi
  return 0
}

# Sperre von install.sh nehmen und wieder freigeben
_test_install_sperre() {
  _wechsel_install_warten || return 1
  if flock -n "$_WECHSEL_INSTALL_SPERRE" true; then return 2; fi
  _wechsel_install_freigeben
  flock -n "$_WECHSEL_INSTALL_SPERRE" true || return 3
}

"$@"
"""

TREIBER_QUELLE = """#!/usr/bin/env bash
set -uo pipefail
source "$1" || exit 99
shift
"$@"
"""

# Ein upload-pack, das nicht antwortet (für das Zeitlimit)
LANGSAM = """#!/usr/bin/env bash
sleep 30
exec git-upload-pack "$@"
"""


def hat_flock():
    return shutil.which("flock") is not None


def git_umgebung():
    umgebung = dict(os.environ)
    # Ohne eigene git-Einstellungen (Signieren, Vorlagen …) und mit neutraler Identität
    umgebung.update({
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.invalid",
        "LC_ALL": "C",
    })
    return umgebung


class Basis(unittest.TestCase):
    def setUp(self):
        self.ordner = tempfile.mkdtemp(prefix="zenos-wechsel-test.")
        self.umgebung = git_umgebung()

    def tearDown(self):
        shutil.rmtree(self.ordner, ignore_errors=True)

    def datei(self, name, inhalt, ausfuehrbar=False):
        pfad = os.path.join(self.ordner, name)
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(inhalt)
        if ausfuehrbar:
            os.chmod(pfad, 0o755)
        return pfad

    def git(self, *argumente, ort=None):
        ergebnis = subprocess.run(["git", *argumente], cwd=ort or self.ordner, env=self.umgebung,
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 0, f"git {' '.join(argumente)}: {ergebnis.stderr}")
        return ergebnis.stdout.strip()


class Holen(Basis):
    """origin als blankes Repo mit Branch dev und Tag v1-rc1, das Ziel als Klon mit allen Tags."""

    def setUp(self):
        super().setUp()
        self.quelle = os.path.join(self.ordner, "quelle")
        self.fern = os.path.join(self.ordner, "fern.git")
        self.ziel = os.path.join(self.ordner, "ziel")
        self.git("init", "-q", "-b", "dev", self.quelle)
        self.commit("a")
        self.git("tag", "-a", "-m", "rc1", "v1-rc1", ort=self.quelle)
        self.erster = self.git("rev-parse", "HEAD", ort=self.quelle)
        self.commit("b")
        self.git("clone", "-q", "--bare", self.quelle, self.fern)
        self.git("clone", "-q", "file://" + self.fern, self.ziel)
        self.git("fetch", "-q", "--tags", "origin", ort=self.ziel)
        self.treiber = self.datei("treiber.sh", TREIBER_WECHSEL)

    def commit(self, text):
        self.git("commit", "-q", "--allow-empty", "-m", text, ort=self.quelle)

    def lauf(self, *argumente):
        return subprocess.run(["bash", self.treiber, self.ziel, WECHSEL, *argumente], env=self.umgebung,
                              capture_output=True, text=True, timeout=60, check=False)

    def tag_commit(self, name, ort=None):
        return self.git("rev-parse", f"refs/tags/{name}^{{commit}}", ort=ort or self.ziel)

    def tag_verschieben(self):
        """v1-rc1 zeigt auf origin danach auf einen neueren Commit (Fall v0.1.0-rc1), dazu ein neuer Tag."""
        self.commit("c")
        self.git("tag", "-f", "-a", "-m", "rc1 verschoben", "v1-rc1", "HEAD", ort=self.quelle)
        self.git("tag", "-a", "-m", "rc2", "v1-rc2", ort=self.quelle)
        self.git("push", "-q", "--force", self.fern, "dev", "refs/tags/*:refs/tags/*", ort=self.quelle)

    def test_alter_weg_bricht_ab(self):
        # Der Fehler, den wechsel.sh umgeht: «git fetch --tags» scheitert am verschobenen Tag, mit --quiet stumm
        self.tag_verschieben()
        ergebnis = subprocess.run(["git", "fetch", "--quiet", "--tags", "--prune", "origin"], cwd=self.ziel,
                                  env=self.umgebung, capture_output=True, text=True, timeout=30, check=False)
        self.assertNotEqual(ergebnis.returncode, 0)

    def test_branch_ohne_tags(self):
        self.tag_verschieben()
        ergebnis = self.lauf("_wechsel_branch_holen")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        self.assertEqual(ergebnis.stderr, "")
        self.assertEqual(self.git("rev-parse", "refs/remotes/origin/dev", ort=self.ziel),
                         self.git("rev-parse", "HEAD", ort=self.quelle))
        # Keine Tags mitgeholt, der alte bleibt
        self.assertEqual(self.git("tag", "-l", "v1-rc2", ort=self.ziel), "")
        self.assertEqual(self.tag_commit("v1-rc1"), self.erster)

    def test_tags_verschoben_nur_warnung(self):
        self.tag_verschieben()
        ergebnis = self.lauf("_wechsel_tags_holen")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        neu = self.git("rev-parse", "--short", "v1-rc1^{commit}", ort=self.quelle)
        self.assertIn(f"zen: Warnung: Tag v1-rc1 wurde auf origin verschoben (dort {neu}, hier {self.erster[:7]}). "
                      "Hier bleibt der alte Stand", ergebnis.stderr)
        self.assertIn(f"Übernehmen: sudo git -C {self.ziel} tag -d v1-rc1, dann noch einmal zen update.",
                      ergebnis.stderr)
        # Nie überschrieben, neue Tags trotzdem da
        self.assertEqual(self.tag_commit("v1-rc1"), self.erster)
        self.assertEqual(self.tag_commit("v1-rc2"), self.git("rev-parse", "HEAD", ort=self.quelle))
        # Ein zweiter Lauf meldet dasselbe, ohne zu scheitern
        ergebnis = self.lauf("_wechsel_tags_holen")
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        self.assertEqual(ergebnis.stderr.count("Warnung:"), 1, ergebnis.stderr)

    def test_tags_ohne_aenderung_still(self):
        ergebnis = self.lauf("_wechsel_tags_holen")
        self.assertEqual((ergebnis.returncode, ergebnis.stdout, ergebnis.stderr), (0, "", ""))

    def test_geloeschter_tag_bleibt(self):
        self.git("push", "-q", self.fern, ":refs/tags/v1-rc1", ort=self.quelle)
        self.assertEqual(self.lauf("_wechsel_branch_holen").returncode, 0)
        self.assertEqual(self.lauf("_wechsel_tags_holen").returncode, 0)
        self.assertEqual(self.tag_commit("v1-rc1"), self.erster)

    def test_origin_weg(self):
        self.git("remote", "set-url", "origin", "file://" + os.path.join(self.ordner, "gibt-es-nicht.git"),
                 ort=self.ziel)
        ergebnis = self.lauf("_wechsel_branch_holen")
        self.assertEqual(ergebnis.returncode, 1)
        self.assertIn("zen: git fetch ist fehlgeschlagen (Exit 128: fatal: ", ergebnis.stderr)
        self.assertIn("Am installierten Stand hat sich nichts geändert.", ergebnis.stderr)
        ergebnis = self.lauf("_wechsel_tags_holen")
        self.assertEqual(ergebnis.returncode, 0)
        self.assertIn("zen: Warnung: Tags von origin nicht geholt (Exit 128: fatal: ", ergebnis.stderr)
        self.assertIn("es gelten die vorhandenen", ergebnis.stderr)

    def test_zeitlimit(self):
        langsam = self.datei("langsam", LANGSAM, ausfuehrbar=True)
        self.git("config", "remote.origin.uploadpack", langsam, ort=self.ziel)
        ergebnis = self.lauf("_WECHSEL_FRIST=2", "_wechsel_branch_holen")
        self.assertEqual(ergebnis.returncode, 1)
        self.assertIn("nach 2 s abgebrochen, Netz langsam oder weg?", ergebnis.stderr)
        ergebnis = self.lauf("_WECHSEL_FRIST=2", "_wechsel_tags_holen")
        self.assertEqual(ergebnis.returncode, 0)
        self.assertIn("Tags von origin nicht geholt (nach 2 s abgebrochen", ergebnis.stderr)

    def test_platz(self):
        ergebnis = self.lauf("_WECHSEL_MIN_FREI_KB=0", "_wechsel_platz", self.ziel)
        self.assertEqual((ergebnis.returncode, ergebnis.stderr), (0, ""))
        ergebnis = self.lauf("_WECHSEL_MIN_FREI_KB=999999999999", "_wechsel_platz", self.ziel)
        self.assertEqual(ergebnis.returncode, 1)
        self.assertRegex(ergebnis.stderr, r"zen: Nur \d+ MB frei unter .*, ein Wechsel braucht mindestens "
                                          r"976562499 MB\. Nichts geändert\.")

    def test_platz_unbekannt(self):
        ergebnis = self.lauf("_wechsel_platz", os.path.join(self.ordner, "gibt-es-nicht"))
        self.assertEqual(ergebnis.returncode, 0)
        self.assertIn("nicht ermittelbar", ergebnis.stderr)


@unittest.skipUnless(hat_flock(), "flock fehlt (util-linux)")
class Sperren(Basis):
    def setUp(self):
        super().setUp()
        self.treiber = self.datei("treiber.sh", TREIBER_WECHSEL)
        self.sperre = os.path.join(self.ordner, "zenos-kanal.lock")
        self.install = os.path.join(self.ordner, "zenos-install.lock")

    def lauf(self, *argumente):
        einstellungen = [f"_WECHSEL_SPERRE={self.sperre}", f"_WECHSEL_INSTALL_SPERRE={self.install}",
                         "_WECHSEL_WARTEN=1"]
        return subprocess.run(["bash", self.treiber, self.ordner, WECHSEL, *einstellungen, *argumente],
                              env=self.umgebung, capture_output=True, text=True, timeout=60, check=False)

    def halten(self, pfad):
        f = open(pfad, "a", encoding="utf-8")  # pylint: disable=consider-using-with
        fcntl.flock(f, fcntl.LOCK_EX)
        self.addCleanup(f.close)
        return f

    def test_sperre_frei(self):
        ergebnis = self.lauf("_test_sperre_gehalten")
        self.assertEqual((ergebnis.returncode, ergebnis.stdout, ergebnis.stderr), (0, "", ""))
        self.assertTrue(os.path.isfile(self.sperre))

    def test_sperre_belegt(self):
        self.halten(self.sperre)
        ergebnis = self.lauf("_wechsel_sperren")
        self.assertEqual(ergebnis.returncode, 1)
        self.assertIn("Ein anderes Update oder Rollback läuft gerade, warte (höchstens 1 Minute)", ergebnis.stdout)
        self.assertIn("ist nach 1 Minute nicht fertig. Nichts geändert.", ergebnis.stderr)

    def test_sperre_wird_frei(self):
        f = self.halten(self.sperre)
        prozess = subprocess.Popen(  # pylint: disable=consider-using-with
            ["bash", self.treiber, self.ordner, WECHSEL, f"_WECHSEL_SPERRE={self.sperre}", "_WECHSEL_WARTEN=20",
             "_wechsel_sperren"], env=self.umgebung, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ausgabe = prozess.stdout.readline()
            self.assertIn("läuft gerade", ausgabe)
            f.close()
            self.assertEqual(prozess.wait(timeout=20), 0)
        finally:
            if prozess.poll() is None:
                prozess.kill()
            prozess.communicate()

    def test_symlink_ohne_sperre(self):
        os.symlink(os.path.join(self.ordner, "ziel"), self.sperre)
        ergebnis = self.lauf("_wechsel_sperren")
        self.assertEqual(ergebnis.returncode, 0)
        self.assertIn("nicht nutzbar, weiter ohne Sperre", ergebnis.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.ordner, "ziel")))

    def test_install_frei(self):
        # Ohne Sperrdatei läuft kein install.sh
        ergebnis = self.lauf("_wechsel_install_warten")
        self.assertEqual((ergebnis.returncode, ergebnis.stdout), (0, ""))
        self.assertFalse(os.path.exists(self.install))
        with open(self.install, "w", encoding="utf-8"):
            pass
        ergebnis = self.lauf("_test_install_sperre")
        self.assertEqual((ergebnis.returncode, ergebnis.stderr), (0, ""))

    def test_install_laeuft(self):
        self.halten(self.install)
        ergebnis = self.lauf("_wechsel_install_warten")
        self.assertEqual(ergebnis.returncode, 1)
        self.assertIn("Eine zenOS-Installation läuft gerade", ergebnis.stdout)
        self.assertIn("Die laufende Installation ist nach 1 Minute nicht fertig. Nichts geändert.", ergebnis.stderr)


class DoctorLog(Basis):
    """_basis_letzter_lauf: letzter Lauf eines Modus im Install-Log."""

    BEGINN = "== Beginn 2026-10-05 08:13:00 · {} · zenOS-Installation"
    ENDE = "== Ende 2026-10-05 08:20:41 · {} · {} · 3 Änderungen · 0 Warnungen"

    def setUp(self):
        super().setUp()
        self.treiber = self.datei("treiber.sh", TREIBER_QUELLE)

    def stand(self, zeilen, modi="normal|image"):
        log = self.datei("install.log", "".join(z + "\n" for z in zeilen))
        ergebnis = subprocess.run(["bash", self.treiber, BASIS, "_basis_letzter_lauf", log, modi],
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(ergebnis.returncode, 0, ergebnis.stderr)
        return ergebnis.stdout.strip()

    def test_vollstaendig(self):
        ende = self.ENDE.format("normal", "ok")
        self.assertEqual(self.stand(["", self.BEGINN.format("normal"), "── 10-code", ende]), ende)

    def test_ohne_ende(self):
        zeilen = [self.BEGINN.format("normal"), self.ENDE.format("normal", "ok"),
                  "== Beginn 2026-10-06 21:04:59 · normal · zenOS-Installation", "── 20-pakete"]
        self.assertEqual(self.stand(zeilen), "offen 2026-10-06 21:04")

    def test_benutzer_danach_verdeckt_nichts(self):
        zeilen = [self.BEGINN.format("normal"), "── 25-quickshell",
                  self.BEGINN.format("benutzer"), self.ENDE.format("benutzer", "ok")]
        self.assertEqual(self.stand(zeilen), "offen 2026-10-05 08:13")
        self.assertEqual(self.stand(zeilen, "benutzer"), self.ENDE.format("benutzer", "ok"))

    def test_neuer_lauf_ersetzt_offenen(self):
        ende = self.ENDE.format("image", "ok")
        zeilen = [self.BEGINN.format("normal"), self.BEGINN.format("image"), ende]
        self.assertEqual(self.stand(zeilen), ende)

    def test_abbruch(self):
        ende = self.ENDE.format("normal", "abbruch (Exit 129)")
        self.assertEqual(self.stand([self.BEGINN.format("normal"), ende]), ende)

    def test_leer(self):
        self.assertEqual(self.stand([]), "")
        self.assertEqual(self.stand(["irgendwas", "== Ende kaputt"]), "")


class Dpkg(Basis):
    def setUp(self):
        super().setUp()
        self.treiber = self.datei("treiber.sh", TREIBER_QUELLE)
        self.updates = os.path.join(self.ordner, "updates")
        os.mkdir(self.updates)

    def unterbrochen(self, ordner=None):
        ergebnis = subprocess.run(["bash", self.treiber, GEMEINSAM, "dpkg_unterbrochen", ordner or self.updates],
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertIn(ergebnis.returncode, (0, 1), ergebnis.stderr)
        return ergebnis.returncode == 0

    def test_leer(self):
        self.assertFalse(self.unterbrochen())

    def test_nur_temp(self):
        self.datei("updates/tmp.i", "")
        self.assertFalse(self.unterbrochen())

    def test_journal(self):
        self.datei("updates/tmp.i", "")
        self.datei("updates/0003", "Package: x\n")
        self.assertTrue(self.unterbrochen())

    def test_ohne_ordner(self):
        self.assertFalse(self.unterbrochen(os.path.join(self.ordner, "gibt-es-nicht")))


if __name__ == "__main__":
    unittest.main()
