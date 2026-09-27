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

## Komponenten

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
