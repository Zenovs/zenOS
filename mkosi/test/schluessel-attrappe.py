#!/usr/bin/env python3
"""Attrappe der Befehle fido2-token, fido2-cred, fido2-assert und pamu2fcfg für mkosi/test/schluessel-einheiten.sh.

Bildet nur das Ein- und Ausgabeformat der Werkzeuge nach, damit die Skripte von zenOS ohne Gerät getestet werden
können. Welche Testschlüssel «stecken», steht in $SCHLUESSEL_ZUSTAND/steckt (Namen, durch Leerzeichen getrennt). Jeder
Name hat einen Zufallswert in $SCHLUESSEL_ZUSTAND/wert-<name>; das «hmac-secret» ist ein HMAC-SHA-256 mit diesem Wert
und dem Credential. Jede Anfrage mit Berührung wird in $SCHLUESSEL_ZUSTAND/beruehrt mitgezählt.
"""

import base64
import hashlib
import hmac
import os
import secrets
import sys
from pathlib import Path

ZUSTAND = Path(os.environ["SCHLUESSEL_ZUSTAND"])


def stecken() -> list[str]:
    datei = ZUSTAND / "steckt"
    return datei.read_text().split() if datei.exists() else []


def wert(name: str) -> bytes:
    datei = ZUSTAND / f"wert-{name}"
    if not datei.exists():
        datei.write_text(secrets.token_hex(32))
    return bytes.fromhex(datei.read_text().strip())


def beruehrt() -> None:
    with open(ZUSTAND / "beruehrt", "a") as f:
        f.write("x\n")


def geraet_name(pfad: str) -> str:
    name = pfad.removeprefix("/dev/hidraw-")
    if name not in stecken():
        print(f"{Path(sys.argv[0]).name}: {pfad}: kein solches Gerät", file=sys.stderr)
        sys.exit(1)
    return name


def zeilen() -> list[str]:
    return sys.stdin.read().split("\n")


def b64(daten: bytes) -> str:
    return base64.b64encode(daten).decode()


def token() -> None:
    if sys.argv[1:] != ["-L"]:
        sys.exit(2)
    for name in stecken():
        print(f"/dev/hidraw-{name}: vendor=0x0000, product=0x0000 (Testschlüssel {name})")


def cred() -> None:
    argumente = sys.argv[1:]
    if "-M" not in argumente:
        sys.exit(2)
    name = geraet_name(argumente[-1])
    eingabe = zeilen()
    beruehrt()
    credential = b64(f"cred:{name}:{secrets.token_hex(8)}".encode())
    for zeile in (eingabe[0], eingabe[1], "packed", b64(b"authdata"), credential, b64(b"sig")):
        print(zeile)


def assertion() -> None:
    argumente = sys.argv[1:]
    if "-G" not in argumente:
        sys.exit(2)
    name = geraet_name(argumente[-1])
    mit_hmac = "-h" in argumente
    still = "up=false" in argumente
    eingabe = zeilen()
    credential = base64.b64decode(eingabe[2]).decode()
    if not credential.startswith(f"cred:{name}:"):
        print("fido2-assert: fido_dev_get_assert: FIDO_ERR_NO_CREDENTIALS", file=sys.stderr)
        sys.exit(1)
    if mit_hmac and still:
        sys.exit(1)
    if not still:
        beruehrt()
    ausgabe = [eingabe[0], eingabe[1], b64(b"authdata"), b64(b"sig")]
    if mit_hmac:
        salz = base64.b64decode(eingabe[3])
        if len(salz) != 32:
            sys.exit(1)
        ausgabe.append(b64(hmac.new(wert(name) + credential.encode(), salz, hashlib.sha256).digest()))
    print("\n".join(ausgabe))


def u2fcfg() -> None:
    gesteckt = stecken()
    if not gesteckt or "-n" not in sys.argv[1:]:
        sys.exit(1)
    beruehrt()
    print(f":KH-{gesteckt[0]}-{secrets.token_hex(4)},PUBKEY{gesteckt[0]},es256,+presence")


{"fido2-token": token, "fido2-cred": cred, "fido2-assert": assertion, "pamu2fcfg": u2fcfg}[Path(sys.argv[0]).name]()
