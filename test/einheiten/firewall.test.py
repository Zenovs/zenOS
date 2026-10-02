#!/usr/bin/env python3
"""Einheitentests für die Firewall: scripts/lib/firewall.sh (bewusster Zustand, Auswertung der ufw-Regeln) und die
Aufrufprüfung von scripts/bin/zenos-firewall.

Ohne ufw, ohne Netz und ohne Root-Rechte: Die Bibliothek wird über ein kleines Treiberskript gesourct, das eine
Funktion mit Argumentliste aufruft (keine Shell-Zeichenkette). Der Helfer wird nur mit falschen Argumenten bzw.
als normaler Benutzer aufgerufen; er ändert dabei nichts.

  python3 test/einheiten/firewall.test.py
"""

import os
import shutil
import subprocess
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.path.join(WURZEL, "scripts", "lib", "firewall.sh")
HELFER = os.path.join(WURZEL, "scripts", "bin", "zenos-firewall")
POLICY = os.path.join(WURZEL, "system", "polkit", "org.zenos.firewall.policy")

TREIBER = """#!/usr/bin/env bash
set -uo pipefail
source "$1" || exit 99
shift
"$@"
"""

KOMMENTAR = "comment=7a656e4f5320535348206c6f6b616c"


def tupel(aktion, netz, proto="tcp", port="22", ziel=None):
    ziel = ziel or ("::/0" if ":" in netz else "0.0.0.0/0")
    return f"### tuple ### {aktion} {proto} {port} {ziel} any {netz} in {KOMMENTAR}"


class FirewallLib(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ordner = tempfile.mkdtemp(prefix="zenos-firewall-test.")
        cls.treiber = os.path.join(cls.ordner, "treiber.sh")
        with open(cls.treiber, "w", encoding="utf-8") as f:
            f.write(TREIBER)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.ordner, ignore_errors=True)

    def lauf(self, *argumente, eingabe=""):
        ergebnis = subprocess.run(["bash", self.treiber, LIB, *argumente], input=eingabe, capture_output=True,
                                  text=True, timeout=30, check=False)
        return ergebnis

    def datei(self, inhalt):
        fd, pfad = tempfile.mkstemp(dir=self.ordner)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(inhalt)
        return pfad

    # --- bewusster Zustand ---------------------------------------------------

    def zustand(self, inhalt):
        pfad = self.datei(inhalt)
        z = self.lauf("_firewall_zustand", pfad)
        s = self.lauf("_firewall_seit", pfad)
        self.assertEqual(z.returncode, 0, z.stderr)
        return z.stdout.strip(), s.stdout.strip()

    def test_zustand_aus(self):
        inhalt = "# zenOS\nzustand=aus\nseit=2026-10-02T14:03:12+02:00\n"
        self.assertEqual(self.zustand(inhalt), ("aus", "2026-10-02T14:03:12+02:00"))

    def test_zustand_an(self):
        self.assertEqual(self.zustand("zustand=an\nseit=2026-10-02T08:00:00+00:00\n")[0], "an")

    def test_zustand_fehlt(self):
        z = self.lauf("_firewall_zustand", os.path.join(self.ordner, "gibt-es-nicht"))
        self.assertEqual((z.returncode, z.stdout), (0, ""))

    def test_zustand_ungueltig_zaehlt_als_standard(self):
        for inhalt in ("zustand=vielleicht\n", "zustand = aus\n", "  zustand=aus\n", "zustand=aus; rm -rf /\n",
                       "zustand=AUS\n", "", "\0\0\0"):
            with self.subTest(inhalt=inhalt):
                self.assertEqual(self.zustand(inhalt)[0], "")

    def test_zustand_letzte_zeile_gilt(self):
        self.assertEqual(self.zustand("zustand=aus\nzustand=an\n")[0], "an")
        self.assertEqual(self.zustand("zustand=an\nzustand=aus  \n")[0], "aus")

    def test_seit_nur_zeitstempel(self):
        self.assertEqual(self.zustand("zustand=aus\nseit=$(id)\n")[1], "")
        self.assertEqual(self.zustand("zustand=aus\nseit=morgen\n")[1], "")

    # --- Auswertung der Regeln -----------------------------------------------

    def auswerten(self, modus, werte, regeln):
        e = self.lauf("_firewall_auswerten", modus, *werte, eingabe="\n".join(regeln) + "\n")
        self.assertEqual(e.returncode, 0, e.stderr)
        return [z for z in e.stdout.splitlines() if z]

    NETZE = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fe80::/10", "fd00::/8"]

    def test_fehlend_limit_und_allow_zaehlen(self):
        regeln = [tupel("limit", "10.0.0.0/8"), tupel("allow", "172.16.0.0/12"), tupel("limit", "fe80::/10")]
        self.assertEqual(self.auswerten("fehlend", self.NETZE, regeln), ["192.168.0.0/16", "fd00::/8"])

    def test_fehlend_andere_regeln_zaehlen_nicht(self):
        regeln = [tupel("deny", "10.0.0.0/8"), tupel("limit", "172.16.0.0/12", proto="udp"),
                  tupel("limit", "192.168.0.0/16", port="2222"), tupel("reject", "fe80::/10")]
        self.assertEqual(self.auswerten("fehlend", self.NETZE, regeln), self.NETZE)

    def test_unbegrenzt(self):
        regeln = [tupel("allow", "10.0.0.0/8"), tupel("limit", "172.16.0.0/12"), tupel("allow", "192.168.0.0/16"),
                  tupel("limit", "192.168.0.0/16")]
        self.assertEqual(self.auswerten("unbegrenzt", self.NETZE, regeln), ["10.0.0.0/8"])

    def test_offen(self):
        regeln = [tupel("limit", n) for n in self.NETZE]
        adressen = ["192.168.1.20", "10.1.2.3", "100.64.1.2", "8.8.8.8", "fe80::1%wlan0", "fd12::5", "2a02:1::1",
                    "::ffff:192.168.1.7", "::ffff:100.64.0.1", "127.0.0.1", "::1", "kaputt"]
        self.assertEqual(self.auswerten("offen", adressen, regeln),
                         ["100.64.1.2", "8.8.8.8", "2a02:1::1", "::ffff:100.64.0.1", "kaputt"])

    def test_offen_ohne_regeln_nur_loopback(self):
        self.assertEqual(self.auswerten("offen", ["127.0.0.1", "192.168.1.2"], []), ["192.168.1.2"])

    def test_unbekannter_modus(self):
        e = self.lauf("_firewall_auswerten", "irgendwas", eingabe="")
        self.assertNotEqual(e.returncode, 0)

    def test_liste(self):
        self.assertEqual(self.lauf("_firewall_liste", "a", "b", "c").stdout, "a, b, c")

    # --- Ports von sshd («sshd -T») ------------------------------------------

    def ports(self, ausgabe):
        e = self.lauf("_firewall_ssh_ports", eingabe=ausgabe)
        self.assertEqual(e.returncode, 0, e.stderr)
        return e.stdout

    def test_ports_standard(self):
        self.assertEqual(self.ports("port 22\naddressfamily any\nlistenaddress [::]:22\nlistenaddress 0.0.0.0:22\n"),
                         "22")

    def test_ports_zweiter_port(self):
        self.assertEqual(self.ports("port 2222\nport 22\nlistenaddress 0.0.0.0:22\n"), "22 2222")

    def test_ports_listenaddress_mit_eigenem_port(self):
        self.assertEqual(self.ports("port 22\nlistenaddress 192.0.2.1:2200\nlistenaddress [::]:22\n"), "22 2200")

    def test_ports_leer_oder_unsinn(self):
        self.assertEqual(self.ports(""), "")
        self.assertEqual(self.ports("port abc\nlistenaddress 0.0.0.0\n"), "")


class FirewallHelfer(unittest.TestCase):
    def lauf(self, *argumente):
        return subprocess.run([HELFER, *argumente], capture_output=True, text=True, timeout=30, check=False,
                              env={"PATH": "/usr/bin:/bin"})

    def test_ausfuehrbar(self):
        self.assertTrue(os.access(HELFER, os.X_OK))

    def test_falsche_aufrufe(self):
        for argumente in ((), ("an",), ("ein", "aus"), ("--hilfe",), ("ein;id",), ("",)):
            with self.subTest(argumente=argumente):
                e = self.lauf(*argumente)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("zenos-firewall:", e.stderr)
                self.assertEqual(e.stdout, "")

    @unittest.skipIf(os.geteuid() == 0, "als root würde der Helfer wirklich schalten")
    def test_nur_als_root(self):
        for modus in ("ein", "aus", "standard", "pruefen"):
            with self.subTest(modus=modus):
                e = self.lauf(modus)
                self.assertEqual(e.returncode, 2, e.stderr)
                self.assertIn("nur als root", e.stderr)


class Policy(unittest.TestCase):
    """polkit-Aktionen: Pfad und Argumente passen zum Helfer, Ausschalten nur mit Passwort, nie aus der Ferne."""

    def test_aktionen(self):
        import xml.etree.ElementTree as ET

        baum = ET.parse(POLICY)
        aktionen = {a.get("id"): a for a in baum.getroot().findall("action")}
        self.assertEqual(set(aktionen), {"org.zenos.firewall.einschalten", "org.zenos.firewall.ausschalten"})
        erwartet = {"org.zenos.firewall.einschalten": ("ein", "yes"), "org.zenos.firewall.ausschalten": ("aus", "auth_admin")}
        for kennung, (argument, aktiv) in erwartet.items():
            with self.subTest(aktion=kennung):
                a = aktionen[kennung]
                notizen = {n.get("key"): n.text for n in a.findall("annotate")}
                self.assertEqual(notizen["org.freedesktop.policykit.exec.path"], "/opt/zenos/scripts/bin/zenos-firewall")
                self.assertEqual(notizen["org.freedesktop.policykit.exec.argv1"], argument)
                vorgaben = a.find("defaults")
                self.assertEqual(vorgaben.find("allow_any").text, "no")
                self.assertEqual(vorgaben.find("allow_inactive").text, "no")
                self.assertEqual(vorgaben.find("allow_active").text, aktiv)
                self.assertTrue(a.find("message").text.strip())


if __name__ == "__main__":
    unittest.main(verbosity=2)
