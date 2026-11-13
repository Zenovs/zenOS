# CLAUDE.md – Arbeitsanweisungen für Claude Code

## Projekt in einem Satz

zenOS ist ein eigenes, unveränderliches Betriebssystem aus Debian-Paketen für Zenos Laptop (Argon ONE UP mit Compute Module 5, Chip BCM2712) und den Raspberry Pi 5, gebaut für genau eine Person (Zeno). Version 0.1 (Ubuntu, Branch `dev`) ist eingefroren; auf dem Branch `neubau` entsteht 1.0. Später soll zenOS auch auf einem x86-Rechner laufen.

## Zuerst lesen

1. `MANIFEST.md`: die Grundsätze in Rangordnung. Bei einem Konflikt gewinnt der höhere Grundsatz.
2. `docs/neubau.md`: das Konzept für 1.0 mit Bedrohungsmodell, Aufbau und Stufen.
3. `BAUAUFTRAG.md`: Ist ein Bauauftrag aktiv, gilt er. Dann arbeitest du selbstständig durch und hältst `docs/baufortschritt.md` aktuell.
4. `ROADMAP.md`: der aktuelle Stand. Ohne aktiven Bauauftrag arbeitest du nur an diesem.
5. `docs/`: Architektur, Konfiguration, Design, Sicherheit. Was dort noch Ubuntu beschreibt, gilt für 0.1.

## Sprache und Stil

- **Mit Zeno:** Hochdeutsch, Du-Form, «ss» statt «ß», kurz und direkt. Widersprich ehrlich, wenn etwas gegen das Manifest geht.
- **Doku und Kommentare:** Deutsch.
- **Code-Bezeichner:** Englisch.
- **Konfigurationsschlüssel:** Deutsch ohne Umlaute, zum Beispiel `zustaende`, `ausloeser`.
- **Befehle für Zeno:** Wenn Zeno einen Terminal-Befehl selbst ausführen soll, gib immer nur einen und warte auf seine Rückmeldung.

## Architektur in Kürze (1.0)

| Ebene | Wahl | Hinweis |
|---|---|---|
| Unterbau | Debian 13 «trixie» arm64 als unveränderliches Image, gebaut mit mkosi | `/` schreibgeschützt mit dm-verity, `/var` und `/home` auf LUKS2 |
| Kernel und Firmware | von Raspberry Pi (`archive.raspberrypi.com`), ab 1.0 aus deren Quellcode mit eigener Konfiguration | Debian kann den BCM2712 nicht vollständig |
| Fenstermanager | labwc (Wayland, aus Debian) | Einrasten per `SnapToRegion`, kein automatisches Kacheln |
| Oberfläche | Quickshell (QML, Qt 6) | Leiste, Befehlsfeld, Mitteilungen, Sperrbildschirm, Login, Einstellungen |
| Terminal | kitty mit fish | schlaues Ctrl+C, Shell-Integration |
| Browser | Chromium aus Debian, gehärtet über Richtlinien | Erweiterungen nur mit freigegebener ID; keine proprietäre Software auf dem Gerät |

Details: `docs/neubau.md`.

## Repo-Struktur

```
zenos/
├── MANIFEST.md            Grundsätze
├── CLAUDE.md              diese Datei
├── BAUAUFTRAG.md          aktueller Bauauftrag
├── ROADMAP.md             Stand und Stufen
├── docs/                  Konzept (neubau.md), Architektur, Konfiguration, Design, Sicherheit, Baufortschritt
├── mkosi/                 Bau des Images für 1.0 (mkosi), Bauumgebung und Angriffstests
├── assets/                Zeichen, Schriften
├── shell/                 Quickshell-Oberfläche (QML), Einstieg shell.qml, Login greeter.qml
│   └── theme/tokens.json  einzige Quelle für Farben, Schrift, Radien, Bewegung
├── system/                Konfiguration für labwc, greetd, systemd, Portale, PAM, kitty, fish, Richtlinien
├── config/                Schemas, Vorlagen (Zustände, Raster) und neutrale Beispiele
├── scripts/, image/       Installer und Image von 0.1 (eingefroren)
├── test/                  Testumgebung im Container (Mac), Einheitentests
└── .github/workflows/     Prüfung bei jedem Push, Image-Build und Releases
```

## Arbeitsweise

- **Stufen:** Ohne aktiven Bauauftrag wird nach `ROADMAP.md` gearbeitet. Pro Stufe: kurz planen, Zeno den Plan zeigen, umsetzen, auf echter Hardware testen lassen, Tag setzen.
- **Bauauftrag:** Ist einer aktiv, arbeitest du ohne Zwischenfragen durch. Du fragst nur bei den Punkten, die der Auftrag unter «Nur nach Rückfrage» nennt, oder bei echten Blockern.
- **Commits:** klein und thematisch. Commit-Nachrichten auf Deutsch im Format `bereich: was und warum`, zum Beispiel `leiste: Uhrzeit aus Tokens`.
- **Attribution:** Die Claude-Attribution in Commits bleibt drin (`Co-Authored-By`). zenOS macht kein Geheimnis daraus, dass es mit Claude entsteht.
- **Rückfrage vor Eingriffen:** Vor Änderungen an System, Paketen oder Netzwerk kurz beschreiben, was passiert, und auf ein Ja warten. Ausnahme: was ein aktiver Bauauftrag ausdrücklich freigibt.

## Bauen und Testen (1.0)

- **Wo gebaut wird:** auf Zenos Mac. mkosi läuft in einem Debian-Container (`mkosi/umgebung/`) unter Docker (Colima); getestet wird in QEMU im selben Container. **Auf dem Laptop wird nicht entwickelt.** Er bekommt nur fertige Images, die Zeno selbst auf einen Datenträger schreibt.
- **Test-Pi 5:** für den signierten Start und das Entwicklungs-Image (mit SSH für Claude Code). Das Entwicklungs-Image wird nie mit dem Release-Schlüssel signiert.
- **Selbsttest:** die Angriffstests in QEMU (`mkosi/test/`) und `gitleaks` vor jedem Commit.
- **0.1:** Der Branch `dev` und `scripts/install.sh` bleiben, wie sie sind. Nichts auf `neubau` darf `zen update` eines Geräts mit 0.1 erreichen.

## Harte Regeln

Diese Regeln gelten immer:

1. **Keine persönlichen Daten im Repo:** keine Namen, Konten, Modi, Orte, Hostnamen oder IP-Adressen. Beispiele bleiben neutral (`config/beispiele/`).
2. **Keine Geheimnisse im Repo:** API-Schlüssel kommen zur Laufzeit aus 1Password (`op`). Vor jedem Commit läuft gitleaks.
3. **SSH, Firewall und Netzwerk** nie ohne ausdrückliche Anweisung anfassen. Das Release-Image hat keinen SSH-Server.
4. **Eingaben aus dem Befehlsfeld** nie ungeprüft an eine Shell geben. Prozesse mit Argument-Listen starten, nie mit `sh -c`.
5. **Sperrbildschirm** nur über `ext-session-lock` und PAM. zenOS fasst nie selbst ein Passwort an.
6. **Leitplanken** aus `MANIFEST.md` sind Code, nicht Konfiguration. Sie dürfen nie abschaltbar werden.
7. **Proprietäre Software** (Chrome, VS Code, 1Password-App) kommt nie aufs Gerät, auch nicht nachinstalliert.
8. **Keine Telemetrie, keine automatischen Uploads.** Nichts verlässt den Rechner ohne Zenos ausdrückliche Aktion.
9. **Datenträger und Firmware:** Nie auf einen USB-Stick, eine SSD, das EEPROM oder das OTP schreiben. Das macht Zeno selbst, mit einem Befehl nach dem anderen, nach ausdrücklichem Ja für genau dieses Gerät.
10. **Schlüssel:** Claude erzeugt, sieht und benutzt nie Signaturschlüssel und startet nie einen Signaturbefehl (`ssh-keygen -Y sign` oder ähnlich). Die geheimen Teile liegen nur auf Zenos FIDO2-Schlüsseln; signiert wird nur von Zeno, in seinem Terminal, mit PIN und Berührung (`docs/signieren.md`). Claude prüft Signaturen nur. Einzige Ausnahme: der Wegwerf-Schlüssel des QEMU-Tests (`mkosi/ausgabe/test-schluessel/`), dem nur das Test-Image traut.

## Design-Regeln

- Farben, Schriften, Radien, Abstände und Bewegung kommen nur aus `shell/theme/tokens.json`. Im QML stehen keine Hex-Werte.
- Kein Weichzeichnen (Blur). Der Hintergrund wird nur abgedunkelt.
- Animationen dauern höchstens 200 ms, mit `Easing.OutCubic`. Keine Animation ist besser als eine ruckelnde.
- Hell und dunkel sind gleichwertig. Jede Komponente wird in beiden geprüft.
- Details und Komponenten stehen in `docs/design.md`.

## Definition of Done

- Läuft flüssig auf dem Argon ONE UP, in hell und dunkel.
- Enthält keine persönlichen Daten und keine Geheimnisse, gitleaks ist sauber.
- Das Image baut aus einem eingefrorenen Paketstand, und die Angriffstests sind grün.
- Die Doku in `docs/` ist angepasst, falls sich Verhalten geändert hat.
- Zeno hat auf echter Hardware abgenommen.
