# Changelog

Was sich an zenOS ändert, pro Version. Das Format lehnt sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
an; eine Version entspricht einem Tag `v…` im Repo.

## Unveröffentlicht

### Neu

- **Bildmarke «Zwei Steine»:** ein Kiesel, diagonal geteilt; der untere Stein trägt den Akzent des aktiven Modus.
  Alle Dateien in `assets/zeichen/` (Zeichen einfarbig und farbig, Pixel-Variante für 16 px, Schriftzug, App-Icon,
  Favicon, GitHub-Avatar und Vorschaubild), erzeugt von `assets/zeichen/erzeugen.py`. Konstruktion und Regeln in
  `docs/bildmarke.md`, die Pfade in `shell/theme/tokens.json` unter `zeichen`.
- **`ZenZeichen`** zeichnet die Marke in der Oberfläche: Leiste 18 px, Login 48 px, Sperrbildschirm 16 px, Befehlsfeld
  ohne Treffer 32 px, Erster Start 44 px, dazu der Notfall-Login. Bei einem Moduswechsel blendet nur der untere Stein
  über; hell/dunkel wechselt beide Steine im selben Bild.
- **App-Icon `zenos`** im hicolor-Thema des Benutzers, 48 bis 512 px (Modul `45-thema`).
- **Bootsplash (Plymouth), vorbereitet, nicht aktiv:** Theme mit dem Zeichen (die Steine gleiten zusammen, der
  untere blendet zum Akzent, danach atmet der Spalt), Passwortfeld wie in Sperre und Login. Modul `42-bootsplash`
  legt es ab, schaltet es aber nicht ein. `zen bootsplash` zeigt den Stand, `zen bootsplash aktivieren` schaltet nach
  Rückfrage ein (Boot-Kommandozeile, initramfs), `zen bootsplash deaktivieren` nimmt es zurück.

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
