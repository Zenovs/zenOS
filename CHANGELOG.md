# Changelog

Was sich an zenOS ändert, pro Version. Das Format lehnt sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
an; eine Version entspricht einem Tag `v…` im Repo.

## Unveröffentlicht

### Neu

- **App-Übersicht:** Ein Klick auf das Zeichen oben links öffnet das Befehlsfeld mit allen installierten Apps
  (Web-Apps eingeschlossen) als Raster aus Kacheln, alphabetisch. Die Karte gleitet vom Zeichen her auf, die
  Kacheln blenden diagonal ein, alles in 200 ms. Pfeiltasten wählen, Enter oder ein Klick startet, Tippen sucht wie
  gewohnt; ein zweiter Klick auf das Zeichen schliesst. Ohne Apps steht dort «Apps installieren». Neu per IPC:
  `zenos-ipc befehlsfeld apps` und `befehlsfeld ansicht`.
- **Akku und Lüfter (Argon ONE UP):** Auf dem Laptop Argon ONE UP mit Compute Module 5 zeigt die Leiste oben rechts
  den Akku mit Prozent, beim Laden mit Blitz; bei höchstens 10 % im Akkubetrieb ruhig in der Warnfarbe. Das
  System-Menü zeigt Akku, Lüfter («aus» oder «Stufe 2 von 4 · 3120 U/min») und CPU-Temperatur. Bei 10 % kommt eine
  ruhige Mitteilung, bei 5 % ersetzt sie eine dringende Karte, die sofort erscheint (ohne Ton); am Netzteil
  verschwindet sie. zenOS fährt nicht selbst herunter. Der Dienst `zenos-argon` erkennt das Gerät und liest den
  Akku-Messchip (Cellwise CW2217). Schläft der Chip, weckt er ihn und lädt Argons Akkuprofil, aber erst nach
  `zen akku freigeben` und nur wenn nötig; danach misst er alle 15 s. Den Lüfter regelt weiter der Kernel.
  `zen akku status`, `zenos-argon --pruefen` und `zen doctor` zeigen den Akku.
- **WLAN-Menü oben rechts:** Das System-Menü zeigt «WLAN» mit Schalter, das verbundene Netz und aufklappbar die
  Netze in Reichweite mit Signal und Schloss. Ein Klick verbindet ein bekanntes Netz, bei einem neuen erscheint ein
  Passwortfeld (Enter verbindet, Esc bricht ab); gespeicherte Netze lassen sich vergessen. Es ist nur eine
  Oberfläche für den NetworkManager von Ubuntu; Passwörter gehen nur über D-Bus an ihn. Netznamen stehen als reiner
  Text da, offene Netze verbinden sich später nur auf Klick. Während einer Bildschirmfreigabe stehen keine
  Netznamen da. Neu per IPC: `zenos-ipc leiste menue wlan`.
- **`zen netzwerk`:** `zen netzwerk umstellen` stellt das Netz einmal von netplan mit systemd-networkd auf
  NetworkManager um: jedes WLAN wird ein eigenes Profil, die alten Dateien werden gesichert, wirksam nach dem
  Neustart (kein `netplan apply`). Auf dem Raspberry Pi schaltet es dabei WPA3 im WLAN-Treiber ab, weil der Chip
  es nicht kann; Mischnetze verbinden über WPA2. `zen netzwerk zurueck` geht ohne Netz zurück, `zen netzwerk
  status` zeigt den Stand, `zen doctor` hat einen Abschnitt «Netz». Ein neues Image stellt beim ersten Start
  selbst um.
- **Scroll-Tempo einstellbar:** Einstellungen → Allgemein → «Scroll-Tempo für Touchpad und Maus» mit «Langsam»,
  «Normal», «Schnell» und «Sehr schnell» (Faktor 0.5, 1, 1.5, 2 für labwc). Die Wahl gilt sofort, ohne Abmelden.
  Gespeichert als `scrollTempo` in `einstellungen.json` (von Hand 0.25 bis 3); ohne Eintrag bleibt alles wie bisher.
- **Ablage:** `~/Ablage` ist der eine Ordner für deine Dateien, ohne vorgegebene Struktur. Ein Knopf mit
  Ordner-Symbol rechts neben dem Raster («4er») und die Aktion «Ablage» im Befehlsfeld öffnen ihn im Dateimanager.
  Downloads, Dokumente, Bilder, Musik und Videos landen dort (`~/.config/user-dirs.dirs`); Ordner wie Downloads oder
  Dokumente legt zenOS nicht an.
- **Bildschirmfotos in `~/Ablage/Screenshots`** (vorher `~/Bilder/Screenshots`). Ein leerer alter Ordner
  verschwindet, einer mit Bildern bleibt, und `install.sh` sagt, wie man sie holt.
- **Dateimanager Thunar** (von Ubuntu, im Image): öffnet Ordner aus dem Befehlsfeld und die Ablage, folgt hell und
  dunkel, ohne Indexer im Hintergrund. Vorher öffneten Ordner in kitty. «Terminal hier öffnen» im Rechtsklick
  startet kitty im Ordner. `zen doctor` prüft Ablage und Dateimanager.
- **Firewall standardmässig an:** `install.sh` (auch `zen update`) schaltet ufw ein: eingehend gesperrt, ausgehend
  offen, SSH nur aus lokalen Netzen. Vorher prüft es, ob jede laufende SSH-Verbindung erlaubt bleibt; sonst bleibt
  die Firewall aus und es warnt. Neue Images starten mit eingeschalteter Firewall.
- **Schalter «Firewall»** in Einstellungen → System. Einschalten geht sofort, Ausschalten nur mit dem Passwort, jedes
  Mal. Wer sie bewusst ausschaltet, behält das: `zen update` lässt sie dann aus (`/var/lib/zenos/firewall`). Solange
  sie aus ist, steht «Firewall · aus» im System-Menü, und `zen doctor` warnt.
- **Passwortdialog für Administratorrechte (polkit-Agent):** Verlangt ein Programm Rechte, die polkit nur nach einer
  Anmeldung gibt, fragt ein ruhiger Dialog nach dem Passwort und zeigt, wofür. Das Passwort geht nur an polkit.
  Während der Sperre gibt es keine Dialoge. Neu per IPC: `zenos-ipc polkit status|agent|abbrechen`.
- **`zen firewall deaktivieren`** schaltet nach der Eingabe «deaktivieren» aus und merkt sich das.
- **App-Leiste am rechten Rand:** Mit der Maus rechts in der Mitte an den Rand fahren und kurz ruhen (300 ms), dann
  gleitet eine schmale Karte mit einem Symbol pro offener App herein, auch über einem Vollbild-Fenster. Ein Klick
  holt die App nach vorne (minimierte kommen zurück), bei der aktiven App mit mehreren Fenstern das nächste. Die
  aktive App trägt einen Punkt im Akzent, mehrere Fenster eine kleine Zahl, beim Zeigen steht der Name daneben.
  Sonst ist am Rand nichts zu sehen; oben und unten und beim Vorbeifahren passiert nichts. Nie während Sperre und
  Einrichtung. Neu per IPC: `zenos-ipc appleiste zeigen|verbergen|status|apps`.

### Geändert

- **Manifest:** «kein eigenes WLAN-Menü» heisst jetzt «kein eigener Netzwerk-Stack»; das WLAN-Menü oben rechts
  bedient nur den NetworkManager von Ubuntu.
- **Netzsymbol in der Leiste** mit Signalstufe: ein bis drei Bögen, die fehlenden blass.
- **`zen update` installiert NetworkManager** (ohne Empfehlungen, also ohne Ubuntus Konnektivitätsprüfung) und lässt
  ihn aus, bis `zen netzwerk umstellen` läuft.
- **Gerätewerte für die Leiste:** `zenos-argon` schreibt `/run/zenos/geraet.json` (Version 1, mit Akku) statt
  `/run/zenos/argon.json`. Der Lüfter steht im System-Menü in einer eigenen Zeile, die CPU-Temperatur ebenso.
- **Natürliches Scrollen** wie auf dem Mac, für Touchpad und Maus (labwc, `rc.xml`).
- **Fenstergrösse leichter ziehen:** Ränder wirken mindestens 16 px breit (vorher 8), Ecken greifen auf 40 px
  entlang jeder Kante (vorher 17).
- **SSH-Regeln der Firewall mit Begrenzung** (`limit` statt `allow`): Je Adresse lässt sie in 30 s fünf neue
  Verbindungen zu und weist die sechste ab. `zen firewall aktivieren` schaltet über denselben Helfer ein wie der Schalter
  (`scripts/bin/zenos-firewall`) und merkt sich «an».
- **Neue Pakete:** `pkexec` (für den Schalter) und `iproute2` (`ss`, für die Prüfung der SSH-Verbindungen; bei Ubuntu
  Server schon dabei).
- **Passwortfelder leeren gründlicher:** Nach dem Weiterreichen bleibt das Getippte auch nicht im
  Rückgängig-Verlauf des Feldes stehen (Login, polkit-Dialog).
- **Alt+Tab grösser und mit App-Symbolen:** Der Fensterwechsler ist so breit wie das Befehlsfeld (720 statt 600 px),
  jede Zeile beginnt mit dem App-Symbol in 40 px (vorher so gross wie die Schrift), Name und Titel in 16 px, mehr
  Abstand. Der Titel fehlt, wenn er nur die App-Kennung wiederholt. Das Verhalten bleibt.

## 0.1.0-rc2 – 2026-09-28

Alles seit `v0.1.0-rc1`: die neue Bildmarke, ein vorbereiteter Bootsplash und die Behebungen aus der Abnahme in einer
VM mit Ubuntu 26.04 arm64 und Chrome 154.

### Neu

- **Bildmarke «Zwei Steine»:** ein Kiesel, diagonal geteilt; der untere Stein trägt den Akzent des aktiven Modus.
  Alle Varianten (einfarbig, farbig, Pixel-Variante für 16 px, Schriftzug, App-Icon, Favicon, GitHub-Avatar,
  Vorschaubild) liegen in `assets/zeichen/`, erzeugt von `erzeugen.py`. Regeln in `docs/bildmarke.md`.
- **`ZenZeichen`** zeigt die Marke in Leiste, Login, Sperrbildschirm, Befehlsfeld (ohne Treffer), Erstem Start und
  Notfall-Login. Bei einem Moduswechsel blendet nur der untere Stein über, hell/dunkel wechselt beide im selben Bild.
  Dazu das App-Icon `zenos` im hicolor-Thema des Benutzers.
- **Bootsplash (Plymouth), vorbereitet, nicht aktiv:** Die Steine gleiten zusammen, der untere blendet zum Akzent,
  danach atmet der Spalt; das Passwortfeld sieht aus wie in Sperre und Login. `zen bootsplash` zeigt den Stand,
  `zen bootsplash aktivieren` schaltet nach Rückfrage ein, `zen bootsplash deaktivieren` nimmt es zurück.

### Behoben

- **Bildschirmfreigabe mit Chrome (Leitplanke):** Beim Klick auf «Teilen» schliesst Chrome die Freigabe seiner
  Vorschau und öffnet sofort eine zweite, ohne Bildschirmwahl. Dazwischen war die Leitplanke 0,6 bis 1,8 s aus, und
  Mitteilungsinhalte konnten ins geteilte Bild gelangen. Jetzt endet eine Freigabe erst nach einem Nachlauf (3 s in
  `zenos-freigabe`, dann 2 s in der Oberfläche), und nur für Freigaben, die vor dem Ende begannen; die Reihenfolge
  entscheidet der Aufrufzeitpunkt. «Sitzung» endet so rund 5 s nach dem Ende der Freigabe, erst dann kommt
  Zurückgehaltenes.
- **Portal beendet:** Die Freigabe wird auch nach `systemctl --user kill` am Portal zurückgesetzt (zusätzlich
  `ExecStartPre` im Drop-in). Vorher blieben Rahmen, Sitzung und Zurückhalten stehen.
- **«Beim Wechsel öffnen: Chrome»** öffnet Chrome im Profil des neuen Modus auch dann, wenn Chrome schon offen ist
  (ein neues Fenster; keins, wenn in diesem Profil schon eines offen ist).
- **Hell/Dunkel:** Hell setzt `color-scheme` jetzt auf `prefer-light` statt `default`. Ein laufendes Chrome wechselt
  so auch von dunkel zurück auf hell (vorher blieb es dunkel). Bestehende Installationen stellen beim nächsten
  Wechsel oder Sitzungsstart selbst um.
- **Mitteilungen:** Dringende Karten lagen über dem System-Menü und fingen dessen Klicks ab. Solange ein Menü der
  Leiste offen ist, treten die Karten auf diesem Bildschirm zurück und kommen danach wieder.
- **Einstellungen:** Eine Änderung während eines laufenden Speicherns (etwa zwei schnelle Klicks auf Farben) ging
  bei Modi, Zuständen, Rastern und Bildschirmen still verloren. Jetzt wird sie danach gespeichert.
- **Erster Start:** Befehlsfeld, Modus- und Zustand-Wahl und Einstellungen öffneten unsichtbar hinter der
  Einrichtung; jetzt bleiben sie zu, bis sie fertig ist. In der Zustimmung liegt der Fokus auf «Installieren», Enter
  genügt. Das Terminal dazu ist höher (bis 64 Zeilen, nie über den Bildschirmrand), und passt die Übersicht nicht,
  zeigt ein Hinweis vor der Frage, wie man zurückblättert (vorher waren die Angaben zu Chrome schon hinausgescrollt).
- **Apps:** Den zweiten, kaputten Starter, den coremail beim ersten Start anlegt, entfernt zenOS (das Befehlsfeld
  zeigte coremail doppelt, der zweite Eintrag startete nichts). Chrome wird Standardbrowser, sofern du nichts anderes
  gewählt hast. Das Befehlsfeld bietet «Apps installieren» nur noch an, wenn die gesuchte App fehlt, sonst «Apps
  verwalten». Fehlt das Programm eines Starters (auch hinter `env NAME=WERT …`), erscheint «Programm nicht gefunden»
  statt still nichts.
- **`zen doctor`** erkennt die temporäre sudo-Regel auch, wenn cloud-init `/etc/sudoers.d` auf 0750 gesetzt hat, und
  meldet den echten letzten Lauf von unattended-upgrades (vorher «✓», auch ohne einen Lauf). Neu warnt es, wenn der
  Login in diesem Boot im Notfall-Modus lief (mit Grund) oder coremail wieder einen kaputten Starter angelegt hat,
  und zeigt, ob Chrome Standardbrowser ist.
- **Installer:** Bricht apt an einem Download ab, steht darunter, dass ein neuer Lauf genügt.
- **Login:** Die Ausgaben des Greeters stehen im Journal (`journalctl -b -t zenos-greeter`), der Grund eines
  Notfall-Logins geht nicht mehr verloren.
- **Terminal:** `?` wählt das Beispiel passend zu den Optionen: `? tar -xzf` zeigt Entpacken statt `tar cf`.
- **Doku:** volle Pfade für `zenos-ipc` und `zenos-thema` (nicht im `PATH`), sicheres DNS in Chrome (von den
  Richtlinien abgeschaltet) und coremail noch ohne `mailto:` beschrieben.

### Bekannte Grenzen

- Beginnt eine Freigabe ohne Bildschirmwahl und ohne eine andere Freigabe in den Sekunden davor (gespeicherte
  Freigabe einer anderen App), können die ersten Bilder weiter Inhalte zeigen. Mit Chrome kam das nicht vor: Dort
  beginnt jede Freigabe mit der Wahl.
- Symbole neu installierter Apps erscheinen im Befehlsfeld erst nach dem nächsten Anmelden.
- Chrome zeichnet seinen eigenen Rahmen, ohne zenOS-Titelzeile und Akzentrand; eingerastet ragt sein Schatten in
  die Lücke. Umstellbar in Chrome, die Entscheidung steht in `ANLEITUNG.md` unter G.

### Entfernt

- Die Platzhalter-Marke «Offene Stelle» (`assets/zeichen-platzhalter.svg`, `Zeichen.qml`), die grossen
  Bogen-Wasserzeichen in Sperre, Login und Erstem Start und das Farb-Token `wasserzeichen`. Der Login zeigt unten nur
  noch das Zeichen, ohne den Text «zenOS».

## 0.1.0-rc1 – 2026-09-28

Erster vollständiger Stand von zenOS 0.1, gebaut nach `BAUAUFTRAG.md`. Getestet in Containern mit Ubuntu 26.04
arm64; die Abnahme auf dem Pi folgt mit `ANLEITUNG.md`. Noch kein Release: Der Tag baut das Image nur als
Workflow-Artefakt.

### Neu

- **M1 · Installer und `zen`:** `scripts/install.sh` richtet alles ein und darf beliebig oft laufen (zweiter Lauf
  «0 Änderungen»), Protokoll unter `/var/log/zenos/install.log`, wartet auf laufende Paketvorgänge. `zen update`,
  `zen rollback <tag>`, `zen doctor` (Prüfbericht ohne Geheimnisse), `zen version`, `zen hilfe`; nach einem Update
  startet die Oberfläche gezielt neu. `scripts/pruefen.sh` prüft das Repo bis zum Start der Oberfläche.
- **M2 · Basis und Sitzung:** labwc, kitty, fish, PipeWire und Portale; Quickshell v0.3.1 aus dem Quellcode (neu
  gebaut nur bei einem neuen Qt). Login über greetd mit einem Greeter im zenOS-Look, ohne Autologin, mit
  Notfall-Login und Hinweis bei abgelaufenem Passwort. Schriften Geist, Geist Mono und Instrument Serif.
- **M3 · Design-Tokens und Theme:** `shell/theme/tokens.json` ist die einzige Quelle für Farben, Schrift, Radien und
  Bewegung. Hell und dunkel (auch nach Tageszeit) mit einem Schalter für Oberfläche, GTK, Qt, kitty, labwc, Chrome
  und VS Code; `zen thema`. Ruhiger Textcursor, der nicht blinkt.
- **M4 · Leiste und «Heute»:** Leiste nach Entwurf 2 mit Modus, Zustand, Raster, Uhrzeit, Mitteilungen,
  Hell/Dunkel und System-Menü (Netz, Ton, 1Password, Temperatur und Lüfter, Sperren, Abmelden, Neustart,
  Ausschalten). Hintergrund «Heute» mit Datum, Gruss und Zusammenfassung.
- **M5 · Befehlsfeld:** `Super + Leertaste` für Apps, Web-Apps, Rechnen, Dateien, Modi, Zustände und Aktionen.
  Werkzeuge Bildschirmfoto (Zwischenablage und `~/Bilder/Screenshots`) und Farbpipette.
- **M6 · Mitteilungen:** Quickshell ist der einzige Mitteilungsdienst. Gesammelt nach Zustand (ohne Zustand zur
  vollen Stunde), Dringendes sofort, Zentrale mit «Jetzt zustellen».
- **M7 · Sperrbildschirm:** ext-session-lock mit PAM; `Super + L`, `zen lock` (auch per SSH), automatisch bei
  Inaktivität und Standby. Bleibt nach einem Absturz gesperrt, Notfall-Sperre mit swaylock; 1Password sperrt mit.
- **M8 · Modi und Zustände:** eigene Modi (Akzent, Chrome-Profil, Apps beim Wechsel, Raster) und Zustände mit den
  Vorlagen Fokus und Sitzung, pro Modus anpassbar. Umschalter mit `Super + M` und `Super + Z`, Einstellungen
  «Modi & Zustände». Die Sitzung startet bei Bildschirmfreigabe von selbst, mit Rahmen und Label.
- **M9 · Raster und Bildschirme:** labwc-Regionen aus `raster/*.json`, Vorlagen Voll, Hälften, 3 Spalten, 4er-Grid
  und Gross + 2. Tastenkürzel für Bereiche, Hälften, Maximieren und den anderen Bildschirm; Bildschirm-Profile mit
  kanshi.
- **M10 · Terminal:** kitty mit schlauem `Ctrl + C`, `Ctrl + V` und Super-Kürzeln; fish mit Eingabezeile und
  Statuszeile pro Befehl. `?` erklärt Befehle offline, gefährliche Befehle brauchen eine Bestätigung. Dazu eza, bat,
  zoxide, fzf und tealdeer.
- **M11 · Sicherheit:** automatische Sicherheitsupdates, Chrome- und VS-Code-Richtlinien, Ubuntu-Nachrichten aus,
  gitleaks als Pre-Commit-Hook und in GitHub Actions. Die Firewall ist vorbereitet, `zen firewall` zeigt und
  schaltet sie ein.
- **M12 · Erster Start:** Einrichtung mit Name, Ort, Erscheinungsbild und erstem Modus. Nach Zustimmung installiert
  `zen apps` Chrome, VS Code, 1Password mit SSH-Agent, die 1Password-CLI und coremail aus den Quellen der
  Hersteller. Web-Apps in den Einstellungen.
- **M13 · Argon ONE:** `zenos-argon` regelt den Lüfter (55, 60, 65 °C) und wertet den Power-Button aus (Doppeltipp
  Neustart, Halten Ausschalten); beim Ausschalten bekommt die Platine das Abschaltsignal. Temperatur und Lüfter in
  der Leiste.
- **M14 · Image:** `image/bauen.sh` und ein Workflow für Tags `v*`: Ubuntu-26.04-Image mit geprüfter Signatur,
  `install.sh --image`, `SHA256SUMS`. Tags mit `-rc` nur als Artefakt, andere als Release.

### Bekannte Grenzen

- **Raster pro Bildschirm:** labwc 0.9 kennt Regionen nur global. Pro Bildschirm-Profil gilt ein Raster für alle
  Bildschirme, auch wenn `bildschirme.json` eines pro Ausgang speichert. Fenster sind nur oben abgerundet.
- **Nubix:** kein ARM-Build bis v4.4.4. `zen apps` bietet es an, sobald es einen gibt.
- **«Danach»:** Kalender und Termine (Leiste, rechte Spalte von «Heute», Auslöser `kalender`), Aufgaben, Wetter und
  Dev-Server fehlen noch. Die Zustandswerte `fenster` und `widgets` werden gespeichert, wirken aber noch nicht.
- **Passwortwechsel** geht nicht im Login (greetd 0.10 kennt kein `pam_chauthtok`), sondern an der Textkonsole.
- **Bildschirmfreigabe ohne Bildschirmwahl** (gespeichertes Token): Dann kündigt nichts die Freigabe vor dem ersten
  Bild an.
- **Am Pi zu prüfen:** Grafik mit GPU und 60 fps, greetd auf dem VT, echte Tastatur, Argon ONE (I2C, GPIO),
  Bildschirmfreigabe mit Chrome. Getestet ist bisher nur im Container, die Punkte stehen in `ANLEITUNG.md` und
  `docs/module/`.
- **Voraussetzung:** Ubuntu 26.04 braucht auf dem Pi 5 einen Bootloader vom 11.02.2025 oder neuer.

### Sicherheit

- **Leitplanken im Code**, nicht abschaltbar: Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen, der
  Sperrbildschirm zeigt nie Inhalte, die automatische Sperre gilt immer (1 bis 15 Minuten).
- Sperre und Login nur über PAM; zenOS fasst kein Passwort an. Prozesse starten mit Argumentlisten, nie über
  `sh -c`.
- **Keine Telemetrie:** 13 Chrome-Richtlinien (darunter 5 Abschaltungen von Telemetrie, nur die 1Password-Erweiterung
  erlaubt), VS Code mit `TelemetryLevel` `off`, motd-news und apt-news aus.
- Proprietäre Apps nur nach Zustimmung, aus den Quellen der Hersteller mit geprüften Schlüsseln, Signaturen und
  Prüfsummen, nie im Image.
- gitleaks prüft jeden Commit und in GitHub Actions den ganzen Verlauf. Die Firewall erlaubt SSH nur aus lokalen
  Netzen und bleibt bis zur Entscheidung aus.
