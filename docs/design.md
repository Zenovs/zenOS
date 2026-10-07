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
| `zudecken` | `rgba(19, 19, 18, 0.92)` | `rgba(241, 239, 234, 0.92)` |

`abdunkeln` liegt hinter Überlagerungen (Befehlsfeld, Auswahl beim Bildschirmfoto). Die Umgebung wird nur
abgedunkelt, nie weichgezeichnet. `zudecken` ist `grund` mit 92 % Deckkraft und liegt hinter der
Fensterübersicht: Dort sollen die Fenster dahinter nicht ablenken, mit `abdunkeln` schienen sie im Hellen stark
durch. Auch `zudecken` zeichnet nichts weich; die Fenster bleiben schwach zu ahnen.

**Zwischentöne** aus Entwurf 2, für Rahmen und Flächen, die zwischen den Grundtönen liegen:

| Token | Dunkel | Hell | Einsatz |
|---|---|---|---|
| `linie2` | `#30302D` | `#D6D2C9` | etwas deutlichere Linie: Rahmen schwebender Flächen (Befehlsfeld, Menüs, Karten, Hinweis), Werkzeug-Chips, Pillen |
| `trennlinie` | `#2A2A27` | `#E4E1D9` | leise Trennlinie innerhalb einer Fläche: unter der Eingabezeile des Befehlsfelds, unter Titelzeilen, zwischen Listenzeilen |
| `eingabeRand` | `#3A3A36` | `#D6D2C9` | Rahmen von Eingabefeldern, umrandeten Chips (Zustand) und Knöpfen mit Rahmen |
| `tasteRand` | `#3A3A36` | `#DFDCD4` | Rahmen der Tastenkappen (Kbd) |
| `abgesetzt` | `#1F1F1D` | `#E6E3DC` | leicht abgesetzter Hintergrund, z. B. der System-Knopf in der Leiste |
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
  Für das Aufgleiten (App-Übersicht) gibt es zwei Tokens: `bewegung.massstab` (0.96, Startmassstab einer Fläche, endet
  bei 1) und `bewegung.versatz` (6 px, um die Einträge beim Einblenden nach oben rücken). Animiert werden nur
  Deckkraft, Massstab und Lage, nie über eine Ebene oder einen Effekt. Gestaffeltes Einblenden ist als Ganzes in
  200 ms fertig. Eine Einstellung «weniger Bewegung» gibt es nicht.
- **Kein Blur.** Überlagerungen dunkeln den Hintergrund nur ab. Schatten gibt es nur am Befehlsfeld und nur mit GPU;
  Menüs, Karten und Hinweise haben einen Rahmen statt eines Schattens.
- **Ruhe:** Nichts blinkt. Textcursor sind ein stehender Strich (1 px, `text`), auch in Sperre und Login.

## Bildmarke

«Zwei Steine»: ein Kiesel, diagonal geteilt, der untere Stein im Akzent des aktiven Modus. Konstruktion, Farben,
Dateien und Regeln stehen in [`docs/bildmarke.md`](bildmarke.md).

- `ZenZeichen` (`qs.komponenten`) zeichnet die Marke mit den Pfaden aus `tokens.json` → `zeichen`; unter 24 px die
  Pixel-Variante. `obenFarbe` ist `text`, `akzent` der Name des Akzents für den unteren Stein (Standard: aktiver
  Modus), `einfarbig` setzt beide Steine auf `obenFarbe`.
- Nur ein neuer Akzent blendet den unteren Stein in 200 ms über. Hell/dunkel schaltet beide Steine im selben Bild um;
  die einfarbige Marke bewegt sich nie.
- Leiste 18 px · Login 48 px (unterer Stein `salbei`) · Sperrbildschirm 16 px und Befehlsfeld ohne Treffer bzw. ohne
  Apps 32 px, beide einfarbig `gedaempft` · Erster Start 44 px.
- Kein Wasserzeichen: Die Marke steht nie gross im Hintergrund.
- App-Icon `zenos` (hicolor 48–512 px) legt Modul `45-thema` unter `~/.local/share/icons` ab.

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

Gemeinsame Bausteine liegen unter `shell/komponenten/` (`import qs.komponenten`): `Symbol`, `ZenZeichen`, `Chip`,
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

**WLAN im System-Menü** (oben, vor Lautstärke; nur mit NetworkManager, siehe `docs/module/netzwerk.md`):

- Zeilen wie Menüeinträge (36 px, Radius 8). «WLAN» mit Schalter (36 × 20) rechts; nur der Schalter schaltet (auch
  mit der Tastatur, eigener Eintrag), die Zeile ist eine Beschriftung. So trennt ein Klick auf «WLAN» oder Pfeil
  runter und Enter nicht versehentlich die Verbindung. Darunter das verbundene Netz: Signal links, Name, rechts Schloss (12 px, `gedaempft`), Haken im Akzent
  und «x» (12 px, `gedaempft`) zum Vergessen. Dann «Netze in Reichweite» mit Pfeil rechts zum Auf- und Zuklappen
  (ohne Animation, die Karte wächst einfach).
- Aufgeklappt: höchstens fünfeinhalb Zeilen, dann scrollt die Liste; die angeschnittene Zeile und ein schmaler
  Balken rechts (3 px, `gedaempft` zu 50 %, ohne Animation) zeigen, dass es weitergeht. Netznamen als reiner Text, Unsichtbares darin (Zeichen ohne Breite, Richtungs- und Steuerzeichen)
  als «�». Signal als WLAN-Symbol mit ein bis drei Bögen, die
  fehlenden Bögen blass (30 % der Farbe). Nicht verbindbare Netze (802.1X, WEP) ganze Zeile blass mit «nicht
  möglich» in Mono. Während eines Versuchs «verbindet …» in Mono.
- Neues Netz mit Passwort: An Stelle der Liste das Netz und darunter das Passwortfeld (Eingabe, 36 px, Text auf
  der Höhe der Namen), darunter 12 px `gedaempft` «Enter verbindet · Esc bricht ab», dann «Verbinde …». Fehler
  ruhig in `fehler` unter dem Feld («Passwort falsch?»), das Feld bekommt den Rahmen in `fehler`. Bietet das Netz
  WPA3 an und scheitert es an Zeit, Ablehnung oder ohne Antwort, steht dazu «Bietet das Netz nur WPA3 an, geht es
  mit diesem WLAN-Chip nicht.» (Mischnetze melden sich gleich, deshalb nur als Möglichkeit). Fehler bei bekannten Netzen stehen unter ihrer Zeile.
- Vergessen fragt einmal nach: Die Zeile zeigt ««Telefon» vergessen?» in `fehler`, erst der zweite Klick löst aus.
- Bildschirmfreigabe: «Netzname verborgen» in `gedaempft`, «Netze in Reichweite» mit «verborgen» und ohne Pfeil.
- Ohne NetworkManager: die Netzzeile wie bisher, mit WLAN-Gerät darunter 12 px `gedaempft` «WLAN wählen: im
  Terminal «zen netzwerk umstellen», dann neu starten.»

Im System-Menü folgt nach 1Password und einer Trennlinie das Gerät: Akku («87 % · lädt», «100 % · Netzteil», «9 %»,
«nicht freigegeben»), Lüfter und CPU-Temperatur («41 °C»). Zeilen ohne Wert fehlen, ohne Akku und Lüfter bleibt nur
die Temperatur. Bei niedrigem Akku steht sein Symbol in `warnung`. Werte reichen höchstens bis kurz vor den Titel und
werden sonst in der Mitte gekürzt.

**Lüfter im System-Menü** (`LuefterAbschnitt`): Die Zeile zeigt Stufe, Drehzahl und Wunsch in Geist Mono, von
lang nach kurz der erste Text, der passt: «Stufe 2 von 4 · 3120 U/min · mind. 2», «Stufe 2 · 3120 U/min · mind. 2»,
«Stufe 2 · mind. 2»; ausgeschaltet «aus · Auto», beim Argon ONE V3 «55 % · Auto». Kann zenos-argon den Wunsch umsetzen,
ist die Zeile ein Eintrag wie die übrigen (Zeigen und Fokus mit `flaeche2`) mit dem Pfeil wie bei «Netze in
Reichweite»; sonst bleibt sie reine Anzeige ohne Zusatz.

- Klick, Enter oder Leertaste klappen darunter die Wahl auf (ohne Animation, die Karte wächst einfach): fünf
  gleich breite Segmente «Auto · 1 · 2 · 3 · 4», bündig mit den Titeln, 32 px hoch, Fläche `flaeche2` mit Radius 10;
  das gewählte Segment hebt sich mit `flaeche` ab, Text 13 px, gewählt in `text`, sonst `gedaempft`. Zeigen hinterlegt
  ein Segment mit `flaeche` zu 45 % (120 ms).
- Tastatur: Pfeil runter bzw. Enter auf der Zeile führt in die Wahl, Pfeile links/rechts (Pos1/Ende) wandern, der
  Fokusrahmen (2 px Akzent) zeigt das Segment; Enter oder Leertaste wählt. Pfeil hoch/runter und Esc wie im Menü.
- Darunter eine Zeile 12 px in `gedaempft`: «Folgt der Temperatur.» bzw. «Mindestens Stufe 2, bei Wärme schneller.»,
  während des Einstellens «Wird eingestellt …». Die neue Wahl ist sofort hervorgehoben und gilt, bis zenos-argon sie
  in `geraet.json` bestätigt (höchstens etwa 2 s, beim V3 5 s). Fehler und eine ausbleibende Bestätigung erscheinen
  ruhig als Hinweis (Warnung), die Wahl springt zurück. Kein Passwort (polkit, `docs/sicherheit.md`), während der
  Sperre nie.

Läuft gerade ein Update aus dem Kanal oder der Ubuntu-Basis (install.sh bzw. apt mit Block-Inhibitor), steht bei
«Neustart» und «Ausschalten» rechts
in Mono «Update läuft»; beide fragen dann nicht nach, ein Klick schliesst das Menü und zeigt den Hinweis (Warnung)
«Update läuft: Ausschalten geht erst danach (meist wenige Minuten)». Sonst steht bei «Neustart» in Mono «nötig»,
solange Updates einen Neustart brauchen (`/run/reboot-required`), mit denselben Grenzen wie das Symbol im System-Knopf
(«Update läuft» geht vor).

Solange die Firewall aus ist, steht im System-Menü unter «Einstellungen» der Eintrag «Firewall» mit dem Wert «aus»
und dem offenen Schloss, ohne Farbe; er öffnet die Einstellungen (System). Ist sie an, fehlt er.

Unter «Sperren» steht «Bildschirm aus» mit dem Symbol `monitor`, ohne Rückfrage: Das Menü schliesst, zenOS sperrt und
schaltet den Bildschirm aus, eine Taste weckt ihn (`docs/module/energie.md`). Dasselbe im Befehlsfeld («Bildschirm
aus», dazu «Energie» für die Seite) und mit Super+Shift+L.

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

- **Links, «wo bin ich»:** Zeichen (18 px, unterer Stein im Modus-Akzent), Modus-Chip, Zustand-Chip (nur wenn aktiv,
  mit Restzeit), Raster (Kurzname), direkt daneben die Ablage. Das Zeichen ist ein Knopf wie die übrigen der Leiste
  (Zeigen färbt leicht ein): Ein Klick öffnet die App-Übersicht des Befehlsfelds, ein zweiter schliesst sie.
- **Ablage:** Knopf mit dem Symbol `ordner` (15 px, `text`), 32 px breit wie Hell/Dunkel, 6 px rechts vom Raster.
  Ein Klick öffnet `~/Ablage` im Dateimanager (Thunar). Er erscheint und verschwindet mit dem Raster (Leiste
  `reduziert` und `aus` ohne ihn).
- **Mitte:** Datum und Uhrzeit in Geist Mono. Der nächste Termin kommt «Danach».
- **Rechts:** Mitteilungen mit nächster Zustellung («3 · 10:00», «2 warten»), Hell/Dunkel (Mond im Hellen, Sonne im
  Dunkeln), System-Knopf auf `abgesetzt` (Netz, Ton, 1Password, Temperatur, Neustart nötig, mit Akku zuletzt der
  Akku). Die Dev-Server-Übersicht kommt «Danach».
- **Neustart nötig** (`/run/reboot-required`, etwa nach einem Kernel- oder greetd-Update): das Symbol `neustart` mit
  14 px in `gedaempft` im System-Knopf, ohne Farbe, ohne Blinken, ohne Mitteilung und ohne Popup; der Screenreader
  hört «Neustart nötig». Leitplanke (Code in `dienste/basis.js`, nicht abschaltbar): nur bei voller Leiste, nie
  während der Bildschirm geteilt wird, nie bei Leiste `reduziert` oder `aus`, nie auf der Sperre. zenOS startet nie
  selbst neu.
- **Netz im System-Knopf:** Kabel als Buchse, WLAN mit Signalstufe: drei Bögen ab 60 %, zwei ab 35 %, sonst einer;
  die fehlenden Bögen blass (30 % der Farbe), ohne Animation. Ohne Verbindung `wlan-aus` in `gedaempft`.
- **Akku** (nur wenn das Gerät einen hat, z. B. Argon ONE UP): Symbol 15 px, waagrecht, der Füllstand in bis zu drei
  Strichen, beim Laden ein Blitz; daneben die Prozent in Geist Mono 12 («87 %»), beides in `text`. Bei höchstens
  10 % im Akkubetrieb stehen Symbol und Zahl in `warnung`, ruhig und ohne Blinken. Ohne sicheren Messwert nur das
  leere Symbol in `gedaempft`.
- **Zustand und Leiste:** Ein Zustand kann die Leiste zurücknehmen (Schlüssel `leiste`). `reduziert` blendet Raster,
  Ablage und Hell/Dunkel aus, `aus` lässt nur Zustand und Uhrzeit stehen. Der Platz bleibt in beiden Fällen reserviert,
  damit Fenster nicht springen. Einzelheiten in `docs/module/m4.md`.

### App-Leiste (rechter Rand)

Wechselt mit der Maus zwischen offenen Apps, auch wenn eine im Vollbild läuft. Sonst ist von ihr nichts zu sehen:
keine Kante, kein Strich.

- **Auslösen:** Pro Bildschirm liegt im mittleren Drittel des rechten Rands eine unsichtbare Zone von 1 px (Ebene
  Overlay, damit sie auch über Vollbild-Fenstern liegt). Die Leiste erscheint erst, wenn der Zeiger dort 300 ms
  verweilt; wandert er dabei mehr als 24 px auf oder ab, beginnt die Zeit neu. Oben und unten am Rand passiert
  nichts. 1 px genügt, weil der Zeiger am Rand anstösst, und nimmt dem Fenster darunter am wenigsten weg (etwa die
  Bildlaufleiste eines Browsers im Vollbild): Ein Klick genau in diese letzte Spalte erreicht das Fenster nicht,
  denn unter Wayland nimmt eine Fläche, die das Zeigen bemerkt, auch die Klicks. 300 ms sind länger als ein
  Vorbeistreifen oder Überschiessen beim Zielen (meist unter 200 ms) und kürzer als die 500 ms der
  Einrast-Vorschau.
- **Karte** wie die Menüs: `flaeche`, Rahmen `linie2`, Radius 12, ohne Schatten; 72 px breit, 8 px vom Rand,
  senkrecht mittig. Zellen 48 px mit Symbol 40 px, 4 px Abstand, innen 8 px oben und unten, 12 px seitlich. Zeigen
  hinterlegt mit `flaeche2` (Radius 10, 120 ms). Ohne Symbol der Anfangsbuchstabe auf `flaeche2` wie in der
  App-Übersicht. Passen nicht alle Apps in die Höhe, scrollt die Spalte.
- **Markierungen:** Die aktive App hat einen Punkt (5 px) im Akzent rechts neben dem Symbol, zum Rand hin. Mehrere
  Fenster einer App zeigt eine Zahl unten rechts am Symbol (Pille 18 px, `flaeche`, Rahmen `linie2`, Geist Mono 12
  in `text2`, ab zehn «9+»).
- **Beschriftung:** Beim Zeigen steht der Name der App links neben der Karte auf Höhe des Symbols (28 px, Radius 8,
  `flaeche`, Rahmen `linie2`, Geist 13 in `text`, höchstens 240 px, sonst gekürzt), ein- und ausgeblendet in
  120 ms. Klicks gehen dort durch.
- **Bewegung:** Die Karte gleitet in 200 ms von rechts herein (Lage, `OutCubic`), die Deckkraft folgt in 120 ms.
  Ausblenden nur über die Deckkraft (120 ms). Keine Bewegung pro Symbol; Einträge, die beim Hereingleiten unter dem
  ruhenden Zeiger durchziehen, gelten nicht als gezeigt.
- **Verschwinden:** 400 ms, nachdem der Zeiger Karte und Zone verlassen hat (kurzes Abrutschen schliesst nicht),
  sofort nach einem Klick auf eine App und sobald Befehlsfeld, ein Menü der Leiste, die Modus- oder Zustand-Wahl,
  die Zentrale oder die Fensterübersicht aufgehen. Während Sperre und Einrichtung erscheint sie nie.
- **Reihenfolge** fest, nach dem ersten Fenster jeder App; neue Apps kommen unten dazu, nichts springt beim
  Wechseln.
- **Klick** holt das zuletzt aktive Fenster der App nach vorne, auch ein minimiertes und auch über ein
  Vollbild-Fenster. Ist die App schon aktiv und hat mehrere Fenster, kommt das nächste.
- Fenster der Oberfläche selbst (Einstellungen) erscheinen nicht. Ohne offene App gibt es weder Leiste noch Zone.
  Bedient wird nur mit der Maus; die Tastatur hat das Befehlsfeld und Alt+Tab.

### «Heute»

Hintergrund auf jedem Bildschirm, in `grund`: Wochentag und Monat (Mono, Grossbuchstaben), Tageszahl in Instrument
Serif 300 px, Gruss nach Tageszeit mit Name (kursiv), Zusammenfassung, Moduszeile mit Akzentpunkt, unten die
Tastenkappen für Befehlsfeld, Modus und Zustand. Die rechte Spalte (Termine, Aufgaben, Wetter) kommt «Danach».
Während einer Freigabe und bei `heute: false` blendet der Inhalt aus (200 ms).

Solange der Schreibtisch frei ist (Super+H, siehe «Schreibtisch»), steht rechts neben den drei Tastenkappen eine
vierte: «Super H · Fenster zurück». Sie blendet in 120 ms nur über die Deckkraft ein und aus; die anderen bleiben
stehen, nichts rückt.

### Befehlsfeld

- 720 px breit, 104 px von oben, Radius 16, `flaeche` mit Rahmen `linie2`, Hintergrund `abdunkeln`.
- Eingabezeile 62 px, Einträge 44 px (Radius 8, Auswahl `flaeche2`), Werkzeug-Chips 34 px.
- Reihenfolge der Abschnitte: Rechnen, Apps und Aktionen, Modus und Zustand, Dateien, Werkzeuge. «Projekt» kommt
  «Danach».
- Findet eine Suche nichts: Zeichen 32 px einfarbig `gedaempft`, darunter «Keine Treffer».
- `Esc` schliesst, `Tab` springt zu den Werkzeugen. Fusszeile: «↑↓ wählen · ↵ ausführen · Tab Werkzeuge · Esc
  schliessen».

**App-Übersicht** (Klick auf das Zeichen der Leiste): eine Ansicht des Befehlsfelds, kein eigenes Fenster.

- Bei leerem Feld statt der Liste ein Raster aus Kacheln unter dem Abschnittstitel «Apps»: alle installierten Apps
  inklusive Web-Apps, alphabetisch. Kacheln mindestens 112 px breit (Spaltenzahl folgt der Breite, im Befehlsfeld
  6) und 104 px hoch, Fläche 3 px innerhalb der Zelle, Radius 10. Symbol 40 px, darunter der Name in Geist 13 px
  (`text`), höchstens zwei Zeilen; passt ein Wort nicht in eine Zeile, einzeilig gekürzt. Ohne Symbol der
  Anfangsbuchstabe auf `flaeche2`, Radius 10.
- Auswahl wie in der Liste mit `flaeche2` hinterlegt; per Tastatur gewählt zusätzlich der Fokusrahmen. Die Werkzeuge
  fehlen hier. Fusszeile «←↑↓→ wählen · ↵ starten · Tippen sucht · Esc schliessen».
- Die Karte wächst mit dem Raster bis zur Höchsthöhe des Befehlsfelds, danach scrollt das Raster.
- Ohne Apps: Zeichen 32 px einfarbig `gedaempft`, «Noch keine Apps installiert» und der Knopf «Apps installieren»
  (sekundär, mit Fokusrahmen, Enter genügt).
- **Aufgleiten:** Über das Zeichen geöffnet blendet die Karte in 120 ms ein und wächst in 200 ms von
  `bewegung.massstab` auf 1, mit dem Zeichen als Ursprung (dadurch rückt sie ein paar Pixel vom Zeichen her in ihre
  Lage). Die Kacheln blenden diagonal von oben links ein, je Diagonale 10 ms später ((200 − 120) / 8, höchstens 8
  Stufen), jede in 120 ms mit `bewegung.versatz` px nach oben. Alles ist nach 200 ms fertig. Aus der Suche heraus
  geöffnet blenden nur die Kacheln ein; geschlossen wird wie immer nur über die Deckkraft.

### Mitteilungen

- Karten oben rechts unter der Leiste: 380 px, `flaeche`, Rahmen `linie2`, Radius 12, Zeiten in Geist Mono, ohne
  Schatten. Die Sammelkarte verschwindet nach 10 s, dringende Karten bleiben bis zum Schliessen. Solange auf ihrem
  Bildschirm ein Menü der Leiste offen ist, und solange die Fensterübersicht offen ist, treten die Karten zurück und
  kommen danach wieder (120 ms, nur Deckkraft); die 10 s der Sammelkarte beginnen dann von vorn.
- Zentrale als Panel rechts (400 px). Kein Ton, kein Blinken; neue Karten kommen unten dazu, damit nichts verrutscht.
- zenOS selbst meldet sich bei Updates (jede Mitteilung nur einmal je Zustand: «zenOS aktualisiert» still, «Update
  gescheitert» normal, «Update kaputt» und «Updates blockiert» dringend, dazu «Anker fehlt», «Update abgelehnt»,
  «Update wartet auf deine Zustimmung», «Seit 14 Tagen kein Kontakt zu origin», beim Zeitpunkt «Von Hand» «Update
  bereit» und «Zeitpunkt für Updates geändert», wenn ihn nicht die Einstellungen setzten; Verweise nennen
  «Einstellungen › System › Updates»; `docs/image-und-releases.md`), bei den Basis-Updates («Ubuntu-Basis
  aktualisiert» still, «Basis-Update kaputt» dringend, «Basis-Update gescheitert» normal und «Basis-Updates warten
  auf dich» bzw. «Basis-Updates gesperrt», wenn die Automatik Kernel, Firmware, Bootloader, Entfernungen oder ein
  geschütztes Paket sah, je einmal, bis sich genau das ändert; zu «Neustart nötig» keine) und bei niedrigem Akku
  (10 % und 5 % im Akkubetrieb, je einmal): Absender
  «zenOS» mit der Bildmarke. 10 % mit Dringlichkeit normal, also nach der Regel des Zustands wie jede andere Mitteilung. 5 %
  dringend: Die Karte kommt sofort (ausser im Zustand «keine») und bleibt bis zum Schliessen, ohne Ton und ohne
  Blinken; bei 3 % schaltet zenOS kontrolliert aus, also darf sie nicht warten. Es steht immer nur eine
  Akku-Mitteilung da (5 % ersetzt 10 %), und am Netzteil verschwindet sie. Bei 3 % (drei Messungen) ersetzt sie die
  dringende Karte «Akku fast leer» / «zenOS schaltet um 22:41 aus. Netzteil anschliessen bricht ab.»; auf der Sperre
  steht dieselbe Uhrzeit in der ruhigen Zeile der Vorwarnung, mit dem Symbol `akku-leer` in `warnung`.

### Fenster

- Radius 12 an den oberen Ecken (labwc rundet nur die Titelzeile, unten eckig), Titelzeile 34 px, Titel in Geist Mono.
- Das aktive Fenster hat einen 1-px-Rand im Modus-Akzent.
- Eingerastete Fenster behalten die runden oberen Ecken; zwischen den Fenstern und zur Leiste liegen 8 px.
- Titelzeile, Akzentrand und Radius gelten für Fenster mit labwc-Rahmen. Apps mit eigenem Rahmen (Chrome,
  GTK4/libadwaita) behalten ihren; eingerastet ragt ihr eigener Schatten in die 8-px-Lücke (`docs/module/m9.md`,
  «Apps mit eigenem Rahmen»).

### Fensterwechsler (Alt+Tab)

labwc zeichnet ihn selbst, als Liste (Stil «classic»), mittig auf dem Bildschirm mit dem Fokus. So breit wie das
Befehlsfeld (720 px), `flaeche` mit 1-px-Rahmen `linie2`, innen 8 px. Jeder Eintrag beginnt mit dem App-Symbol
(40 px wie in App-Übersicht und App-Leiste), dann App-Name und Fenstertitel in Geist 16 px (`text`); der Titel fehlt,
wenn er nur die App-Kennung wiederholt. Einträge 12 px seitlich und 8 px oben und unten. Der gewählte Eintrag ist
mit `flaeche2` hinterlegt und hat den 2-px-Rahmen im Akzent wie der Tastaturfokus; das gewählte Fenster selbst
umrandet labwc im Akzent. Grenzen von labwc 0.9: keine runden Ecken, eine Schrift für Name und Titel (der Titel kann
nicht kleiner oder gedämpft sein). Grössen und Farben schreibt `zenos-thema`, Felder und Schrift `zenos-labwc`.
Warum nicht der Stil mit Vorschaubildern: `docs/module/m9.md`, «Entscheidungen».

### Fensterübersicht (Super+Tab)

Alle offenen App-Fenster auf einen Blick, als Karten ohne Vorschaubilder (`shell/uebersicht/`). Sie öffnet mit
Super+Tab, mit drei Fingern nach oben auf dem Touchpad, über die Aktion «Fensterübersicht» im Befehlsfeld oder mit
`zenos-ipc uebersicht umschalten` und bleibt offen, ohne dass eine Taste gehalten wird. Das unterscheidet sie von
Alt+Tab. Warum ohne Bilder: `docs/module/m9.md`, «Entscheidungen».

- **Fläche:** je Bildschirm eine Fläche über den ganzen Bildschirm, Ebene Overlay (liegt damit auch über Vollbild),
  Namespace `zenos-uebersicht`. Hintergrund `zudecken`, kein Weichzeichnen.
- **Filterzeile:** Pille oben mittig, 72 px von oben (Leiste + 32), 360 × 40 px, Radius 999, `flaeche` mit Rahmen
  `linie2`. Lupe 16 px in `gedaempft`, Platzhalter «Tippen filtert» in `gedaempft`, Eingabe in Geist 14 (`text`),
  Textcursor als stehender Strich (1 px, `text`).
- **Kacheln:** 216 × 164 px, Lücke 16 px, Karte wie die Menüs (`flaeche`, Rahmen 1 px `linie2`, Radius 12, ohne
  Schatten). App-Symbol 56 px mittig, darunter App-Name in Geist 14 (`text`) und Fenstertitel in Geist 12
  (`gedaempft`), höchstens zwei Zeilen, dann gekürzt. Ohne Symbol der Anfangsbuchstabe (Geist 16, `text2`) auf
  `flaeche2` mit Radius 12. Name und Symbol kommen wie in der App-Leiste aus dem Starter der App.
- **Markierungen:** Das beim Öffnen aktive Fenster hat oben rechts einen Akzentpunkt (5 px) wie in der App-Leiste.
  Oben links in Geist Mono 12 (`gedaempft`) «minimiert» oder «Vollbild», bei mehreren Bildschirmen dazu der Name
  des Bildschirms, wenn das Fenster auf einem anderen liegt.
- **Auswahl:** Zeigen und Auswahl hinterlegen die Karte mit `flaeche2` (120 ms); per Tastatur gewählt kommt der
  Fokusrahmen dazu (2 px im Akzent). Die Startauswahl ist das vorige Fenster: Super+Tab und ↵ führt zurück wie
  Alt+Tab.
- **Reihenfolge:** fest wie in der App-Leiste. Apps stehen nach ihrem ersten Fenster, die Fenster einer App
  nebeneinander. Nichts springt, wenn ein anderes Fenster aktiv wird.
- **Raster:** so viele Spalten, wie mit 48 px Rand in die Breite passen (bei 1920 px 7), die Zeilen ausgeglichen
  (10 Fenster ergeben 5 × 2, 12 auf 1440 px 4 × 3). Mittig zwischen Filter- und Fusszeile. Passt es nicht in die
  Höhe, scrollt das Raster (ohne Animation), und die Auswahl bleibt ganz sichtbar.
- **Fusszeile** direkt unter den Kacheln (am unteren Rand läge sie auf den Tastenkappen von «Heute»), Geist 13 in
  `gedaempft`, vier Teile mit 20 px Abstand: «←↑↓→ wählen», «↵ wechseln», «Tippen filtert», «Esc schliessen». Ohne
  Fenster nur «Esc schliessen».
- **Leer:** Zeichen 32 px einfarbig `gedaempft`, darunter «Keine offenen Fenster» bzw. «Keine Treffer».
- **Freigabe:** Während der Bildschirm geteilt wird, steht statt des Titels «Titel verborgen», und die Titel werden
  nicht durchsucht (wie die Dateien im Befehlsfeld).

**Bewegung:** Die Fläche blendet in 120 ms nur über die Deckkraft ein und aus. Die Kacheln blenden gestaffelt ein
wie im App-Raster: je Diagonale 10 ms später, höchstens 8 Stufen, jede in 120 ms mit `bewegung.versatz` px nach oben.
Alles ist nach 200 ms fertig. Beim Wählen läuft der Wechsel sofort, das Ausblenden darüber. Fenster fliegen nicht an
ihren Platz (ohne Lage und Bild der Fenster ginge das nicht, und ein Übergang über den ganzen Bildschirm würde am Pi
am ehesten ruckeln). Kommen oder gehen Fenster, ordnen sich die Kacheln ohne Animation neu.

**Bedienung:**

- **Tastatur:** Pfeile wandern im Raster, Tab und Shift+Tab wählen das nächste bzw. vorige Fenster, Pos1 und Ende
  springen an den Anfang bzw. ans Ende (solange der Filter leer ist). ↵ wechselt, Esc oder ein zweites Super+Tab
  schliesst.
- **Tippen** filtert sofort nach App-Name, Titel und App-Kennung, bewertet wie im Befehlsfeld; der erste Treffer ist
  gewählt.
- **Maus:** Zeigen wählt (nur bei echter Bewegung), ein Klick auf eine Kachel wechselt. Ein Klick daneben oder in
  eine Lücke schliesst, ebenso Rechts- und Mittelklick. Ein Klick in die Filterzeile (auch auf Lupe und Rand) setzt
  den Cursor ins Feld und schliesst nicht. Das Rad scrollt ein übervolles Raster.
- **Touchpad:** Drei Finger nach unten schliessen, drei Finger nach oben öffnen (bei offener Übersicht tun sie
  nichts, damit beim Nachwischen nichts flackert).

**Verhalten:**

- Minimierte Fenster stehen an ihrem Platz mit «minimiert»; Wählen holt sie zurück. Ein gewähltes Fenster kommt
  auch über ein Vollbild-Fenster.
- **Mehrere Bildschirme:** Filter, Kacheln und Tastatur liegen nur auf dem Bildschirm des aktiven Fensters (ohne
  aktives Fenster auf dem ersten), dort stehen alle Fenster. Die anderen Bildschirme sind nur zugedeckt; ein Klick
  dort schliesst. Je Bildschirm die eigenen Fenster wie bei Mission Control kommt «Danach».
- **Bildschirme ändern sich:** Wird ein Bildschirm abgesteckt oder angesteckt (auch ein Ausgang aus oder an, etwa
  über kanshi oder den Deckel), während die Übersicht offen ist, geht sie zu. Fiele ihr Bildschirm weg, bliebe sie
  sonst ohne Tastatur offen, und Getipptes ginge ungesehen an das Fenster dahinter; ein neuer bekäme nur die
  zugedeckte Fläche. Lage, Auflösung und Skalierung allein ändern nichts.
- Fenster der Oberfläche (Einstellungen) fehlen wie in der App-Leiste; für sie gibt es Super+Komma. Es schliesst die
  Übersicht und holt die Einstellungen nach vorn, auch wenn sie schon offen sind (sie springen dann auf die
  Startseite).
- **Fenster von aussen:** Solange die Übersicht die Tastatur hat, aktiviert labwc 0.9.3 kein anderes Fenster. Ein
  neues Fenster erscheint als weitere Kachel, die Übersicht bleibt offen. Alt+Tab wählt dahinter ein Fenster und hebt
  es, aktiv wird es aber erst, wenn die Übersicht zugeht; sie selbst bleibt offen (beides im Container geprüft). Wird
  doch einmal ein anderes Fenster aktiv, geht sie zu.
- **Eine Fläche zur Zeit:** Öffnet die Übersicht, schliessen Befehlsfeld, Modus- und Zustand-Wahl, Zentrale und
  ein offenes Menü der Leiste. Öffnet eine von ihnen, ein Menü der Leiste oder die Einstellungen, schliesst die
  Übersicht (Super+Leertaste bei offener Übersicht führt also direkt ins Befehlsfeld). Die App-Leiste erscheint
  nicht, die Mitteilungskarten treten zurück.
- Während Sperre, Einrichtung und polkit-Dialog öffnet sie nie; das Sperren und eine Passwortfrage von polkit
  schliessen sie. Nach dem Ausblenden ist der Filter leer.

### Schreibtisch (Super+H)

Super+H, die Aktion «Schreibtisch zeigen» im Befehlsfeld oder `zenos-ipc schreibtisch umschalten` minimiert alle
sichtbaren App-Fenster auf allen Bildschirmen, auch Vollbild-Fenster. Leiste, «Heute» und App-Leiste bleiben
stehen, ebenso Fenster der Oberfläche (Einstellungen). Ein zweites Super+H holt genau diese Fenster zurück: das
zuletzt aktive oben und wieder aktiv. Was vorher schon von Hand minimiert war, bleibt unten.

- **Frei:** Solange alle gemerkten Fenster minimiert sind und kein App-Fenster sichtbar ist, gilt der Schreibtisch
  als frei. Dann heisst die Aktion im Befehlsfeld «Fenster zurück», und «Heute» zeigt die Tastenkappe «Super H ·
  Fenster zurück».
- **Vorbei:** Holst du ein Fenster anders zurück (App-Leiste, Alt+Tab, Übersicht) oder erscheint ein neues, ist der
  Schreibtisch nicht mehr frei. Das nächste Super+H minimiert dann wieder alles Sichtbare. Ohne App-Fenster
  bewirkt Super+H nichts.
- **Neuladen:** Lädt die Oberfläche neu (nach dem Entsperren, wenn während der Sperre ein Update kam), bleibt der
  Schreibtisch frei, und Super+H holt dieselben Fenster zurück. Startet sie ganz neu (am Ende von `zen update` oder
  eines Updates ohne Sperre, wenn sich die Oberfläche geändert hat), ist der Merker weg; die Fenster kommen dann
  einzeln zurück (App-Leiste, Alt+Tab, Übersicht).
- **Ruhig:** kein Hinweis, kein Symbol in der Leiste, keine Animation (labwc minimiert ohne Übergang, ein
  nachgebauter Übergang würde ruckeln). Während Sperre und Einrichtung wirkt es nicht.

### Einstellungen

Eigenes Fenster mit labwc-Titelzeile. Navigation 260 px (Modi, Zustände, Raster, Bildschirme, darunter Web-Apps,
Apps, Allgemein, Energie, System), Titel in Instrument Serif, Felder zweispaltig. Was erst später wirkt, ist mit
«später» markiert und nicht bedienbar.

- Wenige feste Möglichkeiten zeigen Segmente (Fläche `flaeche2`, das gewählte Segment hebt sich mit `flaeche` ab),
  Zahlen eine Stufenwahl mit − und +. Beide gehen mit Tab und Pfeiltasten.
- «Allgemein» → «Scroll-Tempo für Touchpad und Maus»: vier Segmente «Langsam», «Normal», «Schnell», «Sehr schnell»,
  ohne Zahlen. Die Wahl wirkt nach dem Speichern sofort (unter einer Sekunde), ohne Abmelden. Ein Wert, den es nur von
  Hand gibt, steht gedämpft daneben («Eigener Wert: 0,75-fach»), dann ist kein Segment gewählt.
- «Allgemein» → «Automatische Sperre nach»: unter der Stufenwahl ein stiller Knopf «Bildschirm aus nach der Sperre:
  Energie» (Symbol `monitor`, 13 px), der die Seite «Energie» öffnet. Die Sperre selbst bleibt auf «Allgemein», sie
  ist Sicherheit.
- «Energie» (`SeiteEnergie.qml`), von oben nach unten, wie die anderen Seiten zweispaltig:
  - «Ohne Eingabe»: die Zeitleiste als ruhiger Satz in `text`, z. B. «Gesperrt nach 5 Min. · Bildschirm aus nach
    6 Min. · Aus nach 65 Min. im Akkubetrieb».
  - «Bildschirm aus»: Stufenwahl 1–10 «Min.», daneben «nach der Sperre» und bei einem Wert von Hand gedämpft «Eigener
    Wert: … · es gelten N Min.». Darunter 13 px `gedaempft` «Dunkel heisst gesperrt: … Am Login-Bildschirm geht er
    nach 1 Min. ohne Eingabe aus.» und «Sofort sperren und Bildschirm aus» mit der Tastenkappe «Super Shift L».
  - «Ausschalten, wenn gesperrt»: Segmente «Nie · Im Akkubetrieb · Immer»; ausser bei «Nie» darunter «Nach»,
    Stufenwahl 30–240 in Schritten von 30 «Min.», «gesperrt ohne Eingabe». Hinweise in `gedaempft` (14 px, Zeilenhöhe
    1,45, nur reiner Text): Vorwarnung und Wächter, ohne Akku «Kein Akku erkannt …», mit Akku der feste Hinweis auf
    3 % und auf den Login-Bildschirm (30 Min. im Akkubetrieb). Ist gerade etwas im Weg, «Zurzeit nicht: SSH-Sitzung
    offen» in `text2` (alle 15 s neu, solange die Seite offen ist); ohne Akku bei «Im Akkubetrieb» nicht, das sagt
    «Kein Akku erkannt» schon.
  - «Ein/Aus-Taste»: Segmente «Sperren · System-Menü · Ausschalten» und ein Hinweis, was kurz drücken und halten tun.
  - «Zuklappen» und «Bereitschaft»: nur Text in `gedaempft` («Sperrt sofort und schaltet den Bildschirm aus …» bzw.
    «Auf diesem Gerät nicht verfügbar: Der Kernel bietet keinen Schlafzustand an …»).
  - Zuletzt der Leitplankenhinweis mit Schloss: «Die automatische Sperre bleibt immer aktiv, nichts auf dieser Seite
    verzögert sie …», darunter der Fuss mit dem Pfad wie bei «Allgemein».

Auf der Seite System steht zuoberst der Schalter «Firewall» mit Zustand («An», «Aus», «Wartet auf dein
Passwort …») und einer Zeile Erklärung in `gedaempft`. Beim Ausschalten zeigt der Schalter sofort «aus»; bricht die
Passwortabfrage ab, springt er zurück.

Darunter «Updates · zenOS» (`SeiteSystem.qml`, Dienst `Kanal`; `einstellungen oeffnen system/updates` scrollt
dorthin):

- Die Lage als Zeile mit Symbol (16 px) und Titel in `text`: «Aktuell» (Haken im Akzent), «Neue Version bereit»
  (Info im Akzent), «Wartet auf deine Zustimmung» (Schloss im Akzent), «Kanal dev, nur von Hand» bzw. «Neuer Stand
  auf dev» (Code), «Anker fehlt» (offenes Schloss in `warnung`), «Blockiert» und «Prüfung abgebrochen» (Warnung in
  `warnung`), «Kein Kontakt» (Wolke), «Noch nie geprüft» (Info, `gedaempft`). Die Lage der Installation geht vor:
  «Update läuft» (Info im Akzent, solange die Übernahme läuft), «Update kaputt» und «Update unterbrochen»
  (Warnung in `warnung`, bis eine spätere Installation es ablöst); nach `zen rollback` «Zurückgestellt: v0.1.0-rc4
  läuft, v0.1.0-rc5 vorhanden» (Info, `gedaempft`). Darunter ein ruhiger Satz in `gedaempft` (13 px, Zeilenhöhe
  1,45), nur reiner Text; bei «kaputt» mit dem Weg («Zuerst den Grund beheben, dann im Terminal zen update»).
- Werte zweispaltig, Titel 96 px in `gedaempft`, Werte in Geist Mono 13 (`text`, zu lang: am Ende gekürzt): Kanal,
  Installiert («v0.1.0-rc4 · 1a2b3c4d5e6f»), Letztes Update (nur bei gescheitert, zurück, abgebrochen oder kaputt:
  «gescheitert, zurück auf dem Stand davor · heute, 11:00 · v0.1.0-rc5 (…)»), Von Hand (angehaltener Stand), Bereit
  (mit dem Wann je Zeitpunkt: «kommt bei der nächsten Sperre», «frühestens morgen, 03:30, danach zwischen 02:00 und
  05:00», «nur über «Jetzt installieren» oder zen update»), Geprüft und Kontakt («heute, 14:03», «gestern, …»,
  «3. Okt., …»), Anker «Serie 1», Wurzel und Release als «SHA256:9xQZHFzU…» (die ersten 8 Zeichen, wie in 1Password
  abgeglichen). Die Zeilen bauen sich nur neu auf, wenn sich etwas ändert.
- Knöpfe 38 px: «Jetzt prüfen» (sekundär, während des Laufs «Prüft …»), «Jetzt installieren» (primär, nur wenn es
  etwas gibt; währenddessen «Wird installiert …») und «Zustimmen …» (sekundär mit Schloss, nur bei Firewall, Netz
  oder Boot; danach fragt der polkit-Dialog nach dem Passwort). Darunter in `gedaempft`, was die Zustimmung betrifft
  und wofür sie gilt («Ändert scripts/module/35-netzwerk.sh. Zustimmen verlangt dein Passwort und gilt nur für
  v0.1.0-rc5 (Objekt …).»), sonst bei «Jetzt installieren» «Installiert genau den angezeigten, schon geprüften Stand.
  Die Oberfläche lädt danach neu, wenn sie sich geändert hat.» Während eines Updates steht dort nichts (Titel und
  Satz oben sagen es).
- Rückmeldungen als Hinweis nur, wo keine Mitteilung kommt («Updates geprüft», «zenOS ist schon aktuell», «Das Update
  braucht deine Zustimmung», «Gerade läuft schon ein Update …»); abgebrochene Passwortabfragen bleiben still.
- «Update läuft» zeigt nur der Abschnitt, dessen Update läuft; die Knöpfe beider Abschnitte warten, solange eines
  läuft oder eine Bedienung unterwegs ist.

Darunter «Updates · Ubuntu-Basis» (Dienst `Basis`, Pakete von Ubuntu und den Herstellerquellen über `zenos-basis`),
mit denselben Bausteinen (Lage, Satz, Werte, Knöpfe 38 px):

- Lage: «Aktuell» (Haken im Akzent), «3 Updates bereit» (Info im Akzent), «4 Updates warten auf dich» (Schloss im
  Akzent; Kernel, Firmware, Bootloader oder Entfernungen), «Gesperrt» (Warnung in `warnung`: apt würde ein
  geschütztes Paket entfernen), «Kein Kontakt zu den Paketquellen» (Wolke, `gedaempft`), «Prüfung gescheitert»
  (Warnung in `warnung`), «Noch nie geprüft» (Info, `gedaempft`). Vor allem: «Update läuft» (Info im Akzent) und
  «Basis-Update kaputt» (Warnung in `warnung`, bis eine spätere Installation es ablöst).
- Satz: bei «bereit» was ansteht und wann es automatisch kommt («Kommt automatisch bei der nächsten Sperre, nicht
  während einer SSH-Sitzung.», «… zwischen 02:00 und 05:00 Uhr …», «… innert 15 Minuten …», «Automatisch kommt nichts
  (Zeitpunkt «Von Hand»).»), bei «warten auf dich» was dabei ist und dass es nie automatisch kommt.
- Werte: Ausstehend («12 Updates · 3 Sicherheit»), Kernel/Boot, Entfernen, Geschützt, Hersteller, Neustart («nötig ·
  linux-raspi» bzw. «voraussichtlich nach dem Update»), Letztes Update («installiert · heute, 03:12 · automatisch»),
  Automatik (letzter Lauf in wenigen Worten, etwa «heute, 09:04 · nicht jetzt: …», oder «aus · einschalten: …»),
  Geprüft, Liste (die ersten 12 Zeichen des Hashs).
- Knöpfe: «Jetzt prüfen» (sekundär), «Jetzt installieren» (primär, nur bei «bereit», ohne Passwort) bzw. «Mit
  Passwort installieren» (sekundär mit Schloss, nur bei Kernel, Firmware, Bootloader oder Entfernungen). Darunter in
  `gedaempft`: «Installiert genau die angezeigte Liste (…), ohne neue Prüfung. …» bzw. «Verlangt dein Passwort und gilt
  nur für die angezeigte Liste (…). zenOS startet danach nie selbst neu.»
- Rückmeldungen wie beim Kanal: als Hinweis nur nach dem eigenen Klick («Ubuntu-Basis geprüft», «Die Liste hat sich
  geändert: bitte noch einmal ansehen», «Kernel, Firmware, Bootloader oder Entfernungen: nur mit deinem Passwort»);
  das Ergebnis einer Installation kommt als Mitteilung.

«Automatisch installieren»: Segmente «Bei Sperre · Zeitfenster · Jederzeit · Von Hand», beim Zeitfenster darunter
«Von» und «bis» mit zwei Zeitfeldern (HH:MM) und «Uhr». Ein zu kurzes Fenster (unter einer Stunde) steht ruhig in
`fehler` darunter und wird nicht gesetzt. Dann ein Satz in `gedaempft`, knapp und ehrlich je Wahl («Kommt, wenn
zenOS seit 5 Minuten gesperrt ist oder der Login-Bildschirm seit 5 Minuten wartet …», «Kommt zwischen 02:00 und
05:00 Uhr, auch wenn du gerade arbeitest. Das Gerät muss dann laufen.», «… die Oberfläche lädt dabei kurz neu.»),
danach, was immer gilt: ganzes Gerät für zenOS und die Ubuntu-Basis, im Akkubetrieb erst ab 50 %, von zenOS nur
gültig Signiertes, Zustimmung bei Firewall, Netz oder Boot, auf dev nie; die Pakete der Ubuntu-Basis auch auf dev, aber
nie während einer SSH-Sitzung und nie mit Kernel, Firmware, Bootloader oder Entfernungen, nie ein Neustart. Ist die
Datei von Hand kaputt, steht neben der Beschriftung in Mono «Datei ungültig · es gilt «Bei Sperre»» in `warnung` (ein
Problem, nichts Angepasstes; nicht im Akzent), und ein Klick auf «Bei Sperre» schreibt sie neu. Während des Setzens
zeigen die Segmente schon die neue Wahl; scheitert es, springen sie zurück.

Darunter «Im Terminal» mit den Tastenkappen «zen kanal», «zen update», «zen doctor» und «Terminal öffnen».

### Sitzung

- Der geteilte Bildschirm bekommt einen 2-px-Rahmen in `sitzung` (Radius 12) und oben mittig das Label «Dieser Bildschirm wird geteilt» (Pille 24 px, Hintergrund `sitzung`, Text `grund`, Geist Mono 12, Monitor-Symbol).
- Mitteilungen werden zurückgehalten und nur als Zahl gezeigt.
- Nach dem Ende der Freigabe bleiben Rahmen und Label rund 5 s auf dem zuletzt geteilten Bildschirm (Nachlauf, siehe
  `docs/architektur.md`). Beginnt in der Zeit eine neue Freigabe, geht es ohne Unterbrechung weiter; nichts blinkt.

### Bestätigung (polkit)

Verlangt ein Programm Administratorrechte (z. B. «Firewall ausschalten»), fragt ein ruhiger Dialog nach dem
Passwort (`shell/polkit/Polkit.qml`).

- Mittig über dem abgedunkelten Hintergrund (`abdunkeln`, kein Weichzeichnen), auf dem Bildschirm mit dem Zeiger.
  Karte 460 px, `flaeche`, Rahmen `linie2`, Radius 16 wie das Befehlsfeld, ohne Schatten.
- Oben das Zeichen 16 px einfarbig `gedaempft` mit «Bestätigung nötig» (Geist Mono 12) wie unten in der Sperre.
  Darunter, was bestätigt wird: der erste Satz der polkit-Nachricht als Titel in Instrument Serif 36 (lange
  Nachrichten 24, höchstens drei Zeilen), der Rest in Geist 14 (`text2`), dann die Kennung der Aktion in Geist Mono
  12 (`gedaempft`). Alles als reiner Text.
- «Passwort von <Konto>» (Anmeldename, nicht der Anzeigename), Passwortfeld (Eingabe, 44 px), darunter eine
  reservierte Zeile für Meldungen, rechts «Abbrechen» (sekundär) und «Bestätigen» (primär). Fusszeile wie im
  Befehlsfeld: «↵ bestätigen · Esc abbrechen».
- Falsches Passwort: Feldrahmen in `fehler`, darunter «Das Passwort stimmt nicht.» in `text2`, das Feld ist leer
  und behält den Fokus. Kein Wackeln. «Wird geprüft …» erscheint erst nach 300 ms (PAM wartet nach einem
  Fehlversuch rund 2 s).
- Ein- und Ausblenden 120 ms, nur die Deckkraft. Ein Klick daneben schliesst nicht.

### Sperrbildschirm und Login

- Grosse Uhrzeit (Instrument Serif 180 px), Datum, Anzahl Mitteilungen ohne Inhalt, Passwortfeld.
- Unten: Zeichen 16 px einfarbig `gedaempft`, daneben «zenOS gesperrt · 1Password gesperrt».
- Vorwarnung vor dem Ausschalten: über der Pille der Mitteilungen eine zweite Pille gleicher Form (Rahmen `linie2`,
  ohne Fläche), Symbol `ausschalten` 14 px in `text2`, Text 14 px in `text2`: «zenOS schaltet um 22:41 aus · Eine Taste
  bricht ab». Die Uhrzeit steht still, es tickt keine Sekunde, nichts blinkt. Bei leerem Akku dieselbe Pille mit dem
  Symbol `akku-leer` in `warnung`: «Akku fast leer: zenOS schaltet um 22:41 aus · Netzteil anschliessen bricht ab».
  Sie ist ein Systemzustand, kein Inhalt.
- Bildschirm aus: Der Bildschirm wird ohne Übergang dunkel und beim Wecken ohne Übergang hell (keine Animation, die
  ruckeln könnte). Die Taste, die weckt, erscheint nicht als Punkt im Passwortfeld. Während der Vorwarnung landet
  jede Taste im Feld (es ist zu sehen).
- Der Login sieht aus wie der Sperrbildschirm und ist immer dunkel. Unten mittig steht das Zeichen 48 px
  (unterer Stein `salbei`), rechts Neustart und Ausschalten. Die Pille der Vorwarnung (Leerlauf im Akkubetrieb oder
  leerer Akku) steht dort wie auf der Sperre unter dem Datum, auf jedem Bildschirm. Übernimmt ein Update aus dem Kanal
  gerade den Code, steht dort dieselbe Pille mit dem Symbol `info` in `text2`: «zenOS wird aktualisiert. Mit
  der Anmeldung bitte warten, bis das fertig ist.» Sie verschwindet von selbst (Takt 3 s), nichts blinkt.
- Login nach 1 Minute ohne Eingabe: Der Bildschirm wird wie auf der Sperre ohne Übergang dunkel und beim Wecken ohne
  Übergang hell, ohne Hinweis und ohne Animation. Die erste Taste, der erste Klick oder die erste Berührung weckt nur:
  kein Punkt im Passwortfeld (auch wenn die Taste gehalten wird), kein gedrückter Knopf, der Fokus bleibt, wo er war.
  Was im Feld stand, bleibt stehen.

### Erster Start

Links das Zeichen 44 px (unterer Stein im Akzent), Titel «Willkommen bei zenOS.» in Instrument Serif 76 px, rechts
das Formular 01–04 (Name, Ort, Erscheinungsbild, erster Modus mit Akzent). Danach die Zustimmung zu den Apps.

### Terminal

- Eingabezeile: Ordner, Git-Branch, Änderungen, darunter `›`.
- Jeder Befehl ist ein Block mit Statuszeile (✓ oder ✗, Dauer, Fehler in Klartext).
- Erklärungen erscheinen als Karte unter dem Befehl, Warnungen mit Rahmen in `warnung`. «Abbrechen» ist die Vorauswahl.
