#!/usr/bin/env python3
"""Einheitentests für scripts/bin/zenos-netzwerk: Umstellung von netplan mit systemd-networkd auf NetworkManager
(ein Profil je WLAN, Probe, Sicherung, Zusatzdateien), zweiter Lauf, Abbrüche ohne Änderung, Rückweg Byte für Byte
und der erste Start eines Images. Alles in einem Testordner (--wurzel), ohne systemctl und udevadm.

Braucht netplan (Paket netplan.io) und python3-yaml, sonst werden die Tests übersprungen (etwa auf dem Mac).
  python3 test/einheiten/netzwerk.test.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROGRAMM = os.path.join(WURZEL, "scripts", "bin", "zenos-netzwerk")

try:
    import yaml  # noqa: F401
    HAT_YAML = True
except ImportError:
    HAT_YAML = False
HAT_NETPLAN = shutil.which("netplan") is not None

# Platzhalter für einen 64-stelligen Hex-Schlüssel (so schreibt ihn der Imager), mit führender Null und wenig
# Entropie, damit gitleaks ihn nicht für ein Geheimnis hält
HEX_PSK = "00" + "a1" * 31

# Neutrale Beispiele (keine echten Netze): wie vom Raspberry Pi Imager über cloud-init und von Hand ergänzt
CLOUD_INIT = """# This file is generated from information provided by the datasource.
network:
    ethernets:
        eth0:
            dhcp4: true
            optional: true
    version: 2
    wifis:
        renderer: networkd
        wlan0:
            access-points:
                Beispielnetz:
                    password: HEXPSK
            dhcp4: true
            optional: true
            regulatory-domain: DE
""".replace("HEXPSK", HEX_PSK)
VON_HAND = """network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      optional: true
      access-points:
        "0815":
          password: "platzhalter-eins"
        "Telefon":
          auth:
            key-management: psk
            password: "platzhalter-zwei"
        "Offenes Netz": {}
"""


def roh_laden(text):
    """YAML mit allen Werten als Text (prüft, dass nichts zur Zahl wurde)."""
    import yaml as y
    return y.load(text, Loader=y.BaseLoader)


@unittest.skipUnless(HAT_NETPLAN and HAT_YAML, "netplan oder python3-yaml fehlt")
class Netzwerk(unittest.TestCase):
    def setUp(self):
        self.wurzel = tempfile.mkdtemp(prefix="zenos-netzwerk-test-")
        self.addCleanup(shutil.rmtree, self.wurzel, True)
        self.netplan = os.path.join(self.wurzel, "etc", "netplan")
        os.makedirs(self.netplan)
        os.makedirs(os.path.join(self.wurzel, "usr", "sbin"))
        open(os.path.join(self.wurzel, "usr", "sbin", "NetworkManager"), "w").close()
        open(os.path.join(self.wurzel, "usr", "sbin", "wpa_supplicant"), "w").close()

    # --- Hilfen ---

    def datei(self, relativ, inhalt, modus=0o600):
        pfad = os.path.join(self.wurzel, relativ)
        os.makedirs(os.path.dirname(pfad), exist_ok=True)
        with open(pfad, "w", encoding="utf-8") as f:
            f.write(inhalt)
        os.chmod(pfad, modus)
        return pfad

    def geraet(self):
        self.datei("etc/netplan/50-cloud-init.yaml", CLOUD_INIT)
        self.datei("etc/netplan/60-wlan.yaml", VON_HAND)

    def aufruf(self, *argumente):
        return subprocess.run([sys.executable, PROGRAMM, *argumente, "--wurzel", self.wurzel],
                              capture_output=True, text=True, timeout=120, check=False)

    def stand(self):
        """Alle Dateien unter der Wurzel mit Inhalt und Modus (ohne usr/)."""
        ergebnis = {}
        for ordner, _, dateien in os.walk(self.wurzel):
            for name in dateien:
                pfad = os.path.join(ordner, name)
                relativ = os.path.relpath(pfad, self.wurzel)
                if relativ.startswith("usr/"):
                    continue
                with open(pfad, "rb") as f:
                    ergebnis[relativ] = (f.read(), os.stat(pfad).st_mode & 0o777)
        return ergebnis

    def netplan_dateien(self):
        return sorted(os.listdir(self.netplan))

    def erzeugen(self):
        """netplan generate über den neuen Stand: Profile für NetworkManager und Dateien für systemd-networkd."""
        r = subprocess.run(["netplan", "generate", "--root-dir", self.wurzel], capture_output=True, text=True,
                           timeout=120, check=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        nm = os.path.join(self.wurzel, "run", "NetworkManager", "system-connections")
        nd = os.path.join(self.wurzel, "run", "systemd", "network")
        return (sorted(os.listdir(nm)) if os.path.isdir(nm) else [],
                sorted(os.listdir(nd)) if os.path.isdir(nd) else [])

    # --- Tests ---

    def test_umstellen_ein_profil_je_wlan(self):
        self.geraet()
        r = self.aufruf("umstellen")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        dateien = self.netplan_dateien()
        self.assertIn("90-zenos-netzwerk.yaml", dateien)
        profile = [d for d in dateien if d.startswith("90-NM-")]
        self.assertEqual(len(profile), 4)
        self.assertNotIn("50-cloud-init.yaml", dateien)
        self.assertNotIn("60-wlan.yaml", dateien)
        for name in dateien:
            self.assertEqual(os.stat(os.path.join(self.netplan, name)).st_mode & 0o777, 0o600, name)

        # Jede Datei ein Netz, eigene Definition ohne Gerätebindung, Name = SSID
        namen = {}
        for name in profile:
            with open(os.path.join(self.netplan, name), encoding="utf-8") as f:
                daten = roh_laden(f.read())["network"]["wifis"]
            (kennung, definition), = daten.items()
            self.assertTrue(kennung.startswith("NM-"))
            self.assertEqual(definition["renderer"], "NetworkManager")
            self.assertEqual(definition["match"], {})
            self.assertEqual(definition["dhcp4"], "true")
            (ssid, zugang), = definition["access-points"].items()
            self.assertEqual(definition["networkmanager"]["name"], ssid)
            namen[ssid] = zugang
        self.assertEqual(sorted(namen), ["0815", "Beispielnetz", "Offenes Netz", "Telefon"])
        # Hex-PSK bleibt Text mit führender Null, die SSID «0815» bleibt «0815»
        self.assertEqual(namen["Beispielnetz"]["auth"]["password"],
                         HEX_PSK)
        self.assertEqual(namen["0815"]["auth"], {"key-management": "psk", "password": "platzhalter-eins"})
        self.assertNotIn("auth", namen["Offenes Netz"])

        with open(os.path.join(self.netplan, "90-zenos-netzwerk.yaml"), encoding="utf-8") as f:
            ziel = roh_laden(f.read())["network"]
        self.assertEqual(ziel["renderer"], "NetworkManager")
        self.assertEqual(ziel["ethernets"]["eth0"]["renderer"], "NetworkManager")
        self.assertNotIn("wifis", ziel)

        # Land und Sicherung
        with open(os.path.join(self.wurzel, "etc/xdg/zenos/wlan-land"), encoding="utf-8") as f:
            self.assertIn("LAND=DE\n", f.read())
        sicherung = os.path.join(self.wurzel, "var/lib/zenos/netplan-vorher")
        self.assertEqual(os.stat(sicherung).st_mode & 0o777, 0o700)
        (stand,) = os.listdir(sicherung)
        with open(os.path.join(sicherung, stand, "zenos.json"), encoding="utf-8") as f:
            info = json.load(f)
        self.assertEqual(info["alt"], ["50-cloud-init.yaml", "60-wlan.yaml"])
        self.assertEqual(info["land"], "DE")
        self.assertIn("etc/xdg/zenos/wlan-land", info["angelegt"])
        self.assertIn("systemctl enable", r.stdout)

        # netplan erzeugt daraus nur Profile für NetworkManager (4 WLANs, 1 Kabel), nichts für systemd-networkd
        nm, nd = self.erzeugen()
        self.assertEqual(len(nm), 5)
        self.assertEqual(nd, [])

    def test_zweiter_lauf_aendert_nichts(self):
        self.geraet()
        self.assertEqual(self.aufruf("umstellen").returncode, 0)
        vorher = self.stand()
        r = self.aufruf("umstellen")
        self.assertEqual(r.returncode, 0)
        self.assertIn("Schon umgestellt", r.stdout)
        self.assertEqual(self.stand(), vorher)

    def test_plan_aendert_nichts(self):
        self.geraet()
        vorher = self.stand()
        r = self.aufruf("plan")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Telefon", r.stdout)
        self.assertIn("WLAN-Land DE", r.stdout)
        self.assertNotIn("platzhalter", r.stdout)
        self.assertEqual(self.stand(), vorher)

    def assertAbbruch(self, teil):
        vorher = self.stand()
        r = self.aufruf("umstellen")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("nichts geändert", r.stderr)
        self.assertIn(teil, r.stderr)
        self.assertEqual(self.stand(), vorher)

    def test_unbekannter_typ_bricht_ab(self):
        self.geraet()
        self.datei("etc/netplan/70-bond.yaml", "network:\n  version: 2\n  bonds:\n    bond0:\n"
                   "      interfaces: [eth0]\n")
        self.assertAbbruch("bonds")

    def test_unternehmens_wlan_bricht_ab(self):
        self.datei("etc/netplan/60-wlan.yaml", """network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "Firma":
          auth:
            key-management: eap
            method: peap
            identity: "beispiel"
            password: "platzhalter"
""")
        self.assertAbbruch("Unternehmens-WLAN")

    def test_mehrere_laender_brechen_ab(self):
        self.geraet()
        self.datei("etc/netplan/70-zweites.yaml", "network:\n  version: 2\n  wifis:\n    wlan1:\n"
                   "      regulatory-domain: FR\n      access-points:\n        Zweites:\n"
                   "          password: platzhalter-drei\n")
        self.assertAbbruch("mehrere WLAN-Länder")

    def test_ohne_networkmanager_bricht_ab(self):
        self.geraet()
        os.unlink(os.path.join(self.wurzel, "usr", "sbin", "NetworkManager"))
        self.assertAbbruch("NetworkManager ist nicht installiert")

    def test_ohne_wpa_supplicant_bricht_ab(self):
        self.geraet()
        os.unlink(os.path.join(self.wurzel, "usr", "sbin", "wpa_supplicant"))
        self.assertAbbruch("wpa_supplicant fehlt")

    def test_zurueck_byte_fuer_byte(self):
        self.geraet()
        # Raspberry Pi mit cloud-init: WPA3-Option und cloud-init-Datei kommen dazu und gehen wieder
        self.datei("proc/device-tree/model", "Raspberry Pi Compute Module 5 Lite Rev 1.0\0", 0o644)
        os.makedirs(os.path.join(self.wurzel, "etc/cloud/cloud.cfg.d"))
        vorher = self.stand()
        self.assertEqual(self.aufruf("umstellen").returncode, 0)
        with open(os.path.join(self.wurzel, "etc/modprobe.d/zenos-brcmfmac.conf"), encoding="utf-8") as f:
            self.assertIn("options brcmfmac feature_disable=0x2082000\n", f.read())
        with open(os.path.join(self.wurzel, "etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg"), encoding="utf-8") as f:
            self.assertIn("network: {config: disabled}\n", f.read())
        # Später im Menü angelegtes Netz (NetworkManager schreibt es selbst)
        self.datei("etc/netplan/90-NM-11111111-2222-3333-4444-555555555555.yaml", "network:\n  version: 2\n")

        r = self.aufruf("zurueck")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("systemctl disable", r.stdout)
        nachher = {k: v for k, v in self.stand().items() if not k.startswith("var/lib/zenos/")}
        self.assertEqual(nachher, vorher)
        # Die Dateien von NetworkManager liegen in der Sicherung
        sicherung = os.path.join(self.wurzel, "var/lib/zenos/netplan-vorher")
        (stand,) = os.listdir(sicherung)
        (spaeter,) = [n for n in os.listdir(os.path.join(sicherung, stand)) if n.startswith("nachher-")]
        verschoben = os.listdir(os.path.join(sicherung, stand, spaeter))
        self.assertIn("90-zenos-netzwerk.yaml", verschoben)
        self.assertEqual(len([n for n in verschoben if n.startswith("90-NM-")]), 5)

        # Danach erzeugt netplan wieder die Dateien für systemd-networkd
        nm, nd = self.erzeugen()
        self.assertEqual(nm, [])
        self.assertIn("10-netplan-wlan0.network", nd)

        # Zweites «zurueck»: nichts zu tun
        r = self.aufruf("zurueck")
        self.assertEqual(r.returncode, 0)
        self.assertIn("Nicht umgestellt", r.stdout)

    def test_erststart_einmal(self):
        self.datei("etc/netplan/50-cloud-init.yaml", CLOUD_INIT)
        marke = self.datei("var/lib/zenos/netzwerk-erststart", "# Marke\n", 0o644)
        r = self.aufruf("erststart")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(os.path.exists(marke))
        self.assertIn("90-zenos-netzwerk.yaml", self.netplan_dateien())
        self.assertIn("netplan generate", r.stdout)
        vorher = self.stand()
        # Ohne Marke nichts mehr
        r = self.aufruf("erststart")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")
        self.assertEqual(self.stand(), vorher)

    def test_erststart_scheitert_ohne_aenderung(self):
        self.datei("etc/netplan/50-cloud-init.yaml", CLOUD_INIT)
        self.datei("etc/netplan/70-bond.yaml", "network:\n  version: 2\n  bonds:\n    bond0:\n"
                   "      interfaces: [eth0]\n")
        marke = self.datei("var/lib/zenos/netzwerk-erststart", "# Marke\n", 0o644)
        vorher = {k: v for k, v in self.stand().items() if k != "var/lib/zenos/netzwerk-erststart"}
        r = self.aufruf("erststart")
        self.assertEqual(r.returncode, 1)
        self.assertIn("bleibt bei systemd-networkd", r.stdout)
        # NetworkManager (im Image aktiviert) bleibt ab dem nächsten Start aus
        self.assertIn("systemctl disable --quiet NetworkManager.service NetworkManager-wait-online.service", r.stdout)
        # Marke weg (kein zweiter Versuch), sonst unverändert
        self.assertFalse(os.path.exists(marke))
        self.assertEqual(self.stand(), vorher)

    def test_status_ohne_root(self):
        self.geraet()
        r = self.aufruf("status")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("nicht umgestellt", r.stdout)
        self.assertNotIn("platzhalter", r.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=1)
