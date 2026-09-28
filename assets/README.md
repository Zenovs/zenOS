# assets

- `zeichen/`: die Bildmarke «Zwei Steine» als SVG, PNG und ICO, dazu `geometrie.json` mit den fertigen Pfaden.
  Konstruktion, Farben und Einsatz stehen in [`docs/bildmarke.md`](../docs/bildmarke.md). Die Oberfläche zeichnet
  das Zeichen selbst, mit den Pfaden aus `shell/theme/tokens.json` (`zeichen`).
- `fonts/`: Geist, Geist Mono und Instrument Serif als TTF mit OFL-Lizenztexten. Quellen, Stände und Prüfsummen in
  `fonts/QUELLEN.md`. `scripts/module/30-schriften.sh` installiert sie nach `/usr/local/share/fonts/zenos/`.

## Bildmarke neu erzeugen

```
python3 assets/zeichen/erzeugen.py
```

Braucht `python3-fonttools` (Schrift in Pfade) und `rsvg-convert` aus `librsvg2-bin` (PNG und ICO). Fehlt eines
davon, entstehen die übrigen Dateien trotzdem, das Skript nennt das fehlende Paket und endet mit Exit 1. Auf dem Mac
läuft es im Testcontainer (`test/container/`).

- **Geometrie:** Die Pfade werden aus der Konstruktion gerechnet. Die Schnittpunkte von Bogen und Schnitt sind auf
  2 Nachkommastellen gerundet: x aus dem Schnitt, y auf dem Kreis, unten links gespiegelt.
- **Farben:** nur aus `shell/theme/tokens.json`; ohne Modus gilt `standardAkzent`.
- **Schrift:** aus `fonts/`, mit Unterschneidung (GPOS `kern`), als Pfade.
- **Stabil:** Geschrieben wird nur, was sich ändert. Ein zweiter Lauf ändert keine Datei.
- **Abgleich:** Das Skript prüft, dass `tokens.json` unter `zeichen` dieselben Pfade enthält, und gibt sonst den
  erwarteten Block aus.

Masse, die `docs/bildmarke.md` nicht nennt, stammen aus Zenos Referenzbildern:

| Datei | Masse |
|---|---|
| App-Icon | Kachel 512 in `grund` (dunkel), Eckradius 118, Zeichen 320 mittig; oberer Stein `text`, unterer `salbei` (dunkel) |
| Avatar | wie das App-Icon, aber ohne Rundung (GitHub schneidet selbst zu), 500 px |
| Vorschaubild | 1280 × 640 auf `grund` (dunkel), alles ab x = 120: Schriftzug mit Schrift 130 px, Zeichen oben bei y = 200; Unterzeile Geist Regular 32 px in `gedaempft`, Grundlinie 420; Mono-Zeile Geist Mono Regular 22 px in `gedaempft` mit Deckkraft 0,84, Grundlinie 470 |
| Schriftzug | Schrift 100, Zeichen 104 hoch; rechts so viel Luft wie links zwischen Rand und Kiesel |
| Favicon | SVG mit der Pixel-Variante, hell und dunkel per `prefers-color-scheme`; ICO mit 16 (Pixel-Variante), 32 und 48 px in den hellen Farben |
