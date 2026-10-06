#!/usr/bin/env python3
"""greetd_attrappe.py SOCKET PROTOKOLL – Attrappe von greetd für test/container/login-e2e.sh (nur im Testcontainer).

Spricht das IPC-Protokoll von greetd (je Nachricht 4 Byte Länge in Maschinenreihenfolge, dann JSON) über einen
Unix-Socket. Quickshell (Greetd) verbindet sich über GREETD_SOCK. Jede Anfrage steht als eine JSON-Zeile im
Protokoll, so prüft der Test, was das Formular des Logins weitergibt (auch die Antwort auf die Passwortfrage: Das
Testkonto «tester» hat das Passwort «tester»; das ist kein Geheimnis). Ein echtes PAM gibt es hier nicht.

  create_session            → Passwortfrage (secret)
  post_auth_message_response → success bei «tester», sonst auth_error wie pam_authenticate
  start_session             → success (Quickshell beendet sich dann wie nach einer echten Anmeldung)
  cancel_session            → success
"""

import json
import os
import socketserver
import struct
import sys

PASSWORT = "tester"


def antwort_auf(anfrage):
    art = anfrage.get("type")
    if art == "create_session":
        return {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "}
    if art == "post_auth_message_response":
        if anfrage.get("response") == PASSWORT:
            return {"type": "success"}
        return {"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"}
    if art in ("start_session", "cancel_session"):
        return {"type": "success"}
    return {"type": "error", "error_type": "error", "description": "unbekannte Anfrage"}


class Verbindung(socketserver.StreamRequestHandler):
    def handle(self):
        while True:
            kopf = self.rfile.read(4)
            if len(kopf) < 4:
                return
            (laenge,) = struct.unpack("=I", kopf)
            daten = self.rfile.read(laenge)
            if len(daten) < laenge:
                return
            try:
                anfrage = json.loads(daten.decode("utf-8"))
            except ValueError:
                anfrage = {"type": "kaputt"}
            with open(self.server.protokoll, "a", encoding="utf-8") as f:
                f.write(json.dumps(anfrage, ensure_ascii=False) + "\n")
            antwort = json.dumps(antwort_auf(anfrage)).encode("utf-8")
            self.wfile.write(struct.pack("=I", len(antwort)) + antwort)
            self.wfile.flush()


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    pfad, protokoll = sys.argv[1], sys.argv[2]
    if os.path.exists(pfad):
        os.unlink(pfad)
    server = Server(pfad, Verbindung)
    server.protokoll = protokoll
    os.chmod(pfad, 0o600)
    try:
        server.serve_forever()
    finally:
        os.unlink(pfad)
    return 0


if __name__ == "__main__":
    sys.exit(main())
