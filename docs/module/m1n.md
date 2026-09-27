# M1n · Nachtrag zu M1: Start-Test der Oberfläche

## Was gebaut ist

- Neuer Teil `start` in `scripts/pruefen.sh` (läuft auch ohne Angabe mit):
  `scripts/pruefen.sh start`, mit `--ausfuehrlich` zusätzlich alle übrigen Warnungen von Qt/Quickshell.
- Einstiege: `shell/shell.qml`, danach jede kleingeschriebene `.qml`-Datei unter `shell/` mit `ShellRoot`
  (derzeit `greeter.qml` und `greeter/notfall/notfall.qml`). Jeder Einstieg startet in einer eigenen
  Testsitzung: labwc ohne Bildschirm (headless, pixman, 1440×900), Quickshell im Software-Backend,
  `ZENOS_CODE` auf das Repo, in dem pruefen.sh liegt.
- Wartet bis «Configuration Loaded» (Zeitlimit 90 s). In `shell.qml` folgt ein Rundgang über IPC:
  Thema hin und zurück, Befehlsfeld (mit Werkzeugen), Zentrale, Modus- und Zustand-Wahl, jede
  Einstellungen-Seite, Einrichtung, Hinweis, Bildschirmfreigabe mit offener Zentrale, zuletzt die Sperre
  (muss danach `gesperrt` melden).
- Fehler (die Zeilen aus dem Protokoll werden ausgegeben): kein «Configuration Loaded», Absturz,
  ERROR/FATAL, «Type … unavailable», «Failed to load configuration», «is not a type»,
  ReferenceError/TypeError, «Cannot assign», «Unable to assign», «Binding loop», jede Warnung aus einer
  Datei unter `shell/`, `console.warn`/`console.error`, ein gescheiterter IPC-Aufruf, eine Sperre, die
  nicht sperrt. Übrige Warnungen von Qt sind Hinweise.
- Bekannte harmlose Meldungen stehen mit Begründung in `START_BEKANNT`: nur die Portal-Registrierung
  (`qt.qpa.services: Failed to register with host portal`). Die PipeWire-Meldung zählt nur als bekannt,
  wenn kein PipeWire-Socket da ist.
- Fehlt eines der nötigen Werkzeuge (labwc, quickshell, dbus-run-session, python3, setsid, timeout, ps),
  etwa in CI, wird der Teil mit Hinweis übersprungen, nicht rot.
- qmllint: die vier bekannten Fehlalarme aus Quickshells Typdaten (`FileView.adapter`,
  `Process.onExited`, `Notification.actions`, `PanelWindow.margins`) bleiben Warnungen und werden
  getrennt gezählt.
- `test/container/oberflaeche.sh` startet Quickshell mit `--no-color` (Protokoll ohne Farbcodes).
  `test/container/README.md` beschreibt den Start-Test.

## Entscheidungen

- **Abgeschottete Testsitzung:** eigenes HOME und eigene XDG-Ordner im Temp-Ordner, eigener
  Sitzungsbus (`dbus-run-session` mit einer Konfiguration ohne Dienstdateien), HTTP(S) über einen Proxy
  ins Leere. Die Testshell beginnt wie ein erster Start und erreicht nie die echte Sitzung: kein fremder
  Mitteilungsdienst, keine Einstellungen, keine Sperre, kein `labwc --reconfigure` der echten Sitzung.
  Nur PipeWire wird mitbenutzt, falls erreichbar (Lautstärke nur gelesen).
- **1Password:** Läuft 1Password beim Benutzer, lässt der Rundgang die Sperre aus (sie würde es über
  `zenos-1password-sperren` mitsperren) und meldet das als Hinweis.
- **Aufräumen:** labwc startet Quickshell in einer eigenen Sitzung. Beendet werden Quickshell (TERM,
  nach 5 s KILL), dann seine Prozessgruppe (Kindprozesse, etwa nach einem Hänger), dann die Gruppe um
  labwc und den Bus. Dasselbe beim Abbruch (Ctrl+C) über den Exit-Trap.
- **Auswertung vor dem Beenden:** Meldungen beim Abbau der Objekte zählen nicht.
- **IPC:** `quickshell ipc --pid … call` mit 15 s Zeitlimit; Fehler erkennt der Test an der Ausgabe
  (Quickshell v0.3.1 endet auch bei «Target not found.» mit Exit 0).

## Getestet (Container, Ubuntu 26.04 arm64)

- Aktueller Arbeitsstand: alle drei Einstiege geladen, Rundgang mit 24 IPC-Aufrufen, ohne Befund
  (rund 30 s).
- Gegenproben in Kopien, alle mit Exit 1 und der richtigen Zeile: Syntaxfehler in einem Dienst
  (ganze Shell und Greeter laden nicht), ReferenceError, TypeError, falsche Zuweisung, Binding loop,
  `console.warn` in einem Dienst, unbekannter Typ in einer Oberfläche, fehlendes IPC-Ziel (Befehlsfeld,
  Freigabe), Syntaxfehler im Greeter, Endlosschleife in einem Dienst (Zeitlimit), Hänger nach dem Start
  mit laufendem Kindprozess (Kindprozess danach weg).
- Ohne labwc/Quickshell und im nackten `ubuntu:26.04` als root: übersprungen, Exit 0.

## Am Pi prüfen

- `scripts/pruefen.sh start` per SSH, während die echte Sitzung läuft: Test ohne Befund, die Sitzung
  bleibt unberührt (Thema, Sperre, Mitteilungen, Fenster). Dauer mit leerem QML-Cache.
- Dasselbe mit laufendem 1Password: Hinweis «Sperre nicht geprüft», 1Password bleibt entsperrt.
