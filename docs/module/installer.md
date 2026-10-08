# zen Installer · heruntergeladene Software installieren

Wunsch (Zeno, Oktober 2026): Software, die als `.deb` aus dem Netz kommt (etwa RustDesk), so einfach installieren wie
auf dem Mac. Doppelklick auf die Datei, ein Fenster zeigt, was kommt, «Installieren», Passwort, fertig. Ubuntu Server
hat dafür nichts (nur `sudo apt install ./datei.deb` im Terminal).

## Ablauf

1. **Öffnen:** Doppelklick in Thunar, ein Download aus Chrome oder Firefox (beide über `xdg-open` bzw. GIO) oder
   «Öffnen mit»: Standard für `application/vnd.debian.binary-package` und `application/x-deb` ist
   `zenos-installer.desktop` (`/etc/xdg/labwc-mimeapps.list`, nur in der zenOS-Sitzung; eine eigene Wahl in
   `~/.config/mimeapps.list` geht vor). In Thunar steht zudem im Kontextmenü einer .deb «Mit zen Installer öffnen»
   (`system/thunar/uca.xml`, 48-ablage). Der Starter ruft `zenos-installer oeffnen %f`: Pfad prüfen (absolut nach
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

## Oberfläche: Fenster «zen Installer»

`shell/installer/Installer.qml` ist Dienst und Fenster zugleich (geladen von `shell.qml`): Phasen, Prozesse, IPC
`installer` und ein `FloatingWindow` wie die Einstellungen (Titel «zen Installer», 640 px breit). Den Inhalt zeichnet
`InstallerInhalt.qml` nach dem, was `installer.js` beschreibt; die Logik ist mit node getestet
(`test/einheiten/installer.test.mjs`). Design: `docs/design.md`, «zen Installer».

1. **Öffnen:** `zenos-installer oeffnen PFAD` → IPC `installer oeffnen PFAD`. Die Oberfläche prüft den Pfad noch
   einmal (absolut, `.deb`, ohne Steuerzeichen) und antwortet `offen`; nicht während der Sperre (`gesperrt`) und der
   Einrichtung (`einrichtung`), denn dort läge das Fenster unsichtbar dahinter. Läuft gerade eine Installation, zeigt
   das Fenster sie (`laeuft`); eine zweite Datei öffnet erst danach (noch einmal doppelklicken). `zenos-installer oeffnen` endet nur bei
   `offen` und `laeuft` mit Exit 0.
2. **Ansehen:** «Wird angesehen …», dann `zenos-installer ansehen PFAD --json` ohne Rechte (aus dem Arbeitsstand,
   `ZENOS_CODE`). Jedes neue Öffnen macht ein laufendes Ansehen ungültig.
3. **Ansicht:** Kopf (Symbol des Pakets, Name aus dem Starter, Zusammenfassung, Paket und Version), Lage («Bereit zum
   Installieren», «Update bereit», «Schon installiert», «Lässt sich nicht installieren» mit dem Grund), Beschreibung,
   Werte (Version mit Zustand, Paket, Herausgeber, Webseite, Platzbedarf, Datei, zusätzliche Pakete, Programme,
   SHA-256) und die Hinweise unter «Beim Installieren». Der Knopf heisst «Installieren», bei einem Update
   «Aktualisieren», bei einem Rückschritt «Ältere Version installieren».
4. **Installieren:** `pkexec /opt/zenos/scripts/bin/zenos-installer-bedienen installieren PFAD SHA256 PLAN`, genau
   mit Pfad, SHA-256 und Plan der Ansicht (fester Pfad: Die polkit-Aktion gilt nur für ihn). Während der Helfer läuft,
   fragt der Dienst alle 1,5 s `zenos-installer status --json` nach der Phase: «Wartet auf dein Passwort …» (solange
   der polkit-Dialog offen ist), «Wartet auf ein laufendes Update …», «Prüft das Paket noch einmal …», «Wird
   installiert …».
5. **Ende:** Der Exit des Helfers zählt, Einzelheiten kommen aus `letzte.json` (nur wenn sie zu genau dieser Datei
   gehört und nach dem Klick entstand). Erfolg: «RustDesk ist installiert», «Du findest es im Befehlsfeld.», Knöpfe
   «Öffnen» (der erste Starter wie im Befehlsfeld in eigener Einheit; kennt die Oberfläche ihn noch nicht, über
   `gio launch /usr/share/applications/…`) und «Fertig». Abgebrochene Passwortabfrage (126): zurück zur Ansicht, ohne
   Meldung. Datei oder Plan geändert (3), Stopp (10) und belegt (75): «Noch einmal ansehen». Sonst «Installation
   gescheitert» mit dem Grund.
6. **Fenster zu:** Während einer Installation läuft sie weiter; an ihrem Ende kommt eine ruhige Mitteilung
   (`notify-send`, App «zen Installer», nach Erfolg mit niedriger Dringlichkeit). Mit offenem Fenster keine
   Mitteilung: Das Fenster sagt es.

IPC `installer`: `oeffnen(pfad)` (siehe oben), `status` (`zu`, `ansehen`, `bereit`, `installiert`, `abgelehnt`,
`fehler`, `laeuft`, `fertig`, `gescheitert`), `schliessen`, `liste` (siehe unten). Installieren geht nur über den Knopf;
IPC startet nie pkexec.
Der Rundgang in `scripts/pruefen.sh` (Teil start) prüft die Pfade, sieht eine selbst gebaute .deb bis «bereit» an,
öffnet sie ein zweites Mal, schliesst und prüft «nicht während der Einrichtung».

## Einstellungen › Apps: Liste und Entfernen

Unter «Über den zen Installer» steht, was über den zen Installer kam (Dienst `shell/dienste/InstallerListe.qml`, Logik
in `installer.js`, Design: `docs/design.md`, «Apps»). `einstellungen oeffnen apps/installer` scrollt dorthin.

1. **Liste:** `zenos-installer liste --json` ohne Rechte (`installiert.json` und der Stand von dpkg). Neu gelesen beim
   Öffnen der Seite, wenn sich `installiert.json` oder `/var/lib/dpkg/status` ändert, alle 15 s, solange die Seite offen
   ist, und nach einer eigenen Entfernung. Je Zeile Name, Paket, Version und seit wann; ging das Paket inzwischen ohne
   den zen Installer, «nicht mehr installiert» (der Knopf heisst dann «Aus der Liste …»).
2. **Entfernen …:** `pkexec /opt/zenos/scripts/bin/zenos-installer-bedienen entfernen PAKET` (polkit
   `org.zenos.installer.entfernen`, `auth_admin` bei jedem Aufruf), nur für ein Paket der Liste, eins zur Zeit, nie
   während der Sperre. Der Knopf zeigt «Wartet …» (Passwort), «Wartet auf ein Update …» bzw. «Wird entfernt …» (Phase
   aus `zenos-installer status --json`, alle 1,5 s). Die Unit läuft weiter, wenn die Einstellungen zugehen.
3. **Rückmeldung** wie bei den Basis-Updates: ein Hinweis nach dem eigenen Klick («Fernzugriff ist entfernt»; bei 3, 10,
   75 und Fehlern eine Warnung mit dem Grund aus `letzte.json`, wenn sie zu genau diesem Paket und diesem Klick gehört),
   keine Mitteilung; abgebrochene Passwortabfrage (126) still.

IPC `installer liste` sagt, was die Liste zeigt (Paketnamen oder `keine`); Entfernen geht nur über den Knopf.

## zen install

`zen install DATEI.deb` öffnet in der Sitzung (Terminal in zenOS, `WAYLAND_DISPLAY` gesetzt) das Fenster, wie ein
Doppelklick. Ohne Sitzung (etwa über SSH) oder mit `--text` zeigt es die Ansicht im Terminal
(`zenos-installer ansehen DATEI --auftrag`: der Text und zuletzt `auftrag SHA256 PLAN`) und installiert erst nach der
Eingabe «ja»: `sudo zenos-installer-bedienen installieren PFAD SHA256 PLAN`. Danach steht der Grund aus `letzte.json`
da (nur wenn er zu dieser Datei und diesem Lauf gehört). Ohne Terminal fragt es nicht und installiert nichts.
`zen install --liste` zeigt, was über den zen Installer kam, `zen install --status` was läuft und das letzte Ergebnis.
Tests: `test/einheiten/zen-install.test.py`.

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
- Einheitentests `test/einheiten/installer.test.py` (selbst gebaute Test-.deb, als Benutzer und als root),
  `zen-install.test.py` und für die Oberfläche `installer.test.mjs` (node).
- Ende zu Ende im Container: `test/container/installer-e2e.sh alle` (echtes systemd, apt und dpkg; Doppelklick über
  `gio open` und `xdg-open` bis ins Fenster, Installieren mit echtem pkexec, «Öffnen», Liste der Einstellungen,
  Entfernen, Ablehnungen, Sperren gegen Kanal und Basis, Stopp, `install.sh` zweimal; siehe
  `test/container/README.md`). xdg-open (Chrome) erkennt den Dateityp unter labwc nur mit `file`; auf Ubuntu Server
  ist es da (ubuntu-standard).

## Rückweg

Siehe Kopf von `scripts/module/76-installer.sh`: die Dateien oben entfernen und die zwei Zeilen für .deb aus
`system/xdg/labwc-mimeapps.list` nehmen. Installierte Software bleibt; entfernen dann mit `sudo apt remove PAKET`.
