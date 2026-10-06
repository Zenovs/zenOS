#!/usr/bin/env python3
"""Klient für den Socket von zenos-gesten, nur für test/container/gesten-e2e.sh (läuft als tester).

  klient.py lesen DATEI [SOCKET]     verbinden und jede Zeile an DATEI anhängen, bis der Dienst trennt
  klient.py schreiben [SOCKET]       verbinden und etwas schicken: «EPIPE» (richtig, der Dienst liest nie),
                                     sonst «gesendet»
  klient.py viele N [SOCKET]         N Klienten nacheinander; dann je Klient «offen» oder «zu» (vom Dienst getrennt)
  klient.py flut SEKUNDEN [SOCKET]   so lange immer neue Klienten, je 8 zugleich offen (wie ein Angreifer, der die
                                     Oberfläche verdrängen will); am Ende die Zahl der Verbindungen
"""

import os
import socket
import sys
import time

SOCKET_PATH = "/run/zenos-gesten/gesten.sock"


def connect(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(path)
    return client


def read_lines(target, path):
    client = connect(path)
    with open(target, "a", encoding="utf-8") as handle:
        handle.write("verbunden\n")
        handle.flush()
        buffer = b""
        while True:
            data = client.recv(64)
            if not data:
                handle.write("getrennt\n")
                return 0
            buffer += data
            while b"\n" in buffer:
                line, _, buffer = buffer.partition(b"\n")
                handle.write(line.decode("ascii", "replace") + "\n")
                handle.flush()


def try_write(path):
    client = connect(path)
    time.sleep(0.2)
    try:
        client.send(b"oben\n", socket.MSG_NOSIGNAL)
        client.send(b"oben\n", socket.MSG_NOSIGNAL)
    except BrokenPipeError:
        print("EPIPE")
        return 0
    print("gesendet")
    return 1


def many(count, path):
    clients = []
    for _ in range(count):
        clients.append(connect(path))
        time.sleep(0.05)
    time.sleep(0.5)
    states = []
    for client in clients:
        try:
            data = client.recv(1, socket.MSG_DONTWAIT | socket.MSG_PEEK)
            states.append("zu" if data == b"" else "offen")
        except BlockingIOError:
            states.append("offen")
        except OSError:
            states.append("zu")
    print(" ".join(states))
    return 0


def flood(seconds, path):
    clients = []
    count = 0
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            clients.append(connect(path))
            count += 1
        except OSError:
            time.sleep(0.01)
        while len(clients) > 8:
            clients.pop(0).close()
        time.sleep(0.01)
    print(count)
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "lesen" and len(argv) >= 3:
        return read_lines(argv[2], argv[3] if len(argv) > 3 else SOCKET_PATH)
    if mode == "schreiben":
        return try_write(argv[2] if len(argv) > 2 else SOCKET_PATH)
    if mode == "viele" and len(argv) >= 3:
        return many(int(argv[2]), argv[3] if len(argv) > 3 else SOCKET_PATH)
    if mode == "flut" and len(argv) >= 3:
        return flood(float(argv[2]), argv[3] if len(argv) > 3 else SOCKET_PATH)
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    os.umask(0o077)
    sys.exit(main(sys.argv))
