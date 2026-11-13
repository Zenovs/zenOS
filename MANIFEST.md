# zenOS Manifest

Die Reihenfolge ist die Rangordnung. Bei einem Konflikt gewinnt immer der höhere Grundsatz.

## 0. zenOS hat genau einen Benutzer.

zenOS ist für mich gebaut, enthält aber nichts von mir. Im Repo und im Image stehen keine Namen, Konten, Modi, Orte oder geheimen Schlüssel. Einzige Ausnahme sind die öffentlichen Prüfschlüssel von zenOS, mit denen Geräte Updates prüfen. Persönliches entsteht lokal beim ersten Start und bleibt dort.

Ein Gerät kann als öffentlicher Bildschirm eingerichtet sein. Dann gibt es dort zusätzlich ein technisches Anzeige-Konto. Es ist kein zweiter Benutzer: Es hat keine Rechte, kein Passwort und keine persönlichen Daten und zeigt nur eine App. Einrichten und entfernen kann es nur root.

## 1. Sicherheit ist Standard.

Sicherheit geht vor Design und Bequemlichkeit. Was nicht gebraucht wird, ist nicht da. Das System ist unveränderlich, signiert und startet nur, was zenOS gebaut hat. Die Bausteine dafür werden nicht selbst erfunden, sondern von Debian, systemd, Raspberry Pi und erprobten Werkzeugen übernommen.

## 2. Ruhe ist der Normalzustand.

Nichts blinkt, nichts springt auf, nichts verlangt Aufmerksamkeit, wenn es nicht wirklich wichtig ist.

## 3. Eine Sache steht im Fokus.

Das aktive Fenster ist im Zentrum. Alles andere tritt zurück und erscheint erst, wenn es gebraucht wird.

## 4. Alles läuft über eine Stelle.

Das Befehlsfeld ist die Zentrale für Apps, Projekte, Werkzeuge, Modi, Zustände und Einstellungen. Die Tastatur hat Vorrang.

## 5. Das Design lebt an einem Ort.

Farben, Schrift, Radien, Abstände und Bewegung stehen als Design-Tokens in einer Datei. Ändert sich dort etwas, zieht das ganze System mit.

## 6. Der Pi ist die Messlatte.

Was auf dem Raspberry Pi 5 nicht flüssig läuft, fliegt raus: flüssige 60 fps, kein Weichzeichnen.

## Leitplanken

Diese Regeln kann kein Modus, kein Zustand und keine Einstellung aushebeln:

- Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen.
- Der Sperrbildschirm zeigt nie Inhalte.
- Die automatische Sperre lässt sich nicht abschalten.
- **Ausnahme Anzeigegerät:** Ist ein Gerät als öffentlicher Bildschirm eingerichtet, läuft dort automatisch nur das Anzeige-Konto: ohne Rechte, ohne Passwort, ohne persönliche Daten, ohne Sperre. Persönliche Konten sperren dort wie überall und melden sich nie automatisch an.
- Es liegen keine Geheimnisse im Repo, und es gibt keine Telemetrie.
- Terminal-Ausgaben und Bildschirminhalte verlassen den Rechner nie automatisch.
- Das Release-Image hat keinen Fernzugang, keine Entwicklerwerkzeuge und keine KI.
- Kein Dienst nimmt Verbindungen von aussen an.
- Auf dem Gerät läuft nur, was im Image von zenOS ist.
- Ein Gerät installiert nur, was zenOS signiert hat. Der geheime Signaturschlüssel existiert nur auf Zenos Hardware-Schlüsseln und verlässt sie nie. Signiert wird nur von Zeno selbst, in seinem Terminal, mit PIN und Berührung des Schlüssels; eine KI löst nie eine Signatur aus.
  Diese zwei Schlüssel gelten (OpenSSH, `ed25519-sk`, `mkosi/schluessel/argon-allowed-signers`): Key A `SHA256:wOv2IuueQWW6oiyF8QkkhZ3OIJIC1T1V2pYZWM9lemA`, Key B `SHA256:BUHu5i7N/37kr64gkxbfKLoOj6uQYAIuKQ6vFgsCWJg`. Zeigt der Bau andere, ist die Datei ausgetauscht worden.
- Jede Leitplanke hat einen Test, der versucht, sie zu brechen.

## Was zenOS bewusst nicht ist

- Kein eigener Kernel, kein eigener Browser, kein eigener Dateimanager, kein eigener Netzwerk-Stack. Der Kernel kommt
  von Raspberry Pi; zenOS baut ihn höchstens mit eigener Konfiguration. Das WLAN-Menü oben rechts bedient nur den
  NetworkManager von Debian.
- Kein Hypervisor. Wer Bereiche räumlich trennen will, nimmt Qubes OS.
- Keine Geschmacksoptionen für andere Menschen.
- Kein Gemeinschaftsprojekt: keine Issues, keine Pull Requests.

Selbst gebaut wird, was man sieht und täglich anfasst. Der Rest kommt von Debian und Raspberry Pi.
