#!/usr/bin/env python3
"""qemu-test.py – startet das Installations-ISO von zenOS in QEMU und hält fest, was man sieht.

    test/x86/qemu-test.py ISO AUSGABE [--sekunden N] [--dvd]

UEFI mit Secure Boot und den Schlüsseln von Microsoft (OVMF_CODE_4M.secboot.fd, OVMF_VARS_4M.ms.fd aus dem Paket
ovmf), mit KVM, 4 GiB Speicher und einer leeren Platte. Das ISO steckt als USB-Stick (Standard) oder als DVD
(--dvd). Alle 5 s ein Bildschirmfoto nach AUSGABE/bild-SSS.png, die serielle Ausgabe nach AUSGABE/seriell.log.

Geprüft wird nur, was ohne Zutun passieren muss: Mit Secure Boot startet das ISO bis in den Installer. Erkannt am
Bildschirm: die Seitenleiste von Calamares (Farbe «flaeche», mindestens 5 %) und der Knopf «Weiter» (Akzentfarbe).
Das Startbild allein zeigt nur «grund» und ein kleines Zeichen in der Akzentfarbe.
Exit 0, wenn der Installer erscheint, 1 sonst, 2 bei falschem Aufruf. Für GitHub Actions (.github/workflows/x86.yml)
und lokal auf amd64-Linux mit KVM.
"""

import argparse
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import zlib

OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
TOKENS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "shell", "theme", "tokens.json")


def farben():
    """Akzent und Fläche (dunkel) aus shell/theme/tokens.json als (r, g, b)."""
    with open(TOKENS, encoding="utf-8") as datei:
        f = json.load(datei)["farben"]

    def rgb(wert):
        return tuple(int(wert[i:i + 2], 16) for i in (1, 3, 5))

    return rgb(f["akzente"][f["standardAkzent"]]["dunkel"]), rgb(f["dunkel"]["flaeche"])


class Qmp:
    """Minimale QMP-Verbindung (JSON je Zeile)."""

    def __init__(self, pfad):
        for _ in range(100):
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(pfad)
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("QMP nicht erreichbar")
        self.datei = self.sock.makefile("rw", encoding="utf-8")
        self._lesen()
        self.befehl("qmp_capabilities")

    def _lesen(self):
        while True:
            zeile = self.datei.readline()
            if not zeile:
                raise RuntimeError("QMP geschlossen")
            antwort = json.loads(zeile)
            if "event" not in antwort:
                return antwort

    def befehl(self, name, **argumente):
        self.datei.write(json.dumps({"execute": name, "arguments": argumente}) + "\n")
        self.datei.flush()
        antwort = self._lesen()
        if "error" in antwort:
            raise RuntimeError("QMP %s: %s" % (name, antwort["error"]))
        return antwort.get("return")


def ppm_lesen(pfad):
    """PPM (P6, 8 bit) → (breite, hoehe, bytes)."""
    with open(pfad, "rb") as datei:
        daten = datei.read()
    teile = []
    pos = 0
    while len(teile) < 4:
        while daten[pos:pos + 1].isspace():
            pos += 1
        if daten[pos:pos + 1] == b"#":
            pos = daten.index(b"\n", pos) + 1
            continue
        ende = pos
        while not daten[ende:ende + 1].isspace():
            ende += 1
        teile.append(daten[pos:ende])
        pos = ende
    if teile[0] != b"P6" or teile[3] != b"255":
        raise ValueError("kein PPM P6")
    return int(teile[1]), int(teile[2]), daten[pos + 1:]


def png_schreiben(pfad, breite, hoehe, pixel):
    """RGB-Bytes als PNG (ohne Zusatzpakete)."""
    zeilen = b"".join(b"\x00" + pixel[y * breite * 3:(y + 1) * breite * 3] for y in range(hoehe))

    def block(art, inhalt):
        return struct.pack(">I", len(inhalt)) + art + inhalt + struct.pack(">I", zlib.crc32(art + inhalt) & 0xFFFFFFFF)

    with open(pfad, "wb") as datei:
        datei.write(b"\x89PNG\r\n\x1a\n")
        datei.write(block(b"IHDR", struct.pack(">IIBBBBB", breite, hoehe, 8, 2, 0, 0, 0)))
        datei.write(block(b"IDAT", zlib.compress(zeilen, 6)))
        datei.write(block(b"IEND", b""))


def anteil_farbe(pixel, farbe, toleranz=10):
    """Anteil der Pixel nahe FARBE (jede Stufe höchstens TOLERANZ daneben), jedes 7. Pixel gezählt."""
    treffer = gezaehlt = 0
    r, g, b = farbe
    for i in range(0, len(pixel) - 2, 21):
        gezaehlt += 1
        if abs(pixel[i] - r) <= toleranz and abs(pixel[i + 1] - g) <= toleranz and abs(pixel[i + 2] - b) <= toleranz:
            treffer += 1
    return treffer / max(gezaehlt, 1)


def main():
    parser = argparse.ArgumentParser(description="zenOS-ISO in QEMU starten (UEFI, Secure Boot)")
    parser.add_argument("iso")
    parser.add_argument("ausgabe")
    parser.add_argument("--sekunden", type=int, default=240)
    parser.add_argument("--dvd", action="store_true", help="als DVD statt als USB-Stick")
    args = parser.parse_args()

    for pfad in (args.iso, OVMF_CODE, OVMF_VARS):
        if not os.path.isfile(pfad):
            print("qemu-test: %s fehlt" % pfad, file=sys.stderr)
            return 2
    os.makedirs(args.ausgabe, exist_ok=True)
    akzent, flaeche = farben()
    arbeit = tempfile.mkdtemp(prefix="zenos-qemu-")
    vars_kopie = os.path.join(arbeit, "vars.fd")
    shutil.copyfile(OVMF_VARS, vars_kopie)
    platte = os.path.join(arbeit, "platte.qcow2")
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", platte, "40G"], check=True)
    qmp_pfad = os.path.join(arbeit, "qmp.sock")

    if args.dvd:
        medium = ["-drive", "if=none,id=iso,media=cdrom,readonly=on,format=raw,file=" + args.iso,
                  "-device", "ide-cd,drive=iso,bootindex=1"]
    else:
        medium = ["-device", "qemu-xhci,id=xhci",
                  "-drive", "if=none,id=iso,readonly=on,format=raw,file=" + args.iso,
                  "-device", "usb-storage,bus=xhci.0,drive=iso,bootindex=1"]
    kvm = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.R_OK | os.W_OK) else ["-cpu", "max"]
    befehl = ["qemu-system-x86_64", "-machine", "q35,smm=on", *kvm, "-smp", "2", "-m", "4096",
              "-global", "driver=cfi.pflash01,property=secure,value=on",
              "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=" + OVMF_CODE,
              "-drive", "if=pflash,format=raw,unit=1,file=" + vars_kopie,
              *medium,
              "-drive", "if=none,id=platte,format=qcow2,file=" + platte,
              "-device", "virtio-blk-pci,drive=platte,bootindex=2",
              "-vga", "std", "-display", "none",
              "-serial", "file:" + os.path.join(args.ausgabe, "seriell.log"),
              "-qmp", "unix:%s,server=on,wait=off" % qmp_pfad]
    print("qemu-test:", " ".join(befehl), flush=True)
    qemu = subprocess.Popen(befehl)
    erschienen = None
    try:
        qmp = Qmp(qmp_pfad)
        start = time.monotonic()
        while time.monotonic() - start < args.sekunden and qemu.poll() is None:
            time.sleep(5)
            sekunde = int(time.monotonic() - start)
            ppm = os.path.join(arbeit, "bild.ppm")
            try:
                qmp.befehl("screendump", filename=ppm)
                breite, hoehe, pixel = ppm_lesen(ppm)
            except (RuntimeError, ValueError, OSError) as fehler:
                print("qemu-test: %3d s: kein Bild (%s)" % (sekunde, fehler), flush=True)
                continue
            png_schreiben(os.path.join(args.ausgabe, "bild-%03d.png" % sekunde), breite, hoehe, pixel)
            anteil_akzent = anteil_farbe(pixel, akzent)
            anteil_flaeche = anteil_farbe(pixel, flaeche, toleranz=3)
            print("qemu-test: %3d s: %dx%d, Akzent %.2f %%, Fläche %.1f %%"
                  % (sekunde, breite, hoehe, anteil_akzent * 100, anteil_flaeche * 100), flush=True)
            if anteil_akzent > 0.0005 and anteil_flaeche > 0.05 and erschienen is None:
                erschienen = sekunde
            if erschienen is not None and sekunde - erschienen >= 20:
                break
    finally:
        if qemu.poll() is None:
            qemu.terminate()
            try:
                qemu.wait(timeout=20)
            except subprocess.TimeoutExpired:
                qemu.kill()
        shutil.rmtree(arbeit, ignore_errors=True)
    if erschienen is None:
        print("qemu-test: Der Installer ist nicht erschienen (Bildschirmfotos und seriell.log in %s)" % args.ausgabe)
        return 1
    print("qemu-test: Installer nach etwa %d s zu sehen" % erschienen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
