# zen Installer · heruntergeladene Software installieren

Wunsch (Zeno, Oktober 2026): Software, die als `.deb` aus dem Netz kommt (etwa RustDesk), so einfach installieren wie
auf dem Mac. Doppelklick auf die Datei, ein Fenster zeigt, was kommt, «Installieren», Passwort, fertig. Ubuntu Server
hat dafür nichts (nur `sudo apt install ./datei.deb` im Terminal).

## Ablauf

1. **Öffnen:** Doppelklick in Thunar, ein Download aus Chrome oder Firefox (beide über `xdg-open` bzw. GIO) oder
   «Öffnen mit»: Standard für `application/vnd.debian.binary-package` und `application/x-deb` ist
   `zenos-installer.desktop` (`/etc/xdg/labwc-mimeapps.list`, nur in der zenOS-Sitzung; eine eigene Wahl in
   `~/.config/mimeapps.list` geht vor). Der Starter ruft `zenos-installer oeffnen %f`: Pfad prüfen (absolut nach
   `realpath`, ohne Steuerzeichen, Endung `.deb`, vorhanden) und als Argument an die Oberfläche geben
   (`zenos-ipc installer oeffnen PFAD`).
2. **Ansehen, ohne Rechte:** `zenos-installer ansehen PFAD --json` liest das Paket nur: `dpkg-deb --ctrl-tarfile` und
   `--fsys-tarfile` als Datenstrom in Pythons `tarfile`, nichts wird entpackt oder ausgeführt. Daraus: Name, Version,
   Architektur, Herausgeber (Maintainer), Webseite, Beschreibung, Platzbedarf, die sichtbaren Starter (Name deutsch,
   wenn vorhanden) und das Symbol (PNG zwischen 64 und 256 Pixeln vor dem grössten PNG vor SVG; nach
   `$XDG_RUNTIME_DIR/zenos-installer/`, 0700). Dazu der Zustand (neu, Update, Rückschritt, gleich), die Simulation
   `apt-get -s install PFAD` (zusätzliche Pakete, Entfernungen), die SHA-256 der Datei und der **Plan**: ein Hash über
   Hauptpaket, Zustand und die Namen aller Pakete, die apt installieren oder entfernen würde.
3. **Hinweise** (ruhig, Stufe «hinweis»; nur Entfernungen sind eine «warnung»): eigene Skripte als root (preinst,
   postinst …), Systemdienste (Units in `/lib`, `/usr/lib` oder `/etc/systemd/system`, `/etc/init.d`, oder ein postinst,
   der `systemctl` und Verwandte ruft), Dienste für die Sitzung, Autostart, Paketquellen (`sources.list.d`,
   Schlüsselbunde, oder ein Skript, das `/etc/apt` anfasst), setuid/setgid, Dateien ausserhalb von `/usr` und `/opt`
   (`/lib`, `/bin` … zählen wegen merged `/usr` wie `/usr`), Kernel-Module und DKMS, Rechte (sudoers, polkit-Regeln,
   PAM, `/etc/security`), ersetzt ein Paket, das nicht über den zen Installer kam, Rückschritt.
4. **Ablehnen:** grösser als 2 GiB, ohne Endung `.deb`, gehört nicht dir, beschädigt (dpkg-deb oder tar scheitern,
   ungültige Pfade oder Felder), falsche Architektur (nur `dpkg --print-architecture` oder `all`), `Essential: yes`,
   ein Name, den schon ein Teil von zenOS oder Ubuntu trägt (Liste aus `scripts/lib/aufraeumen.sh` wie bei
   `zenos-basis`, dazu `scripts/pakete/*.txt`), Abhängigkeiten, die apt nicht erfüllen kann, und jede Entfernung eines
   geschützten Pakets. Geschützt beim Entfernen ist zusätzlich alles manuell Installierte, ausser es kam selbst über
   den zen Installer.
5. **Installieren:** `pkexec /opt/zenos/scripts/bin/zenos-installer-bedienen installieren PFAD SHA256 PLAN` (polkit
   `org.zenos.installer.installieren`, `auth_admin` bei jedem Aufruf). Der Helfer prüft die Argumente streng und ruft
   `zenos-installer auftrag-installieren` (root-eigene Kopie). Das öffnet die Datei als der aufrufende Benutzer
   (`PKEXEC_UID`, effektiv mit seinen Gruppen: Er muss sie lesen können), ohne Verweis am Ende, nur eine reguläre
   Datei, die ihm gehört, höchstens 2 GiB. Es kopiert sie nach `/var/lib/zenos/installer/ablage/SHA256.deb` (root,
   0644) und prüft unterwegs die SHA-256: Hat sich die Datei seit dem Ansehen geändert, Exit 3. Dann
   `zenos-installer-installieren@SHA256.service`: gemeinsame Sperre mit Kanal und Basis
   (`/run/zenos-sperre/kanal.lock`, kein `install.sh` von Hand, kein anderer Paketvorgang; höchstens 20 Minuten
   Warten, sonst Exit 75), Sperre der Paketlisten (kein `apt-get update` dazwischen), dpkg nicht unterbrochen, noch
   einmal auswerten. Nur wenn das Ergebnis «bereit» ist und der Plan gleich blieb: `apt-get install -y` mit
   `DEBIAN_FRONTEND=noninteractive`, confdef und confold, ohne autoremove (bei einem Rückschritt mit
   `--allow-downgrades`), unter einem Block-Inhibitor. Danach: `installiert.json`, `letzte.json` (mit den Startern
   für «Öffnen»), Log, Ablage leer.
6. **Entfernen:** `zenos-installer-bedienen entfernen PAKET` (polkit `org.zenos.installer.entfernen`, `auth_admin`)
   startet `zenos-installer-entfernen@PAKET.service` (Instanz maskiert wie `systemd-escape`): nur Pakete aus
   `installiert.json`, nie ein geschütztes, und nur, wenn `apt-get -s remove` nichts anderes entfernte. Dann
   `apt-get remove` ohne purge (die Konfiguration bleibt).

`zen install` im Terminal (ohne Oberfläche) nutzt dieselben Teile: `zenos-installer ansehen` für die Ansicht,
`sudo zenos-installer-bedienen installieren …` nach «ja».

## Dateien

| Pfad | Inhalt |
|---|---|
| `/usr/local/libexec/zenos/zenos-installer` | root-eigene Kopie des Programms (Modul `76-installer`) |
| `/etc/systemd/system/zenos-installer-installieren@.service`, `…-entfernen@.service` | statische Units |
| `/usr/share/polkit-1/actions/org.zenos.installer.policy` | zwei Aktionen, jedes Mal mit Passwort |
| `/usr/local/share/applications/zenos-installer.desktop` | Starter (NoDisplay, MimeType für .deb) |
| `/var/lib/zenos/installer/installiert.json` | was über den zen Installer kam (root, 0644) |
| `/var/lib/zenos/installer/letzte.json` | Ergebnis der letzten Installation oder Entfernung |
| `/var/lib/zenos/installer/ablage/` | die Datei, solange eine Installation läuft; Reste nach einer Stunde weg |
| `/run/zenos-installer/laeuft-PID.json` | was gerade läuft (für die Oberfläche) |
| `/var/log/zenos/installer.log` | Paketstand vorher und nachher, Exit von apt (root, 0640, Gruppe adm) |

## Sicherheit und Restrisiko

Ein fremdes `.deb` läuft bei der Installation als root: Seine Skripte können alles. Der zen Installer verhindert das
nicht, er zeigt es (Hinweise) und verlangt jedes Mal das Passwort, gebunden an genau die angezeigte Datei und den
angezeigten Plan. Bringt ein Paket eine eigene Paketquelle mit (Chrome, VS Code, viele andere), kommen seine Updates
danach mit den Basis-Updates (`zenos-basis`). Texte aus dem Paket (Name, Beschreibung, Herausgeber) sind nicht
vertrauenswürdig: Das Programm entfernt Steuerzeichen und kürzt sie, die Oberfläche zeigt sie nur als reinen Text.

## Prüfen

- `zen doctor`, Abschnitt «zen Installer»: eingerichtet, Standard für .deb, Ablage leer, letztes Ergebnis.
- Einheitentests `test/einheiten/installer.test.py` (selbst gebaute Test-.deb, als Benutzer und als root).
- Ende zu Ende im Container: `test/container/installer-e2e.sh alle` (echtes systemd, apt und dpkg, über sudo).

## Rückweg

Siehe Kopf von `scripts/module/76-installer.sh`: die Dateien oben entfernen und die zwei Zeilen für .deb aus
`system/xdg/labwc-mimeapps.list` nehmen. Installierte Software bleibt; entfernen dann mit `sudo apt remove PAKET`.
