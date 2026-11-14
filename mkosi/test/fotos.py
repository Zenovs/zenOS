#!/usr/bin/env python3
# Bildschirmfotos von zenOS 1.0 für die Website (zenos-linux.com), aus dem Test-Image in QEMU.
#
#   mkosi/test/fotos.sh          (startet dieses Skript in der Bauumgebung; vorher: mkosi/bauen.sh qemu)
#
# Nimmt die Hilfsfunktionen von erster-start.py (Start, Konsole, Tasten, Bildschirmfoto) und läuft den ersten Start
# durch, mit einem neutralen Konto «demo» und ohne Notfall-Passwort. labwc zeichnet den Mauszeiger immer, auch ohne
# Zeigegerät; deshalb bekommt QEMU eine relative Maus, und der Zeiger wandert in die Ecke unten links, wo er aus dem
# Bild fällt. Jedes Motiv kommt hell und dunkel.
#
# QEMU emuliert die CPU (TCG), alles läuft zäh. Kommt der Gast mit den Tasten nicht nach, gehen Tastendrücke verloren
# (auch das Loslassen: dann wiederholt der Client die Taste, aus «1440» wurde «144000», oder Super bleibt gedrückt).
# Deshalb tippt das Skript langsam, setzt in der Sitzung der VM die Tastenwiederholung auf 5 s, legt die Terminals
# über Fensterregeln von labwc in die Bereiche des Rasters (wie Super+1 bis 4) oder maximiert sie (wie Super+Enter)
# und stellt die Zeigerbeschleunigung flach, damit der Zeiger genau dort landet, wo er soll. Es wartet, bis die Shell
# im neuen Terminal läuft, und vor jedem Bild, bis der Bildschirm ruhig ist (Vergleiche ohne Änderung ausser einem
# blinkenden Cursor). Vorher bewegt es den Zeiger ein paar Mal um ein Pixel: Ohne Bewegung auf dem Bildschirm bekam
# kitty manchmal keinen Takt von labwc (frame callback) und zeigte nicht, was fish schon ausgegeben hatte; die
# Warnkarte fehlte, obwohl fish auf die Antwort wartete (warnung_pruefen sieht nach, dass curl nicht läuft). Der
# Zeiger steht in der Ecke unten links und fällt dort aus dem Bild.
#
# Gezeichnet wird in der VM mit llvmpipe (Software). labwc liest den Puffer einer Fläche manchmal, während die Fläche
# schon das nächste Bild beginnt; dann fehlt im Bildschirm oben links an dieser Fläche ein Stück, jedes Mal anders
# gross (auf der Sperre schwarz, beim Befehlsfeld eine nicht abgedunkelte Leiste, in der Zentrale ein Stück
# Hintergrund). Am echten Gerät zeichnet die GPU; das gibt es dort nicht. Gegenmittel:
#   Login, Sperre, Ausschalten: Der Cursor im Passwortfeld blinkt, es entstehen laufend neue Bilder. Das Skript nimmt
#     alle 0,5 s eines auf, bis eines ohne schwarzes Pixel dabei ist (reines Schwarz kommt im Design nicht vor; die
#     Ecke mit dem Mauszeiger zählt nicht), und behält es.
#   Zentrale, Befehlsfeld: zusätzlich <name>.thema.png nach einem Wechsel des Themas hin und zurück (jede Fläche
#     zeichnet neu) und, wo es ein Eingabefeld gibt, <name>.getippt.png nach einem Zeichen und dessen Löschen.
# Sonst gibt es von jedem Motiv <name>.png und sechs Sekunden später <name>.nachher.png; ausgewählt wird von Hand.
# Die Bilder (1280 × 800, PNG) landen unter $ZENOS_TEST_BILDER, auf dem Mac mkosi/ausgabe/fotos/.
#
# Nur einige Motive: ZENOS_FOTO_MOTIVE="sperre-hell raster terminal" (Motiv mit oder ohne Thema; leer heisst alle).
# Motive: login heute zentrale sperre befehlsfeld-apps befehlsfeld-rechnen systemmenue raster terminal sammelkarte
# ausschalten.
#
# Es zeigt nur Neutrales: das Konto «demo», zwei Mitteilungen (die echte Erinnerung an Updates und eine Mitteilung
# aus dem Browser), Terminals mit «zen status» und der Warnung vor «curl … | sh». Keine Passwörter im Bild.
import importlib.util
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

import pexpect

HIER = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("erster_start", HIER / "erster-start.py")
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)

KONTO = "demo"
t.KONTO = KONTO  # anmelden() in erster-start.py liest das Konto aus dem Modul
# Zeichen, die in den Terminals getippt werden (US-Belegung wie im Test)
t.TASTEN.update({"/": "slash", "|": "shift-backslash", ":": "shift-semicolon", "?": "shift-slash"})


def starte_fuer_fotos(arbeit: Path) -> pexpect.spawn:
    """Wie starte() im Test, aber mit relativer Maus statt Tablett: Nur so lässt sich der Zeiger aus dem Bild schieben."""
    befehl = [
        "qemu-system-aarch64", "-M", "virt", "-cpu", "max", "-smp", "4", "-m", "3072", "-nographic",
        "-drive", f"if=pflash,format=raw,readonly=on,file={t.FIRMWARE}",
        "-drive", f"if=pflash,format=raw,file={arbeit / 'variablen.fd'}",
        "-drive", f"file={arbeit / 'platte.qcow2'},if=virtio,format=qcow2",
        "-device", "virtio-rng-pci",
        "-device", "virtio-gpu-pci,xres=1280,yres=800", "-device", "virtio-keyboard-pci", "-device", "virtio-mouse-pci",
        "-netdev", "user,id=netz", "-device", "virtio-net-pci,netdev=netz,romfile=",
        "-serial", "mon:stdio",
    ]
    return pexpect.spawn(befehl[0], befehl[1:], encoding="utf-8", codec_errors="replace", timeout=900,
                         logfile=sys.stdout, dimensions=(50, 200))


def zeiger_weg(vm: pexpect.spawn) -> None:
    """Mauszeiger in die Ecke unten links: Die Spitze steht auf dem letzten Pixel, der Rest liegt ausserhalb. (Damit
    labwc dort neben einem Fenster nicht den Pfeil zum Grösseziehen zeigt, ist der unsichtbare Griffrand in dieser
    Sitzung schmal, siehe vm_vorbereiten.) Im maximierten Terminal steht er im Fenster; der Ausschnitt lässt die Ecke
    weg."""
    t.monitor(vm, "mouse_move -4000 4000")
    time.sleep(1)


def wecken(vm: pexpect.spawn) -> None:
    """Sechs kleine Bewegungen des Zeigers in der Ecke: labwc zeichnet dann neue Bilder und gibt allen Fenstern den
    Takt (frame callback). Ohne ihn zeichnete kitty unter TCG manchmal nicht nach, was fish schon ausgegeben hatte (die
    Warnkarte fehlte, bis sich etwas bewegte)."""
    for _ in range(6):
        t.monitor(vm, "mouse_move 1 0")
        time.sleep(0.5)
        t.monitor(vm, "mouse_move -1 0")
        time.sleep(1)


def tippen(vm: pexpect.spawn, text: str, enter: bool = True, pause: float = 0.8) -> None:
    """Wie tippen() im Test, aber langsam: Unter TCG gingen sonst Tastendrücke verloren."""
    vm.send("\x01c")
    vm.expect(r"\(qemu\) ")
    codes = []
    for zeichen in text:
        if zeichen.isalnum() and zeichen.isascii():
            codes.append(f"shift-{zeichen.lower()}" if zeichen.isupper() else zeichen)
        else:
            codes.append(t.TASTEN[zeichen])
    if enter:
        codes.append("ret")
    for code in codes:
        vm.sendline(f"sendkey {code}")
        vm.expect(r"\(qemu\) ")
        time.sleep(pause)
    vm.send("\x01c")


VERGLEICH = Path(tempfile.gettempdir()) / "zenos-fotos-vergleich.ppm"
LEISTE = 40  # Zeilen der Leiste (mit der Uhr) zählen beim Vergleich nicht
MOTIVE = os.environ.get("ZENOS_FOTO_MOTIVE", "").split()


def gewuenscht(motiv: str, thema: str = "") -> bool:
    return not MOTIVE or motiv in MOTIVE or f"{motiv}-{thema}" in MOTIVE


def bildschirm_roh(vm: pexpect.spawn) -> tuple[int, int, bytes]:
    """Bildschirm als PPM (ohne Kompression, leicht zu vergleichen): Breite, Höhe, Pixel (RGB)."""
    VERGLEICH.unlink(missing_ok=True)
    vm.send("\x01c")
    vm.expect(r"\(qemu\) ")
    vm.sendline(f"screendump {VERGLEICH}")
    vm.expect(r"\(qemu\) ")
    vm.send("\x01c")
    # QEMU schreibt die Datei noch, wenn der Monitor schon wieder bereit ist: warten, bis sie vollständig ist
    for _ in range(150):
        daten = VERGLEICH.read_bytes() if VERGLEICH.exists() else b""
        kopf = re.match(rb"P6\s+(\d+)\s+(\d+)\s+\d+\s", daten)
        if kopf:
            breite, hoehe = int(kopf[1]), int(kopf[2])
            if len(daten) >= kopf.end() + breite * hoehe * 3:
                return breite, hoehe, daten[kopf.end():kopf.end() + breite * hoehe * 3]
        time.sleep(0.2)
    raise SystemExit(f"Bildschirmfoto {VERGLEICH} blieb unvollständig")


def unterschied(a: tuple[int, int, bytes], b: tuple[int, int, bytes]) -> tuple[int, int] | None:
    """Breite und Höhe des Rechtecks, in dem sich zwei Bilder unterscheiden (unterhalb der Leiste); None: gleich."""
    breite, hoehe, pa = a
    pb = b[2]
    zeile = breite * 3
    x0, x1, y0, y1 = breite, -1, hoehe, -1
    for y in range(LEISTE, hoehe):
        ra, rb = pa[y * zeile:(y + 1) * zeile], pb[y * zeile:(y + 1) * zeile]
        if ra == rb:
            continue
        i = 0
        while ra[i] == rb[i]:
            i += 1
        j = zeile - 1
        while ra[j] == rb[j]:
            j -= 1
        x0, x1, y0, y1 = min(x0, i // 3), max(x1, j // 3), min(y0, y), max(y1, y)
    return None if y1 < 0 else (x1 - x0 + 1, y1 - y0 + 1)


def ruhig_warten(vm: pexpect.spawn, maximal: int, abstand: int = 4) -> None:
    """Warten, bis sich der Bildschirm zweimal hintereinander nicht ändert (ein blinkender Cursor zählt nicht).
    In Terminals mit grösserem Abstand: kitty zeichnet unter TCG mit Pausen von mehreren Sekunden."""
    beginn = time.monotonic()
    vorher = bildschirm_roh(vm)
    ruhig = 0
    while time.monotonic() - beginn < maximal:
        time.sleep(abstand)
        jetzt = bildschirm_roh(vm)
        feld = unterschied(vorher, jetzt)
        if feld is None or (feld[0] <= 4 and feld[1] <= 48):
            ruhig += 1
            if ruhig >= 2:
                print(f"  ruhig nach {time.monotonic() - beginn:.0f} s", flush=True)
                return
        else:
            ruhig = 0
            print(f"  ändert sich noch ({feld[0]} × {feld[1]} Pixel)", flush=True)
        vorher = jetzt
    print(f"  Bildschirm nach {maximal} s nicht ruhig, Aufnahme trotzdem", flush=True)


def bild(vm: pexpect.spawn, name: str, warten: int = 10, ruhig: int = 90, abstand: int = 4) -> None:
    """Warten, bis der Bildschirm ruhig ist, dann zwei Aufnahmen (siehe oben)."""
    zeiger_weg(vm)
    time.sleep(warten)
    wecken(vm)
    ruhig_warten(vm, ruhig, abstand)
    t.foto(vm, name)
    time.sleep(6)
    t.foto(vm, f"{name}.nachher")


def schwarze_pixel(breite: int, hoehe: int, pixel: bytes) -> int:
    """Rein schwarze Pixel ohne die Ecke unten links (dort steht der Mauszeiger mit schwarzem Rand)."""
    zeile, n = breite * 3, 0
    i = pixel.find(b"\x00\x00\x00")
    while i != -1:
        if i % 3 == 0 and not (i // zeile >= hoehe - 16 and (i % zeile) // 3 < 16):
            n += 1
        i = pixel.find(b"\x00\x00\x00", i + 1)
    return n


def png_schreiben(pfad: Path, breite: int, hoehe: int, pixel: bytes) -> None:
    """PNG (RGB, 8 Bit) ohne weitere Bibliotheken."""
    roh = b"".join(b"\x00" + pixel[y * breite * 3:(y + 1) * breite * 3] for y in range(hoehe))

    def block(art: bytes, daten: bytes) -> bytes:
        return struct.pack(">I", len(daten)) + art + daten + struct.pack(">I", zlib.crc32(art + daten) & 0xFFFFFFFF)
    pfad.write_bytes(b"\x89PNG\r\n\x1a\n" + block(b"IHDR", struct.pack(">IIBBBBB", breite, hoehe, 8, 2, 0, 0, 0))
                     + block(b"IDAT", zlib.compress(roh, 9)) + block(b"IEND", b""))


def bestes_bild(vm: pexpect.spawn, name: str, maximal: int = 45) -> None:
    """Für Flächen mit blinkendem Cursor (siehe oben): alle 0,5 s eine Aufnahme, bis eine ohne schwarzes Pixel dabei
    ist; sonst bleibt die mit den wenigsten. Eine Taste alle 15 s hält die Sperre wach (wirkt auch am Login nicht)."""
    beginn = time.monotonic()
    bestes = None
    naechste_taste = 0.0
    while bestes is None or time.monotonic() - beginn < maximal:
        vergangen = time.monotonic() - beginn
        if vergangen >= naechste_taste:
            t.taste(vm, "shift")
            time.sleep(2)
            naechste_taste = vergangen + 15
        breite, hoehe, pixel = bildschirm_roh(vm)
        n = schwarze_pixel(breite, hoehe, pixel)
        if bestes is None or n < bestes[0]:
            bestes = (n, breite, hoehe, pixel)
        if n == 0:
            break
        time.sleep(0.5)
    n, breite, hoehe, pixel = bestes
    t.BILDER.mkdir(parents=True, exist_ok=True)
    png_schreiben(t.BILDER / f"{name}.png", breite, hoehe, pixel)
    print(f"  Bild  {name}.png ({n} schwarze Pixel, {time.monotonic() - beginn:.0f} s)", flush=True)


def varianten(vm: pexpect.spawn, name: str, thema: str, zeichen: str = "") -> None:
    """Weitere Aufnahmen gegen alte Kacheln (siehe oben): nach einem Zeichen und nach dem Thema hin und zurück."""
    if zeichen:
        tippen(vm, zeichen, enter=False)
        time.sleep(6)
        t.taste(vm, "backspace")
        time.sleep(10)
        ruhig_warten(vm, 60)
        t.foto(vm, f"{name}.getippt")
    anderes = "dunkel" if thema == "hell" else "hell"
    t.befehl(vm, f"/usr/lib/zenos/ipc thema setzen {anderes}")
    time.sleep(20)
    t.befehl(vm, f"/usr/lib/zenos/ipc thema setzen {thema}")
    time.sleep(20)
    zeiger_weg(vm)
    ruhig_warten(vm, 60)
    t.foto(vm, f"{name}.thema")


# Fensterregeln für die Terminals der Fotos (kitty --class setzt unter Wayland die App-Kennung)
FENSTERREGELN = "".join(f'<windowRule identifier="foto-{n}"><action name="SnapToRegion" region="r{n}" /></windowRule>'
                        for n in (1, 2, 3, 4)) + '<windowRule identifier="foto-5"><action name="ToggleMaximize" /></windowRule>'


def vm_vorbereiten(vm: pexpect.spawn) -> None:
    """Nur in dieser VM und nur für diese Sitzung: labwc liest rc.xml über einen Verweis im Laufzeitordner
    (/usr/lib/zenos/sitzung, labwc -C $XDG_RUNTIME_DIR/zenos/labwc). Den ersetzt das Skript durch eine Kopie von
    /etc/xdg/labwc/rc.xml mit Tastenwiederholung erst nach 5 s (Vorgabe 0,6 s; geht unter TCG das Loslassen verloren,
    wiederholt der Client die Taste), flacher Zeigerbeschleunigung (mouse_move landet genau), einem unsichtbaren
    Griffrand von 1 statt 16 px (sonst zeigt labwc in der Ecke neben einem Fenster den Pfeil zum Grösseziehen) und den
    Fensterregeln. labwc liest rc.xml nach SIGHUP neu."""
    t.befehl(vm, "f=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/zenos/labwc/rc.xml; "
                 "test -L $f && cp --remove-destination /etc/xdg/labwc/rc.xml $f; "
                 "grep -q '<repeatDelay>' $f || sed -i "
                 "'s|<keyboard>|<keyboard><repeatRate>25</repeatRate><repeatDelay>5000</repeatDelay>|' $f; "
                 "sed -i 's|<minimumArea>16</minimumArea>|<minimumArea>1</minimumArea>|' $f; "
                 "grep -q '<accelProfile>' $f || sed -i "
                 "'s|<device category=\"default\">|<device category=\"default\"><accelProfile>flat</accelProfile>"
                 "<pointerSpeed>0</pointerSpeed>|' $f; "
                 f"grep -q 'foto-1' $f || sed -i 's|</labwc_config>|<windowRules>{FENSTERREGELN}</windowRules>"
                 "</labwc_config>|' $f; pkill -HUP -x -u $(id -u) labwc")
    time.sleep(5)
    pruefung = t.befehl(vm, "grep -c 'repeatDelay\\|foto-1\\|accelProfile\\|<minimumArea>1<' "
                            "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/zenos/labwc/rc.xml")
    print(f"  rc.xml: {pruefung.strip()}", flush=True)
    if pruefung.strip() != "4":
        raise SystemExit("rc.xml der Sitzung liess sich nicht anpassen")


def erster_start(vm: pexpect.spawn) -> None:
    vm.expect("Nummer: ")
    vm.sendline("7")  # USA (die Tasten des Tests sind US-Codes)
    vm.expect("Testeingabe")
    vm.sendline("")
    vm.expect(r"Neues Passwort f.r deine Daten:")
    vm.sendline(t.DATEN_PASSWORT)
    vm.expect("Noch einmal:")
    vm.sendline(t.DATEN_PASSWORT)
    vm.expect("Bereit\\? Enter")
    vm.sendline("")
    vm.expect(t.WIEDERHERSTELLUNG)
    vm.expect("Aufgeschrieben\\? Enter")
    vm.sendline("")
    vm.expect(r"Notfall-Passwort \(Enter = keins\):")
    vm.sendline("")
    vm.expect(t.DATEN_FRAGE)
    vm.sendline(t.DATEN_PASSWORT)
    if vm.expect([r"(?i)press any key", r"(?i)user name"]) == 0:
        vm.send("\r")
        vm.expect(r"(?i)user name")
    vm.sendline(KONTO)
    while True:
        frage = vm.expect([r"(?i)auxiliary group", r"(?i)shell", r"(?i)password", r"login: "])
        if frage in (0, 1):
            vm.sendline("")
        elif frage == 2:
            vm.sendline(t.KONTO_PASSWORT)
        else:
            break
    vm.sendline(KONTO)
    vm.expect(r"[Pp]assword: ")
    vm.sendline(t.KONTO_PASSWORT)
    vm.expect(r"\$ ")


def mitteilungen_schicken(vm: pexpect.spawn) -> None:
    """Zwei Mitteilungen, die gesammelt warten: die echte Erinnerung an Updates und eine aus dem Browser. Vorher
    verschwindet alles aus der Runde davor: «alleVerwerfen» nimmt nur Zugestelltes, deshalb erst zustellen (die
    Sammelkarte steht dann 10 s). Ohne die alte Nummer ersetzt die Erinnerung nicht ihre Vorgängerin."""
    t.befehl(vm, "/usr/lib/zenos/ipc mitteilungen zustellen; sleep 2; /usr/lib/zenos/ipc mitteilungen alleVerwerfen; "
                 "rm -f $XDG_RUNTIME_DIR/zenos/erinnerung-id")
    time.sleep(12)
    erinnerung = t.befehl(vm, "w=$(mktemp -d) && mkdir -p $w/usr/lib/zenos && cp /usr/lib/zenos/paketstand $w/usr/lib/zenos/ "
                 "&& j=$(( $(date -u -d $(cat $w/usr/lib/zenos/paketstand) +%s) + 15 * 86400 )) "
                 "&& systemd-run --user --quiet --wait --pipe --collect -E ZENOS_ERINNERUNG_TESTWURZEL=$w "
                 "-E ZENOS_ERINNERUNG_JETZT=$j -E XDG_STATE_HOME=$w/zustand /usr/lib/zenos/erinnerung 2>&1; echo rc=$?")
    print(f"  Erinnerung: {erinnerung.strip()[-200:]}", flush=True)
    browser = t.befehl(vm, "busctl --user -- call "
                           "org.freedesktop.Notifications /org/freedesktop/Notifications "
                           "org.freedesktop.Notifications Notify susssasa{sv}i Chromium 0 '' "
                           "'Besprechung in 10 Minuten' 'Kalender im Browser' 0 0 -1 2>&1; echo rc=$?")
    print(f"  Mitteilung aus dem Browser: {browser.strip()[-200:]}", flush=True)


def kitty_starten(vm: pexpect.spawn, nummer: int) -> None:
    """kitty starten und warten, bis fish darin läuft und das Fenster ruhig ist (dann hat es auch den Fokus)."""
    t.befehl(vm, f"systemd-run --user --quiet --collect --unit=foto-kitty-{nummer} kitty --class foto-{nummer}")
    t.warten_bis(vm, f"p=$(systemctl --user show -p MainPID --value foto-kitty-{nummer}.service); "
                     f"pgrep -P $p -x fish >/dev/null && echo fish-laeuft", "fish-laeuft", 300)
    time.sleep(10)
    wecken(vm)
    ruhig_warten(vm, 120, 8)


def warnung_pruefen(vm: pexpect.spawn) -> None:
    """Nach «curl … | sh» und Enter muss fish auf die Rückfrage warten; läuft curl, hat die Warnung versagt."""
    lauf = t.befehl(vm, "pgrep -a -u $(id -u) -x curl || echo kein-curl").strip()
    print(f"  Warnung: {'curl läuft ohne Rückfrage! ' + lauf if 'kein-curl' not in lauf else 'curl läuft nicht'}",
          flush=True)


def kitty_beenden(vm: pexpect.spawn) -> None:
    t.befehl(vm, "systemctl --user stop 'foto-kitty-*.service' 2>/dev/null; true")
    time.sleep(5)


def runde(vm: pexpect.spawn, thema: str) -> None:
    """Die gewünschten Motive in einem Thema (hell oder dunkel)."""
    print(f"\n--- Motive {thema}", flush=True)
    t.befehl(vm, f"/usr/lib/zenos/ipc thema setzen {thema}")
    time.sleep(30)
    mitteilungen_schicken(vm)
    if gewuenscht("heute", thema):
        bild(vm, f"heute-{thema}", 25)

    if gewuenscht("zentrale", thema):
        t.befehl(vm, "/usr/lib/zenos/ipc mitteilungen oeffnen")
        bild(vm, f"zentrale-{thema}")
        varianten(vm, f"zentrale-{thema}", thema)
        t.befehl(vm, "/usr/lib/zenos/ipc mitteilungen schliessen")

    if gewuenscht("sperre", thema):
        t.befehl(vm, "/usr/lib/zenos/sperren")
        t.warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "gesperrt", 120)
        zeiger_weg(vm)
        time.sleep(20)
        ruhig_warten(vm, 30)
        bestes_bild(vm, f"sperre-{thema}")
        t.taste(vm, "shift")
        time.sleep(5)
        tippen(vm, t.KONTO_PASSWORT, pause=0.5)
        t.warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "offen", 120)
        time.sleep(10)

    if gewuenscht("befehlsfeld-apps", thema):
        t.befehl(vm, "/usr/lib/zenos/ipc befehlsfeld apps")
        bild(vm, f"befehlsfeld-apps-{thema}")
        varianten(vm, f"befehlsfeld-apps-{thema}", thema)
        t.befehl(vm, "/usr/lib/zenos/ipc befehlsfeld schliessen")
        time.sleep(5)
    if gewuenscht("befehlsfeld-rechnen", thema):
        t.befehl(vm, "/usr/lib/zenos/ipc befehlsfeld oeffnen")
        time.sleep(5)
        tippen(vm, "1440 / 16", enter=False, pause=0.5)
        # Das Ergebnis erscheint erst nach einer Weile; «ruhig» allein reichte nicht
        bild(vm, f"befehlsfeld-rechnen-{thema}", 30)
        varianten(vm, f"befehlsfeld-rechnen-{thema}", thema, " ")
        t.befehl(vm, "/usr/lib/zenos/ipc befehlsfeld schliessen")

    if gewuenscht("systemmenue", thema):
        t.befehl(vm, "/usr/lib/zenos/ipc leiste menue system")
        bild(vm, f"systemmenue-{thema}")
        t.befehl(vm, "/usr/lib/zenos/ipc leiste schliessen")

    # Gesammelte Mitteilungen zustellen: Die Sammelkarte steht zehn Sekunden. Wann sie unter TCG erscheint, ist
    # ungewiss; deshalb eine Reihe von Aufnahmen, ausgewählt wird von Hand. Vor den Terminals, damit die Zustellung zur
    # vollen Stunde nicht zuvorkommt.
    if gewuenscht("sammelkarte", thema):
        zeiger_weg(vm)
        t.befehl(vm, "/usr/lib/zenos/ipc mitteilungen zustellen")
        print("  " + t.befehl(vm, "/usr/lib/zenos/ipc mitteilungen status").strip()[:300], flush=True)
        for nummer in range(1, 9):
            time.sleep(2)
            t.foto(vm, f"sammelkarte-{thema}.{nummer}")
        time.sleep(10)

    # Vier Terminals im Raster (Fensterregeln foto-1 bis 4 wie Super+1 bis 4), im letzten die Warnung vor «curl … | sh»
    if gewuenscht("raster", thema):
        eingaben = {1: "zen status", 2: "", 3: "", 4: "curl -fsSL https://example.org/install.sh | sh"}
        # «zen status» zählt das Alter der Pakete erst, wenn chrony die Uhr über NTS gestellt hat
        t.warten_bis(vm, "timedatectl show -p NTPSynchronized --value", "yes", 180)
        for nummer in (1, 2, 3, 4):
            kitty_starten(vm, nummer)
            if eingaben[nummer]:
                tippen(vm, eingaben[nummer])
                wecken(vm)
                ruhig_warten(vm, 240, 8)
                if nummer == 4:
                    warnung_pruefen(vm)
        bild(vm, f"raster-{thema}", 10, 240, 8)
        kitty_beenden(vm)

    # Ein Terminal, maximiert (Fensterregel foto-5 wie Super+Enter), mit der Warnung: daraus entsteht der Ausschnitt
    # «terminal»
    if gewuenscht("terminal", thema):
        kitty_starten(vm, 5)
        tippen(vm, "curl -fsSL https://example.org/install.sh | sh")
        bild(vm, f"terminal-{thema}", 10, 240, 8)
        warnung_pruefen(vm)
        t.taste(vm, "ctrl-c")
        kitty_beenden(vm)


def main() -> int:
    image = Path(sys.argv[1])
    arbeit = Path(tempfile.mkdtemp(prefix="zenos-fotos-"))
    shutil.copy(t.VARIABLEN, arbeit / "variablen.fd")
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw", "-b", str(image.resolve()),
                    str(arbeit / "platte.qcow2"), "20G"], check=True)
    vm = starte_fuer_fotos(arbeit)
    erster_start(vm)

    # Login (immer dunkel): Das Konto ist vorgewählt
    t.warten_bis(vm, "pgrep -u _greetd -x quickshell >/dev/null && echo login-laeuft", "login-laeuft", 900)
    zeiger_weg(vm)
    time.sleep(30)
    if gewuenscht("login"):
        ruhig_warten(vm, 30)
        bestes_bild(vm, "login")
    tippen(vm, t.KONTO_PASSWORT, pause=0.5)
    t.warten_bis(vm, t.AKTIV_SHELL, "shell-laeuft", 600)
    t.warten_bis(vm, "/usr/lib/zenos/ipc leiste status 2>&1", "zu", 600)
    time.sleep(40)
    vm_vorbereiten(vm)

    runde(vm, "hell")
    runde(vm, "dunkel")
    if gewuenscht("ausschalten"):
        ausschalten(vm)
    try:
        t.monitor(vm, "quit")
    except Exception:
        pass
    print("\n--- Fotos fertig", flush=True)
    return 0


def ausschalten(vm: pexpect.spawn) -> None:
    """Ausschalten nach langer Sperre: Im Test-Image nach 5 Minuten, der Hinweis kommt eine Minute vorher."""
    print("\n--- Ausschalten nach langer Sperre", flush=True)
    t.befehl(vm, "/usr/lib/zenos/sperren")
    t.warten_bis(vm, "/usr/lib/zenos/ipc sperre status", "gesperrt", 120)
    # Gesperrt ginge der Bildschirm bald aus; nach dem Aufwecken blieben oben links alte (schwarze) Kacheln stehen.
    # Deshalb hält alle 20 s eine Taste ihn wach, und das Thema wechselt einmal hin und zurück (die Sperre zeichnet
    # dann jedes Pixel neu). Tasten an der Sperre zählen nicht als entsperrte Sitzung, die fünf Minuten laufen weiter.
    beginn = time.monotonic()
    naechste_taste = 20.0
    gewechselt = False
    while time.monotonic() - beginn < 245:
        vergangen = time.monotonic() - beginn
        if not gewechselt and vergangen > 40:
            t.befehl(vm, "/usr/lib/zenos/ipc thema setzen hell")
            time.sleep(15)
            t.befehl(vm, "/usr/lib/zenos/ipc thema setzen dunkel")
            gewechselt = True
        if vergangen > naechste_taste:
            t.taste(vm, "shift")
            naechste_taste = vergangen + 20
        time.sleep(2)
    zeiger_weg(vm)
    ruhig_warten(vm, 10)
    bestes_bild(vm, "ausschalten-dunkel", 35)


if __name__ == "__main__":
    sys.exit(main())
