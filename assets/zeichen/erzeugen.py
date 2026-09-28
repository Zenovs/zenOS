#!/usr/bin/env python3
# erzeugen.py – erzeugt die Bildmarke «Zwei Steine» (docs/bildmarke.md) in assets/zeichen/: geometrie.json, alle
# SVG-Dateien, die PNG-Grössen und favicon.ico. Die Geometrie wird aus der Konstruktion gerechnet, die Farben
# kommen aus shell/theme/tokens.json, die Schrift aus assets/fonts/ (in Pfade umgewandelt mit fontTools).
# PNG und ICO rendert rsvg-convert (librsvg2-bin). Geschrieben wird nur, was sich ändert; ein zweiter Lauf ändert
# nichts. Prüft zudem, dass tokens.json unter «zeichen» dieselben Pfade enthält.
#   python3 assets/zeichen/erzeugen.py
# Exit 0, wenn alles erzeugt ist und tokens.json passt, sonst 1.

import json
import math
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ORDNER = Path(__file__).resolve().parent
WURZEL = ORDNER.parent.parent
TOKENS = WURZEL / "shell" / "theme" / "tokens.json"
SCHRIFTEN = WURZEL / "assets" / "fonts"

# Konstruktion (docs/bildmarke.md): Kiesel mit Rand ringsum, Schnitt x + y = raster, Spalt senkrecht gemessen
NORMAL = {"raster": 64, "rand": 5, "radius": 19, "spalt": 6}
PIXEL = {"raster": 16, "rand": 1, "radius": 4.9, "spalt": 2}
PIXEL_UNTER = 24

# Schriftzug, in Schriftgrössen: Laufweite, Zeichen, Abstand zwischen Zeichen und Text
LAUFWEITE = -0.03
ZEICHEN_GROESSE = 1.04
ZEICHEN_ABSTAND = 0.26
SCHUTZZONE = 0.25

# App-Icon (Zenos Referenzbild): Kachel 512 in grund (dunkel) mit Eckradius 118, Zeichen 320 mittig.
# Der Avatar ist dieselbe Kachel ohne Rundung (GitHub schneidet selbst zu).
ICON = {"kachel": 512, "radius": 118, "zeichen": 320}
ICON_GROESSEN = (48, 64, 128, 256, 512)
AVATAR_GROESSE = 500
FAVICON_GROESSEN = (16, 32, 48)

# Vorschaubild für GitHub (1280 × 640) in px, gemessen an Zenos Referenzbild: linke Kante, Oberkante des
# Zeichens, Grundlinien und Schriftgrössen
VORSCHAU = {
    "breite": 1280,
    "hoehe": 640,
    "links": 120,
    "schriftzug": {"groesse": 130, "oben": 200},
    "unterzeile": {
        "text": "Ein ruhiges, persönliches Desktop-System für den Raspberry Pi 5.",
        "schrift": "Geist-Regular.ttf",
        "groesse": 32,
        "grundlinie": 420,
    },
    "monozeile": {
        "text": "basiert auf Ubuntu · gebaut mit Claude",
        "schrift": "GeistMono-Regular.ttf",
        "groesse": 22,
        "grundlinie": 470,
        "deckkraft": 0.84,
    },
}

SCHRIFT_ZUG = "Geist-Medium.ttf"


def zahl(wert):
    """Zahl für SVG: höchstens 2 Nachkommastellen, ohne Nullen am Ende."""
    text = f"{round(wert, 2):.2f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


# --- Geometrie ---------------------------------------------------------------


def steine(raster, rand, radius, spalt):
    """Pfade (oben, unten) der zwei Steine im Raster raster × raster."""
    nah = rand + radius  # Mittelpunkte der Eckbögen: nah oder fern
    fern = raster - rand - radius
    kante = raster - rand

    def schnittpunkt(versatz):
        # Bogen oben rechts (Mittelpunkt fern, nah) mit der Geraden x + y = raster + versatz. x kommt aus dem
        # Schnitt, y vom Kreis, damit der gerundete Punkt auf dem Bogen liegt. Unten links gilt derselbe Punkt
        # gespiegelt (die Marke ist symmetrisch zur Diagonalen y = x).
        w = math.sqrt(2 * radius * radius - versatz * versatz)
        x = round(fern + (versatz + w) / 2, 2)
        y = round(nah - math.sqrt(radius * radius - (x - fern) ** 2), 2)
        if not (fern <= x <= kante and rand <= y <= nah):
            raise ValueError(f"Schnitt trifft den Bogen nicht (raster {raster})")
        return x, y

    versatz = spalt / 2 * math.sqrt(2)
    r = zahl(radius)

    def bogen(richtung, x, y):
        return f"A{r} {r} 0 0 {richtung} {zahl(x)} {zahl(y)}"

    ox, oy = schnittpunkt(-versatz)
    ux, uy = schnittpunkt(versatz)
    oben = (f"M{zahl(ox)} {zahl(oy)}" + bogen(0, fern, rand) + f"H{zahl(nah)}" + bogen(0, rand, nah)
            + f"V{zahl(fern)}" + bogen(0, oy, ox) + "Z")
    unten = (f"M{zahl(ux)} {zahl(uy)}" + bogen(1, kante, nah) + f"V{zahl(fern)}" + bogen(1, fern, kante)
             + f"H{zahl(nah)}" + bogen(1, uy, ux) + "Z")
    return oben, unten


def variante(masse):
    oben, unten = steine(**masse)
    return {"raster": masse["raster"], "oben": oben, "unten": unten}


# --- Farben ------------------------------------------------------------------


def farben_laden():
    tokens = json.loads(TOKENS.read_text(encoding="utf-8"))
    f = tokens["farben"]
    akzent = f["akzente"][f["standardAkzent"]]
    satz = {}
    for modus in ("hell", "dunkel"):
        satz[modus] = {
            "grund": f[modus]["grund"],
            "text": f[modus]["text"],
            "gedaempft": f[modus]["gedaempft"],
            "akzent": akzent[modus],
        }
    return tokens, satz


# --- Schrift -----------------------------------------------------------------


class Schrift:
    """TrueType-Schrift: Umrisse als SVG-Pfad, Vorschub mit Unterschneidung (GPOS kern, Paare)."""

    def __init__(self, datei):
        from fontTools.ttLib import TTFont

        self.font = TTFont(str(datei))
        self.einheiten = self.font["head"].unitsPerEm
        self.versal = self.font["OS/2"].sCapHeight
        self.glyphen = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.breiten = self.font["hmtx"].metrics
        self.paare = self._paar_tabellen()

    def _paar_tabellen(self):
        if "GPOS" not in self.font:
            return []
        gpos = self.font["GPOS"].table
        nummern = set()
        for eintrag in gpos.FeatureList.FeatureRecord:
            if eintrag.FeatureTag == "kern":
                nummern.update(eintrag.Feature.LookupListIndex)
        tabellen = []
        for nummer in sorted(nummern):
            lookup = gpos.LookupList.Lookup[nummer]
            teile = []
            for teil in lookup.SubTable:
                if lookup.LookupType == 9:
                    if teil.ExtensionLookupType != 2:
                        continue
                    teil = teil.ExtSubTable
                elif lookup.LookupType != 2:
                    continue
                teile.append(teil)
            tabellen.append(teile)
        return tabellen

    @staticmethod
    def _vorschub(wert):
        if wert is None:
            return 0
        return getattr(wert, "XAdvance", 0) or 0

    def unterschneidung(self, links, rechts):
        summe = 0
        for teile in self.paare:
            for teil in teile:
                if links not in teil.Coverage.glyphs:
                    continue
                if teil.Format == 1:
                    paarsatz = teil.PairSet[teil.Coverage.glyphs.index(links)]
                    treffer = [p for p in paarsatz.PairValueRecord if p.SecondGlyph == rechts]
                    if not treffer:
                        continue
                    summe += self._vorschub(treffer[0].Value1)
                    break
                klasse1 = teil.ClassDef1.classDefs.get(links, 0)
                klasse2 = teil.ClassDef2.classDefs.get(rechts, 0)
                summe += self._vorschub(teil.Class1Record[klasse1].Class2Record[klasse2].Value1)
                break
        return summe

    def glyphe(self, zeichen):
        name = self.cmap.get(ord(zeichen))
        if name is None:
            raise ValueError(f"Zeichen {zeichen!r} fehlt in der Schrift")
        return name

    def setzen(self, text, groesse, x, laufweite=0.0):
        """Liste (zeichen, x, glyphe) ab x und das Ende hinter dem letzten Zeichen (ohne Laufweite)."""
        mass = groesse / self.einheiten
        namen = [self.glyphe(z) for z in text]
        lauf = []
        for i, (z, name) in enumerate(zip(text, namen)):
            lauf.append((z, x, name))
            x += self.breiten[name][0] * mass
            if i + 1 < len(namen):
                x += self.unterschneidung(name, namen[i + 1]) * mass + laufweite * groesse
        return lauf, x

    def pfad(self, lauf, groesse, grundlinie):
        from fontTools.pens.svgPathPen import SVGPathPen
        from fontTools.pens.transformPen import TransformPen

        mass = groesse / self.einheiten
        stift = SVGPathPen(self.glyphen, ntos=zahl)
        for _, x, name in lauf:
            self.glyphen[name].draw(TransformPen(stift, (mass, 0, 0, -mass, x, grundlinie)))
        return stift.getCommands()

    def tinte(self, lauf, groesse):
        """Waagrechte Ausdehnung der Umrisse (links, rechts)."""
        from fontTools.pens.boundsPen import BoundsPen

        mass = groesse / self.einheiten
        links, rechts = math.inf, -math.inf
        for _, x, name in lauf:
            stift = BoundsPen(self.glyphen)
            self.glyphen[name].draw(stift)
            if stift.bounds:
                links = min(links, x + stift.bounds[0] * mass)
                rechts = max(rechts, x + stift.bounds[2] * mass)
        return links, rechts


# --- SVG ---------------------------------------------------------------------


def svg(breite, hoehe, inhalt, extra=""):
    b, h = zahl(breite), zahl(hoehe)
    zeilen = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{b}" height="{h}" viewBox="0 0 {b} {h}"{extra}>']
    zeilen += ["  " + z for z in inhalt]
    zeilen.append("</svg>")
    return "\n".join(zeilen) + "\n"


def zeichen_gruppe(v, oben, unten, x=0, y=0, groesse=None, fokus_id=False):
    """Die zwei Steine als SVG-Elemente, optional verschoben und auf groesse skaliert."""
    fokus = ' id="fokus"' if fokus_id else ""
    oben_attr = f' fill="{oben}"' if oben else ""
    unten_attr = f' fill="{unten}"' if unten else ""
    pfade = [f'<path{oben_attr} d="{v["oben"]}"/>', f'<path{fokus}{unten_attr} d="{v["unten"]}"/>']
    if groesse is None:
        return pfade
    mass = f"scale({groesse / v['raster']:.10g})"
    verschiebung = f"translate({zahl(x)} {zahl(y)}) " if x or y else ""
    return [f'<g transform="{verschiebung}{mass}">'] + ["  " + p for p in pfade] + ["</g>"]


def schriftzug_teile(schrift, farben, groesse, x, oben):
    """Zeichen und «zenOS»; (x, oben) ist die Ecke oben links des Zeichens. Rückgabe: Elemente, Tinte rechts."""
    zeichen = ZEICHEN_GROESSE * groesse
    grundlinie = oben + zeichen / 2 + schrift.versal / schrift.einheiten * groesse / 2
    teile = zeichen_gruppe(GEOMETRIE["normal"], farben["text"], farben["akzent"], x, oben, zeichen)
    lauf, _ = schrift.setzen("zenOS", groesse, x + zeichen + ZEICHEN_ABSTAND * groesse, LAUFWEITE)
    teile.append(f'<path fill="{farben["text"]}" d="{schrift.pfad(lauf[:3], groesse, grundlinie)}"/>')
    teile.append(f'<path fill="{farben["gedaempft"]}" d="{schrift.pfad(lauf[3:], groesse, grundlinie)}"/>')
    return teile, schrift.tinte(lauf, groesse)[1]


def schriftzug_svg(schrift, farben):
    # Schriftgrösse 100, das Zeichen (104) bestimmt die Höhe. Rechts bleibt so viel frei wie links zwischen Rand
    # und Kiesel.
    groesse = 100
    zeichen = ZEICHEN_GROESSE * groesse
    teile, rechts = schriftzug_teile(schrift, farben, groesse, 0, 0)
    breite = math.ceil((rechts + NORMAL["rand"] / NORMAL["raster"] * zeichen) * 100) / 100
    return svg(breite, zeichen, teile, extra=' role="img" aria-label="zenOS"')


def kachel_svg(groesse, gerundet, farben):
    mass = groesse / ICON["kachel"]
    zeichen = ICON["zeichen"] * mass
    rand = (groesse - zeichen) / 2
    radius = f' rx="{zahl(ICON["radius"] * mass)}"' if gerundet else ""
    inhalt = [f'<rect width="{groesse}" height="{groesse}"{radius} fill="{farben["grund"]}"/>']
    inhalt += zeichen_gruppe(GEOMETRIE["normal"], farben["text"], farben["akzent"], rand, rand, zeichen)
    return svg(groesse, groesse, inhalt)


def favicon_svg(farben):
    v = GEOMETRIE["pixel"]
    h, d = farben["hell"], farben["dunkel"]
    stil = (f"<style>.oben{{fill:{h['text']}}}.unten{{fill:{h['akzent']}}}@media (prefers-color-scheme: dark)"
            f"{{.oben{{fill:{d['text']}}}.unten{{fill:{d['akzent']}}}}}</style>")
    inhalt = [stil, f'<path class="oben" d="{v["oben"]}"/>', f'<path class="unten" d="{v["unten"]}"/>']
    return svg(v["raster"], v["raster"], inhalt)


def vorschau_svg(farben):
    v = VORSCHAU
    d = farben["dunkel"]
    inhalt = [f'<rect width="{v["breite"]}" height="{v["hoehe"]}" fill="{d["grund"]}"/>']
    zug = v["schriftzug"]
    teile, _ = schriftzug_teile(Schrift(SCHRIFTEN / SCHRIFT_ZUG), d, zug["groesse"], v["links"], zug["oben"])
    inhalt += teile
    for name in ("unterzeile", "monozeile"):
        zeile = v[name]
        schrift = Schrift(SCHRIFTEN / zeile["schrift"])
        lauf, _ = schrift.setzen(zeile["text"], zeile["groesse"], v["links"])
        pfad = schrift.pfad(lauf, zeile["groesse"], zeile["grundlinie"])
        deckkraft = f' fill-opacity="{zeile["deckkraft"]}"' if "deckkraft" in zeile else ""
        inhalt.append(f'<path fill="{d["gedaempft"]}"{deckkraft} d="{pfad}"/>')
    return svg(v["breite"], v["hoehe"], inhalt)


# --- Raster und ICO ----------------------------------------------------------


def rendern(svg_text, breite, hoehe):
    ergebnis = subprocess.run(["rsvg-convert", "--width", str(breite), "--height", str(hoehe), "--format", "png"],
                              input=svg_text.encode("utf-8"), capture_output=True, check=False)
    if ergebnis.returncode != 0:
        raise RuntimeError(f"rsvg-convert: {ergebnis.stderr.decode(errors='replace').strip()}")
    return ergebnis.stdout


def ico(bilder):
    """ICO mit PNG-Einträgen: bilder = [(groesse, png_bytes)]."""
    kopf = struct.pack("<HHH", 0, 1, len(bilder))
    eintraege, daten = b"", b""
    versatz = 6 + 16 * len(bilder)
    for groesse, png in bilder:
        seite = 0 if groesse >= 256 else groesse
        eintraege += struct.pack("<BBBBHHII", seite, seite, 0, 0, 1, 32, len(png), versatz + len(daten))
        daten += png
    return kopf + eintraege + daten


# --- Ablauf ------------------------------------------------------------------

GEOMETRIE = {"normal": variante(NORMAL), "pixel": variante(PIXEL)}

geschrieben, gleich = [], []


def schreiben(name, inhalt):
    pfad = ORDNER / name
    daten = inhalt.encode("utf-8") if isinstance(inhalt, str) else inhalt
    if pfad.exists() and pfad.read_bytes() == daten:
        gleich.append(name)
        return
    pfad.parent.mkdir(parents=True, exist_ok=True)
    pfad.write_bytes(daten)
    geschrieben.append(name)


def geometrie_json():
    konstruktion = {}
    for name, masse in (("normal", NORMAL), ("pixel", PIXEL)):
        seite = masse["raster"] - 2 * masse["rand"]
        konstruktion[name] = {
            "raster": masse["raster"],
            "kiesel": {"x": masse["rand"], "y": masse["rand"], "seite": seite, "radius": masse["radius"]},
            "schnitt": f"x + y = {masse['raster']}",
            "spalt": masse["spalt"],
            "oben": GEOMETRIE[name]["oben"],
            "unten": GEOMETRIE[name]["unten"],
        }
    daten = {
        "quelle": "docs/bildmarke.md, erzeugt von assets/zeichen/erzeugen.py",
        **konstruktion,
        "pixelUnter": PIXEL_UNTER,
        "schriftzug": {"laufweite": LAUFWEITE, "zeichen": ZEICHEN_GROESSE, "abstand": ZEICHEN_ABSTAND,
                       "ausrichtung": "Mitte der Versalhöhe"},
        "schutzzone": SCHUTZZONE,
        "appIcon": ICON,
    }
    return json.dumps(daten, ensure_ascii=False, indent=2) + "\n"


def tokens_erwartet():
    return {
        "pixelUnter": PIXEL_UNTER,
        "normal": GEOMETRIE["normal"],
        "pixel": GEOMETRIE["pixel"],
    }


def main():
    ok = True
    tokens, farben = farben_laden()
    h, d = farben["hell"], farben["dunkel"]
    normal, pixel = GEOMETRIE["normal"], GEOMETRIE["pixel"]

    schreiben("geometrie.json", geometrie_json())
    schreiben("zenos-zeichen.svg", svg(64, 64, zeichen_gruppe(normal, None, None, fokus_id=True),
                                       extra=' fill="currentColor"'))
    schreiben("zenos-zeichen-16.svg", svg(16, 16, zeichen_gruppe(pixel, None, None, fokus_id=True),
                                          extra=' fill="currentColor"'))
    schreiben("zenos-zeichen-hell.svg", svg(64, 64, zeichen_gruppe(normal, h["text"], h["text"])))
    schreiben("zenos-zeichen-hell-farbig.svg", svg(64, 64, zeichen_gruppe(normal, h["text"], h["akzent"])))
    schreiben("zenos-zeichen-dunkel.svg", svg(64, 64, zeichen_gruppe(normal, d["text"], d["akzent"])))

    icon = kachel_svg(ICON["kachel"], True, d)
    avatar = kachel_svg(AVATAR_GROESSE, False, d)
    schreiben("zenos-app-icon.svg", icon)
    schreiben("github-avatar.svg", avatar)
    schreiben("favicon.svg", favicon_svg(farben))

    vorschau = None
    try:
        import fontTools  # noqa: F401
    except ImportError:
        print("erzeugen.py: fontTools fehlt (apt install python3-fonttools), Schriftzug und Vorschaubild "
              "nicht erzeugt", file=sys.stderr)
        ok = False
    else:
        schrift = Schrift(SCHRIFTEN / SCHRIFT_ZUG)
        schreiben("zenos-schriftzug-hell.svg", schriftzug_svg(schrift, h))
        schreiben("zenos-schriftzug-dunkel.svg", schriftzug_svg(schrift, d))
        vorschau = vorschau_svg(farben)
        schreiben("github-social-preview.svg", vorschau)

    if shutil.which("rsvg-convert") is None:
        print("erzeugen.py: rsvg-convert fehlt (apt install librsvg2-bin), PNG und favicon.ico nicht erzeugt",
              file=sys.stderr)
        ok = False
    else:
        for groesse in ICON_GROESSEN:
            schreiben(f"png/zenos-app-icon-{groesse}.png", rendern(icon, groesse, groesse))
        schreiben(f"png/github-avatar-{AVATAR_GROESSE}.png", rendern(avatar, AVATAR_GROESSE, AVATAR_GROESSE))
        if vorschau:
            b, hh = VORSCHAU["breite"], VORSCHAU["hoehe"]
            schreiben(f"png/github-social-preview-{b}x{hh}.png", rendern(vorschau, b, hh))
        # favicon.ico ohne Umschaltung: Farben für hellen Grund, 16 px mit der Pixel-Variante
        bilder = []
        for groesse in FAVICON_GROESSEN:
            v = pixel if groesse < PIXEL_UNTER else normal
            bild = svg(v["raster"], v["raster"], zeichen_gruppe(v, h["text"], h["akzent"]))
            bilder.append((groesse, rendern(bild, groesse, groesse)))
        schreiben("favicon.ico", ico(bilder))

    if tokens.get("zeichen") != tokens_erwartet():
        print("erzeugen.py: shell/theme/tokens.json → «zeichen» weicht von der Geometrie ab. Erwartet:",
              file=sys.stderr)
        print(json.dumps(tokens_erwartet(), ensure_ascii=False, indent=2), file=sys.stderr)
        ok = False

    print(f"assets/zeichen: {len(geschrieben)} geschrieben, {len(gleich)} unverändert")
    for name in geschrieben:
        print(f"  {name}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
