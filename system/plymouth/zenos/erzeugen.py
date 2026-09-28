#!/usr/bin/env python3
# erzeugen.py – erzeugt die Bilder und die Werte des Bootsplash-Themes (docs/module/bootsplash.md): die zwei Steine
# in Unterpixel-Lagen und Farbstufen, Passwortfeld, Punkte, Beschriftungen, dazu zenos.plymouth und den Werte-Block
# in zenos.script. Quellen: shell/theme/tokens.json (Farben, Schrift, Pfade der Bildmarke, Radius, Abstände, Bewegung),
# assets/zeichen/geometrie.json (Spalt), docs/bildmarke.md (Ablauf), Schrift aus assets/fonts/ (als Pfade, mit der
# Schrift-Klasse aus assets/zeichen/erzeugen.py). Rendert mit rsvg-convert (librsvg2-bin), braucht
# python3-fonttools. Geschrieben wird nur, was sich ändert; ein zweiter Lauf ändert nichts.
#   python3 system/plymouth/zenos/erzeugen.py
# Exit 0, wenn alles erzeugt ist, sonst 1.

import importlib.util
import json
import math
import shutil
import sys
from pathlib import Path

ORDNER = Path(__file__).resolve().parent
WURZEL = ORDNER.parents[2]
TOKENS = WURZEL / "shell" / "theme" / "tokens.json"
GEOMETRIE = WURZEL / "assets" / "zeichen" / "geometrie.json"
MARKE = WURZEL / "assets" / "zeichen" / "erzeugen.py"
SCHRIFTEN = WURZEL / "assets" / "fonts"
SKRIPT = ORDNER / "zenos.script"

# docs/bildmarke.md «Bootsplash»: Zeichen 64 px, Gleiten 300 ms, Überblenden in 200 ms (bewegung.maximal),
# Atmen ±1 Einheit mit 3,2 s pro Zug
ZEICHEN_PX = 64
GLEITEN = 0.3
ATEMZUG = 3.2
ATEM = 1

# Eigene Festlegungen (docs/module/bootsplash.md)
ZUGABE = 8  # Spalt zu Beginn um so viele Einheiten weiter
PHASEN = 8  # Unterpixel-Lagen je Stein (1/8 px), die Sprites selbst stehen auf ganzen Pixeln
STUFEN = 10  # Farbstufen, wenn der untere Stein zur Akzentfarbe überblendet
FAKTOREN = (1, 2)  # 2: Bildschirme ab 2880 × 1620, wenn Plymouth in Bildschirmpixeln zeichnet
LINIE = {"breite": 96, "hoehe": 2}
# Passwortfeld wie Eingabe.qml und die Sperre: 44 px hoch, Text 15 px mit 14 px Innenabstand, Beschriftung
# 10 px darüber
FELD = {"breite": 320, "hoehe": 44, "innen": 14, "schrift": 15, "beschriftung": 10}
TEXTE = {"beschriftung": "Passwort", "hinweis": "Feststelltaste ist aktiv"}
SCHRIFT = "Geist-Regular.ttf"

ANFANG = "# --- Anfang der erzeugten Werte (erzeugen.py) ---"
ENDE = "# --- Ende der erzeugten Werte ---"


def marke_laden():
    spec = importlib.util.spec_from_file_location("zeichen_erzeugen", MARKE)
    modul = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modul)
    return modul


def rgb(hexwert):
    h = hexwert.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexfarbe(werte):
    return "#" + "".join(f"{round(w):02X}" for w in werte)


def mischen(a, b, anteil):
    return hexfarbe(x + (y - x) * anteil for x, y in zip(rgb(a), rgb(b)))


def dezimal(wert):
    text = f"{wert:.5f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def aus_kubisch(x):
    return 1 - (1 - x) ** 3


class Bilder:
    def __init__(self, marke):
        self.marke = marke
        self.geschrieben, self.gleich = [], []

    def schreiben(self, name, daten):
        pfad = ORDNER / name
        if pfad.exists() and pfad.read_bytes() == daten:
            self.gleich.append(name)
            return
        pfad.parent.mkdir(parents=True, exist_ok=True)
        pfad.write_bytes(daten)
        self.geschrieben.append(name)

    def png(self, name, svg_text, breite, hoehe):
        self.schreiben(name, self.marke.rendern(svg_text, breite, hoehe))


def stein(marke, pfad, raster, farbe, faktor, phase):
    """Ein Stein auf der Fläche des Zeichens, um phase/PHASEN px nach rechts unten verschoben."""
    seite = ZEICHEN_PX * faktor
    v = f"{phase / PHASEN:.4f}".rstrip("0").rstrip(".")
    mass = f"{seite / raster:.6g}"
    inhalt = [f'<path fill="{farbe}" transform="translate({v} {v}) scale({mass})" d="{pfad}"/>']
    return marke.svg(seite, seite, inhalt), seite


def text_zeile(marke, schrift, text, groesse, farbe, breite=None):
    """Eine Textzeile: Höhe aus Ober- und Unterlänge der Schrift, Grundlinie auf der Oberlänge."""
    kopf = schrift.font["hhea"]
    oben = kopf.ascent / schrift.einheiten * groesse
    unten = -kopf.descent / schrift.einheiten * groesse
    lauf, ende = schrift.setzen(text, groesse, 0)
    if breite is None:
        breite = math.ceil(ende)
    hoehe = round(oben + unten)
    pfad = schrift.pfad(lauf, groesse, oben + (hoehe - oben - unten) / 2)
    return marke.svg(breite, hoehe, [f'<path fill="{farbe}" d="{pfad}"/>']), breite, hoehe


def feld(marke, faktor, farben, radius):
    b, h, s = FELD["breite"] * faktor, FELD["hoehe"] * faktor, faktor
    innen = s / 2
    rx = radius * faktor - innen
    inhalt = [f'<rect x="{marke.zahl(innen)}" y="{marke.zahl(innen)}" width="{marke.zahl(b - s)}" '
              f'height="{marke.zahl(h - s)}" rx="{marke.zahl(rx)}" fill="{farben["flaeche"]}" '
              f'stroke="{farben["akzent"]}" stroke-width="{s}"/>']
    return marke.svg(b, h, inhalt), b, h


def werte_block(farben, tokens, spalt, raster):
    bewegung = tokens["bewegung"]
    abstand = tokens["abstand"]

    def farbe(name, wert):
        r, g, b = (dezimal(x / 255) for x in rgb(wert))
        return f"{name}.r = {r}; {name}.g = {g}; {name}.b = {b};"

    zeilen = [
        ANFANG,
        "# Quellen: shell/theme/tokens.json, assets/zeichen/geometrie.json, docs/bildmarke.md. Nicht von Hand ändern.",
        farbe("farbe.grund", farben["grund"]),
        farbe("farbe.text", farben["text"]),
        farbe("farbe.gedaempft", farben["gedaempft"]),
        f'schrift.name = "{tokens["schrift"]["text"]}";',
        f"schrift.beschriftung = {tokens['schrift']['groessen']['label']};",
        f"schrift.feld = {FELD['schrift']};",
        f"ablauf.gleiten = {dezimal(GLEITEN)};",
        f"ablauf.blenden = {dezimal(bewegung['maximal'] / 1000)};",
        f"ablauf.kurz = {dezimal(bewegung['kurz'] / 1000)};",
        f"ablauf.atemzug = {dezimal(ATEMZUG)};",
        f"spalt.basis = {dezimal(spalt)};",
        f"spalt.zugabe = {dezimal(ZUGABE)};",
        f"spalt.atem = {dezimal(ATEM)};",
        f"phasen = {PHASEN};",
        f"stufen = {STUFEN};",
        f"mass.zeichen = {ZEICHEN_PX};",
        f"mass.einheit = {dezimal(ZEICHEN_PX / raster)};",
        f"mass.abstand = {abstand[6]};",
        f"mass.hinweis_abstand = {abstand[2]};",
        f"mass.linie_breite = {LINIE['breite']};",
        f"mass.linie_hoehe = {LINIE['hoehe']};",
        f"mass.feld_breite = {FELD['breite']};",
        f"mass.feld_hoehe = {FELD['hoehe']};",
        f"mass.feld_innen = {FELD['innen']};",
        f"mass.beschriftung_abstand = {FELD['beschriftung']};",
        ENDE,
    ]
    return "\n".join(zeilen)


def theme_datei(tokens):
    """zenos.plymouth; Font nimmt plymouth-populate-initrd mit ins initramfs (Fragen und Meldungen in Geist)."""
    ziel = "/usr/share/plymouth/themes/zenos"
    return "\n".join([
        "[Plymouth Theme]",
        "Name=zenOS",
        "Description=Bootsplash von zenOS: die Bildmarke Zwei Steine auf dunklem Grund",
        "ModuleName=script",
        "",
        "[script]",
        f"ImageDir={ziel}/bilder",
        f"ScriptFile={ziel}/zenos.script",
        f"Font={tokens['schrift']['text']} {FELD['schrift']}",
        "",
    ])


def skript_aktualisieren(block):
    text = SKRIPT.read_text(encoding="utf-8")
    anfang, ende = text.find(ANFANG), text.find(ENDE)
    if anfang < 0 or ende < anfang:
        raise ValueError(f"{SKRIPT.name}: Markierungen für die erzeugten Werte fehlen")
    neu = text[:anfang] + block + text[ende + len(ENDE):]
    if neu == text:
        return False
    SKRIPT.write_text(neu, encoding="utf-8")
    return True


def main():
    tokens = json.loads(TOKENS.read_text(encoding="utf-8"))
    geometrie = json.loads(GEOMETRIE.read_text(encoding="utf-8"))
    zeichen = tokens["zeichen"]["normal"]
    raster = zeichen["raster"]
    spalt = geometrie["normal"]["spalt"]
    f = tokens["farben"]
    dunkel = f["dunkel"]
    farben = {
        "grund": dunkel["grund"],
        "text": dunkel["text"],
        "gedaempft": dunkel["gedaempft"],
        "linie": dunkel["linie"],
        "flaeche": dunkel["flaeche"],
        "akzent": f["akzente"][f["standardAkzent"]]["dunkel"],
    }
    groessen = tokens["schrift"]["groessen"]

    fehlt = [name for name, test in (("rsvg-convert (librsvg2-bin)", shutil.which("rsvg-convert")),
                                     ("fontTools (python3-fonttools)", importlib.util.find_spec("fontTools")))
             if test is None]
    if fehlt:
        print(f"erzeugen.py: es fehlt {', '.join(fehlt)}", file=sys.stderr)
        return 1

    marke = marke_laden()
    schrift = marke.Schrift(SCHRIFTEN / SCHRIFT)
    bilder = Bilder(marke)

    for name in ("text", "gedaempft", "linie"):
        bilder.png(f"bilder/pixel-{name}.png",
                   marke.svg(1, 1, [f'<rect width="1" height="1" fill="{farben[name]}"/>']), 1, 1)

    for faktor in FAKTOREN:
        o = f"bilder/{faktor}x"
        for phase in range(PHASEN):
            for name, pfad, farbe in (("oben", zeichen["oben"], farben["text"]),
                                      ("unten-text", zeichen["unten"], farben["text"]),
                                      ("unten-akzent", zeichen["unten"], farben["akzent"])):
                svg_text, seite = stein(marke, pfad, raster, farbe, faktor, phase)
                bilder.png(f"{o}/{name}-{phase}.png", svg_text, seite, seite)
        for stufe in range(1, STUFEN):
            farbe = mischen(farben["text"], farben["akzent"], stufe / STUFEN)
            svg_text, seite = stein(marke, zeichen["unten"], raster, farbe, faktor, 0)
            bilder.png(f"{o}/unten-blende-{stufe}.png", svg_text, seite, seite)

        svg_text, b, h = feld(marke, faktor, farben, tokens["radius"]["feld"])
        bilder.png(f"{o}/feld.png", svg_text, b, h)
        # Punkt wie passwordCharacter «•» in Eingabe.qml; die Breite ist der Schritt von Punkt zu Punkt
        _, ende = schrift.setzen("•", FELD["schrift"] * faktor, 0)
        svg_text, b, h = text_zeile(marke, schrift, "•", FELD["schrift"] * faktor, farben["text"],
                                    breite=max(1, round(ende)))
        bilder.png(f"{o}/punkt.png", svg_text, b, h)
        for name, groesse in (("beschriftung", groessen["label"]), ("hinweis", groessen["klein"])):
            svg_text, b, h = text_zeile(marke, schrift, TEXTE[name], groesse * faktor, farben["gedaempft"])
            bilder.png(f"{o}/{name}.png", svg_text, b, h)

    bilder.schreiben("zenos.plymouth", theme_datei(tokens).encode("utf-8"))
    if skript_aktualisieren(werte_block(farben, tokens, spalt, raster)):
        bilder.geschrieben.append(SKRIPT.name)
    else:
        bilder.gleich.append(SKRIPT.name)

    # Bilder, die nicht mehr erzeugt werden (weniger Lagen, Stufen oder Faktoren), gehören nicht mehr zum Theme
    erzeugt = set(bilder.geschrieben) | set(bilder.gleich)
    entfernt = sorted(str(p.relative_to(ORDNER)) for p in (ORDNER / "bilder").rglob("*.png")
                      if str(p.relative_to(ORDNER)) not in erzeugt)
    for name in entfernt:
        (ORDNER / name).unlink()

    print(f"system/plymouth/zenos: {len(bilder.geschrieben)} geschrieben, {len(bilder.gleich)} unverändert, "
          f"{len(entfernt)} entfernt")
    for name in bilder.geschrieben:
        print(f"  {name}")
    for name in entfernt:
        print(f"  entfernt: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
