# Bildmarke

Die Bildmarke von zenOS heisst «Zwei Steine»: ein Kiesel, diagonal geteilt. Zwei Steine im Gleichgewicht stehen für Ruhe. Der Schnitt folgt der Diagonale eines Z. Der untere Stein trägt die Farbe des aktiven Modus.

Alle Dateien liegen in [`assets/zeichen/`](../assets/zeichen/). Neu erzeugen im Repo-Ordner mit `python3 assets/zeichen/erzeugen.py` (Voraussetzungen in [`assets/README.md`](../assets/README.md)). Das Skript schreibt auch `geometrie.json` mit den fertigen Pfaden.

## Konstruktion

Grundraster 64 × 64 Einheiten.

| Teil | Wert |
|---|---|
| Kiesel | abgerundetes Quadrat 54 × 54 bei (5,5), Eckradius 19 |
| Schnitt | Diagonale von oben rechts nach unten links, Linie x + y = 64 |
| Spalt | 6 breit, senkrecht zum Schnitt gemessen |
| Rand | 5 |

**Unter 24 px** gilt die Pixel-Variante im 16er-Raster: Kiesel 14 × 14 bei (1,1), Eckradius 4,9, Spalt 2. Der Spalt ist relativ etwas breiter, damit er auch bei 16 px sichtbar bleibt.

Die fertigen Pfade beider Varianten stehen in [`assets/zeichen/geometrie.json`](../assets/zeichen/geometrie.json) und in [`shell/theme/tokens.json`](../shell/theme/tokens.json) unter `zeichen` (`normal` und `pixel` mit `raster`, `oben` und `unten`, dazu `pixelUnter`).

## Farbe

- **Oberer Stein:** immer `text` (hell `#1B1B19`, dunkel `#ECEAE4`).
- **Unterer Stein:** Akzent des aktiven Modus. Ohne Modus gilt `salbei` (hell `#4E6A49`, dunkel `#A7B89F`).
- **Einfarbig:** Beide Steine in `text` oder `gedaempft`, für Stellen ohne Farbe, etwa Sperrbildschirm, Doku oder Druck.
- **Farbe bleibt dem unteren Stein vorbehalten.** Der obere Stein ist nie farbig.

## Dateien und Einsatz

Alle Pfade relativ zu `assets/zeichen/`.

| Datei | Wofür |
|---|---|
| `zenos-zeichen.svg` | Einsatz im Code: `currentColor`, der untere Stein hat die ID `fokus` |
| `zenos-zeichen-hell.svg` | einfarbig auf hellem Grund |
| `zenos-zeichen-hell-farbig.svg` · `-dunkel.svg` | mit Akzent, auf hellem bzw. dunklem Grund |
| `zenos-zeichen-16.svg` | alles unter 24 px |
| `zenos-schriftzug-hell.svg` · `-dunkel.svg` | README, Titel; Schrift in Pfade umgewandelt |
| `zenos-app-icon.svg` + `png/zenos-app-icon-*.png` | App-Icon, zum Beispiel für die zenOS-Einstellungen (hicolor 48 bis 512) |
| `favicon.svg` · `favicon.ico` | Web; das SVG schaltet selbst zwischen hell und dunkel |
| `github-avatar.svg` · `png/github-avatar-500.png` | Profilbild auf GitHub |
| `github-social-preview.svg` · `png/github-social-preview-1280x640.png` | Vorschaubild des Repos |
| `geometrie.json` | Pfade und Masse für die Oberfläche |

## Schriftzug

- «zen» in `text`, «OS» in `gedaempft`. Schrift Geist Medium, Laufweite −0,03 em.
- Zeichen = 1,04 × Schriftgrösse, Abstand zum Text = 0,26 × Schriftgrösse.
- Das Zeichen ist vertikal auf die Mitte der Versalhöhe ausgerichtet.

## Schutzzone und Mindestgrösse

- Rundherum mindestens ¼ der Zeichenbreite frei.
- Mindestgrösse 16 px, dann mit der Pixel-Variante.

## Nicht erlaubt

- Drehen, spiegeln, verzerren. Der Schnitt läuft immer von oben rechts nach unten links.
- Den Spalt schliessen oder verbreitern.
- Schatten, Verläufe, Konturen.
- Den oberen Stein einfärben.
- Das Zeichen auf unruhigen Hintergründen oder Bildern.

## Einsatz in zenOS

| Ort | Grösse | Farbe |
|---|---|---|
| Leiste links | 18 px, Pixel-Variante | oberer Stein `text`, unterer Modus-Akzent |
| Login (Greeter) | 48 px | oberer Stein `text`, unterer `salbei` |
| Sperrbildschirm unten | 16 px | einfarbig `gedaempft` |
| Einrichtung beim ersten Start | 44 px | oberer Stein `text`, unterer Akzent |
| Befehlsfeld, leerer Zustand | 32 px | einfarbig `gedaempft` |
| Bootsplash | 64 px | oberer Stein `text`, unterer `salbei` |

## Umsetzung in Quickshell

- **Komponente:** `ZenZeichen.qml` zeichnet das Zeichen mit Qt Quick Shapes: zwei `ShapePath` mit `PathSvg`, die Pfade kommen aus `Theme` (`shell/theme/tokens.json` → `zeichen`). Es ist kein Bild, nur so lässt sich die Farbe des unteren Steins live umschalten.
- **Eigenschaften:** `groesse`, `obenFarbe`, `akzent`, `fokusFarbe`, `einfarbig`. `obenFarbe` ist standardmässig `Theme.text`, `akzent` der Akzent des aktiven Modus (Name, zum Beispiel `salbei` im Login), `fokusFarbe` wird daraus berechnet.
- **Kleine Grössen:** Unter 24 px schaltet die Komponente selbst auf die Pfade der Pixel-Variante um.
- **Moduswechsel:** Der untere Stein blendet in 200 ms zur neuen Farbe über, sonst bewegt sich nichts. Hell/dunkel ist kein Moduswechsel: Beide Steine wechseln im selben Bild, die einfarbige Marke bewegt sich nie.

## Bootsplash (Plymouth)

- **Theme:** `system/plymouth/zenos/`, Hintergrund `grund` (dunkel), Zeichen 64 px in der Mitte, darunter eine dünne Fortschrittslinie.
- **Ablauf:** Die zwei Steine gleiten aus leichtem Abstand zusammen, bis der Spalt 6 breit ist (300 ms). Danach blendet der untere Stein in 200 ms zur Akzentfarbe über.
- **Atmen:** Solange der Start läuft, atmet der Spalt: Er öffnet und schliesst sich um 1 Einheit, 3,2 s pro Zug. Das ist die einzige Dauerbewegung in zenOS und die bewusste Ausnahme von der 200-ms-Regel. Sie endet mit dem Login.
- **Aktivieren:** Das Theme wird mit gebaut (`scripts/module/42-bootsplash.sh`), eingeschaltet ist es nicht. Das Einschalten braucht `splash` in der Boot-Kommandozeile und läuft deshalb nur nach Rückfrage bei Zeno, mit `zen bootsplash aktivieren`. Es zeigt jeden Schritt vorher und verlangt die Eingabe «aktivieren»: `plymouth` und `plymouth-label` installieren (ohne das Label-Plugin stürzt Plymouth mit dem Modul `script` ab), `zenos` als Standard-Theme setzen, `DeviceScale=1` in `/etc/plymouth/plymouthd.conf` (sonst verdoppelt Plymouth auf 4K die 1x-Bilder), «quiet splash» in `/boot/firmware/current/cmdline.txt`, neues initramfs. Der Pi startet danach zweimal (piboot-try prüft die neuen Startdateien). Zurück mit `zen bootsplash deaktivieren`. Details: [`docs/module/bootsplash.md`](module/bootsplash.md).

## GitHub

Avatar und Vorschaubild lädt Zeno von Hand hoch: Profil- bzw. Organisationseinstellungen für den Avatar, `Settings → Social preview` für das Vorschaubild.
