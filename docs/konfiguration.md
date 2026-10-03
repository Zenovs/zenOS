# Konfiguration: Modi, Zustände, Raster, Bildschirme

Alles Persönliche liegt lokal unter `~/.config/zenos/` und nie im Repo. Neutrale Beispiele stehen in `config/beispiele/`. Bearbeitet wird über die Einstellungen in zenOS; die Dateien sind trotzdem lesbar und von Hand änderbar. Ist `einstellungen.json` ungültig (z. B. ein Tippfehler), zeigt zenOS einen Hinweis und behält die bisherigen Werte (beim Start: Standardwerte, die Einrichtung erscheint nicht); das nächste Speichern aus der Oberfläche legt die ungültige Fassung als `einstellungen.json.kaputt` daneben und schreibt die Datei neu.

Eine Datei unter `modi/`, `zustaende/` oder `raster/` mit ungültigem Inhalt fehlt in der Liste; ein aktiver Modus gilt dann als gelöscht. `zenos-konfig pruefe` nennt ungültige Dateien, `zen doctor` zählt sie. Die Schemas stehen in `config/schema/`.

## Dateien

| Datei | Inhalt | Wer schreibt |
|---|---|---|
| `~/.config/zenos/einstellungen.json` | Name, Ort, Erscheinungsbild, Sperrzeit, Mitteilungen ohne Zustand | Einrichtung, Einstellungen → Allgemein, Hell/Dunkel |
| `~/.config/zenos/modi/<id>.json` | ein Modus | Einstellungen → Modi, Einrichtung (erster Modus) |
| `~/.config/zenos/zustaende/<id>.json` | ein Zustand | Einstellungen → Zustände; Vorlagen beim ersten Mal |
| `~/.config/zenos/raster/<id>.json` | ein Raster | Einstellungen → Raster; Vorlagen beim ersten Mal |
| `~/.config/zenos/bildschirme.json` | Bildschirm-Profile | Einstellungen → Bildschirme; Vorlage, falls sie fehlt |
| `~/.config/zenos/webapps.json` | Web-Apps | Einstellungen → Web-Apps (`zenos-webapp`) |
| `~/.local/state/zenos/laufzeit.json` | was gerade gilt | die Oberfläche und `zenos-labwc`, nie von Hand |
| `/etc/xdg/zenos/kanal` | Kanal für `zen update` | Installer beim ersten Mal |
| `/etc/xdg/zenos/argon.json` | Lüfterkurve (optional) | von Hand mit sudo |
| `/etc/xdg/zenos/argon-akkuprofil` | Freigabe: zenos-argon darf Argons Akkuprofil in den Messchip schreiben (Argon ONE UP) | `zen akku freigeben`, entfernt mit `zen akku sperren` |

Die ID ist der Dateiname ohne `.json` (Kleinbuchstaben, Ziffern, Bindestriche). Geschrieben wird mit `zenos-konfig`
(`scripts/bin/`): Es prüft gegen das Schema und darüber hinaus (Akzent aus den Tokens, Raster im Bildschirm,
eindeutige Namen), schreibt nur Gültiges, atomar und nur bei einer Änderung. Befehle: `liste`, `alle`, `lese`,
`schreibe`, `aendere`, `loesche`, `pruefe`, `pfad`.

## Grundidee

- **Modus:** der Kontext, zum Beispiel Arbeit oder privat. Ab Werk gibt es keinen. Du legst sie selbst an.
- **Zustand:** wie sich zenOS gerade verhält, zum Beispiel Fokus oder Sitzung. Ein Zustand wird einmal definiert und kann pro Modus angepasst werden. Ab Werk liegen «Fokus» und «Sitzung» als neutrale Vorlagen bereit.
- **Raster:** Bereiche in Prozent, in die Fenster einrasten.
- **Bildschirm-Profil:** welches Raster gilt, je nachdem, was angeschlossen ist.

## Wie ein Zustand zustande kommt

```
wirksamer Zustand = Zustand (Vorlage)
                  + Anpassungen des aktiven Modus für diesen Zustand
                  + Leitplanken (immer zuletzt, nicht überschreibbar)
```

Die Leitplanken entfernen Schlüssel, die eine Regel aufweichen könnten (z. B. `sperreNachMinuten` in einem Zustand),
und setzen die festen Werte aus dem Code.

## Modus: `modi/<id>.json`

| Schlüssel | Typ | Bedeutung |
|---|---|---|
| `name` | Text | Anzeigename (Pflicht) |
| `akzent` | Text | Akzentfarbe aus `tokens.json`: `salbei`, `sand`, `blau`, `ton`, `graphit` |
| `chromeProfil` | Text | Anzeigename des Chrome-Profils; `zenos-chrome` startet Chrome damit |
| `mailKonten` | Liste | Konten, die coremail in diesem Modus zeigen soll. Freie Merkliste; coremail liest sie in 0.1 noch nicht |
| `heute` | Objekt | `kalender`, `aufgaben`, `wetter`: was die «Heute»-Ansicht zeigt – später |
| `oeffnen` | Liste | Apps (Desktop-ID ohne `.desktop`), die beim Wechsel öffnen, sofern sie noch kein Fenster haben. Ausnahme Chrome, wenn der Modus ein `chromeProfil` hat: Chrome öffnet, solange kein Fenster in diesem Profil offen ist |
| `raster` | Objekt | Bildschirm-Profil (Name aus `bildschirme.json`) → Raster-ID; `Standard` gilt für alle Profile ohne eigenen Eintrag |
| `zustaende` | Liste | Zustände, die dieser Modus anbietet; ohne Liste alle, eine leere Liste heisst keiner |
| `anpassungen` | Objekt | Zustand-ID → Werte, die für diesen Modus abweichen (Schlüssel wie im Zustand, ohne `name`) |

Ein Moduswechsel setzt den Akzent, schreibt den Modus in `laufzeit.json` (danach öffnen die Apps, Chrome also schon
im neuen Profil, auch wenn Chrome in einem anderen Profil schon läuft), setzt das Raster und startet Zustände mit dem
Auslöser `moduswechsel`. Das Raster kommt aus dem Eintrag des aktuellen Bildschirm-Profils, sonst aus `Standard`,
sonst (ohne Profile) aus dem einzigen Eintrag. Beim Anschliessen eines Bildschirms geht das Raster des aktiven Modus
für dieses Profil dem des Profils vor.

## Zustand: `zustaende/<id>.json`

| Schlüssel | Werte |
|---|---|
| `name` | Text (Pflicht) |
| `mitteilungen` | `alle` · `gebuendelt-<minuten>` (1–1440) · `nur-dringend` · `keine` |
| `leiste` | `normal` · `reduziert` (ohne Raster und Hell/Dunkel) · `aus` (nur Zustand und Uhrzeit); der Platz bleibt reserviert |
| `fenster` | `normal` · `fokus` (alles ausser dem aktiven Fenster tritt zurück) – noch ohne Wirkung, später |
| `heute` | `true` · `false` (blendet den Inhalt von «Heute» aus) |
| `widgets` | `true` · `false` – noch ohne Wirkung, später |
| `ausloeser` | Liste aus `manuell` · `bildschirmfreigabe` · `kalender` (später, wird ignoriert) · `uhrzeit:HH:MM` · `moduswechsel`; ohne Liste `manuell` |
| `ende` | `{ "art": "manuell" }` · `{ "art": "timer", "minuten": 50 }` (1–1440) · `{ "art": "ausloeser-endet" }` |

Die Vorlagen `fokus` und `sitzung` (`config/vorlagen/zustaende/`) kopiert der Installer genau einmal; eine gelöschte
Vorlage kommt nicht wieder.

### Auslöser und Ende

- **Angebot:** Im Umschalter und im Befehlsfeld erscheinen die Zustände, die der aktive Modus anbietet und die den
  Auslöser `manuell` haben. «Sitzung» startet nur mit der Bildschirmfreigabe.
- **Bildschirmfreigabe** startet immer, auch über einen von Hand gestarteten Zustand hinweg: den ersten angebotenen
  Zustand mit diesem Auslöser, bevorzugt `sitzung`. Bietet der Modus keinen an, bleibt der aktuelle Zustand; die
  Inhalte der Mitteilungen sind trotzdem verborgen (Leitplanke).
- **Uhrzeit und Moduswechsel** starten nur, wenn kein Zustand läuft oder ein anderer automatisch gestarteter.
  Sie überschreiben nie einen von Hand gestarteten Zustand oder eine laufende Sitzung. Ein Uhrzeit-Auslöser wirkt in
  der Minute, in der die Uhr die Zeit erreicht, und wird nicht nachgeholt.
- **Ende:** `manuell` endet nur von Hand, `timer` nach Ablauf (auch nach einem Neustart, die Endzeit steht in
  `laufzeit.json`), `ausloeser-endet` mit dem Auslöser: bei der Freigabe rund 5 s nach ihrem Ende (Nachlauf, siehe
  `docs/architektur.md`, bis dahin bleiben die Inhalte verborgen), beim Moduswechsel mit dem Verlassen des Modus. Mit
  einer Uhrzeit wirkt `ausloeser-endet` wie `manuell`.
- **Rückkehr nach einer Sitzung:** Endet eine automatisch gestartete Sitzung (auch von Hand beendet), kommt der
  vorher aktive Zustand zurück, wenn sein Timer noch läuft oder sein Ende `manuell` ist. Einer mit
  `ausloeser-endet` kommt nicht zurück.

### Mitteilungen

- `alle`: sofort.
- `gebuendelt-<N>`: zu jedem Vielfachen von N Minuten ab Mitternacht (Ortszeit), z. B. `gebuendelt-60` zur vollen
  Stunde. Die Leiste zeigt die nächste Zustellung.
- `nur-dringend`: nur Dringendes (`urgency critical`) sofort, der Rest wartet.
- `keine`: alles wartet, auch Dringendes.

Dringendes kommt ausser bei `keine` immer sofort. Wartendes kommt, wenn der Zustand endet oder mit «Jetzt
zustellen» in der Zentrale. Ohne Zustand gilt `mitteilungenStandard` aus `einstellungen.json`. Während einer
Bildschirmfreigabe wird höchstens Dringendes zugestellt, und zwar ohne Inhalt; die Vorlage «Sitzung» hält mit
`keine` alles zurück.

## Raster: `raster/<id>.json`

Bereiche in Prozent der nutzbaren Bildschirmfläche (ohne Leiste).

| Schlüssel | Bedeutung |
|---|---|
| `name` | Anzeigename (Pflicht) |
| `kurz` | Kurzname für die Leiste, höchstens 6 Zeichen, z. B. `4er` |
| `abstand` | Lücke zwischen Fenstern und zum Rand in px, 0–64, Standard 8 |
| `bereiche` | 1–12 Bereiche `{ "id", "x", "y", "b", "h" }` in ganzen Prozent |

- Nur ganze Prozente, weil labwc Regionen so liest («3 Spalten» = 33/34/33).
- `x + b` und `y + h` höchstens 100, jede `id` nur einmal (prüfen `zenos-konfig` und `zenos-labwc`).
- Die Reihenfolge ist die Nummer: Der erste Bereich ist Super+1, der vierte Super+4. Weitere Bereiche erreichst du
  beim Ziehen mit der Maus.
- Vorlagen (`config/vorlagen/raster/`): Voll, Hälften, 3 Spalten, 4er-Grid, Gross + 2. Der Installer kopiert sie
  genau einmal; ohne Eintrag gilt `4er-grid`.

## Bildschirme: `bildschirme.json`

| Schlüssel | Bedeutung |
|---|---|
| `profile` | Liste von Profilen (höchstens 20) |
| `profile[].name` | Anzeigename, eindeutig; Modi verweisen darauf |
| `profile[].ausgaenge` | Bildschirm-Ausgänge, an denen das Profil erkannt wird: Name (`HDMI-A-1`), Beschreibung «Hersteller Modell Seriennummer» oder `*` für beliebige weitere Bildschirme |
| `profile[].raster` | Ausgang (oder `*`) → Raster-ID |

- Ein Profil gilt, wenn genau seine Ausgänge angeschlossen sind; mit `*` auch mit beliebigen weiteren.
- kanshi nimmt das erste passende Profil. `zenos-kanshi` stellt Profile mit festen Ausgängen vor die mit `*`.
- labwc 0.9 kennt nur ein Raster für alle Bildschirme. Pro Profil gilt deshalb das Raster des ersten Ausgangs mit
  Eintrag, sonst das von `*`. Die Datei speichert trotzdem ein Raster pro Ausgang; die Einstellungen zeigen, welcher
  Eintrag gilt.
- Fehlt die Datei, legt der Installer die Vorlage an: ein Profil «Standard» für `*` mit dem 4er-Grid.

## Einstellungen: `einstellungen.json`

| Schlüssel | Werte | Standard | Bedeutung |
|---|---|---|---|
| `eingerichtet` | `true` · `false` | `false` | Solange nicht `true`, erscheint beim Anmelden die Einrichtung |
| `name` | Text, höchstens 60 Zeichen | leer | Gruss in «Heute» |
| `ort` | Text, höchstens 100 Zeichen | leer | Ort fürs Wetter – später |
| `erscheinungsbild` | `hell` · `dunkel` · `tageszeit` | `hell` | Erscheinungsbild |
| `tagAb`, `nachtAb` | `HH:MM` | `07:00`, `19:00` | Wechsel bei `tageszeit` |
| `sperreNachMinuten` | 1–15 | 5 | Automatische Sperre; Werte ausserhalb begrenzt der Code, abschalten geht nicht |
| `mitteilungenStandard` | wie `mitteilungen` im Zustand | `gebuendelt-60` | Bündelung ohne aktiven Zustand |

Weitere Schlüssel sind erlaubt und bleiben beim Speichern erhalten.

## Web-Apps: `webapps.json`

```json
{ "webapps": [ { "id": "beispiel", "name": "Beispiel", "url": "https://example.org/", "chromeProfil": "Beispiel" } ] }
```

- `id`, `name`, `url` sind Pflicht. `url` nur mit `https://`, ohne Zugangsdaten, Leer-, Steuer- und
  Anführungszeichen. `chromeProfil` leer: Profil des aktiven Modus. `symbol`: Symbolname oder absoluter Bildpfad.
- Zu jeder Web-App erzeugt `zenos-webapp` einen Starter `~/.local/share/applications/zenos-webapp-<id>.desktop`,
  der `zenos-chrome --app=<url>` aufruft. Das Befehlsfeld zeigt sie als «Web-App».

## Laufzeit: `~/.local/state/zenos/laufzeit.json`

Was gerade gilt und einen Neustart überdauert. Geschrieben wird nur mit `zenos-konfig aendere laufzeit` (führt die
obersten Schlüssel zusammen), damit sich Oberfläche und `zenos-labwc` nicht gegenseitig überschreiben. Von Hand
ändern ist nicht vorgesehen.

| Schlüssel | Bedeutung | schreibt |
|---|---|---|
| `modus` | ID des aktiven Modus oder `null` | Oberfläche (`Modi`) |
| `zustand` | `{ id, seit, ende, endeArt, ausloeser, vorher }` oder `null`; `vorher` ist der Zustand, der nach einer Sitzung zurückkommt | Oberfläche (`Zustaende`) |
| `raster` | ID des aktiven Rasters | `zenos-labwc` |
| `profil` | Name des aktiven Bildschirm-Profils | `zenos-labwc` (über kanshi) |

## Systemweit

- **`/etc/xdg/zenos/kanal`:** `dev` oder `main`. Der Installer legt die Datei beim ersten Mal an (aus dem Branch der
  Quelle, im Image `dev`) und ändert sie danach nicht mehr.
- **`/etc/xdg/zenos/argon.json`** (optional, wird im Betrieb neu gelesen):

  ```json
  { "kurve": [ { "temperatur": 55, "luefter": 30 }, { "temperatur": 60, "luefter": 55 }, { "temperatur": 65, "luefter": 100 } ],
    "hysterese": 3, "absenkenNachSekunden": 30 }
  ```

  Alle Schlüssel sind optional. `kurve`: 1–10 Stufen, `temperatur` 0–100 °C, `luefter` 0–100 %, mit steigender
  Temperatur nie fallend. `hysterese` 0–10 °C, `absenkenNachSekunden` 0–600. Ab 80 °C läuft der Lüfter immer mit
  100 % (Code). Prüfen: `/opt/zenos/scripts/bin/zenos-argon --konfig-pruefen`.

## Leitplanken

Sie sind im Code verankert, nicht in der Konfiguration:

- Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen.
- Der Sperrbildschirm zeigt nie Inhalte.
- Die automatische Sperre bleibt aktiv, nach 1 bis 15 Minuten ohne Eingabe.
