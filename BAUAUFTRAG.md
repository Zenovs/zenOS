# Bauauftrag: zenOS 1.0, Vorschau 1

Erteilt von Zeno am 08.11.2026 («ja, lege los, auf diesem Mac»; die Entscheide in `docs/neubau.md` sind für ihn so in
Ordnung). Der Bauauftrag für 0.1 ist abgeschlossen; er steht im Branch `dev`.

## Ziel

Ein Image, das auf dem Argon ONE UP (Compute Module 5 Lite) von einem USB-Stick startet, nach `docs/neubau.md`,
Abschnitt 6, «Vorschau 1». Zeno schreibt es selbst auf den Stick und testet es am Gerät. Die SSD behält zenOS 0.1, bis
Vorschau 2 Updates kann.

Auf dem Gerät ist nur, was gebraucht wird. Keine überflüssige Software, und als Browser der sicherste, der sich auf
diesem Gerät pflegen lässt (Chromium aus Debian, gehärtet über Richtlinien).

## Rahmen

- Gebaut wird auf Zenos Mac: Docker über Colima, mkosi in einem Debian-Container, Tests in QEMU. Branch `neubau`.
- `MANIFEST.md` und `CLAUDE.md` gelten. Bei einem Widerspruch gewinnt das Manifest.
- Arbeite selbstständig durch. Frag Zeno nur bei den Punkten unter «Nur nach Rückfrage» oder bei einem echten Blocker.
- Halte den Fortschritt in `docs/baufortschritt.md` (Abschnitt «zenOS 1.0») fest. Endet eine Sitzung, muss eine neue
  dort nahtlos weitermachen können.
- Committe thematisch auf `neubau` und pushe danach.

## Freigegeben

- Die Colima-VM auf mehr Kerne und RAM stellen und dafür neu starten.
- Container und Images bauen, Pakete im Container installieren, Caches unter `mkosi/` anlegen (nicht im Repo).
- Pushen auf `neubau`.

## Nur nach Rückfrage bei Zeno

- Alles, was auf einen physischen Datenträger, das EEPROM oder das OTP schreibt. Das macht Zeno selbst.
- Software auf dem Mac ausserhalb von Docker installieren.
- Tags, Releases, GitHub-Einstellungen und Secrets.
- Änderungen am Branch `dev`.
- Signaturschlüssel: Claude erzeugt, sieht und benutzt nie welche.

## Umfang Vorschau 1

- Debian 13 arm64 als Image mit mkosi, aus einem eingefrorenen Paketstand von `snapshot.debian.org`.
- Kernel und Firmware von Raspberry Pi, Bootpartition für das CM5 (mit dem USB-Overlay für Tastatur und Touchpad).
- `/` schreibgeschützt mit dm-verity. `/var` und `/home` auf LUKS2 mit Argon2id, beim ersten Start eingerichtet. Platz
  für die B-Hälfte (Vorschau 2).
- Kein SSH, kein sudo und su, kein apt, keine Compiler. nftables verwirft Eingehendes, chrony mit NTS, resolved ohne
  mDNS und LLMNR, NetworkManager.
- Kernel-Härtung über sysctl und Befehlszeile.
- Chromium mit Richtlinien, udev-Regeln für Trezor und Ledger.
- Oberfläche: Login, Leiste, Apps starten, Sperre, WLAN.
- Angriffstests in QEMU.

## Nicht im Umfang

Updates (Vorschau 2), signierter Start und eigener Kernel (1.0), alle übrigen Funktionen von 0.1.

## Fertig heisst

- Das Image baut, die Angriffstests in QEMU sind grün, gitleaks ist sauber.
- `docs/baufortschritt.md` ist nachgeführt, `mkosi/README.md` erklärt Bau und Schreiben auf den Stick.
- Zeno bekommt einen kurzen Schlussbericht und den ersten Befehl, um das Image auf den Stick zu schreiben.
