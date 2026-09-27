# Konfiguration: Modi, Zustände, Raster, Bildschirme

Alles Persönliche liegt lokal unter `~/.config/zenos/` und nie im Repo. Neutrale Beispiele stehen in `config/beispiele/`. Bearbeitet wird über die Einstellungen in zenOS; die Dateien sind trotzdem lesbar und von Hand änderbar.

## Grundidee

- **Modus:** der Kontext, zum Beispiel Arbeit oder privat. Ab Werk gibt es keinen. Du legst sie selbst an.
- **Zustand:** wie sich zenOS gerade verhält, zum Beispiel Fokus oder Sitzung. Ein Zustand wird einmal definiert und kann pro Modus angepasst werden. Ab Werk liegen «Fokus» und «Sitzung» als neutrale Vorlagen bereit.
- **Raster:** Bereiche in Prozent, in die Fenster einrasten.
- **Bildschirm-Profil:** welches Raster auf welchem Bildschirm gilt, je nachdem, was angeschlossen ist.

## Wie ein Zustand zustande kommt

```
wirksamer Zustand = Zustand (Vorlage)
                  + Anpassungen des aktiven Modus für diesen Zustand
                  + Leitplanken (immer zuletzt, nicht überschreibbar)
```

## Modus: `modi/<name>.json`

| Schlüssel | Typ | Bedeutung |
|---|---|---|
| `name` | Text | Anzeigename |
| `akzent` | Text | Akzentfarbe aus `tokens.json`, zum Beispiel `salbei` |
| `chromeProfil` | Text | Name des Chrome-Profils |
| `mailKonten` | Liste | Konten, die coremail in diesem Modus zeigt |
| `heute` | Objekt | `kalender`, `aufgaben`, `wetter`: was die «Heute»-Ansicht zeigt |
| `oeffnen` | Liste | Apps, die beim Wechsel öffnen |
| `raster` | Objekt | Bildschirm-Profil → Raster |
| `zustaende` | Liste | Zustände, die dieser Modus anbietet |
| `anpassungen` | Objekt | Zustand → Werte, die für diesen Modus abweichen |

## Zustand: `zustaende/<name>.json`

| Schlüssel | Werte |
|---|---|
| `name` | Text |
| `mitteilungen` | `alle` · `gebuendelt-<minuten>` · `nur-dringend` · `keine` |
| `leiste` | `normal` · `reduziert` · `aus` |
| `fenster` | `normal` · `fokus` (alles ausser dem aktiven Fenster tritt zurück) |
| `heute` | `true` · `false` |
| `widgets` | `true` · `false` |
| `ausloeser` | Liste aus `manuell` · `bildschirmfreigabe` · `kalender` · `uhrzeit:HH:MM` · `moduswechsel` |
| `ende` | `{ "art": "manuell" }` · `{ "art": "timer", "minuten": 50 }` · `{ "art": "ausloeser-endet" }` |

## Raster: `raster/<name>.json`

Bereiche in Prozent der nutzbaren Bildschirmfläche. `abstand` in Pixeln.

| Schlüssel | Bedeutung |
|---|---|
| `name` | Anzeigename |
| `abstand` | Lücke zwischen Fenstern in px |
| `bereiche` | Liste aus `{ "id", "x", "y", "b", "h" }` in Prozent |

## Bildschirme: `bildschirme.json`

| Schlüssel | Bedeutung |
|---|---|
| `profile` | Liste von Profilen |
| `profile[].name` | Anzeigename |
| `profile[].ausgaenge` | Bildschirm-Ausgänge, an denen das Profil erkannt wird |
| `profile[].raster` | Ausgang → Raster |

## Leitplanken

Sie sind im Code verankert, nicht in der Konfiguration:

- Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen.
- Der Sperrbildschirm zeigt nie Inhalte.
- Die automatische Sperre bleibt aktiv.
