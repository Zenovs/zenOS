# zenOS Manifest

Die Reihenfolge ist die Rangordnung. Bei einem Konflikt gewinnt immer der höhere Grundsatz.

## 0. zenOS hat genau einen Benutzer.

zenOS ist für mich gebaut, enthält aber nichts von mir. Im Repo und im Image stehen keine Namen, Konten, Modi, Orte oder Schlüssel. Persönliches entsteht lokal beim ersten Start und bleibt dort.

## 1. Sicherheit ist Standard.

Sicherheit geht vor Design und Bequemlichkeit. Sie wird nicht selbst erfunden, sondern von Ubuntu und erprobten Werkzeugen übernommen.

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
- Es liegen keine Geheimnisse im Repo, und es gibt keine Telemetrie.
- Terminal-Ausgaben und Bildschirminhalte verlassen den Rechner nie automatisch.

## Was zenOS bewusst nicht ist

- Kein eigener Kernel, kein eigener Browser, kein eigener Dateimanager, kein eigener Netzwerk-Stack. Das WLAN-Menü
  oben rechts bedient nur den NetworkManager von Ubuntu.
- Keine Geschmacksoptionen für andere Menschen.
- Kein Gemeinschaftsprojekt: keine Issues, keine Pull Requests.

Selbst gebaut wird, was man sieht und täglich anfasst. Der Rest kommt von Ubuntu.
