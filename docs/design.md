# Design

Die einzige Quelle für Werte ist `shell/theme/tokens.json`. Diese Seite erklärt sie.

Entwürfe: [Design-Leinwand zenOS](https://claude.ai/artifact/ASL134ctGMeBL6kmGYAe1n) (privat, Entwurf 2 ist aktuell)

## Haltung

Ruhig, warm, reduziert. Ein Akzent pro Modus, sonst neutrale Töne. Grosse Zahlen und Titel in einer Serifenschrift, alles andere sachlich. Bewegung nur, wenn sie etwas erklärt.

## Farben

| Token | Dunkel | Hell |
|---|---|---|
| `grund` | `#131312` | `#F1EFEA` |
| `flaeche` | `#1C1C1A` | `#FAF9F6` |
| `flaeche2` | `#252523` | `#E4E1D9` |
| `fenster` | `#1A1A18` | `#FAF9F6` |
| `linie` | `#2E2E2B` | `#DFDCD4` |
| `text` | `#ECEAE4` | `#1B1B19` |
| `text2` | `#D9D6CF` | `#3A3935` |
| `gedaempft` | `#A29E95` | `#625F58` |

**Zwischentöne** aus Entwurf 2, für Rahmen und Flächen, die zwischen den Grundtönen liegen:

| Token | Dunkel | Hell | Einsatz |
|---|---|---|---|
| `linie2` | `#30302D` | `#D6D2C9` | etwas deutlichere Linie: Rahmen schwebender Flächen (Befehlsfeld, Hinweis), Werkzeug-Chips, Pillen |
| `trennlinie` | `#2A2A27` | `#E4E1D9` | leise Trennlinie innerhalb einer Fläche: unter der Eingabezeile des Befehlsfelds, unter Titelzeilen, zwischen Listenzeilen |
| `eingabeRand` | `#3A3A36` | `#D6D2C9` | Rahmen von Eingabefeldern, umrandeten Chips (Zustand) und Knöpfen mit Rahmen |
| `tasteRand` | `#3A3A36` | `#DFDCD4` | Rahmen der Tastenkappen (Kbd) |
| `abgesetzt` | `#1F1F1D` | `#E6E3DC` | leicht abgesetzter Hintergrund, z. B. der System-Knopf in der Leiste |
| `wasserzeichen` | `#1B1B19` | `#E6E3DC` | sehr zurückhaltender Bogen im Hintergrund (Sperrbildschirm, Erster Start) |
| `schatten` | `rgba(0, 0, 0, 0.55)` | `rgba(27, 27, 25, 0.16)` | Schatten schwebender Flächen (ohne Weichzeichnen der Umgebung); der helle Wert ist abgeleitet, Entwurf 2 zeigt nur dunkel |

Linien werden im Dunkeln etwas heller, im Hellen etwas dunkler, damit sie auf beiden Gründen gleich stark wirken.

**Modus-Akzente** (je ein Paar für hell und dunkel): Salbei, Sand, Blau, Ton, Graphit.

**Signalfarben:**
- `sitzung` `#E39A5B`: nur für «Bildschirm wird geteilt». Das ist die einzige bewusste Ausnahme von der Ein-Akzent-Regel.
- `fehler` und `warnung`: nur im Terminal und bei echten Problemen.

Kontrast: Fliesstext mindestens 4.5:1, grosse Schrift ab 24 px mindestens 3:1.

## Schrift

| Rolle | Schrift | Einsatz |
|---|---|---|
| Anzeige | Instrument Serif | grosse Zahlen, Titel, Uhrzeit |
| Text | Geist | Oberfläche, Fliesstext |
| Mono | Geist Mono | Zeiten, Labels, Terminal, Tastenkürzel |

Alle drei stehen unter der SIL Open Font License und dürfen ins Image.

## Form und Bewegung

- **Radien:** 6 · 8 · 10 · 12 · 16 px. Fenster 12, Befehlsfeld 16, Chips 8.
- **Abstände:** 4 · 8 · 12 · 16 · 24 · 32 · 48 px. Fenster im Raster mit 8 px Lücke.
- **Bewegung:** 120 ms für Kleines, 200 ms maximal, `OutCubic`.
- **Kein Blur.** Überlagerungen dunkeln den Hintergrund nur ab.

## Tokens in der Oberfläche

- `shell/theme/Theme.qml` liest `tokens.json` beim Start (synchron, damit schon das erste Bild stimmt) und übernimmt
  Änderungen an der Datei sofort. Es ist die einzige Stelle mit Farbwerten; alle anderen QML-Dateien nutzen
  `Theme.<name>` (zum Beispiel `Theme.flaeche`, `Theme.eingabeRand`, `Theme.akzent`) und für Transparenz
  `Qt.alpha(Theme.<name>, a)`. Für Flächen ohne Füllung gibt es `Theme.durchsichtig` statt eines Farbnamens.
- `Theme.akzent` ist der Akzent des aktiven Modus, ohne Modus `standardAkzent`. `Theme.aufAkzent` ist die Farbe
  für Text auf Akzentflächen (dunkel: `grund`, hell: `flaeche`).
- Das Schema steht in `config/schema/tokens.schema.json`. Neue Tokens kommen immer in beide Farbsätze
  (`hell` und `dunkel`) und in diese Seite.
- `scripts/bin/zenos-thema` überträgt dieselben Werte nach aussen: GTK (`color-scheme`, `gtk-theme`), kitty
  (Farben inklusive Akzent), labwc (Titelzeile, Rand, Menüs, Fensterwechsler, Einrast-Vorschau) und VS Code
  (`window.autoDetectColorScheme`). Qt folgt über das Plattform-Theme `xdgdesktopportal`, Chrome über das Portal.

**kitty-Palette:** Grün = Akzent, Rot = `fehler`, Gelb = `warnung`, Hell-Schwarz = `gedaempft`. Blau, Magenta und
Cyan kommen aus den übrigen Akzenten (bevorzugt Blau, Ton, Salbei; der aktive Akzent wird übersprungen).

## Komponenten

Gemeinsame Bausteine liegen unter `shell/komponenten/` (`import qs.komponenten`): `Symbol`, `Zeichen`, `Chip`,
`Knopf`, `Eingabe`, `Kbd`, `Trenner`, `Abschnittstitel`, `Schalter`, `Farbwahl`, `Toast`, `Karte`, `Fokusrahmen`.
Tastaturfokus zeigt ein 2-px-Ring im Akzent; Zeigen und Drücken färben leicht ein (120 ms, `OutCubic`).

### Leiste (40 px)

- **Links, «wo bin ich»:** Zeichen, Modus-Chip, Zustand-Chip (nur wenn aktiv), Raster.
- **Mitte:** Datum, Uhrzeit, nächster Termin.
- **Rechts, höchstens drei Dinge:** Dev-Server (nur wenn einer läuft), Mitteilungen mit nächster Zustellung, System-Knopf (WLAN, Ton, 1Password, Temperatur).

### Befehlsfeld

- 720 px breit, 104 px von oben, Radius 16.
- Reihenfolge der Abschnitte: Projekt, Apps und Aktionen, Modus und Zustand, Werkzeuge.
- `Esc` schliesst, `Tab` springt zu den Werkzeugen.

### Fenster

- Radius 12, Titelzeile 34 px, Titel in Geist Mono.
- Das aktive Fenster hat einen 1-px-Rand im Modus-Akzent.

### Sitzung

- Das geteilte Fenster bekommt einen 2-px-Rahmen in `sitzung` und oben das Label «Dieses Fenster wird geteilt».
- Mitteilungen werden zurückgehalten und nur als Zahl gezeigt.

### Sperrbildschirm

- Grosse Uhrzeit, Datum, Anzahl Mitteilungen ohne Inhalt, Passwortfeld.
- Unten: «zenOS gesperrt · 1Password gesperrt».

### Terminal

- Eingabezeile: Ordner, Git-Branch, Änderungen, darunter `›`.
- Jeder Befehl ist ein Block mit Statuszeile (✓ oder ✗, Dauer, Fehler in Klartext).
- Erklärungen erscheinen als Karte unter dem Befehl, Warnungen mit Rahmen in `warnung`. «Abbrechen» ist die Vorauswahl.
