# Updates signieren (Zeno)

Der Argon ONE UP installiert nur Updates, deren Prüfsummenliste `SHA256SUMS` mit Zenos Schlüssel signiert ist
(Leitplanke: «Ein Gerät installiert nur, was zenOS signiert hat. Signiert wird nie auf einem Rechner, auf dem eine KI
arbeitet.»). So kann auch jemand, der GitHub oder den Mac mit Claude Code übernimmt, nichts aufs Gerät bringen.

Claude erzeugt, sieht und benutzt den Schlüssel nie. Ins Repo kommt nur der **öffentliche** Schlüssel
(`mkosi/schluessel/zenos-updates.asc`); der Bau schreibt ihn nach `/etc/systemd/import-pubring.gpg`.

## Was es braucht

- **Signierrechner:** ein Rechner, der von einem USB-Stick startet, zum Beispiel ein alter PC. Signiert wird in einem
  frisch gestarteten, offiziellen Live-System (Debian Live, von debian.org), ohne Netz. Nie auf dem Mac.
- **Schlüssel-Stick:** ein eigener USB-Stick nur für den Schlüssel, verschlüsselt mit einer Passphrase. Er kommt nie
  in den Mac und nie in den Argon. Dazu eine zweite Kopie, getrennt aufbewahrt.
- **Transfer-Stick:** ein dritter Stick für das, was öffentlich ist: der öffentliche Schlüssel, `SHA256SUMS` und die
  Signatur `SHA256SUMS.gpg`. Nur er wandert zwischen Mac und Signierrechner.
- Später, für 1.0: ein Hardware-Schlüssel mit OpenPGP (YubiKey 5 oder Nitrokey 3) statt des Schlüssel-Sticks. Die
  Schlüssel der Security-Key-Reihe von Yubico für Start und Konto (FIDO2, Bauauftrag 4) können das nicht.

## Einmal: Schlüssel erzeugen

1. Debian Live (amd64, «xfce») von debian.org laden, die Prüfsumme mit der auf debian.org vergleichen und auf einen
   Stick schreiben. Die Variante mit Oberfläche hängt eingesteckte Sticks mit ihrem Namen unter `/media/user/` ein;
   «standard» hat keine Oberfläche und hängt nichts von selbst ein.
2. Den Signierrechner vom Live-Stick starten. Kein Netz anschliessen (kein Kabel, WLAN aus).
3. Den Schlüssel-Stick einstecken (erscheint er nicht von selbst, im Dateimanager einmal anklicken). Auf ihm einen
   Ordner `zenos-schluessel` anlegen.
4. Schlüssel erzeugen (Ed25519, nur zum Signieren, mit Passphrase):
   `gpg --homedir /media/user/<stick>/zenos-schluessel --quick-gen-key "zenOS Updates" ed25519 sign 0`
5. Den Fingerabdruck auf Papier schreiben: `gpg --homedir … --fingerprint`
6. Den öffentlichen Schlüssel auf den Transfer-Stick:
   `gpg --homedir … --armor --export "zenOS Updates" > /media/user/<transfer>/zenos-updates.asc`
7. Die zweite Kopie: den Ordner `zenos-schluessel` auf den zweiten Schlüssel-Stick kopieren.
8. Herunterfahren, alle Sticks abziehen.

Auf dem Mac legt Claude `zenos-updates.asc` vom Transfer-Stick nach `mkosi/schluessel/` und zeigt den Fingerabdruck;
er muss mit dem auf dem Papier übereinstimmen.

## Für jedes Update: signieren

1. Claude baut den Stand und bereitet ihn vor (`mkosi/veroeffentlichen.sh`). Am Ende steht die Prüfsumme von
   `SHA256SUMS`. `SHA256SUMS` kommt auf den Transfer-Stick.
2. Den Signierrechner vom Live-Stick starten, kein Netz. Schlüssel-Stick und Transfer-Stick einstecken.
3. Prüfen, dass es die richtige Datei ist: `sha256sum /media/user/<transfer>/SHA256SUMS` muss die Prüfsumme zeigen,
   die Claude genannt hat.
4. Signieren:
   `gpg --homedir /media/user/<stick>/zenos-schluessel --detach-sign --output /media/user/<transfer>/SHA256SUMS.gpg /media/user/<transfer>/SHA256SUMS`
5. Herunterfahren, Sticks abziehen. Der Transfer-Stick geht zurück an den Mac.

Claude prüft die Signatur mit dem öffentlichen Schlüssel und lädt den Stand nach Zenos Ja auf GitHub hoch, als Release
`zenos-<version>` (nie mit einem Tag `v…`, die gehören zu 0.1). Auf dem Argon holt `zen update` ihn ab.

## Wenn der Schlüssel verloren geht

Mit der zweiten Kopie weiter signieren. Sind beide verloren, nimmt der Argon keine Updates mehr an: Dann braucht es ein
neues Image mit einem neuen Schlüssel, und die SSD wird einmal neu geschrieben (die Daten vorher sichern).
