# Baufortschritt zenOS 0.1

Claude Code führt diese Liste während des Bauauftrags nach. Eine neue Sitzung macht hier weiter.

Status: `offen` · `in Arbeit` · `fertig` · `offener Punkt`

| Modul | Status | Notiz |
|---|---|---|
| M1 · Installer und zen-Werkzeug | fertig | install.sh (idempotent, Module, Log), gemeinsam.sh, zen (update, rollback, doctor, version, benutzer, hilfe), pruefen.sh, Testumgebung `test/container/`. Details: `docs/module/m1.md` |
| M2 · Basis und Sitzung | fertig | Pakete, Quickshell v0.3.1 aus dem Quellcode (Neubau nur bei anderem Commit/Qt), Schriften, greetd mit Quickshell-Greeter (kein Autologin), Sitzung als systemd-Target. Details: `docs/module/m2.md` |
| M3 · Design-Tokens und Theme | fertig | Theme-Singleton aus tokens.json (neue Tokens: linie2, trennlinie, eingabeRand, tasteRand, abgesetzt, wasserzeichen, schatten), Dienste, Komponenten, shell.qml mit isoliert geladenen Oberflächen, zenos-thema (GTK, Qt über Portal, kitty, labwc, VS Code). Details: `docs/module/m3.md` |
| M4 · Leiste | fertig | Leiste nach Entwurf 2, System-Menü, Hintergrund «Heute». Details: `docs/module/m4.md` |
| M5 · Befehlsfeld | fertig | Apps, Web-Apps, Rechnen (eigener Parser), Dateien, Modi/Zustände, Aktionen; Bildschirmfoto und Pipette. Details: `docs/module/m5.md` |
| M6 · Mitteilungen | fertig | NotificationServer, Bündelung nach Zustand, Zentrale, Leitplanke bei Freigabe. Details: `docs/module/m6.md` |
| M7 · Sperrbildschirm | fertig | ext-session-lock + PAM, swayidle, zen lock (auch per SSH), Marker nach Absturz, Notfall-Sperre mit swaylock, 1Password. Details: `docs/module/m7.md` |
| M8 · Modi und Zustände | fertig | Schemas, zenos-konfig, Modi/Zustände/Leitplanken, Freigabe über xdg-desktop-portal-wlr, Einstellungen mit «Modi & Zustände». Details: `docs/module/m8.md` |
| M9 · Raster und Bildschirme | fertig | zenos-labwc (Regionen, Kürzel, Theme-Teil), zenos-kanshi, Raster-Vorlagen. Details: `docs/module/m9.md` |
| M10 · Terminal | fertig | kitty (Ctrl+C/V, Super-Kürzel), fish mit Statuszeile, «?» offline, Warnung bei gefährlichen Befehlen. Details: `docs/module/m10.md` |
| M11 · Sicherheit | fertig | unattended-upgrades, Chrome-Richtlinien, gitleaks-Hook + CI, ufw vorbereitet (nicht aktiv). Details: `docs/module/m11.md` |
| M12 · Erster Start | fertig | Einrichtung nach Entwurf 2, Zustimmung, zen apps (Chrome, VS Code, 1Password, CLI, coremail), Web-Apps. Nubix: kein ARM-Build. Details: `docs/module/m12.md` |
| M13 · Argon ONE | fertig | zenos-argon (Lüfterkurve, Power-Button), Temperatur in der Leiste. Details: `docs/module/m13.md` |
| M14 · Image-Workflow | fertig | image.yml + image/bauen.sh; -rc-Tags nur Artefakt. Details: `docs/module/m14.md` |
| M15 · Abschluss | in Arbeit | Nacharbeit zwischen Modulen, Integrationstest (frische Installation von GitHub, Image-Bau), Reviews |

## Wo gebaut wird

Der Bau lief nicht auf dem Pi, sondern auf dem Mac: Claude Code wurde dort gestartet. Linux-Tests laufen in einem
Docker-Container mit Ubuntu 26.04 arm64 (gleiche Architektur wie der Pi, mit systemd, headless labwc und Quickshell),
siehe `test/container/`. Was nur auf echter Hardware prüfbar ist (Grafik über den Pi-Treiber, greetd auf dem VT,
I2C/GPIO des Argon ONE, Tastatur), ist pro Modul unter «am Pi prüfen» notiert.

## Entscheidungen während des Baus

- **Quickshell** fehlt in den Ubuntu-26.04-Paketquellen → Quellbau v0.3.1 (Commit `1a4716c`), fest eingetragen.
- **Schriften** liegen im Repo unter `assets/fonts/` (Geist v1.7.2, Instrument Serif `65c0ef2`, OFL), Quellen und Prüfsummen in `assets/fonts/QUELLEN.md`.
- **Git-Identität** im Repo: GitHub-noreply-Adresse, damit keine persönliche E-Mail in öffentliche Commits gelangt.

## Offene Punkte für Zeno

(Claude Code trägt hier ein, was Zeno prüfen oder entscheiden muss.)
