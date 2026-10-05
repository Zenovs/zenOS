# shell

Die zenOS-Oberfläche in Quickshell v0.3.1 (QML, Qt 6). Die Sitzung lädt sie aus `~/.config/quickshell`, das auf
`/opt/zenos/shell` verweist; Quickshell übernimmt Änderungen beim Speichern sofort. Jeder Ordner ist ein eigenes
Modul (`import qs.<ordner>`).

| Pfad | Inhalt |
|---|---|
| `shell.qml` | Einstieg der Sitzung: lädt jede Oberfläche einzeln über `LazyLoader`, die Sperre zuerst |
| `greeter.qml`, `greeter/` | Login für greetd; `greeter/notfall/` ist ein schlichter Notfall-Login ohne `qs.*`-Module |
| `theme/` | `tokens.json` (einzige Quelle für Werte), `Theme.qml` (Singleton), `ThemaIpc.qml` (IPC `thema`) |
| `dienste/` | Singletons ohne Oberfläche: Pfade, Einstellungen, Erscheinung, Oberflaeche, Aktionen, System, Geraet, Mitteilungen, Konfig, Modi, Zustaende, Freigabe, Leitplanken, Raster, Firewall, Luefter, Energie, Kanal; `geraet.js`, `energie.js` und `kanal.js` (Logik für Akku und Lüfter, Energie bzw. Update-Kanal, auch mit node getestet) |
| `komponenten/` | gemeinsame Bausteine (Symbol, Chip, Knopf, Eingabe, Toast …), `Hinweise.qml` (IPC `hinweis`) |
| `leiste/` | Leiste, System- und Raster-Menü; WLAN im System-Menü (`WlanQuelle` spricht NetworkManager über `Quickshell.Networking`, nur hier und erst, wenn NetworkManager läuft; `wlan.js` testet auch node) |
| `heute/` | Hintergrund «Heute» |
| `befehlsfeld/` | Befehlsfeld mit App-Übersicht (`AppRaster`, `Kachel`); `rechner.mjs` und `suche.mjs` testet auch node |
| `mitteilungen/` | Karten und Zentrale |
| `appleiste/` | App-Leiste am rechten Rand (`AppLeiste`, `AppEintrag`); `fenster.mjs` (Gruppieren, Reihenfolge, Ziel eines Klicks) testet auch node |
| `sperre/` | Sperrbildschirm (ext-session-lock, PAM) |
| `freigabe/` | Rahmen und Label bei Bildschirmfreigabe |
| `modi/` | Modus- und Zustand-Wahl, `zustandslogik.js` (Logik der Zustände, auch mit node getestet) |
| `einstellungen/` | Einstellungen-Fenster, eine Datei pro Seite, Bausteine unter `teile/` |
| `einrichtung/` | Erster Start und Zustimmung zu den Apps |
| `polkit/` | polkit-Agent der Sitzung: Passwortdialog für Administratorrechte (z. B. «Firewall ausschalten») |

Regeln:

- Farben, Schriften, Radien, Abstände und Bewegung kommen nur aus `theme/tokens.json` (`Theme.<name>`). Keine
  Hex-Werte und keine Farbnamen ausserhalb von `Theme.qml`, kein Blur, Animationen höchstens 200 ms.
- Prozesse starten mit Argumentlisten, nie über `sh -c`.
- Dienste importieren nie `qs.theme`. Ein Syntaxfehler unter `dienste/` oder in `Theme.qml` legt die ganze
  Oberfläche lahm, auch die Sperre: vor dem Commit `scripts/pruefen.sh` (qmllint und Start-Test).

Aufbau und IPC: `docs/architektur.md`. Design: `docs/design.md`. Testen ohne Bildschirm: `test/container/README.md`.
