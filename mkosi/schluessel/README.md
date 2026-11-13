# Schlüssel für Updates

Hier liegen nur die **öffentlichen** Schlüssel, mit denen der Argon die Signatur jedes Updates prüft:
`argon-allowed-signers` (Format `allowed_signers` von OpenSSH), eine Zeile pro FIDO2-Schlüssel von Zeno:

```
argon-update namespaces="argon-update" sk-ssh-ed25519@openssh.com AAAA… Argon Update Key A
```

Der Bau schreibt die Datei nach `/usr/lib/zenos/update-signierer`. Er nimmt nur Schlüssel vom Typ `sk-ssh-ed25519`
für `argon-update` an und bricht ohne die Datei ab (`mkosi.finalize`).

Die geheimen Teile liegen nur auf Zenos zwei Security Keys und verlassen sie nie. Signiert wird nur von Zeno, in
seinem Terminal, mit PIN und Berührung. Claude erzeugt, sieht und benutzt die Schlüssel nie. Einrichten, Testen,
Signieren und was bei Verlust gilt: `docs/signieren.md`.
