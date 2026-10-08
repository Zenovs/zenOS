# Baufortschritt zenOS 0.1

Claude Code führt diese Liste während des Bauauftrags nach. Eine neue Sitzung macht hier weiter.

Status: `offen` · `in Arbeit` · `fertig` · `offener Punkt`

| Modul | Status | Notiz |
|---|---|---|
| M1 · Installer und zen-Werkzeug | fertig | install.sh (idempotent, Module, Log), gemeinsam.sh, zen (update, rollback, doctor, version, benutzer, hilfe), pruefen.sh, Testumgebung `test/container/`. Details: `docs/module/m1.md` |
| M2 · Basis und Sitzung | fertig | Pakete, Quickshell v0.3.1 aus dem Quellcode (Neubau nur bei anderem Commit/Qt), Schriften, greetd mit Quickshell-Greeter (kein Autologin), Sitzung als systemd-Target. Details: `docs/module/m2.md` |
| M3 · Design-Tokens und Theme | fertig | Theme-Singleton aus tokens.json (neue Tokens: linie2, trennlinie, eingabeRand, tasteRand, abgesetzt, schatten), Dienste, Komponenten, shell.qml mit isoliert geladenen Oberflächen, zenos-thema (GTK, Qt über Portal, kitty, labwc, VS Code). Details: `docs/module/m3.md` |
| M4 · Leiste | fertig | Leiste nach Entwurf 2, System-Menü, Hintergrund «Heute». Details: `docs/module/m4.md` |
| M5 · Befehlsfeld | fertig | Apps, Web-Apps, Rechnen (eigener Parser), Dateien, Modi/Zustände, Aktionen; Bildschirmfoto und Pipette. Details: `docs/module/m5.md` |
| M6 · Mitteilungen | fertig | NotificationServer, Bündelung nach Zustand, Zentrale, Leitplanke bei Freigabe. Details: `docs/module/m6.md` |
| M7 · Sperrbildschirm | fertig | ext-session-lock + PAM, swayidle, zen lock (auch per SSH), Marker nach Absturz, Notfall-Sperre mit swaylock, 1Password. Details: `docs/module/m7.md` |
| M8 · Modi und Zustände | fertig | Schemas, zenos-konfig, Modi/Zustände/Leitplanken, Freigabe über xdg-desktop-portal-wlr, Einstellungen mit «Modi & Zustände». Details: `docs/module/m8.md` |
| M9 · Raster und Bildschirme | fertig | zenos-labwc (Regionen, Kürzel, Theme-Teil), zenos-kanshi, Raster-Vorlagen. Details: `docs/module/m9.md` |
| M10 · Terminal | fertig | kitty (Ctrl+C/V, Super-Kürzel), fish mit Statuszeile, «?» offline, Warnung bei gefährlichen Befehlen. Details: `docs/module/m10.md` |
| M11 · Sicherheit | fertig | unattended-upgrades, Chrome-Richtlinien, gitleaks-Hook + CI, ufw (seit `v0.1.0-rc3` standardmässig an). Details: `docs/module/m11.md` |
| M12 · Erster Start | fertig | Einrichtung nach Entwurf 2, Zustimmung, zen apps (Chrome, VS Code, 1Password, CLI, coremail), Web-Apps. Nubix: kein ARM-Build. Details: `docs/module/m12.md` |
| M13 · Argon ONE | fertig | zenos-argon (Lüfterkurve, Power-Button, Abschaltsignal beim Ausschalten), Temperatur in der Leiste. Details: `docs/module/m13.md` |
| M14 · Image-Workflow | fertig | image.yml + image/bauen.sh; Release für jeden gültigen Tag, -rc als Vorabversion (bis rc3 nur Artefakt). Details: `docs/module/m14.md` |
| M15 · Abschluss | fertig | Integration (frische Installation von GitHub, `zen update`, voller Image-Bau, drei Abnahme-Touren, drei Reviews mit Gegenprüfung, 36 Befunde behoben), Doku, ANLEITUNG, CHANGELOG, Tag `v0.1.0-rc1` |
| Bildmarke «Zwei Steine» | fertig | nach Zenos Spezifikation: Dateien in `assets/zeichen/` (erzeugt von `erzeugen.py`), Pfade in tokens.json, `ZenZeichen` statt `Zeichen` in Leiste, Login, Sperre, Befehlsfeld und Erstem Start, Wasserzeichen und Token `wasserzeichen` entfernt, App-Icon `zenos` (45-thema). Details: `docs/bildmarke.md` |
| Bootsplash (Plymouth) | fertig, nicht aktiv | Theme `system/plymouth/zenos/` (Gleiten, Überblenden, atmender Spalt, Passwortfeld, 1x/2x), Modul 42-bootsplash legt es ab, `zen bootsplash` schaltet nach Rückfrage ein, `zen doctor` meldet den Stand. Details: `docs/module/bootsplash.md` |

## Wo gebaut wird

Der Bau lief nicht auf dem Pi, sondern auf dem Mac: Claude Code wurde dort gestartet. Linux-Tests laufen in einem
Docker-Container mit Ubuntu 26.04 arm64 (gleiche Architektur wie der Pi, mit systemd, headless labwc und Quickshell),
siehe `test/container/`. Was nur auf echter Hardware prüfbar ist (Grafik über den Pi-Treiber, greetd auf dem VT,
I2C/GPIO des Argon ONE, Tastatur), ist pro Modul unter «am Pi prüfen» notiert.

## Stand

**Oktober 2026:** Nach `v0.1.0-rc2` kamen der signierte Update-Kanal, Energie, die Systemkennung zenOS und das Image
als eigenständige Distribution (Release-Seite, Quellcode) dazu; `v0.1.0-rc3` ist gebaut (unsigniert, nur Artefakt).
Die Fensterübersicht ist in Arbeit. `v0.1.0-rc4` ist der erste signierte Release-Kandidat (Image-Bau scheiterte, behoben). Nächster
Schritt: `v0.1.0-rc6` (rc5 übersprungen), erstmals mit Release-Seite, als Vorabversion, dann die Abnahme auf echter Hardware und `v0.1.0` (`ROADMAP.md`). Der Rest dieses
Abschnitts beschreibt den Stand von rc1/rc2.

Alle Module sind gebaut und im Container getestet (Ubuntu 26.04 arm64 mit systemd, headless labwc, echte
PAM-/logind-Sitzungen). Die Abnahme auf dem Pi steht aus: `ANLEITUNG.md`, Abschnitte C bis E. Pro Modul steht unter
«Am Pi prüfen» in `docs/module/<modul>.md`, was nur echte Hardware zeigt.

Gemessen im Container (nicht auf dem Pi):
- Frische Installation von GitHub auf nacktem Ubuntu Server 26.04: Exit 0, keine Warnung; zweiter Lauf «0 Änderungen».
  SSH, Netz und Konten unverändert, greetd aktiviert, aber erst nach dem Neustart gestartet.
- `zen update` von GitHub auf ein installiertes System: 5 Änderungen, zweiter Lauf 0; `zen doctor` 0 Fehler.
- Image: `install.sh --image` im Ubuntu-Pi-Image, 1481 MiB mit `xz -9` (72 % der 2-GiB-Grenze), ohne
  SSH-Hostschlüssel, ohne proprietäre Apps, ohne Benutzerdaten. Auf GitHub (Tag `v0.1.0-rc1`) gebaut in 15:29 Minuten,
  1484 MiB, als Workflow-Artefakt (kein Release).
- `scripts/pruefen.sh`: shellcheck, JSON-Schemas, Hex- und sh-c-Regel, rund 300 Einheitentests, qmllint, gitleaks,
  Start-Test der Oberfläche – sauber, auch in der CI auf GitHub.

Abnahme in einer echten VM (lima/Apple Virtualization, Ubuntu 26.04 arm64, virtio-gpu mit Mesa, statt des Pi):
- Installation genau nach ANLEITUNG B–D, Neustart, echter greetd-Login auf VT 7, Einrichtung, echte Installation von
  Chrome 154, VS Code, 1Password, 1Password-CLI und coremail, drei Touren durch die Testliste E.
- 21 bestätigte Befunde, darunter einer hoch (Leitplanke beim Teilen in Chrome kurz aus), alle behoben und in der VM
  nachgeprüft: `zen update` von GitHub (92 Änderungen, zweiter Lauf 0), Freigabe in 1663 empfangenen Bildern aus
  10 Chrome-Sitzungen ohne Mitteilungsinhalt, neue Bildmarke an allen Stellen mit echter Grafik.
- Tag `v0.1.0-rc2` mit Bildmarke und Behebungen; `v0.1.0-rc1` bleibt der Stand des Bauauftrags.

## Entscheidungen während des Baus

- **Gebaut auf dem Mac statt auf dem Pi**, getestet in Docker (`test/container/`). Deshalb führt Zeno `install.sh` auf
  dem Pi selbst aus (ANLEITUNG C); die sudo-Regel aus B12 braucht es nur noch für Nacharbeit mit Claude Code auf dem Pi.
- **Quickshell** fehlt in den Ubuntu-26.04-Paketquellen → Quellbau v0.3.1 (Commit `1a4716c`), fest eingetragen; neu
  gebaut nur bei anderem Commit oder anderer Qt-Version (private Qt-APIs).
- **Schriften** liegen im Repo unter `assets/fonts/` (Geist v1.7.2, Instrument Serif `65c0ef2`, OFL), Quellen und
  Prüfsummen in `assets/fonts/QUELLEN.md`.
- **Git-Identität** im Repo: GitHub-noreply-Adresse, damit keine persönliche E-Mail in öffentliche Commits gelangt.
- **Ubuntu 26.04 hat uutils coreutils und sudo-rs:** `install -D` ersetzt Symlinks im Zielpfad durch Ordner, deshalb
  legt zenOS Elternordner selbst an. Die Testumgebung nutzt sudo-rs wie Ubuntu Server.
- **Dienste starten bei der Paketinstallation nicht** (temporäre policy-rc.d, nur während des eigenen dpkg); greetd
  läuft erst nach dem Neustart, SSH bleibt unberührt. `dbus reload` bleibt erlaubt (polkit).
- **systemd-Benutzereinheiten unter `/etc/systemd/user`**: systemd 259 durchsucht `/etc/xdg/systemd/user` ohne
  `XDG_CONFIG_DIRS` nicht.
- **Logik für Modi und Zustände läuft in Quickshell** (C5-Frage), Anbindung nach aussen über kleine Hilfsprogramme.
- **Notfall-Sperre mit swaylock**, falls die Oberfläche nicht antwortet: Die automatische Sperre darf nie ausfallen.
- **Mitteilungen ohne Zustand gesammelt zur vollen Stunde** (`gebuendelt-60`, «Ruhe ist der Normalzustand»).
- **Tastenkürzel:** Super+Links/Rechts für Hälften, Super+Oben/Unten bleiben für kitty (Entwurf 2: «Super+↑↓ zwischen
  Befehlen»); Super+Enter maximiert.
- **Freigabe:** xdg-desktop-portal-wlr teilt ganze Bildschirme; Label «Dieser Bildschirm wird geteilt».
- **Apps aus der Oberfläche in eigenen systemd-Einheiten**, damit sie einen Neustart der Oberfläche überleben.
- **Ubuntu motd-news und apt-news aus**, VS Code mit `TelemetryLevel` off (Leitplanke «keine Telemetrie»); umkehrbar,
  siehe `docs/sicherheit.md`.
- **Argon-Abschaltsignal** als system-shutdown-Hook wie im Original-Skript (nur bei poweroff/halt, nur mit Argon).
- **Kanal:** Pi und Image folgen `dev`, solange `main` nur den Start-Commit trägt. Überholt: Seit dem signierten
  Kanal folgt das Image dem Kanal seines Tags (`stabil` bzw. `vorschau`), siehe `docs/image-und-releases.md`, «Name,
  Version und Kanal».
- **Tags `v0.1.0-rc1` und `v0.1.0-rc2`** gesetzt, obwohl die Abnahme auf dem Pi aussteht: Die Testliste braucht
  einen Tag für `zen rollback`, und der Workflow baut damit das Image nur als Artefakt, ohne Release. rc2 enthält die
  neue Bildmarke und die Behebungen aus der VM-Abnahme.
- **Neue Bildmarke «Zwei Steine»** nach Zenos Spezifikation (`docs/bildmarke.md`); die Bogen-Wasserzeichen der
  alten Marke sind entfallen. Bootsplash gebaut, aber nicht eingeschaltet (Boot-Kommandozeile = Rückfrage).
- **Login-Bildschirm dunkel nach 1 Minute** (Zenos Entscheid vom 06.10.2026, war ein offener Punkt): am Netzteil wie
  am Akku, die erste Taste, der erste Klick oder die erste Berührung weckt nur und wird verworfen. Gebaut in
  `shell/greeter/Bildschirm.qml` mit wlopm direkt aus dem Login; in der Sitzung bleibt «dunkel heisst gesperrt».
  Ausfallsicher: Was scheitert, lässt den Bildschirm an. Im Container mit `test/container/login-e2e.sh` geprüft, am
  Gerät abzunehmen (`docs/module/energie.md`, «Bildschirm aus am Login-Bildschirm»).

## Offene Punkte für Zeno

- **Bildmarke:** App-Icon mit zwei flacheren Kachelecken in der Referenz (Absicht?), Farbe der Mono-Zeile im
  Vorschaubild (`#8C887F` ist kein Token), Einrichtung 44 px zeigt mit dem Qt-CurveRenderer an den Übergängen Bogen →
  Gerade einzelne harte Pixel (48 px wären glatt), Bootsplash einschalten (`zen bootsplash aktivieren`), Avatar und
  Vorschaubild auf GitHub hochladen.
- **coremail** (eigenes Repo): legt beim ersten Start einen zweiten Starter an; die nötige Änderung steht in
  `docs/module/m12.md`. zenOS entfernt ihn bis dahin.
- **Abnahme auf dem Pi** nach `ANLEITUNG.md` (C bis E). Danach `CHANGELOG.md` ergänzen und `v0.1.0` taggen (G).
- **Temporäre sudo-Regel** `/etc/sudoers.d/zenos-bau` nach der Testphase löschen (G1), falls angelegt.
- **Safe Browsing Stufe 2 oder 1** in Chrome (Zielkonflikt Sicherheit ↔ «keine Telemetrie», `docs/sicherheit.md`).
- **Firewall:** entschieden (Oktober 2026), standardmässig an; Ausschalten nur über den Schalter in den
  Einstellungen mit Passwort oder `zen firewall deaktivieren` (`docs/module/m11.md`). Am Gerät prüfen.
- **Bootsplash einschalten** mit `zen bootsplash aktivieren` (Boot-Kommandozeile, Pakete, initramfs; der Pi startet
  danach zweimal). Bis dahin zeigt `zen doctor` «Bootsplash vorbereitet, nicht aktiv». Prüfliste in
  `docs/module/bootsplash.md`.
- **WLAN-Menü einschalten** mit `zen netzwerk umstellen` und `sudo reboot` am Gerät (NetworkManager statt netplan
  mit systemd-networkd, WPA3 im WLAN-Treiber aus). Rückweg `zen netzwerk zurueck`. Prüfliste in
  `docs/module/netzwerk.md`.
- **Akku messen (Argon ONE UP)** mit `zen akku freigeben`: Erst dann weckt zenos-argon den Akku-Messchip und
  schreibt Argons Akkuprofil (Register und Risiko in `docs/sicherheit.md`). Bis dahin «nicht freigegeben».
- **Akku im Sperrbildschirm:** Die Sperre zeigt heute keinen Akku. Ein kleines Symbol mit Prozent wäre kein Inhalt
  im Sinn der Leitplanke, berührt aber die Sperre (sicherheitskritisch); eigener Schritt nach Zenos Entscheid.
- **GitHub-Avatar und Vorschaubild** von Hand hochladen: `assets/zeichen/png/github-avatar-500.png` und
  `github-social-preview-1280x640.png` (`docs/bildmarke.md`, Abschnitt «GitHub»).
- **`main`** auf `v0.1.0` vorspulen, damit `git clone` ohne `git switch dev` funktioniert (ANLEITUNG G11–G14); danach
  entscheiden, ob Image und neue Installationen `main` folgen.
- **fish als Login-Shell** (`chsh -s /usr/bin/fish`), damit auch SSH-Sitzungen Eingabezeile, `?` und die Warnung haben.
- **Nubix** hat bis v4.4.4 keinen arm64-Build; ein arm64-`.deb` in der Release reicht, `zen apps` bietet es dann an.
- **Widgets** (Zustandswert `widgets`): was sie zeigen sollen, ist offen.
- **Chrome `AutofillCreditCardEnabled`** ist ab Chrome 156 veraltet. Erledigt am 08.10.2026: Die Richtlinie setzt
  zusätzlich den Nachfolger `AutofillSettings` (Kreditkarten auf allen Seiten gesperrt, der Ersatz laut Googles
  Richtlinienliste); die alte bleibt, solange Google sie auswertet. Belege in `docs/sicherheit.md`,
  «Chrome-Richtlinien». Am Gerät prüfen: Chrome-Punkt in ANLEITUNG E (`chrome://policy`, 14 Richtlinien).
- **`esm-cache` von ubuntu-pro-client** fragt bei `apt update` `contracts.canonical.com` ab; abschalten oder lassen.
- **GitHub:** 2FA im Konto prüfen. Erledigt am 08.10.2026 (per `gh`, mit Zenos Ja): Issues aus, Rulesets
  «Release-Tags» (`v*`, `vertrauen/*`: nicht verschieben, nicht löschen, Ausnahme Admin) und «dev und main» (nicht
  löschen, kein Force-Push), unveränderliche Releases an (ANLEITUNG G2 bis G5).
- **Festplattenverschlüsselung und Backups** auf dem Pi sind Ziel, in 0.1 nicht umgesetzt.
- **Name und Marke vor der ersten Weitergabe:** die Markenrecherche zu «zenOS» und bei Canonical schriftlich anfragen
  oder sich auf die Klausel der IPR-Policy zu den Open-Source-Lizenzen stützen (`docs/image-und-releases.md`, «Name
  und Marke»). Seit auch jedes `-rc` eine öffentliche Release-Seite bekommt (Entscheid vom 06.10.2026), ist das schon
  `v0.1.0-rc4`. Entscheid vom 07.10.2026: die Release-Kandidaten erscheinen so, Name und Marke werden vor
  `v0.1.0` geklärt.
- **sudo ohne Passwort von cloud-init:** Hat der Imager den Benutzer angelegt (bis 2.0.10 oder mit
  «passwordlessSudo») oder kam der Benutzer `ubuntu` aus Ubuntus Vorgabe, gibt es eine Regel ohne Passwort
  (`/etc/sudoers.d/90-cloud-init-users`). `zen doctor` warnt dann («sudo geht ohne Passwort»); zenOS ändert sie nicht.
  Entfernen oder lassen.
- **Ein/Aus-Taste am dunklen Login-Bildschirm:** Dort schaltet ein kurzer Druck wie bisher sofort aus (logind). Wer
  den dunklen Login damit wecken will, schaltet aus. Abhilfe wäre ein Hemmer «handle-power-key» im Greeter (berührt
  logind und polkit für `_greetd`, nicht gebaut). Bauen oder lassen.
