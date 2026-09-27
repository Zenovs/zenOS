# Baufortschritt zenOS 0.1

Claude Code führt diese Liste während des Bauauftrags nach. Eine neue Sitzung macht hier weiter.

Status: `offen` · `in Arbeit` · `fertig` · `offener Punkt`

| Modul | Status | Notiz |
|---|---|---|
| M1 · Installer und zen-Werkzeug | fertig | install.sh (idempotent, Module, Log), gemeinsam.sh, zen (update, rollback, doctor, version, benutzer, hilfe), pruefen.sh, Testumgebung `test/container/`. Details: `docs/module/m1.md` |
| M2 · Basis und Sitzung | in Arbeit | Quickshell v0.3.1 im Container gebaut (4,5 min), Schriften unter `assets/fonts/` |
| M3 · Design-Tokens und Theme | fertig | Theme-Singleton aus tokens.json (neue Tokens: linie2, trennlinie, eingabeRand, tasteRand, abgesetzt, wasserzeichen, schatten), Dienste, Komponenten, shell.qml mit isoliert geladenen Oberflächen, zenos-thema (GTK, Qt über Portal, kitty, labwc, VS Code). Details: `docs/module/m3.md` |
| M4 · Leiste | in Arbeit | Phase B |
| M5 · Befehlsfeld | in Arbeit | Phase B |
| M6 · Mitteilungen | in Arbeit | Phase B |
| M7 · Sperrbildschirm | in Arbeit | Phase B |
| M8 · Modi und Zustände | in Arbeit | Phase B |
| M9 · Raster und Bildschirme | in Arbeit | Phase B |
| M10 · Terminal | in Arbeit | Phase B |
| M11 · Sicherheit | in Arbeit | Phase B |
| M12 · Erster Start | in Arbeit | Phase B |
| M13 · Argon ONE | in Arbeit | Phase B |
| M14 · Image-Workflow | in Arbeit | Phase B |
| M15 · Abschluss | offen | |

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
