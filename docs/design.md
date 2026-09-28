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
| `abdunkeln` | `rgba(10, 10, 9, 0.68)` | `rgba(27, 27, 25, 0.35)` |

`abdunkeln` liegt hinter Überlagerungen (Befehlsfeld, Auswahl beim Bildschirmfoto). Die Umgebung wird nur
abgedunkelt, nie weichgezeichnet.

**Zwischentöne** aus Entwurf 2, für Rahmen und Flächen, die zwischen den Grundtönen liegen:

| Token | Dunkel | Hell | Einsatz |
|---|---|---|---|
| `linie2` | `#30302D` | `#D6D2C9` | etwas deutlichere Linie: Rahmen schwebender Flächen (Befehlsfeld, Menüs, Karten, Hinweis), Werkzeug-Chips, Pillen |
| `trennlinie` | `#2A2A27` | `#E4E1D9` | leise Trennlinie innerhalb einer Fläche: unter der Eingabezeile des Befehlsfelds, unter Titelzeilen, zwischen Listenzeilen |
| `eingabeRand` | `#3A3A36` | `#D6D2C9` | Rahmen von Eingabefeldern, umrandeten Chips (Zustand) und Knöpfen mit Rahmen |
| `tasteRand` | `#3A3A36` | `#DFDCD4` | Rahmen der Tastenkappen (Kbd) |
| `abgesetzt` | `#1F1F1D` | `#E6E3DC` | leicht abgesetzter Hintergrund, z. B. der System-Knopf in der Leiste |
| `wasserzeichen` | `#1B1B19` | `#E6E3DC` | sehr zurückhaltender Bogen im Hintergrund (Sperrbildschirm, Login, Erster Start) |
| `schatten` | `rgba(0, 0, 0, 0.55)` | `rgba(27, 27, 25, 0.16)` | Schatten schwebender Flächen (ohne Weichzeichnen der Umgebung); der helle Wert ist abgeleitet, Entwurf 2 zeigt nur dunkel |

Linien werden im Dunkeln etwas heller, im Hellen etwas dunkler, damit sie auf beiden Gründen gleich stark wirken.

**Modus-Akzente** (je ein Paar für hell und dunkel). Ohne Modus gilt `standardAkzent` (`salbei`).

| Akzent | Dunkel | Hell |
|---|---|---|
| `salbei` | `#A7B89F` | `#4E6A49` |
| `sand` | `#D2B48C` | `#8A5F2E` |
| `blau` | `#9DB4CF` | `#3E5C7A` |
| `ton` | `#D99A86` | `#9A4F3C` |
| `graphit` | `#C9C6BE` | `#4A4A45` |

**Signalfarben:**

| Token | Dunkel | Hell | Einsatz |
|---|---|---|---|
| `sitzung` | `#E39A5B` | `#B8642A` | nur für «Bildschirm wird geteilt». Das ist die einzige bewusste Ausnahme von der Ein-Akzent-Regel. |
| `fehler` | `#E88A7A` | `#B3402F` | Terminal und echte Probleme (falsches Passwort, «Modus löschen») |
| `warnung` | `#E0B45C` | `#8A6414` | Terminal und Warnhinweise |

Kontrast: Fliesstext mindestens 4.5:1, grosse Schrift ab 24 px mindestens 3:1.

## Schrift

| Rolle | Schrift | Einsatz |
|---|---|---|
| Anzeige | Instrument Serif | grosse Zahlen, Titel, Uhrzeit |
| Text | Geist | Oberfläche, Fliesstext |
| Mono | Geist Mono | Zeiten, Labels, Terminal, Tastenkürzel, Titelzeilen der Fenster |

Grössen: 12 (klein) · 13 (Label) · 14 (Text) · 16 (gross) · 36 (Titel) · 180 px (Anzeige, Uhrzeit der Sperre).

Alle drei stehen unter der SIL Open Font License und dürfen ins Image (`assets/fonts/`).

## Form und Bewegung

- **Radien:** 6 · 8 · 10 · 12 · 16 px, dazu 999 für Pillen. Chips und Menüeinträge 8, Eingabefelder 10, Fenster,
  Menüs und Karten 12, Befehlsfeld 16.
- **Abstände:** 4 · 8 · 12 · 16 · 24 · 32 · 48 px. Fenster im Raster mit 8 px Lücke.
- **Masse:** Leiste 40 px, Titelzeile 34 px, aktiver Fensterrand 1 px, Befehlsfeld 720 px breit und 104 px von oben.
- **Bewegung:** 120 ms für Kleines, 200 ms maximal, `OutCubic`. Eingeblendet wird meist nur die Deckkraft.
- **Kein Blur.** Überlagerungen dunkeln den Hintergrund nur ab. Schatten gibt es nur am Befehlsfeld und nur mit GPU;
  Menüs, Karten und Hinweise haben einen Rahmen statt eines Schattens.
- **Ruhe:** Nichts blinkt. Textcursor sind ein stehender Strich (1 px, `text`), auch in Sperre und Login.

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
  Die Notfall-Sperre (swaylock) nimmt die dunklen Farben und den Akzent ebenfalls aus den Tokens.

**kitty-Palette:** Grün = Akzent, Rot = `fehler`, Gelb = `warnung`, Hell-Schwarz = `gedaempft`. Blau, Magenta und
Cyan kommen aus den übrigen Akzenten (bevorzugt Blau, Ton, Salbei; der aktive Akzent wird übersprungen).
Die Tab-Leiste liegt im Hintergrund des Terminals (`fenster`), der aktive Tab ist mit `flaeche2` hinterlegt.

## Komponenten

Gemeinsame Bausteine liegen unter `shell/komponenten/` (`import qs.komponenten`): `Symbol`, `Zeichen`, `Chip`,
`Knopf`, `Eingabe`, `Kbd`, `Trenner`, `Abschnittstitel`, `Schalter`, `Farbwahl`, `Toast`, `Karte`, `Fokusrahmen`.
Tastaturfokus zeigt ein 2-px-Ring im Akzent; Zeigen und Drücken färben leicht ein (120 ms, `OutCubic`).
Beschriftungen sind immer reiner Text (keine Auszeichnungen), auch wenn sie von aussen kommen.

- **Symbole:** Strich-Symbole auf einer 24er-Fläche mit runden Enden, Pfade aus Entwurf 2 (Liste in
  `docs/module/m3.md`). Was dort fehlte, ist im selben Stil gezeichnet.
- **Chips:** 28 px, Radius 8; Varianten gefüllt (`flaeche2`), umrandet (`eingabeRand`), still und abgesetzt.
- **Knöpfe:** 44 px; `primaer` im Akzent, `sekundaer` mit Rahmen, `still` ohne Fläche, `gefahr` mit Rahmen und Text in `fehler`.
- **Eingabefelder:** 44 px, Radius 10, Rahmen `eingabeRand`, bei einem Fehler Rahmen in `fehler`. Die Super-Taste
  tippt nie ein Zeichen.

### Menüs

System-Menü und Raster-Menü der Leiste sowie die Modus- und Zustand-Wahl sehen gleich aus: Karte in `flaeche` mit
1-px-Rahmen `linie2`, Radius 12, ohne Schatten. Einträge 36 px hoch (Radius 8, Zeigen und Tastaturfokus hinterlegen
mit `flaeche2`), Symbol links, Wert rechts in Geist Mono. Sie klappen unter ihrem Knopf bzw. Chip auf; per
Tastenkürzel geöffnet erscheint die Wahl mittig. Pfeile und Tab wandern durch die Einträge. Abmelden, Neustart und
Ausschalten fragen einmal nach («Wirklich ausschalten?»), erst der zweite Klick löst aus. Esc oder ein Klick daneben
schliesst. Beim Sperren schliessen alle Menüs, und während der Sperre bleiben sie zu.

### Hinweise (Toast)

Kurze Rückmeldungen wie «Farbe kopiert» erscheinen als Pille unten mittig, über den Tastenkappen von «Heute»:
40 px hoch, Radius 999, `flaeche` mit Rahmen `linie2`, Text 14 px, höchstens 560 px breit (längere Texte werden
gekürzt). Einblenden 120 ms, Ausblenden 200 ms, nur Deckkraft. Die Pille nimmt keine Klicks weg.

| Art | Symbol | Dauer |
|---|---|---|
| Bestätigung (`Oberflaeche.hinweis(text)`, `zenos-ipc hinweis zeigen`) | Haken im Akzent | 2,5 s |
| Warnung (`Oberflaeche.hinweis(text, "warnung")`, `zenos-ipc hinweis warnen`) | Warnung in `warnung` | 4 s |
| eigenes Symbol (`Oberflaeche.hinweis(text, "<symbol>")`) | `x` in `fehler`, sonst Akzent | 2,5 s |

Formularfehler erscheinen nicht als Hinweis, sondern ruhig unter dem Formular.

### Leiste (40 px)

- **Links, «wo bin ich»:** Zeichen, Modus-Chip, Zustand-Chip (nur wenn aktiv, mit Restzeit), Raster (Kurzname).
- **Mitte:** Datum und Uhrzeit in Geist Mono. Der nächste Termin kommt «Danach».
- **Rechts:** Mitteilungen mit nächster Zustellung («3 · 10:00», «2 warten»), Hell/Dunkel (Mond im Hellen, Sonne im
  Dunkeln), System-Knopf auf `abgesetzt` (Netz, Ton, 1Password, Temperatur). Die Dev-Server-Übersicht kommt «Danach».
- **Zustand und Leiste:** Ein Zustand kann die Leiste zurücknehmen (Schlüssel `leiste`). `reduziert` blendet Raster
  und Hell/Dunkel aus, `aus` lässt nur Zustand und Uhrzeit stehen. Der Platz bleibt in beiden Fällen reserviert,
  damit Fenster nicht springen. Einzelheiten in `docs/module/m4.md`.

### «Heute»

Hintergrund auf jedem Bildschirm, in `grund`: Wochentag und Monat (Mono, Grossbuchstaben), Tageszahl in Instrument
Serif 300 px, Gruss nach Tageszeit mit Name (kursiv), Zusammenfassung, Moduszeile mit Akzentpunkt, unten die
Tastenkappen für Befehlsfeld, Modus und Zustand. Die rechte Spalte (Termine, Aufgaben, Wetter) kommt «Danach».
Während einer Freigabe und bei `heute: false` blendet der Inhalt aus (200 ms).

### Befehlsfeld

- 720 px breit, 104 px von oben, Radius 16, `flaeche` mit Rahmen `linie2`, Hintergrund `abdunkeln`.
- Eingabezeile 62 px, Einträge 44 px (Radius 8, Auswahl `flaeche2`), Werkzeug-Chips 34 px.
- Reihenfolge der Abschnitte: Rechnen, Apps und Aktionen, Modus und Zustand, Dateien, Werkzeuge. «Projekt» kommt
  «Danach».
- `Esc` schliesst, `Tab` springt zu den Werkzeugen. Fusszeile: «↑↓ wählen · ↵ ausführen · Tab Werkzeuge · Esc
  schliessen».

### Mitteilungen

- Karten oben rechts unter der Leiste: 380 px, `flaeche`, Rahmen `linie2`, Radius 12, Zeiten in Geist Mono, ohne
  Schatten. Die Sammelkarte verschwindet nach 10 s, dringende Karten bleiben bis zum Schliessen.
- Zentrale als Panel rechts (400 px). Kein Ton, kein Blinken; neue Karten kommen unten dazu, damit nichts verrutscht.

### Fenster

- Radius 12 an den oberen Ecken (labwc rundet nur die Titelzeile, unten eckig), Titelzeile 34 px, Titel in Geist Mono.
- Das aktive Fenster hat einen 1-px-Rand im Modus-Akzent.
- Eingerastete Fenster behalten die runden oberen Ecken; zwischen den Fenstern und zur Leiste liegen 8 px.

### Einstellungen

Eigenes Fenster mit labwc-Titelzeile. Navigation 260 px (Modi, Zustände, Raster, Bildschirme, darunter Web-Apps,
Apps, Allgemein, System), Titel in Instrument Serif, Felder zweispaltig. Was erst später wirkt, ist mit «später»
markiert und nicht bedienbar.

### Sitzung

- Der geteilte Bildschirm bekommt einen 2-px-Rahmen in `sitzung` (Radius 12) und oben mittig das Label «Dieser Bildschirm wird geteilt» (Pille 24 px, Hintergrund `sitzung`, Text `grund`, Geist Mono 12, Monitor-Symbol).
- Mitteilungen werden zurückgehalten und nur als Zahl gezeigt.

### Sperrbildschirm und Login

- Grosse Uhrzeit (Instrument Serif 180 px), Datum, Anzahl Mitteilungen ohne Inhalt, Passwortfeld, Bogen als
  Wasserzeichen.
- Unten: «zenOS gesperrt · 1Password gesperrt».
- Der Login sieht aus wie der Sperrbildschirm und ist immer dunkel.

### Erster Start

Bogen als Wasserzeichen links, Titel «Willkommen bei zenOS.» in Instrument Serif 76 px, rechts das Formular 01–04
(Name, Ort, Erscheinungsbild, erster Modus mit Akzent). Danach die Zustimmung zu den Apps.

### Terminal

- Eingabezeile: Ordner, Git-Branch, Änderungen, darunter `›`.
- Jeder Befehl ist ein Block mit Statuszeile (✓ oder ✗, Dauer, Fehler in Klartext).
- Erklärungen erscheinen als Karte unter dem Befehl, Warnungen mit Rahmen in `warnung`. «Abbrechen» ist die Vorauswahl.
